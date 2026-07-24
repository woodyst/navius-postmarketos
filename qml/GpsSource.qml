import QtQuick 2.7

// Capa de abstracción GPS.
//
// Ticks primarios (isReal=true):
//   "gps"  → fix de hardware (satModel)
//   "sim"  → waypoint de ruta de simulación
//
// Ticks interpolados (isReal=false, source="interp"):
//   sim + ruta  → lerp tiempo-paramétrico entre waypoints; heading desde _headRad (fixes reales)
//   gps + ruta  → dead-reckoning en dirección _headRad (soporta marcha atrás)
//   sin ruta    → dead-reckoning recto con aceleración y tasa de giro
Item {
    id: gps
    visible: false; width: 0; height: 0

    // ── Inputs ────────────────────────────────────────────────────────────────
    property var    satModel:        null   // SatelliteModel QObject
    property var    simRoute:        []     // [{lat,lon,spd}] — ruta a 1 s/punto
    property int    simSpeedBias:       0      // -100..+500 %
    property int    commSpeedLimitKmh:  0      // límite comunitario activo (0 = ninguno)
    property int    simMinSpeedKmh:  0      // saltar pasos lentos en sim
    property bool   simMode:         false
    property bool   simPaused:       false
    property bool   simSignalLost:   false
    property bool   manualActive:    false
    property real   manualLat:       0
    property real   manualLon:       0
    property real   interpolationHz: 20
    property var    routeShape:      null   // [[lon,lat]] shape activo; null = sin ruta
    onRouteShapeChanged: {
        routeShapeLegEnd = -1
        _shapeIdx = 0; _shapeFrac = 0; _fixShapeIdx = 0; _fixShapeFrac = 0
        _curShapeIdx = 0; _curShapeFrac = 0; _corrRemM = 0; _interpSpeedMs = 0; _interpMs = 0; _snapDone = false
        _lastRealTickPos = null; _prevRealTickPos = null
        _lastRealTickHeadingRad = 0; _prevRealTickHeadingRad = 0
        _lastRealTickSpeedMs = 0;  _prevRealTickSpeedMs = 0
        _lastTickPos = null; _lastTickHeadingRad = 0; _lastTickSpeedMs = 0
        _lastMapVehiclePos = null; _lastMapVehicleHeadingRad = 0; _lastMapVehicleSpeedMs = 0
    }

    // ── Outputs ───────────────────────────────────────────────────────────────
    signal gpsTick(real lat, real lon, real speedKmh, real headRad,
                   bool hasFix, bool isReal, real timestampMs, string source)

    property real   lat:          0
    property real   lon:          0
    property real   speedKmh:     0
    property real   realSpeedKmh: 0
    property real   headRad:      0
    property bool   hasFix:       false
    property bool   lastIsReal:   false
    property string lastSource:   ""
    property real   accuracy:     -1

    property int  simIdx:      0
    property bool simFinished: true

    // ── Inputs ────────────────────────────────────────────────────────────────
    property bool   useHardwareSpeed: true  // true → velocidad Doppler del chip; false → d/dt posiciones
    property bool   smoothGps:       true  // false → solo fixes reales (drEnabled)
    property bool   snapToRouteEnabled: true  // ajustar posición y interpolación al shape de ruta
    property real   snapDistM:           8    // distancia máx de snap (m); si GPS más lejos → DR libre
    property int    routeShapeLegEnd:   -1   // índice final del leg activo en routeShape; -1 = sin límite
    property bool   gpsFailEnabled:  false
    property real   gpsFailProb:     5.00
    property real   gpsFailDist:     50
    property int    gpsFailTicks:    3

    property int    _failTicksLeft:  0  // ticks de fallo GPS restantes
    property real   _failLat:        0  // posición desplazada durante el fallo
    property real   _failLon:        0
    property real   _drBaseLat:      0  // base espacial para DR de ticks interpolados
    property real   _drBaseLon:      0
    property int    _turnConsec:     0  // ticks consecutivos girando en la misma dirección
    property int    _turnDirPrev:    0  // dirección del último giro (-1, 0, 1)

    // ── Control manual del vehículo ───────────────────────────────────────────
    property bool   manualDriveMode:  false  // activado desde UI de control
    property bool   driveAccel:       false  // botón aceleración pulsado
    property bool   driveBrake:       false  // botón freno/marcha atrás pulsado
    property bool   driveTurnLeft:    false  // giro izquierda pulsado
    property bool   driveTurnRight:   false  // giro derecha pulsado
    property real   _driveSpeedMs:    0      // velocidad actual (m/s, negativo = marcha atrás)
    readonly property real _driveMaxFwdMs:  138.9  // ~500 km/h máx adelante
    readonly property real _driveMaxRevMs:   13.9  // ~50 km/h máx atrás
    readonly property real _driveAccelMss:    9.0   // m/s² aceleración
    readonly property real _driveBrakeMss:   15.0   // m/s² frenada
    readonly property real _driveTurnRps:     0.5   // rad/s tasa de giro
    readonly property real _driveDecelMss:    1.5   // m/s² deceleración natural (sin uso)

    // Posición por defecto: emite ticks en estas coordenadas desde el arranque
    // hasta que cualquier otro sistema (GPS real, sim GPS, manual) establezca _p2.
    // Vinculado desde Main.qml a appSettings.lastLat/lastLon para que no salte a Madrid
    // si ya hay una posición guardada de la sesión anterior.
    property real defaultLat: 40.4168   // centro de Madrid (override desde Main.qml)
    property real defaultLon: -3.7038

    // ── Estado interno ────────────────────────────────────────────────────────
    property var  _p0: null
    property var  _p1: null
    property var  _p2: null
    property real _speedMs:       0
    property real _accelMss:      0
    property real _headRad:       0
    property real _headRateRads:  0   // tasa de giro rad/s (del buffer de fixes)
    property bool _hasFix:        false

    // Sim tiempo-paramétrico: base del último tick primario
    property real _simBaseMs:       0    // wall clock del tick primario
    property int  _simBaseIdx:      0    // simIdx en ese momento
    property real _simDistM:        0    // distancia recorrida desde inicio de ruta (m)
    property var  _simRouteCumDistM: null // distancias acumuladas del simRoute (m)
    property real _lastSimPrimaryMs: 0   // timestamp del último tick primario
    property bool _simHasTs:        false // true cuando simRoute lleva campo ts (track grabado)
    property real _simStartMs:      0    // wall clock cuando arrancó la sim (para modo ts)

    // GPS real en ruta: posición actual en el shape
    property int  _shapeIdx:      0
    property real _shapeFrac:     0
    // Posición del shape en el último fix real (base para interpolación)
    property int  _fixShapeIdx:   0
    property real _fixShapeFrac:  0
    // Snap del último tick real al shape — misma fuente que _fixShapeIdx/_fixShapeFrac,
    // expuesto para que Main.qml lo use en display y sea consistente con los interpolados.
    property real snapLat:        0
    property real snapLon:        0
    // Timestamp del último tick real (GPS o sim), capturado antes de cualquier proceso.
    // Referencia temporal consistente para todos los ticks interpolados del intervalo.
    property real _realTickMs:    0
    // Corrección suave de posición: decaimiento exponencial (tau=1.0s, cap mín 2 m/s).
    // Signo: + interp detrás del snap GPS (avanzar); − interp delante (retroceder).
    property real _corrRemM:  0   // distancia pendiente de corrección (m, con signo)
    property real _interpSpeedMs: 0 // velocidad integrada por ticks interp
    property real _interpMs:  0   // wall clock del último tick interp; NO se toca en ticks reales
    property bool _snapDone:   false // true tras el primer snap al iniciar ruta
    property bool _snapActive: false // true cuando snap aplica en el último tick real
    // Posición del shape en el tick actual (real o interp) — usada por _routeAheadPoint
    property int  _curShapeIdx:   0
    property real _curShapeFrac:  0

    // ── Nuevo pipeline GPS ────────────────────────────────────────────────────
    property var  routeShapeSpeedKmh: null   // array paralelo a routeShape, vel. Valhalla por segmento
    property bool simPosOnly:         false  // replay ruta sin navegación activa (DR path)
    property var  simRoutePoints:     null   // ref a root.simRoute, para cálculo de heading anticipado
    property var  simRouteSpeedKmh:   null   // array paralelo a simRoutePoints, vel. Valhalla por punto
    property bool bearingDebug:       false  // traza bearing mapa
    property int  _lastBearingLogIdx: -1     // evita trazas duplicadas en ticks interpolados
    property var  bisectorMinPt:      null   // {lat,lon} punto más a la IZQUIERDA (rojo)
    property var  bisectorMaxPt:      null   // {lat,lon} punto más a la DERECHA (azul)
    property var  bisectorCtrPt:      null   // {lat,lon} punto central sobre la ruta (verde)

    // Modo de interpolación (selector debug en PreferencesPanel):
    //   0 = _idealInterpPos  (velocidad constante)
    //   1 = _accelInterpPos  (con aceleración)
    //   2 = _vhRatioInterpPos (ratio GPS/Valhalla)
    property real interpBlendDistM:      5.0   // metros de zona de transición en vértices (giro en 2× = 10 m centrados)
    // Todas las correcciones de interpolación ON por defecto. En debug se pueden
    // togglear desde el panel; fuera de debug no hay panel → quedan siempre activas.
    property bool interpUseIdeal:        true  // componente v×dt en distancia (base)
    property bool interpUseAccel:        true  // componente ½×a×dt² en distancia
    property bool interpUseVhRatio:      true  // ajusta v con ratio GPS/Valhalla antes de aplicar
    property bool interpUseHeadingBlend: true  // _vehicleHeadingRad en tick interp con ruta
    property bool interpUseAccelHeading: true  // _accelInterpHeading en tick interp sin ruta

    property real mapHeadRad: 0  // heading del mapa: solo ticks reales, nunca look-ahead interp

    // Último tick real
    property var  _lastRealTickPos:        null   // {lat, lon, idx, frac, ms}
    property var  _prevRealTickPos:        null   // {lat, lon, idx, frac, ms}
    property real _lastRealTickHeadingRad: 0
    property real _prevRealTickHeadingRad: 0
    property real _lastRealTickSpeedMs:    0
    property real _prevRealTickSpeedMs:    0

    // Último tick emitido (real o interpolado)
    property var  _lastTickPos:        null   // {lat, lon, idx, frac}
    property real _lastTickHeadingRad: 0
    property real _lastTickSpeedMs:    0

    // Última posición renderizada en el mapa
    property var  _lastMapVehiclePos:        null   // {lat, lon, idx, frac}
    property real _lastMapVehicleHeadingRad: 0
    property real _lastMapVehicleSpeedMs:    0

    // ── Dead reckoning (GPS impreciso o perdido) ──────────────────────────────
    // drActive se pone a true cuando se detecta una posición GPS inválida
    // (salto brusco o pérdida de fix) mientras hay ruta activa. En ese estado
    // se emiten ticks sintéticos source="dr" avanzando por el shape de la ruta
    // con la velocidad Valhalla × ratio hasta que GPS recupera 3 fixes válidos.
    property bool drActive:     false  // true = simulando trayecto por ruta
    property int  _drBadCount:  0      // fixes malos consecutivos
    property int  _drGoodCount: 0      // fixes buenos consecutivos (recuperación)
    property real _drSpeedMs:   0      // velocidad al entrar en DR (m/s), ancla/objetivo
    property real _drSpeedRunMs: 0     // velocidad DR evolutiva (modulada por accel calibrado)
    property var  _drRecovFix:  null   // {lat,lon,ms} último candidato de recuperación

    // ── DR sin ruta / desvío (tile caché como shape temporal) ─────────────────
    property var  tileCache:    null   // NavTileCache — conectado desde Main.qml
    property var  _drNrShape:   null   // [[lon,lat]] shape temporal (DR sin ruta o tras desvío)
    property int  _drNrIdx:     0
    property real _drNrFrac:    0.0
    property bool _drLeftRoute: false  // true tras desvío detectado: seguir tile caché, no la ruta
    property real _drDeviateMs: 0      // tiempo sostenido (s) con heading IMU divergente del shape
    property real _drLastDeviateAnchorMs: 0  // wall-clock del último intento de reanclaje por desvío

    // ── IMU (giroscopio + acelerómetro) ────────────────────────────────────────
    // La posición DR SIEMPRE sigue un shape (ruta o tile caché, ver _drSimulateTick).
    // El IMU aporta dos señales sobre ese shape, no la posición:
    //   - heading calibrado: si diverge sostenidamente del heading del shape seguido,
    //     se interpreta como desvío real y se re-ancla sobre el tile caché
    //   - calibratedAccel(): modula la velocidad DR con magnitud similar a la real
    // Solo como último recurso, si no hay NI ruta NI tiles cerca, se usa la posición
    // libre integrada por IMU (imu.advance/imuLat/imuLon) para no congelar el icono.
    property var  imu:          null   // NavImu — conectado desde Main.qml

    // ── Dirección inversa (solo simMode+debugMode) ────────────────────────────
    property var  revRoute:    null  // [{lat,lon,spd}] ruta inversa ~100 m
    property var  revShape:    null  // [[lon,lat],...] formato NavBar, generado al iniciar revMode
    property int  _revIdx:     0
    property bool revMode:      false
    property bool revFinished:  false
    property real _revStartMs:  0    // wall-clock ms al activar revMode

    // ── GPS real ──────────────────────────────────────────────────────────────
    Connections {
        id: satConn
        target: gps.satModel
        enabled: !gps.simMode && !gps.manualActive && !gps.manualDriveMode && gps.satModel !== null
        function onPosition_changed() {
            var m = gps.satModel
            gps.accuracy = m.pos_accuracy
            gps._onRealGpsTick(m.pos_lat, m.pos_lon, m.pos_has_fix, m.pos_speed_kmh, Date.now())
        }
    }

    // Emite posición estática (speed=0) cuando simMode está activo pero sin ruta en curso.
    Timer {
        id: simParkedTimer
        interval: 500; repeat: true
        running: gps.simMode && !gps.manualActive && !gps.manualDriveMode && gps._p2 !== null
                 && !gps.revMode
                 && (gps.simFinished || !gps.simRoute || gps.simRoute.length < 2)
        onTriggered: {
            gps._speedMs     = 0
            gps.realSpeedKmh = 0
            gps._emit(gps._p2.lat, gps._p2.lon, 0, gps._headRad,
                      gps._hasFix, true, Date.now(), "sim")
        }
    }

    // Posición por defecto: ticks a 1 Hz desde el arranque hasta que cualquier
    // sistema (GPS real, sim o manual) establezca _p2.
    Timer {
        id: defaultPosTimer
        interval: 1000; repeat: true
        running: !gps.manualActive && !gps.manualDriveMode
                 && gps._p2 === null && !gps.simSignalLost
        onTriggered: {
            gps._hasFix = true
            gps._emit(gps.defaultLat, gps.defaultLon, 0, 0, true, true, Date.now(), "sim")
        }
        Component.onCompleted: Qt.callLater(function() {
            if (running) {
                gps._hasFix = true
                gps._emit(gps.defaultLat, gps.defaultLon, 0, 0, true, true, Date.now(), "sim")
            }
        })
    }

    // ── Simulación: timer primario ────────────────────────────────────────────
    Timer {
        id: simPrimaryTimer
        interval: Math.round(1000 / Math.max(0.1, 1.0 + gps.simSpeedBias / 100.0))
        repeat:   true
        running:  gps.simMode && !gps.simPaused && !gps.manualActive && !gps.manualDriveMode
                  && ((!gps.simFinished && gps.simRoute && gps.simRoute.length > 1)
                      || gps.revMode)
        onTriggered: gps._simAdvance()
    }

    // ── Control manual: timer 1 Hz (mismo cadencia que GPS real) ─────────────
    Timer {
        id: driveTimer
        interval: 1000; repeat: true
        running: gps.manualDriveMode && gps._p2 !== null && !gps.manualActive
        onTriggered: gps._driveAdvance()
    }

    // ── DR con GPS real: timer independiente ──────────────────────────────────
    // _drSimulateTick() normalmente se dispara reactivamente desde _onRealGpsTick.
    // Pero en un túnel real sin cobertura, el proveedor de localización puede dejar
    // de emitir ticks por completo (ni siquiera "sin fix") — sin este timer, DR se
    // queda sin llamadas y la posición se congela en vez de seguir avanzando.
    Timer {
        id: drRealTimer
        interval: 1000; repeat: true
        running: gps.drActive && !gps.simMode && !gps.manualActive && !gps.manualDriveMode
        onTriggered: gps._drSimulateTick(Date.now())
    }

    // ── Vigía de silencio GPS: activa DR aunque no llegue NINGÚN tick ──────────
    // _onRealGpsTick() (y por tanto la detección de fix inválido) solo se ejecuta
    // cuando el proveedor de localización emite algo. En un túnel real puede dejar
    // de emitir CUALQUIER actualización (ni siquiera "sin fix") — en ese caso
    // _onRealGpsTick nunca se vuelve a llamar y DR nunca llega a activarse, aunque
    // drRealTimer (arriba) ya esté preparado para mantenerlo vivo una vez activo.
    // Este timer comprueba directamente cuánto hace del último tick real bueno.
    Timer {
        id: gpsStaleWatchdog
        interval: 1000; repeat: true
        running: !gps.simMode && !gps.manualActive && !gps.manualDriveMode && !gps.drActive
        onTriggered: {
            if (gps._realTickMs > 0 && (Date.now() - gps._realTickMs) > 3000)
                gps._activateDr()
        }
    }

    // ── Interpolación ─────────────────────────────────────────────────────────
    Timer {
        id: interpTimer
        interval: Math.round(1000 / Math.max(1, gps.interpolationHz))
        repeat:   true
        running:  gps.smoothGps && gps._p2 !== null && gps._speedMs > 0.05
                  && !(gps.simMode && !gps.manualDriveMode && gps.simFinished)
        onTriggered: gps._onInterpTick()
    }

    // ── GPS real: tick primario ───────────────────────────────────────────────
    // Activa drActive si no lo está ya (misma lógica que usaba _onRealGpsTick
    // inline). Extraída para poder llamarla también desde gpsStaleWatchdog,
    // que activa DR aunque no llegue NINGÚN tick del proveedor de localización
    // (ni siquiera "sin fix") — ver comentario en gpsStaleWatchdog.
    function _activateDr() {
        if (drActive || _lastRealTickPos === null || _speedMs <= 1.0) return
        _drSpeedRunMs = _speedMs
        _drLeftRoute  = false
        _drDeviateMs  = 0
        _drLastDeviateAnchorMs = 0
        if (routeShape && routeShape.length > 1) {
            drActive = true; _drSpeedMs = _speedMs
        } else {
            var _nrs = _buildDrNrShape(_lastRealTickPos.lat, _lastRealTickPos.lon)
            if (_nrs) {
                _drNrShape = _nrs.coords; _drNrIdx = _nrs.idx; _drNrFrac = _nrs.frac
                drActive   = true; _drSpeedMs = _speedMs
            } else {
                drActive = true; _drSpeedMs = _speedMs  // sin ruta ni tiles: último recurso, IMU libre
            }
        }
        if (drActive && imu)
            imu.start(_headRad, _lastRealTickPos.lat, _lastRealTickPos.lon)
    }

    function _onRealGpsTick(pLat, pLon, pHasFix, hwSpeedKmh, ms) {
        // ── Detección de fix inválido ─────────────────────────────────────────
        // _p2 aún apunta al último fix BUENO (no se actualiza hasta el final).
        var _isBad = !pHasFix
        if (!_isBad && _p2 !== null) {
            var _dtJ = (ms - _p2.ms) / 1000.0
            if (_dtJ > 0.1 && _dtJ < 10.0) {
                var _jumpDist = _haversineM(_p2.lat, _p2.lon, pLat, pLon)
                // Salto: posición nueva > 2.5× el desplazamiento esperado (con mín 30 m)
                _isBad = _jumpDist > Math.max(30.0, _speedMs * _dtJ * 2.5)
            }
        }

        // ── Gestión de modo DR ────────────────────────────────────────────────
        if (_isBad) {
            _drBadCount++; _drGoodCount = 0; _drRecovFix = null
            if (!drActive && _drBadCount >= 1) _activateDr()
            if (drActive) { _drSimulateTick(ms); return }
        } else if (drActive) {
            // Recuperación: esperar 3 fixes buenos consecutivos sin salto entre ellos
            var _recovOk = true
            if (_drRecovFix !== null) {
                var _dtR = (ms - _drRecovFix.ms) / 1000.0
                if (_dtR > 0.1 && _dtR < 10.0)
                    _recovOk = _haversineM(_drRecovFix.lat, _drRecovFix.lon, pLat, pLon)
                                <= Math.max(30.0, _speedMs * _dtR * 2.5)
            }
            _drRecovFix = {lat: pLat, lon: pLon, ms: ms}
            if (_recovOk) {
                _drGoodCount++
                if (_drGoodCount < 3) { _drSimulateTick(ms); return }
                // 3 fixes buenos → salir de DR
                drActive = false; _drBadCount = 0; _drGoodCount = 0; _drRecovFix = null
                _p0 = null; _p1 = null  // fixes anteriores al DR no son válidos para v/a
                _drNrShape = null; _drLeftRoute = false; _drDeviateMs = 0; _drSpeedRunMs = 0; _drLastDeviateAnchorMs = 0
                if (imu) imu.stop()
            } else {
                _drGoodCount = 0; _drRecovFix = null
                _drSimulateTick(ms); return
            }
        } else {
            _drBadCount = 0
        }

        // ── Procesamiento normal ──────────────────────────────────────────────
        _realTickMs = ms
        _p0 = _p1
        _p1 = _p2
        _p2 = {lat: pLat, lon: pLon, ms: ms}
        _hasFix = pHasFix

        if (_p1 !== null) {
            var dt1 = (_p2.ms - _p1.ms) / 1000.0
            if (dt1 > 0.1) {
                var d1   = _haversineM(_p1.lat, _p1.lon, _p2.lat, _p2.lon)
                var dtSpeed = d1 / dt1
                // Velocidad: Doppler hardware (más precisa a baja vel. y en aceleraciones)
                // o d/dt de posiciones según preferencia del usuario
                _speedMs = (useHardwareSpeed && hwSpeedKmh >= 0) ? hwSpeedKmh / 3.6 : dtSpeed
                _headRad = _bearing(_p1.lat, _p1.lon, _p2.lat, _p2.lon)
                // Alimentar el IMU con el heading GPS para auto-calibrar gyroScale/yawSign
                if (imu && _speedMs > 2.0) imu.feedGpsHeading(_headRad)
            }
        }
        if (_p0 !== null && _p1 !== null) {
            var dt0 = (_p1.ms - _p0.ms) / 1000.0
            if (dt0 > 0.001) {
                var d0 = _haversineM(_p0.lat, _p0.lon, _p1.lat, _p1.lon)
                var v0 = d0 / dt0
                var dtTotal = (_p2.ms - _p0.ms) / 1000.0
                _accelMss = Math.max(-5, Math.min(5, (_speedMs - v0) / dtTotal))
                // Alimentar el IMU con la aceleración GPS recién calculada para
                // auto-calibrar el eje/escala del acelerómetro (wF1/wF2)
                if (imu && _speedMs > 2.0) imu.feedGpsAccel(_accelMss)
                // Tasa de giro: cambio de rumbo entre los dos intervalos
                var hdg01  = _bearing(_p0.lat, _p0.lon, _p1.lat, _p1.lon)
                var dHdg   = _headRad - hdg01
                while (dHdg >  Math.PI) dHdg -= 2 * Math.PI
                while (dHdg < -Math.PI) dHdg += 2 * Math.PI
                _headRateRads = Math.max(-1.0, Math.min(1.0, dHdg / dtTotal))
            }
        }
        _applyTurnFilter()

        realSpeedKmh = _speedMs * 3.6
        _emit(pLat, pLon, _speedMs * 3.6, _headRad, pHasFix, true, ms, "gps")
    }

    // ── Simulación: tick primario ─────────────────────────────────────────────
    function _simAdvance() {
        if (revMode) { _revAdvance(); return }
        if (simFinished || !simRoute || simRoute.length < 2 || !_simRouteCumDistM) return

        var now  = Date.now()
        _realTickMs = now
        var bias = Math.max(0.1, 1.0 + simSpeedBias / 100.0)
        var dt   = _lastSimPrimaryMs > 0 ? Math.min((now - _lastSimPrimaryMs) / 1000.0, 5.0) : 0
        _lastSimPrimaryMs = now
        _simBaseMs = now

        var si = simIdx
        var posLat, posLon, emitSpd
        var oldHeadRad = _headRad

        if (_simHasTs) {
            // ── Modo timestamp: posicionamiento directo por tiempo grabado ─────
            // trackNow = timestamp grabado equivalente al momento actual real
            var trackNow = simRoute[0].ts + (now - _simStartMs) * bias

            if (trackNow >= simRoute[simRoute.length - 1].ts) {
                simFinished = true
                si = simRoute.length - 2
                posLat = simRoute[simRoute.length - 1].lat
                posLon = simRoute[simRoute.length - 1].lon
                _simDistM = _simRouteCumDistM[_simRouteCumDistM.length - 1]
            } else {
                // Búsqueda binaria del segmento activo por timestamp
                var lo = 0, hi = simRoute.length - 1
                while (hi - lo > 1) {
                    var mid = (lo + hi) >> 1
                    if (simRoute[mid].ts <= trackNow) lo = mid; else hi = mid
                }
                si = lo
                var dtMs = simRoute[si + 1].ts - simRoute[si].ts
                var frac = dtMs > 0 ? (trackNow - simRoute[si].ts) / dtMs : 0
                frac = Math.max(0, Math.min(1, frac))
                posLat = simRoute[si].lat + frac * (simRoute[si + 1].lat - simRoute[si].lat)
                posLon = simRoute[si].lon + frac * (simRoute[si + 1].lon - simRoute[si].lon)
                var segDistM = _haversineM(simRoute[si].lat, simRoute[si].lon,
                                           simRoute[si+1].lat, simRoute[si+1].lon)
                _simDistM = _simRouteCumDistM[si] + frac * segDistM
            }
            simIdx = si; _simBaseIdx = si

            // Velocidad: spd grabado por hardware (GPS Doppler) si disponible; si no, geométrica.
            // La velocidad Doppler es más estable que distancia/tiempo (menos ruido de posición).
            var prevSpeedMs = _speedMs
            if (!simFinished && si + 1 < simRoute.length) {
                if (simRoute[si].spd !== undefined) {
                    var interpSpd = simRoute[si].spd
                                  + frac * (simRoute[si + 1].spd - simRoute[si].spd)
                    _speedMs = interpSpd * bias / 3.6
                    emitSpd  = interpSpd * bias
                } else {
                    var segD = _haversineM(simRoute[si].lat, simRoute[si].lon,
                                           simRoute[si+1].lat, simRoute[si+1].lon)
                    var segT = (simRoute[si + 1].ts - simRoute[si].ts) / 1000.0
                    _speedMs = segT > 0.01 ? (segD / segT) * bias : 0
                    emitSpd  = _speedMs * 3.6
                }
            } else {
                _speedMs = 0
                emitSpd  = 0
            }
            realSpeedKmh = _speedMs * 3.6

            var dtAcc = Math.max(dt, 0.01)
            _accelMss = Math.max(-5, Math.min(5, (_speedMs - prevSpeedMs) / dtAcc))

        } else {
            // ── Modo velocidad: rutas Valhalla con spd en cada segmento ────────
            while (si < simRoute.length - 2 && _simRouteCumDistM[si + 1] <= _simDistM) si++
            var routeSpd = simRoute[si].spd
            var effSpd   = commSpeedLimitKmh > 0 ? commSpeedLimitKmh : routeSpd
            // simMinSpeedKmh: suelo para no arrastrarse en tramos Valhalla muy lentos
            // (declarada desde hace tiempo pero nunca aplicada — bug preexistente).
            if (simMinSpeedKmh > 0) effSpd = Math.max(effSpd, simMinSpeedKmh)
            var effSpdMs = effSpd * bias / 3.6

            _simDistM += effSpdMs * dt
            var totalDist = _simRouteCumDistM[_simRouteCumDistM.length - 1]
            if (_simDistM >= totalDist) { _simDistM = totalDist; simFinished = true }

            while (si < simRoute.length - 2 && _simRouteCumDistM[si + 1] <= _simDistM) si++
            simIdx = si; _simBaseIdx = si

            var segStart = _simRouteCumDistM[si]
            var segEnd   = _simRouteCumDistM[Math.min(si + 1, simRoute.length - 1)]
            var frac2    = segEnd > segStart ? (_simDistM - segStart) / (segEnd - segStart) : 0
            frac2 = Math.max(0, Math.min(1, frac2))
            posLat = simRoute[si].lat + frac2 * (simRoute[si + 1].lat - simRoute[si].lat)
            posLon = simRoute[si].lon + frac2 * (simRoute[si + 1].lon - simRoute[si].lon)

            var prevSpeedMs2 = _speedMs
            _speedMs = effSpdMs
            realSpeedKmh = effSpd * bias
            emitSpd = effSpd * bias

            var dtAcc2 = Math.max(dt, 0.01)
            _accelMss = Math.max(-5, Math.min(5, (_speedMs - prevSpeedMs2) / dtAcc2))
        }

        _p0 = _p1; _p1 = _p2
        _p2 = {lat: posLat, lon: posLon, ms: now, spd: _speedMs, hdg: _headRad}
        _hasFix = !simSignalLost
        // Heading del tick real desde la posición real anterior (ignora dónde acabaron los interpolados)
        if (_p1 !== null && _haversineM(_p1.lat, _p1.lon, posLat, posLon) > 1.0)
            _headRad = _bearing(_p1.lat, _p1.lon, posLat, posLon)
        // _headRateRads desde cambio real de posición, no desde segmento futuro de la ruta
        var _dHdgSim = _headRad - oldHeadRad
        while (_dHdgSim >  Math.PI) _dHdgSim -= 2 * Math.PI
        while (_dHdgSim < -Math.PI) _dHdgSim += 2 * Math.PI
        _headRateRads = Math.max(-1.0, Math.min(1.0, _dHdgSim / Math.max(dt, 0.01)))
        _applyTurnFilter()

        // Simulación de fallo GPS: desplazamiento aleatorio durante _failTicksLeft ticks
        var emitLat = posLat, emitLon = posLon
        if (gpsFailEnabled) {
            if (_failTicksLeft === 0 && Math.random() * 100 < gpsFailProb) {
                var perpAngle = _headRad + (Math.random() < 0.5 ? Math.PI / 2 : -Math.PI / 2)
                var displaced = _geoDest(posLat, posLon, perpAngle, gpsFailDist)
                _failLat = displaced.lat; _failLon = displaced.lon
                _failTicksLeft = gpsFailTicks
            } else if (_failTicksLeft > 0 && _p1 !== null) {
                _failLat += posLat - _p1.lat
                _failLon += posLon - _p1.lon
            }
            if (_failTicksLeft > 0) { _failTicksLeft--; emitLat = _failLat; emitLon = _failLon }
        } else {
            _failTicksLeft = 0
        }
        if (satModel) satModel.log_to_file(
            "REAL fix[" + _fixShapeIdx + "+" + _fixShapeFrac.toFixed(3) + "]" +
            " cur[" + _curShapeIdx + "+" + _curShapeFrac.toFixed(3) + "]" +
            " hdg=" + (_headRad * 180 / Math.PI).toFixed(1) +
            " pos=" + posLat.toFixed(6) + "," + posLon.toFixed(6) +
            " dist=" + _simDistM.toFixed(1))

        // ── DR en modo sim (mismo comportamiento que GPS real) ────────────────
        var _isBadSim = !_hasFix  // simSignalLost
        if (!_isBadSim && gpsFailEnabled && _failTicksLeft > 0 && _p1 !== null) {
            var _dtJs = (now - _p1.ms) / 1000.0
            if (_dtJs > 0.05 && _dtJs < 10.0) {
                var _jdSim = _haversineM(_p1.lat, _p1.lon, emitLat, emitLon)
                _isBadSim = _jdSim > Math.max(30.0, _speedMs * _dtJs * 2.5)
            }
        }
        if (_isBadSim) {
            _drBadCount++; _drGoodCount = 0
            if (!drActive && _drBadCount >= 1) _activateDr()
            if (drActive) { _drSimulateTick(now); return }
        } else if (drActive) {
            _drGoodCount++
            if (_drGoodCount < 3) { _drSimulateTick(now); return }
            drActive = false; _drBadCount = 0; _drGoodCount = 0; _drRecovFix = null
            _drNrShape = null; _drLeftRoute = false; _drDeviateMs = 0; _drSpeedRunMs = 0; _drLastDeviateAnchorMs = 0
            if (imu) imu.stop()
        } else {
            _drBadCount = 0
        }

        _emit(emitLat, emitLon, emitSpd, _headRad, _hasFix, true, now, "sim")
    }

    // ── Tick interpolado (cadencia: interpolationHz, configurable en preferencias) ─
    // dt_interp se mide del wall clock entre interp ticks (el timer QML en Ubuntu Touch
    // no garantiza la frecuencia nominal — render+GPS+TTS frenan los disparos). Lo que
    // arregla el stutter de 1 Hz no es fijar dt_interp, sino NO resetear _interpMs en
    // los ticks reales: así no aparece un frame corto post-real.
    // La velocidad _interpSpeedMs se integra por tick (no se queda congelada hasta
    function _onInterpTick() {
        if (_p2 === null || manualDriveMode) return
        if (_speedMs < 0.01) return
        var now = Date.now()
        var dt  = (_realTickMs > 0) ? (now - _realTickMs) / 1000.0 : 0
        if (dt < 0 || dt > 2.0) return

        var pLat, pLon, segHdg, v

        if (routeShape && routeShape.length > 1 && _lastRealTickPos !== null && !simPosOnly && _snapActive) {
            // Con ruta y snap activo: combinación acumulativa de los toggles activos
            var v = _lastRealTickSpeedMs
            if (interpUseVhRatio && routeShapeSpeedKmh
                    && _lastRealTickPos.idx < routeShapeSpeedKmh.length) {
                var vVh = routeShapeSpeedKmh[_lastRealTickPos.idx] / 3.6
                // Mismo suelo que en _simAdvance(): si no se aplica aquí, el ratio
                // v/vVh se satura en el tope ±3× cuando el suelo eleva v muy por
                // encima de la vVh original, y la interpolación va a saltos.
                if (simMinSpeedKmh > 0) vVh = Math.max(vVh, simMinSpeedKmh / 3.6)
                if (vVh > 0.1) {
                    var ratio = Math.max(0.1, Math.min(3.0, v / vVh))
                    v = vVh * ratio
                }
            }
            var distM = 0
            if (interpUseIdeal) distM += v * dt
            if (interpUseAccel) distM += 0.5 * _accelMsFromRealTicks() * dt * dt
            distM = Math.max(0, distM)
            var pos = _walkShape(_lastRealTickPos.idx, _lastRealTickPos.frac, distM)
            if (!pos) return

            pLat   = pos.lat
            pLon   = pos.lon
            v      = _lastRealTickSpeedMs
            segHdg = interpUseHeadingBlend
                     ? _vehicleHeadingRad(pos.idx, pos.frac, interpBlendDistM)
                     : _bearing(routeShape[pos.idx][1], routeShape[pos.idx][0],
                                routeShape[Math.min(pos.idx+1, routeShape.length-1)][1],
                                routeShape[Math.min(pos.idx+1, routeShape.length-1)][0])

            _curShapeIdx  = pos.idx
            _curShapeFrac = pos.frac
            _lastTickPos        = {lat: pLat, lon: pLon, idx: pos.idx, frac: pos.frac}
            _lastTickHeadingRad = segHdg
            _lastTickSpeedMs    = v
        } else {
            // Sin ruta: dead reckoning recto desde _drBaseLat/Lon
            v      = _speedMs
            var dR = _advanceDist(v, dt)
            segHdg = interpUseAccelHeading ? _accelInterpHeading(dt) : _headRad
            var dst = _geoDest(_drBaseLat, _drBaseLon, _headRad, dR)
            pLat   = dst.lat
            pLon   = dst.lon

            _lastTickPos        = {lat: pLat, lon: pLon, idx: 0, frac: 0}
            _lastTickHeadingRad = segHdg
            _lastTickSpeedMs    = v
        }

        _lastMapVehiclePos        = _lastTickPos
        _lastMapVehicleHeadingRad = segHdg
        _lastMapVehicleSpeedMs    = v
        _emit(pLat, pLon, v * 3.6, segHdg, _hasFix, false, now, "interp")
    }

    function _emit(eLat, eLon, eSpdKmh, eHdg, eHasFix, eIsReal, eMs, eSource) {
        lat        = eLat;    lon       = eLon
        speedKmh   = eSpdKmh; headRad  = eHdg
        hasFix     = eHasFix; lastIsReal = eIsReal
        lastSource = eSource
        if (eIsReal) {
            _drBaseLat = eLat; _drBaseLon = eLon
            if (routeShape && routeShape.length > 1) {
                _updateShapePos(eLat, eLon)
                _fixShapeIdx  = _shapeIdx
                _fixShapeFrac = _shapeFrac
                var _sp0 = routeShape[_fixShapeIdx]
                var _sp1 = routeShape[Math.min(_fixShapeIdx + 1, routeShape.length - 1)]
                snapLat = _sp0[1] + _fixShapeFrac * (_sp1[1] - _sp0[1])
                snapLon = _sp0[0] + _fixShapeFrac * (_sp1[0] - _sp0[0])

                // Decidir si el snap aplica: opción activa Y dentro de snapDistM
                var _cosL = Math.cos(eLat * Math.PI / 180)
                var _dLat = (eLat - snapLat) * 111319
                var _dLon = (eLon - snapLon) * 111319 * _cosL
                _snapActive = snapToRouteEnabled && (_dLat*_dLat + _dLon*_dLon) <= snapDistM * snapDistM

                var _baseLat = _snapActive ? snapLat : eLat
                var _baseLon = _snapActive ? snapLon : eLon
                // Heading: bearing del segmento si snap, heading GPS si no
                mapHeadRad = _snapActive ? _bearing(_sp0[1], _sp0[0], _sp1[1], _sp1[0]) : eHdg

                // Actualizar variables del nuevo pipeline
                _prevRealTickPos        = _lastRealTickPos
                _prevRealTickHeadingRad = _lastRealTickHeadingRad
                _prevRealTickSpeedMs    = _lastRealTickSpeedMs
                _curShapeIdx  = _fixShapeIdx
                _curShapeFrac = _fixShapeFrac
                _lastRealTickPos        = {lat: _baseLat, lon: _baseLon,
                                           idx: _fixShapeIdx, frac: _fixShapeFrac, ms: eMs}
                _lastRealTickHeadingRad = eHdg
                _lastRealTickSpeedMs    = _speedMs
            } else {
                mapHeadRad = eHdg
                _prevRealTickPos        = _lastRealTickPos
                _prevRealTickHeadingRad = _lastRealTickHeadingRad
                _prevRealTickSpeedMs    = _lastRealTickSpeedMs
                _lastRealTickPos        = {lat: eLat, lon: eLon, idx: 0, frac: 0, ms: eMs}
                _lastRealTickHeadingRad = eHdg
                _lastRealTickSpeedMs    = _speedMs
            }
            _lastTickPos             = _lastRealTickPos
            _lastTickHeadingRad      = eHdg
            _lastTickSpeedMs         = _speedMs
            _lastMapVehiclePos       = _lastRealTickPos
            _lastMapVehicleHeadingRad = eHdg
            _lastMapVehicleSpeedMs   = _speedMs
        }
        gpsTick(eLat, eLon, eSpdKmh, eHdg, eHasFix, eIsReal, eMs, eSource)
    }

    // ── Control manual del vehículo ───────────────────────────────────────────
    // GPS hardware simulado: fix real a 1 Hz + interpTimer dead-reckoning entre fixes
    // (mismo pipeline que GPS real). _headRateRads/_accelMss se actualizan también
    // en cada pulsación de botón para que el interpTimer responda sin esperar el fix.

    onDriveTurnLeftChanged:  { if (manualDriveMode) _driveUpdateHeadRate() }
    onDriveTurnRightChanged: { if (manualDriveMode) _driveUpdateHeadRate() }
    onDriveAccelChanged:     { if (manualDriveMode) _driveUpdateAccelMss() }
    onDriveBrakeChanged:     { if (manualDriveMode) _driveUpdateAccelMss() }

    function _driveUpdateHeadRate() {
        var td = (driveTurnRight ? 1 : 0) - (driveTurnLeft ? 1 : 0)
        _headRateRads = Math.abs(_driveSpeedMs) > 0.05 ? td * _driveTurnRps : 0
    }
    function _driveUpdateAccelMss() {
        if (driveAccel && !driveBrake)
            _accelMss = _driveSpeedMs >= 0 ? _driveAccelMss : _driveBrakeMss
        else if (driveBrake && !driveAccel)
            _accelMss = _driveSpeedMs > 0 ? -_driveBrakeMss : -_driveAccelMss
        else
            _accelMss = 0
    }

    // Fix de física a 1 Hz: actualiza el buffer igual que _onRealGpsTick.
    function _driveAdvance() {
        if (_p2 === null) return
        var dt  = 1.0
        var now = Date.now()

        var netAccel = 0
        if (driveAccel && !driveBrake) {
            netAccel = _driveSpeedMs >= 0 ? _driveAccelMss : _driveBrakeMss
        } else if (driveBrake && !driveAccel) {
            netAccel = _driveSpeedMs > 0 ? -_driveBrakeMss : -_driveAccelMss
        }

        var newSpeed = _driveSpeedMs + netAccel * dt
        if (driveBrake && !driveAccel) {
            if ((_driveSpeedMs > 0 && newSpeed < 0) || (_driveSpeedMs < 0 && newSpeed > 0))
                newSpeed = 0
        }
        newSpeed = Math.max(-_driveMaxRevMs, Math.min(_driveMaxFwdMs, newSpeed))
        _driveSpeedMs = newSpeed

        var turnDir = (driveTurnRight ? 1 : 0) - (driveTurnLeft ? 1 : 0)
        if (Math.abs(_driveSpeedMs) > 0.05) {
            _headRad += turnDir * _driveTurnRps * dt
            while (_headRad >  Math.PI) _headRad -= 2 * Math.PI
            while (_headRad < -Math.PI) _headRad += 2 * Math.PI
        }

        var effDist = Math.abs(_driveSpeedMs) * dt
        var effHdg  = _driveSpeedMs >= 0 ? _headRad : (_headRad + Math.PI)
        var newPos  = effDist > 0.01 ? _geoDest(_p2.lat, _p2.lon, effHdg, effDist)
                                     : {lat: _p2.lat, lon: _p2.lon}

        _p0 = _p1; _p1 = _p2
        _speedMs      = Math.abs(_driveSpeedMs)
        _accelMss     = netAccel
        _headRateRads = Math.abs(_driveSpeedMs) > 0.05 ? turnDir * _driveTurnRps : 0
        _p2     = {lat: newPos.lat, lon: newPos.lon, ms: now, spd: _driveSpeedMs, hdg: _headRad}
        _hasFix = true
        realSpeedKmh = _speedMs * 3.6
        _emit(newPos.lat, newPos.lon, _speedMs * 3.6, _headRad, true, true, now, "sim")
    }

    // Teletransporta la posición sim al punto más cercano en la ruta activa.
    function snapToRoute() {
        if (!routeShape || routeShape.length < 2 || _p2 === null) return
        _updateShapePos(_p2.lat, _p2.lon)
        var p0 = routeShape[_shapeIdx]
        var p1 = routeShape[Math.min(_shapeIdx + 1, routeShape.length - 1)]
        var sLat = p0[1] + _shapeFrac * (p1[1] - p0[1])
        var sLon = p0[0] + _shapeFrac * (p1[0] - p0[0])
        var now  = Date.now()
        _driveSpeedMs = 0; _speedMs = 0; _accelMss = 0
        _p0 = null; _p1 = null
        _p2 = {lat: sLat, lon: sLon, ms: now}
        _fixShapeIdx = _shapeIdx; _fixShapeFrac = _shapeFrac
        realSpeedKmh = 0
        _emit(sLat, sLon, 0, _headRad, true, true, now, "sim")
    }

    // ── Control de simulación ─────────────────────────────────────────────────
    function simStart() {
        if (!simRoute || simRoute.length < 2) return
        simIdx           = 0
        simFinished      = false
        _simDistM        = 0
        _lastSimPrimaryMs = 0
        _p0 = null; _p1 = null
        _accelMss     = 0
        _headRateRads = 0
        _hasFix       = !simSignalLost
        accuracy  = 8

        // Detectar modo timestamp (track grabado con campo ts)
        _simHasTs   = simRoute[0].ts !== undefined && simRoute[0].ts > 0
        _simStartMs = Date.now()

        // Precomputa distancias acumuladas (usadas para simIdx y modo velocidad)
        var cum = [0]
        for (var ci = 1; ci < simRoute.length; ci++)
            cum.push(cum[ci - 1] + _haversineM(simRoute[ci-1].lat, simRoute[ci-1].lon,
                                                simRoute[ci].lat,   simRoute[ci].lon))
        _simRouteCumDistM = cum

        var pt = simRoute[0]
        var now = Date.now()
        _simBaseMs  = now
        _simBaseIdx = 0
        _headRad    = _bearing(pt.lat, pt.lon, simRoute[1].lat, simRoute[1].lon)
        _speedMs    = 0
        _p2         = {lat: pt.lat, lon: pt.lon, ms: now}
        realSpeedKmh = 0
        _emit(pt.lat, pt.lon, 0, _headRad, _hasFix, true, now, "sim")
        simPrimaryTimer.restart()
    }

    function simStop() {
        simFinished = true
    }

    // Teletransporta la posición GPS simulada a lat/lon sin necesitar simRoute.
    function setSimPosition(lat, lon) {
        var now = Date.now()
        _p0 = null; _p1 = null
        _p2 = {lat: lat, lon: lon, ms: now}
        _hasFix = true
        _emit(lat, lon, 0, _headRad, true, false, now, "sim")
    }

    function seekTo(idx) {
        if (!simRoute || idx < 0 || idx >= simRoute.length) return
        simIdx      = idx
        simFinished = (idx >= simRoute.length - 1)
        var ms = Date.now()

        // Actualizar posición en distancia acumulada
        if (_simRouteCumDistM && idx < _simRouteCumDistM.length)
            _simDistM = _simRouteCumDistM[idx]
        _lastSimPrimaryMs = 0  // resetear para que el siguiente tick no tenga dt residual

        // Siempre resetear historial: seekTo es un salto, no una continuación
        _p0 = null; _p1 = null
        _p2 = {lat: simRoute[idx].lat, lon: simRoute[idx].lon, ms: ms}

        _simBaseMs  = ms
        _simBaseIdx = idx

        var bias = Math.max(0.1, 1.0 + simSpeedBias / 100.0)
        // En modo timestamp (ruta grabada), recalcular _simStartMs para que el siguiente
        // tick de _simAdvance calcule trackNow == simRoute[idx].ts en vez de la posición
        // que correspondería si la sim hubiera avanzado continuamente desde el inicio.
        if (_simHasTs && simRoute[idx].ts > 0)
            _simStartMs = ms - (simRoute[idx].ts - simRoute[0].ts) / bias
        if (idx + 1 < simRoute.length) {
            _headRad = _bearing(simRoute[idx].lat, simRoute[idx].lon,
                                simRoute[idx+1].lat, simRoute[idx+1].lon)
            var routeSpd = simRoute[idx].spd
            var effSpd   = commSpeedLimitKmh > 0 ? commSpeedLimitKmh : routeSpd
            _speedMs = effSpd * bias / 3.6
        } else if (idx > 0) {
            _headRad = _bearing(simRoute[idx-1].lat, simRoute[idx-1].lon,
                                simRoute[idx].lat, simRoute[idx].lon)
            _speedMs = 0
        }
        _hasFix = !simSignalLost
        realSpeedKmh = _speedMs * 3.6

        // Seek = salto brusco, no continuación: limpiar todos los estados del interpolador
        // para que el sistema quede consistente desde el nuevo punto.
        _snapDone = false; _curShapeIdx = 0; _curShapeFrac = 0
        _corrRemM = 0; _accelMss = 0; _headRateRads = 0; _interpMs = 0
        // Reset nuevo pipeline: seek es un salto, los ticks anteriores no son válidos
        _lastRealTickPos = null; _prevRealTickPos = null
        _lastRealTickHeadingRad = 0; _prevRealTickHeadingRad = 0
        _lastRealTickSpeedMs = 0;  _prevRealTickSpeedMs = 0
        _lastTickPos = null; _lastTickHeadingRad = 0; _lastTickSpeedMs = 0
        _lastMapVehiclePos = null; _lastMapVehicleHeadingRad = 0; _lastMapVehicleSpeedMs = 0

        _emit(_p2.lat, _p2.lon, _speedMs * 3.6, _headRad, _hasFix, true, ms, "sim")
        simPrimaryTimer.restart()
    }

    // ── Dirección inversa ─────────────────────────────────────────────────────

    // Búsqueda completa del punto más cercano en routeShape a (lat,lon).
    function _findShapePosAt(lat, lon) {
        if (!routeShape || routeShape.length < 2) return null
        var shape  = routeShape
        var cosLat = Math.cos(lat * Math.PI / 180)
        var minD = 1e18, bestI = 0, bestFrac = 0
        for (var i = 0; i < shape.length - 1; i++) {
            var p0 = shape[i], p1 = shape[i+1]
            var sLat = (p1[1] - p0[1]) * 111319
            var sLon = (p1[0] - p0[0]) * 111319 * cosLat
            var sLen2 = sLat * sLat + sLon * sLon
            var frac = 0
            if (sLen2 > 0.01) {
                frac = ((lat - p0[1]) * 111319 * sLat
                      + (lon - p0[0]) * 111319 * cosLat * sLon) / sLen2
                frac = Math.max(0, Math.min(1, frac))
            }
            var dLat = (lat - (p0[1] + frac * (p1[1] - p0[1]))) * 111319
            var dLon = (lon - (p0[0] + frac * (p1[0] - p0[0]))) * 111319 * cosLat
            var d = dLat * dLat + dLon * dLon
            if (d < minD) { minD = d; bestI = i; bestFrac = frac }
        }
        return {idx: bestI, frac: bestFrac}
    }

    // Camina distM metros hacia atrás en routeShape desde (shapeIdx, shapeFrac).
    function _walkBackwards(shapeIdx, shapeFrac, distM) {
        var shape = routeShape
        var i = shapeIdx, f = shapeFrac, rem = distM
        while (rem > 0.01) {
            var s0 = shape[i], s1 = shape[Math.min(i + 1, shape.length - 1)]
            var segLen = _haversineM(s0[1], s0[0], s1[1], s1[0])
            if (segLen < 0.01) { if (i <= 0) return null; i--; f = 1; continue }
            var distToStart = f * segLen
            if (distToStart >= rem) { f = f - rem / segLen; rem = 0 }
            else { rem -= distToStart; if (i <= 0) return null; i--; f = 1 }
        }
        return {idx: i, frac: f}
    }

    // Construye revRoute y activa el modo reversa.
    // Construye revRoute con waypoints suficientes para 5 s reales; para por tiempo.
    function startRevMode() {
        if (!routeShape || routeShape.length < 2 || _p2 === null) return
        var shapePos = _findShapePosAt(_p2.lat, _p2.lon)
        if (!shapePos) return
        var revSpd  = 50  // km/h
        var revSpdMs = revSpd / 3.6
        var bias    = Math.max(0.1, 1.0 + simSpeedBias / 100.0)
        // Suficientes waypoints para 5 s reales al bias actual + 50 % de margen
        var distM   = Math.max(50, revSpdMs * 5.0 * bias * 1.5)
        var stepM   = revSpdMs  // metros por paso (1 s de timer a bias=1)
        var pts = []
        var curI = shapePos.idx, curF = shapePos.frac
        var s0 = routeShape[curI]
        var s1 = routeShape[Math.min(curI + 1, routeShape.length - 1)]
        pts.push({lat: s0[1] + curF * (s1[1] - s0[1]),
                  lon: s0[0] + curF * (s1[0] - s0[0]), spd: revSpd})
        var totalDist = 0
        while (totalDist < distM) {
            var next = _walkBackwards(curI, curF, stepM)
            if (!next) break
            var ns0 = routeShape[next.idx]
            var ns1 = routeShape[Math.min(next.idx + 1, routeShape.length - 1)]
            pts.push({lat: ns0[1] + next.frac * (ns1[1] - ns0[1]),
                      lon: ns0[0] + next.frac * (ns1[0] - ns0[0]), spd: revSpd})
            curI = next.idx; curF = next.frac
            totalDist += stepM
        }
        if (pts.length < 2) return
        pts[pts.length - 1].spd = 0
        var rs = []
        for (var ri = 0; ri < pts.length; ri++) rs.push([pts[ri].lon, pts[ri].lat])
        revRoute     = pts
        revShape     = rs
        _revIdx      = 0
        revFinished  = false
        _revStartMs  = Date.now()
        revMode      = true
    }

    // Avanza un paso en revRoute.
    function _revAdvance() {
        if (!revRoute || revRoute.length < 2) { revFinished = true; return }
        // Parar por tiempo (5 s reales) o si se agota el shape
        if (Date.now() - _revStartMs >= 5000) { revFinished = true; return }
        if (_revIdx >= revRoute.length - 1)   { revFinished = true; return }
        _revIdx++
        var bias  = Math.max(0.1, 1.0 + simSpeedBias / 100.0)
        var pt    = revRoute[_revIdx]
        var nextPt = (_revIdx + 1 < revRoute.length) ? revRoute[_revIdx + 1] : null
        if (nextPt && pt.spd > 0) {
            _speedMs = (pt.spd / 3.6) * bias
            _headRad = _bearing(pt.lat, pt.lon, nextPt.lat, nextPt.lon)
        } else if (_revIdx > 0) {
            var prevPt = revRoute[_revIdx - 1]
            _speedMs = 0
            _headRad = _bearing(prevPt.lat, prevPt.lon, pt.lat, pt.lon)
        }
        var now = Date.now()
        _realTickMs = now
        _simBaseMs = now
        _p0 = _p1; _p1 = _p2
        _p2 = {lat: pt.lat, lon: pt.lon, ms: now, spd: _speedMs, hdg: _headRad}
        _hasFix = true
        if (_p1 !== null && _p1.spd !== undefined) {
            var dtRev = (_p2.ms - _p1.ms) / 1000.0
            if (dtRev > 0.1) {
                _accelMss = Math.max(-5, Math.min(5, (_speedMs - _p1.spd) / dtRev))
                if (_p0 !== null && _p0.hdg !== undefined) {
                    var dHdgRev = _headRad - _p0.hdg
                    while (dHdgRev >  Math.PI) dHdgRev -= 2 * Math.PI
                    while (dHdgRev < -Math.PI) dHdgRev += 2 * Math.PI
                    var dtTotalRev = (_p2.ms - _p0.ms) / 1000.0
                    _headRateRads = Math.max(-1.0, Math.min(1.0, dHdgRev / dtTotalRev))
                }
            }
        }
        _applyTurnFilter()
        realSpeedKmh = _speedMs * 3.6
        _emit(pt.lat, pt.lon, _speedMs * 3.6, _headRad, _hasFix, true, now, "sim")
    }

    // Cancela revMode sin seekTo (usado al reroutear: la posición queda donde está).
    function cancelRevMode() {
        revMode     = false
        revFinished = false
        revRoute    = null
        revShape    = null
        _revIdx     = 0
    }

    // Desactiva el modo reversa y reanuda el sim principal desde el punto más cercano.
    function stopRevMode() {
        revMode     = false
        revFinished = false
        revRoute    = null
        revShape    = null
        _revIdx     = 0
        if (_p2 !== null && simRoute && simRoute.length > 0) {
            var bestIdx = 0, bestD = 1e18
            for (var k = 0; k < simRoute.length; k++) {
                var dd = _haversineM(_p2.lat, _p2.lon, simRoute[k].lat, simRoute[k].lon)
                if (dd < bestD) { bestD = dd; bestIdx = k }
            }
            seekTo(bestIdx)
        }
    }

    // Giro instantáneo de 180°: emite un tick real con heading inverso.
    function flipHeading() {
        if (_p2 === null) return
        _headRad += Math.PI
        if (_headRad >= 2 * Math.PI) _headRad -= 2 * Math.PI
        _headRateRads = 0
        _emit(_p2.lat, _p2.lon, _speedMs * 3.6, _headRad, _hasFix, true,
              Date.now(), simMode ? "sim" : "gps")
    }

    // ── Shape-following helpers (GPS real en ruta) ────────────────────────────

    // Snapa _shapeIdx/_shapeFrac al punto más cercano en routeShape al fix (lat, lon).
    function _updateShapePos(lat, lon) {
        if (!routeShape || routeShape.length < 2) return
        var cosLat = Math.cos(lat * Math.PI / 180)
        var minD   = 1e18
        var bestI  = _shapeIdx, bestFrac = 0
        // Buscar en ventana ±5 hacia atrás + 200 hacia adelante, acotada al leg activo
        var start  = Math.max(0, _shapeIdx - 5)
        var end    = Math.min(routeShape.length - 1, _shapeIdx + 200)
        if (routeShapeLegEnd >= 0) end = Math.min(end, routeShapeLegEnd)
        for (var i = start; i < end; i++) {
            var p0 = routeShape[i], p1 = routeShape[i+1]
            var sLat  = (p1[1] - p0[1]) * 111319
            var sLon  = (p1[0] - p0[0]) * 111319 * cosLat
            var sLen2 = sLat * sLat + sLon * sLon
            var frac  = 0
            if (sLen2 > 0.01) {
                frac = ((lat - p0[1]) * 111319 * sLat
                      + (lon - p0[0]) * 111319 * cosLat * sLon) / sLen2
                frac = Math.max(0, Math.min(1, frac))
            }
            var dLat = (lat - (p0[1] + frac * (p1[1] - p0[1]))) * 111319
            var dLon = (lon - (p0[0] + frac * (p1[0] - p0[0]))) * 111319 * cosLat
            var d = dLat * dLat + dLon * dLon
            if (d < minD) { minD = d; bestI = i; bestFrac = frac }
        }
        _shapeIdx = bestI; _shapeFrac = bestFrac
    }

    // Avanza distM metros por el polyline de routeShape desde _shapeIdx/_shapeFrac.
    // Actualiza _shapeIdx/_shapeFrac y devuelve {lat, lon}, o null si ya está al final.
    function _advanceAlongShape(distM) {
        if (!routeShape || routeShape.length < 2 || distM <= 0) return null
        var shape = routeShape
        var rem   = distM
        var i     = _shapeIdx
        var frac  = _shapeFrac
        while (rem > 0.01 && i < shape.length - 1) {
            var segLen = _haversineM(shape[i][1], shape[i][0],
                                     shape[i+1][1], shape[i+1][0])
            if (segLen < 0.01) { i++; frac = 0; continue }
            var avail = segLen * (1.0 - frac)
            if (rem < avail) {
                frac += rem / segLen
                _shapeIdx = i; _shapeFrac = frac
                return {
                    lat: shape[i][1] + (shape[i+1][1] - shape[i][1]) * frac,
                    lon: shape[i][0] + (shape[i+1][0] - shape[i][0]) * frac
                }
            }
            rem  -= avail
            i++; frac = 0
        }
        _shapeIdx = Math.min(i, shape.length - 1); _shapeFrac = 0
        var last = shape[_shapeIdx]
        return {lat: last[1], lon: last[0]}
    }

    // Calcula posición en el shape a distM metros desde (startIdx, startFrac),
    // sin mutar _shapeIdx/_shapeFrac. Usado por la interpolación de GPS real.
    function _shapePosDelta(startIdx, startFrac, distM) {
        if (!routeShape || routeShape.length < 2 || distM <= 0) return null
        var shape = routeShape
        var rem   = distM
        var i     = startIdx
        var frac  = startFrac
        while (rem > 0.01 && i < shape.length - 1) {
            var segLen = _haversineM(shape[i][1], shape[i][0],
                                     shape[i+1][1], shape[i+1][0])
            if (segLen < 0.01) { i++; frac = 0; continue }
            var avail = segLen * (1.0 - frac)
            if (rem < avail) {
                frac += rem / segLen
                return {
                    lat: shape[i][1] + (shape[i+1][1] - shape[i][1]) * frac,
                    lon: shape[i][0] + (shape[i+1][0] - shape[i][0]) * frac
                }
            }
            rem -= avail
            i++; frac = 0
        }
        var last = shape[Math.min(i, shape.length - 1)]
        return {lat: last[1], lon: last[0]}
    }

    // Distancia (m) de ruta sim que se recorrería en secsAhead segundos a velocidad actual,
    // ajustada por ratio GPS/_speedMs vs Valhalla. Usa timestamps de simRoutePoints.
    function _simWantedVisibleAheadDistM(secsAhead) {
        if (!simRoutePoints || simRoutePoints.length < 2) return 0
        var pts = simRoutePoints
        var n   = pts.length
        var si  = simIdx
        if (si >= n - 1) return 0

        var vhSpd = (simRouteSpeedKmh && si < simRouteSpeedKmh.length && simRouteSpeedKmh[si] > 0)
                    ? simRouteSpeedKmh[si] / 3.6
                    : ((routeShapeSpeedKmh && _curShapeIdx < routeShapeSpeedKmh.length)
                       ? routeShapeSpeedKmh[_curShapeIdx] / 3.6 : 0)
        var ratio = (vhSpd > 0.1 && _speedMs > 0)
                    ? Math.max(0.1, Math.min(3.0, _speedMs / vhSpd)) : 1.0

        var totalTime = 0.0
        var totalDist = 0.0
        for (var i = si; i < n - 1; i++) {
            var segTime = (pts[i + 1].ts - pts[i].ts) / 1000.0
            if (segTime <= 0) continue
            var adjTime = segTime / ratio
            var segDist = _haversineM(pts[i].lat, pts[i].lon, pts[i + 1].lat, pts[i + 1].lon)
            if (totalTime + adjTime >= secsAhead) {
                var t = (secsAhead - totalTime) / adjTime
                var res = totalDist + segDist * t
                if (bearingDebug && si !== _lastBearingLogIdx) {
                    _lastBearingLogIdx = si
                    console.log("BEARING simAheadDist si=" + si + " secs=" + secsAhead
                        + " spd=" + _speedMs.toFixed(1) + " vhSpd=" + (vhSpd * 3.6).toFixed(1)
                        + " ratio=" + ratio.toFixed(2) + " distM=" + res.toFixed(0))
                }
                return res
            }
            totalTime += adjTime
            totalDist += segDist
        }
        if (bearingDebug && si !== _lastBearingLogIdx) {
            _lastBearingLogIdx = si
            console.log("BEARING simAheadDist EXHAUST si=" + si + " distM=" + totalDist.toFixed(0))
        }
        return totalDist
    }

    // Bisector angular (rad) de los puntos de simRoutePoints visibles en distM metros.
    // Para cada punto dentro de distM se calcula el bearing DESDE EL VEHÍCULO al punto.
    // Devuelve el centro del rango angular [min, max] — bearing ideal del mapa.
    //   minPt (rojo) = punto más a la izquierda visto desde el coche
    //   maxPt (azul) = punto más a la derecha
    //   ctrPt (verde) = punto de la ruta cuyo ángulo es el más próximo al bisector
    // Los tres son puntos reales de la ruta → siempre sobre la ruta, y verde queda
    // angularmente entre rojo y azul por construcción.
    function _simRouteIdealBisectorRad(distM, mapBearingRad) {
        if (!simRoutePoints || simRoutePoints.length < 2 || distM <= 0) return mapBearingRad
        var pts    = simRoutePoints
        var n      = pts.length
        var si     = simIdx
        if (si >= n - 1) return mapBearingRad

        var oLat   = _lastRealTickPos ? _lastRealTickPos.lat : pts[si].lat
        var oLon   = _lastRealTickPos ? _lastRealTickPos.lon : pts[si].lon
        var cosLat = Math.cos(oLat * Math.PI / 180)
        var K      = 111319
        var skipM  = 8.0  // puntos casi sobre el vehículo: su bearing es ruido, se ignoran

        var cumDist = 0.0
        var minRel  =  999, maxRel = -999
        var minPt   = null, maxPt  = null
        var cand    = []   // {rel,lat,lon} de cada punto válido, para elegir el central
        var fwdHdg  = mapBearingRad  // referencia para decidir izquierda/derecha

        for (var i = si; i < n - 1; i++) {
            cumDist += _haversineM(pts[i].lat, pts[i].lon, pts[i + 1].lat, pts[i + 1].lon)
            if (cumDist > distM) break
            // Bearing desde el vehículo hasta el punto pts[i+1]
            var dLat = (pts[i + 1].lat - oLat) * K
            var dLon = (pts[i + 1].lon - oLon) * K * cosLat
            if (Math.sqrt(dLat * dLat + dLon * dLon) < skipM) continue
            var brg = Math.atan2(dLon, dLat)
            // Ángulo relativo al bearing del mapa, normalizado a ±π
            var rel = brg - fwdHdg
            while (rel >  Math.PI) rel -= 2 * Math.PI
            while (rel < -Math.PI) rel += 2 * Math.PI
            cand.push({rel: rel, lat: pts[i + 1].lat, lon: pts[i + 1].lon})
            if (rel < minRel) { minRel = rel; minPt = {lat: pts[i+1].lat, lon: pts[i+1].lon} }
            if (rel > maxRel) { maxRel = rel; maxPt = {lat: pts[i+1].lat, lon: pts[i+1].lon} }
        }

        if (cand.length === 0) { bisectorMinPt = null; bisectorMaxPt = null; bisectorCtrPt = null; return mapBearingRad }

        var ctrRel   = (minRel + maxRel) / 2        // ángulo medio entre rojo y azul
        var bisector = fwdHdg + ctrRel

        // verde = punto de la ruta cuyo ángulo está más cerca del bisector (sobre la ruta)
        var ctrPt = null, bestD = 1e9
        for (var c = 0; c < cand.length; c++) {
            var d = Math.abs(cand[c].rel - ctrRel)
            if (d < bestD) { bestD = d; ctrPt = {lat: cand[c].lat, lon: cand[c].lon} }
        }

        bisectorMinPt = minPt
        bisectorMaxPt = maxPt
        bisectorCtrPt = ctrPt
        return bisector
    }

    // ── Utilidades geométricas ────────────────────────────────────────────────
    function _advanceDist(speedMs, dt) { return speedMs * dt }

    // Proyecta el heading en dt segundos desde el último tick real usando la tasa de giro real.
    // heading = _lastRealTickHeadingRad + rate × dt, normalizado a [-π, π].
    function _accelInterpHeading(dt) {
        if (!_lastRealTickPos) return _lastRealTickHeadingRad
        var hdg = _lastRealTickHeadingRad + _headingRateRadFromRealTicks() * dt
        while (hdg >  Math.PI) hdg -= 2 * Math.PI
        while (hdg < -Math.PI) hdg += 2 * Math.PI
        return hdg
    }

    // Heading del vehículo (icono en mapa) con transición suave en vértices del shape.
    // blendDistM metros antes y después de cada vértice: lerp entre segmentos adyacentes.
    // Para curvas encadenadas (vértices seguidos): zonas solapadas → rotación progresiva.
    // NO afecta a la rotación del mapa (mapView.bearing), solo al icono del vehículo.
    function _vehicleHeadingRad(idx, frac, blendDistM) {
        if (!routeShape || routeShape.length < 2) return _lastRealTickHeadingRad
        var shape  = routeShape
        var n      = shape.length
        var hdgCur = _bearing(shape[idx][1], shape[idx][0],
                              shape[Math.min(idx+1, n-1)][1], shape[Math.min(idx+1, n-1)][0])

        // Blend CENTRADO en el vértice: el giro se reparte simétricamente sobre
        // [V−blendDist, V+blendDist]. La zona "acercándose" rota del segmento actual
        // hasta el punto medio (t: 0→0.5); la zona "recién pasado" continúa del punto
        // medio hasta el segmento actual (t: 0.5→1). En el vértice ambas dan el punto
        // medio → rotación continua A→B sin salto (antes cada zona rotaba A→B completa,
        // creando un diente de sierra: se llegaba a B en V y se reiniciaba a A justo después).

        // Acercándose al vértice siguiente
        if (idx < n - 2) {
            var segLen = _haversineM(shape[idx][1], shape[idx][0], shape[idx+1][1], shape[idx+1][0])
            var distToNext = segLen * (1.0 - frac)
            if (distToNext < blendDistM) {
                var hdgNext = _bearing(shape[idx+1][1], shape[idx+1][0], shape[idx+2][1], shape[idx+2][0])
                var t  = 0.5 * (1.0 - distToNext / blendDistM)   // 0 lejos → 0.5 en el vértice
                var dH = hdgNext - hdgCur
                while (dH >  Math.PI) dH -= 2 * Math.PI
                while (dH < -Math.PI) dH += 2 * Math.PI
                return hdgCur + t * dH
            }
        }

        // Acabando de pasar el vértice anterior
        if (idx > 0) {
            var segLen2      = _haversineM(shape[idx][1], shape[idx][0], shape[idx+1][1], shape[idx+1][0])
            var distFromPrev = segLen2 * frac
            if (distFromPrev < blendDistM) {
                var hdgPrev = _bearing(shape[idx-1][1], shape[idx-1][0], shape[idx][1], shape[idx][0])
                var t2  = 0.5 + 0.5 * (distFromPrev / blendDistM)  // 0.5 en el vértice → 1 lejos
                var dH2 = hdgCur - hdgPrev
                while (dH2 >  Math.PI) dH2 -= 2 * Math.PI
                while (dH2 < -Math.PI) dH2 += 2 * Math.PI
                return hdgPrev + t2 * dH2
            }
        }

        return hdgCur
    }

    // Tasa de cambio de heading entre los dos últimos ticks reales (rad/s), acotada a ±π.
    function _headingRateRadFromRealTicks() {
        if (!_prevRealTickPos || !_lastRealTickPos) return 0
        var dt = (_lastRealTickPos.ms - _prevRealTickPos.ms) / 1000.0
        if (dt < 0.001) return 0
        var dHdg = _lastRealTickHeadingRad - _prevRealTickHeadingRad
        while (dHdg >  Math.PI) dHdg -= 2 * Math.PI
        while (dHdg < -Math.PI) dHdg += 2 * Math.PI
        return Math.max(-Math.PI, Math.min(Math.PI, dHdg / dt))
    }

    // Aceleración entre los dos últimos ticks reales (m/s²), acotada a ±10.
    // Requiere _lastRealTickPos.ms, _prevRealTickPos.ms, _lastRealTickSpeedMs, _prevRealTickSpeedMs.
    // Naming: accelMs = acceleration in m/s².
    function _accelMsFromRealTicks() {
        if (!_prevRealTickPos || !_lastRealTickPos) return 0
        var dt = (_lastRealTickPos.ms - _prevRealTickPos.ms) / 1000.0
        if (dt < 0.001) return 0
        return Math.max(-10, Math.min(10, (_lastRealTickSpeedMs - _prevRealTickSpeedMs) / dt))
    }

    // Proyecta (lat,lon) sobre routeShape. Solo considera segmentos a menos de maxDistM.
    // prevPos {idx,frac}: si no es null, entre varios candidatos dentro del radio
    // elige el más cercano a prevPos en distancia de ruta (evita saltar al tramo
    // paralelo de un giro de 180°). Devuelve {lat,lon,idx,frac} o null si fuera de ruta.
    function _snapToRoute(lat, lon, maxDistM, prevPos) {
        if (!routeShape || routeShape.length < 2) return null
        var shape  = routeShape
        var cosLat = Math.cos(lat * Math.PI / 180)
        var maxD2  = maxDistM * maxDistM
        var bestGpsD2  = 1e18
        var bestRouteD = 1e18
        var bestI = -1, bestF = 0
        var _legLimit = (routeShapeLegEnd >= 0) ? routeShapeLegEnd : shape.length - 1
        for (var i = 0; i < _legLimit; i++) {
            var p0 = shape[i], p1 = shape[i+1]
            var sLat  = (p1[1] - p0[1]) * 111319
            var sLon  = (p1[0] - p0[0]) * 111319 * cosLat
            var sLen2 = sLat*sLat + sLon*sLon
            var f = 0
            if (sLen2 > 0.01) {
                f = ((lat - p0[1])*111319*sLat + (lon - p0[0])*111319*cosLat*sLon) / sLen2
                f = Math.max(0, Math.min(1, f))
            }
            var dLat  = (lat - (p0[1] + f*(p1[1]-p0[1]))) * 111319
            var dLon  = (lon - (p0[0] + f*(p1[0]-p0[0]))) * 111319 * cosLat
            var gpsD2 = dLat*dLat + dLon*dLon
            if (gpsD2 > maxD2) continue
            if (prevPos !== null) {
                // Distancia de ruta desde prevPos (en unidades de segmento+fracción).
                // El candidato más cercano a prevPos es el que "se acerca", no el paralelo lejano.
                var routeD = Math.abs((i - prevPos.idx) + (f - prevPos.frac))
                if (bestI < 0 || routeD < bestRouteD ||
                        (routeD === bestRouteD && gpsD2 < bestGpsD2)) {
                    bestI = i; bestF = f; bestGpsD2 = gpsD2; bestRouteD = routeD
                }
            } else {
                if (bestI < 0 || gpsD2 < bestGpsD2) {
                    bestI = i; bestF = f; bestGpsD2 = gpsD2
                }
            }
        }
        if (bestI < 0) return null
        var s0 = shape[bestI], s1 = shape[Math.min(bestI+1, shape.length-1)]
        return { lat: s0[1] + bestF*(s1[1]-s0[1]),
                 lon: s0[0] + bestF*(s1[0]-s0[0]),
                 idx: bestI, frac: bestF }
    }

    // Posición interpolada con aceleración: proyecta v×dt + ½×a×dt² desde el último tick real.
    // Más precisa que _idealInterpPos cuando el vehículo acelera o frena entre ticks reales.
    // Devuelve {lat, lon, idx, frac, headingRad} o null si no aplica.
    function _accelInterpPos(dt) {
        if (!routeShape || routeShape.length < 2) return null
        if (!_lastRealTickPos) return null
        var accel = _accelMsFromRealTicks()
        var distM = _lastRealTickSpeedMs * dt + 0.5 * accel * dt * dt
        if (distM < 0) distM = 0
        var pos   = _walkShape(_lastRealTickPos.idx, _lastRealTickPos.frac, distM)
        var shape = routeShape
        var hdg   = _bearing(shape[pos.idx][1], shape[pos.idx][0],
                             shape[Math.min(pos.idx + 1, shape.length - 1)][1],
                             shape[Math.min(pos.idx + 1, shape.length - 1)][0])
        return { lat: pos.lat, lon: pos.lon, idx: pos.idx, frac: pos.frac, headingRad: hdg }
    }

    // Posición interpolada usando velocidad Valhalla × ratio (v_GPS / v_Valhalla).
    // Más robusta que _idealInterpPos cuando v_GPS es ruidosa o cero: usa v_Valhalla como base.
    // Devuelve {lat, lon, idx, frac, headingRad} o null si no aplica.
    function _vhRatioInterpPos(dt) {
        if (!routeShape || routeShape.length < 2) return null
        if (!_lastRealTickPos) return null
        var vVh = (routeShapeSpeedKmh && _lastRealTickPos.idx < routeShapeSpeedKmh.length)
                  ? routeShapeSpeedKmh[_lastRealTickPos.idx] / 3.6 : _lastRealTickSpeedMs
        var ratio = (vVh > 0.1) ? _lastRealTickSpeedMs / vVh : 1.0
        ratio = Math.max(0.1, Math.min(3.0, ratio))
        var distM = vVh * ratio * dt
        if (distM < 0) distM = 0
        var pos   = _walkShape(_lastRealTickPos.idx, _lastRealTickPos.frac, distM)
        var shape = routeShape
        var hdg   = _bearing(shape[pos.idx][1], shape[pos.idx][0],
                             shape[Math.min(pos.idx + 1, shape.length - 1)][1],
                             shape[Math.min(pos.idx + 1, shape.length - 1)][0])
        return { lat: pos.lat, lon: pos.lon, idx: pos.idx, frac: pos.frac, headingRad: hdg }
    }

    // Posición ideal del tick interpolado: avanza _lastRealTickSpeedMs × dt metros
    // desde _lastRealTickPos siguiendo la ruta. Heading = segmento del shape en llegada.
    // Solo aplica si hay ruta activa y el vehículo está dentro del radio de snap.
    // Devuelve {lat, lon, idx, frac, headingRad} o null si no aplica.
    function _idealInterpPos(dt) {
        if (!routeShape || routeShape.length < 2) return null
        if (!_lastRealTickPos) return null
        var distM = _advanceDist(_lastRealTickSpeedMs, dt)
        var pos   = _walkShape(_lastRealTickPos.idx, _lastRealTickPos.frac, distM)
        var shape = routeShape
        var hdg   = _bearing(shape[pos.idx][1], shape[pos.idx][0],
                             shape[Math.min(pos.idx + 1, shape.length - 1)][1],
                             shape[Math.min(pos.idx + 1, shape.length - 1)][0])
        return { lat: pos.lat, lon: pos.lon, idx: pos.idx, frac: pos.frac, headingRad: hdg }
    }

    // Avanza distM metros desde (fromIdx, fromFrac) siguiendo cualquier shape [[lon,lat]].
    function _walkOn(shape, fromIdx, fromFrac, distM) {
        var si = fromIdx, sf = fromFrac, rem = distM
        while (rem > 0.001 && si < shape.length - 1) {
            var sLen = _haversineM(shape[si][1], shape[si][0], shape[si+1][1], shape[si+1][0])
            if (sLen < 0.01) { si++; sf = 0; continue }
            var avail = sLen * (1.0 - sf)
            if (rem <= avail) {
                sf += rem / sLen
                return { lat: shape[si][1] + (shape[si+1][1] - shape[si][1]) * sf,
                         lon: shape[si][0] + (shape[si+1][0] - shape[si][0]) * sf,
                         idx: si, frac: sf }
            }
            rem -= avail; si++; sf = 0
        }
        var last = shape[Math.min(si, shape.length - 1)]
        return { lat: last[1], lon: last[0], idx: Math.min(si, shape.length - 1), frac: 0 }
    }

    function _walkShape(fromIdx, fromFrac, distM) {
        return _walkOn(routeShape, fromIdx, fromFrac, distM)
    }

    // Proyecta (lat, lon) sobre el segmento más cercano de shape [[lon,lat]].
    // Devuelve {idx, frac, distM}.
    function _snapToShape(shape, lat, lon) {
        if (!shape || shape.length < 2) return null
        var bestDist = 1e9, bestIdx = 0, bestFrac = 0
        for (var i = 0; i < shape.length - 1; i++) {
            var la1 = shape[i][1],   lo1 = shape[i][0]
            var la2 = shape[i+1][1], lo2 = shape[i+1][0]
            var dx = lo2 - lo1, dy = la2 - la1
            var denom = dx*dx + dy*dy
            if (denom < 1e-18) continue
            var px = lon - lo1, py = lat - la1
            var t = Math.max(0, Math.min(1, (px*dx + py*dy) / denom))
            var pLat = la1 + t*dy, pLon = lo1 + t*dx
            var d = _haversineM(lat, lon, pLat, pLon)
            if (d < bestDist) { bestDist = d; bestIdx = i; bestFrac = t }
        }
        return { idx: bestIdx, frac: bestFrac, distM: bestDist }
    }

    // Diferencia angular en [-π, π].
    function _angleDiff(a, b) {
        var d = a - b
        while (d >  Math.PI) d -= 2 * Math.PI
        while (d < -Math.PI) d += 2 * Math.PI
        return d
    }

    // Construye un shape [[lon,lat]] desde el tile caché para DR sin ruta o tras un
    // desvío detectado. Elige la vía más cercana y mejor alineada con el heading dado.
    // headingRad: opcional; por defecto _headRad (último heading GPS real). Al
    // re-anclar tras un desvío en DR se pasa el heading IMU actual, más fiable que
    // el de la vía abandonada.
    // Devuelve {coords, idx, frac} o null si no hay tiles cargados o vías válidas.
    function _buildDrNrShape(lat, lon, headingRad) {
        if (!tileCache) return null
        var hdgRef = (headingRad !== undefined && headingRad !== null) ? headingRad : _headRad
        var raw = tileCache.roads_near(lat, lon)
        var roads = null
        try { roads = JSON.parse(raw) } catch(e) { return null }
        if (!roads || roads.length === 0) return null

        var bestShape = null, bestIdx = 0, bestFrac = 0.0, bestScore = 1e9

        for (var i = 0; i < roads.length; i++) {
            var r = roads[i]
            if (!r.coords || r.coords.length < 2) continue

            // Rust devuelve coords como [[lat,lon]]; routeShape usa [[lon,lat]]
            var shape = []
            for (var j = 0; j < r.coords.length; j++)
                shape.push([r.coords[j][1], r.coords[j][0]])

            var snap = _snapToShape(shape, lat, lon)
            if (!snap || snap.distM > 100) continue

            var si = snap.idx
            var roadHdg = _bearing(shape[si][1], shape[si][0],
                                   shape[Math.min(si+1, shape.length-1)][1],
                                   shape[Math.min(si+1, shape.length-1)][0])

            var hdgDiff    = Math.abs(_angleDiff(roadHdg,           hdgRef))
            var hdgDiffRev = Math.abs(_angleDiff(roadHdg + Math.PI, hdgRef))
            var minDiff    = Math.min(hdgDiff, hdgDiffRev)
            if (minDiff > 1.309) continue  // > 75°: vía perpendicular, descartar

            // Score: distancia + penalización angular (1 rad ≈ 20 m equivalente)
            var score = snap.distM + minDiff * 20
            if (score < bestScore) {
                bestScore = score
                var reversed = hdgDiffRev < hdgDiff
                if (reversed) {
                    shape = shape.slice().reverse()
                    snap  = _snapToShape(shape, lat, lon)
                }
                bestShape = shape; bestIdx = snap.idx; bestFrac = snap.frac
            }
        }

        return bestShape ? { coords: bestShape, idx: bestIdx, frac: bestFrac } : null
    }

    function _haversineM(la1, lo1, la2, lo2) {
        var R  = 6371000
        var f1 = la1 * Math.PI / 180, f2 = la2 * Math.PI / 180
        var df = (la2 - la1) * Math.PI / 180
        var dl = (lo2 - lo1) * Math.PI / 180
        var a  = Math.sin(df/2)*Math.sin(df/2)
                 + Math.cos(f1)*Math.cos(f2)*Math.sin(dl/2)*Math.sin(dl/2)
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    }

    function _bearing(la1, lo1, la2, lo2) {
        var dl = (lo2 - lo1) * Math.PI / 180
        var f1 = la1 * Math.PI / 180, f2 = la2 * Math.PI / 180
        return Math.atan2(Math.sin(dl)*Math.cos(f2),
                          Math.cos(f1)*Math.sin(f2) - Math.sin(f1)*Math.cos(f2)*Math.cos(dl))
    }

    // Calcula la siguiente velocidad DR (m/s) hacia spdTarget (límite de vía × ratio,
    // o _drSpeedMs si no hay dato de vía). Con acelerómetro calibrado, la velocidad
    // evoluciona integrando la aceleración longitudinal real detectada (magnitud
    // similar a las aceleraciones reales del vehículo, calibradas contra GPS en
    // marcha normal — ver NavImu.feedGpsAccel), anclada suavemente a spdTarget para
    // no derivar sin fin si la calibración o la lectura puntual son ruidosas. Sin
    // acelerómetro calibrado, sigue spdTarget directamente (comportamiento previo).
    function _drNextSpeed(dt, spdTarget) {
        var spd = _drSpeedRunMs > 0.01 ? _drSpeedRunMs : spdTarget
        if (imu && imu.accelAxisCalibrated) {
            var a = Math.max(-4.0, Math.min(4.0, imu.calibratedAccel()))
            spd = Math.max(0, spd + a * dt)
            spd = spd + (spdTarget - spd) * Math.min(1.0, dt / 8.0)
        } else {
            spd = spdTarget
        }
        _drSpeedRunMs = spd
        return spd
    }

    // Emite un tick sintético source="dr". La posición SIEMPRE sigue un shape (ruta
    // Valhalla, o tile caché si no hay ruta o el conductor se ha desviado de ella);
    // el IMU nunca decide la posición salvo que no exista shape alguno (último
    // recurso, ver más abajo). Sobre el shape seguido, el IMU aporta dos señales:
    //   - calibratedAccel(): modula la velocidad con magnitud realista (_drNextSpeed)
    //   - headingRad: si diverge sostenidamente del heading del shape seguido,
    //     se interpreta como desvío real y se re-ancla sobre el tile caché en la
    //     nueva dirección (_buildDrNrShape con el heading IMU)
    // Actualiza _lastRealTickPos y _realTickMs para que el interpTimer siga a 20 Hz.
    function _drSimulateTick(ms) {
        var dt = (_realTickMs > 0) ? (ms - _realTickMs) / 1000.0 : 1.0
        dt = Math.max(0.1, Math.min(5.0, dt))

        var useNr = _drLeftRoute || (_drNrShape && _drNrShape.length > 1 && (!routeShape || routeShape.length < 2))
        var shape = useNr ? _drNrShape : routeShape
        var idx   = useNr ? _drNrIdx   : (_lastRealTickPos ? _lastRealTickPos.idx  : 0)
        var frac  = useNr ? _drNrFrac  : (_lastRealTickPos ? _lastRealTickPos.frac : 0.0)

        // ── Sin shape disponible (ni ruta ni tile caché): último recurso, IMU libre ─
        if (!shape || shape.length < 2) {
            if (imu && imu.calibrated) {
                var spdFree = _drNextSpeed(dt, _drSpeedMs)
                imu.advance(spdFree, dt)
                _speedMs     = spdFree
                realSpeedKmh = spdFree * 3.6
                _headRad     = imu.headingRad
                _realTickMs  = ms
                _emit(imu.imuLat, imu.imuLon, spdFree * 3.6, imu.headingRad, _hasFix, true, ms, "dr")
                return
            }
            drActive = false; _drNrShape = null; _drLeftRoute = false
            return
        }

        // ── Velocidad objetivo: límite de vía × ratio observado al entrar en DR ────
        var spdTarget = _drSpeedMs
        if (!useNr && interpUseVhRatio && routeShapeSpeedKmh
                && _lastRealTickPos && _lastRealTickPos.idx < routeShapeSpeedKmh.length) {
            var vVh = routeShapeSpeedKmh[_lastRealTickPos.idx] / 3.6
            if (vVh > 0.1 && _drSpeedMs > 0.1) {
                var ratio = Math.max(0.1, Math.min(3.0, _drSpeedMs / vVh))
                spdTarget = vVh * ratio
            }
        }
        var spd = _drNextSpeed(dt, spdTarget)

        var pos = _walkOn(shape, idx, frac, spd * dt)
        if (!pos) { drActive = false; _drNrShape = null; _drLeftRoute = false; return }

        var n   = shape.length
        var hdg = _bearing(shape[pos.idx][1], shape[pos.idx][0],
                           shape[Math.min(pos.idx + 1, n - 1)][1],
                           shape[Math.min(pos.idx + 1, n - 1)][0])

        // ── Detección de desvío sostenido: heading IMU vs heading del shape seguido ─
        // Cooldown obligatorio entre reanclajes: roads_near() abre la BD SQLite del
        // caché de tiles y decodifica MVT en el hilo principal — caro si se repite a
        // menudo. Sin este límite, una deriva de heading IMU sostenida (esperable en
        // túneles largos sin GPS que la corrija) puede seguir cumpliendo el umbral
        // cada ~1.5-2s indefinidamente. Confirmado en prueba real (2026-07-24, túnel
        // cerca de Tiana): re-disparo cada ~2s durante ~50s, la app dejó de responder
        // y el gestor de sesiones la mató y relanzó.
        if (imu && imu.calibrated) {
            var hdgDiff = Math.abs(_angleDiff(imu.headingRad, hdg))
            _drDeviateMs = (hdgDiff > 0.44) ? (_drDeviateMs + dt) : 0   // > ~25°
            if (_drDeviateMs >= 1.5) {   // sostenido ≥1.5 s: desvío real, no ruido
                _drDeviateMs = 0
                if (ms - _drLastDeviateAnchorMs > 15000) {   // máx. 1 reanclaje cada 15s
                    _drLastDeviateAnchorMs = ms
                    var _nrs = _buildDrNrShape(pos.lat, pos.lon, imu.headingRad)
                    if (_nrs) {
                        _drNrShape = _nrs.coords; _drNrIdx = _nrs.idx; _drNrFrac = _nrs.frac
                        _drLeftRoute = true
                        console.log("[DR] Desvío sostenido detectado, re-anclado a vía de tile caché")
                    }
                }
            }
        }

        _speedMs     = spd
        realSpeedKmh = spd * 3.6
        _headRad     = hdg
        _realTickMs  = ms

        if (useNr) { _drNrIdx = pos.idx; _drNrFrac = pos.frac }

        _emit(pos.lat, pos.lon, spd * 3.6, hdg, _hasFix, true, ms, "dr")
    }

    function _applyTurnFilter() {
        var dir = _headRateRads > 0.02 ? 1 : (_headRateRads < -0.02 ? -1 : 0)
        if (dir !== 0 && dir === _turnDirPrev) _turnConsec++
        else _turnConsec = (dir !== 0) ? 1 : 0
        _turnDirPrev = dir
        _headRateRads = (_turnConsec >= 3) ? _headRateRads * 0.25 : 0
    }

    function _geoDest(la, lo, hdg, distM) {
        var R = 6371000, d = distM / R
        var f = la * Math.PI / 180, l = lo * Math.PI / 180
        var f2 = Math.asin(Math.sin(f)*Math.cos(d) + Math.cos(f)*Math.sin(d)*Math.cos(hdg))
        var l2 = l + Math.atan2(Math.sin(hdg)*Math.sin(d)*Math.cos(f),
                                 Math.cos(d) - Math.sin(f)*Math.sin(f2))
        return {lat: f2 * 180/Math.PI, lon: l2 * 180/Math.PI}
    }
}
