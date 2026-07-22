/*
 * Copyright (C) 2026  Edi
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 */

import QtQuick 2.7
import QtQuick.Controls 2.15
import QtQuick.Window 2.2
import QtPositioning 5.4
import QtQuick.LocalStorage 2.0
import Qt.labs.settings 1.0
import MapboxMap 1.0

import Navius 1.0
import "SimTestRoutes.js" as SimTestRoutes
import "NavSearch.js" as NavSearch
import "NavAlerts.js" as NavAlerts
import "NavMessages.js" as NavMessages
import "NavSettings.js" as NavSettings

ApplicationWindow {
    id: root
    objectName: 'mainView'

    // Tamaño inicial = pantalla completa. Antes era units.gu(45)×units.gu(80)
    // (el "phone portrait" de Ubuntu Touch), pero con el grid unit ya ajustado
    // a la escala real de Phosh eso pedía una ventana mucho más pequeña que la
    // pantalla y dependía de que el compositor la maximizara.
    width:   Screen.width  > 0 ? Screen.width  : units.gu(45)
    height:  Screen.height > 0 ? Screen.height : units.gu(80)
    visible: true

    SatelliteModel { id: satModel }
    NavHttp        { id: navHttp  }
    NavTts         { id: navTts  }
    // Modo silencio = mute total: ningún sonido (voz ni pitidos) pase lo que pase.
    Binding { target: navTts; property: "muted"; value: root._soundCap === "silencio" }
    NavTracker     { id: navTracker }
    NavTileCache   { id: tileCache  }
    NavImu         { id: navImu; gpsActive: true }

    NavPower {
        id: navPower
        inhibit: appSettings.inhibitSuspend && Qt.application.state === Qt.ApplicationActive
    }
    Timer {
        id: navTrackerPollTimer
        interval: 100; repeat: true; running: true
        onTriggered: {
            navTracker.poll()
            var sp = navTts.is_speaking()
            if (sp !== root.ttsSpeaking) root.ttsSpeaking = sp
        }
    }
    Timer {
        id: msgPollTimer
        interval: 60000; repeat: true; running: mainAuthSettings.token !== "" && appSettings.privacyAccepted
        onTriggered: {
            var sinceId = deviceMsgSt.lastMsgId
            NavMessages.fetchMsgs(deviceMsgSt.deviceId, mainAuthSettings.token, sinceId,
                function(msgs, err) { root._onMsgFetched(msgs, err, false) })
        }
    }
    Connections {
        target: navTracker
        function onSim_route_ready(id, json, route) {
            var act = root._pendingSimAction
            if (!act) return
            root._pendingSimAction = null
            var pts = []
            try { pts = JSON.parse(json) } catch(e) {}
            if (pts.length < 2) {
                root._startupMsg = "Track sin puntos suficientes"
                startupMsgTimer.restart()
                return
            }
            if (!appSettings.simMode) { appSettings.simMode = true; root.simSignalLost = false }
            if (act.type === "applyIdx") {
                _radarFijos = []; _radarTramos = []
                _updateRadarLayers(); alertCanvas.requestPaint()
                prefsPanel.visible = false
                root.simRoute = pts
                gpsSource.simStart()
            } else if (act.type === "trackSim") {
                if (root._navActive) clearRoute()
                // ¿Hay ruta Valhalla guardada y el usuario NO pidió GPS crudo?
                var _savedRoute = null
                if (!act.raw && route && route.length > 0) {
                    try { _savedRoute = JSON.parse(route) } catch(e) { _savedRoute = null }
                }
                root.simRoute = pts
                prefsPanel.visible = false
                root._billboardFetchLat = 0
                root._billboardFetchLng = 0
                root._adShownTs = {}; appSettings.adShownJson = "{}"
                var _p0 = pts[0], _pN = pts[pts.length - 1]
                if (mainAuthSettings.token !== "" && appSettings.privacyAccepted)
                    NavAlerts.obtenerBillboards(_p0.lat, _p0.lon, 30, mainAuthSettings.token, function(ok, lista) {
                        if (ok) { root._billboards = lista; alertCanvas.requestPaint() }
                    })
                if (_savedRoute && _savedRoute.shape && _savedRoute.shape.length > 1) {
                    // Modo conducción: replay sobre la ruta Valhalla guardada (snap, bisector
                    // y cálculos como conducir). El track es la fuente de GPS.
                    gpsSource.simRoutePoints   = null
                    gpsSource.simRouteSpeedKmh = null
                    root._trackReplayRaw = false
                    root._simTrackReplay = true
                    root._startNavigation(_savedRoute)
                    root._startupMsg = "Replay: " + act.trackName
                } else {
                    // Modo GPS crudo: track como única geometría, sin ruta Valhalla.
                    gpsSource.simRoutePoints   = pts
                    gpsSource.simRouteSpeedKmh = null
                    NavSearch.fetchSimRouteSpeedsKmh(pts, function(speeds) {
                        gpsSource.simRouteSpeedKmh = speeds
                    })
                    root._trackReplayRaw = true
                    root._simTrackReplay = true
                    gpsSource.simStart()
                    root._startupMsg = (act.raw ? "Replay GPS crudo: " : "Sim: ") + act.trackName
                    var _coordStr = function(lat, lon) { return lat.toFixed(5) + ", " + lon.toFixed(5) }
                    searchPanel.loadDemoRoute(_p0.lat, _p0.lon, _coordStr(_p0.lat, _p0.lon),
                                              _pN.lat, _pN.lon, _coordStr(_pN.lat, _pN.lon))
                }
                startupMsgTimer.restart()
            }
        }
        function onGpx_ready(id, path) {
            if (path !== "") {
                root._startupMsg = "GPX: " + path.split("/").pop()
                startupMsgTimer.restart()
            }
        }
    }

    GpsSource {
        id: gpsSource
        satModel:        satModel
        simRoute:        root.simRoute
        simSpeedBias:       root.simSpeedBias
        commSpeedLimitKmh:  root._commSpeedLimit
        simMinSpeedKmh:  appSettings.simMinSpeedKmh
        simPaused:       root.simPaused
        simSignalLost:   root.simSignalLost
        simMode:         appSettings.simMode
        manualActive:    appSettings.manualPosActive
        manualLat:       appSettings.manualLat
        manualLon:       appSettings.manualLon
        interpolationHz: appSettings.drHz
        useHardwareSpeed: appSettings.useHardwareSpeed
        smoothGps:          appSettings.drEnabled
        snapToRouteEnabled: appSettings.snapToRouteEnabled
        snapDistM:          appSettings.snapDistM
        gpsFailEnabled:  appSettings.gpsFailEnabled
        gpsFailProb:     appSettings.gpsFailProb
        gpsFailDist:     appSettings.gpsFailDist
        gpsFailTicks:    appSettings.gpsFailTicks
        defaultLat:      appSettings.hasLastPos ? appSettings.lastLat : 40.4168
        defaultLon:      appSettings.hasLastPos ? appSettings.lastLon : -3.7038
        tileCache:       tileCache
        imu:             navImu
    }

    Settings {
        id: mainAuthSettings
        category: "auth"
        property string token:    ""
        property string email:    ""
        property bool   recordar: true
        property int    userId:   0
        property bool   settingsChangedSinceSync: false  // hay cambios locales no sincronizados
        property string settingsLastSyncAt:       ""     // ISO de la última sincronización ok
        Component.onCompleted: {
            // Migración: sesiones guardadas antes de que el servidor devolviera el id en el login.
            // Se puede eliminar cuando todos los usuarios hayan vuelto a hacer login.
            if (token !== "" && userId === 0)
                userId = NavAlerts.jwtSub(token)
        }
    }

    Settings {
        id: mainWhatsNewSt
        category: "whatsNew"
        property string lastSeenVersion: ""
    }

    Settings {
        id: deviceMsgSt
        category: "device_msg"
        property string deviceId:   ""
        property int    lastMsgId:  0
    }

    Settings {
        id: appSettings
        property string lightMode:  "auto"   // "day" | "night" | "auto"
        property bool   autoZoom:   true
        property real   lastLat:    40.4168
        property real   lastLon:    -3.7038
        property bool   hasLastPos: false
        property bool   simMode:    false
        property int    drHz:       20     // dead-reckoning rate: 2 | 10 | 20 | 30 | 50 | 75 | 100
        property string bearingMode: "north"  // "north" | "heading"
        property int    autoZoomSecs: 15    // seconds of road visible ahead at current speed
        property real   lastZoom:   16     // map zoom level on last close
        property string mapMode:    "2d"   // "2d" | "3d"  (map/exploration mode)
        property string navMapMode: "3d"  // "2d" | "3d"  (navigation mode)
        property real   pitch3d:    60     // camera tilt in 3D mode (degrees)
        property string navWaypointsJson: ""  // waypoints de ruta activa (persist)
        property bool   wasNavigating: false  // true si la app cerró mientras navegaba
        property bool   debugMode:        false // activa sim GPS, POI
        property bool   tracesEnabled:    false // activa trazas (net_debug, tts, piper) y TUI
        property bool   debugCleanOnExit: false // borra todos los ficheros debug al salir
        property bool   showZoomSlider:  false  // muestra barra lateral de zoom
        property bool   showSimScrubber: false  // muestra el desplegable de posición GPS simulada
        property bool   showVSimDebug:        false // muestra el panel debug de velocidades
        property bool   showGpsSmoothDebug:   false // muestra panel de funciones de suavizado GPS
        property bool   showImuDebug:         false // muestra panel de debug IMU (NavImu)
        property bool   showBisectorDebug:    false // muestra líneas bisector giro mapa en el mapa
        property bool   showSlDebug:     false // muestra el overlay de límites de velocidad por tramo
        property int    speedAlertPct:      2    // % sobre el límite que activa la alerta
        property bool   speedAlertEnabled: true  // activa/desactiva el aviso de exceso de velocidad
        property bool   showRadarFijos:    true  // muestra radares fijos en el mapa
        property bool   showRadarTramo:    true  // muestra radares de tramo en el mapa
        property int    radarAlertDist:    400   // distancia (m) a la que suena el aviso de radar
        property bool   useHardwareSpeed:   true  // velocidad Doppler del chip vs d/dt posiciones
        property bool   drEnabled:         true  // suavizado GPS (dead-reckoning entre ticks)
        property int    simRouteIdx:       0     // 0=Provença→Pl.Catalunya BCN, 1-3=rutas de test, 4=ruta del usuario
        property int    simMinSpeedKmh:    0     // velocidad mínima reportada en sim (debug)
        property bool   manualPosActive:   false
        property real   manualLat:         0
        property real   manualLon:         0
        property string alertSound:        "tts"    // "tts" | "beep" | "off"
        property string instrSound:        "tts"   // "tts" | "beep" | "off"
        property string ttsLang:           "system" // "system" | "es" | "en" | "fr" | "de" | "pt" | "it" | "ca" | "ru" | "zh" | "ar" | "fa"
        property string ttsEngine:         "auto"   // "auto" | "piper" | "picotts" | "espeak"
        property string ttsVoice:          ""       // ID completo de voz Piper seleccionada ("" = automático)
        property string ttsVoicePico:      ""       // variante PicoTTS ("" = automático según idioma)
        property string ttsVoiceEspeak:    ""       // variante espeak-ng ("" = automático según idioma)
        property bool   showChangesAtStartup: true
        property string mapStyleMode: "auto"  // "auto" | "satellite" | "positron" | "bright"
        property bool   show3dBuildings: true
        property string valhallaUrl: "https://valhalla.egpsistemas.com"
        property string valhallaCustomServers: "[]"
        property bool   preferOsmScout: true
        property bool   gpsTracking:       false   // activa grabación de ruta GPS
        property string customSimTracks:   "[]"    // JSON [{id, name}] de rutas grabadas en lista sim
        property string vehiclesJson:      "[]"    // JSON [{id,alias,costing,parkLat,parkLon,hasPark,lastLat,lastLon,hasLast}]
        property string activeVehicleId:   ""      // ID del vehículo activo
        property string measureSystem:     "metric" // "metric" | "imperial"
        property bool   showGpsTicks:      false   // muestra ticks isReal=true en el mapa
        property bool   gpsFailEnabled:    false   // simulación de fallos GPS
        property real   gpsFailProb:       5.00    // probabilidad de fallo (%)
        property real   gpsFailDist:       50      // desviación máxima del fallo (m)
        property int    gpsFailTicks:      3       // ticks isReal=true con señal perdida
        property int    mapCacheMaxMb:    500      // tamaño máximo caché de tiles (MB)
        property string mapOnlineSource:   "mapbox" // "mapbox" | "osmscout"  fuente cuando hay internet
        property string mapOfflineMode:    "osmscout"  // "cache" | "osmscout"   cuando sin internet
        property string mapTileServer:     "navius"   // "external" | "navius"
        property string mapNaviusDayStyle: "liberty"  // "liberty" | "positron" | "bright" | "fiord"
        property string mapNaviusStyles:   '["positron","bright","fiord","dark"]' // estilos extra del servidor navius (además de auto y satélite)
        property string overpassServer:    "navius"   // "external" | "navius"
        property bool   routeAdjustZoom:   true     // usa velocidades Valhalla de tramos para autoZoom
        property int    routeAheadSecs:        10   // segundos de anticipación del giro de ruta (1-45)
        property int    maxPredictiveTurnDeg:  30   // ángulo máximo de giro predictivo del mapa (°, 0-90)
        property bool   snapToRouteEnabled: true   // ajustar posición visual al shape de la ruta
        property int    snapDistM:          11      // distancia máx de ajuste a la ruta (m, 5-15)
        property int    offRouteDistM:     11       // distancia para detectar desvío y recalcular (m, 5-15)
        property real   textScale:         1.0      // escala global de texto (0.8 – 1.5)
        property real   uiScale:           1.0      // escala global de la UI: multiplica el grid unit
                                                    // (lo lee Rust al arrancar, ver src/i18n_units.rs;
                                                    //  requiere reiniciar para aplicarse)
        property bool   inhibitSuspend:      true   // inhibe suspensión durante navegación activa
        property bool   showRoadSpeedLimit:  false  // mostrar límite de la vía (fuente no fiable)
        property real   duckVolume:          0.70   // volumen de música durante TTS (0.10 – 1.00)
        property string adShownJson:         "{}"   // {id: timestamp} cooldown de anuncios (persiste entre sesiones)
        property int    prefLevel:           0      // 0=Mínimo, 1=Medio, 2=Avanzado
        property bool   privacyAccepted:    false  // usuario aceptó la política de privacidad
        property bool   privacyShown:       false  // el banner de privacidad ya se mostró al menos una vez
    }

    // Detectar cambios en settings sincronizables → debounce → sync automático
    Connections {
        target: appSettings
        onBearingModeChanged:       if (!root._settingsSyncBlocked) root._onSettingChanged()
        onAutoZoomSecsChanged:      if (!root._settingsSyncBlocked) root._onSettingChanged()
        onMapModeChanged:           if (!root._settingsSyncBlocked) root._onSettingChanged()
        onNavMapModeChanged:        if (!root._settingsSyncBlocked) root._onSettingChanged()
        onPitch3dChanged:           if (!root._settingsSyncBlocked) root._onSettingChanged()
        onMapStyleModeChanged:      if (!root._settingsSyncBlocked) root._onSettingChanged()
        onShow3dBuildingsChanged:   if (!root._settingsSyncBlocked) root._onSettingChanged()
        onShowZoomSliderChanged:    if (!root._settingsSyncBlocked) root._onSettingChanged()
        onShowSimScrubberChanged:   if (!root._settingsSyncBlocked) root._onSettingChanged()
        onMapCacheMaxMbChanged:     if (!root._settingsSyncBlocked) root._onSettingChanged()
        onMapOnlineSourceChanged:   if (!root._settingsSyncBlocked) root._onSettingChanged()
        onMapOfflineModeChanged:    if (!root._settingsSyncBlocked) root._onSettingChanged()
        onMapTileServerChanged:     if (!root._settingsSyncBlocked) root._onSettingChanged()
        onMapNaviusDayStyleChanged: if (!root._settingsSyncBlocked) root._onSettingChanged()
        onMapNaviusStylesChanged:   if (!root._settingsSyncBlocked) root._onSettingChanged()
        onValhallaUrlChanged:       if (!root._settingsSyncBlocked) root._onSettingChanged()
        onValhallaCustomServersChanged: if (!root._settingsSyncBlocked) root._onSettingChanged()
        onPreferOsmScoutChanged:    if (!root._settingsSyncBlocked) root._onSettingChanged()
        onOverpassServerChanged:    if (!root._settingsSyncBlocked) root._onSettingChanged()
        onRouteAdjustZoomChanged:      if (!root._settingsSyncBlocked) root._onSettingChanged()
        onRouteAheadSecsChanged: {
            if (!root._settingsSyncBlocked) root._onSettingChanged()
            if (appSettings.bearingMode === "heading") {
                if (gpsSource.simRoutePoints) {
                    var _d = gpsSource._simWantedVisibleAheadDistM(appSettings.routeAheadSecs)
                    root._mapBearingDeg = gpsSource._simRouteIdealBisectorRad(_d, gpsSource.mapHeadRad) * 180 / Math.PI
                    mapView._bearingAuto = true
                    mapView.bearing = root._mapBearingDeg
                    mapView._bearingAuto = false
                }
            }
        }
        onSnapToRouteEnabledChanged:   if (!root._settingsSyncBlocked) root._onSettingChanged()
        onSnapDistMChanged:            if (!root._settingsSyncBlocked) root._onSettingChanged()
        onOffRouteDistMChanged:        if (!root._settingsSyncBlocked) root._onSettingChanged()
        onDrHzChanged:              if (!root._settingsSyncBlocked) root._onSettingChanged()
        onDrEnabledChanged:         if (!root._settingsSyncBlocked) root._onSettingChanged()
        onUseHardwareSpeedChanged:  if (!root._settingsSyncBlocked) root._onSettingChanged()
        onSpeedAlertPctChanged:     if (!root._settingsSyncBlocked) root._onSettingChanged()
        onSpeedAlertEnabledChanged: if (!root._settingsSyncBlocked) root._onSettingChanged()
        onShowRadarFijosChanged:    if (!root._settingsSyncBlocked) root._onSettingChanged()
        onShowRadarTramoChanged:    if (!root._settingsSyncBlocked) root._onSettingChanged()
        onRadarAlertDistChanged:    if (!root._settingsSyncBlocked) root._onSettingChanged()
        onShowRoadSpeedLimitChanged:if (!root._settingsSyncBlocked) root._onSettingChanged()
        onInhibitSuspendChanged:    if (!root._settingsSyncBlocked) root._onSettingChanged()
        onDuckVolumeChanged:        if (!root._settingsSyncBlocked) root._onSettingChanged()
        onAlertSoundChanged:        if (!root._settingsSyncBlocked) root._onSettingChanged()
        onInstrSoundChanged:        if (!root._settingsSyncBlocked) root._onSettingChanged()
        onTtsLangChanged:           if (!root._settingsSyncBlocked) root._onSettingChanged()
        onTtsEngineChanged:         if (!root._settingsSyncBlocked) root._onSettingChanged()
        onTtsVoiceChanged:          if (!root._settingsSyncBlocked) root._onSettingChanged()
        onTtsVoicePicoChanged:      if (!root._settingsSyncBlocked) root._onSettingChanged()
        onTtsVoiceEspeakChanged:    if (!root._settingsSyncBlocked) root._onSettingChanged()
        onTextScaleChanged:         if (!root._settingsSyncBlocked) root._onSettingChanged()
        onMeasureSystemChanged:     if (!root._settingsSyncBlocked) root._onSettingChanged()
        onShowChangesAtStartupChanged: if (!root._settingsSyncBlocked) root._onSettingChanged()
        onVehiclesJsonChanged:      if (!root._settingsSyncBlocked) root._onSettingChanged()
    }

    property bool   ttsSpeaking:     false
    onTtsSpeakingChanged: mediaPanel.duck(ttsSpeaking)

    property bool   _osmScoutActive:   false  // true si OSM Scout Server detectado al arrancar
    property bool   _mapOffline:       false  // true cuando sin internet (detectado por OfflineBanner)
    property bool   _tileServerFailed: false  // true cuando servidor tiles no responde → usando OSM Scout
    property bool   _rerouteBeepedOffline: false  // ya avisamos de sin internet; no repetir hasta restaurar
    property bool   _settingsSyncBlocked: true    // true durante arranque y apply; false en uso normal
    property string _shareToken:   ""             // token del share activo (vacío = no compartiendo)
    property bool   _shareCreating: false         // esperando respuesta de POST /share
    property var    _telemBuf:     []             // buffer de puntos GPS para telemetría batch
    property int    _telemRealCount: 0            // ticks reales acumulados en el buffer
    property string _startupMsg:    ""      // mensaje temporal en barra de estado al arrancar
    property bool   _radarFetchWarned: false // ya se avisó de fallo de radares; evita repetir en cada bbox

    property var    _statusQueue:   []      // cola de mensajes de error {text, color}
    property var    _statusCurrent: null    // mensaje mostrándose ahora

    // Límite temporal de sonido (no persiste, no toca appSettings)
    // "todo" | "alertas" (instr→beep) | "pitidos" (todo→beep) | "silencio"
    property string _soundCap: "todo"
    readonly property string _effAlertSound:
        _soundCap === "silencio" ? "off"
        : _soundCap === "pitidos" ? (appSettings.alertSound === "off" ? "off" : "beep")
        : appSettings.alertSound
    readonly property string _effInstrSound:
        _soundCap === "silencio" ? "off"
        : (_soundCap === "pitidos" || _soundCap === "alertas") ? (appSettings.instrSound === "off" ? "off" : "beep")
        : appSettings.instrSound

    // Offset para botones derecha cuando el scrubber de sim está visible
    readonly property real _scrubOff: simScrubber.visible ? (simScrubber.width + units.gu(0.5)) : 0
    // Ancho de ítems del menú (landscape: 1 columna scrollable)
    readonly property real _menuItemW: root._isLandscape ? units.gu(27) : units.gu(28)

    // ── Variables de tema global para overlays sobre el mapa ─────────────
    // Modos oscuros: "dark" (noche), "fiord", "satellite". Resto son fondos claros.
    readonly property bool _mapIsLight: {
        var m = mapView._forcedStyle !== "" ? mapView._forcedStyle : appSettings.mapStyleMode
        if (m === "fiord" || m === "dark" || m === "satellite") return false
        if (m !== "auto") return true  // positron, bright → siempre claro
        if (mapView._nightMode) return false
        // auto+día: depende del estilo día navius (fiord es oscuro)
        if (mapView._navius && appSettings.mapNaviusDayStyle === "fiord") return false
        return true
    }
    readonly property color _uiBorder: _mapIsLight ? "#CC666666" : "#99FFFFFF"  // contornos/bordes
    readonly property color _uiFg:     _mapIsLight ? "#DD333333" : "#FFFFFFFF"  // texto e iconos
    readonly property color _uiBtnBg:  _mapIsLight ? "#4DFFFFFF" : "#4D12122A" // fondo botones menú 30% alfa

    function _pushStatus(text, color) {
        var clr = color || "#EF9A9A"
        if (_statusCurrent && _statusCurrent.text === text) return
        for (var _qi = 0; _qi < _statusQueue.length; _qi++)
            if (_statusQueue[_qi].text === text) return
        var _q = _statusQueue.slice()
        _q.push({text: text, color: clr})
        _statusQueue = _q
        if (!_statusCurrent) {
            var _q2 = _statusQueue.slice()
            _statusCurrent = _q2.shift()
            _statusQueue = _q2
            _statusQueueTimer.restart()
        }
    }

    property bool _menuOpen:      false   // menú lateral izquierdo desplegado
    property bool _mapLocked:    false   // bloquea pan/zoom del mapa

    // Mensajes servidor
    property int  _msgUnread:     0
    property bool _msgBannerShow: false
    property int  _msgNewCount:   0
    property var  _msgNewMsgs:    []
    property bool _msgInitDone:   false

    function _makeDeviceId() {
        var chars = "0123456789abcdef"
        var s = ""
        for (var i = 0; i < 32; i++) {
            if (i===8||i===12||i===16||i===20) s += "-"
            s += chars[Math.floor(Math.random() * 16)]
        }
        return s
    }

    function _msgBannerColor() {
        for (var i = 0; i < root._msgNewMsgs.length; i++)
            if (root._msgNewMsgs[i].importancia === "urgente") return "#FF5252"
        for (var j = 0; j < root._msgNewMsgs.length; j++)
            if (root._msgNewMsgs[j].importancia === "importante") return "#FF9800"
        return "#1E88E5"
    }

    function _onMsgFetched(msgs, err, isInit) {
        if (err || !msgs) { if (isInit) root._msgInitDone = true; return }
        // Separar mensajes de acción (sistema) de los mensajes visibles al usuario
        var actionBillboard = false
        var visibleMsgs = []
        for (var a = 0; a < msgs.length; a++) {
            if (msgs[a].tipo === "aviso" && msgs[a].titulo === "fetch_billboards")
                actionBillboard = true
            else
                visibleMsgs.push(msgs[a])
        }
        messagesPanel.addNewMsgs(visibleMsgs)
        var maxId = deviceMsgSt.lastMsgId
        for (var i = 0; i < msgs.length; i++)
            if (msgs[i].id > maxId) maxId = msgs[i].id
        deviceMsgSt.lastMsgId = maxId
        // Badge total no leídos
        var unread = 0
        var allMsgs = messagesPanel._msgs
        for (var j = 0; j < allMsgs.length; j++) if (!allMsgs[j].leido_en) unread++
        root._msgUnread = unread
        // Banner de nuevos mensajes solo en polls (no en carga inicial)
        if (!isInit && visibleMsgs.length > 0 && !msgDetailPopup.visible && !messagesPanel.visible) {
            var newArr = root._msgNewMsgs.slice()
            for (var k = 0; k < visibleMsgs.length; k++) if (!visibleMsgs[k].leido_en) newArr.push(visibleMsgs[k])
            root._msgNewMsgs = newArr
            root._msgNewCount = newArr.length
            if (newArr.length > 0) root._msgBannerShow = true
        }
        if (isInit) root._msgInitDone = true
        // Acción: el servidor ha creado un billboard nuevo para este vehículo
        if (actionBillboard) {
            root._billboardFetchLat = 0
            root._billboardFetchLng = 0
            root._fetchBillboards()
        }
    }

    function _addNavDest(lat, lon, nombre) {
        msgDetailPopup.visible = false
        messagesPanel.visible  = false
        root._menuOpen         = false
        if (root._navActive)
            searchPanel._insertPoiInRoute(lat, lon, nombre)
        else
            searchPanel.addDest(lat, lon, nombre)
        searchPanel.visible = true
    }
    property bool _driveCtrlActive: false // modo control manual del vehículo
    property bool _revModeActive:   false // modo dirección inversa (simMode+debugMode)
    property int  _slDebugTick:   0       // incrementa al acabar enrichSpeedLimits → refresca overlay debug
    property string _slDebugText: {
        var _t = root._slDebugTick; var _s = navBar._step
        if (!appSettings.showSlDebug || !root._navData || !root._navData.maneuvers) return ""
        var mans = root._navData.maneuvers
        var lines = []
        function fmt(v) { return (v > 0 ? ("" + v).padStart(3) : "  -") }
        for (var i = 0; i < mans.length; i++) {
            var m   = mans[i]
            var cur = (i === navBar._step) ? "▶" : " "
            var use = fmt(m.speed_limit)
            var osm = fmt(m._slOsm)
            var val = fmt(m._slVal)
            var leg = fmt(m._slLegal)
            var src    = (m.speed_limit_src || "-")
            var rc     = (m._roadClass || "-")
            var manSpd = (m.length > 0 && m.time > 0) ? fmt(Math.round(m.length / m.time * 3.6)) : "  -"
            var pfx    = cur + (""+i).padStart(2)           // "▶  3" o "   3"
            var blank  = "   " + " ".repeat((""+i).length)  // misma anchura que pfx, sin marcador
            lines.push(pfx   + "  →" + use + "  OSM:" + osm + "  V:" + val + "  M:" + manSpd + "  L:" + leg)
            lines.push(blank + "  [" + src + "]  " + rc)
        }
        return lines.join("\n")
    }

    // Hereda el límite del último tramo válido para salidas de rotonda con datos erróneos de Valhalla.
    // type===27 = ExitRoundabout; trace_attributes suele snappear a vías adyacentes incorrectas.
    function _propagateRoundaboutSpeeds(mans) {
        var lastGood = null
        for (var i = 0; i < mans.length; i++) {
            var m = mans[i]
            var isExit = (m.type === 27)
            var suspicious = (m._roadClass === "service_other" || m._roadClass === "residential") &&
                             (m.speed_limit_src === "valhalla") && (m.speed_limit > 0)
            if (isExit && suspicious && lastGood) {
                m.speed_limit     = lastGood.speed_limit
                m.speed_limit_src = lastGood.speed_limit_src + "→rot"
                m._slOsm          = lastGood._slOsm
                m._slVal          = lastGood._slVal
                m._slLegal        = lastGood._slLegal
                m._roadClass      = lastGood._roadClass
                m._dbgSpeed       = lastGood._dbgSpeed
            }
            if (m.speed_limit > 0 && m.type !== 26 && m.type !== 27)
                lastGood = m
        }
    }

    function _writeSlDebugFile() {
        if (!appSettings.showSlDebug || !root._navData || !root._navData.maneuvers) return
        var mans = root._navData.maneuvers
        var now  = new Date()
        var ts   = now.toISOString().replace("T", " ").substring(0, 19)
        var lines = []
        lines.push("=== Navius speed limit debug  " + ts + " ===")
        lines.push("Tramos: " + mans.length + "   Servidor: " + NavSearch.valhallaHost())
        lines.push("")
        var shape  = root._navData.shape || []
        lines.push("Tramo  →uso  OSM   V     M     L     Fuente               Clase")
        lines.push("─────────────────────────────────────────────────────────────────────")
        function fv(v) { return (v > 0 ? ("" + v).padStart(4) : "   -") }
        function fs(s, n) { return (s || "-").padEnd(n) }
        function fcoord(m) {
            var idx = m.begin_shape_index
            if (idx === undefined || !shape[idx]) return ""
            var pt = shape[idx]
            return "  [" + pt[1].toFixed(5) + "," + pt[0].toFixed(5) + "]"
        }
        for (var i = 0; i < mans.length; i++) {
            var m      = mans[i]
            var manSpd = (m.length > 0 && m.time > 0) ? Math.round(m.length / m.time * 3.6) : 0
            var line1  = ("Tramo " + (i+1)).padEnd(7) +
                         fv(m.speed_limit)  + " " +
                         fv(m._slOsm)       + "  " +
                         fv(m._slVal)       + "  " +
                         fv(manSpd)         + "  " +
                         fv(m._slLegal)     + "  " +
                         fs(m.speed_limit_src, 20) +
                         (m._roadClass || "-") +
                         fcoord(m)
            var instr  = (m.instruction || "").substring(0, 70)
            lines.push(line1)
            lines.push("       " + instr)
            lines.push("")
        }
        satModel.write_text_file("navius_sl_debug.txt", lines.join("\n"))
    }

    // ── Escalado dinámico del menú ─────────────────────────────────────────
    property int  _menuVisCount: {
        var n = 4  // Ajustes + Bloq.Mapa + Debug + Guardar.Aparcamiento
        if (root._navActive) n++
        if (appSettings.debugMode) n += 3
        if (appSettings.debugMode && appSettings.simMode) n += 2
        var av = vehicleManager.activeVehicle()
        if (av && av.hasPark && av.costing !== "pedestrian") n += 2  // Borrar + Ver vehículo aparcado
        try {
            var vArr = JSON.parse(appSettings.vehiclesJson || "[]")
            if (vArr.filter(function(v){ return v.hasPark && v.costing !== "pedestrian" }).length > 0) n++
        } catch(e) {}
        return n
    }
    property real _menuItemH: {
        if (root._isLandscape) return units.gu(7)  // Flickable gestiona overflow
        var sp = units.gu(0.5)
        var topY = root._navBarScreenHeight + units.gu(1.5) + units.gu(9) + sp
        var avail = root.height - topY - sp
        var rows = Math.ceil(_menuVisCount / 1)
        var needed = rows * units.gu(8) + (rows - 1) * sp
        return needed > avail ? Math.max(units.gu(4.5), (avail - (rows - 1) * sp) / rows) : units.gu(8)
    }

    // ── Estado de navegación ───────────────────────────────────────────────
    property bool _checkVoiceAfterTour: false
    property bool _navActive:  false   // navegación paso a paso activa
    property bool _navPaused:  false   // pausa temporal de la operativa de navegación
    property var  _navRoutes:  []      // alternativas de ruta
    property int  _navSelIdx:  0       // alternativa seleccionada
    property var  _navData:    null    // ruta activa ({shape,maneuvers,length,time})
    property var  _navDests:     []      // waypoints guardados para recálculo
    property var  _navOpts:      ({})   // opciones de ruta guardadas para recálculo
    property var  _lastNavDests: []     // _navDests del último viaje completado
    property var  _lastNavOpts:  ({})   // _navOpts del último viaje completado
    property var  _lastNavShape: null   // shape del último viaje (para backtrack sim)
    property var  _ttsPregenKeys:  ({})  // text → clave de caché TTS pregenerada
    property bool   _ttsPregenBusy:     false  // true mientras se generan locuciones de distancia
    property string _ttsPregenProgress: ""    // "X/Y" durante la pre-generación
    property var  _previewShape: []     // shape activo en RouteSelectPanel preview
    property var  _routeRadarCounts: [] // nº radares por ruta, paralelo a routeSelectPanel.routes (-1 = cargando)

    // Lanza fetchRadars por cada ruta de la lista y va rellenando _routeRadarCounts.
    function _fetchRouteRadarCounts(routes) {
        var counts = []
        for (var i = 0; i < routes.length; i++) counts.push(-1)
        root._routeRadarCounts = counts
        routes.forEach(function(rd, idx) {
            NavSearch.fetchRadars(rd.shape, function(result) {
                var c = root._routeRadarCounts.slice()
                if (idx >= c.length) return
                c[idx] = result.error ? -1 : (result.fijos.length + result.tramos.length)
                root._routeRadarCounts = c
            })
        })
    }

    // ── Tráfico (re-ruteo periódico) ──────────────────────────────────────────
    property var  _trafficAltRoute:     null
    property int  _trafficTimeSavedSec: 0
    property bool _trafficBannerVisible: false
    property bool _trafficChecking:     false

    // ── Marcador de posición (long press) ────────────────────────────────────
    property real _pinLat:     0
    property real _pinLon:     0
    property bool _pinVisible: false

    // ── Radares ───────────────────────────────────────────────────────────────
    readonly property int _maxTramoLayers: 4
    property var  _radarFijos:     []      // [{lat,lon,maxspeed}]
    property var  _radarTramos:   []      // [{shape,maxspeed,lengthM}]
    property var  _commAlertas:   []      // [{lat,lng,categoria,...}] alertas comunitarias
    property var  _billboards:    []      // [{id,lat,lng,bearing,titulo,subtitulo,url}] billboards publicitarios
    property real _billboardFetchLat: 0   // lat del último fetch de billboards
    property real _billboardFetchLng: 0   // lng del último fetch de billboards
    property var  _adPanelBb:    null     // billboard activo en el panel de anuncio (null = oculto)
    property var  _adShownTs:    ({})     // {id: timestamp} cooldown de anuncios mostrados
    property var  _voteAlerta:    null   // alerta seleccionada para votar
    property var  _autostartPos:  null   // {lat, lon} posición inicial del autostart, aplicada en initLayers
    property var  _gpsTickDots:   []      // [{lat,lon}] ticks isReal=true (debug)
    property var  _pendingSimAction: null // contexto de carga async de track sim
    property bool _simTrackReplay:   false // cuando true, _startNavigation no sobreescribe simRoute
    property bool _trackReplayActive: false // true mientras se reproduce un track grabado
    property bool _trackReplayRaw:   false // true = replay GPS crudo (track como geometría, sin ruta Valhalla)
    property bool _snapToRoute:   true    // false cuando distFromRoute > 25 m
    property var  _activeTramo:   null    // tramo en el que estamos actualmente
    property real _tramoFrac:     0       // 0..1 progreso a través del tramo activo
    property real _tramoSpeedSum:     0   // acumulado km/h para velocidad media
    property int  _tramoSpeedSamples: 0   // número de muestras
    property real _tramoAvgSpeed:     0   // velocidad media km/h en el tramo activo
    property real _tramoSpeedAlertMs: 0   // timestamp ms del último aviso de exceso en tramo
    property var  _nextFijo:      null    // radar fijo más cercano por delante
    property real _nextFijoDist:  1e9    // distancia al mismo (m)
    property bool _radarAlert:    false  // cualquier alerta activa (backward compat)
    property string _radarAlertMsg: ""
    property int  _radarAlertMaxspeed: 0
    property bool _radarApproachingTramo: false
    property bool _radarContrario:        false
    // Alertas separadas: tramo y fijo son independientes y coexisten
    property bool   _tramoAlertActive:   false
    property string _tramoAlertMsg:      ""
    property int    _tramoAlertMaxspeed: 0
    property bool   _fijoAlertActive:    false
    property string _fijoAlertMsg:       ""
    property int    _fijoAlertMaxspeed:  0
    property bool   _fijoContrario:      false
    property bool   _commAlertActive:   false
    property string _commAlertMsg:      ""
    property int    _commAlertId:       -1
    property int    _commAlertSpeed:    0    // velocidad del radar/alerta activa (0=sin dato)
    property var    _commLimites:       []   // lista de límites comunitarios del área
    property var    _tapCommLimit:      null // límite comunitario tapeado en el mapa
    property int    _commSpeedLimit:    0    // límite comunitario activo (0=ninguno)
    property int    _commSpeedLimitId: -1   // id del límite que lo activó
    property int    _lastNavStep:      -1   // step anterior para detectar cambio de tramo
    // Bbox del último fetch de radar por viewport (evita refetch innecesario)
    property real _radarBboxMinLat: 0; property real _radarBboxMaxLat: 0
    property real _radarBboxMinLon: 0; property real _radarBboxMaxLon: 0
    property bool _radarFetching:   false
    property var  _parkingSpots:    []   // [{parkLat, parkLon, alias}] vehículos con aparcamiento
    property bool _anyPanelOpen:    _menuOpen || searchPanel.visible || satPanel.visible
                                    || prefsPanel.visible || pinPanel.visible
                                    || routeViewPanel.visible || routeSelectPanel.visible
                                    || sharedLocationDialog.visible
                                    || osmScoutDialog.visible || vehicleSetupDialog.visible
                                    || parkingDialog.visible || stopTodoPanel.visible
                                    || mediaPanel.visible

    // Estado de vista guardado para restaurar tras cambio de estilo o cierre de opciones
    property string _savedBearingMode:   "north"
    property bool   _savedFollowMode:    false
    property string _savedEffMode:       "2d"
    property bool   _mapViewStateSaved:  false

    // Modo landscape: divide pantalla en panel izquierdo 1/3 (instrucciones+botones) + mapa 2/3
    readonly property bool _isLandscape: width > height
    readonly property bool _searchingGps: !appSettings.simMode && !appSettings.manualPosActive && !satModel.pos_has_fix
    // Altura que NavBar ocupa en la parte superior del MAPA (0 en landscape)
    readonly property real _navBarScreenHeight: _isLandscape ? 0 : (navBar.height + adPanel.height)
    // Altura adicional de banners de alerta (radar/tramo/comunitario) — solo para menuBtn/soundBtn
    readonly property real _alertBannerHeight: _isLandscape ? 0
        : (radarAlertBanner.height + fijoAlertBanner.height
           + tramoBar.height + commAlertBanner.height)
    // Pantalla de carga: solo visible durante la carga inicial, no en cambios de estilo posteriores
    property bool _initialLoadDone: false

    function _setEffectiveUrl(url) {
        NavSearch.setValhallaUrl(url)
        searchPanel.setNavUrl(url)
        // fallback sólo si el usuario lo pide explícitamente (botón "Usar servidor público")
        NavSearch.setFallbackUrl(null)
        searchPanel.setFallbackNavUrl(null)
    }

    function _saveMapViewState() {
        _savedBearingMode  = appSettings.bearingMode
        _savedFollowMode   = mapView.followMode
        _savedEffMode      = root._navActive ? appSettings.navMapMode : appSettings.mapMode
        _mapViewStateSaved = true
    }
    function _restoreMapViewState() {
        _mapViewStateSaved = false
        _applyMapMode(_savedEffMode)
        appSettings.bearingMode = _savedBearingMode
        mapView.followMode      = _savedFollowMode
    }

    // Proyección geo→pantalla (fórmula idéntica a posOverlayRoot._screenPos).
    // Los accesos a propiedades de mapView aseguran que el binding se actualice.
    function _geoToScreen(lat, lon) {
        var mpp = mapView.metersPerPixel
        if (mpp <= 0) return Qt.point(-9999, -9999)
        var cl = mapView._centerLat, co = mapView._centerLon
        var dE = (lon - co) * 111319.49 * Math.cos(cl * Math.PI / 180)
        var dN = (lat - cl) * 111319.49
        var B = mapView.bearing * Math.PI / 180
        var dFwd   = dN * Math.cos(B) + dE * Math.sin(B)
        var dRight = dE * Math.cos(B) - dN * Math.sin(B)
        if (mapView.pitch < 1)
            return Qt.point(mapView.width/2 + dRight/mpp, mapView.height/2 - dFwd/mpp)
        var P = mapView.pitch * Math.PI / 180
        var cosP = Math.cos(P), sinP = Math.sin(P)
        var f = mapView.height / (2 * Math.tan(mapView._fovAngle * Math.PI / 180))
        var dnm = f * mpp + dFwd * sinP
        if (Math.abs(dnm) < 1e-6) return Qt.point(-9999, -9999)
        return Qt.point(mapView.width/2 + f * dRight / dnm,
                        mapView.height/2 - f * dFwd * cosP / dnm)
    }

    // Punto en el shape de la ruta a distM metros por delante de la posición actual.
    function _routeAheadPoint(distM) {
        var rd = navBar.routeData
        if (!rd || !rd.shape || rd.shape.length < 2) return null
        var shape = rd.shape
        var snapI = gpsSource._curShapeIdx
        var snapF = gpsSource._curShapeFrac
        if (snapI >= shape.length - 1) return null
        var rem    = distM
        var cosLat = Math.cos((shape[snapI][1] || 0) * Math.PI / 180)
        var K      = 111319
        for (var i = snapI; i < shape.length - 1; i++) {
            var p0 = shape[i], p1 = shape[i + 1]
            var sLat = (p1[1] - p0[1]) * K
            var sLon = (p1[0] - p0[0]) * K * cosLat
            var segLen   = Math.sqrt(sLat * sLat + sLon * sLon)
            var startF   = (i === snapI) ? snapF : 0
            var remSeg   = segLen * (1 - startF)
            if (rem <= remSeg) {
                var t = startF + rem / segLen
                return { lat: p0[1] + t * (p1[1] - p0[1]),
                         lon: p0[0] + t * (p1[0] - p0[0]) }
            }
            rem -= remSeg
        }
        var last = shape[shape.length - 1]
        return { lat: last[1], lon: last[0] }
    }

    // Bisector de los rumbos a los puntos del shape que cubren los próximos distM metros.
    // Para cada vértice (y el punto de corte final) computa el rumbo desde (aLat,aLon).
    // Devuelve la diferencia relativa al rumbo del vehículo en grados (centro de
    // [bearing mínimo relativo, bearing máximo relativo]). null si no hay puntos válidos.
    // Es el "punto izquierdo máximo / punto derecho máximo" — los extremos angulares
    // del trazado próximo, no el punto medio en arco (que no representa el tramo entero).
    function _routeAheadBisectorRel(distM, vehDeg, aLat, aLon) {
        var rd = navBar.routeData
        if (!rd || !rd.shape || rd.shape.length < 2 || distM < 5) return null
        var shape = rd.shape
        var snapI = gpsSource._curShapeIdx
        var snapF = gpsSource._curShapeFrac
        if (snapI >= shape.length - 1) return null

        var cosLat = Math.cos(aLat * Math.PI / 180)
        var K      = 111319
        var minRel =  360, maxRel = -360
        var rem    = distM
        var skipNearM = 5.0

        for (var i = snapI; i < shape.length - 1 && rem > 0; i++) {
            var p0 = shape[i], p1 = shape[i + 1]
            var sLat = (p1[1] - p0[1]) * K
            var sLon = (p1[0] - p0[0]) * K * cosLat
            var segLen = Math.sqrt(sLat * sLat + sLon * sLon)
            var startF = (i === snapI) ? snapF : 0
            var remSeg = segLen * (1 - startF)
            var endF
            if (rem <= remSeg) { endF = startF + rem / segLen; rem = 0 }
            else               { endF = 1.0;                    rem -= remSeg }
            var lat = p0[1] + endF * (p1[1] - p0[1])
            var lon = p0[0] + endF * (p1[0] - p0[0])
            var dLat = (lat - aLat) * K
            var dLon = (lon - aLon) * K * cosLat
            var distPt = Math.sqrt(dLat * dLat + dLon * dLon)
            if (distPt < skipNearM) continue
            var brg = Math.atan2(dLon, dLat) * 180 / Math.PI
            var rel = (((brg - vehDeg) % 360) + 540) % 360 - 180
            if (rel < minRel) minRel = rel
            if (rel > maxRel) maxRel = rel
        }
        if (minRel > 180 || maxRel < -180) return null
        return (minRel + maxRel) / 2
    }

    // Metros de ruta cubiertos en secsAhead segundos según velocidades Valhalla de cada tramo.
    function _routeAheadDistM(secsAhead) {
        var man = navBar.routeData ? navBar.routeData.maneuvers : null
        if (!man || !man.length) return 0
        var step = navBar._step
        var rem  = secsAhead
        var dist = 0
        // Ratio velocidad real / Valhalla del tramo actual (clamped 0.1–3.0)
        var curVhSpd = (man[step] ? NavSearch.segSpeedKmh(man[step], navBar.commSpeedLimit) : 0) / 3.6
        var ratio = (curVhSpd > 0.1 && gpsSource._speedMs > 0)
                    ? Math.max(0.1, Math.min(3.0, gpsSource._speedMs / curVhSpd)) : 1.0
        // Tramo actual
        var curSpd  = curVhSpd * ratio
        var curRemM = navBar._stepDistKm * 1000
        if (curSpd > 0) {
            var curTime = curRemM / curSpd
            if (curTime >= rem) return dist + rem * curSpd
            dist += curRemM
            rem  -= curTime
        }
        // Tramos siguientes: mismo ratio aplicado a velocidad Valhalla de cada tramo
        for (var m = step + 1; m < man.length && rem > 0; m++) {
            var mSpd   = NavSearch.segSpeedKmh(man[m], navBar.commSpeedLimit) / 3.6 * ratio
            var mDistM = man[m].length * 1000
            if (mSpd > 0) {
                var mTime = mDistM / mSpd
                if (mTime >= rem) return dist + rem * mSpd
                dist += mDistM
                rem  -= mTime
            }
        }
        return dist
    }

    property real _radarLastCheckLat:  999
    property real _radarLastCheckLon:  999
    readonly property real _radarSearchRadiusM: 2000  // radio de búsqueda por posición

    // Carga radares alrededor de la posición actual del mapa (sin navegar).
    // Radio fijo de _radarSearchRadiusM, independiente del zoom/tamaño de viewport.
    function _fetchRadarsViewport() {
        if (_radarFetching || mapView.metersPerPixel <= 0) return
        var cl = mapView._centerLat, co = mapView._centerLon
        // Timer periódico: si el mapa sigue exactamente donde estaba en el último
        // tick, no repetir el cálculo (el margen de coverLat de abajo nunca da
        // "cubierto" cuando el bbox recién calculado coincide con el guardado,
        // así que sin este guard reintentaría indefinidamente parado).
        if (cl === _radarLastCheckLat && co === _radarLastCheckLon) return
        _radarLastCheckLat = cl; _radarLastCheckLon = co
        var hLat = _radarSearchRadiusM / 111319
        var hLon = _radarSearchRadiusM / (111319 * Math.cos(cl * Math.PI / 180))
        var minLat = cl - hLat, maxLat = cl + hLat
        var minLon = co - hLon, maxLon = co + hLon
        // Comprobar si la posición sigue cubierta por el último fetch (75%)
        var coverLat = (_radarBboxMinLat > 0) &&
                       (minLat >= _radarBboxMinLat + (maxLat - minLat) * 0.25) &&
                       (maxLat <= _radarBboxMaxLat - (maxLat - minLat) * 0.25) &&
                       (minLon >= _radarBboxMinLon + (maxLon - minLon) * 0.25) &&
                       (maxLon <= _radarBboxMaxLon - (maxLon - minLon) * 0.25)
        if (coverLat) return
        _radarFetching = true
        _radarBboxMinLat = minLat; _radarBboxMaxLat = maxLat
        _radarBboxMinLon = minLon; _radarBboxMaxLon = maxLon
        NavSearch.fetchRadarsBbox(minLat, minLon, maxLat, maxLon, function(result) {
            root._radarFijos  = result.fijos
            root._radarTramos = result.tramos
            root._updateRadarLayers()
            // La respuesta "fromCache" es solo un adelanto instantáneo de la caché local;
            // _radarFetching sigue true hasta que la petición real a Overpass concluye,
            // para no lanzar peticiones solapadas mientras se conduce.
            if (result.fromCache) return
            _radarFetching  = false
            root._handleRadarFetchResult(result)
        })
    }

    // Avisa una vez si falla la obtención de radares (todos los servidores Overpass agotados);
    // no repite el aviso hasta que un fetch vuelva a tener éxito.
    function _handleRadarFetchResult(result) {
        if (result.error) {
            if (!root._radarFetchWarned) {
                root._radarFetchWarned = true
                root._startupMsg = i18n.tr("⚠ No se pudieron obtener los radares · revisa la conexión")
                startupMsgTimer.restart()
            }
        } else {
            root._radarFetchWarned = false
        }
    }

    function _clearRadarState() {
        _radarFijos  = []; _radarTramos  = []
        _activeTramo = null; _tramoFrac  = 0
        _nextFijo    = null; _nextFijoDist = 1e9
        _radarAlert  = false; _radarAlertMsg = ""; _radarAlertMaxspeed = 0; _radarApproachingTramo = false; _radarContrario = false
        _tramoAlertActive = false; _tramoAlertMsg = ""; _tramoAlertMaxspeed = 0
        _fijoAlertActive = false; _fijoAlertMsg = ""; _fijoAlertMaxspeed = 0; _fijoContrario = false
        _commAlertActive = false; _commAlertMsg = ""; _commAlertId = -1; _commAlertSpeed = 0
        _commSpeedLimit = 0; _commSpeedLimitId = -1; _commLimites = []; _lastNavStep = -1
        _tramoSpeedAlertMs = 0
        if (mapView._layersInit) {
            for (var i = 0; i < _maxTramoLayers; i++)
                mapView.setLayoutProperty("radar-tramo-line-" + i, "visibility", "none")
        }
        alertCanvas.requestPaint()
    }

    function _updateRadarLayers() {
        if (!mapView._layersInit) return
        for (var i = 0; i < _maxTramoLayers; i++) {
            if (i < _radarTramos.length && appSettings.showRadarTramo) {
                var coords = []
                var s = _radarTramos[i].shape
                for (var j = 0; j < s.length; j++)
                    coords.push(QtPositioning.coordinate(s[j][1], s[j][0]))
                mapView.updateSourceLine("radar-tramo-" + i, coords)
                mapView.setLayoutProperty("radar-tramo-line-" + i, "visibility", "visible")
            } else {
                mapView.setLayoutProperty("radar-tramo-line-" + i, "visibility", "none")
            }
        }
        alertCanvas.requestPaint()
    }

    // Comprueba si el punto (aLat, aLon) está a ≤ margin m de la ruta activa.
    // Devuelve {onRoute, arcDist} donde arcDist es la distancia por ruta desde la posición actual.
    // Si no hay ruta activa siempre devuelve onRoute=true para no filtrar nada.
    function _routeInfo(aLat, aLon, margin) {
        if (!root._navActive || !root._navData || !root._navData.shape)
            return { onRoute: true, arcDist: -1 }
        var shape = root._navData.shape  // [[lon, lat], ...]
        if (shape.length < 2) return { onRoute: true, arcDist: -1 }
        var curLat = activeModel.pos_lat, curLon = activeModel.pos_lon
        if (!curLat || !curLon) return { onRoute: true, arcDist: -1 }
        var cosL   = Math.cos(curLat * Math.PI / 180)
        var mPerLL = 111319
        // Punto de la ruta más cercano a la posición actual
        var startI = 0, minD = 1e9
        for (var k = 0; k < shape.length; k++) {
            var dkx = (shape[k][0] - curLon) * mPerLL * cosL
            var dky = (shape[k][1] - curLat) * mPerLL
            var dk  = Math.sqrt(dkx*dkx + dky*dky)
            if (dk < minD) { minD = dk; startI = k }
        }
        // Proyectar la alerta sobre los segmentos de ruta a partir de startI (hasta 1 km)
        var axm = (aLon - curLon) * mPerLL * cosL
        var aym = (aLat - curLat) * mPerLL
        var bestPerp = 1e9, bestArc = 1e9, cumArc = 0
        for (var si = startI; si < shape.length - 1 && cumArc < 1000; si++) {
            var s0x = (shape[si  ][0] - curLon) * mPerLL * cosL
            var s0y = (shape[si  ][1] - curLat) * mPerLL
            var s1x = (shape[si+1][0] - curLon) * mPerLL * cosL
            var s1y = (shape[si+1][1] - curLat) * mPerLL
            var dx = s1x - s0x, dy = s1y - s0y
            var segLen = Math.sqrt(dx*dx + dy*dy)
            var tp = segLen > 0
                ? Math.max(0, Math.min(1, ((axm-s0x)*dx + (aym-s0y)*dy) / (segLen*segLen)))
                : 0
            var nx = s0x + tp*dx, ny = s0y + tp*dy
            var perp = Math.sqrt((axm-nx)*(axm-nx) + (aym-ny)*(aym-ny))
            if (perp < bestPerp) { bestPerp = perp; bestArc = cumArc + tp * segLen }
            cumArc += segLen
        }
        return { onRoute: bestPerp <= margin, arcDist: bestArc < 1e9 ? bestArc : -1 }
    }

    function _checkRadar() {
        var lat = activeModel.pos_lat, lon = activeModel.pos_lon
        if (!lat || !lon) return
        var cosL = Math.cos(lat * Math.PI / 180)
        var spdMs = activeModel.pos_speed_kmh / 3.6
        var alertDist = Math.max(appSettings.radarAlertDist, spdMs * 20)
        var headRad = root._drHeadRad
        var halfPi = Math.PI / 2
        var prevActiveTramo = root._activeTramo

        // Radares fijos — solo si el radar está por delante (diferencia de rumbo < 90°)
        _nextFijo = null; _nextFijoDist = 1e9
        var _nextFijoIsContrario = false
        var _nextFijoArcDist = -1
        if (appSettings.showRadarFijos) {
            for (var fi = 0; fi < _radarFijos.length; fi++) {
                var r = _radarFijos[fi]
                var dlat = (r.lat - lat) * 111319, dlon = (r.lon - lon) * 111319 * cosL
                var d = Math.sqrt(dlat*dlat + dlon*dlon)
                var brgR = geoHeading(lat, lon, r.lat, r.lon)
                var dhR = Math.abs(brgR - headRad)
                if (dhR > Math.PI) dhR = 2 * Math.PI - dhR
                if (dhR >= halfPi) continue   // radar por detrás o lateral

                // Con ruta activa: filtrar radares que no estén sobre la ruta (margen 40 m)
                var riF = _routeInfo(r.lat, r.lon, 40)
                if (!riF.onRoute) continue

                // Comprobar dirección del radar (tag OSM) respecto a nuestro rumbo
                var isContrario = false
                if (r.direction >= 0) {
                    var radarDirRad = r.direction * Math.PI / 180
                    var ddR = Math.abs(radarDirRad - headRad)
                    if (ddR > Math.PI) ddR = 2 * Math.PI - ddR
                    if (ddR > halfPi) isContrario = true
                }
                // Preferir mismo sentido sobre contrario; dentro de igual sentido, el más cercano
                if (_nextFijo === null ||
                    (!isContrario && _nextFijoIsContrario) ||
                    (isContrario === _nextFijoIsContrario && d < _nextFijoDist)) {
                    _nextFijoDist = d; _nextFijo = r; _nextFijoIsContrario = isContrario
                    _nextFijoArcDist = riF.arcDist
                }
            }
            if (_nextFijoDist > alertDist) {
                _nextFijo = null; _nextFijoDist = 1e9; _nextFijoIsContrario = false; _nextFijoArcDist = -1
            }
        }

        // Radares de tramo
        _activeTramo = null; _tramoFrac = 0; _radarApproachingTramo = false
        var approachDist = 1e9
        var approachTramoInfo = null
        var pxm = lon * 111319 * cosL, pym = lat * 111319
        if (appSettings.showRadarTramo) {
            for (var ti = 0; ti < _radarTramos.length; ti++) {
                var t = _radarTramos[ti]
                // Proyección sobre cada segmento para posición continua y distancia mínima real
                var bestSegDist = 1e9, bestSegCum = 0, segCum = 0
                for (var si = 0; si < t.shape.length - 1; si++) {
                    var axm = t.shape[si][0]   * 111319 * cosL, aym = t.shape[si][1]   * 111319
                    var bxm = t.shape[si+1][0] * 111319 * cosL, bym = t.shape[si+1][1] * 111319
                    var dx = bxm - axm, dy = bym - aym
                    var segLen = Math.sqrt(dx*dx + dy*dy)
                    var tp = segLen > 0 ? Math.max(0, Math.min(1, ((pxm-axm)*dx + (pym-aym)*dy) / (segLen*segLen))) : 0
                    var nx = axm + tp*dx, ny = aym + tp*dy
                    var dist = Math.sqrt((pxm-nx)*(pxm-nx) + (pym-ny)*(pym-ny))
                    if (dist < bestSegDist) { bestSegDist = dist; bestSegCum = segCum + tp * segLen }
                    segCum += segLen
                }
                if (bestSegDist < 100) {
                    _activeTramo = t
                    _tramoFrac = t.lengthM > 0 ? Math.min(1, Math.max(0, bestSegCum / t.lengthM)) : 0
                    break
                }
                // Aproximación al tramo — buscar el primer punto del tramo que esté en nuestra ruta
                // (cubre tanto entrada por el inicio como entrada por el medio del tramo)
                var bestEntryArc = 1e9, bestEntryDist = 1e9
                for (var pi = 0; pi < t.shape.length; pi++) {
                    var p = t.shape[pi]
                    var dlatp = (p[1] - lat) * 111319, dlonp = (p[0] - lon) * 111319 * cosL
                    var dp = Math.sqrt(dlatp*dlatp + dlonp*dlonp)
                    if (dp > alertDist) continue
                    var brgP = geoHeading(lat, lon, p[1], p[0])
                    var dhP = Math.abs(brgP - headRad)
                    if (dhP > Math.PI) dhP = 2 * Math.PI - dhP
                    if (dhP >= halfPi) continue
                    var riP = _routeInfo(p[1], p[0], 40)
                    if (!riP.onRoute) continue
                    // Elegir el punto que encontraremos antes por la ruta
                    var effArc = riP.arcDist >= 0 ? riP.arcDist : dp
                    if (effArc < bestEntryArc) { bestEntryArc = effArc; bestEntryDist = dp }
                }
                if (bestEntryDist < approachDist) {
                    approachDist = bestEntryDist; _radarApproachingTramo = true
                    approachTramoInfo = {
                        maxspeed: t.maxspeed, dist: bestEntryDist,
                        arcDist: bestEntryArc < 1e9 ? bestEntryArc : -1
                    }
                }
            }
        }

        // Alerta de tramo — dentro del tramo O aproximándose al inicio
        var tramoAlerting = false; var tramoMsg = ""; var tramoTtsMsg = ""; var tramoMaxspeed = 0
        if (_activeTramo) {
            tramoAlerting = true
            var rem = Math.round(_activeTramo.lengthM * (1 - _tramoFrac))
            tramoMsg = "Radar de tramo  ·  " + rem + " m restantes"
            tramoTtsMsg = "Radar de tramo, " + rem + " metros"
            if (_activeTramo.maxspeed > 0) {
                tramoMsg += "  ·  " + _activeTramo.maxspeed + " km/h"
                tramoTtsMsg += ", límite " + _activeTramo.maxspeed + " kilómetros por hora"
            }
            tramoMaxspeed = _activeTramo.maxspeed
        } else if (approachTramoInfo) {
            tramoAlerting = true
            var tramoDispDist = (approachTramoInfo.arcDist > 0) ? approachTramoInfo.arcDist : approachTramoInfo.dist
            tramoMsg = "Radar de tramo  ·  a " + Math.round(tramoDispDist) + " m"
            tramoTtsMsg = "Radar de tramo en " + Math.round(tramoDispDist) + " metros"
            if (approachTramoInfo.maxspeed > 0) {
                tramoMsg += "  ·  " + approachTramoInfo.maxspeed + " km/h"
                tramoTtsMsg += ", límite " + approachTramoInfo.maxspeed + " kilómetros por hora"
            }
            tramoMaxspeed = approachTramoInfo.maxspeed
        }

        // Alerta de fijo — independiente del tramo
        var fijoAlerting = false; var fijoMsg = ""; var fijoTtsMsg = ""; var fijoMaxspeed = 0; var fijoContrario = false
        if (_nextFijo) {
            fijoAlerting = true
            if (_nextFijoIsContrario) {
                fijoMsg = "Radar sentido contrario  ·  " + Math.round(_nextFijoDist) + " m"
                fijoTtsMsg = "Radar sentido contrario en " + Math.round(_nextFijoDist) + " metros"
                fijoContrario = true
            } else {
                var fijoDispDist = (_nextFijoArcDist > 0) ? _nextFijoArcDist : _nextFijoDist
                fijoMsg = "Radar  ·  " + Math.round(fijoDispDist) + " m"
                fijoTtsMsg = "Radar en " + Math.round(fijoDispDist) + " metros"
                if (_nextFijo.maxspeed > 0) {
                    fijoMsg += "  ·  " + _nextFijo.maxspeed + " km/h"
                    fijoTtsMsg += ", límite " + _nextFijo.maxspeed + " kilómetros por hora"
                }
                fijoMaxspeed = _nextFijo.maxspeed
            }
        }

        // Sonido — flanco de subida independiente para cada canal
        // En modo peatón se muestran radares visualmente pero sin avisos de audio
        var _isPedestrian = vehicleManager.activeCosting() === "pedestrian"
        if (!_isPedestrian) {
            if (tramoAlerting && !_tramoAlertActive) {
                if (root._effAlertSound === "beep") navTts.alert_beep()
                else if (root._effAlertSound === "tts") { navTts.alert_beep(); navTts.say(tramoTtsMsg) }
            }
            if (fijoAlerting && !_fijoAlertActive) {
                if (root._effAlertSound === "beep") navTts.alert_beep()
                else if (root._effAlertSound === "tts") { navTts.alert_beep(); navTts.say(fijoTtsMsg) }
            }
        }

        _tramoAlertActive   = tramoAlerting
        _tramoAlertMsg      = tramoMsg
        _tramoAlertMaxspeed = tramoMaxspeed
        _fijoAlertActive    = fijoAlerting
        _fijoAlertMsg       = fijoMsg
        _fijoAlertMaxspeed  = fijoMaxspeed
        _fijoContrario      = fijoContrario
        _radarAlert         = tramoAlerting || fijoAlerting
        _radarAlertMsg      = tramoAlerting ? tramoMsg : fijoMsg
        _radarAlertMaxspeed = tramoMaxspeed || fijoMaxspeed
        _radarContrario     = fijoContrario

        // Velocidad media en tramo
        if (_activeTramo !== null) {
            if (prevActiveTramo === null) {
                _tramoSpeedSum = 0; _tramoSpeedSamples = 0
                _tramoSpeedAlertMs = 0
            }
            _tramoSpeedSum     += activeModel.pos_speed_kmh
            _tramoSpeedSamples += 1
            _tramoAvgSpeed      = _tramoSpeedSum / _tramoSpeedSamples

            // Aviso periódico (cada 10 s) si velocidad media excede el límite del tramo
            if (_activeTramo.maxspeed > 0 && appSettings.speedAlertEnabled && root._effAlertSound !== "off" && !_isPedestrian) {
                var tramolim = _activeTramo.maxspeed * (1 + appSettings.speedAlertPct / 100.0)
                if (_tramoAvgSpeed > tramolim) {
                    var nowMs = Date.now()
                    if (_tramoSpeedAlertMs <= 0 || (nowMs - _tramoSpeedAlertMs) >= 20000) {
                        _tramoSpeedAlertMs = nowMs
                        navTts.alert_beep()
                        if (root._effAlertSound === "tts") {
                            navTts.say("Velocidad media excedida en el radar de tramo")
                        }
                    }
                } else {
                    _tramoSpeedAlertMs = 0
                }
            }
        } else {
            _tramoAvgSpeed = 0
            _tramoSpeedAlertMs = 0
        }
    }

    function _checkCommAlerts() {
        var lat = activeModel.pos_lat, lon = activeModel.pos_lon
        if (!lat || !lon || root._commAlertas.length === 0) {
            _commAlertActive = false; _commAlertMsg = ""; _commAlertId = -1; _commAlertSpeed = 0; return
        }
        var cosL = Math.cos(lat * Math.PI / 180)
        var headRad = root._drHeadRad
        var best = null, bestDist = 1e9, bestArcDist = -1
        for (var i = 0; i < _commAlertas.length; i++) {
            var a = _commAlertas[i]
            var dlat = (a.lat - lat) * 111319
            var dlon = (a.lng - lon) * 111319 * cosL
            var d = Math.sqrt(dlat*dlat + dlon*dlon)
            if (d > 300) continue
            var brgR = geoHeading(lat, lon, a.lat, a.lng)
            var dh = Math.abs(brgR - headRad)
            if (dh > Math.PI) dh = 2 * Math.PI - dh
            if (dh > Math.PI / 2) continue
            // Con ruta activa: filtrar alertas que no estén sobre la ruta (margen 50 m)
            var riA = _routeInfo(a.lat, a.lng, 50)
            if (!riA.onRoute) continue
            if (d < bestDist) { best = a; bestDist = d; bestArcDist = riA.arcDist }
        }
        if (best !== null) {
            _commAlertSpeed = best.velocidad ? best.velocidad : 0
            var _cm = {
                "trafico":"Tráfico","policia":"Policía","accidente":"Accidente",
                "peligro":"Peligro","carretera_cortada":"Cortada",
                "carril_bloqueado":"Carril bloqueado","error_mapa":"Error mapa",
                "mal_tiempo":"Mal tiempo","asistencia":"Asistencia","lugar":"Lugar",
                "denso":"Tráfico denso","detenido":"Detenido",
                "camara_movil":"Cámara móvil","oculto":"Radar oculto",
                "colision_multiple":"Colisión múltiple","obras":"Obras",
                "coche_arcen":"Coche en arcén","semaforo_estropeado":"Semáforo averiado",
                "bache":"Bache","izquierdo":"Carril izq.","derecho":"Carril der.",
                "central":"Carril central","calzada_resbaladiza":"Calzada resbaladiza",
                "inundacion":"Inundación","nieve":"Nieve","niebla":"Niebla","hielo":"Hielo",
                "companeros":"Ayuda compañeros","emergencia":"Emergencia"
            }
            var lbl = (best.subtipo && best.subtipo !== "")
                ? (_cm[best.subtipo] || best.subtipo)
                : (_cm[best.categoria] || best.categoria)
            var _velSuffix = best.velocidad ? "  ·  " + best.velocidad + " km/h" : ""
            var _dispDist = (bestArcDist > 0) ? bestArcDist : bestDist
            _commAlertMsg    = lbl + "  ·  " + Math.round(_dispDist) + " m" + _velSuffix
            // Sonido: flanco de subida o cambio de alerta
            if (best.id !== _commAlertId) {
                _commAlertId = best.id
                var _isPedestrian = vehicleManager.activeCosting() === "pedestrian"
                if (!_isPedestrian) {
                    if (root._effAlertSound === "beep") navTts.alert_beep()
                    else if (root._effAlertSound === "tts") {
                        navTts.alert_beep()
                        var _ttsVel = best.velocidad ? ", límite " + best.velocidad + " kilómetros por hora" : ""
                        navTts.say(lbl + " en " + Math.round(_dispDist) + " metros" + _ttsVel)
                    }
                }
            }
            _commAlertActive = true
        } else {
            _commAlertActive = false; _commAlertMsg = ""; _commAlertId = -1; _commAlertSpeed = 0
        }
    }

    function _checkCommLimits() {
        if (!root._navActive) return
        var lat = activeModel.pos_lat, lon = activeModel.pos_lon
        if (!lat || !lon || root._commLimites.length === 0) return
        var cosL = Math.cos(lat * Math.PI / 180)
        var headRad = root._drHeadRad
        for (var i = 0; i < _commLimites.length; i++) {
            var lim = _commLimites[i]
            var dlat = (lim.lat - lat) * 111319
            var dlon = (lim.lng - lon) * 111319 * cosL
            var d = Math.sqrt(dlat*dlat + dlon*dlon)
            if (d > 40) continue   // solo activar al pasar muy cerca
            // Mismo sentido: diferencia de bearing < 45°
            var db = Math.abs((lim.bearing * Math.PI / 180) - headRad)
            if (db > Math.PI) db = 2 * Math.PI - db
            if (db > Math.PI / 4) continue
            if (lim.id !== _commSpeedLimitId) {
                _commSpeedLimit   = lim.velocidad
                _commSpeedLimitId = lim.id
            }
            return
        }
    }

    // Cancela límite comunitario cuando Valhalla tiene un nuevo límite conocido
    function _onNavStepChanged(newStep) {
        if (_commSpeedLimit <= 0) return
        var man = root._navData && root._navData.maneuvers
        if (!man || newStep >= man.length) return
        if (man[newStep].speed_limit > 0) {
            _commSpeedLimit   = 0
            _commSpeedLimitId = -1
        }
    }

    function _fetchBillboards() {
        if (mainAuthSettings.token === "" || !appSettings.privacyAccepted) return
        var lat = (gpsSource.lat !== 0 || gpsSource.lon !== 0) ? gpsSource.lat : mapView._centerLat
        var lng = (gpsSource.lat !== 0 || gpsSource.lon !== 0) ? gpsSource.lon : mapView._centerLng
        // Al arranque, _centerLat/_centerLng pueden ser undefined (mapa sin posicionar aún)
        if (!isFinite(lat) || !isFinite(lng) || (lat === 0 && lng === 0)) return
        var dlat = lat - root._billboardFetchLat
        var dlng = lng - root._billboardFetchLng
        // Sin ruta: refetch cada ~500 m (0.0045°² ≈ 0.000020); con ruta: cada ~20 km
        var threshold = root._navActive ? 0.032 : 0.000025
        if (root._billboardFetchLat !== 0 && (dlat*dlat + dlng*dlng) < threshold) return
        root._billboardFetchLat = lat
        root._billboardFetchLng = lng
        var radio = root._navActive ? 30 : 5
        NavAlerts.obtenerBillboards(lat, lng, radio, mainAuthSettings.token || "", function(ok, lista) {
            if (ok) {
                root._billboards = lista
                alertCanvas.requestPaint()
            }
        })
    }

    // Comprueba proximidad a billboards y activa el AdPanel si corresponde
    function _checkBillboardProximity(lat, lon) {
        if (root._adPanelBb !== null || root._billboards.length === 0) return
        var now = Date.now()
        var cooldown = 3600000   // 1 h entre impresiones del mismo cartel (persiste entre sesiones)
        for (var _ci = 0; _ci < root._billboards.length; _ci++) {
            var _cb = root._billboards[_ci]
            var _dlat = lat - _cb.lat
            var _dlon = lon - (_cb.lng !== undefined ? _cb.lng : _cb.lon)
            var _distM = Math.sqrt(_dlat*_dlat + _dlon*_dlon) * 111319
            if (_distM < 600) {
                var _lastTs = root._adShownTs[_cb.id] || 0
                if (now - _lastTs > cooldown) {
                    root._adPanelBb = _cb
                    var _ts = root._adShownTs
                    _ts[_cb.id] = now
                    root._adShownTs = _ts
                    appSettings.adShownJson = JSON.stringify(_ts)
                    adPanelTimer.restart()
                    if (root._effAlertSound !== "off") navTts.alert_beep()
                    NavAlerts.registrarImpresion(mainAuthSettings.token || "",
                                                 deviceMsgSt.deviceId || "", _cb.id)
                    break
                }
            }
        }
    }

    // Fetch de límites comunitarios del área (llamado al arrancar ruta y cada 5 min)
    function _fetchCommLimites() {
        if (mainAuthSettings.token === "" || !appSettings.privacyAccepted) return
        var lat = activeModel.pos_lat, lon = activeModel.pos_lon
        if (!lat || !lon) return
        NavAlerts.obtenerLimites(lat, lon, function(ok, lista) {
            if (ok) root._commLimites = lista
        })
    }

    // ── Sincronización de settings con el servidor ───────────────────────────

    // Llamado por Connections cuando cambia cualquier setting sincronizable
    function _onSettingChanged() {
        if (mainAuthSettings.token === "") return  // no logueado → nada
        mainAuthSettings.settingsChangedSinceSync = true
        settingsSyncTimer.restart()
    }

    // Sube los settings locales al servidor; informa vía _statusQueue si hay error
    function _pushSettingsToServer(silent) {
        if (mainAuthSettings.token === "" || !appSettings.privacyAccepted) return
        var snap = NavSettings.snapshot(appSettings)
        NavSettings.putSettings(mainAuthSettings.token, snap, function(ok, errCode) {
            if (ok) {
                mainAuthSettings.settingsChangedSinceSync = false
                mainAuthSettings.settingsLastSyncAt = new Date().toISOString()
                if (!silent)
                    root._statusQueue.push({ text: i18n.tr("✓ Configuración guardada en el servidor"), color: "#81C784" })
            } else if (!silent) {
                var msg = errCode === "net"  ? "Sin conexión: configuración no guardada"
                        : errCode === "401"  ? "Sesión caducada: configuración no guardada"
                        : "Error " + errCode + ": configuración no guardada"
                root._statusQueue.push({ text: msg, color: "#FF8A65" })
            }
        })
    }

    // Descarga los settings del servidor y los aplica; conflicto si hay cambios locales
    function _pullSettingsFromServer(onConflictCallback) {
        if (mainAuthSettings.token === "" || !appSettings.privacyAccepted) return
        NavSettings.getSettings(mainAuthSettings.token, function(ok, data, updatedAt, errCode) {
            if (!ok) {
                if (errCode === "404")
                    // Servidor sin soporte aún → subir los locales para inicializarlo
                    _pushSettingsToServer(true)
                else if (errCode === "net")
                    root._statusQueue.push({ text: i18n.tr("Sin conexión: no se pudo cargar la configuración del servidor"), color: "#FF8A65" })
                else if (errCode !== "401")
                    root._statusQueue.push({ text: i18n.tr("Error al cargar configuración del servidor: ") + errCode, color: "#FF8A65" })
                return
            }
            if (Object.keys(data).length === 0) {
                // Servidor no tiene settings → subir los locales
                _pushSettingsToServer(true)
                return
            }
            // Hay settings en el servidor
            if (mainAuthSettings.settingsChangedSinceSync) {
                // Conflicto: cambios locales no sync + settings en servidor → preguntar
                onConflictCallback(data, updatedAt)
            } else {
                // Sin conflicto: aplicar los del servidor directamente
                _applyServerSettings(data)
            }
        })
    }

    // Aplica un snapshot del servidor a appSettings (bloqueando onChange para evitar bucle)
    function _applyServerSettings(data) {
        root._settingsSyncBlocked = true
        NavSettings.applySnapshot(appSettings, data)
        root._settingsSyncBlocked = false
        mainAuthSettings.settingsChangedSinceSync = false
        mainAuthSettings.settingsLastSyncAt = new Date().toISOString()
    }

    // Timer debounce: 3 s tras el último cambio de setting → sync automático
    Timer {
        id: settingsSyncTimer
        interval: 3000; repeat: false
        onTriggered: _pushSettingsToServer(true)
    }

    // ── Compartir viaje ───────────────────────────────────────────────────────

    Timer {
        id: shareUpdateTimer
        interval: 5000; repeat: true
        running: root._shareToken !== ""
        onTriggered: root._pushShareUpdate()
    }

    // Flush de telemetría: cada 30 s si no se está compartiendo (el share ya alimenta el servidor).
    Timer {
        id: telemFlushTimer
        interval: 30000; repeat: true
        running: mainAuthSettings.token !== "" && appSettings.privacyAccepted && !appSettings.simMode && root._shareToken === ""
        onTriggered: root._flushTelemetria()
    }

    // Renueva el token silenciosamente y llama callback(ok: bool)
    function _refreshToken(callback) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", NavSettings.serverUrl() + "/api/v1/usuarios/refresh")
        xhr.setRequestHeader("Authorization", "Bearer " + mainAuthSettings.token)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText)
                    mainAuthSettings.token = d.token
                    callback(true)
                } catch(e) { callback(false) }
            } else {
                callback(false)
            }
        }
        xhr.send(null)
    }

    function _startSharing() {
        if (!mainAuthSettings.token) { loginPanel.open(); return }
        if (root._shareCreating) return
        tripSharePanel.errorMsg = ""
        root._shareCreating = true
        _doCreateShare()
    }

    function _doCreateShare() {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", NavSettings.serverUrl() + "/api/v1/share")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("Authorization", "Bearer " + mainAuthSettings.token)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200 || xhr.status === 201) {
                try {
                    var d = JSON.parse(xhr.responseText)
                    root._shareToken        = d.token
                    var _shareLang = Qt.locale().name.split("_")[0]
                    tripSharePanel.shareUrl = d.url + "?lang=" + _shareLang
                    tripSharePanel.active   = true
                    tripSharePanel.errorMsg = ""
                    root._shareCreating     = false
                    root._pushShareUpdate()
                } catch(e) {
                    root._shareCreating     = false
                    tripSharePanel.errorMsg = i18n.tr("Error al procesar la respuesta del servidor")
                }
            } else if (xhr.status === 401) {
                // Intentar renovar el token y reintentar una vez
                root._refreshToken(function(ok) {
                    if (ok) {
                        _doCreateShare()
                    } else {
                        root._shareCreating     = false
                        tripSharePanel.errorMsg = i18n.tr("Sesión no válida — vuelve a iniciar sesión")
                    }
                })
            } else if (xhr.status === 0) {
                root._shareCreating     = false
                tripSharePanel.errorMsg = i18n.tr("Sin conexión con el servidor")
            } else {
                root._shareCreating     = false
                tripSharePanel.errorMsg = i18n.tr("Error del servidor (%1)").arg(xhr.status)
            }
        }
        xhr.send(null)
    }

    function _stopSharing() {
        var tok = root._shareToken
        root._shareToken = ""
        tripSharePanel.active = false
        if (!tok) return
        var xhr = new XMLHttpRequest()
        xhr.open("DELETE", NavSettings.serverUrl() + "/api/v1/share/" + tok)
        xhr.setRequestHeader("Authorization", "Bearer " + mainAuthSettings.token)
        xhr.send(null)
    }

    // Al restaurar la ruta tras un cierre/crash: si el usuario ya tenía un viaje
    // compartido activo en el servidor, lo reanuda con el MISMO token/enlace
    // (no crea uno nuevo) y empuja de inmediato la posición/ruta actuales.
    function _resumeSharingIfActive() {
        if (!mainAuthSettings.token || root._shareToken !== "") return
        _doResumeSharing()
    }

    function _doResumeSharing() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", NavSettings.serverUrl() + "/api/v1/share")
        xhr.setRequestHeader("Authorization", "Bearer " + mainAuthSettings.token)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText)
                    var _shareLang = Qt.locale().name.split("_")[0]
                    root._shareToken        = d.token
                    tripSharePanel.shareUrl = d.url + "?lang=" + _shareLang
                    tripSharePanel.active   = true
                    root._pushShareUpdate()
                } catch(e) {}
            } else if (xhr.status === 401) {
                root._refreshToken(function(ok) { if (ok) _doResumeSharing() })
            }
            // 404: no había share activo en el servidor — nada que reanudar
        }
        xhr.send(null)
    }

    function _flushTelemetria() {
        if (root._telemBuf.length === 0 || !appSettings.privacyAccepted) return
        var buf = root._telemBuf
        root._telemBuf       = []
        root._telemRealCount = 0
        var _isDebugTelem = (appSettings.simMode || root._trackReplayActive) && appSettings.debugMode
        NavAlerts.enviarTelemetria(mainAuthSettings.token, deviceMsgSt.deviceId, buf, _isDebugTelem)
    }

    function _pushShareUpdate() {
        if (!root._shareToken) return
        var lat = activeModel.pos_lat || 0
        var lon = activeModel.pos_lon || 0
        var brg = root._dispHeadRad * 180 / Math.PI
        var spd = activeModel.pos_speed_kmh || 0

        // Muestrear shape de la ruta (máx 10000 puntos para conservar detalle de tramos)
        var shape = []
        if (root._navData && root._navData.shape && root._navData.shape.length > 1) {
            var src  = root._navData.shape
            var step = Math.max(1, Math.ceil(src.length / 10000))
            for (var i = 0; i < src.length; i += step) shape.push(src[i])
            if (shape[shape.length - 1] !== src[src.length - 1]) shape.push(src[src.length - 1])
        }

        // Destinos con tiempo/distancia total restante
        var wps = []
        var dests = searchPanel._dests || []
        if (dests.length > 0) {
            wps.push({
                name:    dests[dests.length - 1].name || dests[dests.length - 1].addr || "",
                eta_sec: Math.round(navBar._timeSec  || 0),
                dist_m:  Math.round((navBar._distKm  || 0) * 1000)
            })
        }

        var xhr = new XMLHttpRequest()
        xhr.open("PUT", NavSettings.serverUrl() + "/api/v1/share/" + root._shareToken + "/location")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("Authorization", "Bearer " + mainAuthSettings.token)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 401 || xhr.status === 403) root._stopSharing()
        }
        xhr.send(JSON.stringify({
            lat: lat, lon: lon, bearing: brg, speed: spd,
            route_shape: shape, waypoints: wps
        }))
    }

    // Dibuja las líneas de ruta en el mapa sin tocar zoom ni followMode.
    // Usar durante navegación activa (inicio o rerouteo).
    readonly property int _maxLegs: 6

    function _ttsEffectiveLang() {
        var l = appSettings.ttsLang
        return l === "system" ? Qt.locale().name.split("_")[0] : l
    }

    function _pregenerateUpcoming(fromStep) {
        if (!_navData || !_navData.maneuvers) return
        var man  = _navData.maneuvers
        var lang = _ttsEffectiveLang()
        var count = 0
        for (var i = fromStep; i < man.length && count < 3; i++) {
            var t = man[i].verbal_pre_transition_instruction || man[i].instruction || ""
            if (!t) continue
            t = navBar._fixOrdinales(t)
            var parts = t.split(". ")
            var t1 = parts[0]
            var t2 = parts.length > 1 ? parts.slice(1).join(". ") : ""
            var changed = false
            if (root._ttsPregenKeys[t1] === undefined) {
                var k1 = navTts.pregenerate(t1, lang)
                var tmp1 = root._ttsPregenKeys; tmp1[t1] = k1; root._ttsPregenKeys = tmp1
                changed = true
            }
            if (t2 && root._ttsPregenKeys[t2] === undefined) {
                var k2 = navTts.pregenerate(t2, lang)
                var tmp2 = root._ttsPregenKeys; tmp2[t2] = k2; root._ttsPregenKeys = tmp2
                changed = true
            }
            if (changed) count++
        }
    }

    function _ttsClearCache() {
        navTts.stop_piper_daemon()
        navTts.clear_tts_cache()
        root._ttsPregenKeys = {}
    }

    function _startRoundPregen(lang, imperial) {
        navTts.pregenerate_round_dists(lang, imperial === true)
        navTts.pregenerate_maneuver_phrases(lang)
        root._ttsPregenBusy = true
        ttsPregenPollTimer.start()
    }

    function drawRoute(routes, selIdx) {
        if (!routes || routes.length === 0) { clearRoute(); return }
        _navRoutes = routes
        _navSelIdx = selIdx
        var main = routes[selIdx]
        var ends = main.legShapeEnds && main.legShapeEnds.length > 0
                   ? main.legShapeEnds : [main.shape.length - 1]
        var legStart = 0
        for (var li = 0; li < _maxLegs; li++) {
            if (li < ends.length) {
                var legEnd = ends[li]
                var coords = []
                for (var pi = legStart; pi <= legEnd; pi++)
                    coords.push(QtPositioning.coordinate(main.shape[pi][1], main.shape[pi][0]))
                mapView.updateSourceLine("nav-route-leg-" + li, coords)
                mapView.setLayoutProperty("nav-route-leg-line-" + li, "visibility", "visible")
                legStart = legEnd   // siguiente leg comparte el punto final
            } else {
                mapView.setLayoutProperty("nav-route-leg-line-" + li, "visibility", "none")
            }
        }
        if (routes.length > 1 && selIdx === 0) {
            var alt = routes[1]; var ac = []
            for (var j = 0; j < alt.shape.length; j++)
                ac.push(QtPositioning.coordinate(alt.shape[j][1], alt.shape[j][0]))
            mapView.updateSourceLine("nav-route-alt", ac)
            mapView.setLayoutProperty("nav-route-alt-line", "visibility", "visible")
        } else {
            mapView.setLayoutProperty("nav-route-alt-line", "visibility", "none")
        }
    }

    // Dibuja todas las rutas en modo selección: seleccionada en azul, alternativas en grises progresivos.
    function drawRoutesPreview(routes, selIdx) {
        // Ocultar todas las capas alt antes de redibujar
        mapView.setLayoutProperty("nav-route-alt-line",   "visibility", "none")
        mapView.setLayoutProperty("nav-route-alt-1-line", "visibility", "none")
        mapView.setLayoutProperty("nav-route-alt-2-line", "visibility", "none")

        drawRoute(routes, selIdx)

        var altLayers = ["nav-route-alt", "nav-route-alt-1", "nav-route-alt-2"]
        var layerIdx = 0
        for (var i = 0; i < routes.length; i++) {
            if (i === selIdx) continue
            if (layerIdx >= altLayers.length) break
            var src = altLayers[layerIdx]
            var ac = []
            for (var j = 0; j < routes[i].shape.length; j++)
                ac.push(QtPositioning.coordinate(routes[i].shape[j][1], routes[i].shape[j][0]))
            mapView.updateSourceLine(src, ac)
            mapView.setLayoutProperty(src + "-line", "visibility", "visible")
            layerIdx++
        }
    }

    // Inicia la navegación con la ruta dada. Usado desde searchPanel y routeSelectPanel.
    function _startNavigation(routeData) {
        navBar.showReloadDest = false
        _activeTramo = null; _tramoFrac = 0
        _radarApproachingTramo = false
        _radarAlert = false; _radarAlertMsg = ""; _radarAlertMaxspeed = 0
        _tramoAlertActive = false; _tramoAlertMsg = ""; _tramoAlertMaxspeed = 0
        _fijoAlertActive = false; _fijoAlertMsg = ""; _fijoAlertMaxspeed = 0; _fijoContrario = false
        _commAlertActive = false; _commAlertMsg = ""; _commAlertId = -1; _commAlertSpeed = 0
        _commSpeedLimit = 0; _commSpeedLimitId = -1; _commLimites = []; _lastNavStep = -1
        root._ttsClearCache()
        // Recortar el shape al destino final exacto.
        // Valhalla incluye el arco de vía completo que contiene el destino; se busca
        // la proyección del destino sobre el shape y se sustituye el tramo restante
        // por el punto destino exacto.
        var _sdests = searchPanel.dests
        if (_sdests && _sdests.length > 0 && routeData.shape && routeData.shape.length >= 2) {
            var _dFin = _sdests[_sdests.length - 1]
            var _sArr = routeData.shape
            var _cosD = Math.cos(_dFin.lat * Math.PI / 180), _KD = 111319
            var _projI = _sArr.length - 1, _projT = 1.0, _projDist = Infinity
            for (var _si2 = 0; _si2 < _sArr.length - 1; _si2++) {
                var _p0 = _sArr[_si2], _p1 = _sArr[_si2 + 1]
                var _sdLat = (_p1[1] - _p0[1]) * _KD
                var _sdLon = (_p1[0] - _p0[0]) * _KD * _cosD
                var _sLen2 = _sdLat * _sdLat + _sdLon * _sdLon
                var _dpLat = (_dFin.lat - _p0[1]) * _KD
                var _dpLon = (_dFin.lon - _p0[0]) * _KD * _cosD
                var _tt = _sLen2 > 0 ? (_dpLat * _sdLat + _dpLon * _sdLon) / _sLen2 : 0
                _tt = Math.max(0, Math.min(1, _tt))
                var _rLat = _dpLat - _tt * _sdLat, _rLon = _dpLon - _tt * _sdLon
                var _pd = _rLat * _rLat + _rLon * _rLon
                if (_pd < _projDist) { _projDist = _pd; _projI = _si2; _projT = _tt }
            }
            // Sólo recortar si el destino proyecta antes del último punto (con margen 300 m)
            if (Math.sqrt(_projDist) < 300 && (_projI < _sArr.length - 2 || _projT < 0.999)) {
                var _newShape = _sArr.slice(0, _projI + 1)
                _newShape.push([_dFin.lon, _dFin.lat])   // destino exacto como último punto
                routeData.shape = _newShape
                var _newEnd = _newShape.length - 1
                if (routeData.legShapeEnds && routeData.legShapeEnds.length > 0)
                    routeData.legShapeEnds[routeData.legShapeEnds.length - 1] = _newEnd
                var _mArr = routeData.maneuvers
                if (_mArr && _mArr.length > 0)
                    _mArr[_mArr.length - 1].end_shape_index = _newEnd
            }
        }
        root._navData          = routeData
        // Si se está grabando, asocia la ruta Valhalla actual al track (para replay alineado).
        if (navTracker.recording && !root._trackReplayActive)
            navTracker.set_route_json(JSON.stringify(routeData))
        gpsSource.routeShape      = routeData.shape
        gpsSource.routeShapeLegEnd = (routeData.legShapeEnds && routeData.legShapeEnds.length > 0)
                                     ? routeData.legShapeEnds[0] : -1
        gpsSource._shapeIdx    = 0
        gpsSource._shapeFrac   = 0
        root._adShownTs = {}; appSettings.adShownJson = "{}"
        root._navActive = true
        root._navDests  = searchPanel.dests.slice()
        root._navOpts   = searchPanel.routeOpts
        if (!appSettings.simMode) appSettings.wasNavigating = true

        // Log de ruta en el servidor (solo con sesión activa y GPS real)
        if (!appSettings.simMode && mainAuthSettings.token !== "" && appSettings.privacyAccepted && routeData && routeData.shape) {
            try {
                NavAlerts.logRuta(mainAuthSettings.token, deviceMsgSt.deviceId,
                                  JSON.stringify(routeData.shape))
            } catch(_e) {}
        }
        var _lang = root._ttsEffectiveLang()
        root._startRoundPregen(_lang, navBar.imperial)
        root._pregenerateUpcoming(0)
        // Frase de inicio + instrucción inicial desde caché (distancia + dirección corta).
        // Solo si man[0].time > 150s: así hay margen suficiente antes de que NavBar
        // dispare pre2 (umbral 123s) y no se repite la misma instrucción dos veces.
        if (root._effInstrSound === "tts") {
            var _man = routeData.maneuvers
            var _firstDistMRaw = 0
            var _shortKey = ""
            var _man0time = (_man && _man.length > 1) ? (_man[0].time || 0) : 0
            // Dos casos para instrucción inicial vía play_start_route:
            //  ≤ 20s: maniobra muy cercana → frase corta inmediata antes de que el coche llegue
            //  > 150s: maniobra lejana → aviso anticipado (NavBar cubre el rango 20-150s)
            if (_man0time <= 20 || _man0time > 150) {
                _firstDistMRaw = Math.round((_man[0].length || 0) * 1000)
                if (_firstDistMRaw > 0) {
                    var _m1 = _man[1]
                    _shortKey = navTts.short_maneuver_key(
                        _m1.type || 0,
                        _m1.roundabout_exit_count || 0,
                        _lang)
                }
            }
            navTts.play_start_route(_firstDistMRaw, _shortKey, _lang, navBar.imperial)
        }
        var routes = root._navRoutes.length > 0 ? root._navRoutes : [routeData]
        root.drawRoute(routes, root._navRoutes.length > 0 ? root._navSelIdx : 0)
        root._applyMapMode(appSettings.navMapMode)
        if (appSettings.simMode) {
            var _wasTrackReplay = root._simTrackReplay
            if (!root._simTrackReplay) {
                root.simRoute = root.buildSimRouteFromNavData(routeData)
                if (appSettings.simRouteIdx > 0 && appSettings.simRouteIdx < 4)
                    root._remapTramoShapes()
                root.simStart()
            }
            root._simTrackReplay = false
            if (_wasTrackReplay && root._trackReplayRaw) {
                // Replay GPS crudo: el track es la única geometría (sin ruta Valhalla).
                // routeShape y la línea azul dibujada pasan a ser el track, de modo que
                // origen del bisector, snap, interpolación, mapHeadRad y línea usen la
                // misma geometría. Sirve para ver el comportamiento real del GPS al grabar.
                root._trackReplayActive = true
                root._snapToRoute = false
                var _trackShape = []
                for (var _ti = 0; _ti < root.simRoute.length; _ti++)
                    _trackShape.push([root.simRoute[_ti].lon, root.simRoute[_ti].lat])
                gpsSource.routeShape        = _trackShape
                gpsSource.routeShapeSpeedKmh = null   // las velocidades vienen de simRoute[idx].spd
                gpsSource._shapeIdx  = 0
                gpsSource._shapeFrac = 0
                root.drawRoute([{ shape: _trackShape,
                                  legShapeEnds: [_trackShape.length - 1] }], 0)
                gpsSource.simStart()   // resetea posición a pts[0] en el momento exacto del inicio de nav
                mapView.followMode = true
            } else if (_wasTrackReplay) {
                // Replay con ruta Valhalla guardada = conducir esa ruta con el track como
                // fuente de GPS. routeShape ya es la ruta Valhalla (línea 1581), drawRoute
                // ya dibujó la ruta, snap respeta snapToRouteEnabled. Todo igual que conducir.
                root._trackReplayActive = true
                gpsSource.simStart()
                mapView.followMode = true
            }
            if (appSettings.debugMode) {
                var sh0 = routeData.shape[0]
                var sr0 = root.simRoute[0]
                var _navTs = root._dtLocal()
                root._sessionTracePath = root._traceBasePath + "_" + _navTs
                root._traceLines = root._tsLocal()
                    + " === NAV START shape=" + routeData.shape.length
                    + " sim=" + root.simRoute.length
                    + " shape[0]=" + sh0[1].toFixed(6) + "," + sh0[0].toFixed(6)
                    + " sim[0]=" + sr0.lat.toFixed(6) + "," + sr0.lon.toFixed(6)
                    + "\n"
                root._pendingTickLines = ""
                root._flushTrace()
            }
        }
        NavSearch.enrichSpeedLimits(routeData.shape, routeData.maneuvers, function(enrichedMans) {
            if (!root._navActive || !root._navData) return
            var origMans = root._navData.maneuvers
            if (!origMans) return
            for (var i = 0; i < enrichedMans.length && i < origMans.length; i++) {
                var sl = enrichedMans[i].speed_limit
                if (sl !== undefined && sl > 0) {
                    origMans[i].speed_limit     = sl
                    origMans[i].speed_limit_src = enrichedMans[i].speed_limit_src || ""
                    origMans[i]._dbgSpeed       = enrichedMans[i]._dbgSpeed  || 0
                    origMans[i]._slOsm          = enrichedMans[i]._slOsm     || 0
                    origMans[i]._slVal          = enrichedMans[i]._slVal     || 0
                    origMans[i]._slLegal        = enrichedMans[i]._slLegal   || 0
                    origMans[i]._roadClass      = enrichedMans[i].road_class || ""
                }
            }
            root._propagateRoundaboutSpeeds(origMans)
            root._slDebugTick++; root._writeSlDebugFile()
            if (appSettings.simMode && root._navActive && root._navData && !root._trackReplayActive) {
                var oldLen = gpsSource.simRoute ? gpsSource.simRoute.length : 0
                var newRoute = root.buildSimRouteFromNavData(root._navData)
                var frac = oldLen > 1 ? gpsSource.simIdx / (oldLen - 1) : 0
                var newIdx = Math.min(Math.round(frac * (newRoute.length - 1)), newRoute.length - 2)
                root.simRoute = newRoute
                gpsSource.seekTo(newIdx)
                if (appSettings.simRouteIdx > 0 && appSettings.simRouteIdx < 4)
                    root._remapTramoShapes()
            }
        })
        if (appSettings.simRouteIdx === 0 || appSettings.simRouteIdx === 4) {
            NavSearch.fetchRadars(routeData.shape, function(result) {
                if (!root._navActive) return
                root._radarFijos  = result.fijos
                root._radarTramos = result.tramos
                root._updateRadarLayers()
                root._handleRadarFetchResult(result)
            })
        }
        Qt.callLater(root._fetchCommLimites)
    }

    // Previsualiza la ruta: dibuja + zoom al bounding box + followMode = false.
    // Usar solo en el panel de previsualización (antes de iniciar navegación).
    function applyRoutes(routes, selIdx) {
        if (!routes || routes.length === 0) { clearRoute(); return }
        drawRoute(routes, selIdx)

        // Centra el mapa en el bounding box de la ruta
        var main = routes[selIdx]
        var minLat=90, maxLat=-90, minLon=180, maxLon=-180
        for (var k = 0; k < main.shape.length; k++) {
            var p = main.shape[k]
            if (p[0] < minLon) minLon = p[0];  if (p[0] > maxLon) maxLon = p[0]
            if (p[1] < minLat) minLat = p[1];  if (p[1] > maxLat) maxLat = p[1]
        }
        var cLat = (minLat + maxLat) / 2, cLon = (minLon + maxLon) / 2
        var span = Math.max(maxLat - minLat, (maxLon - minLon) * Math.cos(cLat * Math.PI / 180))
        if (span > 0) {
            var zoom = Math.log(360 / span * mapView.height / 256) / Math.log(2) - 0.5
            mapView._gpsUpdating = true
            mapView.center = QtPositioning.coordinate(cLat, cLon)
            mapView._gpsUpdating = false
            mapView._zoomAuto = true
            mapView.setZoomLevel(Math.max(8, Math.min(16, zoom)),
                                 Qt.point(mapView.width / 2, mapView.height / 2))
            zoomAutoResetTimer.restart()
        }
        mapView.followMode = false
    }

    function _applyMapMode(mode) {
        if (mode === "3d") {
            mapView.animatePitch(appSettings.pitch3d)
            if (root._navActive) {
                appSettings.bearingMode = "heading"
                mapView.followMode = true
            }
        } else {
            mapView.animatePitch(0)
        }
        mapView.apply3dBuildings(mode)
    }

    // Carga una ruta de test por índice (0=Muntaner→Gran Via BCN, 1..3=rutas de test, 4=ruta del usuario).
    // Todos los índices calculan la geometría via Valhalla; simRoute se asigna en onNavigationStarted.
    function _applySimRoute(idx) {
        // Rutas grabadas en lista de sim (idx 5+)
        if (idx >= 5) {
            appSettings.simRouteIdx = idx
            var custom = []
            try { custom = JSON.parse(appSettings.customSimTracks || "[]") } catch(e) {}
            var track = custom[idx - 5]
            if (!track) return
            root._pendingSimAction = { type: "applyIdx" }
            navTracker.get_track_sim_route_async(track.id)
            return
        }
        appSettings.simRouteIdx = idx
        if (idx === 0) {
            _radarFijos  = []
            _radarTramos = []
            _updateRadarLayers()
            alertCanvas.requestPaint()
            prefsPanel.visible = false
            searchPanel.loadDemoRoute(41.3939, 2.1618, "C/ de Provença, Eixample, Barcelona",
                                      41.3871, 2.1700, "Plaça de Catalunya, Barcelona")
        } else {
            // idx 1-3: rutas de test con radares inyectados; idx 4: ruta libre del usuario.
            // En ambos casos la ruta la calcula Valhalla → onNavigationStarted → buildSimRouteFromNavData.
            if (idx < 4) {
                var d = SimTestRoutes.getRoute(idx - 1)
                if (!d) return
                _radarFijos  = d.radarData.fijos
                _radarTramos = d.radarData.tramos
                _updateRadarLayers()
                alertCanvas.requestPaint()
                if (d.endpoints) {
                    var ep = d.endpoints
                    prefsPanel.visible = false
                    searchPanel.loadDemoRoute(ep.originLat, ep.originLon, ep.originName,
                                              ep.destLat,   ep.destLon,   ep.destName)
                }
            } else {
                // "Ruta del usuario"
                _radarFijos  = []
                _radarTramos = []
                _updateRadarLayers()
                alertCanvas.requestPaint()
                prefsPanel.visible     = false
                searchPanel._simOrigin = null
                searchPanel.visible    = true
            }
        }
    }

    function _updateParkingMarkers() {
        var vehs = vehicleManager.allVehicles()
        var spots = []
        for (var vi = 0; vi < vehs.length; vi++) {
            var v = vehs[vi]
            if (v.hasPark && v.costing !== "pedestrian") {
                spots.push({parkLat: v.parkLat, parkLon: v.parkLon, alias: v.alias})
                if (spots.length >= 8) break
            }
        }
        _parkingSpots = spots
    }

    function clearRoute() {
        var dummy = [QtPositioning.coordinate(0, 0), QtPositioning.coordinate(0, 0)]
        for (var li = 0; li < _maxLegs; li++)
            mapView.setLayoutProperty("nav-route-leg-line-" + li, "visibility", "none")
        mapView.updateSourceLine("nav-route-alt", dummy)
        mapView.setLayoutProperty("nav-route-alt-line",   "visibility", "none")
        mapView.setLayoutProperty("nav-route-alt-1-line", "visibility", "none")
        mapView.setLayoutProperty("nav-route-alt-2-line", "visibility", "none")
        _navRoutes = []
        _navData   = null
        _navActive = false
        _navPaused = false
        _trackReplayActive = false
        legArrivalBanner.visible = false
        legArrivalReplayTimer.stop()
        simRoute     = []
        simSpeedBias = 0
        gpsSource.simStop()
        gpsSource.routeShape         = null
        gpsSource.routeShapeSpeedKmh = null
        gpsSource.simRoutePoints     = null
        gpsSource.simRouteSpeedKmh   = null
        gpsSource._shapeIdx  = 0
        gpsSource._shapeFrac = 0
        root._lastBearingMs  = 0
        appSettings.navWaypointsJson = ""
        appSettings.wasNavigating    = false
        _applyMapMode(appSettings.mapMode)
        _clearRadarState()
        _clearTrafficComparison()
        _ttsClearCache()
    }

    // Devuelve waypoint origen con heading si velocidad >= 3 km/h, sin heading si parado.
    function _originWp(lat, lon) {
        if (navBar.gpsSpeedKmh >= 3) {
            var deg = gpsSource._headRad * 180 / Math.PI
            if (deg < 0) deg += 360
            // En revMode el vehículo va al revés: tolerancia mayor para que Valhalla honre el heading invertido
            var tol = root._revModeActive ? 90 : 45
            return {lat: lat, lon: lon, heading: deg, heading_tolerance: tol}
        }
        return {lat: lat, lon: lon}
    }

    // ── Recargar destino: tras llegar al destino, recalcula ruta al mismo punto ──
    function _reloadDestination() {
        if (!root._lastNavDests || root._lastNavDests.length === 0) return
        var lastDests = root._lastNavDests
        var opts = root._lastNavOpts

        if (!appSettings.simMode) {
            // GPS real: desde posición actual al destino anterior
            var wps = [_originWp(activeModel.pos_lat, activeModel.pos_lon)]
            for (var i = 0; i < lastDests.length; i++) wps.push(lastDests[i])
            NavSearch.route(wps, opts, function(err, routes) {
                if (err || !routes || routes.length === 0) return
                _startNavigation(routes[0])
                root._navDests = lastDests.slice()
                root._navOpts  = opts
            })
            return
        }

        // Sim GPS: intentar vía perpendicular distinta (<150 m), si no, retroceder 50 m
        var shape = root._lastNavShape
        if (!shape || shape.length < 2) {
            var p2 = gpsSource._p2
            var wpsF = [_originWp(p2 ? p2.lat : activeModel.pos_lat, p2 ? p2.lon : activeModel.pos_lon)]
            for (var jj = 0; jj < lastDests.length; jj++) wpsF.push(lastDests[jj])
            NavSearch.route(wpsF, opts, function(err, routes) {
                if (!err && routes && routes.length > 0) {
                    _startNavigation(routes[0]); root._navDests = lastDests.slice(); root._navOpts = opts
                }
            })
            return
        }

        var last = shape[shape.length - 1]
        var prev = shape[shape.length - 2]
        var cosL = Math.cos(last[1] * Math.PI / 180)
        var segDLat = (last[1] - prev[1]) * 111319
        var segDLon = (last[0] - prev[0]) * 111319 * cosL
        var segLen  = Math.sqrt(segDLat*segDLat + segDLon*segDLon)
        var perpLat = segLen > 1 ? -segDLon / segLen : 0
        var perpLon = segLen > 1 ?  segDLat / segLen : 1
        var d = 100  // metros
        var cands = [
            {lat: last[1] + perpLat*d/111319, lon: last[0] + perpLon*d/(111319*cosL)},
            {lat: last[1] - perpLat*d/111319, lon: last[0] - perpLon*d/(111319*cosL)}
        ]

        function _tryPerp(idx) {
            if (idx >= cands.length) { root._reloadFallback50m(shape, lastDests, opts); return }
            var c = cands[idx]
            var wps2 = [{lat: c.lat, lon: c.lon}]
            for (var k = 0; k < lastDests.length; k++) wps2.push(lastDests[k])
            NavSearch.route(wps2, opts, function(err, routes) {
                if (!err && routes && routes.length > 0) {
                    var rs = routes[0].shape
                    var dLat = (rs[0][1] - last[1]) * 111319
                    var dLon = (rs[0][0] - last[0]) * 111319 * cosL
                    // Vía distinta si el punto de inicio está a >30 m del destino
                    if (Math.sqrt(dLat*dLat + dLon*dLon) > 30) {
                        _startNavigation(routes[0]); root._navDests = lastDests.slice(); root._navOpts = opts
                        return
                    }
                }
                _tryPerp(idx + 1)
            })
        }
        _tryPerp(0)
    }

    // Fallback: retrocede 50 m por el shape anterior y calcula ruta desde ahí
    function _reloadFallback50m(shape, lastDests, opts) {
        var rem = 50, i = shape.length - 1
        var startLat = shape[0][1], startLon = shape[0][0]
        while (rem > 0 && i > 0) {
            var p0 = shape[i-1], p1 = shape[i]
            var cl = Math.cos(p0[1] * Math.PI / 180)
            var dLat = (p1[1] - p0[1]) * 111319, dLon = (p1[0] - p0[0]) * 111319 * cl
            var sLen = Math.sqrt(dLat*dLat + dLon*dLon)
            if (sLen < 0.01) { i--; continue }
            if (rem <= sLen) {
                var t = 1.0 - rem / sLen
                startLat = p0[1] + (p1[1] - p0[1]) * t
                startLon = p0[0] + (p1[0] - p0[0]) * t
                break
            }
            rem -= sLen; i--
        }
        var wps = [{lat: startLat, lon: startLon}]
        for (var k = 0; k < lastDests.length; k++) wps.push(lastDests[k])
        NavSearch.route(wps, opts, function(err, routes) {
            if (!err && routes && routes.length > 0) {
                _startNavigation(routes[0]); root._navDests = lastDests.slice(); root._navOpts = opts
            }
        })
    }

    function _clearTrafficComparison() {
        if (!_trafficBannerVisible && !trafficRouteDialog.visible && !_trafficAltRoute) return
        trafficRouteDialog.visible = false
        _trafficBannerVisible  = false
        _trafficAltRoute       = null
        _trafficTimeSavedSec   = 0
        _trafficChecking       = false
        var dummy = [[0,0],[0,0]]
        mapView.updateSourceLine("nav-route-alt", dummy)
        mapView.setPaintProperty("nav-route-alt-line", "line-color",   "#78909C")
        mapView.setPaintProperty("nav-route-alt-line", "line-opacity", 0.55)
        mapView.setPaintProperty("nav-route-alt-line", "line-width",   4)
        mapView.setLayoutProperty("nav-route-alt-line", "visibility",  "none")
    }

    function _checkFasterRoute() {
        if (!_navActive || _trafficChecking || _trafficBannerVisible || trafficRouteDialog.visible) return
        if (!_navDests || _navDests.length === 0) return
        if (!activeModel.pos_has_fix) return
        _trafficChecking = true
        var wps = [{lat: activeModel.pos_lat, lon: activeModel.pos_lon}]
        for (var _ti = navBar._completedLegs; _ti < _navDests.length; _ti++) wps.push(_navDests[_ti])
        NavSearch.route(wps, _navOpts, function(err, routes) {
            _trafficChecking = false
            if (err || !routes || routes.length === 0 || !_navActive) return
            var saved = navBar._timeSec - routes[0].time
            if (saved > 120) {
                _trafficAltRoute      = routes[0]
                _trafficTimeSavedSec  = Math.round(saved)
                _trafficBannerVisible = true
            }
        })
    }

    function _showTrafficComparison() {
        _trafficBannerVisible = false
        var ac = []
        var sh = _trafficAltRoute.shape
        for (var _si = 0; _si < sh.length; _si++) ac.push([sh[_si][0], sh[_si][1]])
        mapView.updateSourceLine("nav-route-alt", ac)
        mapView.setPaintProperty("nav-route-alt-line", "line-color",   "#4CAF50")
        mapView.setPaintProperty("nav-route-alt-line", "line-opacity", 0.85)
        mapView.setPaintProperty("nav-route-alt-line", "line-width",   6)
        mapView.setLayoutProperty("nav-route-alt-line", "visibility",  "visible")
        trafficRouteDialog.currentTimeSec = Math.round(navBar._timeSec)
        trafficRouteDialog.altTimeSec     = Math.round(_trafficAltRoute.time)
        trafficRouteDialog.timeSavedSec   = _trafficTimeSavedSec
        trafficRouteDialog.visible        = true
    }

    Timer {
        id: autoZoomRestoreTimer
        interval: 1000; repeat: false; running: false
        onTriggered: {
            mapView._zoomAutoTarget = mapView.zoomLevel
            appSettings.autoZoom = true
        }
    }

    Connections {
        target: appSettings
        function onAutoZoomChanged() {
            if (appSettings.autoZoom)
                mapView._zoomAutoTarget = mapView.zoomLevel
        }
    }

    function _applyTtsLang() {
        var lang = appSettings.ttsLang
        if (lang === "system") lang = Qt.locale().name.split("_")[0]
        navTts.set_engine_override(appSettings.ttsEngine)
        var engine = appSettings.ttsEngine
        var voice
        if (engine === "espeak" && appSettings.ttsVoiceEspeak !== "")
            voice = appSettings.ttsVoiceEspeak
        else if (engine === "picotts" && appSettings.ttsVoicePico !== "")
            voice = appSettings.ttsVoicePico
        else
            voice = appSettings.ttsVoice !== "" ? appSettings.ttsVoice : lang
        navTts.set_voice(voice)
    }

    // ── Gestión de vehículos ──────────────────────────────────────────────────
    QtObject {
        id: vehicleManager

        function allVehicles() {
            try { return JSON.parse(appSettings.vehiclesJson) || [] } catch(e) { return [] }
        }
        function saveVehicles(arr) { appSettings.vehiclesJson = JSON.stringify(arr) }

        function activeVehicle() {
            var arr = allVehicles()
            for (var i = 0; i < arr.length; i++)
                if (arr[i].id === appSettings.activeVehicleId) return arr[i]
            return arr.length > 0 ? arr[0] : null
        }
        function activeCosting() {
            var v = activeVehicle(); return v ? v.costing : "auto"
        }
        function generateId() {
            return String(Date.now()) + String(Math.floor(Math.random() * 9999))
        }
        function addVehicle(alias, costing) {
            var arr = allVehicles()
            var id = generateId()
            arr.push({ id: id, alias: alias, costing: costing,
                       parkLat: 0, parkLon: 0, hasPark: false,
                       lastLat: 0, lastLon: 0, hasLast: false })
            saveVehicles(arr)
            return id
        }
        function removeVehicle(id) {
            var arr = allVehicles().filter(function(v) { return v.id !== id })
            saveVehicles(arr)
            if (appSettings.activeVehicleId === id)
                appSettings.activeVehicleId = arr.length > 0 ? arr[0].id : ""
            NavSearch.setActiveCosting(activeCosting())
        }
        function setActive(id) {
            appSettings.activeVehicleId = id
            NavSearch.setActiveCosting(activeCosting())
        }
        function ensurePedestrian() {
            var arr = allVehicles()
            for (var i = 0; i < arr.length; i++) if (arr[i].costing === "pedestrian") return
            var id = generateId()
            arr.unshift({ id: id, alias: i18n.tr("A pie"), costing: "pedestrian",
                          parkLat: 0, parkLon: 0, hasPark: false,
                          lastLat: 0, lastLon: 0, hasLast: false })
            saveVehicles(arr)
        }
        function savePark(lat, lon) {
            var arr = allVehicles(), av = activeVehicle()
            if (!av) return
            for (var i = 0; i < arr.length; i++)
                if (arr[i].id === av.id) { arr[i].parkLat = lat; arr[i].parkLon = lon; arr[i].hasPark = true; break }
            saveVehicles(arr)
        }
        function clearPark(id) {
            var arr = allVehicles()
            for (var i = 0; i < arr.length; i++)
                if (arr[i].id === id) { arr[i].hasPark = false; break }
            saveVehicles(arr)
        }
        function saveLastPos(lat, lon) {
            var av = activeVehicle()
            if (!av || av.costing === "pedestrian") return
            var arr = allVehicles()
            for (var i = 0; i < arr.length; i++)
                if (arr[i].id === av.id) { arr[i].lastLat = lat; arr[i].lastLon = lon; arr[i].hasLast = true; break }
            saveVehicles(arr)
        }
        function vehiclesWithParking() {
            return allVehicles().filter(function(v) { return v.hasPark })
        }
        function costingLabel(c) {
            if (c === "auto")          return i18n.tr("Coche")
            if (c === "motorcycle")    return i18n.tr("Moto")
            if (c === "motor_scooter") return i18n.tr("Scooter")
            if (c === "truck")         return i18n.tr("Camión")
            if (c === "bicycle")       return i18n.tr("Bicicleta")
            if (c === "pedestrian")    return i18n.tr("A pie")
            return c
        }
    }

    // Diálogo: crear vehículo
    VehicleSetupDialog {
        id: vehicleSetupDialog
        textScale: appSettings.textScale
        onAccepted: function(alias, costing) {
            var id = vehicleManager.addVehicle(alias, costing)
            vehicleManager.setActive(id)
        }
    }

    // Diálogo: navegar al aparcamiento
    ParkingDialog {
        id: parkingDialog
        textScale: appSettings.textScale
        onNavigateRequested: function(destLat, destLon, costing) {
            var myLat = gpsSource.hasFix ? gpsSource.lat : appSettings.lastLat
            var myLon = gpsSource.hasFix ? gpsSource.lon : appSettings.lastLon
            NavSearch.route(
                [_originWp(myLat, myLon), {lat: destLat, lon: destLon}],
                {costing: costing},
                function(err, routes) {
                    if (err || !routes || routes.length === 0) {
                        root._startupMsg = i18n.tr("No se pudo calcular la ruta al aparcamiento")
                        startupMsgTimer.restart()
                        return
                    }
                    root._startNavigation(routes[0])
                })
        }
    }

    // Guardar última posición y liberar el GPS al cerrar la app.
    // La sesión GPS se mantiene en segundo plano (posicionamiento continuo),
    // pero al cerrar hay que soltar la sesión LLS explícitamente: el LLS de
    // stock (24.04-1.3) puede dejar sesiones huérfanas con el chip GPS
    // encendido si el cliente muere sin llamar StopPositionUpdates.
    Connections {
        target: Qt.application
        onAboutToQuit: {
            if (gpsSource.hasFix || appSettings.hasLastPos) {
                var lat = gpsSource.hasFix ? gpsSource.lat : appSettings.lastLat
                var lon = gpsSource.hasFix ? gpsSource.lon : appSettings.lastLon
                vehicleManager.saveLastPos(lat, lon)
            }
            satModel.stop_updates()
        }
    }

    Component.onCompleted: {
        console.log("TRACE [" + Date.now() + "]: root.onCompleted START")
        // Ubicación compartida por otra app vía esquema geo: (argv al lanzar,
        // ver sharedUri en main.rs) — sustituye al Content-Hub de Lomiri.
        if (typeof sharedUri !== "undefined" && sharedUri.length > 0) {
            Qt.callLater(function() { root._parseSharedText(sharedUri) })
        }
        // Restaurar cooldown de anuncios, descartando entradas > 1 h
        try {
            var _adSt = JSON.parse(appSettings.adShownJson)
            var _adNow = Date.now(), _adPruned = {}
            for (var _adK in _adSt) { if (_adNow - _adSt[_adK] < 3600000) _adPruned[_adK] = _adSt[_adK] }
            root._adShownTs = _adPruned
        } catch(e) { root._adShownTs = {} }
        Qt.callLater(function() {
            if (!mainAuthSettings.recordar) {
                mainAuthSettings.token = ""
                mainAuthSettings.email = ""
            }
            if (!appSettings.privacyShown || !appSettings.privacyAccepted) {
                privacyBanner.show()
            } else {
                if (appSettings.showChangesAtStartup &&
                        mainWhatsNewSt.lastSeenVersion !== whatsNewDialog.currentVersion)
                    whatsNewDialog.show()
                tourOverlay.checkShowAtStartup()
            }
            root._checkVoiceAfterTour = tourOverlay.visible
            if (!tourOverlay.visible) {
                var _tipLang = (appSettings.ttsLang && appSettings.ttsLang !== "system")
                    ? appSettings.ttsLang : Qt.locale().name.split("_")[0]
                if (!navTts.installed_piper_voices(_tipLang))
                    Qt.callLater(function() { tourOverlay.showVoiceTip() })
            }
        })
        appSettings.autoZoom = false   // inhibit during map init
        satModel.set_traces_enabled(appSettings.tracesEnabled)
        satModel.start_updates()
        // Inicializar device_id para mensajes
        if (deviceMsgSt.deviceId === "") deviceMsgSt.deviceId = root._makeDeviceId()
        Qt.callLater(function() {
            NavMessages.fetchMsgs(deviceMsgSt.deviceId, mainAuthSettings.token, 0,
                function(msgs, err) { root._onMsgFetched(msgs, err, true) })
        })
        // Si ya hay sesión activa, sincronizar settings silenciosamente al arrancar
        if (mainAuthSettings.token !== "") {
            Qt.callLater(function() {
                root._pullSettingsFromServer(function(serverData, updatedAt) {
                    settingsConflictDialog.show(serverData, updatedAt)
                })
            })
        }
        console.log("TRACE [" + Date.now() + "]: root.onCompleted DONE pre-autostart")
        // Arrancar ruta solo si hay fichero navius_autostart con routeIdx explícito.
        // simMode en ajustes guardados NO arranca ninguna ruta automáticamente.
        var _asXhr = new XMLHttpRequest()
        _asXhr.open("GET", root._autostartPath)
        _asXhr.onreadystatechange = function() {
            if (_asXhr.readyState !== 4) return
            if (_asXhr.status !== 200 || !_asXhr.responseText) return
            try {
                var _cfg = JSON.parse(_asXhr.responseText)
                if (_cfg.sim   !== undefined) appSettings.simMode   = _cfg.sim
                if (_cfg.debug !== undefined) appSettings.debugMode = _cfg.debug
                if (_cfg.pos   !== undefined) {
                    var _p = String(_cfg.pos).split(",")
                    if (_p.length >= 2) {
                        var _pLat = parseFloat(_p[0]), _pLon = parseFloat(_p[1])
                        if (!isNaN(_pLat) && !isNaN(_pLon)) {
                            root._autostartPos = {lat: _pLat, lon: _pLon}
                            Qt.callLater(function() {
                                appSettings.manualLat = _pLat; appSettings.manualLon = _pLon
                                appSettings.manualPosActive = true
                                mapView.followMode = true
                                mapView._gpsUpdating = true
                                mapView.center = QtPositioning.coordinate(_pLat, _pLon)
                                mapView._gpsUpdating = false
                                mapView.updateGPS(_pLat, _pLon, 5.0)
                            })
                        }
                    }
                }
                if (_cfg.routeIdx !== undefined) {
                    appSettings.simRouteIdx = _cfg.routeIdx
                    Qt.callLater(function() { root._applySimRoute(_cfg.routeIdx) })
                }
                if (_cfg.route !== undefined) {
                    var _r = _cfg.route
                    Qt.callLater(function() {
                        appSettings.simMode = true
                        prefsPanel.visible = false
                        searchPanel.loadDemoRoute(
                            _r.oLat, _r.oLon, _r.oName || "",
                            _r.dLat, _r.dLon, _r.dName || "")
                    })
                }
            } catch(e) {}
        }
        _asXhr.send()
        searchPanel.setNaviusOverpassServer(appSettings.overpassServer === "navius")
        NavSearch.probeOverpassServers()
        NavSearch.setFileLogCallback(function(msg) { satModel.log_to_file(msg) })
        NavSearch.setLogCallback(function(msg)     { satModel.log_to_file(msg); searchPanel._addLog(msg) })
        // NavSearch.js no usa .pragma library: cada import tiene su propio estado
        // aislado. SearchPanel.qml ya fija su navHttp para sus propias llamadas,
        // pero este import de Main.qml (usado por onOsmScoutDetectRequested,
        // ServerFallbackDialog.onUseOsmScout, onMapOnlineSourceChanged) necesita
        // el suyo — si no, ensure_osmscout_running() nunca se invoca (_navHttp null).
        NavSearch.setNavHttp(navHttp)
        var _radarDb = LocalStorage.openDatabaseSync("NaviusRadares", "1.0", "Radares fijos y de tramo", 4 * 1024 * 1024)
        NavSearch.setRadarDb(_radarDb)
        Qt.callLater(function() { NavSearch.maybeRunDailyRadarSweep() })
        NavSearch.setStatusPushCallback(function(text, color) { root._pushStatus(text, color) })
        NavSearch.setDeferFn(function(fn, ms) {
            if (ms && ms > 0) {
                var t = Qt.createQmlObject('import QtQuick 2.0; Timer{}', root, "deferTimer")
                t.interval = ms; t.repeat = false; t.running = true
                t.triggered.connect(function() { t.destroy(); fn() })
            } else { Qt.callLater(fn) }
        })
        satModel.log_to_file("OSM Scout: preferOsmScout=" + appSettings.preferOsmScout)
        if (appSettings.preferOsmScout) {
            // Bloquear rutas hasta confirmar servidor; ninguna petición irá a valhalla1
            NavSearch.setRouteBlocked(true)
            searchPanel.setRouteBlocked(true)
            _setEffectiveUrl("http://127.0.0.1:8553/v2")  // URL especulativa
            satModel.log_to_file("OSM Scout: iniciando detección…")
            NavSearch.detectOsmScout(function(found) {
                root._osmScoutActive = found
                satModel.log_to_file("OSM Scout detect result: " + (found ? "ACTIVO" : "no disponible"))
                if (found) {
                    NavSearch.setRouteBlocked(false)
                    searchPanel.setRouteBlocked(false)
                    root._startupMsg = i18n.tr("OSM Scout · rutas y mapas offline")
                    startupMsgTimer.restart()
                } else {
                    // No está instalado o no arrancó — fallback silencioso
                    satModel.log_to_file("OSM Scout: no disponible — fallback a " + appSettings.valhallaUrl)
                    _setEffectiveUrl(appSettings.valhallaUrl)
                    NavSearch.setRouteBlocked(false)
                    searchPanel.setRouteBlocked(false)
                }
            })
        } else {
            _setEffectiveUrl(appSettings.valhallaUrl)
            root._startupMsg = i18n.tr("Servidor: ") + appSettings.valhallaUrl.replace("https://","").replace("http://","")
            startupMsgTimer.restart()
        }
        // Restaurar navegación desde navius_route si quedó activa al cerrar
        var _rrXhr = new XMLHttpRequest()
        _rrXhr.open("GET", root._routePath)
        _rrXhr.onreadystatechange = function() {
            if (_rrXhr.readyState !== 4) return
            if (_rrXhr.status !== 200 || !_rrXhr.responseText) return
            try {
                var _rr = JSON.parse(_rrXhr.responseText.trim())
                if (_rr.active && Array.isArray(_rr.dests) && _rr.dests.length > 0) {
                    if (searchPanel.dests.length === 0) {
                        searchPanel._dests = _rr.dests
                        searchPanel._saveWaypoints()
                    }
                    if (!root._restoreVisible) root._restoreVisible = true
                }
            } catch(e) {}
        }
        _rrXhr.send()
        autoZoomRestoreTimer.start()
        _applyTtsLang()
        // ── Vehículos ──────────────────────────────────────────────────────────
        vehicleManager.ensurePedestrian()
        var _vehArr = vehicleManager.allVehicles()
        var _nonPed = _vehArr.filter(function(v) { return v.costing !== "pedestrian" })
        if (_nonPed.length === 0) {
            Qt.callLater(function() { vehicleSetupDialog.openDialog(true) })
        } else {
            // Asegurar activeVehicleId apunta a un vehículo válido
            if (appSettings.activeVehicleId === "") vehicleManager.setActive(_nonPed[0].id)
            NavSearch.setActiveCosting(vehicleManager.activeCosting())
            // Mostrar dialog de aparcamiento si hay parking guardado
            var _avPark = vehicleManager.activeVehicle()
            if (_avPark && _avPark.hasPark) Qt.callLater(function() { parkingDialog.openNavigate() })
        }
        // URI recibida al lanzar la app (URL dispatcher / geo: link)
        for (var _ai = 1; _ai < Qt.application.arguments.length; _ai++) {
            var _arg = Qt.application.arguments[_ai]
            if (_arg.indexOf("geo:") === 0 || _arg.indexOf("http") === 0) {
                Qt.callLater(function(u) { root._parseSharedText(u) }, _arg)
                break
            }
        }
        // Desbloquear sync de settings y limpiar flag espurio del arranque.
        // Qt.callLater de _pullSettingsFromServer se ejecuta DESPUÉS de esto, así
        // que cuando llegue verá settingsChangedSinceSync=false y no mostrará conflicto.
        root._settingsSyncBlocked = false
        mainAuthSettings.settingsChangedSinceSync = false
    }

    // URI geo: recibida mientras la app ya está en ejecución
    Connections {
        target: UriHandler
        onOpened: {
            for (var _ui = 0; _ui < uris.length; _ui++) {
                var _u = uris[_ui]
                if (_u.indexOf("geo:") === 0 || _u.indexOf("http") === 0) {
                    root._parseSharedText(_u)
                    break
                }
            }
        }
    }
    Component.onDestruction: {
        if (appSettings.debugCleanOnExit) satModel.delete_debug_file("all")
        navTts.clear_tts_cache(); satModel.stop_updates()
    }

    // ── GPS Simulator ──────────────────────────────────────────────────────
    // simRoute se construye desde Valhalla vía _applySimRoute(simRouteIdx).
    property var simRoute: []

    property int  simSpeedBias:  0      // -100..+500 % — modifica el intervalo del timer primario sim
    property bool simSignalLost: false  // simula túnel / pérdida de señal
    property bool simPaused:     false  // congela posición para inspección debug

    // True while extrapolating position with DR after GPS signal loss
    property bool _drEstimating: !gpsSource.hasFix
                                  && mapView._hasPos
                                  && gpsSource.speedKmh > 1

    // ── Heading display state ─────────────────────────────────────────────────
    property real _drHeadRad:     0   // rumbo de cálculo (solo ticks reales)
    property real _dispTargetRad: 0   // rumbo objetivo de display (todos los ticks: shape en interp, snap en real)
    property real _dispHeadRad:   0   // rumbo flecha vehículo (rápido: 180°/0.5s)
    property bool _hasArrow:     false

    // Map bearing smooth
    property real _mapBearingDeg:  0     // bearing actual suavizado del mapa
    property real _lastBearingMs:  0     // ms del último tick que actualizó el bearing
    property real _smoothBisRel:   0     // offset bisector suavizado (°), τ=1.5s
    property real _smoothMapTgt:   0     // target bearing mapa suavizado (°), τ=1.5s
    property bool _nextTurnSharp:  false // próximo nodo de maniobra gira >45°



    // Bearing del mapa y flecha vehículo — actualizados en el bloque bearing de onGpsTick,
    // sincronizados con cada tick de posición (real o interpolado).
    //   _dispHeadRad (flecha vehículo): 180°/s hacia _dispTargetRad (look-ahead shape).
    //   _mapBearingDeg (mapa): target = _dispHeadRad + _smoothBisRel (bisector suavizado τ=1.5s
    //   de los rumbos extremos del trazado próximo), cap 60°/s wall-clock dt.

    // Bearing A→B in radians (N=0, clockwise)
    function geoHeading(la1, lo1, la2, lo2) {
        var dlo = (lo2 - lo1) * Math.PI / 180
        la1 *= Math.PI / 180;  la2 *= Math.PI / 180
        return Math.atan2(Math.sin(dlo) * Math.cos(la2),
                          Math.cos(la1) * Math.sin(la2)
                          - Math.sin(la1) * Math.cos(la2) * Math.cos(dlo))
    }

    // Round a meter value to a "nice" scale-bar distance; returns {meters, label, logicalPx}
    function niceScale(metersPerPhysPx, pixelRatio, targetLogicalPx) {
        if (metersPerPhysPx <= 0 || pixelRatio <= 0) return {meters:0, label:"", logicalPx:0}
        var raw = metersPerPhysPx * pixelRatio * targetLogicalPx
        var exp = Math.floor(Math.log(raw) / Math.LN10)
        var mag = Math.pow(10, exp)
        var n   = raw / mag
        var nice = n < 1.5 ? 1 : n < 3.5 ? 2 : n < 7.5 ? 5 : 10
        var m   = nice * mag
        var lbl = m >= 1000 ? (m/1000).toFixed(m >= 10000 ? 0 : 1) + " km" : m.toFixed(0) + " m"
        return {meters: m, label: lbl, logicalPx: m / (metersPerPhysPx * pixelRatio)}
    }

    // Destination point: start (deg), heading (rad), distance (m)
    function geoDest(lat, lon, hdg, dist) {
        var R = 6371000, d = dist / R
        var la = lat * Math.PI / 180, lo = lon * Math.PI / 180
        var la2 = Math.asin(Math.sin(la)*Math.cos(d)
                            + Math.cos(la)*Math.sin(d)*Math.cos(hdg))
        var lo2 = lo + Math.atan2(Math.sin(hdg)*Math.sin(d)*Math.cos(la),
                                  Math.cos(d) - Math.sin(la)*Math.sin(la2))
        return {lat: la2 * 180/Math.PI, lon: lo2 * 180/Math.PI}
    }

    // ── Fixed simulated satellite constellation: 8 GPS + 2 GLONASS ───────────
    // Positions don't change (realistic — they drift slowly over minutes)
    // Signals vary ±4 dB each tick to look alive
    property var _simSigBase:    [44, 39, 36, 42, 30, 46, 34, 40, 37, 24]
    property var simSatIds:      [ 1,  2,  3,  5,  7,  9, 11, 13, 65, 66]
    property var simSatSystems:  [ 1,  1,  1,  1,  1,  1,  1,  1,  2,  2]
    property var simSatAzimuths: [30,120,210,300, 75,155,240,345, 90,270]
    property var simSatElevs:    [65, 45, 30, 55, 20, 70, 35, 50, 25, 40]
    property var simSatInUse:    [true,true,true,true,true,true,true,true,true,false]
    property var simSatSignals:  [44, 39, 36, 42, 30, 46, 34, 40, 37, 24]

    function _simVarySignals() {
        var out = []
        for (var i = 0; i < _simSigBase.length; i++)
            out.push(Math.round(_simSigBase[i] + (Math.random() * 8 - 4)))
        simSatSignals = out
    }

    // Actualiza el shape de cada tramo inyectado con la geometría real de simRoute.
    // Se llama tras buildSimRouteFromNavData para rutas de test (simRouteIdx > 0).
    function _remapTramoShapes() {
        if (!root._radarTramos || root._radarTramos.length === 0) return
        var sr = root.simRoute
        if (!sr || sr.length < 2) return
        var newTramos = []
        for (var ti = 0; ti < root._radarTramos.length; ti++) {
            var tramo = root._radarTramos[ti]
            var origShape = tramo.shape
            if (!origShape || origShape.length < 2) { newTramos.push(tramo); continue }
            // Buscar en simRoute el punto más cercano al inicio y fin del shape original
            var startLat = origShape[0][1], startLon = origShape[0][0]
            var endLat   = origShape[origShape.length-1][1], endLon = origShape[origShape.length-1][0]
            var bestStartIdx = 0, bestStartD = 1e9
            var bestEndIdx   = sr.length - 1, bestEndD = 1e9
            for (var ri = 0; ri < sr.length; ri++) {
                var ds = (sr[ri].lat - startLat)*(sr[ri].lat - startLat) + (sr[ri].lon - startLon)*(sr[ri].lon - startLon)
                var de = (sr[ri].lat - endLat)*(sr[ri].lat - endLat)     + (sr[ri].lon - endLon)*(sr[ri].lon - endLon)
                if (ds < bestStartD) { bestStartD = ds; bestStartIdx = ri }
                if (de < bestEndD)   { bestEndD   = de; bestEndIdx   = ri }
            }
            if (bestStartIdx >= bestEndIdx) { newTramos.push(tramo); continue }
            // Extraer sub-shape y recalcular longitud
            var newShape = []
            var cosL = Math.cos(sr[bestStartIdx].lat * Math.PI / 180)
            var newLenM = 0
            for (var si2 = bestStartIdx; si2 <= bestEndIdx; si2++) {
                if (si2 > bestStartIdx) {
                    var dLat = (sr[si2].lat - sr[si2-1].lat) * 111319
                    var dLon = (sr[si2].lon - sr[si2-1].lon) * 111319 * cosL
                    newLenM += Math.sqrt(dLat*dLat + dLon*dLon)
                }
                newShape.push([sr[si2].lon, sr[si2].lat])
            }
            newTramos.push({ shape: newShape, maxspeed: tramo.maxspeed,
                             lengthM: Math.max(1, Math.round(newLenM)) })
        }
        root._radarTramos = newTramos
        root._updateRadarLayers()
    }



    // Build a 1-Hz sim route from a real Valhalla navData object.
    // Shape is [[lon,lat],...]; maneuvers carry speed_limit (km/h) and length/time.
    function buildSimRouteFromNavData(navData) {
        var shape = navData.shape
        var mans  = navData.maneuvers
        if (!shape || shape.length < 2 || !mans || mans.length === 0)
            return []

        // Per-segment speed (km/h).
        // Para vehículos lentos (peatón, bici, scooter) usamos el tiempo real de Valhalla
        // para reflejar la velocidad real del modo de transporte.
        // Para vehículos rápidos usamos speed_limit / road_class como referencia.
        var _costing = vehicleManager.activeCosting()
        // Velocidad máxima por tipo de vehículo (0 = sin límite propio)
        var _spdCap = _costing === "pedestrian"   ? 5
                    : _costing === "bicycle"       ? 30
                    : _costing === "motor_scooter" ? 45
                    : 0
        var segSpd = []
        var mIdx = 0
        for (var si = 0; si < shape.length - 1; si++) {
            while (mIdx < mans.length - 1 && si >= mans[mIdx].end_shape_index) mIdx++
            var m = mans[mIdx]
            var spd = NavSearch.segSpeedKmh(m, 0)  // 0 = sin límite comunitario (se aplica dinámicamente en GpsSource)
            if (_spdCap > 0) spd = Math.min(spd, _spdCap)
            segSpd.push(Math.max(2, Math.min(150, spd)))
        }

        // Segment timeline: haversine distance → duration → cumulative tStart
        var segs = [], tAcc = 0
        for (var si2 = 0; si2 < shape.length - 1; si2++) {
            var lon1 = shape[si2][0],   lat1 = shape[si2][1]
            var lon2 = shape[si2+1][0], lat2 = shape[si2+1][1]
            var dLat = (lat2 - lat1) * Math.PI / 180
            var dLon = (lon2 - lon1) * Math.PI / 180
            var la1r = lat1 * Math.PI / 180, la2r = lat2 * Math.PI / 180
            var sl = Math.sin(dLat/2), so = Math.sin(dLon/2)
            var distM = 6371000 * 2 * Math.atan2(Math.sqrt(sl*sl + Math.cos(la1r)*Math.cos(la2r)*so*so),
                                                  Math.sqrt(1 - sl*sl - Math.cos(la1r)*Math.cos(la2r)*so*so))
            var timeS = distM / (segSpd[si2] / 3.6)
            if (timeS <= 0) timeS = 0.01
            segs.push({lat1:lat1,lon1:lon1,lat2:lat2,lon2:lon2, spdKmh:segSpd[si2], timeS:timeS, tStart:tAcc})
            tAcc += timeS
        }

        // Resample to 1-second points
        var result = [{lat: segs[0].lat1, lon: segs[0].lon1, spd: segs[0].spdKmh}]
        var sj = 0
        for (var t = 1; t < tAcc; t++) {
            while (sj < segs.length - 1 && segs[sj].tStart + segs[sj].timeS <= t) sj++
            var seg = segs[sj]
            var frac = Math.min(1, (t - seg.tStart) / seg.timeS)
            result.push({lat: seg.lat1 + (seg.lat2 - seg.lat1) * frac,
                         lon: seg.lon1 + (seg.lon2 - seg.lon1) * frac,
                         spd: seg.spdKmh})
        }
        var last = segs[segs.length - 1]
        result.push({lat: last.lat2, lon: last.lon2, spd: 0})
        var slCount = 0
        for (var ci = 0; ci < mans.length; ci++) if (mans[ci].speed_limit > 0) slCount++
        satModel.log_to_file("SimRoute: " + result.length + " pts, ~" + Math.round(tAcc/60)
                             + " min, sl en " + slCount + "/" + mans.length + " maniobras")
        gpsSource.routeShapeSpeedKmh = segSpd
        return result
    }

    function simStart() {
        if (!simRoute || simRoute.length < 2) return
        mapView.followMode = true
        gpsSource.simStart()
    }

    // ── Handler de ticks GPS (reales e interpolados desde GpsSource) ───────────
    Connections {
        target: gpsSource
        function onGpsTick(lat, lon, speedKmh, headRad, hasFix, isReal, ms, source) {
            if (isNaN(lat) || isNaN(lon)) return

            // Liberar posición de arranque al recibir el primer fix real o simulado
            if (root._autostartPos !== null && hasFix) {
                root._autostartPos = null
                appSettings.manualPosActive = false
            }

            // Telemetría: GPS real normal (debug=0) o sim/replay+debugMode (debug=1 para pruebas)
            var _telemReal = isReal && !appSettings.simMode && !root._trackReplayActive
            var _telemDebug = (appSettings.simMode || root._trackReplayActive) && appSettings.debugMode
            if ((_telemReal || _telemDebug) && mainAuthSettings.token !== "") {
                var _tp = root._telemBuf
                _tp.push({ lat: lat, lon: lon,
                           spd: speedKmh,
                           hdg: (headRad * 180 / Math.PI + 360) % 360,
                           acc: hasFix ? gpsSource.posAccuracy : -1,
                           ts:  ms })
                root._telemBuf = _tp
                root._telemRealCount += 1
                if (root._telemRealCount >= 10) root._flushTelemetria()
            }

            // Acumular ticks reales para visualización debug
            if (isReal && appSettings.showGpsTicks) {
                var dots = root._gpsTickDots
                dots.push({lat: lat, lon: lon})
                if (dots.length > 500) dots.splice(0, dots.length - 500)
                root._gpsTickDots = dots
                alertCanvas.requestPaint()
            }

            // Heading blend
            // En ticks reales con ruta activa: heading del segmento snap (predictivo, sigue la vía).
            // En ticks interpolados: headRad viene ya del segmento del shape desde GpsSource.
            // Fuera de ruta, sin nav o tick no-real: headRad GPS/sim directo.
            var _effectiveHeadRad = headRad
            if (isReal && root._navActive && !root._navPaused && root._snapToRoute
                    && navBar.snapHeadRad !== 0)
                _effectiveHeadRad = navBar.snapHeadRad

            // _dispTargetRad: cuando seguimos ruta, solo en ticks interpolados.
            // El tick real emite heading del snap GPS (NavBar) y el interp emite el look-ahead del
            // shape en la posición más adelantada — si el real actualiza también, el heading oscila
            // cada segundo entre el heading del snap (atrasado) y el del interp (adelantado).
            var _isFollowingRoute = root._navActive && !root._navPaused
                                    && navBar.routeData && root._snapToRoute
            if (!isReal || !_isFollowingRoute)
                root._dispTargetRad = _effectiveHeadRad

            // Canal de cálculo: _drHeadRad solo en ticks reales.
            // El suavizado de _dispHeadRad lo hace el bloque bearing en onGpsTick.
            if (isReal) {
                root._drHeadRad = _effectiveHeadRad
                if (!appSettings.drEnabled) {
                    root._dispHeadRad   = _effectiveHeadRad  // sin DR: snap
                    root._mapBearingDeg = _effectiveHeadRad * 180 / Math.PI
                }
            }

            // ── Bearing del mapa — ANTES de actualizar el centro ────────────────
            // Debe preceder a _navFollowCenter y _smoothApplyPos: ambos usan mapView.bearing
            // para calcular dónde centrar el mapa; si el bearing cambia después, el icono
            // aparece desplazado respecto a la posición recién calculada.
            {
                // _bdt = tiempo REAL transcurrido desde el último update de bearing.
                // Tope 0.5s solo para proteger de saltos tras pausa/arranque. NO capar a
                // 1/drHz: el timer QML dispara más lento que drHz (~8 Hz aunque drHz=30),
                // y capar a 1/drHz haría que los suavizados exponenciales integren el
                // tiempo 4x más lento → el mapa se arrastra (τ efectivo ~3s en vez de 0.8s).
                var _bdtRaw  = (root._lastBearingMs > 0) ? (ms - root._lastBearingMs) / 1000.0 : 0
                var _bdt     = Math.min(_bdtRaw, 0.5)

                // Flecha vehículo (DR mode)
                if (appSettings.drEnabled) {
                    if (_bdt <= 0) {
                        root._dispHeadRad = root._dispTargetRad
                    } else {
                        var _bmxD  = Math.PI * _bdt
                        var _bdfD  = root._dispTargetRad - root._dispHeadRad
                        _bdfD = ((_bdfD % (2*Math.PI)) + 3*Math.PI) % (2*Math.PI) - Math.PI
                        root._dispHeadRad += Math.abs(_bdfD) <= _bmxD
                            ? _bdfD : (_bdfD > 0 ? _bmxD : -_bmxD)
                    }
                }

                // Bearing del mapa — target = bisector ideal de ruta sim visible
                if (appSettings.bearingMode === "heading" && root._hasArrow && !mapView._bearingAnimating) {
                    var _rawHdgDeg = gpsSource.mapHeadRad * 180 / Math.PI
                    var _mapTgt = _rawHdgDeg  // fallback sin ruta o en recálculo
                    if (!navBar._rerouting) {
                        // Distancia look-ahead del bisector (común para sim y ruta real)
                        var _ahdM = 0
                        if (gpsSource.simRoutePoints) {
                            _ahdM = gpsSource._simWantedVisibleAheadDistM(appSettings.routeAheadSecs)
                            _mapTgt = gpsSource._simRouteIdealBisectorRad(_ahdM, root._mapBearingDeg * Math.PI / 180) * 180 / Math.PI
                        } else if (root._navActive && navBar.routeData) {
                            _ahdM  = root._routeAheadDistM(appSettings.routeAheadSecs)
                            var _oLat  = gpsSource.lat, _oLon = gpsSource.lon
                            var _shpB  = navBar.routeData.shape
                            if (_shpB && _shpB.length > 1 && gpsSource._curShapeIdx >= 0
                                    && gpsSource._curShapeIdx < _shpB.length - 1) {
                                var _sp0b = _shpB[gpsSource._curShapeIdx]
                                var _sp1b = _shpB[Math.min(gpsSource._curShapeIdx + 1, _shpB.length - 1)]
                                _oLat = _sp0b[1] + gpsSource._curShapeFrac * (_sp1b[1] - _sp0b[1])
                                _oLon = _sp0b[0] + gpsSource._curShapeFrac * (_sp1b[0] - _sp0b[0])
                            }
                            var _midPt = root._routeAheadPoint(_ahdM / 2)
                            if (_midPt !== null) {
                                var _dLat = (_midPt.lat - _oLat) * 111319
                                var _dLon = (_midPt.lon - _oLon) * 111319 * Math.cos(_oLat * Math.PI / 180)
                                _mapTgt = Math.atan2(_dLon, _dLat) * 180 / Math.PI
                            }
                        }
                        // Recorrer nodos de maniobra dentro de routeAheadSecs:
                        //   ≤45°  → curva progresiva: aplicar corrección predictiva
                        //   >45°  → giro brusco: no aplicar corrección (desorienta en ciudad)
                        var _sharpNext = false
                        var _antiMapTgt = null   // si != null, override de anticipación de giro brusco
                        if (navBar.routeData && navBar.routeData.maneuvers) {
                            var _mans = navBar.routeData.maneuvers
                            var _shpN = navBar.routeData.shape
                            // 1. Anticipación de giro brusco: comprueba el nodo del TRAMO
                            //    ACTIVO directamente (sin _effStep) para que la ventana de
                            //    2 s no quede anulada por el avance de _effStep.
                            if (navBar._step < _mans.length - 1) {
                                var _cNIdx = _mans[navBar._step].end_shape_index
                                if (_cNIdx > 0 && _cNIdx < _shpN.length - 1) {
                                    var _cA = _shpN[_cNIdx-1], _cB = _shpN[_cNIdx], _cC = _shpN[_cNIdx+1]
                                    var _cBin  = Math.atan2((_cB[0]-_cA[0])*Math.cos(_cA[1]*Math.PI/180), _cB[1]-_cA[1]) * 180/Math.PI
                                    var _cBout = Math.atan2((_cC[0]-_cB[0])*Math.cos(_cB[1]*Math.PI/180), _cC[1]-_cB[1]) * 180/Math.PI
                                    var _cAng  = Math.abs((((_cBout - _cBin) % 360) + 540) % 360 - 180)
                                    if (_cAng > 45) {
                                        var _antiM = Math.max(5, 1 * gpsSource._speedMs)  // 1 s de anticipación, mín 5 m
                                        if (navBar._stepDistKm * 1000 < _antiM)
                                            _antiMapTgt = _cBout  // apuntar al bearing de salida
                                    }
                                }
                            }
                            // 2. Análisis look-ahead para _sharpNext (suprime bisector si hay
                            //    giro brusco próximo). _effStep avanza cuando el nodo entra en
                            //    la ventana del bisector para sincronizar el unlock.
                            var _effStep = (navBar._stepDistKm * 1000 < _ahdM / 2 && navBar._step + 1 < _mans.length)
                                           ? navBar._step + 1 : navBar._step
                            var _cumSecs = 0
                            var _foundTurn = false
                            for (var _mi = _effStep; _mi < _mans.length - 1 && !_foundTurn; _mi++) {
                                if (_mi > _effStep) _cumSecs += _mans[_mi].time || 0
                                if (_cumSecs > appSettings.routeAheadSecs) break
                                var _nIdx = _mans[_mi].end_shape_index
                                if (!(_nIdx > 0 && _nIdx < _shpN.length - 1)) continue
                                var _pA = _shpN[_nIdx-1], _pB = _shpN[_nIdx], _pC = _shpN[_nIdx+1]
                                var _bIn  = Math.atan2((_pB[0]-_pA[0])*Math.cos(_pA[1]*Math.PI/180), _pB[1]-_pA[1]) * 180/Math.PI
                                var _bOut = Math.atan2((_pC[0]-_pB[0])*Math.cos(_pB[1]*Math.PI/180), _pC[1]-_pB[1]) * 180/Math.PI
                                var _ang  = Math.abs((((_bOut - _bIn) % 360) + 540) % 360 - 180)
                                _foundTurn = true
                                _sharpNext = (_ang > 45)
                            }
                        }
                        root._nextTurnSharp = _sharpNext
                        if (_antiMapTgt !== null) {
                            // Anticipación: dentro de 2 s del giro brusco → bearing de salida
                            _mapTgt = _antiMapTgt
                        } else if (_sharpNext) {
                            // Giro brusco próximo: heading crudo del vehículo
                            _mapTgt = _rawHdgDeg
                        } else {
                            // Curva progresiva: bisector con cap de opciones (maxPredictiveTurnDeg)
                            var _bisOff = (((_mapTgt - _rawHdgDeg) % 360) + 540) % 360 - 180
                            var _maxOff = appSettings.maxPredictiveTurnDeg
                            _mapTgt = _rawHdgDeg + Math.max(-_maxOff, Math.min(_maxOff, _bisOff))
                        }
                    }
                    // Suavizar el target (τ=0.8s) antes de que el bearing lo persiga
                    var _tDf = (((_mapTgt - root._smoothMapTgt) % 360) + 540) % 360 - 180
                    var _tA  = (_bdt > 0) ? (1.0 - Math.exp(-_bdt / 0.8)) : 1.0
                    root._smoothMapTgt += _tDf * _tA
                    var _smoothedTgt = root._smoothMapTgt
                    if (_bdt <= 0) {
                        root._mapBearingDeg = _smoothedTgt
                    } else {
                        var _mDf = (((_smoothedTgt - root._mapBearingDeg) % 360) + 540) % 360 - 180
                        var _mA  = (_bdt > 0) ? (1.0 - Math.exp(-_bdt / 0.15)) : 1.0
                        root._mapBearingDeg += _mDf * _mA
                    }
                    mapView._bearingAuto = true
                    mapView.bearing = root._mapBearingDeg
                    mapView._bearingAuto = false
                }

                root._lastBearingMs = ms
            }

            // Posición del mapa en heading-up (bearing ya actualizado arriba).
            // Con smoothGps+ruta activa, los ticks reales no actualizan el centro: los interp a
            // 10 Hz lo hacen a través de _smoothApplyPos, evitando saltos de posición GPS cruda.
            if (appSettings.bearingMode === "heading" && root._hasArrow
                    && !(isReal && gpsSource.smoothGps && root._navActive)) {
                if (mapView.followMode && mapView.metersPerPixel > 0) {
                    mapView._gpsUpdating = true
                    mapView.center = mapView._navFollowCenter(lat, lon)
                    mapView._gpsUpdating = false
                }
            }

            // Arrow indicator
            if (speedKmh >= 1) root._hasArrow = true
            else if (!hasFix && speedKmh < 0.5) root._hasArrow = false

            // NavBar primero: calcula distFromRoute y snapLat/snapLon antes de posicionar.
            // En simMode los ticks de GPS hardware (source="gps") no alimentan NavBar.
            // En track replay: handleTick sí se llama para avanzar instrucciones; NavBar ya
            // tiene guardas internas (trackReplayMode=true) para inhibir rerouting y arrived().
            if (root._navActive && !root._navPaused
                    && !(appSettings.simMode && source === "gps"))
                navBar.handleTick(isReal, ms)

            // Map position
            // Con smoothGps activo y ruta, el tick real NO actualiza el display — el interp
            // emite snapLat/snapLon en el tick siguiente (dt≈0) haciendo el paso uniforme.
            // Sin smoothGps, o sin ruta, el tick real sí actualiza (única fuente de display).
            if (isReal && !(root._trackReplayActive && root._trackReplayRaw))
                root._snapToRoute = gpsSource._snapActive
            var _isSnapFollowing = isReal && root._navActive && !root._navPaused
                                   && navBar.routeData && root._snapToRoute
            if (!isReal || !gpsSource.smoothGps || !_isSnapFollowing) {
                var _dispLat = lat, _dispLon = lon
                if (_isSnapFollowing) {
                    _dispLat = gpsSource.snapLat
                    _dispLon = gpsSource.snapLon
                }
                mapView._smoothApplyPos(_dispLat, _dispLon)
            }

            if (isReal) {
                mapView._lastLat = lat; mapView._lastLon = lon
                mapView._lastAcc = gpsSource.accuracy; mapView._hasPos = true
                if (!appSettings.simMode) {
                    appSettings.lastLat    = lat
                    appSettings.lastLon    = lon
                    appSettings.hasLastPos = true
                }
                if (appSettings.gpsTracking && (hasFix || appSettings.simMode))
                    navTracker.add_point(lat, lon, speedKmh, ms)
                if (appSettings.simMode) root._simVarySignals()
                activeModel.data_changed()
                if (root._navActive) root._checkRadar()
                root._checkCommAlerts()
                root._checkCommLimits()
                root._fetchBillboards()
                root._checkBillboardProximity(lat, lon)
                var _curStep = navBar._step
                if (_curStep !== root._lastNavStep) {
                    root._lastNavStep = _curStep
                    root._onNavStepChanged(_curStep)
                }
            }

            // Ticks interpolados: buffer hasta el próximo tick real
            if (!isReal && appSettings.debugMode && appSettings.simMode && root._navActive) {
                var tsI = root._tsLocal(ms)
                root._pendingTickLines += "  " + tsI + " interp "
                    + lat.toFixed(6) + "," + lon.toFixed(6)
                    + " spd=" + speedKmh.toFixed(1)
                    + "\n"
            }

            // Log de tick real: después de handleTick para tener distFromRoute actualizado
            if (isReal && appSettings.debugMode && appSettings.simMode && root._navActive) {
                var tsR = root._tsLocal(ms)
                var realLine = tsR + " idx=" + gpsSource.simIdx
                    + " src=" + source
                    + " " + lat.toFixed(6) + "," + lon.toFixed(6)
                    + " spd=" + speedKmh.toFixed(1)
                    + " dist=" + navBar.distFromRoute.toFixed(1)
                    + " off=" + navBar._offCount
                    + " st=" + navBar._status
                    + " step=" + navBar._step
                    + "\n"
                // Marcador explícito de off-route (off=1,2 antes del recálculo; off=3 ya dispara REROUTE)
                var offMark = (navBar._offCount > 0)
                    ? (tsR + " !!! OFF " + navBar._offCount + "/3 dist="
                       + navBar.distFromRoute.toFixed(1) + "m\n")
                    : ""
                root._traceLines += root._pendingTickLines + offMark + realLine
                root._pendingTickLines = ""
            }
        }

        function onSimFinishedChanged() {
            if (gpsSource.simFinished && root._trackReplayActive) {
                root._startupMsg = i18n.tr("Reproducción terminada")
                startupMsgTimer.restart()
                Qt.callLater(function() { root.clearRoute() })
            }
        }
        function onRevFinishedChanged() {
            if (gpsSource.revFinished && root._revModeActive) {
                root._revModeActive = false
                gpsSource.stopRevMode()
            }
        }
    }

    // Immediately restore position when simulated signal comes back
    onSimSignalLostChanged: {
        if (!simSignalLost && appSettings.simMode)
            gpsSource.seekTo(gpsSource.simIdx)
    }

    // Actualizar capas de radar al cambiar visibilidad en ajustes
    Connections {
        target: appSettings
        function onShowRadarTramoChanged()    { root._updateRadarLayers() }
        function onShowRadarFijosChanged()    { alertCanvas.requestPaint() }
        function onShowGpsTicksChanged()      { if (!appSettings.showGpsTicks) root._gpsTickDots = []; alertCanvas.requestPaint() }
        function onNavMapModeChanged()        { mapView.apply3dBuildings() }
        function onMapModeChanged()           { mapView.apply3dBuildings() }
        function onValhallaUrlChanged()       { if (!root._osmScoutActive) _setEffectiveUrl(appSettings.valhallaUrl) }
        function onOverpassServerChanged()     { searchPanel.setNaviusOverpassServer(appSettings.overpassServer === "navius") }
        function onGpsTrackingChanged() {
            if (appSettings.gpsTracking) {
                navTracker.start_recording()
                // Guarda la ruta Valhalla activa para poder alinear el track en replay.
                if (root._navActive && root._navData)
                    navTracker.set_route_json(JSON.stringify(root._navData))
            } else {
                navTracker.stop_and_save()
            }
        }
    }

    // ── Active model proxy (delegates to gpsSource or satModel) ───────────
    QtObject {
        id: activeModel
        signal data_changed()   // emitido en gpsTick real; SatelliteView escucha esto

        property real   pos_lat:       appSettings.manualPosActive ? appSettings.manualLat  : gpsSource.lat
        property real   pos_lon:       appSettings.manualPosActive ? appSettings.manualLon  : gpsSource.lon
        property real   pos_speed_kmh: appSettings.manualPosActive ? 0                      : gpsSource.realSpeedKmh
        property real   pos_accuracy:  appSettings.manualPosActive ? 5.0                    : gpsSource.accuracy
        property bool   pos_has_fix:   appSettings.manualPosActive ? true                   : gpsSource.hasFix
        property int    in_use_count:  appSettings.manualPosActive ? 4  : appSettings.simMode ? 9  : satModel.in_use_count
        property int    in_view_count: appSettings.manualPosActive ? 6  : appSettings.simMode ? 10 : satModel.in_view_count
        property bool   is_active:     appSettings.manualPosActive ? true : appSettings.simMode ? true : satModel.is_active
        property string error_string:  appSettings.simMode ? ""                : satModel.error_string
        property var    sat_ids:       appSettings.simMode ? root.simSatIds      : satModel.sat_ids
        property var    sat_azimuths:  appSettings.simMode ? root.simSatAzimuths : satModel.sat_azimuths
        property var    sat_elevations: appSettings.simMode ? root.simSatElevs   : satModel.sat_elevations
        property var    sat_in_use:    appSettings.simMode ? root.simSatInUse    : satModel.sat_in_use
        property var    sat_systems:   appSettings.simMode ? root.simSatSystems  : satModel.sat_systems
        property var    sat_signals:   appSettings.simMode ? root.simSatSignals  : satModel.sat_signals
    }

    // ── Panel izquierdo landscape (1/3): fondo detrás de NavBar + botones ──
    Rectangle {
        id: landscapePanel
        visible: root._isLandscape
        z: 0
        anchors { left: parent.left; top: parent.top; bottom: statusBar.top }
        width: root._isLandscape ? Math.round(parent.width / 3) : 0
        color: "#F007111E"
        // Línea separadora derecha
        Rectangle {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: units.gu(0.1); color: "#29B6F6"; opacity: 0.4
        }
    }

    // ── Map (MapLibre GL Native) ───────────────────────────────────────────
    MapboxMap {
        id: mapView
        anchors {
            left:   root._isLandscape ? landscapePanel.right : parent.left
            right:  parent.right
            top:    parent.top
            bottom: parent.bottom
        }

        property bool _usingOsmScoutMaps: {
            if (!root._osmScoutActive) return false
            // Fuente online configurada como OSM Scout → siempre
            if (appSettings.mapOnlineSource === "osmscout") return true
            // Sin internet: prioridad según mapOfflineMode
            //   "osmscout" → cambio inmediato a OSM Scout
            //   "cache"    → caché primero; OSM Scout solo si caché también falla (_tileServerFailed)
            if (root._mapOffline && appSettings.mapOfflineMode === "osmscout") return true
            // Servidor de tiles no disponible (o caché fallida en modo "cache") → fallback automático
            if (root._tileServerFailed) return true
            return false
        }
        readonly property string _navMaps: "https://navius-maps.egpsistemas.com/styles"
        readonly property bool   _navius:  !_usingOsmScoutMaps && (!root._tileServerFailed || root._mapOffline) && appSettings.mapTileServer === "navius"
        // Solo liberty (navius o externo auto) tiene capa building-3d
        readonly property bool   _has3dBuildings: {
            var s = _forcedStyle || appSettings.mapStyleMode
            if (s === "positron" || s === "bright" || s === "fiord" || s === "dark") return false
            if (s === "satellite") return false
            // "auto": liberty externo (siempre tiene), o navius según mapNaviusDayStyle
            return !_navius || appSettings.mapNaviusDayStyle === "liberty"
        }

        property string dayUrl:   _usingOsmScoutMaps
            ? "http://localhost:8553/v1/mbgl/style?style=osmbright"
            : _navius ? _navMaps + "/" + appSettings.mapNaviusDayStyle + "/style.json"
                      : "https://tiles.openfreemap.org/styles/liberty"
        property string nightUrl: _usingOsmScoutMaps
            ? "http://localhost:8553/v1/mbgl/style?style=mc"
            : fiordUrl
        property string positronUrl: _navius
            ? _navMaps + "/positron/style.json"
            : "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json"
        property string brightUrl: _navius
            ? _navMaps + "/bright/style.json"
            : "https://tiles.openfreemap.org/styles/bright"
        property string fiordUrl:  _navius
            ? _navMaps + "/fiord/style.json"
            : brightUrl
        property string darkUrl:   _navius
            ? _navMaps + "/dark/style.json"
            : fiordUrl
        readonly property string satelliteUrl: "https://server.arcgisonline.com/arcgis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        readonly property string satelliteStyleUrl: 'data:application/json,{"version":8,"sources":{"sat":{"type":"raster","tiles":["https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"],"tileSize":256,"maxzoom":19}},"layers":[{"id":"sat","type":"raster","source":"sat"}]}'

        cacheDatabaseDefaultPath: !_usingOsmScoutMaps
        cacheDatabaseMaximalSize: _usingOsmScoutMaps ? 0 : appSettings.mapCacheMaxMb * 1024 * 1024

        onDayUrlChanged:      if (_layersInit) Qt.callLater(applyLightMode)
        onNightUrlChanged:    if (_layersInit) Qt.callLater(applyLightMode)
        onPositronUrlChanged: if (_layersInit) Qt.callLater(applyLightMode)
        onBrightUrlChanged:   if (_layersInit) Qt.callLater(applyLightMode)
        onFiordUrlChanged:    if (_layersInit) Qt.callLater(applyLightMode)
        onDarkUrlChanged:     if (_layersInit) Qt.callLater(applyLightMode)

        onErrorChanged: {
            satModel.log_to_file("MapboxMap.error: " + error)
            if (!error || error.length === 0 || root._tileServerFailed) return
            if (!tileErrorDebounceTimer.running) tileErrorDebounceTimer.start()
        }

        styleUrl:   dayUrl
        center:     QtPositioning.coordinate(appSettings.lastLat, appSettings.lastLon)
        zoomLevel:  appSettings.lastZoom
        // ×4.0 se calibró para cómo UT/Lomiri reportaba devicePixelRatio; en
        // postmarketOS/Phosh (epolan: devicePixelRatio=3, = escalado del sistema
        // al 300%) eso daba pixelRatio=12, haciendo la ruta/líneas visiblemente
        // más gordas que en UT. Calibrado en dispositivo: ×1.0 (pixelRatio=3)
        // queda muy pequeño, ×2.0 (pixelRatio=6) es el valor bueno confirmado.
        pixelRatio: (Screen.devicePixelRatio || 1) * 2.0

        property bool   followMode:   true
        property bool   _gpsUpdating: false
        property bool   _layersInit:  false
        property real   _lastLat:     0
        property real   _lastLon:     0
        property real   _lastAcc:     0
        property bool   _hasPos:      false
        property real   _dispLat:     0      // current displayed position (updated at DR rate)
        property real   _dispLon:     0
        property real   _centerLat:   appSettings.lastLat  // map centre (for screen-coord math)
        property real   _centerLon:   appSettings.lastLon
        property bool   _bearingAuto:      false  // true while DR/button is setting bearing programmatically
        property bool   _autoNight:        false  // set explicitly by applyLightMode(); avoids URL normalization issues
        property string _forcedStyle:      ""    // estilo forzado temporalmente por el botón (no persiste)
        property bool   _nightMode: {
            var m = _forcedStyle || appSettings.mapStyleMode
            if (m === "satellite" || m === "dark") return true
            if (m === "positron" || m === "bright" || m === "fiord") return false
            // "auto": noche explícita o auto-detectada
            if (appSettings.lightMode === "night") return true
            return _autoNight
        }
        property bool   _bearingAnimating: false  // true during mode-switch bearing animation
        property real   _animBearing:      0      // animated intermediate bearing value
        property bool   _pitchAnimating:   false  // true during 2D↔3D pitch animation
        property real   _animPitch:        0      // animated intermediate pitch value
        property bool   _zoomAnimating:    false  // true during auto-zoom animation
        property real   _animZoom:         0      // animated intermediate zoom value
        property real   _fovAngle:         18.435 // MapLibre effective vertical FOV half-angle (°); tunable via "fovXX" cmd

        on_AnimBearingChanged: {
            if (_bearingAnimating) {
                _bearingAuto = true
                bearing = _animBearing
                _bearingAuto = false
            }
        }

        // Pitch + center se fijan juntos en el mismo handler para que MapLibre
        // los aplique en el mismo ciclo de render — así el GPS no deriva durante
        // la animación 2D↔3D (el pivot visual queda en la posición del GPS).
        on_AnimZoomChanged: {
            if (_zoomAnimating)
                setZoomLevel(_animZoom, Qt.point(width / 2, height / 2))
        }

        on_AnimPitchChanged: {
            if (_pitchAnimating) {
                pitch = _animPitch
                if (appSettings.bearingMode === "heading" && followMode
                        && metersPerPixel > 0 && !isNaN(_dispLat) && _dispLat !== 0) {
                    _gpsUpdating = true
                    center = _navFollowCenter(_dispLat, _dispLon)
                    _gpsUpdating = false
                }
            }
        }

        NumberAnimation {
            id: bearingAnim
            target: mapView; property: "_animBearing"
            duration: 150; easing.type: Easing.OutCubic
            onStopped: {
                mapView._bearingAnimating = false
                // Snap to exact target heading after transition ends (DR may have drifted slightly)
                if (appSettings.bearingMode === "heading" && root._hasArrow) {
                    mapView._bearingAuto = true
                    mapView.bearing = root._mapBearingDeg
                    mapView._bearingAuto = false
                }
            }
        }

        // Smoothly rotate the map to 'targetDeg' degrees, taking the shortest arc
        function animateBearing(targetDeg) {
            var from = bearing
            var diff = ((targetDeg - from) % 360 + 540) % 360 - 180
            _animBearing = from
            _bearingAnimating = true
            _bearingAuto = true
            bearingAnim.stop()
            bearingAnim.from = from
            bearingAnim.to   = from + diff
            bearingAnim.start()
        }

        // ── Pitch (2D/3D) animation ───────────────────────────────────────
        NumberAnimation {
            id: pitchAnim
            target: mapView; property: "_animPitch"
            duration: 500; easing.type: Easing.OutCubic
            onStopped: {
                mapView._pitchAnimating = false
                // Corrección final por si mpp cambió al final de la animación
                if (appSettings.bearingMode === "heading" && mapView.followMode
                        && mapView.metersPerPixel > 0
                        && !isNaN(mapView._dispLat) && mapView._dispLat !== 0) {
                    mapView._gpsUpdating = true
                    mapView.center = mapView._navFollowCenter(mapView._dispLat, mapView._dispLon)
                    mapView._gpsUpdating = false
                }
            }
        }

        function animatePitch(targetPitch) {
            pitchAnim.stop()
            _animPitch = pitch
            _pitchAnimating = true
            pitchAnim.from = pitch
            pitchAnim.to   = targetPitch
            pitchAnim.start()
        }

        NumberAnimation {
            id: zoomAnim
            target: mapView; property: "_animZoom"
            duration: 1800; easing.type: Easing.OutCubic
            onStopped: { mapView._zoomAnimating = false }
        }

        function animateZoom(targetZoom) {
            zoomAnim.stop()
            _animZoom = zoomLevel
            _zoomAnimating = true
            zoomAnim.from = zoomLevel
            zoomAnim.to   = targetZoom
            zoomAnim.start()
        }

        function apply3dBuildings(explicitMode) {
            // Capas del estilo liberty/dark, no custom → no necesita _layersInit
            if (appSettings.mapStyleMode !== "auto") return
            var curMode = explicitMode || (root._navActive ? appSettings.navMapMode : appSettings.mapMode)
            var alpha = curMode === "3d" ? 0.5 : 0.7
            if (!_has3dBuildings) {
                // Estilo sin building-3d: mostrar edificios planos siempre
                setPaintProperty("building", "fill-opacity", alpha)
                return
            }
            if (appSettings.show3dBuildings) {
                setPaintProperty("building-3d", "fill-extrusion-opacity", alpha)
                setPaintProperty("building",    "fill-opacity",           0.0)
            } else {
                setPaintProperty("building-3d", "fill-extrusion-opacity", 0.0)
                setPaintProperty("building",    "fill-opacity",           alpha)
            }
        }

        // ── Style (day/night/auto) ─────────────────────────────────────────
        function applyLightMode() {
            _forcedStyle = ""   // limpia override temporal del botón
            var mode = appSettings.mapStyleMode
            if (mode === "satellite") { if (styleUrl !== satelliteStyleUrl) styleUrl = satelliteStyleUrl; return }
            if (mode === "positron")  { if (styleUrl !== positronUrl)  styleUrl = positronUrl;  return }
            if (mode === "bright")    { if (styleUrl !== brightUrl)    styleUrl = brightUrl;    return }
            if (mode === "fiord")     { if (styleUrl !== fiordUrl)     styleUrl = fiordUrl;     return }
            if (mode === "dark")      { if (styleUrl !== darkUrl)      styleUrl = darkUrl;      return }
            // noche explícita → fiord; auto-noche (sol) → fiord; día → dayUrl
            if (appSettings.lightMode === "night") {
                _autoNight = true
                if (styleUrl !== nightUrl) styleUrl = nightUrl
                return
            }
            var night
            if (appSettings.lightMode === "day") night = false
            else                                 night = isSunBelow()
            _autoNight = night
            var url = night ? nightUrl : dayUrl
            if (styleUrl !== url) styleUrl = url
        }

        function isSunBelow() {
            var now = new Date()
            if (!_hasPos) {
                var h = now.getHours() + now.getMinutes()/60
                return (h < 7 || h >= 21)
            }
            // Algoritmo Meeus simplificado — precisión ±1-2 min
            var jd  = now.getTime() / 86400000 + 2440587.5
            var n   = jd - 2451545.0                                   // días desde J2000.0
            var D2R = Math.PI / 180
            var L   = (280.46 + 0.9856474 * n) % 360                  // longitud media (°)
            var g   = (357.53 + 0.9856003 * n) % 360                  // anomalía media (°)
            var gR  = g * D2R
            var lam = (L + 1.915 * Math.sin(gR) + 0.020 * Math.sin(2*gR)) * D2R  // longitud eclíptica
            var eps = (23.439 - 0.0000004 * n) * D2R                  // oblicuidad eclíptica
            var decl = Math.asin(Math.sin(eps) * Math.sin(lam))       // declinación
            // Tiempo sidéreo local → ángulo horario
            var gmst = (280.46061837 + 360.98564736629 * n) * D2R
            var alpha = Math.atan2(Math.cos(eps) * Math.sin(lam), Math.cos(lam))
            var H    = gmst + _lastLon * D2R - alpha                   // ángulo horario
            // Altitud solar (+ refracción estándar −0.833°)
            var latR = _lastLat * D2R
            var alt  = Math.asin(Math.sin(latR)*Math.sin(decl) + Math.cos(latR)*Math.cos(decl)*Math.cos(H))
            return alt < -0.01454   // −0.833° en radianes (crepúsculo civil ≈ −6°)
        }

        Timer {
            id: lightTimer
            interval: 60000; repeat: true
            running:  appSettings.lightMode === "auto"
            onTriggered: mapView.applyLightMode()
        }

        // ── Auto-zoom by speed ─────────────────────────────────────────────
        property bool _zoomAuto:        false  // true while auto-zoom animates
        property real _zoomAutoTarget:  appSettings.lastZoom  // last zoom level we set programmatically
        property bool _mapInitialized:  false  // guard: evita desactivar autoZoom en el zoom inicial al arrancar

        property string _autoZoomLog: ""

        onZoomLevelChanged: {
            // Persist zoom level so we restore it on next launch
            appSettings.lastZoom = zoomLevel
            // Recenter map so GPS stays at targetY after zoom changes mpp.
            // Use a 0-ms timer to let metersPerPixel settle first.
            zoomRecenter.restart()
            // Zoom manual (pinch): desactivar autoZoom para que aparezca el botón
            // Ignorar si la animación automática está activa (_zoomAnimating) o si el timer
            // de gracia aún no ha expirado (_zoomAuto). Ambas guards son necesarias porque
            // _zoomAuto expira antes de que termine la animación (1500 ms < 1800 ms de zoomAnim).
            if (_mapInitialized && !_zoomAuto && !_zoomAnimating && appSettings.autoZoom)
                appSettings.autoZoom = false
        }

        Timer {
            id: zoomRecenter
            interval: 0; repeat: false
            onTriggered: {
                if (appSettings.bearingMode === "heading" && mapView.followMode
                        && mapView.metersPerPixel > 0
                        && !isNaN(mapView._dispLat) && mapView._dispLat !== 0) {
                    mapView._gpsUpdating = true
                    mapView.center = mapView._navFollowCenter(mapView._dispLat, mapView._dispLon)
                    mapView._gpsUpdating = false
                }
            }
        }

        Timer {
            id: zoomTimer
            interval: 2000; repeat: true
            running:  appSettings.autoZoom && mapView._hasPos
            onTriggered: {
                if (!mapView._hasPos) return
                var distM
                if (appSettings.routeAdjustZoom && root._navActive && navBar.routeData) {
                    distM = root._routeAheadDistM(appSettings.autoZoomSecs)
                    if (distM < 1) return
                } else {
                    var speedMs = activeModel.pos_speed_kmh / 3.6
                    if (speedMs < 0.5) return
                    distM = speedMs * appSettings.autoZoomSecs
                }
                var P      = mapView.pitch * Math.PI / 180
                var cosP   = Math.cos(P); var sinP = Math.sin(P)
                var fPx    = mapView.height / (2 * Math.tan(mapView._fovAngle * Math.PI / 180))
                var pxAbv  = posOverlayRoot._cy - mapView.height / 2
                var yDelta = mapView.height / 2 - root._navBarScreenHeight
                var kEff   = (sinP > 0.001)
                    ? yDelta * fPx / (fPx * cosP - yDelta * sinP) + pxAbv / (cosP + pxAbv * sinP / fPx)
                    : pxAbv + yDelta
                var targetMpp = distM / Math.max(kEff, 1)
                var target    = mapView.zoomLevel + Math.log(mapView.metersPerPixel / targetMpp) / Math.log(2)
                target = Math.max(12, Math.min(21, target))
                mapView._zoomAutoTarget = target
                if (Math.abs(mapView.zoomLevel - target) > 0.25) {
                    mapView._zoomAuto = true
                    mapView.animateZoom(target)
                    zoomAutoResetTimer.restart()
                }
            }
        }

        Timer {
            id: zoomAutoResetTimer
            interval: 2200; repeat: false  // > zoomAnim.duration (1800 ms)
            onTriggered: mapView._zoomAuto = false
        }

        // ── Layer initialization ───────────────────────────────────────────
        onStyleUrlChanged: {
            if (_layersInit) root._saveMapViewState()   // guarda antes del reload
            _layersInit = false
            _tileBusy = true
            _tileIdleTimer.restart()
            _layerInitTimer.restart()
        }

        // onMapToQtPixelRatioChanged no siempre dispara al volver al mismo estilo → timer de respaldo
        Timer {
            id: _layerInitTimer
            interval: 3000; repeat: false
            onTriggered: { if (!mapView._layersInit) mapView.initLayers() }
        }

        // Indica que el mapa aún está cargando tiles — se activa en onCompleted y al cambiar estilo
        property bool _tileBusy: true
        Timer {
            id: _tileIdleTimer
            interval: 3000; repeat: false
            onTriggered: {
                mapView._tileBusy = false
                if (!root._initialLoadDone) root._initialLoadDone = true
            }
        }

        onMapToQtPixelRatioChanged: {
            if (!_layersInit) {
                _layerInitTimer.stop()
                initLayers()
                if (_hasPos) _applyPos(_lastLat, _lastLon, _lastAcc)
            }
        }

        Timer {
            id: _mapInitTimer; interval: 800; repeat: false
            onTriggered: mapView._mapInitialized = true
        }

        Component.onCompleted: {
            console.log("TRACE [" + Date.now() + "]: mapView.onCompleted START")
            _tileBusy = true
            _tileIdleTimer.restart()
            initLayers()
            applyLightMode()
            appSettings.pitch3d = 60   // update persisted value in case of stale save
            var initMode = root._navActive ? appSettings.navMapMode : appSettings.mapMode
            pitch = (initMode === "3d") ? 60 : 0
            if (gpsSource._p2 === null) {
                _gpsUpdating = true
                center = QtPositioning.coordinate(gpsSource.defaultLat, gpsSource.defaultLon)
                _gpsUpdating = false
            }
            _mapInitTimer.start()
            console.log("TRACE [" + Date.now() + "]: mapView.onCompleted END")
        }

        function initLayers() {
            if (_layersInit) return
            _layersInit = true
            _tileBusy = true
            _tileIdleTimer.restart()
            console.log("TRACE [" + Date.now() + "]: initLayers START")

            // ── Rutas (por debajo del punto GPS) ──────────────────────────
            var dummy = QtPositioning.coordinate(0, 0)

            mapView.addSourceLine("nav-route-alt", [dummy, dummy])
            mapView.addLayer("nav-route-alt-line", {"type": "line", "source": "nav-route-alt"})
            mapView.setPaintProperty("nav-route-alt-line", "line-color",   "#78909C")
            mapView.setPaintProperty("nav-route-alt-line", "line-width",   4)
            mapView.setPaintProperty("nav-route-alt-line", "line-opacity", 0.55)
            mapView.setLayoutProperty("nav-route-alt-line", "line-cap",  "round")
            mapView.setLayoutProperty("nav-route-alt-line", "line-join", "round")
            mapView.setLayoutProperty("nav-route-alt-line", "visibility", "none")

            mapView.addSourceLine("nav-route-alt-1", [dummy, dummy])
            mapView.addLayer("nav-route-alt-1-line", {"type": "line", "source": "nav-route-alt-1"})
            mapView.setPaintProperty("nav-route-alt-1-line", "line-color",   "#90A4AE")
            mapView.setPaintProperty("nav-route-alt-1-line", "line-width",   4)
            mapView.setPaintProperty("nav-route-alt-1-line", "line-opacity", 0.45)
            mapView.setLayoutProperty("nav-route-alt-1-line", "line-cap",  "round")
            mapView.setLayoutProperty("nav-route-alt-1-line", "line-join", "round")
            mapView.setLayoutProperty("nav-route-alt-1-line", "visibility", "none")

            mapView.addSourceLine("nav-route-alt-2", [dummy, dummy])
            mapView.addLayer("nav-route-alt-2-line", {"type": "line", "source": "nav-route-alt-2"})
            mapView.setPaintProperty("nav-route-alt-2-line", "line-color",   "#B0BEC5")
            mapView.setPaintProperty("nav-route-alt-2-line", "line-width",   4)
            mapView.setPaintProperty("nav-route-alt-2-line", "line-opacity", 0.35)
            mapView.setLayoutProperty("nav-route-alt-2-line", "line-cap",  "round")
            mapView.setLayoutProperty("nav-route-alt-2-line", "line-join", "round")
            mapView.setLayoutProperty("nav-route-alt-2-line", "visibility", "none")

            var legColors = ["#2979FF","#40C4FF","#80D8FF","#B3E5FC","#E1F5FE","#F0FAFF"]
            for (var lci = legColors.length - 1; lci >= 0; lci--) {
                var lsrc = "nav-route-leg-" + lci
                mapView.addSourceLine(lsrc, [dummy, dummy])
                mapView.addLayer("nav-route-leg-line-" + lci, {"type": "line", "source": lsrc})
                mapView.setPaintProperty("nav-route-leg-line-" + lci, "line-color",   legColors[lci])
                mapView.setPaintProperty("nav-route-leg-line-" + lci, "line-width",   6)
                mapView.setPaintProperty("nav-route-leg-line-" + lci, "line-opacity", 0.72)
                mapView.setLayoutProperty("nav-route-leg-line-" + lci, "line-cap",  "round")
                mapView.setLayoutProperty("nav-route-leg-line-" + lci, "line-join", "round")
                mapView.setLayoutProperty("nav-route-leg-line-" + lci, "visibility", "none")
            }

            // ── Capas de radar de tramo ──────────────────────────────────
            var dummyR = QtPositioning.coordinate(0.001, 0.001)
            for (var rci = 0; rci < root._maxTramoLayers; rci++) {
                var rsrc = "radar-tramo-" + rci
                mapView.addSourceLine(rsrc, [dummyR, dummyR])
                mapView.addLayer("radar-tramo-line-" + rci, {"type": "line", "source": rsrc})
                mapView.setPaintProperty("radar-tramo-line-" + rci, "line-color",   "#FF6F00")
                mapView.setPaintProperty("radar-tramo-line-" + rci, "line-width",   6)
                mapView.setPaintProperty("radar-tramo-line-" + rci, "line-opacity", 0.85)
                mapView.setLayoutProperty("radar-tramo-line-" + rci, "line-cap",  "round")
                mapView.setLayoutProperty("radar-tramo-line-" + rci, "line-join", "round")
                mapView.setLayoutProperty("radar-tramo-line-" + rci, "visibility", "none")
            }

            // Restaura ruta si había una activa
            if (root._navRoutes.length > 0) {
                Qt.callLater(function() {
                    if (root._navActive) {
                        // Durante navegación activa: solo redibuja sin pan/zoom ni deshabilitar follow
                        root.drawRoute(root._navRoutes, root._navSelIdx)
                        mapView.followMode = true   // restaura follow (sim o GPS real)
                    } else {
                        // Selección de ruta pre-nav: centra el mapa normalmente
                        root.applyRoutes(root._navRoutes, root._navSelIdx)
                    }
                })
            }
            // Actualiza capas de radar si ya hay datos (p.ej. ruta test cargada antes del init)
            Qt.callLater(function() { root._updateRadarLayers(); alertCanvas.requestPaint() })

            // ── Punto GPS y anillo de precisión ───────────────────────────
            var initPos = QtPositioning.coordinate(appSettings.lastLat, appSettings.lastLon)
            mapView.addSourcePoint("nav-pos", initPos)
            mapView.addLayer("nav-dot", {"type": "circle", "source": "nav-pos"})
            mapView.setPaintProperty("nav-dot", "circle-radius", 8)
            mapView.setPaintProperty("nav-dot", "circle-color", "#2196F3")
            mapView.setPaintProperty("nav-dot", "circle-stroke-color", "white")
            mapView.setPaintProperty("nav-dot", "circle-stroke-width", 3)
            mapView.setLayoutProperty("nav-dot", "visibility", "none")

            mapView.addSourcePoint("nav-acc", initPos)
            mapView.addLayer("nav-acc-ring", {"type": "circle", "source": "nav-acc"})
            mapView.setPaintProperty("nav-acc-ring", "circle-radius", 0)
            mapView.setPaintProperty("nav-acc-ring", "circle-color", "#2196F3")
            mapView.setPaintProperty("nav-acc-ring", "circle-opacity", 0.15)
            mapView.setPaintProperty("nav-acc-ring", "circle-pitch-alignment", "map")
            mapView.setLayoutProperty("nav-acc-ring", "visibility", "none")

            // ── Debug POI markers (toggled by "poi" file command) ─────────
            // Yellow cross: map centre (should appear at screen centre)
            // Red cross:    exact GPS position (should appear at targetY)
            mapView.addSourcePoint("dbg-center", initPos)
            mapView.addLayer("dbg-center-dot", {"type": "circle", "source": "dbg-center"})
            mapView.setPaintProperty("dbg-center-dot", "circle-radius", 10)
            mapView.setPaintProperty("dbg-center-dot", "circle-color", "#FFD700")
            mapView.setPaintProperty("dbg-center-dot", "circle-stroke-color", "black")
            mapView.setPaintProperty("dbg-center-dot", "circle-stroke-width", 2)
            mapView.setLayoutProperty("dbg-center-dot", "visibility", "none")

            mapView.addSourcePoint("dbg-gps", initPos)
            mapView.addLayer("dbg-gps-dot", {"type": "circle", "source": "dbg-gps"})
            mapView.setPaintProperty("dbg-gps-dot", "circle-radius", 10)
            mapView.setPaintProperty("dbg-gps-dot", "circle-color", "#FF1744")
            mapView.setPaintProperty("dbg-gps-dot", "circle-stroke-color", "white")
            mapView.setPaintProperty("dbg-gps-dot", "circle-stroke-width", 2)
            mapView.setLayoutProperty("dbg-gps-dot", "visibility", "none")

            // Edificios 3D: aplicar visibilidad según preferencia
            mapView.apply3dBuildings()

            // Cardinal POI dots 100m from GPS: green=N, red=S, cyan=E, orange=W
            var cardColors = ["#00E676","#FF1744","#00E5FF","#FF9100"]
            var cardIds    = ["dbg-N","dbg-S","dbg-E","dbg-W"]
            for (var ci = 0; ci < 4; ci++) {
                mapView.addSourcePoint(cardIds[ci], initPos)
                mapView.addLayer(cardIds[ci]+"-dot", {"type":"circle","source":cardIds[ci]})
                mapView.setPaintProperty(cardIds[ci]+"-dot", "circle-radius", 8)
                mapView.setPaintProperty(cardIds[ci]+"-dot", "circle-color", cardColors[ci])
                mapView.setPaintProperty(cardIds[ci]+"-dot", "circle-stroke-color", "black")
                mapView.setPaintProperty(cardIds[ci]+"-dot", "circle-stroke-width", 2)
                mapView.setLayoutProperty(cardIds[ci]+"-dot", "visibility", "none")
            }

            Qt.callLater(function() { alertasOverlay._fetchAlertas() })
            Qt.callLater(root._fetchBillboards)

            // Test POI — círculo magenta para verificar _geoToScreen (toggled by "testpoi" cmd)
            mapView.addSourcePoint("test-poi", QtPositioning.coordinate(0, 0))
            mapView.addLayer("test-poi-dot", {"type": "circle", "source": "test-poi"})
            mapView.setPaintProperty("test-poi-dot", "circle-radius", 16)
            mapView.setPaintProperty("test-poi-dot", "circle-color", "#E040FB")
            mapView.setPaintProperty("test-poi-dot", "circle-stroke-color", "white")
            mapView.setPaintProperty("test-poi-dot", "circle-stroke-width", 3)
            mapView.setLayoutProperty("test-poi-dot", "visibility", "none")

            Qt.callLater(function() { root._updateParkingMarkers() })

            // Posición inicial del autostart (campo "pos" en navius_autostart)
            if (root._autostartPos !== null) {
                var _ap = root._autostartPos
                Qt.callLater(function() {
                    appSettings.manualLat = _ap.lat; appSettings.manualLon = _ap.lon
                    appSettings.manualPosActive = true
                    mapView.followMode = true
                    mapView._gpsUpdating = true
                    mapView.center = QtPositioning.coordinate(_ap.lat, _ap.lon)
                    mapView._gpsUpdating = false
                    mapView.updateGPS(_ap.lat, _ap.lon, 5.0)
                })
            }

            // Restaura vista tras cambio de estilo (solo si se guardó estado previo)
            if (root._mapViewStateSaved)
                Qt.callLater(root._restoreMapViewState)
            console.log("TRACE [" + Date.now() + "]: initLayers END")
        }

        // ── Follow / bearing mode ─────────────────────────────────────────
        onCenterChanged: {
            _centerLat = center.latitude
            _centerLon = center.longitude
            if (!_gpsUpdating) followMode = false
        }

        // Recompute centre when pitch changes outside of animation
        // (file commands "pitch+N", Component.onCompleted, etc.)
        onPitchChanged: {
            if (!_pitchAnimating && appSettings.bearingMode === "heading" && followMode
                    && metersPerPixel > 0 && !isNaN(_dispLat) && _dispLat !== 0) {
                _gpsUpdating = true
                center = _navFollowCenter(_dispLat, _dispLon)
                _gpsUpdating = false
            }
        }

        // Manual rotation exits heading-up mode
        onBearingChanged: {
            if (!_bearingAuto && appSettings.bearingMode === "heading")
                appSettings.bearingMode = "north"
        }

        // ── GPS update (para restauración de estilo / reinicio de capas) ─────
        function updateGPS(lat, lon, acc) {
            if (isNaN(lat) || isNaN(lon)) return
            _lastLat = lat; _lastLon = lon; _lastAcc = acc; _hasPos = true
            _applyPos(lat, lon, acc)
        }

        // In heading-up follow mode, offset the map centre so the GPS marker appears
        // near the bottom of the screen, giving more visibility ahead.
        // In north-up mode, the GPS marker stays at screen centre.
        function _navFollowCenter(lat, lon) {
            if (appSettings.bearingMode !== "heading" || metersPerPixel <= 0)
                return QtPositioning.coordinate(lat, lon)
            var targetY = height - units.gu(19)
            var pxAbove = targetY - height / 2   // pixels the GPS should appear below centre
            var pitchRad = pitch * Math.PI / 180
            var sinP = Math.sin(pitchRad), cosP = Math.cos(pitchRad)
            // Camera pivots around map centre (MapLibre model).
            // Camera at (0, -camH·sinP, camH·cosP), GPS at (0, -mOff, 0).
            //   pxAbove = f · mOff · cosP / (camH − mOff · sinP)
            // Solving for mOff (camH = f · mpp):
            //   mOff = pxAbove · mpp / (cosP + pxAbove · sinP / f)
            // At pitch=0 → mOff = pxAbove · mpp ✓
            var f    = height / (2 * Math.tan(_fovAngle * Math.PI / 180))  // ≈ 1.5·height
            var mOff = pxAbove * metersPerPixel
                       / (cosP + pxAbove * sinP / f)
            var br   = bearing * Math.PI / 180
            var dLat = mOff * Math.cos(br) / 111319
            var dLon = mOff * Math.sin(br) / (111319 * Math.cos(lat * Math.PI / 180))
            return QtPositioning.coordinate(lat + dLat, lon + dLon)
        }

        // Dead-reckoning smooth update: keeps source points and overlay in sync
        // in both follow mode (map moves) and non-follow mode (marker moves on fixed map).
        function _smoothApplyPos(lat, lon) {
            if (isNaN(lat) || isNaN(lon)) return
            var c = QtPositioning.coordinate(lat, lon)
            mapView.updateSourcePoint("nav-pos", c)
            mapView.updateSourcePoint("nav-acc", c)
            _dispLat = lat
            _dispLon = lon
            if (!followMode) return
            _gpsUpdating = true
            mapView.center = _navFollowCenter(lat, lon)
            _gpsUpdating = false
        }

        function _applyPos(lat, lon, acc) {
            _smoothApplyPos(lat, lon)
        }

        MapboxMapGestureArea {
            id: gestureArea; map: mapView
            enabled: !root._mapLocked
            activePressAndHoldGeo: true
            onDoubleClicked: {
                if (!mapView._hasPos) return
                mapView.followMode = true
                mapView._gpsUpdating = true
                mapView.center = QtPositioning.coordinate(mapView._lastLat, mapView._lastLon)
                mapView._gpsUpdating = false
            }
            onClicked: {
                // Detectar tap en billboard — abre URL en navegador
                if (root._billboards.length > 0) {
                    var _bbWL2 = units.gu(13), _bbWP2 = units.gu(13) * 1.2
                    var _bbH2 = units.gu(6), _bbPH2 = units.gu(2.5), _bbOD2 = units.gu(6)
                    for (var _bbt = 0; _bbt < root._billboards.length; _bbt++) {
                        var _bbb  = root._billboards[_bbt]
                        var _bbp2 = root._geoToScreen(_bbb.lat, _bbb.lng)
                        var _rr2  = ((_bbb.bearing || 0) - mapView.bearing + 90) * Math.PI / 180
                        var _bx2, _pBase2, _bw2
                        if ((_bbb.tipo || "lado") === "puente") {
                            _bw2    = _bbWP2
                            _bx2    = _bbp2.x - _bw2 / 2
                            _pBase2 = _bbp2.y
                        } else {
                            _bw2    = _bbWL2
                            var _ax2 = _bbp2.x + Math.sin(_rr2) * _bbOD2
                            var _ay2 = _bbp2.y - Math.cos(_rr2) * _bbOD2
                            _bx2    = (_bbb._sideFixed !== false) ? _ax2 : (_ax2 - _bw2)
                            _pBase2 = _ay2
                        }
                        var _by2 = _pBase2 - _bbPH2 - _bbH2
                        if (mouse.x >= _bx2 && mouse.x <= _bx2 + _bw2
                                && mouse.y >= _by2 && mouse.y <= _by2 + _bbH2) {
                            if (_bbb.url) Qt.openUrlExternally(
                                NavAlerts.clickUrl(_bbb.id, mainAuthSettings.token || ""))
                            return
                        }
                    }
                }
                // Detectar tap en señal de límite comunitaria
                if (mainAuthSettings.token !== "") {
                    var _slHitR = units.gu(4)
                    for (var _slt = 0; _slt < root._commLimites.length; _slt++) {
                        var _slHit = root._commLimites[_slt]
                        var _slHp  = root._geoToScreen(_slHit.lat, _slHit.lng)
                        var _slBrg2 = _slHit.bearing * Math.PI / 180
                        var _slOff2  = units.gu(3.5)
                        var _slHcx = _slHp.x + Math.cos(_slBrg2) * _slOff2
                        var _slHcy = _slHp.y + Math.sin(_slBrg2) * _slOff2
                        var _slDx = mouse.x - _slHcx, _slDy = mouse.y - _slHcy
                        if (Math.sqrt(_slDx*_slDx + _slDy*_slDy) < _slHitR) {
                            root._tapCommLimit = _slHit
                            commLimitCancelPopup.visible = true
                            return
                        }
                    }
                }
                // Detectar tap en alerta cercana (umbral 60 px, solo con sesión)
                var _nearAlert = null
                for (var _ai = 0; _ai < (mainAuthSettings.token !== "" ? root._commAlertas.length : 0); _ai++) {
                    var _aa = root._commAlertas[_ai]
                    var _sp = root._geoToScreen(_aa.lat, _aa.lng)
                    var _dx = mouse.x - _sp.x, _dy = mouse.y - _sp.y
                    // Hit: viñeta a la derecha del punto geo + margen en el punto
                    var _inViñeta = _dx > -units.gu(1) && _dx < units.gu(16)
                                    && Math.abs(_dy) < units.gu(6)
                    if (_inViñeta) { _nearAlert = _aa; break }
                }
                if (_nearAlert) {
                    root._voteAlerta = _nearAlert
                    var _uid = mainAuthSettings.userId
                    var _aid = _nearAlert.usuario_id || 0
                    alertaVotePopup._isOwn = _uid > 0 && _aid > 0 && _aid === _uid
                    alertaVotePopup.visible = true
                } else {
                    if (root._pinVisible) root._pinVisible = false
                    if (alertaVotePopup.visible) alertaVotePopup.visible = false
                }
            }
            onPressAndHoldGeo: {
                root._pinLat = geocoordinate.latitude
                root._pinLon = geocoordinate.longitude
                root._pinVisible = true
                alertCanvas.requestPaint()
            }
        }
    }

    // ── Canvas de radares (iconos sobre el mapa, bajo el marcador GPS) ────────
    Canvas {
        id: alertCanvas
        anchors.fill: mapView
        z: 0


        visible: !prefsPanel.visible && !satPanel.visible
                 && (root._pinVisible || root._testPoiVisible ||
                     (root._navActive && root._navDests.length > 0) ||
                     (appSettings.showRadarFijos && root._radarFijos.length > 0) ||
                     (appSettings.showRadarTramo && root._radarTramos.length > 0) ||
                     (appSettings.showGpsTicks && root._gpsTickDots.length > 0) ||
                     root._commAlertas.length > 0 ||
                     root._commLimites.length > 0 ||
                     appSettings.showBisectorDebug)

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var iW = width, iH = height
            // Margen superior: evita pintar sobre NavBar y banners de radar
            var topClip = root._navBarScreenHeight + (root._navActive
                ? root._radarBarsHeight
                : (root._commAlertActive ? units.gu(5.5) : 0))

            // Radares de tramo — icono de inicio y fin (mismo estilo que radares fijos)
            if (appSettings.showRadarTramo) {
                for (var ti = 0; ti < root._radarTramos.length; ti++) {
                    var trm = root._radarTramos[ti]
                    var tSz = units.gu(2.4)
                    // Posiciones reales de las cámaras (origShape si disponible, si no shape[0/last])
                    var orig0 = trm.origShape ? trm.origShape[0] : trm.shape[0]
                    var origN = trm.origShape ? trm.origShape[1] : trm.shape[trm.shape.length - 1]
                    var startLat = orig0[1], startLon = orig0[0]
                    var endLat   = origN[1], endLon   = origN[0]
                    var p0 = root._geoToScreen(startLat, startLon)
                    var pN = root._geoToScreen(endLat, endLon)

                    // Línea de puntos entre las dos cámaras reales
                    if (trm.origShape) {
                        ctx.save()
                        ctx.setLineDash([units.gu(0.6), units.gu(0.5)])
                        ctx.strokeStyle = "#FF6F00"; ctx.lineWidth = units.gu(0.35)
                        ctx.beginPath(); ctx.moveTo(p0.x, p0.y); ctx.lineTo(pN.x, pN.y)
                        ctx.stroke()
                        ctx.restore()
                    }

                    // Icono inicio (círculo sólido naranja con límite)
                    if (p0.x > -tSz && p0.x < iW+tSz && p0.y >= topClip && p0.y < iH+tSz) {
                        ctx.beginPath()
                        ctx.arc(p0.x, p0.y, tSz, 0, Math.PI * 2)
                        ctx.fillStyle = "#FF6F00"; ctx.fill()
                        ctx.strokeStyle = "white"; ctx.lineWidth = 2; ctx.stroke()
                        ctx.fillStyle = "white"
                        ctx.font = "bold " + Math.round(units.gu(1.4)) + "px sans-serif"
                        ctx.textAlign = "center"; ctx.textBaseline = "middle"
                        ctx.fillText(trm.maxspeed > 0 ? String(trm.maxspeed) : "T", p0.x, p0.y)
                    }
                    // Icono fin (círculo semitransparente naranja)
                    if (pN.x > -tSz && pN.x < iW+tSz && pN.y >= topClip && pN.y < iH+tSz) {
                        ctx.beginPath()
                        ctx.arc(pN.x, pN.y, tSz * 0.75, 0, Math.PI * 2)
                        ctx.fillStyle = "#55FF6F00"; ctx.fill()
                        ctx.strokeStyle = "#FF6F00"; ctx.lineWidth = 2; ctx.stroke()
                    }
                }
            }

            // Radares fijos — círculo rojo con límite de velocidad
            if (appSettings.showRadarFijos) {
                for (var fi = 0; fi < root._radarFijos.length; fi++) {
                    var r = root._radarFijos[fi]
                    var sz2 = units.gu(2.4)
                    var sp = root._geoToScreen(r.lat, r.lon)
                    if (sp.x < -sz2 || sp.x > iW+sz2 || sp.y < topClip || sp.y > iH+sz2) continue
                    ctx.beginPath()
                    ctx.arc(sp.x, sp.y, sz2, 0, Math.PI * 2)
                    ctx.fillStyle = "#E53935"; ctx.fill()
                    ctx.strokeStyle = "white"; ctx.lineWidth = 2; ctx.stroke()
                    ctx.fillStyle = "white"
                    ctx.font = "bold " + Math.round(units.gu(1.4)) + "px sans-serif"
                    ctx.textAlign = "center"; ctx.textBaseline = "middle"
                    ctx.fillText(r.maxspeed > 0 ? String(r.maxspeed) : "R", sp.x, sp.y)
                }
            }

            // Bandera a cuadros en el destino final (cuando hay navegación activa)
            if (root._navActive && root._navDests.length > 0) {
                var dest = root._navDests[root._navDests.length - 1]
                var dp   = root._geoToScreen(dest.lat, dest.lon)
                var dW   = iW, dH = iH
                if (dp.x > -units.gu(5) && dp.x < dW + units.gu(5)
                        && dp.y > topClip - units.gu(5) && dp.y < dH + units.gu(5)) {
                    var poleH = units.gu(3.2)
                    var fw = units.gu(2.0), fh = units.gu(1.4)
                    var cols = 4, rows = 3
                    var sw = fw / cols, sh = fh / rows
                    var fx = dp.x, fy = dp.y
                    // Sombra del palo
                    ctx.save()
                    ctx.shadowColor = "rgba(0,0,0,0.6)"; ctx.shadowBlur = 4
                    ctx.strokeStyle = "white"; ctx.lineWidth = units.gu(0.25)
                    ctx.beginPath()
                    ctx.moveTo(fx, fy)
                    ctx.lineTo(fx, fy - poleH - fh)
                    ctx.stroke()
                    ctx.restore()
                    // Cuadrícula de la bandera
                    for (var fr = 0; fr < rows; fr++) {
                        for (var fc = 0; fc < cols; fc++) {
                            ctx.fillStyle = (fr + fc) % 2 === 0 ? "white" : "#111111"
                            ctx.fillRect(fx + fc * sw, fy - poleH - fh + fr * sh, sw, sh)
                        }
                    }
                    // Borde bandera
                    ctx.strokeStyle = "#BBBBBB"; ctx.lineWidth = 1
                    ctx.strokeRect(fx, fy - poleH - fh, fw, fh)
                    // Punto de anclaje (base del palo)
                    ctx.beginPath()
                    ctx.arc(fx, fy, units.gu(0.4), 0, Math.PI * 2)
                    ctx.fillStyle = "white"; ctx.fill()
                }
            }

            // Marcador de long press — pin azul con cruz
            if (root._pinVisible) {
                var pp = root._geoToScreen(root._pinLat, root._pinLon)
                if (pp.x > -units.gu(4) && pp.x < iW+units.gu(4)
                        && pp.y > -units.gu(4) && pp.y < iH+units.gu(4)) {
                    var pr = units.gu(1.4)
                    ctx.beginPath()
                    ctx.arc(pp.x, pp.y, pr, 0, Math.PI * 2)
                    ctx.fillStyle = "#CC1565C3"; ctx.fill()
                    ctx.strokeStyle = "white"; ctx.lineWidth = units.gu(0.2); ctx.stroke()
                    var arm = units.gu(2.2)
                    ctx.beginPath()
                    ctx.moveTo(pp.x - arm, pp.y); ctx.lineTo(pp.x + arm, pp.y)
                    ctx.moveTo(pp.x, pp.y - arm); ctx.lineTo(pp.x, pp.y + arm)
                    ctx.strokeStyle = "#1565C3"; ctx.lineWidth = units.gu(0.25); ctx.stroke()
                }
            }


            // Ticks GPS reales (debug)
            if (appSettings.showGpsTicks && root._gpsTickDots.length > 0) {
                var dotR = units.gu(0.5)
                for (var di = 0; di < root._gpsTickDots.length; di++) {
                    var td = root._gpsTickDots[di]
                    var tp2 = root._geoToScreen(td.lat, td.lon)
                    if (tp2.x < -dotR || tp2.x > iW + dotR || tp2.y < -dotR || tp2.y > iH + dotR) continue
                    ctx.beginPath()
                    ctx.arc(tp2.x, tp2.y, dotR, 0, Math.PI * 2)
                    ctx.fillStyle = "#CC00E5FF"; ctx.fill()
                }
            }

            // Debug bisector: extremos angulares de la ruta (relativo al bearing del mapa)
            if (appSettings.showBisectorDebug) {
                var _veh = root._geoToScreen(gpsSource.lat, gpsSource.lon)
                var _r   = units.gu(1.2)
                ctx.font = units.gu(1.2) + "px sans-serif"
                function _drawBisLine(pt, color, label) {
                    if (!pt) return
                    var sp = root._geoToScreen(pt.lat, pt.lon)
                    ctx.beginPath(); ctx.moveTo(_veh.x, _veh.y); ctx.lineTo(sp.x, sp.y)
                    ctx.strokeStyle = color; ctx.lineWidth = units.gu(0.3); ctx.stroke()
                    ctx.beginPath(); ctx.arc(sp.x, sp.y, _r, 0, Math.PI * 2)
                    ctx.fillStyle = color; ctx.fill()
                    ctx.fillStyle = "white"
                    ctx.fillText(label, sp.x + _r + units.gu(0.3), sp.y + units.gu(0.5))
                }
                _drawBisLine(gpsSource.bisectorMinPt, "#FF4444", "izq")
                _drawBisLine(gpsSource.bisectorMaxPt, "#4488FF", "der")
                if (gpsSource.bisectorCtrPt) {
                    var _sc = root._geoToScreen(gpsSource.bisectorCtrPt.lat, gpsSource.bisectorCtrPt.lon)
                    ctx.beginPath(); ctx.arc(_sc.x, _sc.y, units.gu(1.5), 0, Math.PI * 2)
                    ctx.fillStyle = "#44FF88"; ctx.fill()
                    ctx.fillStyle = "white"
                    ctx.fillText("ctr", _sc.x + units.gu(1.8), _sc.y + units.gu(0.5))
                }
            }

            // Test POI canvas: cruz magenta en _geoToScreen para comparar con capa MapboxGL
            if (root._testPoiVisible) {
                var tp = root._geoToScreen(root._testPoiLat, root._testPoiLon)
                if (tp.x > -units.gu(4) && tp.x < iW + units.gu(4)
                        && tp.y > -units.gu(4) && tp.y < iH + units.gu(4)) {
                    var arm2 = units.gu(5.0)
                    ctx.strokeStyle = "#E040FB"; ctx.lineWidth = units.gu(0.5)
                    ctx.beginPath()
                    ctx.moveTo(tp.x - arm2, tp.y); ctx.lineTo(tp.x + arm2, tp.y)
                    ctx.moveTo(tp.x, tp.y - arm2); ctx.lineTo(tp.x, tp.y + arm2)
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.arc(tp.x, tp.y, arm2 * 0.6, 0, Math.PI * 2)
                    ctx.strokeStyle = "#E040FB"; ctx.lineWidth = units.gu(0.4); ctx.stroke()
                }
            }

            // Viñetas de alertas comunitarias: icono arriba + texto+votos abajo
            var _vSubMap = {
                "denso":"Tráfico denso","detenido":"Detenido",
                "camara_movil":"Cámara móvil","oculto":"Oculto",
                "colision_multiple":"Col. múltiple",
                "obras":"Obras","coche_arcen":"Arcén","semaforo_estropeado":"Semáforo","bache":"Bache",
                "izquierdo":"Carril izq.","derecho":"Carril der.","central":"Carril central",
                "calzada_resbaladiza":"Resbaladiza","inundacion":"Inundación",
                "nieve":"Nieve","niebla":"Niebla","hielo":"Hielo",
                "companeros":"Compañeros","emergencia":"Emergencia"
            }
            var _vCatMap = {
                "trafico":"Tráfico","policia":"Policía","accidente":"Accidente",
                "peligro":"Peligro","carretera_cortada":"Cortada",
                "carril_bloqueado":"Carril","error_mapa":"Error mapa",
                "mal_tiempo":"Mal tiempo","asistencia":"Asistencia","lugar":"Lugar"
            }
            var _viISz = units.gu(6.5)   // tamaño icono
            var _viFS  = Math.round(units.gu(1.35))
            var _viTH  = units.gu(2.0)   // alto zona texto
            var _viPad = units.gu(0.5)
            var _viBH  = _viPad + _viISz + _viPad + _viTH + _viPad  // alto burbuja
            var _viTriH= units.gu(1.0)   // alto triángulo puntero
            var _viBr  = units.gu(0.7)   // radio esquinas
            var _viMinW = _viISz + _viPad * 2   // ancho mínimo (icono + márgenes)

            for (var _vai = 0; _vai < root._commAlertas.length; _vai++) {
                var _va2  = root._commAlertas[_vai]
                var _vap  = root._geoToScreen(_va2.lat, _va2.lng)
                if (_vap.x < -units.gu(12) || _vap.x > iW + units.gu(12)
                        || _vap.y < -units.gu(12) || _vap.y > iH + units.gu(12)) continue

                var _viKey = (_va2.subtipo && _va2.subtipo !== "")
                             ? _va2.categoria + "_" + _va2.subtipo
                             : _va2.categoria
                var _viUrl = "qrc:/assets/alertas/" + _viKey + ".png"
                var _viImgReady = alertCanvas.isImageLoaded(_viUrl)

                var _viTxt = (_va2.subtipo && _va2.subtipo !== "")
                             ? (_vSubMap[_va2.subtipo] || _va2.subtipo)
                             : (_vCatMap[_va2.categoria] || _va2.categoria)
                if (_va2.votos_ok > 0) _viTxt += "  +" + _va2.votos_ok

                // ancho dinámico según texto medido
                ctx.font = "bold " + _viFS + "px sans-serif"
                var _viTw = ctx.measureText(_viTxt).width
                var _viW  = Math.max(_viMinW, _viTw + _viPad * 2)

                // punta a la izquierda → viñeta a la derecha de la posición geo
                var _viTriW = units.gu(1.0)  // ancho punta
                var _viBx   = _vap.x + _viTriW
                var _viBy   = _vap.y - _viBH / 2

                // fondo burbuja redondeado
                ctx.fillStyle = "rgba(210, 100, 20, 0.90)"
                ctx.beginPath()
                ctx.moveTo(_viBx + _viBr, _viBy)
                ctx.lineTo(_viBx + _viW - _viBr, _viBy)
                ctx.arcTo(_viBx+_viW, _viBy,        _viBx+_viW, _viBy+_viBr,        _viBr)
                ctx.lineTo(_viBx+_viW, _viBy+_viBH-_viBr)
                ctx.arcTo(_viBx+_viW, _viBy+_viBH,  _viBx+_viW-_viBr, _viBy+_viBH, _viBr)
                ctx.lineTo(_viBx+_viBr, _viBy+_viBH)
                ctx.arcTo(_viBx,       _viBy+_viBH,  _viBx, _viBy+_viBH-_viBr,      _viBr)
                ctx.lineTo(_viBx,      _viBy+_viBr)
                ctx.arcTo(_viBx,       _viBy,         _viBx+_viBr, _viBy,            _viBr)
                ctx.closePath()
                ctx.fill()

                // triángulo puntero a la izquierda
                var _viMidY = _vap.y
                ctx.beginPath()
                ctx.moveTo(_viBx, _viMidY - units.gu(0.55))
                ctx.lineTo(_vap.x, _viMidY)
                ctx.lineTo(_viBx, _viMidY + units.gu(0.55))
                ctx.fillStyle = "rgba(210, 100, 20, 0.90)"; ctx.fill()

                // icono PNG centrado en la zona superior (solo si cargado)
                var _viIx = _viBx + (_viW - _viISz) / 2
                var _viIy = _viBy + _viPad
                if (_viImgReady) ctx.drawImage(_viUrl, _viIx, _viIy, _viISz, _viISz)

                // badge señal de velocidad (esquina inferior derecha del icono)
                if (_va2.velocidad) {
                    var _vsr = units.gu(1.8)
                    var _vscx = _viBx + _viW - _vsr * 0.6
                    var _vscy = _viBy + _viPad + _viISz - _vsr * 0.6
                    ctx.beginPath(); ctx.arc(_vscx, _vscy, _vsr, 0, 2 * Math.PI)
                    ctx.fillStyle = "white"; ctx.fill()
                    ctx.strokeStyle = "#C62828"; ctx.lineWidth = units.gu(0.3)
                    ctx.stroke()
                    ctx.font = "bold " + Math.round(units.gu(1.5)) + "px sans-serif"
                    ctx.textAlign = "center"; ctx.textBaseline = "middle"
                    ctx.fillStyle = "black"
                    ctx.fillText(_va2.velocidad, _vscx, _vscy)
                }

                // texto centrado en zona inferior
                ctx.font = "bold " + _viFS + "px sans-serif"
                ctx.textAlign = "center"; ctx.textBaseline = "middle"
                ctx.fillStyle = "white"
                ctx.fillText(_viTxt, _viBx + _viW / 2, _viBy + _viPad + _viISz + _viPad + _viTH / 2)
            }

            // ── Señales de límite de velocidad comunitarias ──────────────────
            var _slR = units.gu(1.92)   // 60% de 3.2
            var _slFS = Math.round(units.gu(1.8))
            var _mapBrgSl = mapView.bearing * Math.PI / 180
            for (var _sli = 0; _sli < root._commLimites.length; _sli++) {
                var _sl2 = root._commLimites[_sli]
                var _slp = root._geoToScreen(_sl2.lat, _sl2.lng)
                if (_slp.x < -_slR*2 || _slp.x > iW + _slR*2
                        || _slp.y < topClip - _slR*2 || _slp.y > iH + _slR*2) continue
                // Perpendicular derecha del sentido de marcha en coordenadas de pantalla
                var _slBrg = _sl2.bearing * Math.PI / 180
                var _slRel = _slBrg - _mapBrgSl
                var _slOff = units.gu(4.5)
                var _slcx = _slp.x + Math.cos(_slRel) * _slOff
                var _slcy = _slp.y + Math.sin(_slRel) * _slOff
                ctx.beginPath(); ctx.arc(_slcx, _slcy, _slR, 0, 2 * Math.PI)
                ctx.fillStyle = "white"; ctx.fill()
                ctx.strokeStyle = "#C62828"
                ctx.lineWidth = _sl2.id === root._commSpeedLimitId ? units.gu(0.55) : units.gu(0.35)
                ctx.stroke()
                ctx.font = "bold " + (_sl2.velocidad >= 100 ? Math.round(units.gu(1.5)) : _slFS) + "px sans-serif"
                ctx.textAlign = "center"; ctx.textBaseline = "middle"
                ctx.fillStyle = "#1A1A1A"
                ctx.fillText(_sl2.velocidad, _slcx, _slcy)
            }

        }
        // Nota: los billboards se dibujan en bridgeCanvas (z:3), sobre el icono del vehículo (z:1)

        // Repintar cuando el mapa se mueve
        Connections {
            target: mapView
            function onBearingChanged()        { alertCanvas.requestPaint() }
            function onPitchChanged()          { alertCanvas.requestPaint() }
            function onCenterChanged()         { alertCanvas.requestPaint() }
            function onZoomLevelChanged()      { alertCanvas.requestPaint() }
            function onMetersPerPixelChanged() { alertCanvas.requestPaint() }
        }
        Connections {
            target: root
            function onPinVisibleChanged()      { alertCanvas.requestPaint() }
            function onPinLatChanged()          { alertCanvas.requestPaint() }
            function onNavActiveChanged()       { alertCanvas.requestPaint() }
            function onNavDestsChanged()        { alertCanvas.requestPaint() }
            function onDispHeadRadChanged()     { alertCanvas.requestPaint() }
            function onTestPoiVisibleChanged()  { alertCanvas.requestPaint() }
            function onBillboardsChanged()       { alertCanvas.requestPaint() }
            function onCommAlertasChanged()     { alertCanvas.requestPaint() }
            function onCommLimitesChanged()     { alertCanvas.requestPaint() }
            function onCommSpeedLimitIdChanged(){ alertCanvas.requestPaint() }
        }
        Connections {
            target: gpsSource
            function onBisectorCtrPtChanged() { if (appSettings.showBisectorDebug) alertCanvas.requestPaint() }
        }
        Connections {
            target: gpsSource
            function onDrActiveChanged() {
                if (!gpsSource.drActive)
                    root._statusQueue.push({ text: i18n.tr("GPS recuperado"), color: "#81C784" })
            }
        }
    }

    // ── Position overlay: accuracy ring + direction arrow or dot ──────────────
    // Follow mode: fixed at screen centre (zero vibration).
    // Non-follow mode: geo→screen projection updated at dead-reckoning rate.
    Item {
        id: posOverlayRoot
        visible: (activeModel.pos_has_fix || root._drEstimating)
                 && !satPanel.visible && !prefsPanel.visible
        anchors.fill: mapView
        z: 1

        // Screen-space position of the GPS fix.
        // In follow mode the map centre tracks the GPS, so the difference ≈ 0 → screen centre.
        // When the map is rotated (bearing ≠ 0) the geo→screen projection must rotate accordingly:
        //   screen_x component = dE·cos(B) − dN·sin(B)
        //   screen_y component = dE·sin(B) + dN·cos(B)   (then negated because screen y is down)
        // Perspective-correct geo→screen projection for the GPS marker.
        // In flat mode (pitch<1) degenerates to plain equirectangular formula.
        // In 3D, uses the same pinhole model as _navFollowCenter / _pt():
        //   dnm = f·mpp + dFwd·sinP  (perspective denominator, grows for far points)
        property point _screenPos: {
            if (mapView.followMode)
                return Qt.point(mapView.width / 2,
                    appSettings.bearingMode === "heading"
                        ? (mapView.height - units.gu(19)) : mapView.height / 2)
            if (mapView.metersPerPixel <= 0)
                return Qt.point(mapView.width / 2, mapView.height / 2)
            var dE     = (mapView._dispLon - mapView._centerLon)
                         * 111319.49 * Math.cos(mapView._centerLat * Math.PI / 180)
            var dN     = (mapView._dispLat - mapView._centerLat) * 111319.49
            var B      = mapView.bearing * Math.PI / 180
            var dFwd   = dN * Math.cos(B) + dE * Math.sin(B)
            var dRight = dE * Math.cos(B) - dN * Math.sin(B)
            var mpp    = mapView.metersPerPixel
            if (mapView.pitch < 1)
                return Qt.point(mapView.width  / 2 + dRight / mpp,
                                mapView.height / 2 - dFwd   / mpp)
            var P    = mapView.pitch * Math.PI / 180
            var cosP = Math.cos(P), sinP = Math.sin(P)
            var f    = mapView.height / (2 * Math.tan(mapView._fovAngle * Math.PI / 180))
            var dnm  = f * mpp + dFwd * sinP
            if (Math.abs(dnm) < 1e-6) return Qt.point(mapView.width / 2, mapView.height / 2)
            return Qt.point(
                mapView.width  / 2 + f * dRight / dnm,
                mapView.height / 2 - f * dFwd * cosP / dnm)
        }
        property real _cx: _screenPos.x
        property real _cy: _screenPos.y

        // Accuracy ring — hidden during dead-reckoning (accuracy unknown)
        Rectangle {
            property real accPx: (mapView.metersPerPixel > 0 && activeModel.pos_accuracy > 0)
                                 ? activeModel.pos_accuracy / mapView.metersPerPixel / mapView.pixelRatio
                                 : 0
            visible: accPx > 2 && !root._drEstimating
            width: accPx * 2; height: accPx * 2; radius: accPx
            x: posOverlayRoot._cx - width  / 2
            y: posOverlayRoot._cy - height / 2
            color: "#202196F3"
            border.color: "#602196F3"; border.width: 1
        }

        // Direction arrow — delta-wing shape pointing toward heading.
        // Red + blinking while dead-reckoning (no GPS fix).
        Item {
            id: arrowItem
            visible: root._hasArrow
            width: units.gu(5.4); height: units.gu(5.4)
            x: posOverlayRoot._cx - width  / 2
            y: posOverlayRoot._cy - height / 2
            rotation: root._dispHeadRad * 180 / Math.PI - mapView.bearing

            SequentialAnimation on opacity {
                running: root._drEstimating && root._hasArrow
                loops:   Animation.Infinite
                NumberAnimation { to: 0.2; duration: 420 }
                NumberAnimation { to: 1.0; duration: 420 }
                onStopped: arrowItem.opacity = 1.0
            }

            Canvas {
                id: arrowCanvas
                property color arrowFill: root._drEstimating ? "#FF5252" : "#29B6F6"
                anchors.fill: parent
                Component.onCompleted: requestPaint()
                onVisibleChanged:   if (visible) requestPaint()
                onArrowFillChanged: requestPaint()
                onPaint: {
                    var ctx  = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var w    = width, h = height
                    // Compress forward axis at half intensity: blend 50% between full and cosP
                    var cosP  = Math.cos(mapView.pitch * Math.PI / 180)
                    var scale = 0.5 + 0.5 * cosP
                    var tipY  = h * 0.83 - scale * (h * 0.83 - h * 0.04)
                    var joinY = h * 0.83 - scale * (h * 0.83 - h * 0.57)
                    ctx.beginPath()
                    ctx.moveTo(w * 0.50, tipY)
                    ctx.lineTo(w * 0.90, h * 0.83)
                    ctx.lineTo(w * 0.50, joinY)
                    ctx.lineTo(w * 0.10, h * 0.83)
                    ctx.closePath()
                    ctx.fillStyle   = arrowFill
                    ctx.fill()
                    ctx.strokeStyle = "white"
                    ctx.lineWidth   = 2.5
                    ctx.lineJoin    = "round"
                    ctx.stroke()
                }
                Connections {
                    target: mapView
                    function onPitchChanged() { arrowCanvas.requestPaint() }
                }
            }
        }

        // Dot — shown before the arrow appears (speed < 1 km/h since last fix)
        // Red + blinking while dead-reckoning.
        Rectangle {
            id: posDot
            visible: !root._hasArrow
            width: units.gu(0.8); height: units.gu(0.8); radius: width / 2
            x: posOverlayRoot._cx - width  / 2
            y: posOverlayRoot._cy - height / 2
            color: root._drEstimating ? "#FF5252" : "#2196F3"
            border.color: "white"; border.width: units.gu(0.14)

            SequentialAnimation on opacity {
                running: root._drEstimating && !root._hasArrow
                loops:   Animation.Infinite
                NumberAnimation { to: 0.2; duration: 420 }
                NumberAnimation { to: 1.0; duration: 420 }
                onStopped: posDot.opacity = 1.0
            }
        }
    }

    // ── Todos los billboards — z:3 (sobre vehículo z:1 y aparcamiento z:2) ────
    Canvas {
        id: bridgeCanvas
        anchors.fill: mapView
        z: 3
        visible: root._billboards.length > 0 && !prefsPanel.visible && !satPanel.visible

        Connections {
            target: alertCanvas
            function onPainted() { bridgeCanvas.requestPaint() }
        }
        Connections {
            target: mapView
            function onBearingChanged()        { bridgeCanvas.requestPaint() }
            function onCenterChanged()         { bridgeCanvas.requestPaint() }
            function onZoomLevelChanged()      { bridgeCanvas.requestPaint() }
            function onMetersPerPixelChanged() { bridgeCanvas.requestPaint() }
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root._billboards.length === 0 || mapView.zoomLevel < 10) return
            var iW = width, iH = height

            var _bbWL    = units.gu(13)           // ancho tipo lado
            var _bbWP    = units.gu(13) * 1.2     // ancho tipo puente (+20 %)
            var _bbR     = units.gu(0.6)
            var _bbPoleH = units.gu(2.5)
            var _bbPoleW = units.gu(0.3)
            var _bbFS    = Math.round(units.gu(1.3))
            var _bbSF    = Math.round(units.gu(1.1))
            var _bbLH    = units.gu(1.7)
            var _bbPad   = units.gu(0.65)
            var _bbGap   = units.gu(0.4)
            var _bbODist = units.gu(6)
            var _logoR   = units.gu(1.0)

            var _wrap = function(txt, maxCh, maxLines) {
                if (!txt) return []
                var words = txt.split(/\s+/).filter(Boolean), lines = [], cur = ""
                for (var wi = 0; wi < words.length; wi++) {
                    var w = words[wi]
                    if (w.length > maxCh) w = w.substring(0, maxCh - 1) + "…"
                    var test = cur ? cur + " " + w : w
                    if (test.length <= maxCh) { cur = test }
                    else {
                        if (cur) lines.push(cur)
                        if (lines.length >= maxLines) { cur = ""; break }
                        cur = w
                    }
                }
                if (cur && lines.length < maxLines) lines.push(cur)
                return lines
            }

            // Precalcular posiciones en pantalla y ordenar por Y ascendente:
            // Y pequeño = más arriba en pantalla = más lejos = se pinta primero = queda detrás
            var _withPos = root._billboards.map(function(b) {
                return { bb: b, bp: root._geoToScreen(b.lat, b.lng) }
            })
            _withPos.sort(function(a, b) { return a.bp.y - b.bp.y })

            for (var _bi = 0; _bi < _withPos.length; _bi++) {
                var _bb       = _withPos[_bi].bb
                var _bp       = _withPos[_bi].bp
                var _tipo     = _bb.tipo || "lado"
                var _rightRad = ((_bb.bearing || 0) - mapView.bearing + 90) * Math.PI / 180

                // ── Posición según tipo ───────────────────────────────────
                var _bbW, _bx, _pBaseY, _p1x, _p2x
                if (_tipo === "puente") {
                    _bbW    = _bbWP
                    _bx     = _bp.x - _bbW / 2
                    _pBaseY = _bp.y
                    _p1x    = _bx
                    _p2x    = _bx + _bbW
                } else {
                    _bbW    = _bbWL
                    var _ax = _bp.x + Math.sin(_rightRad) * _bbODist
                    var _ay = _bp.y - Math.cos(_rightRad) * _bbODist
                    if (_bb._sideFixed === undefined)
                        _bb._sideFixed = (_ax + _bbW <= iW)
                    _bx     = _bb._sideFixed ? _ax : (_ax - _bbW)
                    _pBaseY = _ay
                    _p1x    = _bx + _bbW * 0.25
                    _p2x    = _bx + _bbW * 0.75
                }

                // ── Badge y área de texto ─────────────────────────────────
                var _isNavius   = !!(_bb.url && _bb.url.indexOf("navius") >= 0)
                var _badgeSlotW = _isNavius ? (2 * _logoR + _bbPad * 0.75) : 0
                var _txtAreaL   = _bx + _bbPad + _badgeSlotW
                var _txtAreaR   = _bx + _bbW - _bbPad
                var _txtW       = _txtAreaR - _txtAreaL
                var _chT = Math.max(5, Math.floor(_txtW / (_bbFS * 0.62)))
                var _chS = Math.max(5, Math.floor(_txtW / (_bbSF * 0.62)))

                // ── Texto y altura ────────────────────────────────────────
                var _tLines = _wrap(_bb.titulo || "", _chT, 2)
                var _sRaw   = _bb.subtitulo || (_bb.url ? _bb.url.replace(/^https?:\/\//, "") : "")
                var _sLines = _wrap(_sRaw, _chS, 2)
                var _hasS   = _sLines.length > 0
                var _textH  = _bbPad * 2 + _tLines.length * _bbLH
                              + (_hasS ? _bbGap + _sLines.length * _bbLH : 0)
                var _badgeH = _isNavius ? (_bbPad * 2 + 2 * _logoR) : 0
                var _bbH    = Math.max(_textH, _badgeH)
                var _by     = _pBaseY - _bbPoleH - _bbH
                if (_bx + _bbW < 0 || _bx > iW || _pBaseY < 0 || _by > iH) continue

                // ── Estructura metálica ───────────────────────────────────
                ctx.strokeStyle = "#666"; ctx.lineWidth = _bbPoleW
                ctx.beginPath(); ctx.moveTo(_p1x, _pBaseY); ctx.lineTo(_p1x, _pBaseY - _bbPoleH); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(_p2x, _pBaseY); ctx.lineTo(_p2x, _pBaseY - _bbPoleH); ctx.stroke()
                if (_tipo === "puente") {
                    ctx.beginPath()
                    ctx.moveTo(_p1x, _pBaseY - _bbPoleH)
                    ctx.lineTo(_p2x, _pBaseY - _bbPoleH)
                    ctx.stroke()
                }

                // ── Panel ─────────────────────────────────────────────────
                ctx.beginPath()
                ctx.moveTo(_bx + _bbR, _by)
                ctx.lineTo(_bx + _bbW - _bbR, _by)
                ctx.arcTo(_bx + _bbW, _by,        _bx + _bbW, _by + _bbR,         _bbR)
                ctx.lineTo(_bx + _bbW, _by + _bbH - _bbR)
                ctx.arcTo(_bx + _bbW, _by + _bbH, _bx + _bbW - _bbR, _by + _bbH, _bbR)
                ctx.lineTo(_bx + _bbR, _by + _bbH)
                ctx.arcTo(_bx, _by + _bbH,        _bx, _by + _bbH - _bbR,         _bbR)
                ctx.lineTo(_bx, _by + _bbR)
                ctx.arcTo(_bx, _by,               _bx + _bbR, _by,                _bbR)
                ctx.closePath()
                ctx.fillStyle = "rgba(255,255,255,0.97)"; ctx.fill()
                ctx.strokeStyle = "#bbb"; ctx.lineWidth = 1.5; ctx.stroke()

                // ── Badge arriba-izquierda ────────────────────────────────
                if (_isNavius) {
                    var _logoCx = _bx + _bbPad + _logoR
                    var _logoCy = _by + _bbPad + _logoR
                    ctx.shadowColor = "transparent"; ctx.shadowBlur = 0
                    ctx.beginPath(); ctx.arc(_logoCx, _logoCy, _logoR, 0, Math.PI * 2)
                    ctx.fillStyle = "#1565C0"; ctx.fill()
                    ctx.fillStyle = "white"
                    ctx.font = "bold " + Math.round(_logoR * 1.2) + "px sans-serif"
                    ctx.textAlign = "center"; ctx.textBaseline = "middle"
                    ctx.fillText("N", _logoCx, _logoCy)
                }

                // ── Título ────────────────────────────────────────────────
                ctx.fillStyle = "#111"; ctx.font = "bold " + _bbFS + "px sans-serif"
                ctx.textAlign = "center"; ctx.textBaseline = "middle"
                ctx.shadowColor = "rgba(255,255,255,0.5)"; ctx.shadowBlur = 1
                ctx.shadowOffsetX = 0; ctx.shadowOffsetY = 0
                var _txtCx = (_txtAreaL + _txtAreaR) / 2
                var _totalTextH = _tLines.length * _bbLH + (_hasS ? _bbGap + _sLines.length * _bbLH : 0)
                var _ty = _by + (_bbH - _totalTextH) / 2 + _bbLH * 0.5
                for (var _tli = 0; _tli < _tLines.length; _tli++)
                    ctx.fillText(_tLines[_tli], _txtCx, _ty + _tli * _bbLH)

                // ── Subtítulo ─────────────────────────────────────────────
                if (_hasS) {
                    ctx.font = _bbSF + "px sans-serif"; ctx.fillStyle = "#1565C0"
                    ctx.shadowColor = "transparent"; ctx.shadowBlur = 0
                    var _sy = _ty + _tLines.length * _bbLH + _bbGap
                    for (var _sli = 0; _sli < _sLines.length; _sli++)
                        ctx.fillText(_sLines[_sli], _txtCx, _sy + _sli * _bbLH)
                }
                ctx.shadowColor = "transparent"; ctx.shadowBlur = 0
                ctx.shadowOffsetX = 0; ctx.shadowOffsetY = 0
            }
        }
    }

    // ── Marcadores de aparcamiento (overlay QML sobre el mapa) ───────────────
    Item {
        anchors.fill: mapView
        z: 2
        visible: !root._anyPanelOpen
        Repeater {
            model: root._parkingSpots
            delegate: Item {
                anchors.fill: parent
                property point _pos: root._geoToScreen(modelData.parkLat, modelData.parkLon)
                property bool _onMap: _pos.x > -units.gu(6) && _pos.x < parent.width  + units.gu(6)
                                   && _pos.y > -units.gu(6) && _pos.y < parent.height + units.gu(6)
                Rectangle {
                    visible: _onMap
                    x: _pos.x - width  / 2
                    y: _pos.y - height / 2
                    width: units.gu(5.5); height: units.gu(5.5); radius: width / 2
                    color: "#1565C0"
                    border.color: "white"; border.width: units.gu(0.25)
                    Label {
                        anchors.centerIn: parent
                        text: "P"; color: "white"
                        font.pixelSize: units.gu(2.8 * appSettings.textScale); font.bold: true
                    }
                }
            }
        }
    }

    // Altura combinada de los banners de radar activos (alerta + barra de tramo)
    property real _radarBarsHeight:
        (root._tramoAlertActive && root._navActive ? units.gu(5.5) : 0) +
        (root._fijoAlertActive  && root._navActive ? units.gu(5.5) : 0) +
        (root._activeTramo !== null && root._navActive ? units.gu(5.5) : 0) +
        (root._commAlertActive ? units.gu(5.5) : 0)

    // Margen superior dinámico: empuja los widgets debajo de la NavBar.
    // En landscape, NavBar está en el panel izquierdo → el mapa empieza desde arriba (margen mínimo).
    property real _topWidgetMargin: root._navBarScreenHeight + units.gu(1)
                                    + (root._navActive ? root._radarBarsHeight : 0)


    // ── Señal de límite de velocidad (encima de la barra de escala) ──────────
    Item {
        id: speedLimitSign
        visible: root._navActive && !root._navPaused && !prefsPanel.visible && !satPanel.visible && !searchPanel.visible
                 && (root._commSpeedLimit > 0 || root._commAlertActive || root._radarAlert || appSettings.showRoadSpeedLimit)
        anchors { left: root._isLandscape ? landscapePanel.right : parent.left
                  leftMargin: units.gu(1.5)
                  bottom: simSpeedCorrectionBar.top; bottomMargin: units.gu(0.5) }
        width: units.gu(8); height: units.gu(8)
        z: 15

        // _alert: velocidad supera el límite efectivo (usa lógica unificada de NavBar)
        property bool _alert: root._navActive && appSettings.speedAlertEnabled
                              && navBar._effLimit > 0
                              && activeModel.pos_speed_kmh > navBar._effLimit * (1.0 + appSettings.speedAlertPct / 100.0)
        property bool _blinkOn: true

        SequentialAnimation {
            running: speedLimitSign._alert
            loops: Animation.Infinite
            onRunningChanged: if (!running) speedLimitSign._blinkOn = true
            ScriptAction { script: speedLimitSign._blinkOn = false }
            PauseAnimation { duration: 400 }
            ScriptAction { script: speedLimitSign._blinkOn = true }
            PauseAnimation { duration: 700 }
        }

        // Delega en NavBar: _effLimit y _effVerified son la fuente única de verdad
        property int  _effLimit:    navBar._effLimit
        property bool _commActive:  root._commSpeedLimit > 0
        property bool _verified:    navBar._effVerified

        // Sin dato: muy atenuado. Estimado: semitransparente. Verificado/comunitario: pleno
        opacity: _effLimit <= 0     ? 0.30
               : !_verified         ? (_blinkOn ? 0.60 : 0.15)
               :                      (_blinkOn ? 1.00 : 0.15)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "white"
            border.color: speedLimitSign._effLimit > 0 && !speedLimitSign._verified && !speedLimitSign._commActive ? "#FF6F00"
                        : "#E53935"
            border.width: units.gu(0.75)

            Label {
                anchors.centerIn: parent
                text: speedLimitSign._effLimit > 0 && speedLimitSign._verified
                      ? speedLimitSign._effLimit
                      : speedLimitSign._effLimit > 0 ? (speedLimitSign._effLimit + "?") : "?"
                color: "#1A1A1A"; font.bold: true
                font.pixelSize: speedLimitSign._verified
                                ? (speedLimitSign._effLimit >= 100 ? units.gu(2.2) : units.gu(2.8))
                                : (speedLimitSign._effLimit >= 100 ? units.gu(1.8) : units.gu(2.2))
            }
        }

        Item {
            visible: speedLimitSign._alert && speedLimitSign._blinkOn
            anchors { right: parent.right; top: parent.top
                      rightMargin: -units.gu(1.2); topMargin: -units.gu(1.2) }
            width: units.gu(4); height: units.gu(4)

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: speedLimitSign._commActive ? "#1565C3"
                     : speedLimitSign._verified   ? "#E53935" : "#FF6F00"
            }
            Label {
                anchors.centerIn: parent
                text: "!"
                color: "white"
                font.pixelSize: units.gu(2.6 * appSettings.textScale)
                font.bold: true
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: commLimitPicker.open()
        }
    }

    // ── Debug: origen del límite de velocidad ────────────────────────────────
    Rectangle {
        visible: appSettings.showSlDebug && root._navActive && navBar._speedLimit > 0
        anchors { horizontalCenter: speedLimitSign.horizontalCenter
                  top: speedLimitSign.bottom; topMargin: units.gu(0.3) }
        width:  srcLabel.implicitWidth + units.gu(1.0)
        height: srcLabel.implicitHeight + units.gu(0.4)
        radius: units.gu(0.3)
        color:  "#CC000000"
        z:      speedLimitSign.z
        Label {
            id: srcLabel
            anchors.centerIn: parent
            text: navBar._speedLimitSrc || "?"
            color: navBar._speedLimitVerified ? "#4CAF50" : "#FF9800"
            font.pixelSize: units.gu(1.1 * appSettings.textScale)
            font.family: "Monospace"
        }
    }

    // ── Info bar sim: heading + velocidad (encima del vehículo) ────────────────
    Item {
        id: simVehicleInfo
        visible: appSettings.tracesEnabled && appSettings.simMode && root._driveCtrlActive
                 && !prefsPanel.visible && !satPanel.visible
        x: Math.max(units.gu(0.5),
           Math.min(parent.width - width - units.gu(0.5), posOverlayRoot._cx - width / 2))
        y: Math.max(root._topWidgetMargin,
           posOverlayRoot._cy - units.gu(2.8) - height - units.gu(0.5))
        width: units.gu(22); height: units.gu(5.5)
        z: 11

        Rectangle {
            anchors.fill: parent; radius: units.gu(0.5)
            color: "#CC07111E"; border.color: "#29B6F6"; border.width: units.gu(0.1)

            Row {
                anchors { left: parent.left; right: parent.right
                          verticalCenter: parent.verticalCenter
                          leftMargin: units.gu(1); rightMargin: units.gu(1) }
                spacing: units.gu(1)

                Canvas {
                    id: simInfoCompass
                    width: units.gu(4); height: units.gu(4)
                    anchors.verticalCenter: parent.verticalCenter
                    property real headRad: gpsSource._headRad
                    onHeadRadChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        var cx = width/2, cy = height/2, r = width/2 - 2
                        ctx.strokeStyle = "#29B6F6"; ctx.lineWidth = 1.5
                        ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2*Math.PI); ctx.stroke()
                        var h = headRad - Math.PI/2
                        ctx.save(); ctx.translate(cx, cy); ctx.rotate(h)
                        ctx.fillStyle = "#29B6F6"
                        ctx.beginPath()
                        ctx.moveTo(0, -r+2); ctx.lineTo(r*0.35, r*0.45)
                        ctx.lineTo(0, r*0.2); ctx.lineTo(-r*0.35, r*0.45)
                        ctx.closePath(); ctx.fill()
                        ctx.restore()
                        ctx.fillStyle = "#FF5252"
                        ctx.beginPath(); ctx.arc(cx, cy - r + 4, 2.5, 0, 2*Math.PI); ctx.fill()
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 0
                    Label {
                        text: { var d = Math.round(gpsSource._headRad * 180 / Math.PI)
                                return (d < 0 ? d + 360 : d) + "°" }
                        color: "#29B6F6"; font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
                    }
                    Label { text: i18n.tr("Rumbo"); color: "#90A4AE"; font.pixelSize: units.gu(1.1 * appSettings.textScale) }
                }

                Rectangle {
                    width: units.gu(0.1); height: units.gu(3.5); color: "#30FFFFFF"
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 0
                    Label {
                        text: (root._driveCtrlActive
                               ? Math.abs(gpsSource._driveSpeedMs * 3.6)
                               : gpsSource.realSpeedKmh).toFixed(1)
                        color: gpsSource._driveSpeedMs < -0.1 ? "#FF7043" : "white"
                        font.pixelSize: units.gu(2.2 * appSettings.textScale); font.bold: true
                    }
                    Label {
                        text: gpsSource._driveSpeedMs < -0.1 ? i18n.tr("km/h ◄") : i18n.tr("km/h")
                        color: "#90A4AE"; font.pixelSize: units.gu(1.1 * appSettings.textScale)
                    }
                }
            }
        }
    }

    // ── Selector de velocidad sim + botón control manual (columna bottom-left) ──
    Column {
        id: simBiasGroup
        visible: appSettings.debugMode && appSettings.simMode && !prefsPanel.visible && !satPanel.visible
                 && !searchPanel.visible && !routeSelectPanel.visible && !routeViewPanel.visible
        // Sin límite de velocidad: ancla a la izquierda del área de mapa (misma posición que la señal).
        // Con límite de velocidad: a la derecha de la señal para no solapar.
        anchors { left:         root._isLandscape
                                ? landscapePanel.right
                                : (speedLimitSign.visible ? speedLimitSign.right : parent.left)
                  leftMargin:   units.gu(0.5)
                  bottom:       mapBottomAnchor.bottom
                  bottomMargin: units.gu(0.5) }
        width: units.gu(7); spacing: units.gu(0.25)
        z: 11

        // ── Botón fallo GPS ──────────────────────────────────────────────────
        Rectangle {
            id: gpsFailBtn
            visible: appSettings.debugMode && appSettings.simMode
            width: parent.width; height: visible ? units.gu(5) : 0
            radius: units.gu(0.5)
            opacity: appSettings.gpsFailEnabled ? 1.0 : 0.35
            color:  appSettings.gpsFailEnabled ? "#BB1565C0" : "#CC1A2A3A"
            border.color: "#29B6F6"; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(0.4)
                Label { text: "📡"; font.pixelSize: units.gu(1.8 * appSettings.textScale)
                        anchors.verticalCenter: parent.verticalCenter }
                BtnLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: appSettings.gpsFailEnabled ? i18n.tr("Fallo GPS ON") : i18n.tr("Fallo GPS")
                    fontSize: units.gu(1.1); bold: appSettings.gpsFailEnabled
                    mainColor: appSettings.gpsFailEnabled ? "white" : "#29B6F6"
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: appSettings.gpsFailEnabled
                onClicked: appSettings.gpsFailEnabled = false
            }
        }

        // ── Botón dirección inversa ───────────────────────────────────────────
        Rectangle {
            id: revDirBtn
            visible: !root._driveCtrlActive && root._navActive
                     && gpsSource.routeShape !== null
            width: parent.width; height: visible ? units.gu(5) : 0
            radius: units.gu(0.5)
            color:  "#CC1A2A3A"
            border.color: "#FF7043"; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(0.4)
                Label { text: "↩"; font.pixelSize: units.gu(2.0 * appSettings.textScale)
                        anchors.verticalCenter: parent.verticalCenter }
                BtnLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: i18n.tr("Rev.")
                    fontSize: units.gu(1.1)
                    mainColor: "#FF7043"
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: gpsSource.flipHeading()
            }
        }

        // ── Selector de velocidad de simulación ───────────────────────────────
        Item {
            id: simBiasControl
            visible: !root._driveCtrlActive
            width: parent.width; height: visible ? units.gu(17.5) : 0
            clip: true

            property var _presets: [0, 1, 5, 10, 15, 20, 30, 50, 100, 500]
            function _nextPreset() {
                var p = _presets
                for (var i = 0; i < p.length; i++)
                    if (p[i] > root.simSpeedBias) { root.simSpeedBias = p[i]; return }
                root.simSpeedBias = p[p.length - 1]
            }
            function _prevPreset() {
                var p = _presets
                for (var i = p.length - 1; i >= 0; i--)
                    if (p[i] < root.simSpeedBias) { root.simSpeedBias = p[i]; return }
                root.simSpeedBias = p[0]
            }

            Column {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                spacing: units.gu(0.25)

                Rectangle {
                    width: parent.width; height: units.gu(5.5); radius: units.gu(0.5)
                    color: root.simSpeedBias >= 500 ? "#33FFFFFF" : "#CC1A2A1A"
                    border.color: "#00E676"; border.width: units.gu(0.15)
                    Label {
                        anchors.centerIn: parent; text: "▲"
                        color: root.simSpeedBias >= 500 ? "#336600" : "#00E676"
                        font.pixelSize: units.gu(1.6 * appSettings.textScale)
                    }
                    MouseArea { anchors.fill: parent; onClicked: simBiasControl._nextPreset() }
                }

                Rectangle {
                    width: parent.width; height: units.gu(5.5); radius: units.gu(0.5)
                    color: "#CC12122A"
                    border.color: root.simSpeedBias === 0 ? "#546E7A" : "#00E676"
                    border.width: units.gu(0.15)
                    Label {
                        anchors.centerIn: parent
                        text: (root.simSpeedBias > 0 ? "+" : "") + root.simSpeedBias + "%"
                        color: root.simSpeedBias === 0 ? "#546E7A" : "#00E676"
                        font.pixelSize: units.gu(1.3 * appSettings.textScale); font.bold: root.simSpeedBias !== 0
                    }
                }

                Rectangle {
                    width: parent.width; height: units.gu(5.5); radius: units.gu(0.5)
                    color: root.simSpeedBias <= 0 ? "#33FFFFFF" : "#CC2A1A1A"
                    border.color: "#FF7043"; border.width: units.gu(0.15)
                    Label {
                        anchors.centerIn: parent; text: "▼"
                        color: root.simSpeedBias <= 0 ? "#663300" : "#FF7043"
                        font.pixelSize: units.gu(1.6 * appSettings.textScale)
                    }
                    MouseArea { anchors.fill: parent; onClicked: simBiasControl._prevPreset() }
                }
            }
        }

        // ── Botón activar control manual ──────────────────────────────────────
        Rectangle {
            id: driveCtrlToggleBtn
            width: parent.width; height: units.gu(5); radius: units.gu(0.5)
            color: root._driveCtrlActive ? "#B329B6F6" : "#CC1A2A3A"
            border.color: root._driveCtrlActive ? "#29B6F6" : "#546E7A"
            border.width: units.gu(0.15)

            Row {
                anchors.centerIn: parent; spacing: units.gu(0.4)
                Label { text: "🚗"; font.pixelSize: units.gu(2.0 * appSettings.textScale)
                        anchors.verticalCenter: parent.verticalCenter }
                BtnLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._driveCtrlActive ? i18n.tr("Ctrl ON") : i18n.tr("Ctrl")
                    fontSize: units.gu(1.1); bold: root._driveCtrlActive
                    mainColor: root._driveCtrlActive ? "#29B6F6" : "#90A4AE"
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root._driveCtrlActive = !root._driveCtrlActive
                    gpsSource.manualDriveMode = root._driveCtrlActive
                    gpsSource.driveAccel     = false
                    gpsSource.driveBrake     = false
                    gpsSource.driveTurnLeft  = false
                    gpsSource.driveTurnRight = false
                    if (root._driveCtrlActive) {
                        // Iniciar control remoto a la velocidad actual de la simulación
                        gpsSource._driveSpeedMs = gpsSource._speedMs
                    } else {
                        gpsSource._driveSpeedMs = 0
                        gpsSource._speedMs      = 0
                        gpsSource._accelMss     = 0
                        gpsSource.realSpeedKmh  = 0
                    }
                }
            }
        }
    }

    // ── Panel debug: funciones de suavizado GPS ───────────────────────────────
    Column {
        id: gpsSmoothPanel
        visible: appSettings.debugMode && appSettings.showGpsSmoothDebug
                 && !prefsPanel.visible && !satPanel.visible
                 && !searchPanel.visible && !routeSelectPanel.visible && !routeViewPanel.visible
        anchors {
            left:         simBiasGroup.visible ? simBiasGroup.right : (root._isLandscape ? landscapePanel.right : parent.left)
            leftMargin:   units.gu(0.5)
            bottom:       mapBottomAnchor.bottom
            bottomMargin: units.gu(0.5)
        }
        width: units.gu(9); spacing: units.gu(0.3); z: 11

        property bool _hasRoute: gpsSource.routeShape !== null
                                  && gpsSource.routeShape.length > 1

        // ── Con ruta ────────────────────────────────────────────────────
        Label {
            visible: gpsSmoothPanel._hasRoute
            text: i18n.tr("Con ruta")
            color: "#90A4AE"; font.pixelSize: units.gu(1.2 * appSettings.textScale)
            font.bold: true
        }

        // Modo posición: toggles acumulativos
        Repeater {
            model: [
                {label: "Ideal",    prop: "interpUseIdeal",   color: "#29B6F6"},
                {label: "Accel",    prop: "interpUseAccel",   color: "#00E676"},
                {label: "VH Ratio", prop: "interpUseVhRatio", color: "#CE93D8"}
            ]
            Rectangle {
                visible: gpsSmoothPanel._hasRoute
                width: gpsSmoothPanel.width; height: units.gu(3.5); radius: units.gu(0.5)
                property bool _on: gpsSource[modelData.prop]
                color:        _on ? "#CC1A3A1A" : "#CC12122A"
                border.color: _on ? modelData.color : "#546E7A"
                border.width: units.gu(0.15)
                Label {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent._on ? modelData.color : "#78909C"
                    font.pixelSize: units.gu(1.2 * appSettings.textScale)
                    font.bold: parent._on
                }
                MouseArea { anchors.fill: parent; onClicked: gpsSource[modelData.prop] = !gpsSource[modelData.prop] }
            }
        }

        // Heading: blend en vértices
        Rectangle {
            visible: gpsSmoothPanel._hasRoute
            width: gpsSmoothPanel.width; height: units.gu(3.5); radius: units.gu(0.5)
            color:        gpsSource.interpUseHeadingBlend ? "#CC1A2A3A" : "#CC12122A"
            border.color: gpsSource.interpUseHeadingBlend ? "#FFB300" : "#546E7A"
            border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: i18n.tr("Hdg blend")
                color: gpsSource.interpUseHeadingBlend ? "#FFB300" : "#78909C"
                font.pixelSize: units.gu(1.2 * appSettings.textScale)
                font.bold: gpsSource.interpUseHeadingBlend
            }
            MouseArea { anchors.fill: parent; onClicked: gpsSource.interpUseHeadingBlend = !gpsSource.interpUseHeadingBlend }
        }

        // ── Sin ruta ────────────────────────────────────────────────────
        Label {
            visible: !gpsSmoothPanel._hasRoute
            text: i18n.tr("Sin ruta")
            color: "#90A4AE"; font.pixelSize: units.gu(1.2 * appSettings.textScale)
            font.bold: true
        }

        // Heading: aceleración
        Rectangle {
            visible: !gpsSmoothPanel._hasRoute
            width: gpsSmoothPanel.width; height: units.gu(3.5); radius: units.gu(0.5)
            color:        gpsSource.interpUseAccelHeading ? "#CC1A2A3A" : "#CC12122A"
            border.color: gpsSource.interpUseAccelHeading ? "#FF7043" : "#546E7A"
            border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: i18n.tr("Hdg accel")
                color: gpsSource.interpUseAccelHeading ? "#FF7043" : "#78909C"
                font.pixelSize: units.gu(1.2 * appSettings.textScale)
                font.bold: gpsSource.interpUseAccelHeading
            }
            MouseArea { anchors.fill: parent; onClicked: gpsSource.interpUseAccelHeading = !gpsSource.interpUseAccelHeading }
        }

        // Pos sin nav: replay ticks de ruta como conducción libre
        Rectangle {
            width: gpsSmoothPanel.width; height: units.gu(3.5); radius: units.gu(0.5)
            color:        gpsSource.simPosOnly ? "#CC2A1A2A" : "#CC12122A"
            border.color: gpsSource.simPosOnly ? "#CE93D8" : "#546E7A"
            border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: i18n.tr("Pos sin nav")
                color: gpsSource.simPosOnly ? "#CE93D8" : "#78909C"
                font.pixelSize: units.gu(1.2 * appSettings.textScale)
                font.bold: gpsSource.simPosOnly
            }
            MouseArea { anchors.fill: parent; onClicked: gpsSource.simPosOnly = !gpsSource.simPosOnly }
        }
    }

    // ── Panel debug: IMU (NavImu — cuaternión, calibración, heading) ─────────
    Column {
        id: imuDebugPanel
        visible: appSettings.debugMode && appSettings.showImuDebug
                 && !prefsPanel.visible && !satPanel.visible
                 && !searchPanel.visible && !routeSelectPanel.visible && !routeViewPanel.visible
        anchors {
            right:        parent.right
            rightMargin:  units.gu(0.5)
            bottom:       mapBottomAnchor.bottom
            bottomMargin: units.gu(0.5)
        }
        width: units.gu(13); spacing: units.gu(0.3); z: 11

        // ── Cabecera ──────────────────────────────────────────────────────
        Rectangle {
            width: parent.width; height: units.gu(3)
            radius: units.gu(0.5); color: "#DD0D1B2B"
            border.color: "#29B6F6"; border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: "🧭 IMU DEBUG"
                color: "#29B6F6"
                font.pixelSize: units.gu(1.3 * appSettings.textScale)
                font.bold: true
            }
        }

        // ── Calibración acelerómetro ──────────────────────────────────────
        Rectangle {
            width: parent.width; height: units.gu(4.5)
            radius: units.gu(0.5); color: "#CC0D1B2B"
            border.color: navImu.calibrated ? "#00E676" : "#FF7043"
            border.width: units.gu(0.15)
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: units.gu(0.6); rightMargin: units.gu(0.6) }
                spacing: units.gu(0.2)
                Label {
                    text: navImu.calibrated
                          ? "✓ Accel OK   |a|=" + navImu.accelMag.toFixed(2) + " m/s²"
                          : "⏳ Calibrando accel  " + Math.round(navImu.calibProgress * 100) + "%"
                    color: navImu.calibrated ? "#00E676" : "#FFB300"
                    font.pixelSize: units.gu(1.1 * appSettings.textScale)
                    width: parent.width; elide: Text.ElideRight
                }
                // Barra de progreso
                Rectangle {
                    visible: !navImu.calibrated
                    width: parent.width; height: units.gu(0.5); radius: units.gu(0.25)
                    color: "#1A2A3A"
                    Rectangle {
                        width: parent.width * navImu.calibProgress
                        height: parent.height; radius: parent.radius
                        color: "#FFB300"
                    }
                }
            }
        }

        // ── Calibración GPS (gyroScale / yawSign) ─────────────────────────
        Rectangle {
            width: parent.width; height: units.gu(4.5)
            radius: units.gu(0.5); color: "#CC0D1B2B"
            border.color: navImu.gpsScaleCalibrated ? "#00E676" : "#546E7A"
            border.width: units.gu(0.15)
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: units.gu(0.6); rightMargin: units.gu(0.6) }
                spacing: units.gu(0.1)
                Label {
                    text: navImu.gpsScaleCalibrated
                          ? "✓ GPS calib  " + navImu._gpsCalibN + "/" + navImu.gpsCalibTarget
                          : "· GPS calib  " + navImu._gpsCalibN + "/" + navImu.gpsCalibTarget
                    color: navImu.gpsScaleCalibrated ? "#00E676" : "#90A4AE"
                    font.pixelSize: units.gu(1.1 * appSettings.textScale)
                    width: parent.width; elide: Text.ElideRight
                }
                Label {
                    text: "scale=" + navImu.gyroScale.toFixed(5)
                          + (navImu.gyroScale > 0.5 ? "  rad/s" : "  deg→r")
                          + "  sign=" + (navImu.yawSign > 0 ? "+1" : "-1")
                    color: "#78909C"
                    font.pixelSize: units.gu(1.0 * appSettings.textScale)
                    width: parent.width; elide: Text.ElideRight
                }
            }
        }

        // ── Valores en tiempo real ────────────────────────────────────────
        Rectangle {
            width: parent.width; height: units.gu(5.5)
            radius: units.gu(0.5); color: "#CC0D1B2B"
            border.color: "#37474F"; border.width: units.gu(0.15)
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: units.gu(0.6); rightMargin: units.gu(0.6) }
                spacing: units.gu(0.15)
                Label {
                    text: "rawGz   " + navImu.rawGz.toFixed(4)
                          + (navImu.gyroScale > 0.5 ? " r/s" : " °/s")
                    color: "#CE93D8"; font.pixelSize: units.gu(1.1 * appSettings.textScale)
                    width: parent.width; elide: Text.ElideRight
                }
                Label {
                    text: "Δheading  " + (navImu.yawDeltaDeg >= 0 ? "+" : "")
                          + navImu.yawDeltaDeg.toFixed(1) + "°"
                    color: "#CE93D8"; font.pixelSize: units.gu(1.1 * appSettings.textScale)
                    width: parent.width; elide: Text.ElideRight
                }
                Label {
                    text: "heading  " + (navImu.headingRad * 180 / Math.PI).toFixed(1) + "°"
                    color: "#29B6F6"; font.pixelSize: units.gu(1.1 * appSettings.textScale)
                    width: parent.width; elide: Text.ElideRight
                }
            }
        }

        // ── Posición DR estimada (solo cuando DR activo) ──────────────────
        Rectangle {
            visible: gpsSource.drActive
            width: parent.width; height: visible ? units.gu(5) : 0
            radius: units.gu(0.5); color: "#CC1A0D0D"
            border.color: "#FF8A65"; border.width: units.gu(0.15)
            Column {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: units.gu(0.6) }
                spacing: units.gu(0.15)
                Label {
                    text: "DR lat  " + navImu.imuLat.toFixed(6)
                    color: "#FF8A65"; font.pixelSize: units.gu(1.1 * appSettings.textScale)
                    width: parent.width; elide: Text.ElideRight
                }
                Label {
                    text: "DR lon  " + navImu.imuLon.toFixed(6)
                    color: "#FF8A65"; font.pixelSize: units.gu(1.1 * appSettings.textScale)
                    width: parent.width; elide: Text.ElideRight
                }
            }
        }

        // ── Botón reset calibración GPS ───────────────────────────────────
        Rectangle {
            width: parent.width; height: units.gu(3.5)
            radius: units.gu(0.5); color: "#CC1A1A2A"
            border.color: "#546E7A"; border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: "↺  Reset calib GPS"
                color: "#90A4AE"
                font.pixelSize: units.gu(1.1 * appSettings.textScale)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { navImu.resetGpsCalib(); console.log("[debug] IMU GPS calib reset") }
            }
        }
    }

    // ── Panel de control manual del vehículo ─────────────────────────────────
    Item {
        id: driveCtrlPanel
        visible: root._driveCtrlActive && appSettings.simMode && appSettings.tracesEnabled
                 && !prefsPanel.visible && !satPanel.visible
                 && !searchPanel.visible && !routeSelectPanel.visible && !routeViewPanel.visible
        x: Math.max(units.gu(0.5),
           Math.min(parent.width - width - units.gu(0.5), posOverlayRoot._cx - width / 2))
        y: posOverlayRoot._cy + units.gu(3.2)
        width: units.gu(26); z: 11

        // D-pad de control
        Item {
            id: driveDpad
            anchors { left: parent.left; right: parent.right
                      top: parent.top }
            height: root._navActive ? units.gu(24.5) : units.gu(17.5)

            // Función compartida: aplica/quita input al soltar
            property real _btnSz: units.gu(8)

            // ── Acelerar (arriba-centro) ───
            Rectangle {
                id: driveAccelBtn
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                width: driveDpad._btnSz; height: driveDpad._btnSz; radius: units.gu(0.5)
                color: gpsSource.driveAccel ? "#CC2E7D32" : "#CC1A2A1A"
                border.color: "#00E676"; border.width: units.gu(0.15)
                Label { anchors.centerIn: parent; text: "▲"
                        color: "#00E676"; font.pixelSize: units.gu(3.5 * appSettings.textScale) }
                MouseArea {
                    anchors.fill: parent
                    onPressed:  gpsSource.driveAccel = true
                    onReleased: gpsSource.driveAccel = false
                    onCanceled: gpsSource.driveAccel = false
                }
            }

            // ── Giro izquierda (medio-izquierda) ───
            Rectangle {
                anchors { left: parent.left; verticalCenter: driveBrakeBtn.verticalCenter }
                width: driveDpad._btnSz; height: driveDpad._btnSz; radius: units.gu(0.5)
                color: gpsSource.driveTurnLeft ? "#CC1A2A4A" : "#CC0D1220"
                border.color: "#29B6F6"; border.width: units.gu(0.15)
                Label { anchors.centerIn: parent; text: "◄"
                        color: "#29B6F6"; font.pixelSize: units.gu(3.5 * appSettings.textScale) }
                MouseArea {
                    anchors.fill: parent
                    onPressed:  gpsSource.driveTurnLeft = true
                    onReleased: gpsSource.driveTurnLeft = false
                    onCanceled: gpsSource.driveTurnLeft = false
                }
            }

            // ── Freno/marcha atrás (abajo-centro) ───
            Rectangle {
                id: driveBrakeBtn
                anchors { horizontalCenter: parent.horizontalCenter
                          top: driveAccelBtn.bottom; topMargin: units.gu(0.5) }
                width: driveDpad._btnSz; height: driveDpad._btnSz; radius: units.gu(0.5)
                color: gpsSource.driveBrake ? "#CC8B1A00" : "#CC2A1A1A"
                border.color: "#FF7043"; border.width: units.gu(0.15)
                Label { anchors.centerIn: parent; text: "▼"
                        color: "#FF7043"; font.pixelSize: units.gu(3.5 * appSettings.textScale) }
                MouseArea {
                    anchors.fill: parent
                    onPressed:  gpsSource.driveBrake = true
                    onReleased: gpsSource.driveBrake = false
                    onCanceled: gpsSource.driveBrake = false
                }
            }

            // ── Giro derecha (medio-derecha) ───
            Rectangle {
                anchors { right: parent.right; verticalCenter: driveBrakeBtn.verticalCenter }
                width: driveDpad._btnSz; height: driveDpad._btnSz; radius: units.gu(0.5)
                color: gpsSource.driveTurnRight ? "#CC1A2A4A" : "#CC0D1220"
                border.color: "#29B6F6"; border.width: units.gu(0.15)
                Label { anchors.centerIn: parent; text: "►"
                        color: "#29B6F6"; font.pixelSize: units.gu(3.5 * appSettings.textScale) }
                MouseArea {
                    anchors.fill: parent
                    onPressed:  gpsSource.driveTurnRight = true
                    onReleased: gpsSource.driveTurnRight = false
                    onCanceled: gpsSource.driveTurnRight = false
                }
            }

            // ── Seguir ruta (solo con navegación activa) ───
            Rectangle {
                visible: root._navActive
                anchors { horizontalCenter: parent.horizontalCenter
                          top: driveBrakeBtn.bottom; topMargin: units.gu(0.5) }
                width: driveDpad._btnSz * 2 + units.gu(1); height: units.gu(6.5)
                radius: units.gu(0.5)
                color: "#CC1A1A2E"; border.color: "#9C27B0"; border.width: units.gu(0.15)
                Row {
                    anchors.centerIn: parent; spacing: units.gu(0.8)
                    Label { anchors.verticalCenter: parent.verticalCenter
                            text: "⟐"; color: "#CE93D8"; font.pixelSize: units.gu(2.8 * appSettings.textScale) }
                    Label { anchors.verticalCenter: parent.verticalCenter
                            text: i18n.tr("Seguir ruta")
                            color: "#CE93D8"; font.pixelSize: units.gu(1.8 * appSettings.textScale); font.bold: true }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: gpsSource.snapToRoute()
                }
            }
        }

        height: driveDpad.height
    }

    // ── Simulation badge (top-center, only when simMode is on) ────────────
    Rectangle {
        visible: appSettings.simMode
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top
                  topMargin: root._topWidgetMargin }
        Behavior on anchors.topMargin { NumberAnimation { duration: 200 } }
        height: units.gu(2.8); width: simBadgeLabel.width + units.gu(3)
        radius: height / 2
        color: "#CC7B1FA3"
        border.color: "#CE93D8"; border.width: units.gu(0.15)

        Label {
            id: simBadgeLabel
            anchors.centerIn: parent
            text:  i18n.tr("SIMULACIÓN GPS")
            color: "white"; font.pixelSize: units.gu(1.3 * appSettings.textScale); font.bold: true
        }
    }

    // ── Debug overlay: límites de velocidad por tramo ────────────────────────
    Rectangle {
        id: slDebugOverlay
        visible: appSettings.showSlDebug && root._navActive && root._navData !== null
                 && !prefsPanel.visible && !searchPanel.visible && !satPanel.visible
                 && !routeSelectPanel.visible && !routeViewPanel.visible
        anchors { horizontalCenter: parent.horizontalCenter
                  top: parent.top
                  topMargin: root._topWidgetMargin + units.gu(3.5) }
        width:  Math.min(parent.width * 0.92, units.gu(55))
        height: Math.min(slDebugFlick.contentHeight + units.gu(2.8), units.gu(22))
        radius: units.gu(0.5)
        color:  "#E0000000"
        border.color: "#444"; border.width: 1
        z: 14

        // Cabecera: servidor activo
        Rectangle {
            id: slDebugHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(2.5); radius: units.gu(0.5)
            color: root._osmScoutActive ? "#CC1B5E20" : "#CC1A1A2E"
            Label {
                anchors { left: parent.left; leftMargin: units.gu(0.8); verticalCenter: parent.verticalCenter }
                text: root._osmScoutActive ? i18n.tr("OSM Scout Server  ·  límites de velocidad por tramo")
                                           : "Valhalla: " + NavSearch.valhallaHost() + "  ·  límites por tramo"
                color: root._osmScoutActive ? "#69F0AE" : "#90CAF9"
                font.pixelSize: units.gu(1.1 * appSettings.textScale); font.bold: true; font.family: "Monospace"
            }
        }

        Flickable {
            id: slDebugFlick
            anchors { top: slDebugHeader.bottom; left: parent.left; right: parent.right
                      bottom: parent.bottom; margins: units.gu(0.4) }
            contentHeight: slDebugBody.implicitHeight
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Text {
                id: slDebugBody
                width: slDebugFlick.width
                text: root._slDebugText
                color: "white"
                font.pixelSize: units.gu(1.15 * appSettings.textScale)
                font.family: "Monospace"
                wrapMode: Text.NoWrap
                onTextChanged: {
                    var n = root._navData ? root._navData.maneuvers.length : 1
                    var lineH = implicitHeight / Math.max(1, n)
                    var targetY = navBar._step * lineH - slDebugFlick.height / 2
                    slDebugFlick.contentY = Math.max(0, Math.min(targetY, slDebugFlick.contentHeight - slDebugFlick.height))
                }
            }
        }
    }

    // ── REC badge (top-center, below sim badge, only when GPS recording active) ──
    Rectangle {
        id: recBadge
        visible: navTracker.recording
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top
                  topMargin: root._topWidgetMargin + (appSettings.simMode ? units.gu(3.5) : 0) }
        height: units.gu(2.8); width: recBadgeLabel.width + units.gu(3)
        radius: height / 2
        color: "#CCB71C1C"
        border.color: "#EF5350"; border.width: units.gu(0.15)

        SequentialAnimation on opacity {
            running: navTracker.recording
            loops: Animation.Infinite
            NumberAnimation { to: 0.5; duration: 600 }
            NumberAnimation { to: 1.0; duration: 600 }
        }

        Label {
            id: recBadgeLabel
            anchors.centerIn: parent
            text: "REC · " + navTracker.get_point_count() + " pt"
            color: "white"; font.pixelSize: units.gu(1.3 * appSettings.textScale); font.bold: true
        }
        Timer {
            interval: 5000; repeat: true; running: navTracker.recording
            onTriggered: recBadgeLabel.text = "REC · " + navTracker.get_point_count() + " pt"
        }
    }

    // ── Sim route scrubber (vertical, left of zoom slider, only when simMode on) ──
    Item {
        id: simScrubber
        visible: appSettings.debugMode && appSettings.simMode && appSettings.showSimScrubber && !satPanel.visible
        anchors {
            right:  parent.right
            top:    root._isLandscape ? parent.top : adPanel.bottom
            bottom: statusBar.top
        }
        width: units.gu(3)

        Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.color: "#60FFFFFF"; border.width: units.gu(0.1) }

        Rectangle {
            id: ssTrack
            anchors { horizontalCenter: parent.horizontalCenter
                      top: parent.top; topMargin: units.gu(1.75)
                      bottom: parent.bottom; bottomMargin: units.gu(1.75) }
            width: units.gu(0.4); radius: width / 2
            color: "#50CE93D8"
        }

        Label {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
            text: "▶"; color: "#CE93D8"; opacity: 0.6; font.pixelSize: units.gu(1.4 * appSettings.textScale)
        }
        Label {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            text: "●"; color: "#CE93D8"; opacity: 0.6; font.pixelSize: units.gu(1.0 * appSettings.textScale)
        }

        Rectangle {
            id: ssHandle
            width: units.gu(3.5); height: units.gu(3.5); radius: width / 2
            color: "#CC1A0A2E"
            border.color: "#CE93D8"; border.width: units.gu(0.15)
            anchors.horizontalCenter: parent.horizontalCenter

            property bool _dragging: false
            property real frac: gpsSource.simRoute && gpsSource.simRoute.length > 1
                                 ? gpsSource.simIdx / (gpsSource.simRoute.length - 1) : 0
            property real targetY: (1.0 - frac) * ssTrack.height + ssTrack.y - height / 2 + units.gu(1.75)
            y: _dragging ? y : targetY

            MouseArea {
                anchors.fill: parent
                onPressed:  { ssHandle._dragging = true;  root.simPaused = true }
                onReleased: { ssHandle._dragging = false; root.simPaused = false }
                onPositionChanged: {
                    if (!pressed) return
                    var cy   = ssHandle.y + ssHandle.height / 2 - ssTrack.y - units.gu(1.75)
                    var frac = 1.0 - Math.max(0, Math.min(cy, ssTrack.height)) / ssTrack.height
                    var n    = gpsSource.simRoute ? gpsSource.simRoute.length : 0
                    var idx  = Math.round(frac * (n - 1))
                    idx = Math.max(0, Math.min(idx, n - 1))
                    gpsSource.seekTo(idx)
                    if (root._navActive && !root._navPaused) navBar.handleTick(true, Date.now())
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            function seek(my) {
                var cy   = my - ssTrack.y - units.gu(1.75)
                var frac = 1.0 - Math.max(0, Math.min(cy, ssTrack.height)) / ssTrack.height
                var n    = gpsSource.simRoute ? gpsSource.simRoute.length : 0
                var idx  = Math.round(frac * (n - 1))
                idx = Math.max(0, Math.min(idx, n - 1))
                gpsSource.seekTo(idx)
                if (root._navActive) navBar.handleTick(true, Date.now())
            }
            onPressed:         { root.simPaused = true;  seek(mouse.y) }
            onReleased:        root.simPaused = false
            onPositionChanged: seek(mouse.y)
        }

    }


    // ── Re-center crosshair (bottom-center del mapa) ─────────────────────
    Item {
        visible: !mapView.followMode && !root._menuOpen
        anchors { bottom: mapBottomAnchor.bottom; bottomMargin: units.gu(9) }
        x: root._isLandscape
           ? landscapePanel.width + (parent.width - landscapePanel.width) / 2 - width / 2
           : parent.width / 2 - width / 2
        width: units.gu(9); height: units.gu(9)

        Rectangle {
            anchors.fill: parent; radius: width / 2
            color: "transparent"
            border.color: root._uiBorder; border.width: units.gu(0.15)
        }
        Rectangle {
            anchors.centerIn: parent
            width: units.gu(1); height: units.gu(1)
            radius: width / 2; color: root._uiFg
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.55; height: units.gu(0.15)
            color: root._uiFg
        }
        Rectangle {
            anchors.centerIn: parent
            width: units.gu(0.15); height: parent.height * 0.55
            color: root._uiFg
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                mapView.followMode = true
                var lat, lon
                if (!isNaN(mapView._lastLat) && !isNaN(mapView._lastLon) && mapView._hasPos) {
                    lat = mapView._lastLat; lon = mapView._lastLon
                } else if (appSettings.hasLastPos) {
                    lat = appSettings.lastLat; lon = appSettings.lastLon
                }
                if (lat !== undefined) {
                    mapView._gpsUpdating = true
                    mapView.center = QtPositioning.coordinate(lat, lon)
                    mapView._gpsUpdating = false
                }
            }
        }
    }

    // ── Compass widget: brújula minimalista + ciclo N+2D / Giro+3D / Giro+2D ──
    CompassWidget {
        id: compassWidget
        z: 4
        visible: !root._menuOpen && !satPanel.visible && !prefsPanel.visible
        anchors { right: parent.right; rightMargin: units.gu(2.5) + root._scrubOff
                  bottom: mapBottomAnchor.bottom; bottomMargin: units.gu(0.5) }
        bearing:     mapView.bearing
        nightMode:   mapView._nightMode
        bearingMode: appSettings.bearingMode
        hasArrow:    root._hasArrow
        dispHeadRad: root._dispHeadRad
        is3d:        (root._navActive ? appSettings.navMapMode : appSettings.mapMode) === "3d"
        fgColor:      root._uiFg
        borderColor:  root._uiBorder
        onCycleRequested: {
            var curBearing = appSettings.bearingMode
            var curMode    = root._navActive ? appSettings.navMapMode : appSettings.mapMode
            var newMapMode, newBearing

            if (curBearing === "north") {
                // N+2D → Giro+3D
                newBearing = "heading"; newMapMode = "3d"
            } else if (curMode === "3d") {
                // Giro+3D → Giro+2D
                newBearing = "heading"; newMapMode = "2d"
            } else {
                // Giro+2D → N+2D
                newBearing = "north"; newMapMode = "2d"
            }

            appSettings.bearingMode = newBearing
            if (root._navActive) appSettings.navMapMode = newMapMode
            else                 appSettings.mapMode    = newMapMode
            root._applyMapMode(newMapMode)

            if (newBearing === "heading") {
                mapView.followMode = true
                mapView.animateBearing(root._hasArrow ? root._dispHeadRad * 180 / Math.PI : 0)
            } else {
                mapView.animateBearing(0)
            }
        }
    }

    // ── Grupo de botones del mapa: Flow portrait=vertical / landscape=horizontal ──
    Flow {
        id: mapBtnGroup
        visible: !root._menuOpen && !prefsPanel.visible && !searchPanel.visible
                 && !satPanel.visible && !routeSelectPanel.visible && !routeViewPanel.visible
        z: 15
        readonly property real _sz: root._isLandscape ? units.gu(6) : units.gu(9)
        readonly property real _sp: root._isLandscape ? units.gu(0.8) : units.gu(1)
        flow:    root._isLandscape ? Flow.LeftToRight : Flow.TopToBottom
        spacing: _sp
        width:   root._isLandscape ? landscapePanel.width - units.gu(2) : _sz
        // Anchors por defecto = portrait (top fijo)
        anchors { left: parent.left; leftMargin: units.gu(2)
                  top: parent.top;   topMargin:  root._topWidgetMargin }
        // Landscape: libera top, ancla a bottom — AnchorChanges lo hace de forma fiable
        states: State {
            name: "ls"; when: root._isLandscape
            AnchorChanges {
                target: mapBtnGroup
                anchors.top: undefined; anchors.bottom: mapBottomAnchor.bottom
            }
            PropertyChanges {
                target: mapBtnGroup
                anchors.leftMargin:   units.gu(1)
                anchors.bottomMargin: units.gu(0.5)
                anchors.topMargin:    0
            }
        }

    // ── Botón de modo de mapa (incluye Mapa 3D/2D fusionado) ─────────────
    Rectangle {
        id: mapStyleBtn
        width: mapBtnGroup._sz; height: mapBtnGroup._sz; radius: width / 2
        color: "transparent"
        border.color: root._uiBorder
        border.width: units.gu(0.15)

        readonly property var _styleMeta: ({
            "auto3d":    { icon: "🏢", label: i18n.tr("Mapa 3D")  },
            "auto":      { icon: "🗺", label: i18n.tr("Mapa")      },
            "satellite": { icon: "🛰", label: i18n.tr("Satélite")  },
            "positron":  { icon: "☀", label: i18n.tr("Claro")      },
            "bright":    { icon: "🌐", label: i18n.tr("Vivo")       },
            "fiord":     { icon: "🌊", label: "Fiord"      },
            "dark":      { icon: "🌙", label: i18n.tr("Noche")      }
        })

        property var _modes: {
            if (!mapView._navius) return ["auto3d", "auto", "satellite", "positron", "bright"]
            var extra = JSON.parse(appSettings.mapNaviusStyles)
            return ["auto3d", "auto", "satellite"].concat(extra)
        }

        property int _idx: 0

        function _urlFor(name) {
            if (name === "satellite") return mapView.satelliteStyleUrl
            if (name === "positron")  return mapView.positronUrl
            if (name === "bright")    return mapView.brightUrl
            if (name === "fiord")     return mapView.fiordUrl
            if (name === "dark")      return mapView.darkUrl
            return mapView._autoNight ? mapView.nightUrl : mapView.dayUrl
        }

        Component.onCompleted: {
            var m = appSettings.mapStyleMode
            var want3d = appSettings.show3dBuildings
            for (var i = 0; i < _modes.length; i++) {
                var n = _modes[i]
                if (n === "auto3d" && m === "auto" && want3d) { _idx = i; return }
                if (n !== "auto3d" && n === m)                { _idx = i; return }
            }
            _idx = 0
        }

        Column {
            anchors.centerIn: parent; spacing: units.gu(0.1)
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (mapStyleBtn._styleMeta[mapStyleBtn._modes[mapStyleBtn._idx]] || {}).icon || "🗺"
                font.pixelSize: units.gu(2.4 * appSettings.textScale)
            }
            BtnLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (mapStyleBtn._styleMeta[mapStyleBtn._modes[mapStyleBtn._idx]] || {}).label || ""
                fontSize: units.gu(1.3); bold: false
                mainColor: root._uiFg
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                var next = (parent._idx + 1) % parent._modes.length
                parent._idx = next
                var name     = parent._modes[next]
                var baseName = (name === "auto3d") ? "auto" : name
                var want3d   = (name === "auto3d")
                mapView._forcedStyle = baseName
                mapView.styleUrl = parent._urlFor(name)
                if (appSettings.show3dBuildings !== want3d) {
                    appSettings.show3dBuildings = want3d
                    mapView.apply3dBuildings()
                }
            }
        }
    }

    // ── Botón pausa/reanudar navegación (último en el grupo) ─────────────
    Rectangle {
        id: navPauseBtn
        visible: root._navActive && !root._driveCtrlActive
                 && !prefsPanel.visible && !searchPanel.visible && !routeViewPanel.visible
        width: mapBtnGroup._sz; height: mapBtnGroup._sz; radius: width / 2
        color: "transparent"
        border.color: root._uiBorder
        border.width: units.gu(0.15)

        Label {
            anchors.centerIn: parent
            text: root._navPaused ? "▶" : "⏸"
            color: root._uiFg
            font.pixelSize: units.gu(3.2 * appSettings.textScale)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root._navPaused = !root._navPaused
        }
    }

    } // fin mapBtnGroup

    // ── Línea separadora azul sobre botones (solo landscape) ─────────────
    Rectangle {
        id: mapBtnSeparator
        visible: root._isLandscape && mapBtnGroup.visible
        z: 14
        anchors { left: parent.left; right: landscapePanel.right
                  bottom: mapBtnGroup.top; bottomMargin: units.gu(0.2) }
        height: units.gu(0.12)
        color: "#29B6F6"; opacity: 0.55
    }

    // ── Scale bar (bottom-left, above ⚙ button) ───────────────────────────
    Item {
        id: simSpeedCorrectionBar
        z: 4                        // sobre billboards (z:3)
        property var sc: root.niceScale(mapView.metersPerPixel, mapView.pixelRatio, units.gu(12))
        visible: mapView.metersPerPixel > 0
        anchors { left: parent.left; leftMargin: units.gu(2)
                  bottom: mapBottomAnchor.bottom; bottomMargin: units.gu(0.5) }
        width:  sc.logicalPx + units.gu(0.3)
        height: units.gu(2.8)

        // Horizontal bar
        Rectangle {
            anchors { bottom: parent.bottom; bottomMargin: units.gu(0.3)
                      left: parent.left }
            width:  simSpeedCorrectionBar.sc.logicalPx; height: units.gu(0.35)
            color: mapView._nightMode ? "white" : "#666666"; opacity: 0.8
        }
        // Left end tick
        Rectangle {
            anchors { bottom: parent.bottom; bottomMargin: units.gu(0.3)
                      left: parent.left }
            width: units.gu(0.25); height: units.gu(0.9)
            color: mapView._nightMode ? "white" : "#666666"; opacity: 0.8
        }
        // Right end tick
        Rectangle {
            anchors { bottom: parent.bottom; bottomMargin: units.gu(0.3) }
            x: simSpeedCorrectionBar.sc.logicalPx - units.gu(0.25)
            width: units.gu(0.25); height: units.gu(0.9)
            color: mapView._nightMode ? "white" : "#666666"; opacity: 0.8
        }
        // Label
        Label {
            anchors { bottom: parent.bottom; bottomMargin: units.gu(1.35)
                      left: parent.left }
            text: simSpeedCorrectionBar.sc.label
            color: mapView._nightMode ? "white" : "#666666"; opacity: 0.85
            font.pixelSize: units.gu(1.4 * appSettings.textScale)
        }
    }

    // ── Zoom slider (right side, between SpeedView and bottom buttons) ─────
    Item {
        id: zoomSlider
        visible: appSettings.showZoomSlider && (!root._navActive || appSettings.debugMode) && !root._menuOpen && !satPanel.visible && !root._isLandscape
        readonly property real minZoom: 1
        readonly property real maxZoom: 20
        anchors { horizontalCenter: autoZoomBtn.horizontalCenter
                  top: soundBtn.bottom; topMargin: units.gu(1)
                  bottom: alertasBtnPortrait.top; bottomMargin: units.gu(1) }
        width: units.gu(3)

        Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.color: "#60FFFFFF"; border.width: units.gu(0.1) }

        // Track
        Rectangle {
            id: zsTrack
            anchors { horizontalCenter: parent.horizontalCenter
                      top: parent.top; topMargin: units.gu(1.75)
                      bottom: parent.bottom; bottomMargin: units.gu(1.75) }
            width: units.gu(0.4); radius: width / 2
            color: "#50FFFFFF"
        }

        // + / − labels at ends
        BtnLabel {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
            text: "+"; fontSize: units.gu(2.0); bold: true
        }
        BtnLabel {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            text: "−"; fontSize: units.gu(2.0); bold: true
        }

        // Handle — position derived from mapView.zoomLevel; drag sets zoom
        Rectangle {
            id: zsHandle
            width: units.gu(3.5); height: units.gu(3.5); radius: width / 2
            color: "#CC1E3A5F"
            border.color: "#29B6F6"; border.width: units.gu(0.15)
            anchors.horizontalCenter: parent.horizontalCenter

            property bool _dragging: false
            // frac = 0 at minZoom (bottom), 1 at maxZoom (top)
            property real frac: (Math.max(zoomSlider.minZoom, Math.min(zoomSlider.maxZoom, mapView.zoomLevel))
                                  - zoomSlider.minZoom) / (zoomSlider.maxZoom - zoomSlider.minZoom)
            // top-of-handle y when not dragging
            property real targetY: (1.0 - frac) * (zsTrack.height) + zsTrack.y - height / 2 + units.gu(1.75)
            y: _dragging ? y : targetY

            MouseArea {
                anchors.fill: parent
                onPressed:  zsHandle._dragging = true
                onReleased: zsHandle._dragging = false
                onPositionChanged: {
                    if (!pressed) return
                    // Convert handle centre y to zoom level
                    var cy   = zsHandle.y + zsHandle.height / 2 - zsTrack.y - units.gu(1.75)
                    var frac = 1.0 - Math.max(0, Math.min(cy, zsTrack.height)) / zsTrack.height
                    var z    = zoomSlider.minZoom + frac * (zoomSlider.maxZoom - zoomSlider.minZoom)
                    mapView.setZoomLevel(z, Qt.point(mapView.width / 2, mapView.height / 2))
                }
            }
        }

        // Whole-track drag (outside handle)
        MouseArea {
            anchors.fill: parent
            onPressed: {
                var cy   = mouse.y - zsTrack.y - units.gu(1.75)
                var frac = 1.0 - Math.max(0, Math.min(cy, zsTrack.height)) / zsTrack.height
                var z    = zoomSlider.minZoom + frac * (zoomSlider.maxZoom - zoomSlider.minZoom)
                mapView.setZoomLevel(z, Qt.point(mapView.width / 2, mapView.height / 2))
            }
            onPositionChanged: onPressed(mouse)
        }
    }


    // ── Botón alertas portrait (encima de auto-zoom, derecha) ────────────
    Rectangle {
        id: alertasBtnPortrait
        visible: !root._isLandscape && !root._menuOpen && !prefsPanel.visible && !searchPanel.visible && !satPanel.visible && !routeSelectPanel.visible
        anchors { right: parent.right; rightMargin: units.gu(2.5) + root._scrubOff
                  bottom: autoZoomBtn.top; bottomMargin: units.gu(0.5) }
        width: units.gu(9); height: units.gu(9); radius: width / 2
        color: "transparent"
        border.color: root._uiBorder; border.width: units.gu(0.15)
        opacity: mainAuthSettings.token !== "" ? 1.0 : 0.45
        z: 10
        Column {
            anchors.centerIn: parent; spacing: units.gu(0.1)
            Label { anchors.horizontalCenter: parent.horizontalCenter
                    text: "⚠️"; font.pixelSize: units.gu(4.2 * appSettings.textScale) }
            BtnLabel { anchors.horizontalCenter: parent.horizontalCenter
                       text: i18n.tr("Alerta"); fontSize: units.gu(2.05); bold: false; mainColor: root._uiFg }
        }
        MouseArea { anchors.fill: parent
            onClicked: mainAuthSettings.token !== "" ? alertasOverlay.open() : loginPanel.open() }
    }

    // ── Botón alertas landscape (izquierda de la brújula) ────────────────
    Rectangle {
        id: alertasBtnLandscape
        visible: root._isLandscape && !root._menuOpen && !prefsPanel.visible && !searchPanel.visible && !satPanel.visible && !routeSelectPanel.visible
        anchors { right: compassWidget.left; rightMargin: units.gu(0.5)
                  verticalCenter: compassWidget.verticalCenter }
        width: units.gu(9); height: units.gu(9); radius: width / 2
        color: "transparent"
        border.color: root._uiBorder; border.width: units.gu(0.15)
        opacity: mainAuthSettings.token !== "" ? 1.0 : 0.45
        z: 10
        Column {
            anchors.centerIn: parent; spacing: units.gu(0.1)
            Label { anchors.horizontalCenter: parent.horizontalCenter
                    text: "⚠️"; font.pixelSize: units.gu(4.2 * appSettings.textScale) }
            BtnLabel { anchors.horizontalCenter: parent.horizontalCenter
                       text: i18n.tr("Alerta"); fontSize: units.gu(2.05); bold: false; mainColor: root._uiFg }
        }
        MouseArea { anchors.fill: parent
            onClicked: mainAuthSettings.token !== "" ? alertasOverlay.open() : loginPanel.open() }
    }

    // ── Auto-zoom button (encima del botón 3D, mismo estilo) ─────────────
    Rectangle {
        id: autoZoomBtn
        visible: !appSettings.autoZoom && !root._menuOpen && !prefsPanel.visible && !searchPanel.visible && !satPanel.visible && !routeSelectPanel.visible
        anchors { right: parent.right; rightMargin: units.gu(2.5) + root._scrubOff
                  bottom: compassWidget.top; bottomMargin: units.gu(0.5) }
        width: units.gu(9); height: units.gu(9); radius: width / 2
        color: "transparent"
        border.color: root._uiBorder
        border.width: units.gu(0.15)
        z: 10

        Column {
            anchors.centerIn: parent; spacing: units.gu(0.1)
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "⊙"
                color: root._uiFg
                font.pixelSize: units.gu(3.2 * appSettings.textScale)
            }
            BtnLabel {
                anchors.horizontalCenter: parent.horizontalCenter
                text: i18n.tr("Auto")
                fontSize: units.gu(1.5); bold: false
                mainColor: root._uiFg
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: appSettings.autoZoom = !appSettings.autoZoom
        }
    }



    // Safety: if rerouting hangs (network timeout not caught, etc.), reset after 20s
    Timer {
        id: rerouteWatchdog
        interval: 20000; repeat: false
        onTriggered: {
            if (navBar._rerouting) {
                navBar._rerouting = false
                navBar._status    = "nav"
                navBar._lastRerouteMs = Date.now()
            }
        }
    }

    // ── NavBar (siempre visible, adapta contenido según modo) ─────────────
    NavBar {
        id: navBar
        z: 4                        // sobre billboards (z:3)
        visible: !satPanel.visible
        paused:            root._navPaused
        navActive:         root._navActive
        routeData:         root._navData
        gpsLat:            activeModel.pos_lat
        gpsLon:            activeModel.pos_lon
        gpsHeadRad:        root._dispHeadRad
        gpsSpeedKmh:       activeModel.pos_speed_kmh
        hasFix:            activeModel.pos_has_fix
        searchingGps:      root._searchingGps
        // En landscape: panel izquierdo 1/3. En portrait: barra superior completa.
        // La altura en landscape la fija NavBar.qml (height: parent.height).
        anchors {
            left:  parent.left
            right: root._isLandscape ? landscapePanel.right : parent.right
            top:   parent.top
        }
        isLandscape: root._isLandscape
        posAccuracy:       activeModel.pos_accuracy
        navWaypoints:      root._navDests
        speedAlertPct:     appSettings.speedAlertPct
        speedAlertEnabled: appSettings.speedAlertEnabled
        commSpeedLimit:      root._commSpeedLimit
        commAlertSpeed:      root._commAlertSpeed
        radarMaxspeed:       root._radarAlertMaxspeed
        showRoadSpeedLimit:  appSettings.showRoadSpeedLimit
        offRouteDistM:       appSettings.offRouteDistM
        imperial:            appSettings.measureSystem === "imperial"
        revMode:           root._revModeActive
        revShape:          gpsSource.revShape
        trackReplayMode:   root._trackReplayActive
        textScale:         appSettings.textScale
        onStartNavRequested: searchPanel.visible = true
        onReloadDestRequested: root._reloadDestination()
        onInstructionsRequested: instructionListPanel.visible = true
        onIntermediateArrived: function(waypointIndex) {
            // Avanzar el límite de leg en GpsSource al nuevo leg activo
            var rd = root._navData
            var newLeg = waypointIndex + 1
            gpsSource.routeShapeLegEnd = (rd && rd.legShapeEnds && newLeg < rd.legShapeEnds.length)
                                         ? rd.legShapeEnds[newLeg] : -1
            // Sincronizar tramos completados para que recálculos no reutilicen legs ya hechos
            searchPanel.completedLegs = navBar._completedLegs
            // Reanudar sim pausado en la confirmación de tramo
            if (appSettings.simMode) root.simPaused = false
            var wps = root._navDests
            if (wps && wps[waypointIndex] && wps[waypointIndex].todos && wps[waypointIndex].todos.length > 0) {
                todoArrivalBanner._wpIdx  = waypointIndex
                todoArrivalBanner._wpName = wps[waypointIndex].name || ""
                todoArrivalBanner.visible = true
            }
        }
        onLegArrivalReached: function(legIdx, isFinal) {
            var wps = root._navDests
            legArrivalBanner._legIdx  = legIdx
            legArrivalBanner._isFinal = isFinal
            legArrivalBanner._name    = (wps && wps[legIdx]) ? (wps[legIdx].name || "") : ""
            legArrivalBanner.visible  = true
            // En sim: pausar el GPS para que no avance al siguiente tramo mientras el banner está visible
            if (appSettings.simMode && !isFinal) root.simPaused = true
            // En replay: auto-aceptar si no se responde en 8 s. En conducción real, espera.
            if (root._trackReplayActive) legArrivalReplayTimer.restart()
            if (root._effInstrSound === "tts")       { navTts.beep(); navTts.say(navTts.leg_arrived_text_qt(root._ttsEffectiveLang())) }
            else if (root._effInstrSound === "beep") navTts.beep()
        }
        onAnnounce: function(distM, text, text2, instrId, annType) {
            if (root._effInstrSound === "tts") {
                var lang = root._ttsEffectiveLang()
                // Clave para parte1
                var key1 = root._ttsPregenKeys[text]
                if (key1 === undefined) {
                    key1 = navTts.pregenerate(text, lang)
                    var tmp1 = root._ttsPregenKeys; tmp1[text] = key1; root._ttsPregenKeys = tmp1
                }
                // Clave para parte2 (solo en "ya"; pre1/pre2 reciben text2 vacío)
                var key2 = ""
                if (text2) {
                    key2 = root._ttsPregenKeys[text2]
                    if (key2 === undefined) {
                        key2 = navTts.pregenerate(text2, lang)
                        var tmp2 = root._ttsPregenKeys; tmp2[text2] = key2; root._ttsPregenKeys = tmp2
                    }
                }
                // Frase corta de maniobra: fallback si caché no lista, o forzado si siguiente
                // maniobra está a < 5s (no hay tiempo para instrucción larga completa).
                var _navMan = _navData ? _navData.maneuvers : null
                var _mvAnn  = _navMan ? _navMan[instrId] : null
                var shortKey = _mvAnn ? navTts.short_maneuver_key(
                    _mvAnn.type || 0, _mvAnn.roundabout_exit_count || 0, lang) : ""
                var preferShort = false
                if (shortKey !== "" && _mvAnn && _mvAnn.length) {
                    var _spdMs = navBar.gpsSpeedKmh / 3.6
                    var _timeToNext = _spdMs > 0.5 ? (_mvAnn.length * 1000 / _spdMs) : 99999
                    preferShort = _timeToNext < 5
                }
                navTts.beep()
                navTts.play_round_then_instr(distM, key1, text, key2, text2,
                                             shortKey, preferShort, lang, navBar.imperial)
                root._pregenerateUpcoming(navBar._step)
            } else if (root._effInstrSound === "beep") {
                navTts.beep()
            }
        }
        onStopNavigation: {
            rerouteWatchdog.stop()
            try { searchPanel.saveTodosToDb(root._navDests) } catch(e) { console.error("saveTodosToDb onStop:", e) }
            root._navDests = []
            searchPanel.completedLegs = 0
            root.clearRoute()
            appSettings.wasNavigating = false
        }
        onArrived: {
            console.log("NAV ARRIVED trackReplay=" + root._trackReplayActive
                        + " step=" + navBar._step
                        + " distFromRoute=" + navBar.distFromRoute.toFixed(1))
            rerouteWatchdog.stop()
            if (appSettings.debugMode && appSettings.simMode) {
                root._traceLines += root._tsLocal()
                    + " === ARRIVED step=" + navBar._step
                    + " dist=" + navBar.distFromRoute.toFixed(1) + "m\n"
                root._flushTrace()
            }
            if (root._effInstrSound === "tts")       { navTts.beep(); navTts.say(navTts.arrived_text_qt(root._ttsEffectiveLang())) }
            else if (root._effInstrSound === "beep") navTts.beep()
            // Ofrecer guardar aparcamiento si el vehículo activo no es peatón
            var _avArr = vehicleManager.activeVehicle()
            if (_avArr && _avArr.costing !== "pedestrian") {
                parkSaveOffer.visible = true
                parkSaveOfferTimer.restart()
            }
            // Guardar destino antes de borrar la ruta
            root._lastNavDests = root._navDests.slice()
            root._lastNavOpts  = root._navOpts
            root._lastNavShape = root._navData ? root._navData.shape : null
            try { searchPanel.saveTodosToDb(root._lastNavDests) } catch(e) { console.error("saveTodosToDb onArrived:", e) }
            root._navDests = []
            searchPanel.completedLegs = 0
            root.clearRoute()
            appSettings.wasNavigating = false
            navBar.showReloadDest = root._lastNavDests.length > 0
            // Show "Abrir tareas" button if any destination has tasks
            var _atd = root._lastNavDests
            var _atdHas = false
            for (var _ati = 0; _ati < _atd.length; _ati++) {
                if (_atd[_ati].todos && _atd[_ati].todos.length > 0) { _atdHas = true; break }
            }
            if (_atdHas) {
                var _atdLast = _atd.length - 1
                todoArrivalBanner._wpIdx  = _atdLast
                todoArrivalBanner._wpName = _atd[_atdLast].name || ""
                todoArrivalBanner.visible = true
            }
        }
        onOffRoute: {
            if (appSettings.debugMode && appSettings.simMode) {
                var tsOff = root._tsLocal()
                var reLine = tsOff + " === REROUTE simIdx=" + gpsSource.simIdx
                    + " realLat=" + navBar._realLat.toFixed(6)
                    + " realLon=" + navBar._realLon.toFixed(6)
                    + " dist=" + navBar.distFromRoute.toFixed(1)
                    + " step=" + navBar._step
                    + " spd=" + activeModel.pos_speed_kmh.toFixed(1)
                    + "\n"
                root._traceLines += root._pendingTickLines + reLine
                root._pendingTickLines = ""
                root._flushTrace()
            }
            root._clearTrafficComparison()
            var _wasRev = root._revModeActive
            // En simMode usar navBar._realLat (siempre posición sim, nunca GPS hardware)
            var _rerouteLat = appSettings.simMode ? navBar._realLat : activeModel.pos_lat
            var _rerouteLon = appSettings.simMode ? navBar._realLon : activeModel.pos_lon
            var wps = [_originWp(_rerouteLat, _rerouteLon)]
            for (var i = navBar._completedLegs; i < root._navDests.length; i++) wps.push(root._navDests[i])
            if (wps.length < 2) {
                navBar._rerouting = false; navBar._status = "nav"; return
            }
            // Sin internet y sin OSM Scout local → no intentar recalcular (fallaría)
            if (root._mapOffline && !root._osmScoutActive) {
                if (!root._rerouteBeepedOffline) {
                    navTts.alert_beep()
                    root._rerouteBeepedOffline = true
                }
                navBar._rerouting = false; navBar._status = "nav"; return
            }
            rerouteWatchdog.restart()
            if (root._effAlertSound !== "off" || root._effInstrSound !== "off") navTts.reroute_beep()
            NavSearch.route(wps, root._navOpts, function(err, routes) {
                rerouteWatchdog.stop()
                if (_wasRev) { root._revModeActive = false; gpsSource.cancelRevMode() }
                navBar._rerouting = false
                navBar._lastRerouteMs = Date.now()
                if (!root._navActive) return
                if (err || !routes || routes.length === 0) {
                    navBar._status = "nav"
                    return
                }
                root.drawRoute(routes, 0)
                root._navData        = routes[0]
                gpsSource.routeShape = routes[0].shape
                gpsSource._shapeIdx  = 0
                gpsSource._shapeFrac = 0
                // En simMode: actualizar simRoute inmediatamente para que el sim no use la ruta antigua
                // (seekTo antes del callback async enrichSpeedLimits evita el salto visual de 180°)
                if (appSettings.simMode && root._navActive && root._navData) {
                    root.simRoute = root.buildSimRouteFromNavData(root._navData)
                    gpsSource.seekTo(0)
                }
                if (appSettings.debugMode && appSettings.simMode) {
                    root._traceLines += root._tsLocal()
                        + " === REROUTE_OK shape=" + routes[0].shape.length
                        + " steps=" + routes[0].maneuvers.length + "\n"
                    root._flushTrace()
                }
                mapView.followMode = true
                root._activeTramo = null; root._tramoFrac = 0
                root._radarApproachingTramo = false
                root._radarAlert = false; root._radarAlertMsg = ""; root._radarAlertMaxspeed = 0
                if (appSettings.simRouteIdx === 0 || appSettings.simRouteIdx === 4) {
                    NavSearch.fetchRadars(routes[0].shape, function(result) {
                        if (!root._navActive) return
                        root._radarFijos  = result.fijos
                        root._radarTramos = result.tramos
                        root._updateRadarLayers()
                        root._handleRadarFetchResult(result)
                    })
                }
                NavSearch.enrichSpeedLimits(routes[0].shape, routes[0].maneuvers, function(enrichedMans) {
                    if (!root._navActive || !root._navData) return
                    var origMans = root._navData.maneuvers
                    if (!origMans) return
                    for (var ri = 0; ri < enrichedMans.length && ri < origMans.length; ri++) {
                        var rsl = enrichedMans[ri].speed_limit
                        if (rsl !== undefined && rsl > 0) {
                            origMans[ri].speed_limit     = rsl
                            origMans[ri].speed_limit_src = enrichedMans[ri].speed_limit_src || ""
                            origMans[ri]._dbgSpeed       = enrichedMans[ri]._dbgSpeed  || 0
                            origMans[ri]._slOsm          = enrichedMans[ri]._slOsm     || 0
                            origMans[ri]._slVal          = enrichedMans[ri]._slVal     || 0
                            origMans[ri]._slLegal        = enrichedMans[ri]._slLegal   || 0
                            origMans[ri]._roadClass      = enrichedMans[ri].road_class || ""
                        }
                    }
                    root._propagateRoundaboutSpeeds(origMans)
                    root._slDebugTick++; root._writeSlDebugFile()
                    // Actualizar simRoute con límites de velocidad reales; sin seekTo (sim ya corre desde idx=0)
                    if (appSettings.simMode && root._navActive && root._navData) {
                        root.simRoute = root.buildSimRouteFromNavData(root._navData)
                    }
                })
            })
        }
    }

    // ── AdPanel: panel de anuncio de proximidad ───────────────────────────────
    Timer {
        id: adPanelTimer
        interval: 12000
        onTriggered: root._adPanelBb = null
    }

    Rectangle {
        id: adPanel
        anchors { left: parent.left; right: parent.right; top: navBar.bottom }
        height: (root._adPanelBb !== null && navBar.visible && !prefsPanel.visible) ? units.gu(10) : 0
        clip: true
        z: 4                        // sobre billboards (z:3), bajo searchPanel (z≥11)
        color: "white"
        border.color: "#ddd"
        border.width: height > 0 ? 1 : 0
        Behavior on height { NumberAnimation { duration: 200 } }

        // Franja azul superior
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: units.gu(0.4)
            color: "#1565C0"
        }

        // Slot de ancho fijo para el badge (0 cuando no hay badge, evita anclas condicionales)
        Item {
            id: adBadgeSlot
            anchors { left: parent.left; leftMargin: units.gu(1.2); verticalCenter: parent.verticalCenter }
            width:  adBadge.visible ? (adBadge.width + units.gu(1.0)) : 0
            height: adBadge.visible ? adBadge.height : 0

            Rectangle {
                id: adBadge
                visible: !!(root._adPanelBb && root._adPanelBb.url
                            && root._adPanelBb.url.indexOf("navius") >= 0)
                width: units.gu(4.5); height: units.gu(4.5); radius: width / 2
                color: "#1565C0"
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                Text {
                    anchors.centerIn: parent
                    text: "N"; color: "white"
                    font.bold: true; font.pixelSize: units.gu(2.0)
                }
            }
        }

        // Textos (siempre anclados al slot, que tiene ancho 0 sin badge)
        Column {
            anchors {
                left: adBadgeSlot.right
                right: adCloseBtn.left; rightMargin: units.gu(0.5)
                verticalCenter: parent.verticalCenter
            }
            spacing: units.gu(0.5)
            Text {
                width: parent.width
                text: root._adLocalized(root._adPanelBb, "titulo")
                font.bold: true; font.pixelSize: units.gu(2.1)
                color: "#111"; elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root._adPanelBb
                      ? (_adLocalized(root._adPanelBb, "subtitulo")
                         || (root._adPanelBb.url
                             ? root._adPanelBb.url.replace(/^https?:\/\//, "")
                             : ""))
                      : ""
                font.pixelSize: units.gu(1.7); color: "#1565C0"; elide: Text.ElideRight
            }
        }

        // Botón cierre
        Rectangle {
            id: adCloseBtn
            width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
            color: "transparent"
            anchors { right: parent.right; rightMargin: units.gu(0.8); verticalCenter: parent.verticalCenter }
            Text { anchors.centerIn: parent; text: "✕"; color: "#888"; font.pixelSize: units.gu(1.6) }
            MouseArea { anchors.fill: parent; onClicked: { adPanelTimer.stop(); root._adPanelBb = null } }
        }

        // Tap en el panel abre la URL
        MouseArea {
            anchors { fill: parent; rightMargin: adCloseBtn.width }
            onClicked: {
                if (root._adPanelBb && root._adPanelBb.url)
                    Qt.openUrlExternally(NavAlerts.clickUrl(root._adPanelBb.id,
                                                            mainAuthSettings.token || ""))
            }
        }
    }

    // ── Lista de indicaciones (pantalla completa, visible al pulsar la zona de instrucciones) ──
    InstructionListPanel {
        id: instructionListPanel
        textScale: appSettings.textScale
        anchors.fill: parent
        visible:      false
        z:            50
        maneuvers:    (root._navData && root._navData.maneuvers) ? root._navData.maneuvers : []
        navWaypoints: root._navDests
        currentStep:  navBar._step + 1
        hasFix:       satModel.pos_has_fix
        imperial:     appSettings.measureSystem === "imperial"
        gpsLat:       satModel.pos_lat
        gpsLon:       satModel.pos_lon
        navActive:    root._navActive
        currentWpIdx: navBar._completedLegs
        onClosed:          instructionListPanel.visible = false
        onEditRouteRequested: {
            instructionListPanel.visible = false
            searchPanel.visible = true
        }
        onPoiRequested: function(type, mode, minutes) {
            instructionListPanel.visible = false
            searchPanel.poiMode    = mode
            searchPanel.poiMinutes = minutes
            searchPanel.visible    = true
            searchPanel.searchPoi(type)
        }
        onTodoToggled: function(wpIdx, todoIdx, done) {
            var dests = JSON.parse(JSON.stringify(root._navDests))
            if (dests[wpIdx] && dests[wpIdx].todos && dests[wpIdx].todos[todoIdx] !== undefined) {
                dests[wpIdx].todos[todoIdx].done = done
                root._navDests = dests
                appSettings.navWaypointsJson = JSON.stringify(dests)
                searchPanel.syncTodoFromNav(wpIdx, todoIdx, done)
            }
        }
    }

    // ── Panel de lista de tareas por destino ─────────────────────────────
    MessagesPanel {
        id: messagesPanel
        deviceId:  deviceMsgSt.deviceId
        authToken: mainAuthSettings.token
        textScale: appSettings.textScale
        onClosed: {
            messagesPanel.visible = false
            var unread = 0
            for (var i = 0; i < messagesPanel._msgs.length; i++)
                if (!messagesPanel._msgs[i].leido_en) unread++
            root._msgUnread = unread
        }
        onAddDestRequested: function(lat, lon, nombre) { root._addNavDest(lat, lon, nombre) }
        onViewDetailRequested: function(msg) { msgDetailPopup.open([msg]) }
    }

    MsgDetailPopup {
        id: msgDetailPopup
        deviceId:  deviceMsgSt.deviceId
        authToken: mainAuthSettings.token
        textScale: appSettings.textScale
        onClosed: {
            msgDetailPopup.visible = false
            root._msgBannerShow = false
            root._msgNewCount   = 0
            root._msgNewMsgs    = []
            var unread = 0
            for (var i = 0; i < messagesPanel._msgs.length; i++)
                if (!messagesPanel._msgs[i].leido_en) unread++
            root._msgUnread = unread
        }
        onAddDestRequested: function(lat, lon, nombre) { root._addNavDest(lat, lon, nombre) }
    }

    // ── Reproductor de música ────────────────────────────────────────────
    MediaPanel {
        id: mediaPanel
        textScale: appSettings.textScale
        navHttpObj: navHttp
        ttsObj: navTts
        duckVolume: appSettings.duckVolume
        onDuckVolumeEdited: appSettings.duckVolume = vol
        onDismissed: mediaPanel.visible = false
    }

    StopTodoPanel {
        id: stopTodoPanel
        textScale: appSettings.textScale
        navWaypoints: root._navDests.length > 0 ? root._navDests
                    : root._lastNavDests.length > 0 ? root._lastNavDests
                    : searchPanel._dests
        onClosed: stopTodoPanel.visible = false
        onVisibleChanged: if (visible) todoArrivalBanner.visible = false
        onTodoToggled: function(wpIdx, todoIdx, done) {
            if (root._navDests.length > 0) {
                var dests = JSON.parse(JSON.stringify(root._navDests))
                if (dests[wpIdx] && dests[wpIdx].todos && dests[wpIdx].todos[todoIdx] !== undefined) {
                    dests[wpIdx].todos[todoIdx].done = done
                    root._navDests = dests
                    appSettings.navWaypointsJson = JSON.stringify(dests)
                    searchPanel.syncTodoFromNav(wpIdx, todoIdx, done)
                }
            } else if (root._lastNavDests.length > 0) {
                var lastDests = JSON.parse(JSON.stringify(root._lastNavDests))
                if (lastDests[wpIdx] && lastDests[wpIdx].todos && lastDests[wpIdx].todos[todoIdx] !== undefined) {
                    lastDests[wpIdx].todos[todoIdx].done = done
                    root._lastNavDests = lastDests
                    searchPanel.syncTodoFromNav(wpIdx, todoIdx, done)
                }
            } else {
                searchPanel.syncTodoFromNav(wpIdx, todoIdx, done)
            }
        }
        onTodoDeleted: function(wpIdx, todoIdx) {
            var spDests = JSON.parse(JSON.stringify(searchPanel._dests))
            if (spDests[wpIdx] && spDests[wpIdx].todos && todoIdx >= 0 && todoIdx < spDests[wpIdx].todos.length) {
                spDests[wpIdx].todos.splice(todoIdx, 1)
                searchPanel._dests = spDests
                searchPanel._saveWaypoints()
            }
            if (root._navDests.length > 0) {
                var nd = JSON.parse(JSON.stringify(root._navDests))
                if (nd[wpIdx] && nd[wpIdx].todos && todoIdx >= 0 && todoIdx < nd[wpIdx].todos.length) {
                    nd[wpIdx].todos.splice(todoIdx, 1)
                    root._navDests = nd
                    appSettings.navWaypointsJson = JSON.stringify(nd)
                }
            } else if (root._lastNavDests.length > 0) {
                var ld = JSON.parse(JSON.stringify(root._lastNavDests))
                if (ld[wpIdx] && ld[wpIdx].todos && todoIdx >= 0 && todoIdx < ld[wpIdx].todos.length) {
                    ld[wpIdx].todos.splice(todoIdx, 1)
                    root._lastNavDests = ld
                }
            }
        }
        onTodoRenamed: function(wpIdx, todoIdx, newText) {
            var spDests = JSON.parse(JSON.stringify(searchPanel._dests))
            if (spDests[wpIdx] && spDests[wpIdx].todos && todoIdx >= 0 && todoIdx < spDests[wpIdx].todos.length) {
                spDests[wpIdx].todos[todoIdx].text = newText
                searchPanel._dests = spDests
                searchPanel._saveWaypoints()
            }
            if (root._navDests.length > 0) {
                var nd = JSON.parse(JSON.stringify(root._navDests))
                if (nd[wpIdx] && nd[wpIdx].todos && todoIdx >= 0 && todoIdx < nd[wpIdx].todos.length) {
                    nd[wpIdx].todos[todoIdx].text = newText
                    root._navDests = nd
                    appSettings.navWaypointsJson = JSON.stringify(nd)
                }
            } else if (root._lastNavDests.length > 0) {
                var ld = JSON.parse(JSON.stringify(root._lastNavDests))
                if (ld[wpIdx] && ld[wpIdx].todos && todoIdx >= 0 && todoIdx < ld[wpIdx].todos.length) {
                    ld[wpIdx].todos[todoIdx].text = newText
                    root._lastNavDests = ld
                }
            }
        }
    }

    // ── Botón menú (derecha, debajo del panel superior) ──────────────────
    Rectangle {
        id: menuBtn
        visible: !prefsPanel.visible && !searchPanel.visible && !satPanel.visible && !routeSelectPanel.visible
        anchors { right: parent.right; rightMargin: units.gu(2.5) + root._scrubOff
                  top: parent.top; topMargin: root._navBarScreenHeight + root._alertBannerHeight + units.gu(1.5) }
        width: units.gu(9); height: units.gu(9); radius: width / 2
        color: "transparent"
        border.color: root._uiBorder
        border.width: units.gu(0.15)
        z: 20

        BtnLabel {
            anchors.centerIn: parent
            text: root._menuOpen ? "✕" : "≡"
            fontSize: units.gu(3.2)
            mainColor: root._uiFg
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root._menuOpen = !root._menuOpen
        }
    }

    // ── Velocidad overlay en mapa (landscape, ocupa sitio del soundBtn) ──────
    Rectangle {
        id: mapSpeedOverlay
        visible: root._isLandscape && !root._menuOpen && !prefsPanel.visible
                 && !searchPanel.visible && !satPanel.visible && !routeSelectPanel.visible
        // Anchors por defecto = portrait (sólo relevante visualmente en landscape)
        anchors { right: parent.right; rightMargin: units.gu(2.5)
                  top: menuBtn.bottom; topMargin: units.gu(0.5) }
        // Landscape: libera top, centra verticalmente con menuBtn
        states: State {
            name: "ls"; when: root._isLandscape
            AnchorChanges {
                target: mapSpeedOverlay
                anchors.top: undefined
                anchors.right: menuBtn.left
                anchors.verticalCenter: menuBtn.verticalCenter
            }
            PropertyChanges {
                target: mapSpeedOverlay
                anchors.rightMargin: units.gu(0.5)
                anchors.topMargin:   0
            }
        }
        width: units.gu(9); height: units.gu(9); radius: width / 2
        color: "#07111E"
        border.color: "#546E7A"; border.width: units.gu(0.15)
        z: 15
        Column {
            anchors.centerIn: parent; spacing: 0
            visible: navBar.hasFix && !root._searchingGps
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: NavSearch.formatSpeed(navBar.gpsSpeedKmh, navBar.imperial).toString()
                color: navBar._speedOver && navBar._effVerified ? "#E53935"
                     : navBar._speedOver                        ? "#FF6F00" : "white"
                font.pixelSize: units.gu(3.5); font.bold: true; lineHeight: 0.9
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: NavSearch.speedUnit(navBar.imperial)
                color: "white"; opacity: 0.75
                font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
            }
        }
        Column {
            anchors.centerIn: parent; spacing: units.gu(0.1)
            visible: root._searchingGps
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "⟳"; color: "white"
                font.pixelSize: units.gu(2.8)
                RotationAnimation on rotation {
                    running: root._searchingGps
                    loops: Animation.Infinite; from: 0; to: 360; duration: 2000
                }
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "GPS"; color: "white"; opacity: 0.75
                font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
            }
        }
    }

    // ── Botón sonido (solo portrait, debajo del menú) ────────────────────
    // ── Tooltip modo sonido (aparece 2s junto al botón al cambiar modo) ───────
    Rectangle {
        id: soundModeTooltip
        z: 16
        visible: opacity > 0
        opacity: 0.0
        anchors {
            left:           root._isLandscape ? soundBtnInGroup.right : undefined
            leftMargin:     root._isLandscape ? units.gu(1)           : 0
            right:          root._isLandscape ? undefined             : soundBtn.left
            rightMargin:    root._isLandscape ? 0                     : units.gu(1)
            verticalCenter: root._isLandscape ? soundBtnInGroup.verticalCenter : soundBtn.verticalCenter
        }
        height: units.gu(4.5)
        width: _sttLabel.implicitWidth + units.gu(3)
        radius: units.gu(0.6)
        color: "#E5071118"
        border.color: "#29B6F6"; border.width: units.gu(0.1)

        Label {
            id: _sttLabel
            anchors.centerIn: parent
            text: {
                var i = root._effInstrSound; var a = root._effAlertSound
                if (i === "off" && a === "off")   return "🔇  " + i18n.tr("Silenciado")
                if (i === "tts" && a === "tts")   return "🔊  " + i18n.tr("Indicaciones y alertas por voz")
                if (i === "tts" && a === "beep")  return "🔊  " + i18n.tr("Indicaciones voz, alertas pitido")
                if (i === "tts" && a === "off")   return "🔊  " + i18n.tr("Solo indicaciones por voz")
                if (i === "beep" && a === "tts")  return "🔔  " + i18n.tr("Indicaciones pitido, alertas voz")
                if (i === "beep" && a === "beep") return "🔈  " + i18n.tr("Solo pitidos")
                if (i === "beep" && a === "off")  return "🔈  " + i18n.tr("Solo indicaciones (pitido)")
                if (i === "off" && a === "tts")   return "🔔  " + i18n.tr("Solo alertas por voz")
                return "🔔  " + i18n.tr("Solo alertas (pitido)")
            }
            color: "white"
            font.pixelSize: units.gu(1.8 * appSettings.textScale)
        }

        Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

        Timer {
            id: _soundTtTimer
            interval: 2000; repeat: false
            onTriggered: soundModeTooltip.opacity = 0.0
        }

        function show() { opacity = 1.0; _soundTtTimer.restart() }
    }

    // Overlay transparente para cerrar el menú al tocar fuera
    MouseArea {
        visible: root._menuOpen && !satPanel.visible
        anchors.fill: parent
        z: 19
        onClicked: root._menuOpen = false
    }

    // ── Columna del menú (visible al abrir) ────────────────────────────────
    Flickable {
        id: menuFlick
        visible: root._menuOpen && !satPanel.visible
        anchors { right: menuBtn.right; top: menuBtn.bottom; topMargin: units.gu(0.5) }
        z: 20
        width: units.gu(28)
        height: Math.min(contentHeight,
                         root.height - menuBtn.y - menuBtn.height - units.gu(0.5)
                         - statusBar.height - units.gu(1))
        contentWidth: width
        contentHeight: menuColumn.implicitHeight
        clip: true
        interactive: contentHeight > height

    Flow {
        id: menuColumn
        flow: Flow.LeftToRight
        spacing: units.gu(0.5)
        width: parent.width

        // Sonido (primera opción)
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root._uiBorder
            border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: root._soundCap === "todo"    ? "🔊" :
                              root._soundCap === "alertas" ? "🔔" :
                              root._soundCap === "pitidos" ? "🔈" : "🔇"
                        font.pixelSize: root._menuItemH * 0.55; anchors.verticalCenter: parent.verticalCenter }
                Label { text: root._soundCap === "todo"    ? i18n.tr("Voz + alertas") :
                              root._soundCap === "alertas" ? i18n.tr("Solo alertas") :
                              root._soundCap === "pitidos" ? i18n.tr("Solo pitidos") : i18n.tr("Silencio")
                        color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.40; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root._soundCap === "todo") {
                        root._soundCap = "alertas"; navTts.alert_beep()
                    } else if (root._soundCap === "alertas") {
                        navTts.stop_tts(); root._soundCap = "pitidos"; navTts.alert_beep()
                    } else if (root._soundCap === "pitidos") {
                        navTts.stop_tts(); root._soundCap = "silencio"
                    } else {
                        navTts.stop_tts(); root._soundCap = "todo"; navTts.beep()
                    }
                }
            }
        }

        // Compartir viaje
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root._shareToken !== "" ? "#FF5252" : root._uiBorder
            border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: root._shareToken !== "" ? "🔴" : "📡"
                        font.pixelSize: root._menuItemH * 0.50
                        anchors.verticalCenter: parent.verticalCenter }
                Label { text: root._shareToken !== "" ? i18n.tr("Compartiendo") : i18n.tr("Compartir viaje")
                        color: root._shareToken !== "" ? "#FF5252" : root._uiFg
                        font.pixelSize: root._menuItemH * 0.375
                        anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root._menuOpen = false
                    tripSharePanel.active  = root._shareToken !== ""
                    tripSharePanel.visible = true
                }
            }
        }

        // Previsualización de ruta
        Rectangle {
            visible: root._navActive && !routeViewPanel.visible
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg; border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "⊞"; color: root._uiFg; font.pixelSize: root._menuItemH * 0.55
                        anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Prev. Ruta"); color: root._uiFg; font.pixelSize: root._menuItemH * 0.40
                        anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; onClicked: { root._menuOpen = false; routeViewPanel.open() } }
        }

        // Lista de tareas
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg; border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "📋"; font.pixelSize: root._menuItemH * 0.45
                        anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Tareas"); color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.375
                        anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent
                onClicked: { root._menuOpen = false; stopTodoPanel.openAtWaypoint(-1) } }
        }

        // Guardar aparcamiento
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "🅿"; font.pixelSize: root._menuItemH * 0.45; anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Parking"); color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.40; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root._menuOpen = false
                    var lat = gpsSource.hasFix ? gpsSource.lat : appSettings.lastLat
                    var lon = gpsSource.hasFix ? gpsSource.lon : appSettings.lastLon
                    vehicleManager.savePark(lat, lon)
                    root._startupMsg = i18n.tr("🅿 Aparcamiento guardado · ") + (vehicleManager.activeVehicle() ? vehicleManager.activeVehicle().alias : "")
                    startupMsgTimer.restart()
                    root._updateParkingMarkers()
                }
            }
        }

        // Borrar aparcamiento
        Rectangle {
            visible: { var av = vehicleManager.activeVehicle(); return av && av.hasPark && av.costing !== "pedestrian" }
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "🗑"; font.pixelSize: root._menuItemH * 0.45; anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Borrar aparcamiento"); color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.325; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root._menuOpen = false
                    var av = vehicleManager.activeVehicle()
                    if (av) {
                        vehicleManager.clearPark(av.id)
                        root._updateParkingMarkers()
                        root._startupMsg = i18n.tr("🗑 Aparcamiento eliminado · ") + av.alias
                        startupMsgTimer.restart()
                    }
                }
            }
        }

        // Ver vehículo aparcado
        Rectangle {
            visible: { var av = vehicleManager.activeVehicle(); return av && av.hasPark && av.costing !== "pedestrian" }
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "📍"; font.pixelSize: root._menuItemH * 0.45; anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Ver vehículo"); color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.325; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root._menuOpen = false
                    var av = vehicleManager.activeVehicle()
                    if (av && av.hasPark) {
                        mapView.followMode = false
                        mapView._gpsUpdating = true
                        mapView.center = QtPositioning.coordinate(av.parkLat, av.parkLon)
                        mapView._gpsUpdating = false
                    }
                }
            }
        }

        // Ir al aparcamiento
        Rectangle {
            visible: {
                try {
                    var vArr = JSON.parse(appSettings.vehiclesJson || "[]")
                    return vArr.filter(function(v){ return v.hasPark && v.costing !== "pedestrian" }).length > 0
                } catch(e) { return false }
            }
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "🧭"; font.pixelSize: root._menuItemH * 0.45; anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Ir al aparcamiento"); color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.325; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: { root._menuOpen = false; parkingDialog.openNavigate() }
            }
        }

        // Música
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg; border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "🎵"; font.pixelSize: root._menuItemH * 0.50
                        anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Música"); color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.40; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; onClicked: { root._menuOpen = false; mediaPanel.visible = true } }
        }

        // Ajustes
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg; border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "⚙"; color: root._uiFg; font.pixelSize: root._menuItemH * 0.55
                        anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Ajustes"); color: root._uiFg; font.pixelSize: root._menuItemH * 0.40
                        anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; onClicked: { root._menuOpen = false; prefsPanel.visible = true } }
        }

        // Cuenta
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: mainAuthSettings.token !== "" ? "#66BB6A" : root._uiBorder
            border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: mainAuthSettings.token !== "" ? "✅" : "👤"
                        font.pixelSize: root._menuItemH * 0.55; anchors.verticalCenter: parent.verticalCenter }
                Label { text: mainAuthSettings.token !== "" ? i18n.tr("Mi cuenta") : i18n.tr("Login")
                        color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.40; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; onClicked: { root._menuOpen = false; loginPanel.open() } }
        }

        // Mensajes
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg; border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "✉"; color: root._uiFg; font.pixelSize: root._menuItemH * 0.55
                        anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Mensajes"); color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.40
                        anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    visible: root._msgUnread > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(units.gu(2.8), msgBadgeLbl.width + units.gu(1.2))
                    height: units.gu(2.8); radius: units.gu(1); color: "#FF5722"
                    Label {
                        id: msgBadgeLbl; anchors.centerIn: parent
                        text: root._msgUnread
                        color: "white"; font.pixelSize: units.gu(1.3 * appSettings.textScale); font.bold: true
                    }
                }
            }
            MouseArea { anchors.fill: parent
                onClicked: { root._menuOpen = false; messagesPanel.open(-1) } }
        }

        // Bloqueo de mapa
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root._mapLocked ? "#FF9800" : root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: root._mapLocked ? "🔒" : "🔓"
                        font.pixelSize: root._menuItemH * 0.475
                        anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Bloq. Mapa")
                        color: root._mapLocked ? "#FF9800" : root._uiFg
                        font.pixelSize: root._menuItemH * 0.375
                        anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; onClicked: root._mapLocked = !root._mapLocked }
        }

        // Debug
        Rectangle {
            visible: appSettings.prefLevel >= 2
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: appSettings.debugMode ? "#FFD700" : root._uiBorder; border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: "⬡ " + i18n.tr("Debug")
                color: appSettings.debugMode ? "#FFD700" : root._uiFg; font.pixelSize: root._menuItemH * 0.375
            }
            MouseArea { anchors.fill: parent; onClicked: appSettings.debugMode = !appSettings.debugMode }
        }

        // Simulación GPS
        Rectangle {
            visible: appSettings.debugMode
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: appSettings.simMode ? "#CE93D8" : root._uiBorder; border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: "⏵ " + i18n.tr("Sim GPS")
                color: appSettings.simMode ? "#CE93D8" : root._uiFg; font.pixelSize: root._menuItemH * 0.375
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    appSettings.simMode = !appSettings.simMode
                    if (appSettings.simMode) {
                        root.simSignalLost = false
                        if (gpsSource.simIdx > 0 && !gpsSource.simFinished) {
                            mapView.followMode = true
                            gpsSource.seekTo(gpsSource.simIdx)
                        } else { root.simStart() }
                    } else {
                        root.simSignalLost = false
                        gpsSource.simStop()
                        mapView._hasPos = false
                    }
                }
            }
        }

        // Fallo GPS (antes Sin GPS)
        Rectangle {
            visible: appSettings.debugMode && appSettings.simMode
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root.simSignalLost ? "#FF5252" : root._uiBorder; border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: root.simSignalLost ? "⊗ " + i18n.tr("GPS on") : "⊗ " + i18n.tr("Fallo GPS")
                color: root.simSignalLost ? "#FF5252" : root._uiFg; font.pixelSize: root._menuItemH * 0.375
            }
            MouseArea { anchors.fill: parent; onClicked: root.simSignalLost = !root.simSignalLost }
        }

        // Pausar simulación
        Rectangle {
            visible: appSettings.debugMode && appSettings.simMode
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root.simPaused ? "#29B6F6" : root._uiBorder; border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: root.simPaused ? "▶ " + i18n.tr("Reanudar") : "⏸ " + i18n.tr("Pausar sim")
                color: root.simPaused ? "#29B6F6" : root._uiFg; font.pixelSize: root._menuItemH * 0.375
                font.bold: root.simPaused
            }
            MouseArea { anchors.fill: parent; onClicked: root.simPaused = !root.simPaused }
        }

        // Suavizado GPS debug
        Rectangle {
            visible: appSettings.debugMode
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1); color: root._uiBtnBg
            border.color: appSettings.showGpsSmoothDebug ? "#29B6F6" : root._uiBorder
            border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: "🔧 " + i18n.tr("Suavizado GPS")
                color: appSettings.showGpsSmoothDebug ? "#29B6F6" : root._uiFg
                font.pixelSize: root._menuItemH * 0.375
                font.bold: appSettings.showGpsSmoothDebug
            }
            MouseArea { anchors.fill: parent; onClicked: appSettings.showGpsSmoothDebug = !appSettings.showGpsSmoothDebug }
        }

        // IMU debug
        Rectangle {
            visible: appSettings.debugMode
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1); color: root._uiBtnBg
            border.color: appSettings.showImuDebug ? "#CE93D8" : root._uiBorder
            border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: "🧭 " + i18n.tr("IMU debug")
                color: appSettings.showImuDebug ? "#CE93D8" : root._uiFg
                font.pixelSize: root._menuItemH * 0.375
                font.bold: appSettings.showImuDebug
            }
            MouseArea { anchors.fill: parent; onClicked: appSettings.showImuDebug = !appSettings.showImuDebug }
        }

        // Bisector debug
        Rectangle {
            visible: appSettings.debugMode && appSettings.simMode
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1); color: root._uiBtnBg
            border.color: appSettings.showBisectorDebug ? "#29B6F6" : root._uiBorder
            border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: "📐 " + i18n.tr("Bisector")
                color: appSettings.showBisectorDebug ? "#29B6F6" : root._uiFg
                font.pixelSize: root._menuItemH * 0.375
                font.bold: appSettings.showBisectorDebug
            }
            MouseArea { anchors.fill: parent; onClicked: appSettings.showBisectorDebug = !appSettings.showBisectorDebug }
        }

        // POIs debug
        Rectangle {
            visible: appSettings.debugMode
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root._dbgPoi ? "#00E676" : root._uiBorder; border.width: units.gu(0.15)
            Label {
                anchors.centerIn: parent
                text: "⊙ " + i18n.tr("POIs debug")
                color: root._dbgPoi ? "#00E676" : root._uiFg; font.pixelSize: root._menuItemH * 0.375
                font.bold: root._dbgPoi
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root._dbgPoi = !root._dbgPoi
                    var vis = root._dbgPoi ? "visible" : "none"
                    mapView.setLayoutProperty("dbg-center-dot", "visibility", vis)
                    mapView.setLayoutProperty("dbg-gps-dot",    "visibility", vis)
                    mapView.setLayoutProperty("dbg-N-dot",      "visibility", vis)
                    mapView.setLayoutProperty("dbg-S-dot",      "visibility", vis)
                    mapView.setLayoutProperty("dbg-E-dot",      "visibility", vis)
                    mapView.setLayoutProperty("dbg-W-dot",      "visibility", vis)
                }
            }
        }


        // Donar
        Rectangle {
            width: root._menuItemW; height: root._menuItemH
            radius: units.gu(1)
            color: root._uiBtnBg
            border.color: root._uiBorder; border.width: units.gu(0.15)
            Row {
                anchors.centerIn: parent; spacing: units.gu(1.2)
                Label { text: "♥"; color: root._uiFg; font.pixelSize: root._menuItemH * 0.55
                        anchors.verticalCenter: parent.verticalCenter }
                Label { text: i18n.tr("Donar"); color: root._uiFg
                        font.pixelSize: root._menuItemH * 0.40
                        anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent
                onClicked: { root._menuOpen = false; Qt.openUrlExternally("https://liberapay.com/Navius-GPS/donate") } }
        }

    }  // fin menuColumn

    }  // fin menuFlick

    // ── Panel de búsqueda y navegación ────────────────────────────────────
    SearchPanel {
        id: searchPanel
        isLandscape: root._isLandscape
        textScale: appSettings.textScale
        gpsLat:      activeModel.pos_has_fix ? activeModel.pos_lat : appSettings.lastLat
        gpsLon:      activeModel.pos_has_fix ? activeModel.pos_lon : appSettings.lastLon
        hasFix:      activeModel.pos_has_fix
        simMode:     appSettings.simMode
        imperial:    appSettings.measureSystem === "imperial"
        fileLogger:  satModel
        navHttp:     navHttp
        restoreNav:  appSettings.wasNavigating
        navActive:    root._navActive
        navShape:     (root._navActive && root._navData) ? root._navData.shape : null
        navSpeedKmh:  (root._navActive && root._navData && root._navData.time > 0)
                      ? (root._navData.length / root._navData.time * 3600) : 0
        onClosed: searchPanel.visible = false
        onRouteReady: function(routes, selIdx) {
            if (!routes || routes.length === 0) {
                root.clearRoute()
            } else {
                root.applyRoutes(routes, selIdx)
                root._fetchRouteRadarCounts(routes)
                // Guarda waypoints para recuperar tras reinicio
                // (SearchPanel los gestiona en su Settings interno)
            }
        }
        onNavigationStarted: function(routeData) {
            root._startNavigation(routeData)
        }
        onPreviewRequested: function(routes, selIdx) {
            Qt.inputMethod.hide()
            searchPanel.visible = false
            routeSelectPanel.routes = routes
            routeSelectPanel.selIdx = selIdx
            root._fetchRouteRadarCounts(routes)
            // Combinar puntos de todas las rutas para que el bbox/zoom/centro
            // abarque todas las alternativas y no se mueva al cambiar de ruta.
            var combined = []
            for (var i = 0; i < routes.length; i++)
                combined = combined.concat(routes[i].shape)
            root._previewShape = combined
            routeSelectPanel.visible = true   // visible antes de open() para que bottomPanelHeight sea correcto
            routeViewPanel.open()
            root.drawRoutesPreview(routes, selIdx)
        }
        onGoogleMapsRequested: {
            // GoogleMapsPanel (QtWebEngine) no está disponible en postmarketOS:
            // solo existe QtWebEngine para Qt6 en los repos, y esta app es Qt5.
            // Sin sustituto por ahora — no-op.
            Qt.inputMethod.hide()
        }
        onServerFallbackNeeded: function(service, message, retryFn) {
            Qt.inputMethod.hide()
            serverFallbackDialog._retryFn = retryFn
            serverFallbackDialog.showOsmScout = (service === "Valhalla")
            serverFallbackDialog.open(service, message)
        }
    }

    // ── Banner de alerta de radar ─────────────────────────────────────────
    // ── Debug: estado del próximo aviso TTS ──────────────────────────────────
    Rectangle {
        visible: appSettings.debugMode && appSettings.showVSimDebug && root._navActive
                 && !prefsPanel.visible && !satPanel.visible
                 && !searchPanel.visible && !routeSelectPanel.visible
                 && !routeViewPanel.visible && !instructionListPanel.visible
        anchors { left: parent.left; right: parent.right; top: adPanel.bottom }
        height: units.gu(5.5); z: 11
        color: "#CC07111E"
        Column {
            anchors { left: parent.left; leftMargin: units.gu(1); top: parent.top; topMargin: units.gu(0.3) }
            spacing: units.gu(0.1)
            Label {
                text: {
                    var idx  = navBar._annStep
                    var cnt  = navBar._annCount
                    var tgt  = navBar._annTarget >= 0 ? navBar._annTarget + "m" : "-"
                    var spd  = navBar.gpsSpeedKmh
                    var t2m  = spd > 1
                               ? (navBar._stepDistKm * 1000 / (spd / 3.6)).toFixed(0) + "s"
                               : "?s"
                    return "idx=" + idx + " cnt=" + cnt + " tgt=" + tgt +
                           " t2m=" + t2m + " v=" + spd.toFixed(1) + "km/h"
                }
                color: "#CE93D8"; font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
            }
            Label {
                text: {
                    var vV  = navBar._valhallaSpeedKmh
                    var sl  = navBar._speedLimit
                    var rc  = navBar._roadClass
                    var vG  = (sl > 0) ? sl : NavSearch._legalSpeedByClass(rc, 0)
                    return "vV=" + vV.toFixed(0) + "km/h" +
                           "  sl=" + (sl > 0 ? sl + "km/h" : "-") +
                           "  vG=" + (vG > 0 ? vG.toFixed(0) + "km/h" : "?") +
                           "  rc=" + (rc || "-")
                }
                color: "#80CBC4"; font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
            }
        }
    }

    Item {
        id: radarAlertBanner
        anchors { left: parent.left; right: parent.right; top: adPanel.bottom }
        height: root._tramoAlertActive && root._navActive && !prefsPanel.visible
                ? units.gu(5.5) : 0
        clip: true; z: 12
        Behavior on height { NumberAnimation { duration: 180 } }

        Rectangle {
            anchors.fill: parent
            color: {
                if (root._tramoAlertMaxspeed <= 0) return "#DD8F3B00"
                var spd = activeModel.pos_speed_kmh
                var lim = root._tramoAlertMaxspeed
                if (spd <= lim) return "#DD2E7D32"
                if (spd <= lim * (1.0 + appSettings.speedAlertPct / 100.0)) return "#DD8F3B00"
                return "#DDB71C1C"
            }

            Row {
                anchors.centerIn: parent; spacing: units.gu(1.5)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⏱"
                    font.pixelSize: units.gu(2.8 * appSettings.textScale)
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._tramoAlertMsg
                    color: "white"
                    font.pixelSize: units.gu(1.9 * appSettings.textScale); font.bold: true
                }
            }
        }
    }

    Item {
        id: fijoAlertBanner
        anchors { left: parent.left; right: parent.right; top: radarAlertBanner.bottom }
        height: root._fijoAlertActive && root._navActive && !prefsPanel.visible
                ? units.gu(5.5) : 0
        clip: true; z: 12
        Behavior on height { NumberAnimation { duration: 180 } }

        Rectangle {
            anchors.fill: parent
            color: {
                if (root._fijoContrario) return "#DD1565C3"
                if (root._fijoAlertMaxspeed <= 0) return "#DD8F3B00"
                var spd = activeModel.pos_speed_kmh
                var lim = root._fijoAlertMaxspeed
                if (spd <= lim) return "#DD2E7D32"
                if (spd <= lim * (1.0 + appSettings.speedAlertPct / 100.0)) return "#DD8F3B00"
                return "#DDB71C1C"
            }

            Row {
                anchors.centerIn: parent; spacing: units.gu(1.5)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "📷"
                    font.pixelSize: units.gu(2.8 * appSettings.textScale)
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._fijoAlertMsg
                    color: "white"
                    font.pixelSize: units.gu(1.9 * appSettings.textScale); font.bold: true
                }
            }
        }
    }

    // ── Barra de progreso de tramo ────────────────────────────────────────
    // Aparece cuando el vehículo está dentro de un radar de tramo.
    Item {
        id: tramoBar
        anchors { left: parent.left; right: parent.right; top: fijoAlertBanner.bottom }
        height: root._activeTramo !== null && root._navActive && !prefsPanel.visible
                ? units.gu(5.5) : 0
        clip: true; z: 12
        Behavior on height { NumberAnimation { duration: 180 } }

        Rectangle {
            anchors.fill: parent
            color: "#CC0D0D1A"

            // ── Fila superior: inicio / info / fin ──────────────────────
            Item {
                id: tramoTopRow
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: units.gu(3)

                Label {
                    anchors { left: parent.left; leftMargin: units.gu(1.5); verticalCenter: parent.verticalCenter }
                    text: i18n.tr("INICIO")
                    color: "#FF6F00"; font.pixelSize: units.gu(1.25 * appSettings.textScale); font.bold: true
                }

                Row {
                    anchors.centerIn: parent; spacing: units.gu(0.8)
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._activeTramo
                              ? (Math.round(root._activeTramo.lengthM * (1 - root._tramoFrac)) + " m")
                              : ""
                        color: "white"; font.pixelSize: units.gu(1.7 * appSettings.textScale); font.bold: true
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._activeTramo && root._activeTramo.maxspeed > 0
                              ? ("·  " + root._activeTramo.maxspeed + " km/h") : ""
                        color: "#FFB74D"; font.pixelSize: units.gu(1.7 * appSettings.textScale); font.bold: true
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root._tramoSpeedSamples > 0
                        text: "·  " + Math.round(root._tramoAvgSpeed) + " km/h media"
                        color: {
                            if (!root._activeTramo || root._activeTramo.maxspeed <= 0) return "white"
                            var lim = root._activeTramo.maxspeed
                            var margin = lim * (1.0 + appSettings.speedAlertPct / 100.0)
                            if (root._tramoAvgSpeed > margin) return "#FF5252"
                            if (root._tramoAvgSpeed > lim)   return "#FFB74D"
                            return "#69F0AE"
                        }
                        font.pixelSize: units.gu(1.5 * appSettings.textScale); font.bold: true
                    }
                }

                Label {
                    anchors { right: parent.right; rightMargin: units.gu(1.5); verticalCenter: parent.verticalCenter }
                    text: i18n.tr("FIN")
                    color: "#FF6F00"; font.pixelSize: units.gu(1.25 * appSettings.textScale); font.bold: true
                }
            }

            // ── Track deslizante ─────────────────────────────────────────
            Item {
                anchors {
                    left: parent.left; right: parent.right; bottom: parent.bottom
                    leftMargin: units.gu(2); rightMargin: units.gu(2); bottomMargin: units.gu(0.8)
                }
                height: units.gu(1.6)

                // Fondo del track
                Rectangle {
                    id: tramoTrackBg
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    height: units.gu(0.35); radius: height / 2
                    color: "#55FF6F00"
                }

                // Parte recorrida (relleno naranja)
                Rectangle {
                    anchors { left: tramoTrackBg.left; verticalCenter: parent.verticalCenter }
                    width: tramoTrackBg.width * root._tramoFrac
                    height: tramoTrackBg.height; radius: height / 2
                    color: "#CCFF6F00"
                    Behavior on width { NumberAnimation { duration: 2000 } }
                }

                // Marcador de posición actual (círculo blanco)
                Rectangle {
                    x: tramoTrackBg.width * root._tramoFrac - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: units.gu(1.6); height: units.gu(1.6); radius: width / 2
                    color: "white"
                    border.color: "#FF6F00"; border.width: units.gu(0.15)
                    Behavior on x { NumberAnimation { duration: 2000 } }
                }
            }
        }
    }

    // ── Banner alerta comunitaria próxima ────────────────────────────────────
    Item {
        id: commAlertBanner
        anchors { left: parent.left; right: parent.right; top: tramoBar.bottom }
        height: root._commAlertActive && !prefsPanel.visible ? units.gu(5.5) : 0
        clip: true; z: 12
        Behavior on height { NumberAnimation { duration: 180 } }

        Rectangle {
            anchors.fill: parent
            color: "#DDC75A00"

            Row {
                anchors.centerIn: parent; spacing: units.gu(1.5)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⚠"
                    font.pixelSize: units.gu(2.8 * appSettings.textScale)
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root._commAlertMsg
                    color: "white"
                    font.pixelSize: units.gu(1.9 * appSettings.textScale); font.bold: true
                }
            }
        }
    }

    // ── Panel de coordenadas (long press) ────────────────────────────────────
    Rectangle {
        id: pinPanel
        visible: root._pinVisible && !prefsPanel.visible && !satPanel.visible
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: appSettings.simMode ? units.gu(16) : units.gu(10); z: 20
        Behavior on height { NumberAnimation { duration: 150 } }
        color: "#EE0D0D1A"

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.1); color: "#1565C3"
        }

        // ── Fila de coordenadas ───────────────────────────────────────────
        Row {
            id: pinCoordsRow
            anchors { top: parent.top; topMargin: units.gu(1.2)
                      left: parent.left; leftMargin: units.gu(2)
                      right: pinCloseBtn.left; rightMargin: units.gu(1) }
            spacing: units.gu(2)

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: "📍"; font.pixelSize: units.gu(2.4 * appSettings.textScale)
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: units.gu(0.2)
                Label {
                    text: "Lat: " + root._pinLat.toFixed(6)
                    color: "white"; font.pixelSize: units.gu(1.8 * appSettings.textScale); font.bold: true
                    font.family: "Ubuntu Mono, Monospace"
                }
                Label {
                    text: "Lon: " + root._pinLon.toFixed(6)
                    color: "#90CAF9"; font.pixelSize: units.gu(1.8 * appSettings.textScale); font.bold: true
                    font.family: "Ubuntu Mono, Monospace"
                }
            }
        }

        // ── Botones de acción ─────────────────────────────────────────────
        Column {
            anchors { top: pinCoordsRow.bottom; topMargin: units.gu(1.0)
                      left: parent.left; leftMargin: units.gu(2); right: parent.right; rightMargin: units.gu(2) }
            spacing: units.gu(0.8)

            // Fila 1: Inicio sim + Añadir destino
            Row {
                width: parent.width; spacing: units.gu(1.2)

                // Inicio simulación (solo en modo sim)
                Rectangle {
                    visible: appSettings.simMode
                    width: units.gu(10); height: units.gu(4); radius: units.gu(0.6)
                    color: "#1565C3"
                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Inicio sim")
                        color: "white"; font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var pinName = root._pinLat.toFixed(5) + ", " + root._pinLon.toFixed(5)
                            searchPanel.setSimOrigin(root._pinLat, root._pinLon, pinName)
                            root._pinVisible = false
                        }
                    }
                }

                // Añadir como destino (siempre)
                Rectangle {
                    width: parent.width - (appSettings.simMode ? units.gu(10) + units.gu(1.2) : 0)
                    height: units.gu(4); radius: units.gu(0.6)
                    color: "#2E7D32"
                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Añadir destino")
                        color: "white"; font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var pinLat  = root._pinLat
                            var pinLon  = root._pinLon
                            var pinName = pinLat.toFixed(5) + ", " + pinLon.toFixed(5)

                            searchPanel.addDest(pinLat, pinLon, pinName)

                            if (root._navActive) {
                                var newDests = root._navDests.slice()
                                newDests.push({lat: pinLat, lon: pinLon, name: pinName})
                                root._navDests = newDests
                                var wps = [_originWp(activeModel.pos_lat, activeModel.pos_lon)]
                                for (var wi = navBar._completedLegs; wi < root._navDests.length; wi++) wps.push(root._navDests[wi])
                                NavSearch.route(wps, root._navOpts, function(err, routes) {
                                    if (!root._navActive) return
                                    if (err || !routes || routes.length === 0) return
                                    root.drawRoute(routes, 0)
                                    root._navData        = routes[0]
                                    gpsSource.routeShape = routes[0].shape
                                    gpsSource._shapeIdx  = 0
                                    gpsSource._shapeFrac = 0
                                    mapView.followMode = true
                                })
                            } else if (appSettings.simMode) {
                                searchPanel.setSimOrigin(
                                    activeModel.pos_lat, activeModel.pos_lon, "Posición actual")
                            }
                            root._pinVisible = false
                        }
                    }
                }
            }

            // Fila 2: Añadir alerta en esta posición
            Rectangle {
                width: parent.width; height: units.gu(4); radius: units.gu(0.6)
                color: alertaPinMa.pressed ? "#E65100" : "#BF360C"
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("🚨  Añadir alerta aquí")
                    color: "white"; font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
                }
                MouseArea {
                    id: alertaPinMa
                    anchors.fill: parent
                    onClicked: {
                        var lat = root._pinLat
                        var lon = root._pinLon
                        root._pinVisible = false
                        if (mainAuthSettings.token !== "") {
                            alertasOverlay.openAt(lat, lon)
                        } else {
                            alertasOverlay.alertLat = lat
                            alertasOverlay.alertLng = lon
                            loginPanel.open()
                        }
                    }
                }
            }

            // Fila 3: Establecer posición GPS (solo en modo sim)
            Rectangle {
                visible: appSettings.simMode
                width: parent.width; height: units.gu(4); radius: units.gu(0.6)
                color: "#37474F"
                border.color: "#CE93D8"; border.width: units.gu(0.12)
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("📍 Establecer posición GPS")
                    color: "#CE93D8"; font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        gpsSource.setSimPosition(root._pinLat, root._pinLon)
                        mapView.followMode = true
                        root._pinVisible = false
                    }
                }
            }
        }

        Rectangle {
            id: pinCloseBtn
            anchors { right: parent.right; top: parent.top
                      rightMargin: units.gu(2); topMargin: units.gu(1.2) }
            width: units.gu(4); height: units.gu(4); radius: width / 2
            color: "#2A2A3E"
            Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: units.gu(1.8 * appSettings.textScale) }
            MouseArea { anchors.fill: parent; onClicked: root._pinVisible = false }
        }
    }

    // ── Popup de voto para alertas comunitarias ───────────────────────────────
    Rectangle {
        id: alertaVotePopup
        visible: false
        z: 25
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: voteCol.implicitHeight + units.gu(3)
        radius: units.gu(2)
        color: "#0D1B2A"
        border.color: "#1E3A5F"
        clip: true

        function _catInfo(cat) {
            var _m = {
                "trafico":           ["🚗","Tráfico"],
                "policia":           ["👮","Policía"],
                "accidente":         ["💥","Accidente"],
                "peligro":           ["⚠️","Peligro"],
                "carretera_cortada": ["🚧","Carretera cortada"],
                "carril_bloqueado":  ["⛔","Carril bloqueado"],
                "error_mapa":        ["🗺️","Error mapa"],
                "mal_tiempo":        ["🌧️","Mal tiempo"],
                "asistencia":        ["🆘","Asistencia"],
                "lugar":             ["📍","Lugar"]
            }
            return _m[cat] || ["⚠️","Alerta"]
        }
        function _subLabel(sub) {
            var _m = {
                "denso":"Tráfico denso","detenido":"Detenido",
                "camara_movil":"Cámara móvil","oculto":"Policía oculto",
                "colision_multiple":"Colisión múltiple",
                "obras":"Obras","coche_arcen":"Coche en arcén",
                "semaforo_estropeado":"Semáforo averiado","bache":"Bache",
                "izquierdo":"Carril izquierdo","derecho":"Carril derecho","central":"Carril central",
                "calzada_resbaladiza":"Calzada resbaladiza","inundacion":"Inundación",
                "nieve":"Nieve","niebla":"Niebla","hielo":"Hielo",
                "companeros":"Compañeros","emergencia":"Emergencia"
            }
            return _m[sub] || sub
        }

        property bool _isOwn: false

        MouseArea { anchors.fill: parent }

        Column {
            id: voteCol
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: units.gu(1.5); leftMargin: units.gu(2); rightMargin: units.gu(2) }
            spacing: units.gu(1.2)

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(5); height: units.gu(0.5); radius: height/2; color: "#2A3A4A"
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: units.gu(1)
                Label {
                    text: root._voteAlerta ? alertaVotePopup._catInfo(root._voteAlerta.categoria)[0] : ""
                    font.pixelSize: units.gu(4 * appSettings.textScale); anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    text: root._voteAlerta ? alertaVotePopup._catInfo(root._voteAlerta.categoria)[1] : ""
                    color: "white"; font.pixelSize: units.gu(3 * appSettings.textScale); font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root._voteAlerta
                         && root._voteAlerta.subtipo !== undefined
                         && root._voteAlerta.subtipo !== null
                         && root._voteAlerta.subtipo !== ""
                text: root._voteAlerta && root._voteAlerta.subtipo
                      ? alertaVotePopup._subLabel(root._voteAlerta.subtipo) : ""
                color: "#90CAF9"; font.pixelSize: units.gu(2.0 * appSettings.textScale)
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root._voteAlerta && !alertaVotePopup._isOwn
                text: root._voteAlerta
                      ? ("✅ " + root._voteAlerta.votos_ok + "   ❌ " + root._voteAlerta.votos_no)
                      : ""
                color: "#90A4AE"; font.pixelSize: units.gu(2.3 * appSettings.textScale)
            }

            // Botones de voto (solo si la alerta no es del usuario actual)
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: units.gu(2)
                visible: root._voteAlerta && !alertaVotePopup._isOwn

                Rectangle {
                    width: units.gu(18); height: units.gu(7); radius: units.gu(1)
                    color: voteOkMa.pressed ? "#1B5E20" : "#2E7D32"
                    Label { anchors.centerIn: parent; text: i18n.tr("👍  Confirmar")
                            color: "white"; font.pixelSize: units.gu(2.5 * appSettings.textScale) }
                    MouseArea {
                        id: voteOkMa; anchors.fill: parent
                        onClicked: {
                            var _va = root._voteAlerta
                            alertaVotePopup.visible = false
                            if (_va && mainAuthSettings.token !== "") {
                                // Optimista: incrementar votos_ok localmente
                                var _upd = root._commAlertas.map(function(a) {
                                    return a.id === _va.id ? Object.assign({}, a, {votos_ok: a.votos_ok + 1}) : a
                                })
                                root._commAlertas = _upd
                                NavAlerts.votar(mainAuthSettings.token, _va.id, true,
                                    function(_ok) { Qt.callLater(alertasOverlay._fetchAlertas) })
                            }
                        }
                    }
                }

                Rectangle {
                    width: units.gu(18); height: units.gu(7); radius: units.gu(1)
                    color: voteNoMa.pressed ? "#B71C1C" : "#C62828"
                    Label { anchors.centerIn: parent; text: i18n.tr("👎  Desmentir")
                            color: "white"; font.pixelSize: units.gu(2.5 * appSettings.textScale) }
                    MouseArea {
                        id: voteNoMa; anchors.fill: parent
                        onClicked: {
                            var _va = root._voteAlerta
                            alertaVotePopup.visible = false
                            if (_va && mainAuthSettings.token !== "") {
                                var _upd = root._commAlertas.map(function(a) {
                                    return a.id === _va.id ? Object.assign({}, a, {votos_no: a.votos_no + 1}) : a
                                })
                                root._commAlertas = _upd
                                NavAlerts.votar(mainAuthSettings.token, _va.id, false,
                                    function(_ok) { Qt.callLater(alertasOverlay._fetchAlertas) })
                            }
                        }
                    }
                }
            }

            // Botón cancelar alerta (solo si es del usuario actual)
            Rectangle {
                width: parent.width; height: units.gu(7); radius: units.gu(0.8)
                visible: alertaVotePopup._isOwn
                color: deleteAlertMa.pressed ? "#B71C1C" : "#7B1FA2"
                Label { anchors.centerIn: parent; text: i18n.tr("🗑  Cancelar mi alerta")
                        color: "white"; font.pixelSize: units.gu(2.5 * appSettings.textScale) }
                MouseArea {
                    id: deleteAlertMa; anchors.fill: parent
                    onClicked: {
                        var _va = root._voteAlerta
                        alertaVotePopup.visible = false
                        if (_va && mainAuthSettings.token !== "") {
                            // Optimista: quitar del mapa inmediatamente
                            root._commAlertas = root._commAlertas.filter(function(a) { return a.id !== _va.id })
                            NavAlerts.eliminarAlerta(mainAuthSettings.token, _va.id,
                                function(_ok) { Qt.callLater(alertasOverlay._fetchAlertas) })
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width; height: units.gu(7); radius: units.gu(0.8)
                color: voteCancelMa.pressed ? "#1A2535" : "#1C2D40"; border.color: "#2A4060"
                Label { anchors.centerIn: parent; text: i18n.tr("Cerrar")
                        color: "#90A4AE"; font.pixelSize: units.gu(2.5 * appSettings.textScale) }
                MouseArea { id: voteCancelMa; anchors.fill: parent
                            onClicked: alertaVotePopup.visible = false }
            }

            Item { width: 1; height: units.gu(0.5) }
        }
    }

    // ── Timer periódico para cargar radares por posición ────────────────────
    // Repite cada 60s sin depender de que el mapa deje de moverse: en movimiento
    // continuo (conduciendo) un debounce por restart() nunca llegaría a disparar.
    // _fetchRadarsViewport() ya no hace nada si la posición actual sigue cubierta.
    Timer {
        id: radarViewportTimer
        interval: 60000; repeat: true; running: true
        onTriggered: root._fetchRadarsViewport()
    }

    // ── Sondeo de pre-generación TTS (actualiza barra de estado) ─────────
    Timer {
        id: ttsPregenPollTimer
        interval: 500; repeat: true; running: false
        onTriggered: {
            root._ttsPregenProgress = navTts.pregen_progress()
            if (!navTts.is_pregen_active()) {
                root._ttsPregenBusy     = false
                root._ttsPregenProgress = ""
                stop()
            }
        }
    }


    // ── Timer de comprobación de radares (alertas en navegación) ──────────
    Timer {
        id: radarCheckTimer
        interval: 3000; repeat: true
        running: root._navActive && !root._navPaused &&
                 (root._radarFijos.length > 0 || root._radarTramos.length > 0) &&
                 (appSettings.showRadarFijos || appSettings.showRadarTramo)
        onTriggered: root._checkRadar()
    }

    Timer {
        id: trafficCheckTimer
        interval: 5 * 60 * 1000; repeat: true
        running: root._navActive && !root._navPaused
        onTriggered: root._checkFasterRoute()
    }

    // ── Satellite panel overlay ────────────────────────────────────────────
    Rectangle {
        id: satPanel
        anchors.fill: parent; color: "#F0000000"; visible: false; z: 50

        Rectangle { anchors.fill: parent; color: "#0D0D1A" }

        Rectangle {
            id: satPanelHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(6); color: "#1C1C2E"

            Label {
                anchors.centerIn: parent
                text: i18n.tr("Satélites"); color: "white"
                font.pixelSize: units.gu(2.5); font.bold: true
            }

            Rectangle {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter
                          rightMargin: units.gu(2) }
                width: units.gu(4); height: units.gu(4)
                radius: width / 2; color: "#2A2A3E"

                Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: units.gu(1.8 * appSettings.textScale) }
                MouseArea { anchors.fill: parent; onClicked: satPanel.visible = false }
            }
        }

        SatelliteView {
            anchors { top: satPanelHeader.bottom; left: parent.left
                      right: parent.right; bottom: parent.bottom }
            satModel:    appSettings.simMode ? activeModel : satModel
            isLandscape: root._isLandscape
        }
    }

    // ── TTS Voices panel ───────────────────────────────────────────────────
    TtsVoicesPanel {
        id: ttsVoicesPanel
        textScale: appSettings.textScale
        ttsRef: navTts
        onClosed: _applyTtsLang()   // pick up newly installed voices
    }

    Timer {
        id: ttsProcessingTimer
        interval: 150; repeat: true
        onTriggered: {
            if (!navTts.is_tts_busy()) {
                prefsPanel.ttsProcessing = false
                stop()
            }
        }
    }

// ── Preferences panel overlay ──────────────────────────────────────────
    PreferencesPanel {
        id: prefsPanel
        textScale: appSettings.textScale
        anchors.fill: parent; visible: false; z: 300
        cfg:             appSettings
        ttsRef:          navTts
        trackerRef:      navTracker
        vehicleMgr:      vehicleManager
        osmScoutActive:  root._osmScoutActive
        navius:          mapView._navius
        navMapStyles:    appSettings.mapNaviusStyles
        simSignalLost: root.simSignalLost
        simFinished:   gpsSource.simFinished
        simSegIdx:     gpsSource.simIdx
        onVisibleChanged: {
            if (visible)  root._saveMapViewState()
            else          root._restoreMapViewState()
        }
        onClosed:      prefsPanel.visible = false
        onSoundTest: function(mode, context) {
            if (mode === "tts") {
                if (context === "alertas")
                    navTts.say("Voz activada para alertas")
                else
                    navTts.say("Voz activada para indicaciones")
            } else {
                if (context === "alertas") navTts.alert_beep()
                else                       navTts.beep()
            }
        }
        onVoicesRequested: ttsVoicesPanel.open()
        onVoiceSelected: function(voiceId) {
            _applyTtsLang()
            var parts = voiceId.split("-")
            var name = parts.length >= 2 ? parts.slice(1).join(" ") : voiceId
            prefsPanel.ttsProcessing = true
            ttsProcessingTimer.restart()
            navTts.say_with_lang(voiceId, "Soy paiper con voz " + name)
        }
        onVoicePicoSelected: function(voiceId) {
            _applyTtsLang()
            prefsPanel.ttsProcessing = true
            ttsProcessingTimer.restart()
            navTts.say_with_lang(voiceId, "Soy Pico T T S con voz " + voiceId)
        }
        onVoiceEspeakSelected: function(voiceId) {
            _applyTtsLang()
            prefsPanel.ttsProcessing = true
            ttsProcessingTimer.restart()
            navTts.say_with_lang(voiceId, "Soy espeak con voz " + voiceId)
        }
        onClearLiveCacheRequested: {
            navTts.clear_all_tts_cache()
            root._ttsPregenKeys = {}
            root._startRoundPregen(root._ttsEffectiveLang(), navBar.imperial)
        }
        onOsmScoutDetectRequested: {
            NavSearch.detectOsmScout(function(found) {
                root._osmScoutActive = found
                if (found) {
                    _setEffectiveUrl("http://127.0.0.1:8553/v2")
                    root._startupMsg = i18n.tr("OSM Scout · rutas y mapas offline")
                } else {
                    _setEffectiveUrl(appSettings.valhallaUrl)
                    root._startupMsg = i18n.tr("OSM Scout no disponible · usando ") + appSettings.valhallaUrl.replace("https://","").replace("http://","")
                }
                startupMsgTimer.restart()
            }, true)  // autoLaunch: acción explícita del usuario al pulsar "Detectar"
        }
        onEngineChanged: function(engine) {
            _applyTtsLang()
            var lang = appSettings.ttsLang
            if (lang === "system") lang = Qt.locale().name.split("_")[0]
            var names = { "auto": "automático", "piper": "Piper",
                          "mimic": "Mimic H T S", "picotts": "Pico T T S", "espeak": "espeak" }
            var engineName = names[engine] || engine
            // set_engine_override ya fue llamado síncronamente en _applyTtsLang;
            // engine_for_lang lee el estado actual y devuelve el motor real.
            var actual = navTts.engine_for_lang(lang)
            var text = (engine !== "auto" && actual !== engine)
                ? "Motor T T S " + engineName + " no disponible"
                : "Hola! Soy el motor T T S " + engineName
            navTts.say_with_lang(lang, text)
            // El motor cambió: caché antigua no sirve
            root._ttsClearCache()
            root._startRoundPregen(lang, navBar.imperial)
            if (root._navActive) root._pregenerateUpcoming(navBar._step)
        }
        onLangChanged: function(lang) {
            appSettings.ttsVoice = ""
            appSettings.ttsVoicePico = ""
            appSettings.ttsVoiceEspeak = ""
            var phrases = {
                "es": "Seleccionado español para indicaciones y alertas",
                "en": "Selected English for instructions and alerts",
                "fr": "Sélectionné français pour les instructions et alertes",
                "de": "Deutsch ausgewählt für Anweisungen und Warnungen",
                "pt": "Selecionado português para instruções e alertas",
                "it": "Selezionato italiano per le indicaciones e gli avvisi",
                "ca": "Seleccionat català per a les indicacions i alertes",
                "eu": "Hautatua euskara argibide eta alertetarako",
                "ru": "Выбран русский язык для навигации",
                "zh": "已选择中文导航语言",
                "ar": "تم اختيار اللغة العربية للتنقل",
                "fa": "زبان فارسی برای ناوبری انتخاب شد"
            }
            var effective = lang === "system" ? Qt.locale().name.split("_")[0] : lang
            navTts.say_with_lang(effective, phrases[effective] || phrases["es"])
            // Invalidar caché (idioma y motor pueden haber cambiado)
            root._ttsClearCache()
            root._startRoundPregen(effective, navBar.imperial)
            if (root._navActive) root._pregenerateUpcoming(navBar._step)
        }
        onMapCacheClearRequested: {
            satModel.delete_mapbox_cache()   // borra SQLite de estilos/sprites/tiles de Mapbox GL
            mapView.clearCache()             // limpia caché en memoria
            // Fuerza recarga del estilo (nuevo estilo del servidor — POI, sprites, etc.)
            var _savedUrl = mapView.styleUrl
            mapView.styleUrl = ""
            Qt.callLater(function() { mapView.styleUrl = _savedUrl })
            mapView._tileBusy = true
            mapView._tileIdleTimer.restart()
            root._startupMsg = i18n.tr("Caché de mapas eliminada")
            startupMsgTimer.restart()
        }
        onGoogleMapsCacheClearRequested: {
            // GoogleMapsPanel no existe en este port (ver onGoogleMapsRequested) — no-op.
        }
        onAllTracksClearRequested: {
            if (navTracker) navTracker.delete_all_tracks()
        }
        onLightModeApplied: mapView.applyLightMode()
        onSimToggled: function(active) {
            root.simSignalLost = false
            if (active) {
                if (root._navActive && root._navData) {
                    // Replace default sim route with the actual navigation route
                    root.simRoute = root.buildSimRouteFromNavData(root._navData)
                    if (appSettings.simRouteIdx > 0 && appSettings.simRouteIdx < 4) {
                        root._remapTramoShapes()
                    }
                    root.simStart()
                } else if (gpsSource.simIdx > 0 && !gpsSource.simFinished) {
                    mapView.followMode = true
                    gpsSource.seekTo(gpsSource.simIdx)
                } else {
                    root.simStart()
                }
            } else {
                gpsSource.simStop()
                mapView._hasPos = false
            }
        }
        onSignalLostToggled: root.simSignalLost = !root.simSignalLost
        onSimRouteChanged: function(idx) { root._applySimRoute(idx) }
        onManualPosApplied: function(lat, lon) {
            appSettings.manualLat = lat
            appSettings.manualLon = lon
            appSettings.manualPosActive = true
            mapView.followMode = true
            mapView._gpsUpdating = true
            mapView.updateGPS(lat, lon, 5.0)
        }
        onManualPosCleared: {
            appSettings.manualPosActive = false
            if (satModel.pos_has_fix)
                mapView.updateGPS(satModel.pos_lat, satModel.pos_lon, satModel.pos_accuracy)
            else
                mapView._hasPos = false
        }
        onTrackSimRequested: function(trackId, trackName, raw) {
            if (!appSettings.simMode) { appSettings.simMode = true; root.simSignalLost = false }
            root._pendingSimAction = { type: "trackSim", trackName: trackName, raw: raw === true }
            navTracker.get_track_sim_route_async(trackId)
        }
        onTrackGpxRequested: function(trackId) {
            navTracker.export_gpx_async(trackId)
        }
        onTrackAddToSim: function(trackId, trackName) {
            var c = []
            try { c = JSON.parse(appSettings.customSimTracks || "[]") } catch(e) {}
            if (!c.some(function(t) { return t.id === trackId })) {
                c.push({id: trackId, name: trackName})
                appSettings.customSimTracks = JSON.stringify(c)
            }
        }
        onTrackRemovedFromSim: function(simIdx) {
            var c = []
            try { c = JSON.parse(appSettings.customSimTracks || "[]") } catch(e) {}
            c.splice(simIdx, 1)
            appSettings.customSimTracks = JSON.stringify(c)
            if (appSettings.simRouteIdx >= 5) appSettings.simRouteIdx = 0
        }
        onDebugOff: {
            gpsSource.simStop()
            root._dbgVisible = false
            mapView._hasPos = false
        }
        onDebugOn: {
            satModel.ensure_debug_dir()
        }
        onDebugFileDeleteRequested: function(pattern) {
            satModel.delete_debug_file(pattern)
        }
        onHelpRequested: {
            prefsPanel.visible = false
            helpPanel.show()
        }
        onLoginRequested: {
            prefsPanel.visible = false
            loginPanel.open()
        }
        onLogoutRequested: {
            mainAuthSettings.token = ""
            mainAuthSettings.email = ""
            root._billboards = []
            root._billboardFetchLat = 0
            root._billboardFetchLng = 0
        }
        onPrivacyBannerRequested: {
            prefsPanel.visible = false
            privacyBanner.show()
        }
        onAboutRequested: {
            prefsPanel.visible = false
            aboutDialog.show()
        }
        onTourRequested: {
            prefsPanel.visible = false
            tourOverlay.show()
        }
    }

    HelpPanel {
        id: helpPanel
        textScale: appSettings.textScale
        anchors.fill: parent
        z: 310
        onClosed: helpPanel.visible = false
    }

    AboutDialog {
        id: aboutDialog
        textScale: appSettings.textScale
        anchors.fill: parent
        z: 310
    }

    TourOverlay {
        id: tourOverlay
        textScale: appSettings.textScale
        anchors.fill: parent
        z: 310
        onVoicesRequested: ttsVoicesPanel.open()
        onTourClosed: {
            if (root._checkVoiceAfterTour) {
                root._checkVoiceAfterTour = false
                var lang = (appSettings.ttsLang && appSettings.ttsLang !== "system")
                    ? appSettings.ttsLang : Qt.locale().name.split("_")[0]
                if (!navTts.installed_piper_voices(lang))
                    Qt.callLater(function() { tourOverlay.showVoiceTip() })
            }
        }
    }

    AlertasOverlay {
        id: alertasOverlay
        isLandscape: root._isLandscape
        textScale: appSettings.textScale
        anchors.fill: parent
        z: 200
        gpsLat:       activeModel.pos_has_fix ? activeModel.pos_lat : 0
        gpsLng:       activeModel.pos_has_fix ? activeModel.pos_lon : 0
        gpsBearing:   gpsSource.hasFix ? ((Math.round(gpsSource._headRad * 180 / Math.PI) % 360) + 360) % 360 : 0
        mapCenterLat: mapView._centerLat
        mapCenterLng: mapView._centerLon
        onLoginRequerido: loginPanel.open()
        onAlertasActualizadas: function(lista) {
            root._commAlertas = lista
            // Pre-cargar iconos (QRC es síncrono: tras loadImage ya están listos)
            var _seen = {}
            for (var _pi = 0; _pi < lista.length; _pi++) {
                var _pa = lista[_pi]
                var _pk = (_pa.subtipo && _pa.subtipo !== "")
                          ? _pa.categoria + "_" + _pa.subtipo : _pa.categoria
                if (!_seen[_pk]) {
                    _seen[_pk] = true
                    var _pu = "qrc:/assets/alertas/" + _pk + ".png"
                    if (!alertCanvas.isImageLoaded(_pu)) alertCanvas.loadImage(_pu)
                }
            }
            // Un único repaint diferido, cuando todos los iconos ya están cargados
            Qt.callLater(function() { alertCanvas.requestPaint() })
        }
    }

    // ── Popup cancelar límite de velocidad comunitario ──────────────────────
    Item {
        id: commLimitCancelPopup
        anchors.fill: parent; visible: false; z: 200

        Rectangle {
            anchors.fill: parent; color: "#000000"; opacity: 0.55
            MouseArea { anchors.fill: parent; onClicked: commLimitCancelPopup.visible = false }
        }

        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: clcCol.implicitHeight + units.gu(3)
            radius: units.gu(2); color: "#0D1B2A"; border.color: "#1E3A5F"; clip: true

            Column {
                id: clcCol
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: units.gu(1.5); leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                spacing: units.gu(1.2)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(5); height: units.gu(0.5); radius: height/2; color: "#2A3A4A"
                }

                // Señal grande centrada
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(10); height: units.gu(10); radius: width/2
                    color: "white"; border.color: "#C62828"; border.width: units.gu(0.6)
                    Label {
                        anchors.centerIn: parent
                        text: root._tapCommLimit ? root._tapCommLimit.velocidad : ""
                        color: "#1A1A1A"; font.pixelSize: units.gu(4.0 * appSettings.textScale); font.bold: true
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: i18n.tr("Límite comunitario")
                    color: "#90A4AE"; font.pixelSize: units.gu(2.0 * appSettings.textScale)
                }

                Rectangle {
                    width: parent.width; height: units.gu(8); radius: units.gu(0.8)
                    color: clcCancelMa.pressed ? "#3A0A0A" : "#B71C1C"; border.color: "#E53935"
                    Label { anchors.centerIn: parent; text: i18n.tr("Eliminar este límite")
                            color: "white"; font.pixelSize: units.gu(2.7 * appSettings.textScale); font.bold: true }
                    MouseArea {
                        id: clcCancelMa; anchors.fill: parent
                        onClicked: {
                            commLimitCancelPopup.visible = false
                            if (!root._tapCommLimit) return
                            var _limId = root._tapCommLimit.id
                            NavAlerts.eliminarLimite(mainAuthSettings.token, _limId, function(ok) {
                                root._commLimites = root._commLimites.filter(function(l) { return l.id !== _limId })
                                if (root._commSpeedLimitId === _limId) {
                                    root._commSpeedLimit   = 0
                                    root._commSpeedLimitId = -1
                                }
                            })
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: units.gu(8); radius: units.gu(0.8)
                    color: clcCloseMa.pressed ? "#1A2535" : "#1C2D40"; border.color: "#2A4060"
                    Label { anchors.centerIn: parent; text: i18n.tr("Cerrar")
                            color: "#90A4AE"; font.pixelSize: units.gu(2.7 * appSettings.textScale) }
                    MouseArea { id: clcCloseMa; anchors.fill: parent; onClicked: commLimitCancelPopup.visible = false }
                }

                Item { width: 1; height: units.gu(0.5) }
            }
        }
    }

    // ── Picker límite de velocidad comunitario ───────────────────────────────
    Item {
        id: commLimitPicker
        anchors.fill: parent
        visible: false
        z: 200

        function open() {
            if (mainAuthSettings.token === "") { loginPanel.open(); return }
            visible = true
        }

        Rectangle {
            anchors.fill: parent; color: "#000000"; opacity: 0.55
            MouseArea { anchors.fill: parent; onClicked: commLimitPicker.visible = false }
        }

        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: clpCol.implicitHeight + units.gu(3)
            radius: units.gu(2); color: "#0D1B2A"; border.color: "#1E3A5F"; clip: true

            Column {
                id: clpCol
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: units.gu(1.5); leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                spacing: units.gu(1.2)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(5); height: units.gu(0.5); radius: height/2; color: "#2A3A4A"
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: i18n.tr("Límite de velocidad aquí")
                    color: "white"; font.pixelSize: units.gu(3.0 * appSettings.textScale); font.bold: true
                }

                Grid {
                    id: clpGrid
                    width: parent.width
                    columns: 5; spacing: units.gu(0.8)

                    Repeater {
                        model: [10,20,30,40,50,60,70,80,90,100,110,120,130,140]
                        delegate: Rectangle {
                            width:  (clpGrid.width - clpGrid.spacing * 4) / 5
                            height: width; radius: width / 2
                            color: "white"
                            border.color: "#C62828"; border.width: units.gu(0.45)
                            Label {
                                anchors.centerIn: parent; text: modelData
                                color: "black"
                                font.pixelSize: modelData >= 100 ? units.gu(2.1) : units.gu(2.5)
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    commLimitPicker.visible = false
                                    var _lat = activeModel.pos_lat
                                    var _lng = activeModel.pos_lon
                                    var _brg = Math.round(root._drHeadRad * 180 / Math.PI)
                                    _brg = ((_brg % 360) + 360) % 360
                                    NavAlerts.enviarLimite(mainAuthSettings.token,
                                        _lat, _lng, _brg, modelData,
                                        function(ok) {
                                            if (ok) Qt.callLater(root._fetchCommLimites)
                                        })
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: units.gu(8); radius: units.gu(0.8)
                    color: clpCancelMa.pressed ? "#1A2535" : "#1C2D40"; border.color: "#2A4060"
                    Label { anchors.centerIn: parent; text: i18n.tr("Cancelar"); color: "#90A4AE"; font.pixelSize: units.gu(2.7 * appSettings.textScale) }
                    MouseArea { id: clpCancelMa; anchors.fill: parent; onClicked: commLimitPicker.visible = false }
                }

                Item { width: 1; height: units.gu(0.5) }
            }
        }
    }

    LoginPanel {
        id: loginPanel
        textScale: appSettings.textScale
        privacyAccepted: appSettings.privacyAccepted
        anchors.fill: parent
        z: 201
        onPrivacyRequired: {
            loginPanel.visible = false
            privacyBanner.show()
        }
        onLoginOk: {
            mainAuthSettings.token = loginPanel.currentToken
            mainAuthSettings.email = loginPanel.currentEmail
            alertasOverlay.continuarTrasLogin()
            alertasOverlay._fetchAlertas()
            // Sincronizar settings al hacer login
            root._pullSettingsFromServer(function(serverData, updatedAt) {
                settingsConflictDialog.show(serverData, updatedAt)
            })
        }
        onLogoutOk: {
            mainAuthSettings.token = ""
            mainAuthSettings.email = ""
            root._billboards = []
            root._billboardFetchLat = 0
            root._billboardFetchLng = 0
        }
    }

    PrivacyBanner {
        id: privacyBanner
        textScale: appSettings.textScale
        anchors.fill: parent
        z: 210
        onAccepted: {
            appSettings.privacyAccepted = true
            appSettings.privacyShown    = true
            if (appSettings.showChangesAtStartup &&
                    mainWhatsNewSt.lastSeenVersion !== whatsNewDialog.currentVersion)
                whatsNewDialog.show()
            tourOverlay.checkShowAtStartup()
        }
        onDismissed: {
            appSettings.privacyAccepted = false
            appSettings.privacyShown    = true
            mainAuthSettings.token = ""
            mainAuthSettings.email = ""
            root._billboards = []
            root._billboardFetchLat = 0
            root._billboardFetchLng = 0
            if (appSettings.showChangesAtStartup &&
                    mainWhatsNewSt.lastSeenVersion !== whatsNewDialog.currentVersion)
                whatsNewDialog.show()
            tourOverlay.checkShowAtStartup()
        }
    }

    // Diálogo de conflicto de settings: cambios locales vs settings del servidor
    Rectangle {
        id: settingsConflictDialog
        visible: false
        z: 500
        anchors.centerIn: parent
        width:  Math.min(parent.width  - units.gu(6), units.gu(52))
        height: conflictCol.implicitHeight + units.gu(4)
        radius: units.gu(1.2)
        color:  "#1C1C2E"
        border.color: "#546E7A"; border.width: 1

        property var    _serverData:      null
        property string _serverUpdatedAt: ""

        function show(data, updatedAt) {
            _serverData      = data
            _serverUpdatedAt = updatedAt
            visible = true
        }

        Column {
            id: conflictCol
            anchors { left: parent.left; right: parent.right; top: parent.top
                      margins: units.gu(2) }
            spacing: units.gu(1.5)

            Label {
                width: parent.width
                text: i18n.tr("⚙  Configuración en el servidor")
                color: "#90CAF9"; font.bold: true
                font.pixelSize: units.gu(2.2 * appSettings.textScale)
                wrapMode: Text.WordWrap
            }
            Label {
                width: parent.width
                text: settingsConflictDialog._serverUpdatedAt
                    ? "Guardada el " + settingsConflictDialog._serverUpdatedAt.replace("T", " ").slice(0, 16)
                    : "Hay configuración guardada en el servidor."
                color: "#B0BEC5"
                font.pixelSize: units.gu(1.8 * appSettings.textScale)
                wrapMode: Text.WordWrap
            }
            Label {
                width: parent.width
                text: i18n.tr("Tienes cambios locales no sincronizados. ¿Cuál configuración usar?")
                color: "#CFD8DC"
                font.pixelSize: units.gu(1.8 * appSettings.textScale)
                wrapMode: Text.WordWrap
            }
            Row {
                width: parent.width; spacing: units.gu(1.5)
                Rectangle {
                    width: (parent.width - units.gu(1.5)) / 2; height: units.gu(5.5)
                    radius: units.gu(0.7); color: "#1565C0"
                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Usar del servidor"); color: "white"
                        font.pixelSize: units.gu(1.8 * appSettings.textScale); font.bold: true
                        wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                        width: parent.width - units.gu(1)
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root._applyServerSettings(settingsConflictDialog._serverData)
                            settingsConflictDialog.visible = false
                            root._statusQueue.push({ text: i18n.tr("✓ Configuración del servidor aplicada"), color: "#81C784" })
                        }
                    }
                }
                Rectangle {
                    width: (parent.width - units.gu(1.5)) / 2; height: units.gu(5.5)
                    radius: units.gu(0.7); color: "#37474F"
                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Mantener la local"); color: "white"
                        font.pixelSize: units.gu(1.8 * appSettings.textScale); font.bold: true
                        wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                        width: parent.width - units.gu(1)
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            settingsConflictDialog.visible = false
                            root._pushSettingsToServer(false)
                        }
                    }
                }
            }
        }
    }

    // ── Panel de compartir viaje ──────────────────────────────────────────
    TripSharePanel {
        id: tripSharePanel
        textScale: appSettings.textScale
        creating: root._shareCreating
        onCreateRequested: root._startSharing()
        onStopRequested: {
            root._stopSharing()
            dismissed()
        }
        onDismissed: visible = false
    }

    // ── Debug info overlay ────────────────────────────────────────────────
    // Shown when _dbgVisible; toggled via file command "dbg".
    property bool   _dbgVisible: false
    property string _lastCmdKey: ""
    readonly property string _version: (typeof appVersion !== "undefined") ? appVersion : "?"
    property bool   _restoreVisible: false

    Timer { id: startupMsgTimer; interval: 5000; repeat: false; onTriggered: root._startupMsg = "" }

    Timer {
        id: _statusQueueTimer
        interval: 3000; repeat: false
        onTriggered: {
            if (root._statusQueue.length > 0) {
                var _q = root._statusQueue.slice()
                root._statusCurrent = _q.shift()
                root._statusQueue = _q
                _statusQueueTimer.restart()
            } else {
                root._statusCurrent = null
            }
        }
    }

    Timer {
        id: commLimitesInitTimer
        interval: 4000; repeat: false; running: true
        onTriggered: root._fetchCommLimites()
    }
    Timer {
        id: commLimitesRefreshTimer
        interval: 60000; repeat: true; running: true
        onTriggered: root._fetchCommLimites()
    }

    // ── Pre-caché de tiles a lo largo de la ruta ──────────────────────────
    property var _preCacheRouteDat:  null
    property int _preCacheSweepI:    0
    property int _preCacheSweepStep: 1
    property int _preCachePhase:     0   // 0 = wide (z11, buffer 5km+)  1 = detail (z15)

    // Devuelve el texto localizado de un billboard/anuncio.
    // Si el anunciante no proporcionó traducción para el locale actual, usa el campo base.
    function _adLocalized(bb, field) {
        if (!bb) return ""
        var lang = Qt.locale().name.substring(0, 2)
        if (bb.traducciones && bb.traducciones[lang] && bb.traducciones[lang][field])
            return bb.traducciones[lang][field]
        return bb[field] || ""
    }

    function _preCacheProgress() {
        var shape = _preCacheRouteDat ? _preCacheRouteDat.shape : null
        if (!shape) return ""
        var total = Math.ceil(shape.length / _preCacheSweepStep) * 2
        var done  = (_preCachePhase === 0)
            ? Math.floor(_preCacheSweepI / _preCacheSweepStep)
            : Math.ceil(shape.length / _preCacheSweepStep)
              + Math.floor(_preCacheSweepI / _preCacheSweepStep)
        return Math.min(100, Math.round(done * 100 / Math.max(1, total))) + "%"
    }

    Timer {
        id: preCacheSweepTimer
        interval: 70; repeat: true
        onTriggered: {
            var shape = root._preCacheRouteDat ? root._preCacheRouteDat.shape : null
            if (!shape || root._preCacheSweepI >= shape.length) {
                if (root._preCachePhase === 0) {
                    // Pasar a fase 1: detalle zoom 15
                    root._preCachePhase = 1
                    root._preCacheSweepI = 0
                    root._preCacheSweepStep = Math.max(1, Math.floor(shape.length / 150))
                    root._startupMsg = i18n.tr("Cacheando mapa… detalle")
                    startupMsgTimer.restart()
                    return
                }
                preCacheSweepTimer.stop()
                var rd = root._preCacheRouteDat
                root._preCacheRouteDat = null
                mapView.followMode = true
                root._startNavigation(rd)
                return
            }
            var pt = shape[root._preCacheSweepI]
            mapView._gpsUpdating = true
            mapView.center = QtPositioning.coordinate(pt[1], pt[0])
            mapView._gpsUpdating = false
            mapView.zoomLevel = root._preCachePhase === 0 ? 11 : 15
            root._preCacheSweepI += root._preCacheSweepStep
            // Actualizar progreso en status bar cada 10 pasos
            if (root._preCacheSweepI % (root._preCacheSweepStep * 10) < root._preCacheSweepStep) {
                var pct = root._preCacheProgress()
                root._startupMsg = i18n.tr("Cacheando mapa… ") + pct
                startupMsgTimer.restart()
            }
        }
    }

    Connections {
        target: appSettings
        onTracesEnabledChanged: {
            satModel.set_traces_enabled(appSettings.tracesEnabled)
            gpsSource.bearingDebug = appSettings.tracesEnabled
            if (appSettings.tracesEnabled) {
                console.log("SETTINGS bearingMode=" + appSettings.bearingMode
                    + " routeAheadSecs=" + appSettings.routeAheadSecs
                    + " drEnabled=" + appSettings.drEnabled
                    + " drHz=" + appSettings.drHz
                    + " simMode=" + appSettings.simMode
                    + " simRoutePoints=" + (gpsSource.simRoutePoints ? gpsSource.simRoutePoints.length + "pts" : "null")
                    + " simIdx=" + gpsSource.simIdx
                    + " navActive=" + root._navActive
                    + " hasRouteData=" + (navBar.routeData !== null))
            }
        }
    }

    // Mensajes de estado al cambiar fuente de mapas desde ajustes
    Connections {
        target: appSettings
        onMapOnlineSourceChanged: {
            if (appSettings.mapOnlineSource === "osmscout" && root._osmScoutActive) {
                root._startupMsg = i18n.tr("Mapa online: OSM Scout")
                startupMsgTimer.restart()
            } else if (appSettings.mapOnlineSource === "osmscout") {
                // Elección explícita del usuario: intentar detectar y arrancar si hace falta.
                NavSearch.detectOsmScout(function(found) {
                    root._osmScoutActive = found
                    root._startupMsg = found
                        ? i18n.tr("Mapa online: OSM Scout")
                        : i18n.tr("Mapa online: OSM Scout (no disponible · usando Mapbox)")
                    startupMsgTimer.restart()
                }, true)
            } else {
                root._startupMsg = i18n.tr("Mapa online: Mapbox")
                startupMsgTimer.restart()
            }
        }
        onMapOfflineModeChanged: {
            if (appSettings.mapOfflineMode === "osmscout" && root._osmScoutActive)
                root._startupMsg = i18n.tr("Sin internet: fallback a OSM Scout")
            else if (appSettings.mapOfflineMode === "osmscout")
                root._startupMsg = i18n.tr("Sin internet: fallback OSM Scout (no disponible)")
            else
                root._startupMsg = i18n.tr("Sin internet: caché de tiles")
            startupMsgTimer.restart()
        }
    }

    // Polling cuando preferOsmScout=true pero server no disponible: re-detecta cada 3s
    Timer {
        id: osmScoutPollTimer
        interval: 3000; repeat: true
        onTriggered: {
            NavSearch.pingOsmScout(function(alive) {
                if (alive) {
                    osmScoutPollTimer.stop()
                    osmScoutDialog.visible = false
                    root._osmScoutActive = true
                    satModel.log_to_file("OSM Scout: detectado — activando rutas offline")
                    _setEffectiveUrl("http://127.0.0.1:8553/v2")
                    // Desbloquear: si hay petición pendiente se dispara sola; si no, rerouteIfActive la lanza
                    NavSearch.setRouteBlocked(false)
                    searchPanel.setRouteBlocked(false)
                    root._startupMsg = i18n.tr("OSM Scout · rutas y mapas offline")
                    startupMsgTimer.restart()
                    searchPanel.rerouteIfActive()
                }
            })
        }
    }

    // Ping proactivo cada 60s al servidor de tiles (por si onErrorChanged no dispara)
    Timer {
        id: tileServerPingTimer
        interval: 60000; repeat: true; running: true
        onTriggered: {
            satModel.log_to_file("tileServerPingTimer: failed=" + root._tileServerFailed + " offline=" + root._mapOffline + " navius=" + mapView._navius)
            if (root._tileServerFailed || root._mapOffline || !mapView._navius) return
            var lat = mapView._lastLat || appSettings.lastLat
            var lon = mapView._lastLon || appSettings.lastLon
            NavSearch.pingTileServer("https://navius-maps.egpsistemas.com/tiles/planet/", lat, lon, function(alive) {
                satModel.log_to_file("tileServerPing: " + (alive ? "OK" : "FALLO"))
                if (!alive && !tileErrorDebounceTimer.running) tileErrorDebounceTimer.start()
            })
        }
    }

    // Debounce errores de tiles: espera 5s y confirma con ping antes de cambiar a OSM Scout
    Timer {
        id: tileErrorDebounceTimer
        interval: 5000; repeat: false
        onTriggered: {
            if (root._tileServerFailed) return
            var lat = mapView._lastLat || appSettings.lastLat
            var lon = mapView._lastLon || appSettings.lastLon
            NavSearch.pingTileServer("https://navius-maps.egpsistemas.com/tiles/planet/", lat, lon, function(alive) {
                if (alive) return
                root._tileServerFailed = true
                navTts.alert_beep()
                if (root._osmScoutActive) {
                    root._startupMsg = i18n.tr("Mapas: servidor no disponible · usando OSM Scout")
                } else {
                    root._startupMsg = i18n.tr("Mapas: servidor no disponible · usando servidor público")
                }
                startupMsgTimer.restart()
                tileRecoveryTimer.start()
            })
        }
    }

    // Cada 5 min comprueba si el servidor de tiles original volvió
    Timer {
        id: tileRecoveryTimer
        interval: 300000; repeat: true
        onTriggered: {
            var lat = mapView._lastLat || appSettings.lastLat
            var lon = mapView._lastLon || appSettings.lastLon
            NavSearch.pingTileServer("https://navius-maps.egpsistemas.com/tiles/planet/", lat, lon, function(alive) {
                if (!alive) return
                tileRecoveryTimer.stop()
                root._tileServerFailed = false
                navTts.alert_beep()
                root._startupMsg = i18n.tr("Servidor de mapas recuperado · restaurando")
                startupMsgTimer.restart()
            })
        }
    }


    // ── Conectividad ─────────────────────────────────────────────────────
    OfflineBanner {
        id:           offlineBanner
        topY:         root._navActive ? root._navBarScreenHeight : 0
        osmScoutMaps: mapView._usingOsmScoutMaps
        onIsOfflineChanged: {
            root._mapOffline = isOffline
            if (isOffline) {
                if (appSettings.mapOfflineMode === "osmscout") {
                    if (root._osmScoutActive) {
                        navTts.alert_beep()
                        root._startupMsg = i18n.tr("Sin internet · usando OSM Scout Server")
                        startupMsgTimer.restart()
                    } else {
                        // Ping rápido por si OSM Scout está corriendo pero no se detectó en arranque
                        NavSearch.pingOsmScout(function(found) {
                            if (!found) return
                            root._osmScoutActive = true
                            navTts.alert_beep()
                            root._startupMsg = i18n.tr("Sin internet · usando OSM Scout Server")
                            startupMsgTimer.restart()
                        })
                    }
                }
            } else {
                root._rerouteBeepedOffline = false
                if (root._tileServerFailed) {
                    // Ping inmediato al recuperar internet para ver si el servidor volvió
                    var lat = mapView._lastLat || appSettings.lastLat
                    var lon = mapView._lastLon || appSettings.lastLon
                    NavSearch.pingTileServer("https://navius-maps.egpsistemas.com/tiles/planet/", lat, lon, function(alive) {
                        if (!alive) return
                        tileRecoveryTimer.stop()
                        root._tileServerFailed = false
                        navTts.alert_beep()
                        root._startupMsg = i18n.tr("Conexión restaurada · volviendo a mapas online")
                        startupMsgTimer.restart()
                    })
                } else if (mapView._usingOsmScoutMaps && appSettings.mapOnlineSource !== "osmscout") {
                    navTts.alert_beep()
                    root._startupMsg = i18n.tr("Conexión restaurada · volviendo a mapas online")
                    startupMsgTimer.restart()
                }
            }
        }
    }

    // Comprueba si hay que restaurar la ruta anterior al arrancar
    Timer {
        interval: 300; running: true; repeat: false
        onTriggered: {
            if (appSettings.wasNavigating && searchPanel.dests.length > 0)
                root._restoreVisible = true
        }
    }

    RouteRestoreDialog {
        textScale: appSettings.textScale
        visible: root._restoreVisible
        onRestoreAccepted: {
            root._restoreVisible = false
            searchPanel.triggerRestore()
            root._resumeSharingIfActive()
        }
        onRestoreDeclined: {
            root._restoreVisible = false
            appSettings.wasNavigating = false
            searchPanel.cancelRestore()
        }
    }

    RouteSelectPanel {
        id: routeSelectPanel
        textScale: appSettings.textScale
        navBarHeight: root._navBarScreenHeight
        isLandscape:  root._isLandscape
        vehicleMgr:   vehicleManager
        imperial:     appSettings.measureSystem === "imperial"
        radarCounts:  root._routeRadarCounts
        onClosed: {
            routeSelectPanel.visible = false
            root._previewShape = []
            routeViewPanel.close()
            searchPanel.visible = true
        }
        onRouteSelected: function(idx) {
            routeSelectPanel.selIdx = idx
            root.drawRoutesPreview(routeSelectPanel.routes, idx)
        }
        onNavigationRequested: function(idx) {
            routeSelectPanel.visible = false
            root._previewShape = []
            routeViewPanel.close()
            var rd = routeSelectPanel.routes[idx]
            if (!mapView._usingOsmScoutMaps && rd && rd.shape && rd.shape.length > 1) {
                mapView.followMode = false
                root._preCacheRouteDat = rd
                root._preCachePhase = 0
                root._preCacheSweepStep = Math.max(1, Math.floor(rd.shape.length / 25))
                root._preCacheSweepI = 0
                preCacheSweepTimer.restart()
                root._startupMsg = i18n.tr("Cacheando mapa… 0%")
                startupMsgTimer.restart()
            } else {
                root._startNavigation(rd)
            }
        }
        onVehicleChangeRequested: function(vehicleId) {
            vehicleManager.setActive(vehicleId)
            NavSearch.setActiveCosting(vehicleManager.activeCosting())
            searchPanel.rerouteForVehicle(function(err, routes) {
                routeSelectPanel._recalculating = false
                if (err || !routes || routes.length === 0) return
                routeSelectPanel.routes = routes
                routeSelectPanel.selIdx = 0
                root._fetchRouteRadarCounts(routes)
                var combined = []
                for (var i = 0; i < routes.length; i++)
                    combined = combined.concat(routes[i].shape)
                root._previewShape = combined
                root.drawRoutesPreview(routes, 0)
            })
        }
    }

    RouteViewPanel {
        id: routeViewPanel
        textScale: appSettings.textScale
        mapRef:       mapView
        navBarHeight: root._navActive ? root._navBarScreenHeight : 0
        shape:        root._previewShape.length > 0
                      ? root._previewShape
                      : ((root._navActive && root._navData) ? root._navData.shape : [])
        hideCloseBtn:      routeSelectPanel.visible
        bottomPanelHeight: routeSelectPanel.visible ? routeSelectPanel.sheetHeight : 0
        navActive:    routeSelectPanel.visible || root._navActive
        navDests:     routeSelectPanel.visible ? searchPanel.dests : root._navDests
        screenPosOf:  root._geoToScreen
        onClosed: { /* estado restaurado internamente */ }
    }


    Rectangle {
        visible: root._dbgVisible && appSettings.debugMode && !prefsPanel.visible
        anchors {
            left:            root._isLandscape ? landscapePanel.right : undefined
            leftMargin:      root._isLandscape ? units.gu(2)          : 0
            horizontalCenter: root._isLandscape ? undefined            : parent.horizontalCenter
            top:             parent.top
            topMargin:       root._topWidgetMargin + units.gu(3.5)
        }
        height: units.gu(2.4); width: dbgLabel.width + units.gu(2)
        color: "#CC000000"; radius: units.gu(0.4)

        Label {
            id: dbgLabel
            anchors.centerIn: parent
            text: appSettings.bearingMode + " | " + appSettings.mapMode
                  + " | z:" + mapView.zoomLevel.toFixed(2)
                  + " | az:" + (appSettings.autoZoom ? "ON" : "OFF")
                  + " | p:" + Math.round(mapView.pitch)
                  + " | mpp:" + mapView.metersPerPixel.toFixed(4)
                  + " | cy:" + Math.round(posOverlayRoot._cy)
            color: "#FFD700"; font.pixelSize: units.gu(1.1 * appSettings.textScale)
        }
    }

    // ── Banner "Tienes N mensajes nuevos" ────────────────────────────────
    Rectangle {
        id: msgNavBanner
        anchors { left: parent.left; right: parent.right; bottom: trafficBanner.visible ? trafficBanner.top : mapBottomAnchor.bottom }
        height: units.gu(7)
        visible: root._msgBannerShow && !msgDetailPopup.visible && !messagesPanel.visible && !root._menuOpen
        color: "#0A0E1A"
        z: 18

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.18); color: root._msgBannerColor()
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root._msgBannerShow = false
                var unread = []
                var all = messagesPanel._msgs
                for (var i = 0; i < all.length; i++) if (!all[i].leido_en) unread.push(all[i])
                if (unread.length > 0) msgDetailPopup.open(unread)
            }
        }

        Row {
            anchors { fill: parent; leftMargin: units.gu(2); rightMargin: units.gu(1.5); topMargin: units.gu(0.5); bottomMargin: units.gu(0.5) }
            spacing: units.gu(1.5)

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: "📨"; font.pixelSize: units.gu(2.5 * appSettings.textScale)
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - units.gu(14)
                text: root._msgNewCount === 1
                      ? i18n.tr("Tienes un mensaje nuevo")
                      : i18n.tr("Tienes %1 mensajes nuevos").arg(root._msgNewCount)
                color: "white"; font.pixelSize: units.gu(1.8 * appSettings.textScale); font.bold: true
                elide: Text.ElideRight
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: "▶"; color: "#90A4AE"; font.pixelSize: units.gu(1.6 * appSettings.textScale)
            }
        }
    }

    // ── Banner tráfico: ruta más rápida ──────────────────────────────────────
    Rectangle {
        id: trafficBanner
        anchors { left: parent.left; right: parent.right; bottom: mapBottomAnchor.bottom }
        height: units.gu(7)
        visible: root._trafficBannerVisible && root._navActive
        color: "#0D1F0D"
        z: 18

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.1); color: "#4CAF50"; opacity: 0.7
        }

        Row {
            anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1); topMargin: units.gu(0.5); bottomMargin: units.gu(0.5) }
            spacing: units.gu(1)

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - tBannerRevisar.width - tBannerIgnorar.width - units.gu(3)
                Label {
                    text: "🚦 " + i18n.tr("Ruta más rápida")
                    color: "white"; font.pixelSize: units.gu(1.6 * appSettings.textScale); font.bold: true
                }
                Label {
                    text: i18n.tr("Ahorra") + " " + Math.round(root._trafficTimeSavedSec / 60) + " min"
                    color: "#A5D6A7"; font.pixelSize: units.gu(1.3 * appSettings.textScale)
                }
            }

            Rectangle {
                id: tBannerRevisar
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(10); height: units.gu(5); radius: units.gu(0.6)
                color: tBannerRevisarArea.pressed ? "#1B5E20" : "#2E7D32"
                Label { anchors.centerIn: parent; text: i18n.tr("Revisar"); color: "white"; font.pixelSize: units.gu(1.5 * appSettings.textScale); font.bold: true }
                MouseArea { id: tBannerRevisarArea; anchors.fill: parent; onClicked: root._showTrafficComparison() }
            }

            Rectangle {
                id: tBannerIgnorar
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(8); height: units.gu(5); radius: units.gu(0.6)
                color: tBannerIgnorarArea.pressed ? "#1C2C3C" : "#263238"
                Label { anchors.centerIn: parent; text: i18n.tr("Ignorar"); color: "#90A4AE"; font.pixelSize: units.gu(1.4 * appSettings.textScale) }
                MouseArea { id: tBannerIgnorarArea; anchors.fill: parent; onClicked: root._clearTrafficComparison() }
            }
        }
    }

    // ── Widget compacto de música (encima del status bar) ────────────────
    MediaWidget {
        id: mediaWidget
        anchors { left: parent.left; right: parent.right; bottom: statusBar.top
                  bottomMargin: units.gu(0.4); leftMargin: units.gu(1); rightMargin: units.gu(1) }
        height: units.gu(5.5 * appSettings.textScale)
        z: 6
        visible: mediaPanel.hasTrack && !satPanel.visible && !prefsPanel.visible
                 && !searchPanel.visible && !root._menuOpen
        textScale:   appSettings.textScale
        isPlaying:   mediaPanel.isPlaying
        hasTrack:    mediaPanel.hasTrack
        trackName:   mediaPanel.currentName
        onPlayPauseClicked: mediaPanel.playPause()
        onNextClicked:      mediaPanel.playNext()
        onPrevClicked:      mediaPanel.playPrev()
        onOpenRequested:    mediaPanel.visible = true
        onCloseClicked:     mediaPanel.stop()
    }

    // Referencia de bottom que sube cuando el MediaWidget es visible
    Item {
        id: mapBottomAnchor
        anchors { left: parent.left; right: parent.right }
        anchors.bottom: (mediaWidget.visible && !root._isLandscape) ? mediaWidget.top : statusBar.top
        height: 0
    }

    // ── Status bar (siempre abajo) ────────────────────────────────────────
    Rectangle {
        id: statusBar
        visible: !satPanel.visible
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.gu(4.5 * appSettings.textScale)
        color: "#07111E"
        z: 5

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.1); color: "#29B6F6"; opacity: 0.5
        }

        Label {
            anchors { left: parent.left; leftMargin: units.gu(1.5); verticalCenter: parent.verticalCenter }
            text: "Navius"
            color: "#B0BEC5"; font.pixelSize: units.gu(1.9 * appSettings.textScale); font.bold: true
        }

        Label {
            anchors.centerIn: parent
            text: root._ttsPregenBusy   ? (i18n.tr("Pre-procesando motor TTS") + " " + root._ttsPregenProgress)
                : gpsSource.drActive    ? i18n.tr("GPS impreciso. Simulando trayecto.")
                : root._statusCurrent   ? root._statusCurrent.text
                : root._startupMsg      ? root._startupMsg
                : mapView._tileBusy     ? i18n.tr("Cargando mapa…")
                :                         ("v" + root._version)
            color: root._ttsPregenBusy  ? "#FFA000"
                 : gpsSource.drActive   ? "#FF8A65"
                 : root._statusCurrent  ? root._statusCurrent.color
                 : root._startupMsg     ? (root._osmScoutActive ? "#66BB6A" : "#B0BEC5")
                 : mapView._tileBusy    ? "#80CBC4"
                 :                        "#90A4AE"
            font.pixelSize: units.gu(1.6 * appSettings.textScale)
        }

        Item {
            anchors { right: parent.right; rightMargin: units.gu(1); verticalCenter: parent.verticalCenter }
            width: units.gu(9); height: parent.height

            Row {
                anchors.centerIn: parent; spacing: units.gu(0.5)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: activeModel.in_use_count + "/" + activeModel.in_view_count
                    color: activeModel.pos_has_fix       ? "white" :
                           activeModel.in_view_count > 0 ? "#FFA000" : "#90A4AE"
                    font.pixelSize: units.gu(1.7 * appSettings.textScale); font.bold: true
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SAT"
                    color: activeModel.pos_has_fix       ? "#29B6F6" :
                           activeModel.in_view_count > 0 ? "#FFA000" : "#90A4AE"
                    font.pixelSize: units.gu(1.45 * appSettings.textScale)
                }
            }
            MouseArea { anchors.fill: parent; onClicked: satPanel.visible = !satPanel.visible }
        }

        // Barra de progreso pre-generación TTS
        Rectangle {
            visible: root._ttsPregenBusy
            anchors { left: parent.left; bottom: parent.bottom }
            height: units.gu(0.35)
            color: "#29B6F6"
            width: {
                var parts = root._ttsPregenProgress.split("/")
                if (parts.length !== 2) return 0
                var total = parseInt(parts[1])
                if (isNaN(total) || total <= 0) return 0
                return parent.width * Math.min(parseInt(parts[0]), total) / total
            }
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
        }

        // Barra animada de carga de tiles (barrido de izquierda a derecha)
        Rectangle {
            id: _tileLoadBar
            visible: mapView._tileBusy && !root._ttsPregenBusy
            anchors { left: parent.left; bottom: parent.bottom }
            height: units.gu(0.5)
            width: parent.width * 0.45
            color: "#4DB6AC"
            SequentialAnimation on x {
                running: _tileLoadBar.visible
                loops: Animation.Infinite
                NumberAnimation { from: -_tileLoadBar.width; to: _tileLoadBar.parent.width; duration: 1400; easing.type: Easing.InOutSine }
            }
        }
    }

    // ── File-based debug command system ──────────────────────────────────────
    // D=~/.local/share/navius/debug (dataDirUri/dataDirPath vienen de main.rs,
    // calculados a partir de $HOME real en vez de estar hardcodeados)
    //
    // Modes:
    //   echo "2d"            > $D/navius_cmd   → switch to 2D
    //   echo "3d"            > $D/navius_cmd   → switch to 3D (pitch 60°)
    //   echo "north"         > $D/navius_cmd   → north-up mode
    //   echo "heading"       > $D/navius_cmd   → heading-up mode
    //   echo "follow"        > $D/navius_cmd   → enable follow mode
    //   echo "pause"         > $D/navius_cmd   → freeze simulation position
    //   echo "resume"        > $D/navius_cmd   → unfreeze simulation
    //   echo "dbg"           > $D/navius_cmd   → toggle debug overlay
    //   echo "poi"           > $D/navius_cmd   → toggle GPS/centre dots + cardinal POIs
    //   echo "shot"          > $D/navius_cmd   → save screenshot to navius_shot.png
    //   echo "pos40.32,−3.51"> $D/navius_cmd   → set manual position (lat,lon)
    //   echo "posoff"        > $D/navius_cmd   → release manual position
    // Fine control (repeat with timestamp suffix to re-send):
    //   echo "pitch+10" > $D/navius_cmd   → increase pitch by 10°
    //   echo "pitch-10" > $D/navius_cmd   → decrease pitch by 10°
    //   echo "pitch0"   > $D/navius_cmd   → set pitch to 0
    //   echo "pitch60"  > $D/navius_cmd   → set pitch to 60°
    //   echo "bear+10"  > $D/navius_cmd   → rotate map bearing +10°
    //   echo "bear-10"  > $D/navius_cmd   → rotate map bearing -10°
    //   echo "bear0"    > $D/navius_cmd   → reset bearing to north
    //
    // Response: each processed command is written to $D/navius_ack
    //   tail -f $D/navius_ack   ← to monitor from SSH
    readonly property string _cmdBase:  dataDirUri + "/debug"
    readonly property string _shotPath: dataDirPath + "/navius_shot.png"
    readonly property string _ackPath:  _cmdBase + "/navius_ack"

    readonly property string _routePath:      _cmdBase + "/navius_route"
    readonly property string _tracePath:      _cmdBase + "/navius_trace"
    readonly property string _traceBasePath:  _cmdBase + "/navius_trace"
    readonly property string _autostartPath:  _cmdBase + "/navius_autostart"
    property string _traceLines:       ""  // log acumulado desde inicio de nav (escrito cada 2s)
    property string _pendingTickLines: ""  // ticks interp pendientes hasta el próximo tick real

    function _tsLocal(ms) {
        var d = (ms !== undefined) ? new Date(ms) : new Date()
        return ("0"+d.getHours()).slice(-2)+":"+("0"+d.getMinutes()).slice(-2)+":"
              +("0"+d.getSeconds()).slice(-2)+"."+("00"+d.getMilliseconds()).slice(-3)
    }

    function _dtLocal() {
        var d = new Date()
        return d.getFullYear()
              +("0"+(d.getMonth()+1)).slice(-2)+("0"+d.getDate()).slice(-2)
              +"_"+("0"+d.getHours()).slice(-2)+("0"+d.getMinutes()).slice(-2)
              +("0"+d.getSeconds()).slice(-2)
    }

    property string _sessionTracePath: _tracePath  // se actualiza en NAV START

    function _flushTrace() {
        if (!appSettings.debugMode || root._traceLines.length === 0) return
        var fxhr = new XMLHttpRequest()
        fxhr.open("PUT", root._sessionTracePath)
        fxhr.send(root._traceLines)
    }

    function _writeAck(msg) {
        var xhr = new XMLHttpRequest()
        xhr.open("PUT", _ackPath)
        xhr.send(root._tsLocal() + " CMD: " + msg
                 + "\n  mode=" + appSettings.bearingMode + "/" + appSettings.mapMode
                 + " pitch=" + Math.round(mapView.pitch)
                 + " bear=" + Math.round(mapView.bearing)
                 + " mpp=" + mapView.metersPerPixel.toFixed(4)
                 + " cy=" + Math.round(posOverlayRoot._cy)
                 + " fov=" + mapView._fovAngle.toFixed(3)
                 + " poi=" + root._dbgPoi
                 + " follow=" + mapView.followMode
                 + " paused=" + root.simPaused
                 + " sim_mode=" + appSettings.simMode
                 + " sim_route=" + appSettings.simRouteIdx
                 + " rv=" + routeViewPanel.visible
                 + " rv_pts=" + routeViewPanel._dbgPts
                 + " rv_zoom=" + routeViewPanel._dbgZoom.toFixed(2)
                 + " rv_zH=" + routeViewPanel._dbgZH.toFixed(2)
                 + " rv_zW=" + routeViewPanel._dbgZW.toFixed(2)
                 + " rv_dLat=" + routeViewPanel._dbgDLat.toFixed(5)
                 + " rv_dLon=" + routeViewPanel._dbgDLon.toFixed(5)
                 + " rv_cLat=" + routeViewPanel._dbgCLat.toFixed(5)
                 + " rv_cLon=" + routeViewPanel._dbgCLon.toFixed(5)
                 + " rv_vH=" + routeViewPanel._dbgVH.toFixed(0)
                 + " rv_vW=" + routeViewPanel._dbgVW.toFixed(0)
                 + " rv_spanV=" + routeViewPanel._dbgSpanV.toFixed(0)
                 + " rv_spanH=" + routeViewPanel._dbgSpanH.toFixed(0)
                 + " rv_mpp=" + routeViewPanel._dbgMpp.toFixed(4)
                 + " rv_mppT=" + routeViewPanel._dbgMppT.toFixed(4)
                 + " rv_savedZ=" + routeViewPanel._dbgSavedZ.toFixed(2)
                 + "\n  AZ: lat=" + gpsSource.lat.toFixed(6) + " lon=" + gpsSource.lon.toFixed(6) + " bear=" + Math.round(mapView.bearing)
                 + " spd=" + activeModel.pos_speed_kmh.toFixed(1) + " rawSpd=" + gpsSource.speedKmh.toFixed(1)
                 + " secs=" + appSettings.autoZoomSecs
                 + " az=" + appSettings.autoZoom + " hasPos=" + mapView._hasPos
                 + " azTgt=" + mapView._zoomAutoTarget.toFixed(3)
                 + " azLog=" + mapView._autoZoomLog
                 + " mpp=" + mapView.metersPerPixel.toFixed(5)
                 + " pxR=" + mapView.pixelRatio
                 + " mapH=" + mapView.height
                 + " dist=" + ((activeModel.pos_speed_kmh/3.6)*appSettings.autoZoomSecs).toFixed(1)
                 + " zoom=" + mapView.zoomLevel.toFixed(3)
                 + "\n")
    }

    // Escribe datos de ruta/sim en navius_route cada 2s cuando está navegando o en sim
    Timer {
        interval: 2000; repeat: true
        running: root._navActive || appSettings.simMode
        onTriggered: {
            var nb = navBar
            var dist = (nb && root._navActive) ? Math.round(nb._distKm * 1000) : -1
            var eta  = (nb && root._navActive) ? Math.round(nb._timeSec)       : -1
            var lim  = (nb && root._navActive) ? Math.round(nb._speedLimit)    : 0
            var spd  = Math.round(activeModel.pos_speed_kmh)
            var man  = ""
            if (nb && nb._step >= 0 && root._navData && root._navData.maneuvers) {
                var m = root._navData.maneuvers[nb._step]
                if (m) man = m.instruction || ""
            }
            var obj = '{"active":' + root._navActive
                    + ',"dist_m":' + dist
                    + ',"eta_s":' + eta
                    + ',"limit_kmh":' + lim
                    + ',"speed_kmh":' + spd
                    + ',"lat":' + activeModel.pos_lat.toFixed(6)
                    + ',"lon":' + activeModel.pos_lon.toFixed(6)
                    + ',"sim_mode":' + appSettings.simMode
                    + ',"sim_route_idx":' + appSettings.simRouteIdx
                    + ',"sim_seg":' + gpsSource.simIdx
                    + ',"sim_total":' + (root.simRoute ? root.simRoute.length : 0)
                    + ',"dests":' + JSON.stringify(root._navDests)
                    + ',"maneuver":' + JSON.stringify(man) + '}'
            var xhr = new XMLHttpRequest()
            xhr.open("PUT", root._routePath)
            xhr.send(obj + "\n")
            if (appSettings.debugMode && root._traceLines.length > 0) {
                var txhr = new XMLHttpRequest()
                txhr.open("PUT", root._sessionTracePath)
                txhr.send(root._traceLines)
            }
        }
    }

    // Limpia tráfico y navius_route al salir de navegación
    Connections {
        target: root
        function onNavActiveChanged() {
            if (!root._navActive) root._clearTrafficComparison()
            if (!root._navActive) {
                var xhr2 = new XMLHttpRequest()
                xhr2.open("PUT", root._routePath)
                xhr2.send('{"active":false}\n')
            }
        }
    }

    Timer {
        interval: 2000; repeat: true; running: appSettings.debugMode
        onTriggered: root._writeAck("auto")
    }

    function _execCmd(cmd) {
        if      (cmd === "2d")       {
            if (root._navActive) appSettings.navMapMode = "2d"; else appSettings.mapMode = "2d"
            root._applyMapMode("2d")
        }
        else if (cmd === "3d")       {
            if (root._navActive) appSettings.navMapMode = "3d"; else appSettings.mapMode = "3d"
            root._applyMapMode("3d")
        }
        else if (cmd === "north")    { appSettings.bearingMode = "north"; mapView.animateBearing(0) }
        else if (cmd === "heading")  {
            appSettings.bearingMode = "heading"; mapView.followMode = true
            mapView.animateBearing(root._hasArrow ? root._dispHeadRad * 180 / Math.PI : 0)
        }
        else if (cmd === "follow")   { mapView.followMode = true }
        else if (cmd === "dbg")      { root._dbgVisible = !root._dbgVisible }
        else if (cmd === "pause")    { root.simPaused = true }
        else if (cmd === "resume")   { root.simPaused = false }
        else if (cmd === "testpoi")  {
            root._testPoiLat = mapView._centerLat
            root._testPoiLon = mapView._centerLon
            root._testPoiVisible = !root._testPoiVisible
            if (mapView._layersInit) {
                var tvis = root._testPoiVisible ? "visible" : "none"
                mapView.setLayoutProperty("test-poi-dot", "visibility", tvis)
                if (root._testPoiVisible)
                    mapView.updateSourcePoint("test-poi",
                        QtPositioning.coordinate(root._testPoiLat, root._testPoiLon))
            }
        }
        else if (cmd === "poi")      {
            root._dbgPoi = !root._dbgPoi
            var vis = root._dbgPoi ? "visible" : "none"
            mapView.setLayoutProperty("dbg-center-dot", "visibility", vis)
            mapView.setLayoutProperty("dbg-gps-dot",    "visibility", vis)
            mapView.setLayoutProperty("dbg-N-dot",      "visibility", vis)
            mapView.setLayoutProperty("dbg-S-dot",      "visibility", vis)
            mapView.setLayoutProperty("dbg-E-dot",      "visibility", vis)
            mapView.setLayoutProperty("dbg-W-dot",      "visibility", vis)
        }
        else if (cmd === "shot")     {
            root.grabToImage(function(result) { result.saveToFile(root._shotPath) })
        }
        else if (cmd.indexOf("pitch") === 0) {
            var rest = cmd.substring(5)
            var newP
            if (rest[0] === "+") newP = mapView.pitch + parseFloat(rest.substring(1))
            else if (rest[0] === "-") newP = mapView.pitch - parseFloat(rest.substring(1))
            else newP = parseFloat(rest)
            newP = Math.max(0, Math.min(85, newP))
            mapView.pitch = newP
        }
        else if (cmd.indexOf("bear") === 0) {
            var brest = cmd.substring(4)
            var newB
            if (brest[0] === "+") newB = mapView.bearing + parseFloat(brest.substring(1))
            else if (brest[0] === "-") newB = mapView.bearing - parseFloat(brest.substring(1))
            else newB = parseFloat(brest)
            mapView._bearingAuto = true
            mapView.bearing = ((newB % 360) + 360) % 360
            mapView._bearingAuto = false
        }
        else if (cmd.indexOf("zoom") === 0) {
            var zrest = cmd.substring(4)
            var newZ
            if (zrest[0] === "+") newZ = mapView.zoomLevel + parseFloat(zrest.substring(1))
            else if (zrest[0] === "-") newZ = mapView.zoomLevel - parseFloat(zrest.substring(1))
            else newZ = parseFloat(zrest)
            newZ = Math.max(8, Math.min(20, newZ))
            mapView.setZoomLevel(newZ, Qt.point(mapView.width / 2, mapView.height / 2))
        }
        else if (cmd.indexOf("fov") === 0) {
            var newFov = parseFloat(cmd.substring(3))
            if (!isNaN(newFov)) mapView._fovAngle = Math.max(5, Math.min(70, newFov))
            if (mapView.followMode) {
                mapView._gpsUpdating = true
                mapView.center = mapView._navFollowCenter(mapView._dispLat, mapView._dispLon)
                mapView._gpsUpdating = false
            }
        }
        else if (cmd === "posoff") {
            appSettings.manualPosActive = false
        }
        else if (cmd.indexOf("azsecs") === 0) {
            var azVal = parseInt(cmd.substring(6))
            if (!isNaN(azVal) && azVal >= 5 && azVal <= 120)
                appSettings.autoZoomSecs = azVal
        }
        else if (cmd.indexOf("simbias") === 0) {
            var sbVal = parseInt(cmd.substring(7))
            if (!isNaN(sbVal)) root.simSpeedBias = Math.max(-90, Math.min(500, sbVal))
        }
        else if (cmd === "routeview") {
            if (routeViewPanel.visible) routeViewPanel.close()
            else                        routeViewPanel.open()
        }
        else if (cmd.indexOf("simroute") === 0) {
            var srIdx = parseInt(cmd.substring(8))
            if (!isNaN(srIdx) && srIdx >= 0 && srIdx <= 4) {
                if (!appSettings.simMode) appSettings.simMode = true
                root._navActive  = false
                root._navData    = null
                gpsSource.simStop()
                root._applySimRoute(srIdx)
            }
        }
        else if (cmd === "tts") {
            navTts.say("En quinientos metros, gire a la derecha")
        }
        else if (cmd.indexOf("pos") === 0) {
            var posRest2 = cmd.substring(3)
            var posCoords = posRest2.split(",")
            if (posCoords.length >= 2) {
                var posLat2 = parseFloat(posCoords[0])
                var posLon2 = parseFloat(posCoords[1])
                if (!isNaN(posLat2) && !isNaN(posLon2)) {
                    appSettings.manualLat = posLat2
                    appSettings.manualLon = posLon2
                    appSettings.manualPosActive = true
                    mapView.followMode = true
                    mapView._gpsUpdating = true
                    mapView.center = QtPositioning.coordinate(posLat2, posLon2)
                    mapView._gpsUpdating = false
                    mapView.updateGPS(posLat2, posLon2, 5.0)
                }
            }
        }
    }

    // Lee navius_cmd cada 400ms. Soporta un comando por línea (batch) o formato
    // legado (<cmd>\n<epoch>). El fichero completo sirve como clave de dedup.
    // Formato batch: primera línea = epoch (>1e9), líneas siguientes = comandos.
    // Formato legado: primera línea = "<cmd>" (o "<epoch> <cmd>").
    Timer {
        interval: 400; repeat: true; running: appSettings.debugMode
        onTriggered: {
            var xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                var content = xhr.responseText.trim()
                if (content === "" || content === root._lastCmdKey) return
                root._lastCmdKey = content

                var lines = content.split("\n")
                var cmds = []
                var firstLine = lines[0].trim()

                // Batch: línea 0 es timestamp epoch (> 1e9)
                if (!isNaN(parseInt(firstLine)) && parseInt(firstLine) > 1000000000) {
                    for (var ci = 1; ci < lines.length; ci++) {
                        var cl = lines[ci].trim()
                        if (cl !== "") cmds.push(cl)
                    }
                } else {
                    // Legado: "<epoch> <cmd>" o solo "<cmd>"
                    var spIdx = firstLine.indexOf(" ")
                    var cmd0 = (spIdx > 0 && !isNaN(firstLine.substring(0, spIdx)))
                               ? firstLine.substring(spIdx + 1).trim()
                               : firstLine
                    if (cmd0 !== "") cmds.push(cmd0)
                }

                for (var di = 0; di < cmds.length; di++)
                    root._execCmd(cmds[di])

                root._writeAck(cmds.join("|") || "?")
            }
            xhr.open("GET", root._cmdBase + "/navius_cmd")
            xhr.send()
        }
    }

    // ── Debug POI markers ─────────────────────────────────────────────────
    // Yellow = map centre (should appear at screen centre).
    // Red    = exact GPS position (should appear at _cy = height - gu(19)).
    // Green/Cyan/Orange/White = cardinal points 100m N/E/S/W from GPS.
    // All toggled by the "poi" file command; updated continuously when active.
    property bool _dbgPoi: false
    readonly property real _poiDistM: 100   // metres for cardinal POIs

    property bool _testPoiVisible: false
    property real _testPoiLat: 0
    property real _testPoiLon: 0

    Timer {
        interval: 200; repeat: true; running: root._dbgPoi
        onTriggered: {
            if (mapView._dispLat === 0 && mapView._dispLon === 0) return
            var lat = mapView._dispLat, lon = mapView._dispLon
            var dLat = _poiDistM / 111319
            var dLon = _poiDistM / (111319 * Math.cos(lat * Math.PI / 180))
            mapView.updateSourcePoint("dbg-center",
                QtPositioning.coordinate(mapView._centerLat, mapView._centerLon))
            mapView.updateSourcePoint("dbg-gps",
                QtPositioning.coordinate(lat, lon))
            mapView.updateSourcePoint("dbg-N", QtPositioning.coordinate(lat + dLat, lon))
            mapView.updateSourcePoint("dbg-S", QtPositioning.coordinate(lat - dLat, lon))
            mapView.updateSourcePoint("dbg-E", QtPositioning.coordinate(lat, lon + dLon))
            mapView.updateSourcePoint("dbg-W", QtPositioning.coordinate(lat, lon - dLon))
        }
    }

    // ── Debug POI screen overlay ──────────────────────────────────────────
    // Crosshairs drawn in QML at the EXPECTED screen positions of each debug
    // map marker, using the same perspective formula as _navFollowCenter.
    // If formula + map rendering are consistent, crosshair and dot coincide.
    // Colors match the MapLibre dots: yellow=center, red=GPS,
    // green=N, salmon=S, cyan=E, orange=W.
    Item {
        id: dbgPoiScreenOverlay
        visible: root._dbgPoi && !satPanel.visible && !prefsPanel.visible
        anchors.fill: parent
        z: 3

        // Forward-project geo (poi_lat, poi_lon) → screen Qt.point.
        // Heading-up 3D follow mode: exact perspective formula.
        // All other modes: 2D linear projection from map centre.
        function _pt(poi_lat, poi_lon) {
            var mpp = mapView.metersPerPixel
            if (mpp <= 0 || (mapView._dispLat === 0 && mapView._dispLon === 0))
                return Qt.point(-9999, -9999)
            var B = mapView.bearing * Math.PI / 180
            if (appSettings.bearingMode !== "heading" || !mapView.followMode
                    || mapView.pitch < 1) {
                var dNc = (poi_lat - mapView._centerLat) * 111319.49
                var dEc = (poi_lon - mapView._centerLon) * 111319.49
                          * Math.cos(mapView._centerLat * Math.PI / 180)
                return Qt.point(
                    mapView.width  / 2 + (dEc * Math.cos(B) - dNc * Math.sin(B)) / mpp,
                    mapView.height / 2 - (dEc * Math.sin(B) + dNc * Math.cos(B)) / mpp)
            }
            var dN = (poi_lat - mapView._dispLat) * 111319.49
            var dE = (poi_lon - mapView._dispLon) * 111319.49
                     * Math.cos(mapView._dispLat * Math.PI / 180)
            var P    = mapView.pitch * Math.PI / 180
            var cosP = Math.cos(P), sinP = Math.sin(P)
            var dFwd   =  dN * Math.cos(B) + dE * Math.sin(B)
            var dRight = -dN * Math.sin(B) + dE * Math.cos(B)
            // focal length; same constant as _navFollowCenter
            var f   = mapView.height / (2 * Math.tan(mapView._fovAngle * Math.PI / 180))
            // GPS offset from map centre (metres, in heading-forward direction)
            var pxA = (mapView.height - units.gu(19)) - mapView.height / 2
            var dG  = pxA * mpp / (cosP + pxA * sinP / f)
            // POI offset from map centre (pivot model: same denominator for x and y)
            var dP  = dG - dFwd
            var dnm = f * mpp - dP * sinP
            if (Math.abs(dnm) < 1e-6)
                return Qt.point(-9999, -9999)
            return Qt.point(
                mapView.width  / 2 + f * dRight / dnm,
                mapView.height / 2 + f * dP * cosP / dnm)
        }

        property real _dLat: root._poiDistM / 111319.49
        property real _dLon: mapView._dispLat !== 0
            ? root._poiDistM / (111319.49 * Math.cos(mapView._dispLat * Math.PI / 180))
            : 0

        property point _ptN: _pt(mapView._dispLat + _dLat, mapView._dispLon)
        property point _ptS: _pt(mapView._dispLat - _dLat, mapView._dispLon)
        property point _ptE: _pt(mapView._dispLat,          mapView._dispLon + _dLon)
        property point _ptW: _pt(mapView._dispLat,          mapView._dispLon - _dLon)

        // Yellow crosshair: map centre (should match the yellow MapLibre dot)
        Item {
            x: mapView.width / 2 - units.gu(2.5); y: mapView.height / 2 - units.gu(2.5)
            width: units.gu(5); height: units.gu(5)
            Rectangle { anchors.centerIn: parent; width: parent.width; height: units.gu(0.6); color: "#FFD700" }
            Rectangle { anchors.centerIn: parent; width: units.gu(0.6); height: parent.height; color: "#FFD700" }
            Label { anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    text: "C"; color: "#FFD700"; font.pixelSize: units.gu(1.2 * appSettings.textScale) }
        }
        // Red crosshair: GPS position (should match the red MapLibre dot + the arrow tip)
        Item {
            x: posOverlayRoot._cx - units.gu(2.5); y: posOverlayRoot._cy - units.gu(2.5)
            width: units.gu(5); height: units.gu(5)
            Rectangle { anchors.centerIn: parent; width: parent.width; height: units.gu(0.6); color: "#FF1744" }
            Rectangle { anchors.centerIn: parent; width: units.gu(0.6); height: parent.height; color: "#FF1744" }
            Label { anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    text: "G"; color: "#FF1744"; font.pixelSize: units.gu(1.2 * appSettings.textScale) }
        }
        // Green crosshair: 100m north of GPS
        Item {
            x: dbgPoiScreenOverlay._ptN.x - units.gu(2.5); y: dbgPoiScreenOverlay._ptN.y - units.gu(2.5)
            width: units.gu(5); height: units.gu(5)
            Rectangle { anchors.centerIn: parent; width: parent.width; height: units.gu(0.6); color: "#00E676" }
            Rectangle { anchors.centerIn: parent; width: units.gu(0.6); height: parent.height; color: "#00E676" }
            Label { anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    text: "N"; color: "#00E676"; font.pixelSize: units.gu(1.2 * appSettings.textScale) }
        }
        // Salmon crosshair: 100m south of GPS
        Item {
            x: dbgPoiScreenOverlay._ptS.x - units.gu(2.5); y: dbgPoiScreenOverlay._ptS.y - units.gu(2.5)
            width: units.gu(5); height: units.gu(5)
            Rectangle { anchors.centerIn: parent; width: parent.width; height: units.gu(0.6); color: "#FF5252" }
            Rectangle { anchors.centerIn: parent; width: units.gu(0.6); height: parent.height; color: "#FF5252" }
            Label { anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    text: "S"; color: "#FF5252"; font.pixelSize: units.gu(1.2 * appSettings.textScale) }
        }
        // Cyan crosshair: 100m east of GPS
        Item {
            x: dbgPoiScreenOverlay._ptE.x - units.gu(2.5); y: dbgPoiScreenOverlay._ptE.y - units.gu(2.5)
            width: units.gu(5); height: units.gu(5)
            Rectangle { anchors.centerIn: parent; width: parent.width; height: units.gu(0.6); color: "#00E5FF" }
            Rectangle { anchors.centerIn: parent; width: units.gu(0.6); height: parent.height; color: "#00E5FF" }
            Label { anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    text: "E"; color: "#00E5FF"; font.pixelSize: units.gu(1.2 * appSettings.textScale) }
        }
        // Orange crosshair: 100m west of GPS
        Item {
            x: dbgPoiScreenOverlay._ptW.x - units.gu(2.5); y: dbgPoiScreenOverlay._ptW.y - units.gu(2.5)
            width: units.gu(5); height: units.gu(5)
            Rectangle { anchors.centerIn: parent; width: parent.width; height: units.gu(0.6); color: "#FF9100" }
            Rectangle { anchors.centerIn: parent; width: units.gu(0.6); height: parent.height; color: "#FF9100" }
            Label { anchors { top: parent.bottom; horizontalCenter: parent.horizontalCenter }
                    text: "W"; color: "#FF9100"; font.pixelSize: units.gu(1.2 * appSettings.textScale) }
        }
    }

    // ── Recibir coordenadas compartidas desde otras apps (esquema geo:) ───────
    function _showSharedLocation(lat, lon, name) {
        if (isNaN(lat) || isNaN(lon)) return
        if (Math.abs(lat) > 90 || Math.abs(lon) > 180) return
        sharedLocationDialog.lat     = lat
        sharedLocationDialog.lon     = lon
        sharedLocationDialog.locName = name || i18n.tr("Ubicación compartida")
        sharedLocationDialog.navActive = root._navActive
        sharedLocationDialog.hasDests  = searchPanel._dests.length > 0
        sharedLocationDialog.debugMode = appSettings.debugMode
        sharedLocationDialog.visible   = true
    }

    function _parseSharedText(text) {
        text = text.trim()

        // geo:lat,lon o geo:lat,lon?q=nombre
        if (text.indexOf("geo:") === 0) {
            var geoBody = text.substring(4)
            var geoName = ""
            if (geoBody.indexOf("?") !== -1) {
                var qStr = geoBody.split("?")[1]
                geoBody  = geoBody.split("?")[0]
                var qIdx = qStr.indexOf("q=")
                if (qIdx !== -1) geoName = decodeURIComponent(qStr.substring(qIdx + 2).split("&")[0])
            }
            var geo = geoBody.split(",")
            if (geo.length >= 2) root._showSharedLocation(parseFloat(geo[0]), parseFloat(geo[1]), geoName)
            return
        }

        // Google Maps: https://maps.google.com/maps?q=lat,lon
        //              https://www.google.com/maps/@lat,lon,zoom
        //              https://goo.gl/maps/... (URL corta — ignorar)
        var gmatch = text.match(/[?@,/](-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)/)
        if (gmatch) {
            root._showSharedLocation(parseFloat(gmatch[1]), parseFloat(gmatch[2]), "")
            return
        }

        // Texto plano: "lat,lon"
        var parts = text.split(",")
        if (parts.length >= 2) {
            var lt = parseFloat(parts[0].trim()), ln = parseFloat(parts[1].trim())
            if (!isNaN(lt) && !isNaN(ln)) root._showSharedLocation(lt, ln, "")
        }
    }

    // Recepción de contenido compartido: ver sharedUri + Component.onCompleted
    // más arriba (esquema geo:, gestionado por main.rs/el .desktop).

    ServerFallbackDialog {
        id: serverFallbackDialog
        anchors.fill: parent
        z: 25
        onUseOsmScout: {
            _detecting = true
            NavSearch.pingOsmScout(function(alive) {
                if (alive) {
                    _detecting = false
                    root._osmScoutActive = true
                    _setEffectiveUrl("http://127.0.0.1:8553/v2")
                    serverFallbackDialog.visible = false
                    serverFallbackDialog.retryRequested()
                } else {
                    NavSearch.detectOsmScout(function(found) {
                        _detecting = false
                        if (found) {
                            root._osmScoutActive = true
                            _setEffectiveUrl("http://127.0.0.1:8553/v2")
                            serverFallbackDialog.visible = false
                            serverFallbackDialog.retryRequested()
                        } else {
                            _osmNotFound = true
                        }
                    }, true)  // autoLaunch: el usuario pulsó "usar OSM Scout" explícitamente
                }
            })
        }
        onCancelled: serverFallbackDialog.visible = false
    }

    OsmScoutDialog {
        id: osmScoutDialog
        textScale: appSettings.textScale
        anchors { left: parent.left; right: parent.right; bottom: statusBar.top }
        z: 22
        onCancelled: {
            osmScoutDialog.visible = false
            osmScoutPollTimer.stop()
            root._startupMsg = ""
            _setEffectiveUrl(appSettings.valhallaUrl)
            // Desbloquear: si hay petición pendiente se dispara ahora hacia el servidor público
            NavSearch.setRouteBlocked(false)
            searchPanel.setRouteBlocked(false)
        }
    }

    TrafficRouteDialog {
        id: trafficRouteDialog
        textScale: appSettings.textScale
        anchors { left: parent.left; right: parent.right; bottom: statusBar.top }
        z: 22
        onRouteAccepted: {
            var altRoute = root._trafficAltRoute
            root._clearTrafficComparison()
            root._startNavigation(altRoute)
            trafficCheckTimer.restart()
        }
        onRouteRejected: root._clearTrafficComparison()
    }

    // GoogleMapsPanel (búsqueda vía Google Maps embebido) no se porta: usa
    // QtWebEngine, que en postmarketOS solo existe para Qt6 (esta app es Qt5).
    // Ver onGoogleMapsRequested/onGoogleMapsCacheClearRequested más arriba.

    WhatsNewDialog {
        id: whatsNewDialog
        textScale: appSettings.textScale
        showAtStartup: appSettings.showChangesAtStartup
    }

    SharedLocationDialog {
        id: sharedLocationDialog
        textScale: appSettings.textScale
        onDismissed: sharedLocationDialog.visible = false
        onDestRequested: function(lat, lon, name) {
            sharedLocationDialog.visible = false
            searchPanel.addDest(lat, lon, name)
            searchPanel.addToHistory(lat, lon, name)
            if (root._navActive) {
                var newDests = root._navDests.slice()
                newDests.push({ lat: lat, lon: lon, name: name })
                root._navDests = newDests
                var wps = [_originWp(activeModel.pos_lat, activeModel.pos_lon)]
                for (var wi = 0; wi < root._navDests.length; wi++) wps.push(root._navDests[wi])
                NavSearch.route(wps, root._navOpts, function(err, routes) {
                    if (!root._navActive) return
                    if (err || !routes || routes.length === 0) return
                    root.drawRoute(routes, 0)
                    root._navData        = routes[0]
                    gpsSource.routeShape = routes[0].shape
                    gpsSource._shapeIdx  = 0
                    gpsSource._shapeFrac = 0
                    mapView.followMode = true
                })
            } else {
                prefsPanel.visible  = false
                satPanel.visible    = false
                searchPanel.visible = true
            }
        }
        onOriginRequested: function(lat, lon, name) {
            sharedLocationDialog.visible = false
            searchPanel.addToHistory(lat, lon, name)
            searchPanel.setSimOrigin(lat, lon, name)
        }
        onWaypointRequested: function(lat, lon, name) {
            sharedLocationDialog.visible = false
            searchPanel.insertDestFirst(lat, lon, name)
            searchPanel.addToHistory(lat, lon, name)
            var newDests = root._navDests.slice()
            newDests.unshift({ lat: lat, lon: lon, name: name })
            root._navDests = newDests
            var wps = [_originWp(activeModel.pos_lat, activeModel.pos_lon)]
            for (var wi = 0; wi < root._navDests.length; wi++) wps.push(root._navDests[wi])
            NavSearch.route(wps, root._navOpts, function(err, routes) {
                if (!root._navActive) return
                if (err || !routes || routes.length === 0) return
                root.drawRoute(routes, 0)
                root._navData        = routes[0]
                gpsSource.routeShape = routes[0].shape
                gpsSource._shapeIdx  = 0
                gpsSource._shapeFrac = 0
                mapView.followMode = true
            })
        }
    }

    // ── Banner "¿Has llegado a X?" — confirmación manual de llegada al leg activo ──
    // En replay, si no se responde en 8 s se auto-acepta (para no atascar la reproducción).
    Timer {
        id: legArrivalReplayTimer
        interval: 8000; repeat: false
        onTriggered: {
            if (legArrivalBanner.visible) {
                legArrivalBanner.visible = false
                navBar.confirmLegArrival()
            }
        }
    }
    Rectangle {
        id: legArrivalBanner
        visible: false
        property int    _legIdx:  -1
        property bool   _isFinal: false
        property string _name:    ""
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter
                  bottomMargin: units.gu(10) }
        width: Math.min(parent.width * 0.9, units.gu(50))
        height: units.gu(8.5)
        radius: units.gu(1.2)
        color: "#CC071120"; border.color: "#66BB6A"; border.width: 1
        z: 51
        Column {
            anchors { fill: parent; margins: units.gu(1.2) }
            spacing: units.gu(0.8)
            Label {
                width: parent.width
                text: "🏁 " + i18n.tr("¿Has llegado a") + " "
                      + (legArrivalBanner._name.length > 0 ? legArrivalBanner._name : i18n.tr("el destino")) + "?"
                color: "#A5D6A7"; font.pixelSize: units.gu(1.9 * appSettings.textScale)
                elide: Text.ElideRight
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: units.gu(1.5)
                Rectangle {
                    width: units.gu(13); height: units.gu(4.5); radius: height / 2; color: "#2E7D32"
                    Label { anchors.centerIn: parent; text: i18n.tr("Sí, he llegado")
                            color: "white"; font.pixelSize: units.gu(1.8 * appSettings.textScale); font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: {
                        legArrivalReplayTimer.stop()
                        legArrivalBanner.visible = false
                        navBar.confirmLegArrival()
                    } }
                }
                Rectangle {
                    width: units.gu(11); height: units.gu(4.5); radius: height / 2
                    color: "#1E2A3A"; border.color: "#90A4AE"; border.width: 1
                    Label { anchors.centerIn: parent; text: i18n.tr("Todavía no")
                            color: "#B0BEC5"; font.pixelSize: units.gu(1.8 * appSettings.textScale) }
                    MouseArea { anchors.fill: parent; onClicked: {
                        legArrivalReplayTimer.stop()
                        legArrivalBanner.visible = false
                        if (appSettings.simMode) root.simPaused = false
                        navBar.dismissLegArrival()
                    } }
                }
            }
        }
    }

    Rectangle {
        id: todoArrivalBanner
        visible: false
        property int    _wpIdx:  -1
        property string _wpName: ""
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter
                  bottomMargin: units.gu(10) }
        width: Math.min(parent.width * 0.88, units.gu(48))
        height: units.gu(7.5)
        radius: units.gu(1.2)
        color: "#CC071120"; border.color: "#26C6DA"; border.width: 1
        z: 50
        Row {
            anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
            spacing: units.gu(1)
            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - units.gu(17) - units.gu(2)
                text: "📋 " + (todoArrivalBanner._wpName.length > 0
                      ? todoArrivalBanner._wpName : i18n.tr("Tareas pendientes"))
                color: "#26C6DA"; font.pixelSize: units.gu(1.9 * appSettings.textScale)
                elide: Text.ElideRight
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(10); height: units.gu(5.5); radius: height / 2
                color: openTaskMa.pressed ? "#0D3F4F" : "#0A2A35"
                border.color: "#26C6DA"; border.width: 1
                Label { anchors.centerIn: parent; text: i18n.tr("Abrir")
                        color: "#26C6DA"; font.pixelSize: units.gu(2.0 * appSettings.textScale); font.bold: true }
                MouseArea {
                    id: openTaskMa; anchors.fill: parent
                    onClicked: {
                        todoArrivalBanner.visible = false
                        stopTodoPanel.openAtWaypoint(todoArrivalBanner._wpIdx)
                    }
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(5.5); height: units.gu(5.5); radius: height / 2
                color: "#1E2A3A"; border.color: "#90A4AE"; border.width: 1
                Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: units.gu(2.0 * appSettings.textScale) }
                MouseArea { anchors.fill: parent; onClicked: todoArrivalBanner.visible = false }
            }
        }
    }

    // ── Banner "¿Guardar aparcamiento?" al llegar al destino ─────────────────
    Timer {
        id: parkSaveOfferTimer
        interval: 15000; repeat: false
        onTriggered: parkSaveOffer.visible = false
    }
    Rectangle {
        id: parkSaveOffer
        visible: false
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: units.gu(10) }
        width: Math.min(parent.width * 0.88, units.gu(48))
        height: rowPark.implicitHeight + units.gu(2.5)
        radius: units.gu(1.2)
        color: "#CC1A1A2E"; border.color: "#FF9800"; border.width: 1
        z: 50
        Row {
            id: rowPark
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
            spacing: units.gu(1)
            Label {
                text: i18n.tr("🅿 ¿Guardar aparcamiento aquí?")
                color: "#FF9800"; font.pixelSize: units.gu(2.0 * appSettings.textScale)
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                width: parent.width - units.gu(22)
            }
            Rectangle {
                width: units.gu(10); height: units.gu(5.5); radius: height / 2; color: "#FF9800"
                anchors.verticalCenter: parent.verticalCenter
                Label { anchors.centerIn: parent; text: i18n.tr("Guardar"); color: "#0A0A1A"; font.pixelSize: units.gu(2.0 * appSettings.textScale); font.bold: true }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        parkSaveOffer.visible = false; parkSaveOfferTimer.stop()
                        var lat = gpsSource.hasFix ? gpsSource.lat : appSettings.lastLat
                        var lon = gpsSource.hasFix ? gpsSource.lon : appSettings.lastLon
                        vehicleManager.savePark(lat, lon)
                        root._updateParkingMarkers()
                        root._startupMsg = i18n.tr("🅿 Aparcamiento guardado")
                        startupMsgTimer.restart()
                    }
                }
            }
            Rectangle {
                width: units.gu(9); height: units.gu(5.5); radius: height / 2; color: "#1E2A3A"
                border.color: "#90A4AE"; border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                Label { anchors.centerIn: parent; text: "No"; color: "#90A4AE"; font.pixelSize: units.gu(2.0 * appSettings.textScale) }
                MouseArea { anchors.fill: parent; onClicked: { parkSaveOffer.visible = false; parkSaveOfferTimer.stop() } }
            }
        }
    }

    // ── Pantalla de carga ─────────────────────────────────────────────────────
    Rectangle {
        id: loadingScreen
        anchors.fill: parent
        color: "#07111E"
        z: 9000
        visible: opacity > 0
        opacity: (mapView._tileBusy && !root._initialLoadDone) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

        Column {
            anchors.centerIn: parent
            spacing: units.gu(4)

            NaviusLogo {
                anchors.horizontalCenter: parent.horizontalCenter
                size: units.gu(5)
            }

            // Spinner estilo Ubuntu Touch: arco azul girando
            Canvas {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(5); height: units.gu(5)
                Component.onCompleted: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var cx = width / 2, cy = height / 2
                    var r  = width / 2 - units.gu(0.3)
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, -Math.PI / 2, Math.PI)
                    ctx.strokeStyle = "#29B6F6"
                    ctx.lineWidth   = units.gu(0.35)
                    ctx.lineCap     = "round"
                    ctx.stroke()
                }
                RotationAnimator on rotation {
                    from: 0; to: 360
                    duration: 1100
                    loops: Animation.Infinite
                    running: loadingScreen.visible
                }
            }
        }
    }
}
