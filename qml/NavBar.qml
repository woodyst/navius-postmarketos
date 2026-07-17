import QtQuick 2.7
import QtQuick.Controls 2.15
import "NavSearch.js" as NavSearch

// Barra de navegación activa — aparece en la parte superior de la pantalla.
Rectangle {
    id: bar

    property real textScale:    1.0    // escala global de texto (pasada desde Main)
    function ts(v) { return units.gu(v * 0.9 * textScale) }

    property bool imperial:     false  // true = sistema imperial (mph, mi, ft)
    property var  routeData:    null   // {shape, maneuvers, length, time}
    property real gpsLat:       0
    property real gpsLon:       0
    property real gpsHeadRad:   0      // heading en radianes (del conductor)
    property real gpsSpeedKmh:  0      // velocidad actual
    property real posAccuracy:  -1    // precisión GPS en metros
    property bool hasFix:       false  // true cuando hay fix GPS válido
    property bool searchingGps: false  // true cuando no hay fix de satélites reales
    property bool navActive:    true   // false = modo mapa (muestra "Iniciar navegación")

    signal stopNavigation()
    signal offRoute()
    signal arrived()                // destino FINAL confirmado (vía confirmLegArrival)
    signal startNavRequested()      // pulsado "Iniciar navegación" en modo mapa
    signal reloadDestRequested()    // pulsado "Recargar destino" tras llegar
    signal instructionsRequested()  // pulsado la zona de instrucciones
    signal intermediateArrived(int waypointIndex)  // llegada a parada intermedia (tras confirmar)
    // Se ha alcanzado el destino del leg activo; Main muestra "¿Has llegado?" y confirma.
    signal legArrivalReached(int legIdx, bool isFinal)

    property bool showReloadDest: false  // muestra botón "Recargar destino"
    // distM=0 → ya; instrId=índice 1-based; text=parte1 (antes del punto); text2=parte2 (solo en ya)
    signal announce(int distM, string text, string text2, int instrId, string annType)

    width:  parent.width
    // En landscape el panel padre fija la altura; en portrait la calcula el contenido
    height: isLandscape ? parent.height
            : navActive
              ? ((_wrongDir ? ts(3.5) : 0) + instrRect.height + (_hasNextWp ? ts(9.5) : ts(7.0)))
              : (showReloadDest ? ts(20) : ts(15))
    Behavior on height { NumberAnimation { duration: 200 } }
    color:  "#07111E"

    property bool trackReplayMode: false  // true durante reproducción de track grabado
    property int  _step:        0
    property bool _arrivedEmitted: false
    property real _distKm:      0
    property real _timeSec:     0
    property real   _stepDistKm:      0
    property real   _stepTimeSec:     0
    property real   _valhallaSpeedKmh: 0 // velocidad estimada Valhalla para el tramo actual
    property real   _lastTickMs:      0
    property string _roadClass:        ""  // clase de vía Valhalla (motorway, trunk, primary...)
    property real   _legDistKm:    0
    property real   _legTimeSec:   0
    property bool   _hasNextWp:    false
    property var    navWaypoints:  []   // [{lat,lon,name,todos}] — _navDests de Main
    property string _nextWpName:   ""
    property string _finalName:    ""
    property int    _completedLegs: 0   // leg activo (= tramos confirmados). Solo avanza al confirmar llegada.
    // Confirmación manual de llegada al destino del leg activo:
    property bool   _legArrivalPending: false  // banner "¿Has llegado?" mostrado, esperando respuesta
    property bool   _legArrivalArmed:   true   // puede disparar la pregunta (se rearma al alejarse / parar cerca)
    property real   _legDismissMs:      0      // ms del último "Todavía no" (0 = ninguno)
    property real   _legStoppedMs:      0      // ms desde que estás parado cerca del destino (0 = no)
    property int    _speedLimit:          -1     // km/h del tramo actual, -1 = desconocido
    property bool   _speedLimitVerified:  false  // true = confirmado por OSM edge.speed_limit
    property string _speedLimitSrc:       ""     // origen del dato: "OSM", "dflt(ES/primary)", etc.
    property int    speedAlertPct:        1      // % margen alerta (pasado desde Main)
    property bool   speedAlertEnabled:    true   // activa/desactiva alerta (pasado desde Main)
    property int    commSpeedLimit:       0      // límite comunitario activo (0 = ninguno)
    property int    commAlertSpeed:       0      // velocidad de alerta comunitaria activa
    property int    radarMaxspeed:        0      // velocidad de radar fijo/tramo OSM activo
    property bool   showRoadSpeedLimit:   false  // mostrar límite de la vía (fuente no fiable)
    property bool   isLandscape:          false  // true = panel lateral izquierdo 1/3

    // Límite efectivo para el letrero: zona comunitaria > alerta comunitaria > radar OSM > vía (opcional)
    readonly property int  _effLimit:    commSpeedLimit > 0    ? commSpeedLimit
                                       : commAlertSpeed > 0    ? commAlertSpeed
                                       : radarMaxspeed > 0     ? radarMaxspeed
                                       : (showRoadSpeedLimit && _speedLimit > 0) ? _speedLimit
                                       : -1
    readonly property bool _effVerified: commSpeedLimit > 0 || commAlertSpeed > 0
                                       || radarMaxspeed > 0   || _speedLimitVerified

    // Límite para el color del indicador: radar > usuario; si showRoadSpeedLimit también alerta y vía
    readonly property int  _colorLimit:  radarMaxspeed > 0     ? radarMaxspeed
                                       : commSpeedLimit > 0    ? commSpeedLimit
                                       : (showRoadSpeedLimit && commAlertSpeed > 0) ? commAlertSpeed
                                       : (showRoadSpeedLimit && _speedLimit > 0)    ? _speedLimit
                                       : -1

    property bool   _speedOver: navActive && speedAlertEnabled && _colorLimit > 0 &&
                                gpsSpeedKmh > _colorLimit * (1.0 + speedAlertPct / 100.0)

    // Off-route
    property int  _offCount:      0   // lecturas consecutivas fuera de ruta
    property bool _rerouting:     false
    property real _lastRerouteMs:    0   // timestamp de finalización del último recálculo (ms)
    property real _lastRerouteLat:   0   // posición donde se disparó el último recálculo
    property real _lastRerouteLon:   0
    property int  _stableFixes:   0   // fixes consecutivos con precisión < 50 m
    property bool _realFix:       false // true tras ≥5 fixes estables
    property real _realLat:       0   // lat del último tick GPS real (solo ticks primarios)
    property real _realLon:       0   // lon del último tick GPS real
    property real distFromRoute:  0   // distancia al shape más cercano (m); 0 sin ruta
    property int  offRouteDistM:  25  // distancia para detectar desvío y recalcular (m)
    property real snapLat:        0   // punto proyectado sobre el segmento más cercano
    property real snapLon:        0
    property real snapHeadRad:    0   // rumbo del segmento de ruta en el punto snap (rad)
    property int  _snapShapeI:    0   // índice del segmento donde cae snapLat/snapLon
    property real _snapShapeFrac: 0   // fracción dentro de ese segmento
    property bool revMode:        false
    property var  revShape:       null   // [[lon,lat],...] forma de revRoute; nulo fuera de revMode
    property bool paused:         false
    property real _lastDistMs:    0
    property real _lastUpdateMs:  0   // throttle update() a 2 Hz máximo

    // Estado de display: "nav" | "offroute" | "rerouting"
    property string _status: "nav"

    // Dirección contraria
    property bool _wrongDir:   false
    property int  _wrongCount: 0

    // Avisos acústicos: máquina de estado por maniobra
    // _annCount: avisos pendientes (2=pre2+pre1+ya, 1=pre1+ya, 0=ya solo)
    // _annTarget: distancia en metros a la que se disparará el próximo pre (-1 = sin establecer)
    property int  _annStep:   -1
    property int  _annCount:   0
    property real _annTarget: -1
    property bool _yaDone:   false
    property real _lastYaMs:  0   // timestamp del último "ya" emitido
    property real _navStartMs: 0  // timestamp de inicio de ruta (para gracia inicial)

    // ETA desde un punto de la ruta. endIdx opcional (por defecto hasta el final).
    // Devuelve {stepSec, totalSec, totalKm}.
    function _calcEta(man, stepIdx, remainDistKm, currentSpeedKmh, commLimit, endIdx) {
        var end = (endIdx !== undefined) ? endIdx : man.length
        var plannedSpd = (man[stepIdx]) ? NavSearch.segSpeedKmh(man[stepIdx], commLimit) : 50
        var effSpd = Math.max(currentSpeedKmh, plannedSpd)
        var stepSec  = effSpd > 0 ? remainDistKm * 3600 / effSpd : 0
        var totalKm  = remainDistKm
        var totalSec = stepSec
        for (var m = stepIdx + 1; m < end; m++) {
            var mSpd = NavSearch.segSpeedKmh(man[m], commLimit)
            totalKm  += man[m].length
            totalSec += mSpd > 0 ? man[m].length * 3600 / mSpd : man[m].time
        }
        return { stepSec: stepSec, totalSec: totalSec, totalKm: totalKm }
    }

    // Redondea una distancia (metros) al valor inferior más próximo de la escala de avisos.
    // Convierte "1.°" / "2.º" / "3.ª" en el ordinal español con género
    // detectado por palabras clave en el propio texto de la instrucción.
    // Usado para que Piper no lea "uno punto o" en instrucciones de glorieta.
    function _fixOrdinales(txt) {
        // ° U+00B0  º U+00BA  ª U+00AA — los tres pueden aparecer según la versión de Valhalla
        if (!/\d+\.[°ºª]/.test(txt)) return txt
        var FEM_RE = /glorieta|rotonda|salida|calle|avenida|carretera|v[ií]a|autopista|ruta/i
        var MAS_RE = /camino|paso|carril|ramal|puente/i
        var useFem = FEM_RE.test(txt) || !MAS_RE.test(txt)   // fem por defecto
        var ordF = ["","primera","segunda","tercera","cuarta","quinta","sexta","séptima","octava","novena","décima"]
        var ordM = ["","primero","segundo","tercero","cuarto","quinto","sexto","séptimo","octavo","noveno","décimo"]
        return txt.replace(/(\d+)\.[°ºª]/g, function(_, n) {
            var i = parseInt(n, 10)
            if (i < 1 || i > 10) return n + "."
            return useFem ? ordF[i] : ordM[i]
        })
    }

    function _roundDist(m) {
        if (m <= 0)    return 10
        if (m < 100)   return Math.max(10, Math.floor(m / 10)   * 10)
        if (m < 300)   return Math.floor(m / 50)  * 50
        if (m < 500)   return Math.floor(m / 100) * 100
        if (m < 1000)  return Math.floor(m / 200) * 200
        if (m < 10000) return Math.floor(m / 1000)* 1000
        return Math.round(m)
    }

    // El usuario confirma "Sí, he llegado" al destino del leg activo.
    // Último leg → arrived() (termina nav). Intermedio → avanza al siguiente leg.
    function confirmLegArrival() {
        if (!_legArrivalPending) return
        _legArrivalPending = false
        _legStoppedMs = 0; _legDismissMs = 0
        var wps = navWaypoints
        var isFinal = !routeData || !routeData.shape
                      || !routeData.legShapeEnds || routeData.legShapeEnds.length === 0
                      || _completedLegs >= routeData.legShapeEnds.length - 1
        if (isFinal) {
            _arrivedEmitted = true
            bar.arrived()
        } else {
            _completedLegs += 1            // el siguiente destino pasa a ser el activo
            _legArrivalArmed = true        // rearmado para la pregunta del nuevo leg
            // _step se reposiciona en el siguiente tick (snap ya acotado al nuevo leg)
            bar.intermediateArrived(_completedLegs - 1)
        }
    }

    // "Todavía no": cierra el banner sin completar el leg. Re-preguntará si te alejas
    // y vuelves, o si te paras cerca >5 s.
    function dismissLegArrival() {
        _legArrivalPending = false
        _legArrivalArmed   = false
        _legDismissMs      = Date.now()
        _legStoppedMs      = 0
    }

    function update() {
        if (!routeData || !routeData.shape || routeData.shape.length < 2) return
        if (_rerouting) return

        var shape  = (revMode && revShape && revShape.length > 1) ? revShape : routeData.shape
        var start  = (revMode && revShape) ? 0
                     : (routeData.maneuvers && _step < routeData.maneuvers.length
                        ? routeData.maneuvers[_step].begin_shape_index : 0)
        // Acotar el snap (y por tanto sentido de marcha, off-route y avance de step) al
        // LEG ACTIVO únicamente. En rutas ida-vuelta el shape contiene ida y vuelta; sin
        // este límite el snap puede engancharse al tramo de vuelta (sentido contrario)
        // donde ambos coinciden geográficamente.
        var _legEnds   = (!revMode && routeData.legShapeEnds && routeData.legShapeEnds.length > 0)
                         ? routeData.legShapeEnds : null
        var _legEndIdx = (_legEnds && _completedLegs < _legEnds.length)
                         ? _legEnds[_completedLegs] : (shape.length - 1)
        var end    = Math.min(shape.length - 1, start + 300, _legEndIdx)
        var cosLat = Math.cos(_realLat * Math.PI / 180)
        var K      = 111319

        // Distancia al segmento más cercano (proyección perpendicular)
        var minD = 1e18, minI = start, minT = 0
        for (var i = start; i < end; i++) {
            var p0Lat = shape[i][1],   p0Lon = shape[i][0]
            var p1Lat = shape[i+1][1], p1Lon = shape[i+1][0]
            var sLat  = (p1Lat - p0Lat) * K
            var sLon  = (p1Lon - p0Lon) * K * cosLat
            var sLen2 = sLat * sLat + sLon * sLon
            var dLat  = (_realLat - p0Lat) * K
            var dLon  = (_realLon - p0Lon) * K * cosLat
            var t = (sLen2 < 0.01) ? 0 : Math.max(0, Math.min(1, (dLat * sLat + dLon * sLon) / sLen2))
            var eLat = dLat - t * sLat, eLon = dLon - t * sLon
            var d2 = eLat * eLat + eLon * eLon
            if (d2 < minD) { minD = d2; minI = i; minT = t }
        }
        // Extender búsqueda si alcanzamos el límite — pero sin pasar del leg activo
        if (minI === end - 1 && end < _legEndIdx) {
            for (var j = end; j < _legEndIdx; j++) {
                var p0Lat2 = shape[j][1],   p0Lon2 = shape[j][0]
                var p1Lat2 = shape[j+1][1], p1Lon2 = shape[j+1][0]
                var sLat2  = (p1Lat2 - p0Lat2) * K
                var sLon2  = (p1Lon2 - p0Lon2) * K * cosLat
                var sLen22 = sLat2 * sLat2 + sLon2 * sLon2
                var dLat2  = (_realLat - p0Lat2) * K
                var dLon2  = (_realLon - p0Lon2) * K * cosLat
                var t2 = (sLen22 < 0.01) ? 0 : Math.max(0, Math.min(1, (dLat2 * sLat2 + dLon2 * sLon2) / sLen22))
                var eLat2 = dLat2 - t2 * sLat2, eLon2 = dLon2 - t2 * sLon2
                var d22 = eLat2 * eLat2 + eLon2 * eLon2
                if (d22 < minD) { minD = d22; minI = j; minT = t2 } else break
            }
        }
        var distM = Math.sqrt(minD)
        distFromRoute = distM
        var _sp0 = shape[minI], _sp1 = shape[Math.min(minI + 1, shape.length - 1)]
        snapLat        = _sp0[1] + minT * (_sp1[1] - _sp0[1])
        snapLon        = _sp0[0] + minT * (_sp1[0] - _sp0[0])
        _snapShapeI    = minI
        _snapShapeFrac = minT
        // Bearing del segmento de ruta activo (heading predictivo)
        var _sLa1 = _sp0[1], _sLo1 = _sp0[0], _sLa2 = _sp1[1], _sLo2 = _sp1[0]
        if (_sLa1 !== _sLa2 || _sLo1 !== _sLo2) {
            var _dl = (_sLo2 - _sLo1) * Math.PI / 180
            var _f1 = _sLa1 * Math.PI / 180, _f2 = _sLa2 * Math.PI / 180
            snapHeadRad = Math.atan2(Math.sin(_dl) * Math.cos(_f2),
                                     Math.cos(_f1) * Math.sin(_f2) - Math.sin(_f1) * Math.cos(_f2) * Math.cos(_dl))
        }

        // Off-route: >8 m durante 3 ticks GPS reales consecutivos
        // No detectar si estamos en la última maniobra (destino alcanzado)
        var man          = revMode ? null : routeData.maneuvers
        // Distancia al waypoint del leg activo — calculada antes del bloque off-route
        // para poder suprimir detección cuando el GPS se aproxima al cruce de parada.
        var _legDest     = shape[Math.min(_legEndIdx, shape.length - 1)]
        var _legDestDLat = (_realLat - _legDest[1]) * 111319
        var _legDestDLon = (_realLon - _legDest[0]) * cosLat * 111319
        var _distToLegEnd = Math.sqrt(_legDestDLat*_legDestDLat + _legDestDLon*_legDestDLon)
        // nearDest suprime off-route/sentido: última maniobra, esperando confirmación,
        // o GPS a <150 m del waypoint (evita rerouting espúreo por deriva en el cruce)
        var nearDest     = (man && _step >= man.length - 1) || _legArrivalPending
                           || _distToLegEnd < 150
        var offThreshold = bar.offRouteDistM
        var goodAccuracy = bar.posAccuracy < 0 || bar.posAccuracy < offThreshold

        if (!nearDest && distM > offThreshold && bar.hasFix && goodAccuracy && _realFix && !bar.trackReplayMode) {
            _offCount++
            if (_offCount === 1) _status = "offroute"
            if (_offCount >= 3) {
                var _rcdOff = Date.now() - _lastRerouteMs < 5000
                if (!_rcdOff && _lastRerouteLat !== 0) {
                    var _rdLatOff = (_realLat - _lastRerouteLat) * 111319
                    var _rdLonOff = (_realLon - _lastRerouteLon) * 111319 * Math.cos(_realLat * Math.PI / 180)
                    if (Math.sqrt(_rdLatOff*_rdLatOff + _rdLonOff*_rdLonOff) < 50) _rcdOff = true
                }
                if (_rcdOff) {
                    _offCount = 0
                } else {
                    _offCount = 0
                    _status   = "rerouting"; _rerouting = true
                    _lastRerouteLat = _realLat; _lastRerouteLon = _realLon
                    bar.offRoute()
                }
            }
        } else {
            _offCount = 0
            if (_status !== "rerouting") _status = "nav"
        }

        // En revMode: distancia/snap/off-route usan revShape; _wrongDir usa ruta principal.
        // Rerouting por dirección contraria solo si además nos alejamos de revShape.
        if (revMode) {
            var mShape = routeData.shape
            var mIdx = (_step < routeData.maneuvers.length)
                       ? Math.min(routeData.maneuvers[_step].begin_shape_index, mShape.length - 2)
                       : 0
            if (bar.gpsSpeedKmh > 5 && mIdx + 1 < mShape.length) {
                var la1r = mShape[mIdx][1] * Math.PI / 180
                var la2r = mShape[mIdx + 1][1] * Math.PI / 180
                var dlor = (mShape[mIdx + 1][0] - mShape[mIdx][0]) * Math.PI / 180
                var routeBearR = Math.atan2(Math.sin(dlor) * Math.cos(la2r),
                                            Math.cos(la1r) * Math.sin(la2r)
                                            - Math.sin(la1r) * Math.cos(la2r) * Math.cos(dlor))
                var diffR = bar.gpsHeadRad - routeBearR
                diffR = diffR - 2 * Math.PI * Math.floor((diffR + Math.PI) / (2 * Math.PI))
                // En revMode: esperar ≥4 ticks (~4 s) para no reroutear nada más activar
                if (Math.abs(diffR) > 2.356) {
                    _wrongCount++
                    if (_wrongCount >= 4) _wrongDir = true
                    if (_wrongCount === 4 && bar.hasFix && !_rerouting) {
                        var _rcdRev = Date.now() - _lastRerouteMs < 5000
                        if (!_rcdRev && _lastRerouteLat !== 0) {
                            var _rdLatRev = (_realLat - _lastRerouteLat) * 111319
                            var _rdLonRev = (_realLon - _lastRerouteLon) * 111319 * Math.cos(_realLat * Math.PI / 180)
                            if (Math.sqrt(_rdLatRev*_rdLatRev + _rdLonRev*_rdLonRev) < 50) _rcdRev = true
                        }
                        if (!_rcdRev) {
                            _status = "rerouting"; _rerouting = true
                            _lastRerouteLat = _realLat; _lastRerouteLon = _realLon
                            bar.offRoute()
                        }
                    }
                } else {
                    _wrongCount = 0; _wrongDir = false
                }
            } else {
                _wrongCount = 0; _wrongDir = false
            }

            // Distancia a maniobra: proyectar GPS sobre ruta principal y sumar segmentos
            if (routeData.maneuvers && _step < routeData.maneuvers.length) {
                var curM_r  = routeData.maneuvers[_step]
                var mEndIdx = curM_r.end_shape_index
                var mWS     = Math.max(0, curM_r.begin_shape_index - 200)
                var mWE     = Math.min(mShape.length - 1, mEndIdx + 1)
                var mMinD   = 1e18, mMinI = mWS, mMinT = 0
                for (var mi = mWS; mi < mWE; mi++) {
                    var mp0 = mShape[mi], mp1 = mShape[mi + 1]
                    var msL  = (mp1[1] - mp0[1]) * K
                    var msN  = (mp1[0] - mp0[0]) * K * cosLat
                    var msl2 = msL * msL + msN * msN
                    var mdL  = (_realLat - mp0[1]) * K
                    var mdN  = (_realLon - mp0[0]) * K * cosLat
                    var mmt  = msl2 < 0.01 ? 0 : Math.max(0, Math.min(1, (mdL * msL + mdN * msN) / msl2))
                    var meL  = mdL - mmt * msL, meN = mdN - mmt * msN
                    var md   = meL * meL + meN * meN
                    if (md < mMinD) { mMinD = md; mMinI = mi; mMinT = mmt }
                }
                var mSp0 = mShape[mMinI], mSp1 = mShape[Math.min(mMinI + 1, mShape.length - 1)]
                var mRem = 0
                if (mMinI < mEndIdx) {
                    var mg0L = (mSp1[1] - mSp0[1]) * K, mg0N = (mSp1[0] - mSp0[0]) * K * cosLat
                    mRem += (1 - mMinT) * Math.sqrt(mg0L * mg0L + mg0N * mg0N)
                    for (var msi = mMinI + 1; msi < mEndIdx && msi + 1 < mShape.length; msi++) {
                        var msiL = (mShape[msi + 1][1] - mShape[msi][1]) * K
                        var msiN = (mShape[msi + 1][0] - mShape[msi][0]) * K * cosLat
                        mRem += Math.sqrt(msiL * msiL + msiN * msiN)
                    }
                }
                _stepDistKm       = mRem / 1000
                _valhallaSpeedKmh = NavSearch.segSpeedKmh(curM_r, commSpeedLimit)
                _stepTimeSec      = _calcEta(man, _step, _stepDistKm, gpsSpeedKmh, commSpeedLimit, _step + 1).stepSec
            }
            return
        }

        // Llegada al destino del LEG ACTIVO (≤10 m, rebaso, o parado cerca >5 s).
        // NO se completa el leg aquí: se emite legArrivalReached y Main pregunta
        // "¿Has llegado?". El leg solo avanza al confirmar (confirmLegArrival()).
        // Re-pregunta si te alejas y vuelves, o si te paras cerca tras descartar.
        if (!_arrivedEmitted && bar.hasFix) {
            // Reutiliza _legDest y _distToLegEnd calculados arriba para off-route
            var dlat_d  = _legDestDLat
            var dlon_d  = _legDestDLon
            var distToDest = _distToLegEnd
            // Rebaso: (pos − dest)·(dir último segmento del leg) > 0
            // Solo comprobar si ya estamos cerca (<100 m): el producto escalar puede
            // ser positivo aunque estés kilómetros atrás si la dirección del segmento
            // apunta hacia donde vienes, disparando el banner prematuramente.
            var passed = false
            if (distToDest < 100 && _legEndIdx >= 1) {
                var prev   = shape[_legEndIdx - 1]
                var segLat = (_legDest[1] - prev[1]) * 111319
                var segLon = (_legDest[0] - prev[0]) * cosLat * 111319
                var segLen = Math.sqrt(segLat * segLat + segLon * segLon)
                if (segLen > 0.1)
                    passed = (dlat_d * segLat + dlon_d * segLon) > 0
            }
            var _isFinalLeg = (_legEndIdx >= shape.length - 1)
            var _nowA = Date.now()
            // Cronómetro de "parado cerca" (para re-preguntar)
            if (distToDest <= 10 && bar.gpsSpeedKmh < 3) {
                if (_legStoppedMs === 0) _legStoppedMs = _nowA
            } else {
                _legStoppedMs = 0
            }
            var _stoppedNear = _legStoppedMs > 0 && (_nowA - _legStoppedMs) > 5000

            if (_legArrivalArmed && !_legArrivalPending && (distToDest <= 10 || passed || _stoppedNear)) {
                console.log("NavBar LEG ARRIVAL leg=" + _completedLegs + " final=" + _isFinalLeg
                            + " dist=" + distToDest.toFixed(1) + " passed=" + passed)
                _legArrivalPending = true
                _legArrivalArmed   = false
                bar.legArrivalReached(_completedLegs, _isFinalLeg)
            } else if (!_legArrivalPending && !_legArrivalArmed) {
                // Rearmar: te has alejado (>50 m) o sigues parado cerca >5 s tras descartar
                if (distToDest > 50)
                    _legArrivalArmed = true
                else if (_stoppedNear && _legDismissMs > 0 && (_nowA - _legDismissMs) > 5000)
                    _legArrivalArmed = true
            }
        }

        // Determina la maniobra actual; empieza desde _step para no retroceder
        for (var k = _step; k < man.length - 1; k++) {
            if (minI >= man[k].begin_shape_index && minI <= man[k].end_shape_index) {
                _step = k; break
            }
        }
        // Límite de velocidad y clase de vía del tramo actual
        var sl  = man[_step].speed_limit
        var slv = man[_step].speed_limit_verified
        _speedLimit         = (sl !== undefined && sl > 0) ? Math.round(sl) : -1
        _speedLimitVerified = (slv === true)
        _speedLimitSrc      = man[_step].speed_limit_src || ""
        _roadClass          = man[_step].road_class || ""

        // Distancia/tiempo restantes en la maniobra actual (recorrido por segmentos de shape)
        var curM   = man[_step]
        var endIdx = curM.end_shape_index
        var remDistM = 0
        if (minI < endIdx) {
            var seg0Lat = (_sp1[1] - _sp0[1]) * K
            var seg0Lon = (_sp1[0] - _sp0[0]) * K * cosLat
            remDistM += (1 - minT) * Math.sqrt(seg0Lat * seg0Lat + seg0Lon * seg0Lon)
            for (var si = minI + 1; si < endIdx && si + 1 < shape.length; si++) {
                var siLat = (shape[si+1][1] - shape[si][1]) * K
                var siLon = (shape[si+1][0] - shape[si][0]) * K * cosLat
                remDistM += Math.sqrt(siLat * siLat + siLon * siLon)
            }
        }
        _stepDistKm       = remDistM / 1000
        _valhallaSpeedKmh = NavSearch.segSpeedKmh(curM, commSpeedLimit)
        var eta = _calcEta(man, _step, _stepDistKm, gpsSpeedKmh, commSpeedLimit)
        _stepTimeSec = eta.stepSec
        _distKm      = eta.totalKm
        _timeSec     = eta.totalSec

        // Destino intermedio: primer maneuver tipo Destination antes del último
        var nextWpIdx = -1
        for (var wi = _step; wi < man.length - 1; wi++) {
            var t2 = man[wi].type
            if (t2 === 4 || t2 === 5 || t2 === 6) { nextWpIdx = wi; break }
        }
        _hasNextWp = nextWpIdx >= 0
        if (_hasNextWp) {
            var legEta  = _calcEta(man, _step, _stepDistKm, gpsSpeedKmh, commSpeedLimit, nextWpIdx + 1)
            _legDistKm  = legEta.totalKm
            _legTimeSec = legEta.totalSec
        }

        // Nombres de destinos según el leg ACTIVO (= _completedLegs). _completedLegs ya no
        // se deriva de _step: solo avanza al confirmar la llegada (confirmLegArrival()).
        var wps = navWaypoints
        _nextWpName = (wps.length > _completedLegs) ? (wps[_completedLegs].name || "") : ""
        _finalName  = (wps.length > 0)              ? (wps[wps.length - 1].name || "") : ""

        // Dirección contraria: ángulo entre heading y dirección de la ruta > 135°
        if (bar.gpsSpeedKmh > 5 && !nearDest && minI + 1 < shape.length) {
            var la1 = shape[minI][1] * Math.PI / 180
            var la2 = shape[minI + 1][1] * Math.PI / 180
            var dlo = (shape[minI + 1][0] - shape[minI][0]) * Math.PI / 180
            var routeBear = Math.atan2(Math.sin(dlo) * Math.cos(la2),
                                       Math.cos(la1) * Math.sin(la2)
                                       - Math.sin(la1) * Math.cos(la2) * Math.cos(dlo))
            var diff = bar.gpsHeadRad - routeBear
            diff = diff - 2 * Math.PI * Math.floor((diff + Math.PI) / (2 * Math.PI))
            if (Math.abs(diff) > 2.356) {   // > 135°
                _wrongCount++
                if (_wrongCount >= 2) _wrongDir = true
                if (_wrongCount === 2 && bar.hasFix && !_rerouting) {
                    var _rcdWd = Date.now() - _lastRerouteMs < 5000
                    if (!_rcdWd && _lastRerouteLat !== 0) {
                        var _rdLatWd = (_realLat - _lastRerouteLat) * 111319
                        var _rdLonWd = (_realLon - _lastRerouteLon) * 111319 * Math.cos(_realLat * Math.PI / 180)
                        if (Math.sqrt(_rdLatWd*_rdLatWd + _rdLonWd*_rdLonWd) < 50) _rcdWd = true
                    }
                    if (!_rcdWd) {
                        _status = "rerouting"; _rerouting = true
                        _lastRerouteLat = _realLat; _lastRerouteLon = _realLon
                        bar.offRoute()
                    }
                }
            } else {
                _wrongCount = 0; _wrongDir = false
            }
        } else {
            _wrongCount = 0; _wrongDir = false
        }

        // ── Avisos acústicos ───────────────────────────────────────────────
        if (_status !== "nav" || !bar.hasFix) return
        var dispIdx = Math.min(_step + 1, man.length - 1)
        var mv2 = man[dispIdx]
        var instrText = mv2.verbal_pre_transition_instruction || mv2.instruction || ""
        if (!instrText) return

        var spdMs    = bar.gpsSpeedKmh / 3.6
        var distM    = _stepDistKm * 1000
        var timeToMnv = spdMs > 0.5 ? distM / spdMs : 99999

        // Resetear máquina de estado al cambiar de step
        if (_annStep !== _step) {
            _annStep   = _step
            _yaDone    = false
            _annTarget = -1
            // Cuando el coche está parado (spdMs≤0.5), timeToMnv=99999 provoca _annCount=2
            // para maniobras cercanas → pre2+pre1+ya todos disparan. Usar estimación
            // por distancia (50 km/h nominal) para calcular el _annCount correcto.
            var _tEff = spdMs > 0.5 ? timeToMnv : (distM / 13.9)
            if      (_tEff >= 123) _annCount = 2
            else if (_tEff >= 48)  _annCount = 1
            else                   _annCount = 0
        }

        var now = Date.now()
        // Periodo de gracia al inicio: deja terminar play_start_route antes del primer aviso
        if ((now - _navStartMs) < 4000) return

        // Dividir instrucción: parte1 (antes del primer punto) y parte2 (resto)
        var _instrFixed = _fixOrdinales(instrText)
        var _annParts = _instrFixed.split(". ")
        var _annText1 = _annParts[0]
        var _annText2 = _annParts.length > 1 ? _annParts.slice(1).join(". ") : ""

        // ── Texto de fusión con siguiente maniobra ─────────────────────────
        // Si el siguiente maneuver llega antes de que termine de sonar el TTS
        // actual, lo fusionamos: "…, y a continuación [siguiente instrucción]"
        var _nextDispIdx = Math.min(dispIdx + 1, man.length - 1)
        var _nextMv = (_nextDispIdx > dispIdx) ? man[_nextDispIdx] : null
        var _nextText = _nextMv ? (_nextMv.verbal_pre_transition_instruction || _nextMv.instruction || "") : ""
        var _nextText1 = _nextText ? _fixOrdinales(_nextText).split(". ")[0] : ""
        // Tiempo hasta el siguiente maneuver desde posición actual
        var _timeToNext = (spdMs > 0.5 && mv2.length)
                          ? timeToMnv + (mv2.length * 1000 / spdMs)
                          : 99999
        // Duración estimada TTS: 65 ms/carácter; +20 para "En X metros, " en pre1/pre2
        function _ttsSec(txt, withDist) { return (txt.length + (withDist ? 20 : 0)) * 0.065 }
        function _fuseText(txt, withDist) {
            if (!_nextText1 || _annText2) return txt
            if (_timeToNext < _ttsSec(txt, withDist) + 15 + 5)
                return txt + ", y a continuación " + _nextText1.toLowerCase()
            return txt
        }

        // ── pre2: ventana 48–123 s, máximo 2000 m ────────────────────────
        // Si timeToMnv ya cayó al rango de pre1 o ya, omitir pre2 directamente.
        if (_annCount >= 2) {
            if (_annTarget < 0 && timeToMnv <= 123 && timeToMnv > 48 && distM <= 2000)
                _annTarget = _roundDist(distM)
            if (_annTarget >= 0 && distM <= _annTarget) {
                if (now - _lastYaMs >= 3000) {
                    bar.announce(_annTarget, _fuseText(_annText1, true), "", dispIdx, "pre2")
                    _annCount  = 1
                    _annTarget = -1
                } else {
                    _annCount  = 1
                    _annTarget = -1
                }
            } else if (_annTarget < 0 && timeToMnv <= 48) {
                // timeToMnv ya está en zona de pre1: saltar pre2
                _annCount  = 1
                _annTarget = -1
            }
        }

        // ── pre1: ventana 15–48 s, máximo 500 m ──────────────────────────
        // Si timeToMnv ya cayó al rango de ya, omitir pre1 directamente.
        if (_annCount === 1) {
            if (_annTarget < 0 && timeToMnv <= 48 && timeToMnv > 15 && distM <= 500)
                _annTarget = _roundDist(distM)
            if (_annTarget >= 0 && distM <= _annTarget) {
                if (now - _lastYaMs >= 3000) {
                    bar.announce(_annTarget, _fuseText(_annText1, true), "", dispIdx, "pre1")
                    _annCount  = 0
                    _annTarget = -1
                } else {
                    _annCount  = 0
                    _annTarget = -1
                }
            } else if (_annTarget < 0 && timeToMnv <= 15) {
                // timeToMnv ya está en zona de ya: saltar pre1
                _annCount  = 0
                _annTarget = -1
            }
        }

        // ── ya: a 15 s de maniobra, mínimo 15 m, siempre ──────────────────
        // text2 se reproduce justo tras la maniobra (paso de la indicación)
        if (!_yaDone && timeToMnv <= 15 && distM >= 15) {
            bar.announce(0, _fuseText(_annText1, false), _annText2, dispIdx, "ya")
            _yaDone   = true
            _lastYaMs = now
        }
    }

    // Llamado desde Main.qml en cada gpsTick del GpsSource.
    // isReal=true → tick primario (fix real o punto de ruta sim): ejecuta update() completo.
    // isReal=false → tick interpolado: decrementa distancias/tiempos con velocidad actual.
    function handleTick(isReal, ms) {
        if (routeData === null || !navActive) return
        if (isReal) {
            _realLat = gpsLat
            _realLon = gpsLon
            if (bar.posAccuracy > 0 && bar.posAccuracy < 50) {
                if (++_stableFixes >= 5) _realFix = true
            } else {
                _stableFixes = 0
            }
            if (ms - _lastUpdateMs >= 500) { _lastUpdateMs = ms; update() }
        } else if (bar.hasFix && gpsSpeedKmh > 0.5) {
            var dtS = (_lastTickMs > 0) ? (ms - _lastTickMs) / 1000.0 : 0
            if (dtS > 0 && dtS < 2.0) {
                var dKm = gpsSpeedKmh * dtS / 3600
                if (!revMode && ms - _lastDistMs >= 500) {
                    _stepDistKm = Math.max(0, _stepDistKm - dKm)
                    var man2 = routeData ? routeData.maneuvers : null
                    if (man2) {
                        var eta2 = _calcEta(man2, _step, _stepDistKm, gpsSpeedKmh, commSpeedLimit)
                        _stepTimeSec = eta2.stepSec
                        _distKm      = eta2.totalKm
                        _timeSec     = eta2.totalSec
                    } else {
                        _stepTimeSec = Math.max(0, _stepTimeSec - dtS)
                        _distKm      = Math.max(0, _distKm      - dKm)
                        _timeSec     = Math.max(0, _timeSec     - dtS)
                    }
                    _lastDistMs = ms
                }
                // Avanzar snap a lo largo del shape activo (revShape en revMode)
                var shape3 = revMode ? revShape : (routeData && routeData.shape)
                if (shape3 && shape3.length > 1 && dKm > 0) {
                    var cosL3 = Math.cos(snapLat * Math.PI / 180)
                    var dM3 = dKm * 1000
                    var si3 = _snapShapeI, sf3 = _snapShapeFrac
                    while (dM3 > 0.01 && si3 < shape3.length - 1) {
                        var sp0i = shape3[si3], sp1i = shape3[si3 + 1]
                        var sgL = (sp1i[1] - sp0i[1]) * 111319
                        var sgN = (sp1i[0] - sp0i[0]) * 111319 * cosL3
                        var sgLen = Math.sqrt(sgL * sgL + sgN * sgN)
                        if (sgLen < 0.01) { si3++; sf3 = 0; continue }
                        var avail3 = sgLen * (1.0 - sf3)
                        if (dM3 < avail3) { sf3 += dM3 / sgLen; dM3 = 0 }
                        else { dM3 -= avail3; si3++; sf3 = 0 }
                    }
                    _snapShapeI = si3; _snapShapeFrac = sf3
                    var spA = shape3[si3], spB = shape3[Math.min(si3 + 1, shape3.length - 1)]
                    snapLat = spA[1] + sf3 * (spB[1] - spA[1])
                    snapLon = spA[0] + sf3 * (spB[0] - spA[0])
                }
            }
        }
        _lastTickMs = ms
    }

    onHasFixChanged: { if (!hasFix) { _stableFixes = 0; _realFix = false } }

    onRouteDataChanged: {
        _step = 0; _offCount = 0; _status = "nav"; _arrivedEmitted = false; _completedLegs = 0; _lastUpdateMs = 0
        _legArrivalPending = false; _legArrivalArmed = true; _legDismissMs = 0; _legStoppedMs = 0
        _navStartMs = Date.now()
        if (routeData && routeData.shape && routeData.shape.length > 0) {
            _realLat = routeData.shape[0][1]
            _realLon = routeData.shape[0][0]
        } else {
            _realLat = gpsLat; _realLon = gpsLon
        }
        // No llamar update() aquí: evita que arrived() se dispare síncronamente
        // dentro de _startNavigation antes del primer tick GPS real.
        // El primer handleTick(isReal=true) llama update() con la posición real.
    }

    // ── UI ─────────────────────────────────────────────────────────────────
    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        Rectangle { width: parent.width; height: units.gu(0.12); color: "#29B6F6" }

        // Aviso dirección contraria
        Rectangle {
            visible: bar._wrongDir && bar.navActive
            width: parent.width; height: bar._wrongDir ? units.gu(3.5) : 0
            color: "#C62828"
            Row {
                anchors.centerIn: parent; spacing: units.gu(1)
                Label { text: "⟵"; color: "white"; font.pixelSize: ts(2.5); font.bold: true }
                Label { text: i18n.tr("SENTIDO CONTRARIO"); color: "white"
                        font.pixelSize: ts(2.1); font.bold: true }
                Label { text: "⟶"; color: "white"; font.pixelSize: ts(2.5); font.bold: true }
            }
        }

        // Maniobra / estado
        Rectangle {
            id: instrRect
            width: parent.width
            height: !bar.navActive ? (showReloadDest ? ts(20) : ts(15))
                    : Math.max(ts(13), instrContentCol.implicitHeight + ts(2.5))
            Behavior on height { NumberAnimation { duration: 200 } }
            color: "transparent"

            // Panel velocidad/precisión (derecha) — oculto en landscape (lo muestra mapSpeedOverlay)
            Item {
                id: speedPanel
                visible: !bar.isLandscape
                anchors { right: parent.right; rightMargin: units.gu(0.5)
                          top: parent.top; bottom: parent.bottom }
                width: bar.isLandscape ? 0 : units.gu(13)

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                              topMargin: units.gu(1); bottomMargin: units.gu(1) }
                    width: units.gu(0.1); color: "#40FFFFFF"
                }

                Column {
                    anchors.centerIn: parent; spacing: 0
                    visible: bar.hasFix && !bar.searchingGps
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: NavSearch.formatSpeed(bar.gpsSpeedKmh, bar.imperial).toString()
                        color: bar._speedOver && bar._effVerified ? "#E53935"
                             : bar._speedOver                      ? "#FF6F00"
                             : "white"
                        font.pixelSize: units.gu(5.5); font.bold: true
                        lineHeight: 0.9
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: NavSearch.speedUnit(bar.imperial)
                        color: "white"; opacity: 0.75
                        font.pixelSize: ts(2.2); font.bold: true
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: bar.posAccuracy >= 0
                        text: "±" + bar.posAccuracy.toFixed(0) + " m"
                        color: "white"; opacity: 0.75; font.pixelSize: ts(1.75)
                    }
                }
                Column {
                    anchors.centerIn: parent; spacing: units.gu(0.1)
                    visible: bar.searchingGps
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "⟳"; color: "white"
                        font.pixelSize: units.gu(3.5)
                        RotationAnimation on rotation {
                            running: bar.searchingGps
                            loops: Animation.Infinite; from: 0; to: 360; duration: 2000
                        }
                    }
                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "GPS"; color: "white"; opacity: 0.75
                        font.pixelSize: ts(2.0); font.bold: true
                    }
                }
            }

            // Modo mapa: "Iniciar navegación" [+ "Reiniciar navegación"]
            Item {
                visible: !bar.navActive
                anchors { left: parent.left; right: bar.isLandscape ? parent.right : speedPanel.left
                          top: parent.top; bottom: parent.bottom
                          leftMargin: units.gu(2); rightMargin: units.gu(1) }

                // "Reiniciar navegación" — franja fija en la parte inferior
                Item {
                    id: reloadItem
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: bar.showReloadDest ? units.gu(5) : 0
                    clip: true
                    Row {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left }
                        spacing: units.gu(1.5)
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⟳"
                            color: "#29B6F6"; font.pixelSize: ts(3.2); font.bold: true
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: i18n.tr("Reiniciar navegación")
                            color: "#B0BEC5"; font.pixelSize: ts(2.5); font.bold: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: bar.showReloadDest
                        onClicked: bar.reloadDestRequested()
                    }
                }

                // "Iniciar navegación" — centrado en el espacio restante
                Item {
                    anchors { left: parent.left; right: parent.right
                              top: parent.top; bottom: reloadItem.top }
                    Row {
                        anchors { verticalCenter: parent.verticalCenter; left: parent.left }
                        spacing: units.gu(1.5)
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "▶"
                            color: "#4CAF50"; font.pixelSize: ts(4.0); font.bold: true
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: units.gu(0.3)
                            Label {
                                text: i18n.tr("Iniciar navegación")
                                color: "white"; font.pixelSize: ts(2.75); font.bold: true
                            }
                            Label {
                                visible: !bar.hasFix
                                text: i18n.tr("Buscando GPS…")
                                color: "#FFA000"; font.pixelSize: ts(1.75)
                            }
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: bar.startNavRequested() }
                }
            }

            // Modo navegación: instrucciones
            Row {
                id: instructionRow
                visible: bar.navActive
                anchors { fill: parent; leftMargin: units.gu(2)
                          rightMargin: bar.isLandscape ? units.gu(1) : units.gu(14.5) }
                spacing: units.gu(1.5)

                // Icono de maniobra o estado
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: ts(5); height: ts(5)

                    // Icono normal de maniobra
                    Label {
                        anchors.centerIn: parent
                        visible: bar._status === "nav"
                        text: {
                            var man = bar.routeData ? bar.routeData.maneuvers : null
                            if (!man || man.length === 0) return "↑"
                            var idx = Math.min(bar._step + 1, man.length - 1)
                            return NavSearch.maneuverIcon(man[idx].type)
                        }
                        color: "#29B6F6"; font.pixelSize: ts(5.0); font.bold: true
                    }
                    // Advertencia fuera de ruta
                    Label {
                        anchors.centerIn: parent
                        visible: bar._status === "offroute"
                        text: "⚠"; color: "#FFA726"; font.pixelSize: ts(4.4)
                    }
                    // Spinner recalculando
                    Label {
                        anchors.centerIn: parent
                        visible: bar._status === "rerouting"
                        text: "↻"; color: "#29B6F6"; font.pixelSize: ts(4.4)
                        RotationAnimation on rotation {
                            running: bar._status === "rerouting"
                            loops: Animation.Infinite; from: 0; to: 360; duration: 1000
                        }
                    }
                }

                Column {
                    id: instrContentCol
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - ts(7)
                    spacing: units.gu(0.3)

                    // Distancia al próximo giro
                    Label {
                        width: parent.width
                        visible: bar._status === "nav"
                        text: NavSearch.formatDist(bar._stepDistKm, bar.imperial)
                        color: "#29B6F6"; font.pixelSize: ts(2.75); font.bold: true
                    }

                    // Instrucción principal
                    Label {
                        width: parent.width
                        text: {
                            if (bar._status === "rerouting") return i18n.tr("Recalculando ruta…")
                            if (bar._status === "offroute")  return i18n.tr("Fuera de ruta")
                            var man = bar.routeData ? bar.routeData.maneuvers : null
                            if (!man || man.length === 0) return ""
                            var mv = man[Math.min(bar._step + 1, man.length - 1)]
                            return mv.verbal_pre_transition_instruction || mv.instruction || ""
                        }
                        color: bar._status === "offroute"  ? "#FFA726" :
                               bar._status === "rerouting" ? "#B0BEC5" : "white"
                        font.pixelSize: ts(2.4); font.bold: true
                        wrapMode: Text.WordWrap
                    }

                    // Siguiente instrucción
                    Label {
                        width: parent.width
                        visible: bar._status === "nav"
                        text: {
                            var man = bar.routeData ? bar.routeData.maneuvers : null
                            if (!man || man.length === 0 || bar._step + 2 >= man.length) return ""
                            var nx = man[bar._step + 2]
                            return "▸ " + (nx.verbal_pre_transition_instruction || nx.instruction || "")
                        }
                        color: "#B0BEC5"; font.pixelSize: ts(1.9)
                        elide: Text.ElideRight
                    }

                    // Indicador de pausa
                    Label {
                        visible: bar.paused
                        text: "⏸  " + i18n.tr("Ruta pausada")
                        color: "#FFA726"; font.pixelSize: ts(2.5); font.bold: true
                    }
                }
            }

            MouseArea {
                anchors { left: parent.left; right: parent.right
                          top: parent.top; bottom: parent.bottom }
                visible: bar.navActive
                onClicked: bar.instructionsRequested()
            }
        }

        // Barra ETA — destino intermedio (si hay) + ruta entera
        Rectangle {
            visible: bar.navActive
            width: parent.width
            height: bar.navActive ? (_hasNextWp ? ts(9.5) : ts(7.0)) : 0
            Behavior on height { NumberAnimation { duration: 200 } }
            color: "#1C1C2E"
            Row {
                anchors { fill: parent; leftMargin: units.gu(2); rightMargin: units.gu(1.5) }
                spacing: units.gu(1)

                Column {
                    id: etaCol
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: units.gu(0.7)
                    width: parent.width - stopBtn.width - units.gu(2)

                    // Próxima parada (solo con múltiples destinos)
                    Item {
                        visible: _hasNextWp
                        width: etaCol.width; height: ts(2.4)
                        Row {
                            anchors { left: parent.left; right: nextDist.left; rightMargin: units.gu(0.8) }
                            spacing: units.gu(0.5)
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: bar._nextWpName
                                color: "#B0BEC5"; font.pixelSize: ts(1.75); font.bold: true
                                elide: Text.ElideRight
                                width: {
                                    var wps = bar.navWaypoints
                                    var td = wps && wps[bar._completedLegs] ? wps[bar._completedLegs].todos : null
                                    return (td && td.length > 0) ? parent.width - todoBadge.width - units.gu(0.5) : parent.width
                                }
                            }
                            Rectangle {
                                id: todoBadge
                                anchors.verticalCenter: parent.verticalCenter
                                visible: {
                                    var wps = bar.navWaypoints
                                    var td = wps && wps[bar._completedLegs] ? wps[bar._completedLegs].todos : null
                                    return td ? td.length > 0 : false
                                }
                                width: units.gu(3.5); height: units.gu(1.8); radius: height / 2
                                color: "#1E3A5F"
                                Label {
                                    anchors.centerIn: parent
                                    text: {
                                        var wps = bar.navWaypoints
                                        var td = wps && wps[bar._completedLegs] ? wps[bar._completedLegs].todos : null
                                        if (!td) return ""
                                        var p = 0; for (var i = 0; i < td.length; i++) if (!td[i].done) p++
                                        return "📝" + p
                                    }
                                    color: "#29B6F6"; font.pixelSize: ts(1.2)
                                }
                            }
                        }
                        Label {
                            id: nextDist
                            anchors.right: parent.right
                            text: NavSearch.formatDist(bar._legDistKm, bar.imperial) + "  ·  " + NavSearch.formatTime(bar._legTimeSec) + "  ·  " + NavSearch.formatEta(bar._legTimeSec)
                            color: "#B0BEC5"; font.pixelSize: ts(2.0)
                        }
                    }

                    // Destino final
                    Item {
                        width: etaCol.width; height: ts(2.4)
                        Label {
                            anchors { left: parent.left; right: totalDist.left; rightMargin: units.gu(0.8) }
                            text: bar._finalName
                            color: "#B0BEC5"; font.pixelSize: ts(1.75); font.bold: true
                            elide: Text.ElideRight
                        }
                        Label {
                            id: totalDist
                            anchors.right: parent.right
                            text: NavSearch.formatDist(bar._distKm, bar.imperial) + "  ·  " + NavSearch.formatTime(bar._timeSec) + "  ·  " + NavSearch.formatEta(bar._timeSec)
                            color: "#B0BEC5"; font.pixelSize: ts(2.0)
                        }
                    }
                }

                Rectangle {
                    id: stopBtn
                    anchors.verticalCenter: parent.verticalCenter
                    width: ts(9.5); height: ts(5.5); radius: units.gu(0.6)
                    color: "#B71C1C"
                    Label { anchors.centerIn: parent; text: "■ " + i18n.tr("Parar")
                            color: "white"; font.pixelSize: ts(2.1); font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: bar.stopNavigation() }
                }
            }
        }
    }
}
