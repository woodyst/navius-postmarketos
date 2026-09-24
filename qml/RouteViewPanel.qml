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
    // Ancho del panel lateral que cubre el mapa por la derecha. En landscape el
    // de seleccion de rutas se lleva casi la mitad del ancho: sin descontarlo,
    // la ruta se encuadraba centrada en TODO el mapa y su mitad derecha quedaba
    // debajo del panel.
    property real rightPanelWidth:   0
    // Barra de estado de abajo ("Navius · version · satelites"). Tapa el mapa
    // igual que las otras, y en apaisado es lo unico que lo tapa por abajo.
    property real bottomBarHeight:   0
    // En previsualizacion la ruta se centra en el area visible. Navegando NO:
    // alli el encuadre imita la vista de conduccion, con el inicio abajo, donde
    // esta el marcador de posicion.
    property bool enPrevisualizacion: false

    // Encuadre que dejo puesto open(), para saber si el mapa sigue en el.
    property real _encLat:  0
    property real _encLon:  0
    property real _encZoom: -1

    // ¿Sigue el mapa donde lo dejo open()? Es lo que decide si hace falta el
    // boton de recentrar. Fuera de previsualizacion eso lo dice followMode,
    // pero en previsualizacion followMode es SIEMPRE false —no se sigue a
    // nadie, se esta mirando la ruta—, asi que sin esto el boton no
    // desaparecia nunca, ni recien encuadrado.
    readonly property bool enEncuadre: {
        if (!mapRef || _encZoom < 0) return false
        if (Math.abs(mapRef.zoomLevel - _encZoom) > 0.05) return false
        var c = mapRef.center
        if (!c) return false
        // Tolerancia en PIXELES, no en grados ni en metros: lo que importa es
        // si se nota el desplazamiento en pantalla, y el mismo desplazamiento
        // en metros se ve mucho o nada segun el zoom.
        var M = 111319
        var dLat = (c.latitude  - _encLat) * M
        var dLon = (c.longitude - _encLon) * M * Math.cos(_encLat * Math.PI / 180)
        return Math.sqrt(dLat * dLat + dLon * dLon) < mapRef.metersPerPixel * units.gu(1)
    }

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

        // ── Area de mapa que se ve de verdad ─────────────────────────────
        // El mapa ocupa toda la ventana y encima van los paneles, asi que hay
        // que descontar lo que lo tapa en cada modo. Cuales son cambia con la
        // orientacion: en vertical el panel de rutas esta abajo y la barra de
        // navegacion arriba; en apaisado el panel esta a la derecha y arriba no
        // hay nada. Por eso no vale un margen fijo, hay que calcularlo.
        var visTop    = navBarHeight
        // Por abajo tapan dos cosas, pero se solapan: en vertical el panel de
        // rutas se dibuja ENCIMA de la barra de estado, asi que restar las dos
        // se comia el alto de la barra por duplicado. Manda la mas alta.
        var visBottom = mapRef.height - Math.max(bottomPanelHeight, bottomBarHeight)
        var visLeft   = 0
        var visRight  = mapRef.width - rightPanelWidth
        // Margen para que la ruta no llegue a tocar los bordes. Proporcional al
        // area y no una medida fija: entre vertical y apaisado el alto util
        // cambia casi al doble, y con gu() fijo la ruta salia pegada arriba y
        // abajo justo en el modo donde mas sitio hay.
        var margenV = Math.max(units.gu(2.25), (visBottom - visTop)  * 0.06)
        var margenH = Math.max(units.gu(2.25), (visRight  - visLeft) * 0.06)

        // targetY: posición GPS en navegación (gu(19) desde abajo) o justo encima del panel
        // de selección de rutas cuando está activo (bottomPanelHeight + gu(3) margen).
        var targetY = bottomPanelHeight > 0
                      ? mapRef.height - bottomPanelHeight - units.gu(5)
                      : mapRef.height - units.gu(19)
        var vW, vH
        if (enPrevisualizacion) {
            vW = Math.max(1, (visRight  - visLeft) - margenH * 2)
            vH = Math.max(1, (visBottom - visTop)  - margenV * 2)
        } else {
            // vH: espacio disponible entre el panel superior y targetY.
            // El 10% extra sobre navBarHeight compensa que el panel puede crecer
            // con instrucciones largas y tapar la parte superior de la ruta.
            vH = Math.max(1, targetY - navBarHeight - units.gu(2.25) - mapRef.height * 0.10)
            vW = Math.max(1, mapRef.width - rightPanelWidth - units.gu(2.25))
        }

        var zV   = _savedZoom + Math.log(currentMpp * vH / spanV) / Math.log(2)
        var zW   = _savedZoom + Math.log(currentMpp * vW / spanH) / Math.log(2)
        var zoom = Math.min(zV, zW)
        // Mínimo 3 para que rutas largas (>500 km) quepan sin recorte;
        // con floor 7 el zoom quedaba clampeado y la ruta desbordaba vH.
        zoom = Math.max(3, Math.min(17, zoom))

        var mppNew = currentMpp * Math.pow(2, _savedZoom - zoom)

        // Donde cae la ruta en pantalla. Con el mapa centrado en el centro
        // geometrico de la ruta, esta sale centrada en la VENTANA; lo que sigue
        // corre el centro del mapa para llevarla donde toca.
        //
        // Los ejes son los de la ruta, no los de la pantalla: V va en el sentido
        // de la marcha (hacia arriba, porque el mapa se ha girado al rumbo) y H
        // es el perpendicular. Y los signos no son los que uno diria, estan
        // sacados de la formula de mas abajo: correr el centro +dV por V baja la
        // ruta en pantalla, y correrlo +dH por H la mueve a la IZQUIERDA.
        var adjLat, adjLon
        if (enPrevisualizacion) {
            // Centrada en el area visible: es una pantalla para mirar el
            // trazado entero, no para conducir.
            var cx = (visLeft + visRight) / 2
            var cy = (visTop  + visBottom) / 2
            var dH = (mapRef.width  / 2 - cx) * mppNew
            var dV = (cy - mapRef.height / 2) * mppNew
            adjLat = mapCLat + dV * cosB / M            - dH * sinB / M
            adjLon = mapCLon + dV * sinB / (M * cosLat) + dH * cosB / (M * cosLat)
        } else {
            // Navegando: el inicio de la ruta en targetY, que es donde va el
            // marcador de posicion. Con la ruta centrada el inicio estaria en
            // height/2 + spanV/(2*mppNew); dt_m corre el centro para bajarlo.
            var dt_m = spanV / 2 - (targetY - mapRef.height / 2) * mppNew
            adjLat = mapCLat - dt_m * cosB / M
            adjLon = mapCLon - dt_m * sinB / (M * cosLat)
            if (rightPanelWidth > 0) {
                var dh_m = (rightPanelWidth / 2) * mppNew
                adjLat += -dh_m * sinB / M
                adjLon +=  dh_m * cosB / (M * cosLat)
            }
        }

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
        _encLat = adjLat; _encLon = adjLon; _encZoom = zoom
        visible = true
    }

    function close() {
        visible = false
        _stateSaved = false
        _encZoom    = -1
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
