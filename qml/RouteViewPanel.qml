import QtQuick 2.7
import QtQuick.Controls 2.15
import QtPositioning 5.5

// Muestra la ruta completa en el mapa: rota al bearing inicio→fin y encuadra.
// El inicio de ruta queda en mapRef.height/2 (posición GPS en modo N).
// Propiedades obligatorias: mapRef, shape ([lon,lat] pairs), navBarHeight
// Para bandera de destino: navActive, navDests, screenPosOf
Item {
    id: rvp
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    visible: false
    anchors.fill: parent
    z: 25

    property var  mapRef:       null
    property var  shape:        []      // [[lon,lat], ...]
    property real navBarHeight: 0

    // Bandera de destino
    property bool navActive:    false
    property var  navDests:     []
    property var  screenPosOf:  null    // function(lat, lon) → {x, y}

    signal closed()

    // Debug
    property int  _dbgPts:  0
    property real _dbgMinLat: 0; property real _dbgMaxLat: 0
    property real _dbgMinLon: 0; property real _dbgMaxLon: 0
    property real _dbgCLat: 0;  property real _dbgCLon: 0
    property real _dbgDLat: 0;  property real _dbgDLon: 0
    property real _dbgZH:   0;  property real _dbgZW:   0
    property real _dbgZoom: 0
    property real _dbgVH:   0;  property real _dbgVW:   0
    property real _dbgSpanV: 0; property real _dbgSpanH: 0
    property real _dbgMpp:   0; property real _dbgMppT:  0
    property real _dbgSavedZ: 0

    property bool hideCloseBtn:      false  // ocultado cuando RouteSelectPanel es el dueño
    property real bottomPanelHeight: 0     // altura del panel inferior que cubre el mapa

    // Estado del mapa guardado al abrir
    property bool   _stateSaved:  false
    property real   _savedZoom:     0
    property real   _savedMpp:      0   // mpp en el momento del save; usado en todas las llamadas
    property var    _savedCenter:   null
    property real   _savedBearing:  0
    property real   _savedPitch:    0
    property bool   _savedFollow:   false
    property string _savedBearMode: "heading"
    property bool   _savedAutoZoom: true

    function open() {
        if (!mapRef || shape.length < 2) return

        // Guardar estado sólo en la primera llamada; las siguientes (cambio de ruta
        // seleccionada) reutilizan el estado guardado para poder restaurar correctamente.
        // _savedMpp se guarda junto al zoom: ambos deben ser consistentes para que
        // las llamadas sucesivas calculen el zoom correcto.
        if (!_stateSaved) {
            _savedZoom     = mapRef.zoomLevel
            _savedMpp      = mapRef.metersPerPixel
            _savedCenter   = mapRef.center
            _savedBearing  = mapRef.bearing
            _savedPitch    = mapRef.pitch
            _savedFollow   = mapRef.followMode
            _savedBearMode = appSettings.bearingMode
            _savedAutoZoom = appSettings.autoZoom
            _stateSaved    = true
        }
        // Usar siempre el mpp del zoom guardado (no el mpp actual, que puede haber
        // cambiado si open() ya se llamó antes con otra ruta seleccionada).
        var currentMpp = _savedMpp

        // Bearing inicio→fin (ruta de abajo a arriba en pantalla)
        var s0 = shape[0], sN = shape[shape.length - 1]
        var dlo = (sN[0] - s0[0]) * Math.PI / 180
        var la1 = s0[1] * Math.PI / 180, la2 = sN[1] * Math.PI / 180
        var bearRad = Math.atan2(
            Math.sin(dlo) * Math.cos(la2),
            Math.cos(la1) * Math.sin(la2) - Math.sin(la1) * Math.cos(la2) * Math.cos(dlo))
        var bearDeg = (bearRad * 180 / Math.PI + 360) % 360
        var sinB = Math.sin(bearRad), cosB = Math.cos(bearRad)

        // Bbox → centro provisional
        var minLat = 1e9, maxLat = -1e9, minLon = 1e9, maxLon = -1e9
        for (var i = 0; i < shape.length; i++) {
            var lo = shape[i][0], la = shape[i][1]
            if (la < minLat) minLat = la;  if (la > maxLat) maxLat = la
            if (lo < minLon) minLon = lo;  if (lo > maxLon) maxLon = lo
        }
        var cLat   = (minLat + maxLat) / 2
        var cLon   = (minLon + maxLon) / 2
        var cosLat = Math.cos(cLat * Math.PI / 180)
        var M      = 111319

        // Proyectar todos los puntos sobre los ejes de pantalla rotados
        var minV = 1e15, maxV = -1e15, minH = 1e15, maxH = -1e15
        for (var j = 0; j < shape.length; j++) {
            var dx = (shape[j][0] - cLon) * M * cosLat
            var dy = (shape[j][1] - cLat) * M
            var pV = dx * sinB + dy * cosB
            var pH = dx * cosB - dy * sinB
            if (pV < minV) minV = pV;  if (pV > maxV) maxV = pV
            if (pH < minH) minH = pH;  if (pH > maxH) maxH = pH
        }
        var spanV = Math.max(1, maxV - minV)
        var spanH = Math.max(1, maxH - minH)

        // Centro geométrico del extent proyectado
        var cV_m = (minV + maxV) / 2
        var cH_m = (minH + maxH) / 2
        var mapCLat = cLat + (-cH_m * sinB + cV_m * cosB) / M
        var mapCLon = cLon + ( cH_m * cosB + cV_m * sinB) / (M * cosLat)

        // targetY: posición GPS en navegación (gu(19) desde abajo) o justo encima del panel
        // de selección de rutas cuando está activo (bottomPanelHeight + gu(3) margen).
        var targetY = bottomPanelHeight > 0
                      ? mapRef.height - bottomPanelHeight - units.gu(5)
                      : mapRef.height - units.gu(19)
        // vH: espacio disponible entre el panel superior y targetY.
        // El 10% extra sobre navBarHeight compensa que el panel puede crecer
        // con instrucciones largas y tapar la parte superior de la ruta.
        var vH = Math.max(1, targetY - navBarHeight - units.gu(2.25) - mapRef.height * 0.10)
        var vW = mapRef.width

        var zV   = _savedZoom + Math.log(currentMpp * vH / spanV) / Math.log(2)
        var zW   = _savedZoom + Math.log(currentMpp * vW / spanH) / Math.log(2)
        var zoom = Math.min(zV, zW)
        // Mínimo 3 para que rutas largas (>500 km) quepan sin recorte;
        // con floor 7 el zoom quedaba clampeado y la ruta desbordaba vH.
        zoom = Math.max(3, Math.min(17, zoom))

        var mppNew = currentMpp * Math.pow(2, _savedZoom - zoom)

        // Colocar inicio de ruta en targetY (posición GPS en modo navegación).
        // Con ruta centrada en pantalla, inicio estaría en height/2 + spanV/(2*mppNew);
        // dt_m desplaza el centro para llevarlo a targetY.
        var dt_m   = spanV / 2 - (targetY - mapRef.height / 2) * mppNew
        var adjLat = mapCLat - dt_m * cosB / M
        var adjLon = mapCLon - dt_m * sinB / (M * cosLat)

        // Debug
        _dbgPts    = shape.length
        _dbgMinLat = minLat; _dbgMaxLat = maxLat
        _dbgMinLon = minLon; _dbgMaxLon = maxLon
        _dbgCLat   = mapCLat; _dbgCLon = mapCLon
        _dbgDLat   = spanV / M; _dbgDLon = spanH / (M * cosLat)
        _dbgZH     = zV;   _dbgZW = zW
        _dbgZoom   = zoom
        _dbgVH     = vH; _dbgVW = vW
        _dbgSpanV  = spanV;  _dbgSpanH = spanH
        _dbgMpp    = currentMpp; _dbgMppT = mppNew
        _dbgSavedZ = _savedZoom

        // Aplicar
        appSettings.autoZoom    = false
        appSettings.bearingMode = "north"
        mapRef.followMode       = false
        mapRef.animatePitch(0)
        mapRef.animateBearing(bearDeg)
        mapRef._gpsUpdating = true
        mapRef.center = QtPositioning.coordinate(adjLat, adjLon)
        mapRef._gpsUpdating = false
        mapRef.setZoomLevel(zoom, Qt.point(mapRef.width / 2, mapRef.height / 2))
        visible = true
    }

    function close() {
        visible = false
        _stateSaved = false
        if (!mapRef) { rvp.closed(); return }
        appSettings.autoZoom    = _savedAutoZoom
        appSettings.bearingMode = _savedBearMode
        mapRef.followMode       = _savedFollow
        mapRef.animatePitch(_savedPitch)
        mapRef.animateBearing(_savedBearing)
        mapRef._gpsUpdating = true
        mapRef.center = _savedCenter
        mapRef._gpsUpdating = false
        mapRef.setZoomLevel(_savedZoom, Qt.point(mapRef.width / 2, mapRef.height / 2))
        rvp.closed()
    }

    Rectangle { anchors.fill: parent; color: "transparent" }

    // ── Bandera de destino (z:26, visible sobre RouteViewPanel) ──────────────
    Canvas {
        id: flagCanvas
        anchors.fill: parent
        z: 1   // relativo al RouteViewPanel (z:25) → total z:26 en el padre

        function repaint() { requestPaint() }

        Connections {
            target: rvp.mapRef
            onBearingChanged:   flagCanvas.requestPaint()
            onCenterChanged:    flagCanvas.requestPaint()
            onZoomLevelChanged: flagCanvas.requestPaint()
        }
        onVisibleChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (!rvp.navActive || !rvp.navDests || rvp.navDests.length === 0) return
            if (!rvp.screenPosOf) return

            var dest = rvp.navDests[rvp.navDests.length - 1]
            var dp   = rvp.screenPosOf(dest.lat, dest.lon)
            if (!dp) return
            if (dp.x < -units.gu(5) || dp.x > width + units.gu(5)) return
            if (dp.y < -units.gu(5) || dp.y > height + units.gu(5)) return

            var poleH = units.gu(3.2)
            var fw = units.gu(2.0), fh = units.gu(1.4)
            var cols = 4, rows = 3
            var sw = fw / cols, sh = fh / rows
            var fx = dp.x, fy = dp.y

            ctx.save()
            ctx.shadowColor = "rgba(0,0,0,0.6)"; ctx.shadowBlur = 4
            ctx.strokeStyle = "white"; ctx.lineWidth = units.gu(0.25)
            ctx.beginPath()
            ctx.moveTo(fx, fy); ctx.lineTo(fx, fy - poleH - fh)
            ctx.stroke()
            ctx.restore()

            for (var fr = 0; fr < rows; fr++) {
                for (var fc = 0; fc < cols; fc++) {
                    ctx.fillStyle = (fr + fc) % 2 === 0 ? "white" : "#111111"
                    ctx.fillRect(fx + fc * sw, fy - poleH - fh + fr * sh, sw, sh)
                }
            }
            ctx.strokeStyle = "#BBBBBB"; ctx.lineWidth = 1
            ctx.strokeRect(fx, fy - poleH - fh, fw, fh)
            ctx.beginPath()
            ctx.arc(fx, fy, units.gu(0.4), 0, Math.PI * 2)
            ctx.fillStyle = "white"; ctx.fill()
        }
    }

    // Disparar repaint de bandera cuando cambian los datos de navegación
    onNavActiveChanged: flagCanvas.requestPaint()
    onNavDestsChanged:  flagCanvas.requestPaint()

    // ── Botón cerrar — mismo estilo que ⊞ ────────────────────────────────────
    Rectangle {
        id: closeBtn
        visible: !rvp.hideCloseBtn
        anchors {
            right: parent.right
            top:   parent.top
            rightMargin: units.gu(1.5)
            topMargin:   navBarHeight + units.gu(1)
        }
        width: units.gu(5.5); height: units.gu(5.5)
        radius: width / 2
        color: "#CC1C1C2E"
        border.color: "#90A4AE"; border.width: units.gu(0.12)
        Label {
            anchors.centerIn: parent
            text: "✕"
            color: "#90A4AE"; font.pixelSize: ts(2.2)
        }
        MouseArea { anchors.fill: parent; onClicked: rvp.close() }
    }
}
