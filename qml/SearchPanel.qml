import QtQuick 2.7
import QtQuick.Controls 2.15
import Qt.labs.settings 1.0
import QtQuick.LocalStorage 2.0
import "NavSearch.js" as NavSearch
import "TodoDB.js" as TodoDB

Rectangle {
    id: panel
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    color: "#0D0D1A"
    z: 10
    visible: false

    // ── API pública ────────────────────────────────────────────────────────
    property real gpsLat: 0
    property real gpsLon: 0
    property bool hasFix: false
    property bool simMode: false
    property bool imperial: false
    property bool isLandscape: false
    property var    fileLogger:  null
    property var    navHttp:     null
    property bool   navActive:    false
    property var    navShape:     null
    property real   navSpeedKmh:  0
    property string poiMode:      "cerca"   // "cerca" | "en_ruta" | "destino"
    property int    poiMinutes:   10        // 5 | 10 | 20

    readonly property int _poiRadiusM: poiMinutes === 5 ? 4000 : poiMinutes === 10 ? 8000 : 15000

    onNavActiveChanged: { poiMode = navActive ? "en_ruta" : "cerca" }

    property var  _simOrigin: null      // {lat, lon, name} — origen personalizado en modo sim
    property bool _settingOrigin: false // true mientras buscamos el punto de inicio

    onHasFixChanged: { if (hasFix && _pendingCalc) { _pendingCalc = false; _calcRoute(true) } }

    signal closed()
    signal routeReady(var routes, int selIdx)
    signal navigationStarted(var routeData)
    signal previewRequested(var routes, int selIdx)
    signal googleMapsRequested()
    signal serverFallbackNeeded(string service, string message, var retryFn)

    onVisibleChanged: {
        if (visible) { _st = "idle" }
        else { Qt.inputMethod.hide(); _pendingCalc = false }
    }

    // ── Estado interno ─────────────────────────────────────────────────────
    property string _st: "idle"     // idle | results | routing | routed
    property bool _pendingCalc: false
    property bool _searching: false
    property string _searchErr: ""
    property var    _results:  []
    property string _poiType:  ""
    property string _mineturDate: ""
    property var _dests:     []     // [{lat, lon, name, todos:[{text,done}]}, ...]  waypoints del usuario
    property int _todoEditIdx: -1   // índice del waypoint cuyo editor TODO está abierto
    property var _routes:    []     // alternativas calculadas
    property int _selRoute:  0
    property bool _noTolls:   false
    property bool _noFerry:   false
    property bool _noDirt:    false
    property bool _noHighway: false
    property var  _logLines:   []     // log de actividad de red

    // Expuesto para recálculo de ruta en Main.qml
    property var dests:     _dests
    property var routeOpts: ({"no_tolls": _noTolls, "no_ferry": _noFerry, "no_dirt": _noDirt, "no_highway": _noHighway})
    property bool _logVisible:    false  // bool explícito para evitar problemas con var.length en bindings
    property bool _logCollapsed: false

    property var _history:   []
    property var _favorites: []
    property var _favPending: null   // {lat, lon, name, address} mientras el diálogo está abierto
    property real _kbdH: 0
    Behavior on _kbdH { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    property Item _kbdFocusItem: null
    property bool _favsExpanded: true
    property bool _histExpanded: true
    property bool _poiExpanded:  false
    property var  _pastTodos:      []    // TODOs anteriores cargados para el destino en edición
    property bool _pastTodosOpen:  false // sección "Anteriores" desplegada
    property int  _movingDestIdx:  -1   // índice de _dests del TODO que se está moviendo
    property int  _movingTodoIdx:  -1   // índice del TODO dentro de ese destino

    // Hora de salida (session-only, no se persiste)
    property bool _useDepTime:   false
    property int  _depDayOffset: 0       // 0=hoy, 1=mañana, ...
    property int  _depHour:      8
    property int  _depMin:       0

    // Planes guardados
    property var _savedPlans: []

    property bool restoreNav: false   // set true by Main.qml if was navigating at exit
    property int  completedLegs: 0    // tramos confirmados; sincronizado desde navBar._completedLegs por Main

    function setNavUrl(url)              { NavSearch.setValhallaUrl(url) }
    // NavSearch.js NO es .pragma library, así que cada componente que lo importa
    // tiene SU copia de las variables. Main.qml no puede poner el interruptor
    // por nosotros: hay que reenviarlo, igual que se hace con setNavUrl. Sin
    // esto, la búsqueda y los POIs se quedaban sin respaldo local aunque el
    // servidor estuviera detectado.
    function setOsmScoutSearch(ok)       { NavSearch.setOsmScoutSearch(ok) }
    function setOffline(v)               { NavSearch.setOffline(v) }
    function setFallbackNavUrl(url)      { NavSearch.setFallbackUrl(url) }
    function setRouteBlocked(v)          { NavSearch.setRouteBlocked(v) }
    function setNaviusOverpassServer(en) { NavSearch.setNaviusServer(en) }
    function rerouteIfActive()      { if (_dests.length > 0) _calcRoute(false) }

    // Recalcula con el costing activo en NavSearch y llama callback(err, routes).
    // Usado desde RouteSelectPanel cuando el usuario cambia de vehículo.
    function rerouteForVehicle(callback) {
        if (_dests.length === 0) { callback(i18n.tr("Sin destino"), []); return }
        var wps = []
        if (panel.simMode && panel._simOrigin) {
            wps.push(panel._simOrigin)
        } else if (panel.gpsLat !== 0 || panel.gpsLon !== 0) {
            wps.push({lat: panel.gpsLat, lon: panel.gpsLon})
        } else {
            callback(i18n.tr("Sin GPS"), []); return
        }
        for (var i = completedLegs; i < _dests.length; i++) wps.push(_dests[i])
        if (wps.length < 2) { callback(i18n.tr("Sin destino"), []); return }
        var opts = {no_tolls: _noTolls, no_ferry: _noFerry, no_dirt: _noDirt, no_highway: _noHighway}
        NavSearch.route(wps, opts, function(err, routes) {
            if (!err && routes && routes.length > 0) {
                _routes = routes
                _selRoute = 0
                routeReady(_routes, 0)
            }
            callback(err, routes)
        })
    }

    // Carga los endpoints de una ruta de demo, calcula la ruta e inicia la navegación.
    // Llamado desde Main.qml cuando el usuario selecciona una ruta de test.
    function loadDemoRoute(originLat, originLon, originName, destLat, destLon, destName) {
        _simOrigin  = { lat: originLat, lon: originLon, name: originName }
        _dests      = [{ lat: destLat,  lon: destLon,  name: destName  }]
        _st         = "idle"
        _routes     = []
        _selRoute   = 0
        navSt.waypointsJson = JSON.stringify(_dests)
        _calcRoute(true)   // calcula ruta e inicia navegación automáticamente
    }

    // Cambia el punto de inicio de la ruta en curso (sin tocar el destino).
    // Muestra el panel para que el usuario vea el nuevo origen y el cálculo.
    function setSimOrigin(lat, lon, name) {
        _simOrigin = { lat: lat, lon: lon, name: name }
        _st        = "idle"
        _routes    = []
        _selRoute  = 0
        if (_dests.length > 0) {
            panel.visible = true
            _calcRoute(true)
        }
    }

    // Establece un único destino (descarta waypoints anteriores) sin abrir panel.
    function setDest(lat, lon, name) {
        _dests    = [{ lat: lat, lon: lon, name: name, todos: _latestTodos(lat, lon) }]
        _st       = "idle"
        _routes   = []
        _selRoute = 0
        _saveWaypoints()
    }

    // Expone _addToHistory públicamente para que Main.qml pueda añadir al historial.
    function addToHistory(lat, lon, name) { _addToHistory(lat, lon, name) }

    // Guarda los TODOs de una lista de destinos en la base de datos SQLite.
    // Llamado desde Main.qml al llegar al destino o al parar la navegación.
    function saveTodosToDb(dests) {
        if (!dests || dests.length === 0) return
        var dateStr = Qt.formatDate(new Date(), "yyyy-MM-dd")
        for (var i = 0; i < dests.length; i++) {
            var d = dests[i]
            if (!d.todos || d.todos.length === 0) continue
            var key = TodoDB.destKey(d.lat, d.lon)
            TodoDB.saveTodosForDest(key, d.name || "", d.todos, dateStr)
        }
    }

    // Carga TODOs anteriores del DB para el destino dado (lat, lon).
    function _loadPastTodos(lat, lon) {
        var key = TodoDB.destKey(lat, lon)
        _pastTodos = TodoDB.loadPastTodosForDest(key)
        _pastTodosOpen = _pastTodos.length > 0
    }

    // Devuelve los TODOs de la última sesión para un destino (para auto-poblar al añadir).
    function _latestTodos(lat, lon) {
        return TodoDB.loadLatestTodosForDest(TodoDB.destKey(lat, lon))
    }

    // Añade un destino al final de la lista de waypoints y persiste.
    function addDest(lat, lon, name) {
        var d = _dests.slice()
        d.push({ lat: lat, lon: lon, name: name, todos: _latestTodos(lat, lon) })
        _dests = d
        _saveWaypoints()
    }

    // Inserta un destino al principio (próxima parada inmediata).
    function insertDestFirst(lat, lon, name) {
        var d = _dests.slice()
        d.unshift({ lat: lat, lon: lon, name: name, todos: _latestTodos(lat, lon) })
        _dests = d
        _saveWaypoints()
    }

    // Elimina el destino en la posición idx (para marcar como completado durante la navegación).
    function removeDestAt(idx) {
        var d = _dests.slice()
        if (idx < 0 || idx >= d.length) return
        d.splice(idx, 1)
        _dests = d
        _saveWaypoints()
    }

    Settings {
        id: navSt
        category: "nav"
        property string waypointsJson: ""
        property bool   noTolls:   false
        property bool   noFerry:   false
        property bool   noDirt:    false
        property bool   noHighway: false
    }
    Settings { id: histSt;  category: "dest_history"; property string json: "" }
    Settings { id: favSt;   category: "favorites";    property string json: "" }
    Settings { id: planSt;  category: "saved_plans";  property string json: "" }
    Settings { id: uiSt;    category: "search_ui";    property bool favsExpanded: true; property bool histExpanded: true }

    TextInput { id: focusDummy; readOnly: true; width: 0; height: 0; visible: true }

    Component.onCompleted: {
        if (navSt.waypointsJson !== "") {
            try { _dests = JSON.parse(navSt.waypointsJson) } catch(e) {}
        }
        if (histSt.json !== "") {
            try { _history = JSON.parse(histSt.json) } catch(e) {}
        }
        if (favSt.json !== "") {
            try { _favorites = JSON.parse(favSt.json) } catch(e) {}
        }
        if (planSt.json !== "") {
            try { _savedPlans = JSON.parse(planSt.json) } catch(e) {}
        }
        TodoDB.init()
        _favsExpanded = uiSt.favsExpanded
        _histExpanded = uiSt.histExpanded
        _noTolls   = navSt.noTolls
        _noFerry   = navSt.noFerry
        _noDirt    = navSt.noDirt
        _noHighway = navSt.noHighway
        NavSearch.setLogCallback(function(msg) { panel._addLog(msg) })
        NavSearch.setFileLogCallback(function(msg) { panel._writeFile(msg) })
        NavSearch.setNavHttp(panel.navHttp)
        NavSearch.setDeferFn(function(fn, ms) {
            if (ms && ms > 0) {
                var t = Qt.createQmlObject('import QtQuick 2.0; Timer{}', panel, "deferTimer")
                t.interval = ms; t.repeat = false; t.running = true
                t.triggered.connect(function() { t.destroy(); fn() })
            } else { Qt.callLater(fn) }
        })
        var _db = LocalStorage.openDatabaseSync("NaviusMinetur", "1.0", "MINETUR combustible", 8 * 1024 * 1024)
        NavSearch.setMineturDb(_db)
        Qt.callLater(function() { NavSearch.initMinetur() })
    }

    Timer {
        interval: 43200000   // 12 h
        repeat: true; running: true
        onTriggered: NavSearch.refreshMinetur()
    }

    Connections {
        target: panel.navHttp
        onDone: function(reqId, body, err) {
            NavSearch.processOverpassResult(reqId, body, err)
        }
    }

    function _writeFile(msg) {
        if (fileLogger) fileLogger.log_to_file(msg)   // snake_case: nombre real del método Rust
    }

    function _addLog(msg) {
        var d  = new Date()
        var ts = ("0" + d.getHours()).slice(-2) + ":"
                + ("0" + d.getMinutes()).slice(-2) + ":"
                + ("0" + d.getSeconds()).slice(-2)
        var line = ts + "  " + msg
        var lines = _logLines.slice()
        lines.push(line)
        _logLines    = lines
        _logVisible  = true
        _writeFile(line)
    }

    function _resetLog() {
        _logLines      = []
        _logVisible    = false
        _logCollapsed  = false
    }

    function _saveWaypoints() {
        navSt.waypointsJson = _dests.length > 0 ? JSON.stringify(_dests) : ""
    }

    function _setDestTodos(idx, todos) {
        var d = _dests.slice()
        d[idx] = Object.assign({}, d[idx], {todos: todos})
        _dests = d
        _saveWaypoints()
        try { saveTodosToDb([d[idx]]) } catch(e) { console.error("saveTodosToDb _setDestTodos:", e) }
    }

    // Llamado desde Main.qml cuando el usuario marca/desmarca un TODO durante navegación
    function syncTodoFromNav(idx, todoIdx, done) {
        if (idx < 0 || idx >= _dests.length) return
        var todos = (_dests[idx].todos || []).slice()
        if (todoIdx < 0 || todoIdx >= todos.length) return
        todos[todoIdx] = Object.assign({}, todos[todoIdx], {done: done})
        _setDestTodos(idx, todos)
    }

    function _doSearch(q) {
        if (q.length < 2) { _results = []; _searching = false; _searchErr = ""; return }
        _st        = "results"
        _searching = true
        _searchErr = ""
        _results   = []
        _poiType   = ""
        _resetLog()
        _addLog(i18n.tr("Buscando «%1»").arg(q))
        NavSearch.geocode(q, panel.gpsLat, panel.gpsLon, function(err, res) {
            _searching = false
            if (err) {
                var isConnErr = err.indexOf("Timeout") >= 0 || err.indexOf("HTTP 0") >= 0
                             || err.indexOf("HTTP 5") >= 0 || err.indexOf("sin respuesta") >= 0
                if (isConnErr) {
                    panel.serverFallbackNeeded("Photon",
                        i18n.tr("El servidor de búsqueda no ha respondido."),
                        function() { _doSearch(q) })
                } else {
                    _searchErr = i18n.tr("Error de red: ") + err
                }
                return
            } else if (!res || res.length === 0) {
                _searchErr = i18n.tr("Sin resultados para «") + q + "»"
            } else {
                _searchErr = ""
                _results = res
            }
        })
    }

    function _searchPoi(type) {
        _st          = "results"
        _searching   = true
        _searchErr   = ""
        _results     = []
        _poiType     = type
        _mineturDate = ""
        _resetLog()
        var r   = panel._poiRadiusM
        var def = NavSearch.poiDef(type)
        var modeLabel = panel.poiMode === "en_ruta"  ? "en ruta"
                      : panel.poiMode === "destino"  ? "en destino"
                      : "cerca"
        _addLog((def ? def.icon + " " + def.label : type) + " · " + modeLabel + " · " + r + " m")
        var cb = function(err, res) {
            _searching = false
            if (err) {
                _addLog("✗ " + err)
                var isConnErr = err.indexOf("Timeout") >= 0 || err.indexOf("HTTP 0") >= 0
                             || err.indexOf("HTTP 5") >= 0 || err.indexOf("sin respuesta") >= 0
                if (isConnErr) {
                    panel.serverFallbackNeeded("Overpass",
                        i18n.tr("El servidor de puntos de interés no ha respondido."),
                        function() { _searchPoi(type) })
                } else {
                    _searchErr = i18n.tr("Error: ") + err
                }
            } else if (!res || res.length === 0) { _searchErr = i18n.tr("Sin resultados cerca"); _addLog("Sin resultados") }
            else                                  { _results = res; _addLog("✓ " + res.length + " resultado(s)") }
            if (type === "fuel") _mineturDate = NavSearch.mineturCacheDate()
        }
        var spd = panel.navSpeedKmh
        if (panel.poiMode === "en_ruta" && panel.navShape && panel.navShape.length > 0)
            NavSearch.fetchPoisAlongRoute(panel.gpsLat, panel.gpsLon, panel.navShape, r, type, spd, panel.poiMinutes, cb)
        else if (panel.poiMode === "destino" && panel._dests.length > 0)
            NavSearch.fetchPois(panel._dests[panel._dests.length-1].lat, panel._dests[panel._dests.length-1].lon, r, type, 0, cb)
        else
            NavSearch.fetchPois(panel.gpsLat, panel.gpsLon, r, type, spd, cb)
    }

    function _removeFromHistory(idx) {
        var h = _history.slice(); h.splice(idx, 1)
        _history = h
        histSt.json = h.length > 0 ? JSON.stringify(h) : ""
    }

    function _addToHistory(lat, lon, name) {
        var h = _history.slice()
        for (var i = h.length - 1; i >= 0; i--)
            if (h[i].name === name) h.splice(i, 1)
        h.unshift({lat: lat, lon: lon, name: name})
        if (h.length > 50) h = h.slice(0, 50)
        _history = h
        histSt.json = JSON.stringify(h)
    }

    function _isFavorite(lat, lon) {
        for (var i = 0; i < _favorites.length; i++)
            if (Math.abs(_favorites[i].lat - lat) < 0.0001 && Math.abs(_favorites[i].lon - lon) < 0.0001)
                return true
        return false
    }

    function _saveFavorite(name, lat, lon, address) {
        var favs = _favorites.slice()
        for (var i = favs.length - 1; i >= 0; i--)
            if (Math.abs(favs[i].lat - lat) < 0.0001 && Math.abs(favs[i].lon - lon) < 0.0001)
                favs.splice(i, 1)
        favs.unshift({name: name, lat: lat, lon: lon, address: address})
        _favorites = favs
        favSt.json = JSON.stringify(favs)
    }

    function _removeFavorite(idx) {
        var favs = _favorites.slice(); favs.splice(idx, 1)
        _favorites = favs
        favSt.json = favs.length > 0 ? JSON.stringify(favs) : ""
    }

    function _depDateTimeObj() {
        if (!_useDepTime) return {type: 0, value: "current"}
        var d = new Date()
        d.setDate(d.getDate() + _depDayOffset)
        d.setHours(_depHour, _depMin, 0, 0)
        var p = function(n) { return ("0" + n).slice(-2) }
        var iso = d.getFullYear() + "-" + p(d.getMonth()+1) + "-" + p(d.getDate()) +
                  "T" + p(_depHour) + ":" + p(_depMin)
        return {type: 1, value: iso}
    }

    function _depDateLabel() {
        if (_depDayOffset === 0) return i18n.tr("hoy")
        if (_depDayOffset === 1) return i18n.tr("mañana")
        var d = new Date(); d.setDate(d.getDate() + _depDayOffset)
        var days   = [i18n.tr("dom"),i18n.tr("lun"),i18n.tr("mar"),i18n.tr("mié"),
                      i18n.tr("jue"),i18n.tr("vie"),i18n.tr("sáb")]
        var months = [i18n.tr("ene"),i18n.tr("feb"),i18n.tr("mar"),i18n.tr("abr"),
                      i18n.tr("may"),i18n.tr("jun"),i18n.tr("jul"),i18n.tr("ago"),
                      i18n.tr("sep"),i18n.tr("oct"),i18n.tr("nov"),i18n.tr("dic")]
        return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()]
    }

    function _planName(plan) {
        if (!plan.dests || plan.dests.length === 0) return "?"
        var parts = []
        for (var i = 0; i < plan.dests.length; i++) parts.push(plan.dests[i].name)
        return parts.join(" → ")
    }

    function _planDepLabel(plan) {
        if (!plan.useDepTime || !plan.depAbsDate) return i18n.tr("Salida: ahora")
        var d = new Date(plan.depAbsDate)
        var days   = ["dom","lun","mar","mié","jue","vie","sáb"]
        var months = ["ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"]
        var p = function(n) { return ("0" + n).slice(-2) }
        return i18n.tr("Salida: ") + days[d.getDay()] + " " + d.getDate() + " " +
               months[d.getMonth()] + " · " + p(d.getHours()) + ":" + p(d.getMinutes())
    }

    function _savePlan() {
        if (_dests.length === 0) return
        var plan = {
            id: Date.now(),
            dests: JSON.parse(JSON.stringify(_dests)),  // deep copy (incluye todos)
            useDepTime: _useDepTime,
            savedAt: new Date().toISOString(),
            noTolls:   _noTolls,
            noFerry:   _noFerry,
            noDirt:    _noDirt,
            noHighway: _noHighway
        }
        if (_useDepTime) {
            var d = new Date()
            d.setDate(d.getDate() + _depDayOffset)
            d.setHours(_depHour, _depMin, 0, 0)
            plan.depAbsDate = d.toISOString()
        }
        var plans = _savedPlans.slice()
        plans.unshift(plan)
        _savedPlans = plans
        planSt.json = JSON.stringify(plans)
    }

    function _loadPlan(idx) {
        var p = _savedPlans[idx]
        if (!p) return
        _dests     = JSON.parse(JSON.stringify(p.dests))
        _noTolls   = p.noTolls   || false
        _noFerry   = p.noFerry   || false
        _noDirt    = p.noDirt    || false
        _noHighway = p.noHighway || false
        navSt.noTolls = _noTolls; navSt.noFerry = _noFerry
        navSt.noDirt  = _noDirt;  navSt.noHighway = _noHighway
        if (p.useDepTime && p.depAbsDate) {
            var d = new Date(p.depAbsDate)
            var diffDays = Math.round((d - new Date()) / 86400000)
            _depDayOffset = Math.max(0, diffDays)
            _depHour = d.getHours()
            _depMin  = d.getMinutes()
            _useDepTime = true
        } else {
            _useDepTime = false
        }
        _routes = []; _st = "idle"
        _saveWaypoints()
    }

    function _removePlan(idx) {
        var plans = _savedPlans.slice(); plans.splice(idx, 1)
        _savedPlans = plans
        planSt.json = plans.length > 0 ? JSON.stringify(plans) : ""
    }

    function _addDest(lat, lon, name) {
        var d = _dests.slice()
        d.push({lat: lat, lon: lon, name: name, todos: _latestTodos(lat, lon)})
        _dests   = d
        _routes  = []
        _st      = "idle"
        searchField.text = ""
        _saveWaypoints()
        _addToHistory(lat, lon, name)
    }

    // Distancia perpendicular de punto (pLat,pLon) al segmento (aLat,aLon)-(bLat,bLon), en km.
    function _segDistKm(pLat, pLon, aLat, aLon, bLat, bLon) {
        var cos = Math.cos((aLat + bLat) / 2 * Math.PI / 180)
        var px = pLon*cos, py = pLat
        var ax = aLon*cos, ay = aLat
        var bx = bLon*cos, by = bLat
        var dx = bx-ax,    dy = by-ay
        var lenSq = dx*dx + dy*dy
        var tx, ty
        if (lenSq < 1e-14) { tx = ax; ty = ay }
        else {
            var t = Math.max(0, Math.min(1, ((px-ax)*dx + (py-ay)*dy) / lenSq))
            tx = ax + t*dx; ty = ay + t*dy
        }
        var R = 6371, d2r = Math.PI/180
        var nearLat = ty, nearLon = (cos > 1e-6) ? tx/cos : aLon
        var dLa = (nearLat-pLat)*d2r, dLo = (nearLon-pLon)*d2r
        var a = Math.sin(dLa/2)*Math.sin(dLa/2)
              + Math.cos(pLat*d2r)*Math.cos(nearLat*d2r)*Math.sin(dLo/2)*Math.sin(dLo/2)
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
    }

    // Inserta POI en el segmento de ruta más cercano (entre GPS actual y los destinos).
    function _insertPoiInRoute(lat, lon, name) {
        var chain = []
        if (panel.gpsLat !== 0 || panel.gpsLon !== 0)
            chain.push({lat: panel.gpsLat, lon: panel.gpsLon})
        for (var i = 0; i < _dests.length; i++) chain.push(_dests[i])

        var insertIdx = _dests.length  // fallback: append
        if (chain.length >= 2) {
            var bestSeg = 0, bestDist = 1e18
            for (var s = 0; s < chain.length - 1; s++) {
                var dist = _segDistKm(lat, lon,
                                      chain[s].lat,   chain[s].lon,
                                      chain[s+1].lat, chain[s+1].lon)
                if (dist < bestDist) { bestDist = dist; bestSeg = s }
            }
            // chain[0] = gpsPos → chain[bestSeg+1] = _dests[bestSeg]
            insertIdx = bestSeg
        }

        var d = _dests.slice()
        d.splice(insertIdx, 0, {lat: lat, lon: lon, name: name, todos: _latestTodos(lat, lon)})
        _dests   = d
        _routes  = []
        _st      = "idle"
        searchField.text = ""
        _saveWaypoints()
        _addToHistory(lat, lon, name)
    }

    function _moveDest(idx, dir) {
        var d = _dests.slice()
        var j = idx + dir
        if (j < 0 || j >= d.length) return
        var tmp = d[idx]; d[idx] = d[j]; d[j] = tmp
        _dests  = d
        _routes = []
        _saveWaypoints()
    }

    function _pick(result) {
        focusDummy.forceActiveFocus()
        Qt.inputMethod.hide()
        if (_settingOrigin) {
            _simOrigin = {
                lat:  result.geometry.coordinates[1],
                lon:  result.geometry.coordinates[0],
                name: NavSearch.photonLabel(result)
            }
            _settingOrigin = false
            _results = []
            _st = "idle"
            searchField.text = ""
        } else {
            var lat  = result.geometry.coordinates[1]
            var lon  = result.geometry.coordinates[0]
            var name = NavSearch.photonLabel(result)
            if (result._isPoi && panel.navActive)
                _insertPoiInRoute(lat, lon, name)
            else
                _addDest(lat, lon, name)
        }
    }

    function _remove(idx) {
        var d = _dests.slice(); d.splice(idx, 1)
        _dests  = d
        _routes = []
        _st     = "idle"
        _saveWaypoints()
    }

    function _calcRoute(autoStart) {
        if (_dests.length === 0) return
        var wps = []
        if (panel.simMode && panel._simOrigin) {
            wps.push(panel._simOrigin)
        } else if (panel.gpsLat !== 0 || panel.gpsLon !== 0) {
            wps.push({lat: panel.gpsLat, lon: panel.gpsLon})
        } else {
            // Sin posición alguna: esperar al primer fix
            _pendingCalc = true
            errLabel.text = i18n.tr("Esperando posición GPS…")
            return
        }
        for (var i = completedLegs; i < _dests.length; i++) wps.push(_dests[i])
        if (wps.length < 2) { errLabel.text = i18n.tr("Se necesita al menos un destino"); return }
        _pendingCalc = false
        errLabel.text = ""
        _st = "routing"
        _resetLog()
        _addLog(i18n.tr("Calculando ruta…"))
        var opts = {no_tolls: _noTolls, no_ferry: _noFerry, no_dirt: _noDirt, no_highway: _noHighway,
                    date_time: _depDateTimeObj()}
        NavSearch.route(wps, opts, function(err, routes) {
            if (err || !routes || routes.length === 0) {
                _st = "idle"
                var isConnErr = err && (err.indexOf("Timeout") >= 0 || err.indexOf("HTTP 0") >= 0
                                        || err.indexOf("HTTP 5") >= 0 || err.indexOf("sin respuesta") >= 0
                                        || err.indexOf("Servidor:") >= 0)
                if (isConnErr) {
                    panel.serverFallbackNeeded("Valhalla",
                        i18n.tr("El servidor de rutas no ha respondido."),
                        function() { _calcRoute(autoStart) })
                } else {
                    errLabel.text = err || i18n.tr("No se encontró ruta")
                }
                return
            }
            _routes   = routes
            _selRoute = 0
            _st       = "routed"
            panel.routeReady(_routes, 0)
            if (autoStart) {
                panel.navigationStarted(_routes[0])
                panel.closed()
            }
        })
    }

    function triggerRestore() {
        if (_dests.length === 0) return
        if (hasFix)
            _calcRoute(true)
        else
            _pendingCalc = true
    }

    function cancelRestore() {
        _pendingCalc = false
        _dests = []
        _saveWaypoints()
    }

    function searchPoi(type) { _searchPoi(type) }

    // ── Layout (anchor-based para que el log no quede bajo el teclado) ─────

    // Cabecera
    Rectangle {
        id: panelHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(7)
        color: "#1C1C2E"

        Label {
            anchors.centerIn: parent
            text: i18n.tr("Navegación"); color: "white"
            font.pixelSize: units.gu(2.5); font.bold: true
        }
        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
            width: units.gu(4); height: units.gu(4); radius: width/2; color: "#2A2A3E"
            Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: ts(1.8) }
            MouseArea { anchors.fill: parent; onClicked: { Qt.inputMethod.hide(); panel.closed() } }
        }
    }

    // Campo de búsqueda
    Rectangle {
        id: searchBar
        anchors { top: panelHeader.bottom; left: parent.left; right: parent.right }
        height: units.gu(6.5)
        color: "#12122A"
        Row {
            anchors { verticalCenter: parent.verticalCenter
                      left: parent.left; right: parent.right
                      leftMargin: units.gu(2); rightMargin: units.gu(1.5) }
            spacing: units.gu(1)
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: "⌕"; font.pixelSize: ts(2.2); color: "#B0BEC5"
            }
            NavTextInput {
                id: searchField
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - units.gu(6) - (clearBtn.visible ? units.gu(4) : 0) - (logToggleBtn.visible ? units.gu(4) : 0)
                color: "white"; font.pixelSize: ts(1.8)
                inputMethodHints: Qt.ImhNoPredictiveText
                Label {
                    visible: parent.text.length === 0 && !parent.activeFocus
                    text: panel._settingOrigin ? i18n.tr("Buscar punto de inicio…") : i18n.tr("Buscar destino…"); color: "#90A4AE"
                    font.pixelSize: parent.font.pixelSize
                    anchors.verticalCenter: parent.verticalCenter
                }
                onTextChanged: panel._doSearch(text)
            }
            Rectangle {
                id: clearBtn; visible: searchField.text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(3.5); height: units.gu(3.5); radius: width/2; color: "#2A2A3E"
                Label { anchors.centerIn: parent; text: "✕"; color: "#B0BEC5"; font.pixelSize: ts(1.5) }
                MouseArea { anchors.fill: parent; onClicked: { searchField.text = ""; panel._results = []; panel._st = "idle"; panel._settingOrigin = false } }
            }
            Rectangle {
                id: logToggleBtn; visible: panel._logVisible
                anchors.verticalCenter: parent.verticalCenter
                width: units.gu(3.5); height: units.gu(3.5); radius: width/2; color: "#1C2C3A"
                border.color: "#37474F"; border.width: units.gu(0.1)
                Label { anchors.centerIn: parent; text: panel._logCollapsed ? "▼" : "▲"; color: "#4DB6AC"; font.pixelSize: ts(1.4) }
                MouseArea { anchors.fill: parent; onClicked: panel._logCollapsed = !panel._logCollapsed }
            }
        }
    }

    // Log de actividad — justo bajo el campo de búsqueda, visible con el teclado
    Rectangle {
        id: logBox
        anchors { top: searchBar.bottom; left: parent.left; right: parent.right }
        height: (panel._logVisible && !panel._logCollapsed) ? (panel.isLandscape ? units.gu(8) : units.gu(12)) : 0
        color: "#080812"
        clip: true

        Rectangle {
            width: parent.width; height: units.gu(0.08)
            anchors.top: parent.top; color: "#1C2C3A"
        }

        Flickable {
            id: logFlick
            anchors {
                fill: parent
                topMargin: units.gu(0.5)
                bottomMargin: units.gu(0.4)
                leftMargin: units.gu(1.5)
                rightMargin: units.gu(1)
            }
            contentWidth: width
            contentHeight: logText.implicitHeight
            clip: true
            onContentHeightChanged: {
                if (contentHeight > height) contentY = contentHeight - height
            }
            Text {
                id: logText
                width: logFlick.width
                text: panel._logLines.join("\n")
                color: "#4DB6AC"
                font.pixelSize: ts(1.25)
                font.family: "Ubuntu Mono"
                wrapMode: Text.WrapAnywhere
            }
        }
    }

    // Cuerpo — ocupa el espacio restante bajo el log
    Item {
        id: bodyItem
        anchors { top: logBox.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }

        // ── Contenedor derecho/inferior: opciones de ruta + botón calcular ──
        // Anchors siempre estables (right+bottom); solo cambian width y height.
        // Evita el bug de anchor top:undefined que rompe el layout al rotar.
        Item {
            id: stickyArea
            visible: panel._st === "idle" || panel._st === "routed"
            anchors { right: parent.right; bottom: parent.bottom }
            width:  panel.isLandscape ? Math.round(parent.width / 2) : parent.width
            height: panel.isLandscape ? parent.height : stickyBottom.implicitHeight

            Column {
                id: stickyBottom
                anchors { left: parent.left; right: parent.right; top: parent.top }
                topPadding: units.gu(0.8)
            bottomPadding: units.gu(1.2)
            leftPadding: units.gu(2)
            rightPadding: units.gu(2)
            spacing: units.gu(0.8)

            Rectangle {
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: units.gu(0.06); color: "#1C2C3A"
            }

            Label {
                id: errLabel
                width: parent.width - parent.leftPadding - parent.rightPadding
                visible: text.length > 0
                text: ""; color: "#FF5252"; font.pixelSize: ts(1.4)
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: units.gu(1)
                Repeater {
                    model: [
                        {key:"no_tolls",   lbl: i18n.tr("Sin peaje")},
                        {key:"no_ferry",   lbl: i18n.tr("Sin ferry")},
                        {key:"no_dirt",    lbl: i18n.tr("Sin tierra")},
                        {key:"no_highway", lbl: i18n.tr("Sin autopista")}
                    ]
                    Rectangle {
                        height: units.gu(4.5); width: lbl.width + units.gu(2.5); radius: height/2
                        property bool on: modelData.key==="no_tolls"   ? panel._noTolls   :
                                          modelData.key==="no_ferry"   ? panel._noFerry   :
                                          modelData.key==="no_dirt"    ? panel._noDirt    : panel._noHighway
                        color: on ? "#1E3A5F" : "#2A2A3E"
                        border.color: on ? "#29B6F6" : "transparent"; border.width: units.gu(0.15)
                        Label { id: lbl; anchors.centerIn: parent; text: modelData.lbl
                            color: on ? "#29B6F6" : "#78909C"; font.pixelSize: ts(1.8) }
                        MouseArea { anchors.fill: parent; onClicked: {
                            if      (modelData.key==="no_tolls")   { panel._noTolls   = !panel._noTolls;   navSt.noTolls   = panel._noTolls   }
                            else if (modelData.key==="no_ferry")   { panel._noFerry   = !panel._noFerry;   navSt.noFerry   = panel._noFerry   }
                            else if (modelData.key==="no_dirt")    { panel._noDirt    = !panel._noDirt;    navSt.noDirt    = panel._noDirt    }
                            else                                   { panel._noHighway = !panel._noHighway; navSt.noHighway = panel._noHighway }
                        }}
                    }
                }
            }

            Rectangle {
                // GoogleMapsPanel no existe en este port (QtWebEngine5 no
                // disponible en postmarketOS) — botón oculto, sin sustituto.
                visible: false && panel._st === "idle"
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: units.gu(5.5); radius: units.gu(0.8)
                color: gmapsArea.pressed ? "#1A2A1A" : "#1C2C1C"
                border.color: "#4CAF50"; border.width: units.gu(0.12)
                Row {
                    anchors.centerIn: parent; spacing: units.gu(1)
                    Label { anchors.verticalCenter: parent.verticalCenter
                        text: "🗺"; font.pixelSize: ts(2) }
                    Label { anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("Buscar en Google Maps")
                        color: "#81C784"; font.pixelSize: ts(1.8) }
                }
                MouseArea { id: gmapsArea; anchors.fill: parent
                    onClicked: panel.googleMapsRequested() }
            }

            // ── Hora de salida ────────────────────────────────────────────────
            Column {
                visible: panel._dests.length > 0 && panel._st !== "routed"
                width: parent.width - parent.leftPadding - parent.rightPadding
                spacing: units.gu(0.6)

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: units.gu(0.8)
                    Rectangle {
                        height: units.gu(4); width: nowLbl.width + units.gu(3); radius: height/2
                        color: !panel._useDepTime ? "#1E3A5F" : "#2A2A3E"
                        border.color: !panel._useDepTime ? "#29B6F6" : "transparent"; border.width: units.gu(0.15)
                        Label { id: nowLbl; anchors.centerIn: parent; text: i18n.tr("Salir ahora")
                            color: !panel._useDepTime ? "#29B6F6" : "#78909C"; font.pixelSize: ts(1.5) }
                        MouseArea { anchors.fill: parent; onClicked: { panel._useDepTime = false; panel._depDayOffset = 0 } }
                    }
                    Rectangle {
                        height: units.gu(4); width: schedLbl.width + units.gu(3); radius: height/2
                        color: panel._useDepTime ? "#1E3A5F" : "#2A2A3E"
                        border.color: panel._useDepTime ? "#29B6F6" : "transparent"; border.width: units.gu(0.15)
                        Label { id: schedLbl; anchors.centerIn: parent; text: "⏱ " + i18n.tr("Hora de salida")
                            color: panel._useDepTime ? "#29B6F6" : "#78909C"; font.pixelSize: ts(1.5) }
                        MouseArea { anchors.fill: parent; onClicked: {
                            if (!panel._useDepTime) {
                                var now = new Date()
                                panel._depDayOffset = 0
                                panel._depHour = now.getHours()
                                var m = Math.ceil(now.getMinutes() / 5) * 5
                                if (m >= 60) { m = 0; panel._depHour = Math.min(23, panel._depHour + 1) }
                                panel._depMin = m
                                panel._useDepTime = true
                            }
                        }}
                    }
                }

                Rectangle {
                    visible: panel._useDepTime
                    width: parent.width
                    height: units.gu(7.5); radius: units.gu(0.8); color: "#1C1C2E"
                    Row {
                        anchors.centerIn: parent; spacing: units.gu(2)
                        Row {
                            anchors.verticalCenter: parent.verticalCenter; spacing: units.gu(0.5)
                            Rectangle {
                                width: units.gu(3.8); height: units.gu(3.8); radius: units.gu(0.6); color: "#2A2A3E"
                                anchors.verticalCenter: parent.verticalCenter
                                Label { anchors.centerIn: parent; text: "◀"; color: "#B0BEC5"; font.pixelSize: ts(1.6) }
                                MouseArea { anchors.fill: parent; onClicked: { if (panel._depDayOffset > 0) panel._depDayOffset-- } }
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: panel._depDateLabel()
                                color: "white"; font.pixelSize: ts(1.6); font.bold: true
                                width: units.gu(11); horizontalAlignment: Text.AlignHCenter
                            }
                            Rectangle {
                                width: units.gu(3.8); height: units.gu(3.8); radius: units.gu(0.6); color: "#2A2A3E"
                                anchors.verticalCenter: parent.verticalCenter
                                Label { anchors.centerIn: parent; text: "▶"; color: "#B0BEC5"; font.pixelSize: ts(1.6) }
                                MouseArea { anchors.fill: parent; onClicked: { if (panel._depDayOffset < 30) panel._depDayOffset++ } }
                            }
                        }
                        Label { anchors.verticalCenter: parent.verticalCenter; text: "·"; color: "#90A4AE"; font.pixelSize: ts(2) }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter; spacing: units.gu(0.3)
                            Column {
                                spacing: units.gu(0.2)
                                Rectangle { width: units.gu(4); height: units.gu(2.4); radius: units.gu(0.5); color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "▲"; color: "#B0BEC5"; font.pixelSize: ts(1.3) }
                                    MouseArea { anchors.fill: parent; onClicked: panel._depHour = (panel._depHour + 1) % 24 }
                                }
                                Label { anchors.horizontalCenter: parent.horizontalCenter
                                    text: ("0" + panel._depHour).slice(-2)
                                    color: "white"; font.pixelSize: ts(2.2); font.bold: true }
                                Rectangle { width: units.gu(4); height: units.gu(2.4); radius: units.gu(0.5); color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "▼"; color: "#B0BEC5"; font.pixelSize: ts(1.3) }
                                    MouseArea { anchors.fill: parent; onClicked: panel._depHour = (panel._depHour + 23) % 24 }
                                }
                            }
                            Label { anchors.verticalCenter: parent.verticalCenter; text: ":"; color: "#90A4AE"; font.pixelSize: ts(2.4) }
                            Column {
                                spacing: units.gu(0.2)
                                Rectangle { width: units.gu(4); height: units.gu(2.4); radius: units.gu(0.5); color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "▲"; color: "#B0BEC5"; font.pixelSize: ts(1.3) }
                                    MouseArea { anchors.fill: parent; onClicked: panel._depMin = (panel._depMin + 5) % 60 }
                                }
                                Label { anchors.horizontalCenter: parent.horizontalCenter
                                    text: ("0" + panel._depMin).slice(-2)
                                    color: "white"; font.pixelSize: ts(2.2); font.bold: true }
                                Rectangle { width: units.gu(4); height: units.gu(2.4); radius: units.gu(0.5); color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "▼"; color: "#B0BEC5"; font.pixelSize: ts(1.3) }
                                    MouseArea { anchors.fill: parent; onClicked: panel._depMin = (panel._depMin + 55) % 60 }
                                }
                            }
                        }
                    }
                }
            }

            Row {
                visible: panel._dests.length > 0 && panel._st !== "routed"
                width: parent.width - parent.leftPadding - parent.rightPadding
                spacing: units.gu(0.8)

                Rectangle {
                    height: units.gu(6); width: parent.width - savePlanBtn.width - units.gu(0.8)
                    radius: units.gu(0.8); color: "#1565C0"
                    Label { anchors.centerIn: parent; text: i18n.tr("CALCULAR RUTA")
                        color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                    MouseArea { anchors.fill: parent; onClicked: panel._calcRoute() }
                }
                Rectangle {
                    id: savePlanBtn
                    height: units.gu(6); width: units.gu(6); radius: units.gu(0.8)
                    color: "#2A2A3E"
                    Label { anchors.centerIn: parent; text: "⊕"; color: "#B0BEC5"; font.pixelSize: ts(2.2) }
                    MouseArea { anchors.fill: parent; onClicked: panel._savePlan() }
                }
            }

            Rectangle {
                visible: panel._st === "routed" && panel._routes.length > 0
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: units.gu(5.5); radius: units.gu(0.8)
                color: "transparent"
                border.color: "#29B6F6"; border.width: units.gu(0.15)
                Row {
                    anchors.centerIn: parent; spacing: units.gu(0.8)
                    Label { anchors.verticalCenter: parent.verticalCenter
                        text: "⊞"; color: "#29B6F6"; font.pixelSize: ts(2) }
                    Label { anchors.verticalCenter: parent.verticalCenter
                        text: i18n.tr("Previsualizar en mapa"); color: "#29B6F6"; font.pixelSize: ts(1.8) }
                }
                MouseArea { anchors.fill: parent; onClicked: {
                    Qt.inputMethod.hide()
                    panel.previewRequested(panel._routes, panel._selRoute)
                }}
            }

            Rectangle {
                visible: panel._st === "routed" && panel._routes.length > 0
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: units.gu(6.5); radius: units.gu(0.8); color: "#2E7D32"
                Label { anchors.centerIn: parent
                    text: "▶  " + i18n.tr("INICIAR NAVEGACIÓN")
                    color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: {
                    Qt.inputMethod.hide()
                    panel.routeReady(panel._routes, panel._selRoute)
                    panel.navigationStarted(panel._routes[panel._selRoute])
                    panel.closed()
                }}
            }

            Rectangle {
                visible: panel._st === "routed"
                width: parent.width - parent.leftPadding - parent.rightPadding
                height: units.gu(5); radius: units.gu(0.8); color: "transparent"
                border.color: "#90A4AE"; border.width: units.gu(0.15)
                Label { anchors.centerIn: parent; text: i18n.tr("Borrar ruta")
                    color: "#B0BEC5"; font.pixelSize: ts(1.8) }
                MouseArea { anchors.fill: parent; onClicked: {
                    panel._dests       = []
                    panel._routes      = []
                    panel._st          = "idle"
                    panel._pendingCalc = false
                    panel._saveWaypoints()
                    panel.routeReady([], -1)
                }}
            }
        }
        }  // fin Item stickyArea

        // ── Resultados de búsqueda ─────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: panel._st === "results"

            Column {
                anchors.centerIn: parent
                visible: panel._searching
                spacing: units.gu(1.5)
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "⟳"; color: "#29B6F6"; font.pixelSize: ts(4)
                    RotationAnimation on rotation {
                        running: panel._searching; loops: Animation.Infinite
                        from: 0; to: 360; duration: 1000
                    }
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: i18n.tr("Buscando…"); color: "#90A4AE"; font.pixelSize: ts(1.7)
                }
            }

            Label {
                anchors.centerIn: parent
                visible: !panel._searching && panel._searchErr.length > 0
                text: panel._searchErr; color: "#FF7043"
                font.pixelSize: ts(1.6); wrapMode: Text.WordWrap
                width: parent.width - units.gu(4)
                horizontalAlignment: Text.AlignHCenter
            }

            Label {
                id: fuelDateLabel
                anchors { top: parent.top; topMargin: units.gu(0.5); horizontalCenter: parent.horizontalCenter }
                visible: !panel._searching && panel._poiType === "fuel" && panel._results.length > 0
                text: i18n.tr("Precios: ") + panel._mineturDate
                color: "#90A4AE"; font.pixelSize: ts(2.8)
            }

            ListView {
                anchors { fill: parent; topMargin: fuelDateLabel.visible ? fuelDateLabel.height + units.gu(1) : 0 }
                visible: !panel._searching && panel._results.length > 0
                model: panel._results
                clip: true
                delegate: Rectangle {
                    id: resultDelegate
                    property string _detail: (modelData.properties && modelData.properties.detail) ? modelData.properties.detail : ""
                    width: parent.width
                    height: _detail.length > 0 ? units.gu(12) : units.gu(10)
                    color: rm.pressed ? "#1E3A5F" : "transparent"
                    Rectangle { width: parent.width; height: units.gu(0.06); anchors.bottom: parent.bottom; color: "#1C1C2E" }

                    property real _rLat: modelData.geometry.coordinates[1]
                    property real _rLon: modelData.geometry.coordinates[0]

                    Column {
                        anchors { left: parent.left; right: favStarBtn.left; verticalCenter: parent.verticalCenter
                                  leftMargin: units.gu(2); rightMargin: units.gu(1) }
                        spacing: units.gu(0.3)
                        Label {
                            width: parent.width
                            text: NavSearch.photonShortName(modelData)
                            color: "white"; font.pixelSize: ts(2.1); elide: Text.ElideRight
                        }
                        Label {
                            width: parent.width
                            text: NavSearch.photonSubtitle(modelData)
                            color: "#B0BEC5"; font.pixelSize: ts(1.6); elide: Text.ElideRight
                        }
                        Label {
                            width: parent.width
                            visible: resultDelegate._detail.length > 0
                            text: resultDelegate._detail
                            color: "#29B6F6"; font.pixelSize: ts(1.6); elide: Text.ElideRight
                        }
                    }

                    Rectangle {
                        id: favStarBtn
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(1) }
                        width: units.gu(7.5); height: units.gu(7.5); radius: width/2
                        color: panel._isFavorite(resultDelegate._rLat, resultDelegate._rLon) ? "#2A2A1A" : "transparent"
                        Label {
                            anchors.centerIn: parent
                            text: panel._isFavorite(resultDelegate._rLat, resultDelegate._rLon) ? "★" : "☆"
                            color: panel._isFavorite(resultDelegate._rLat, resultDelegate._rLon) ? "#FFD600" : "#78909C"
                            font.pixelSize: ts(3.5)
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                panel._favPending = {
                                    lat:     resultDelegate._rLat,
                                    lon:     resultDelegate._rLon,
                                    name:    NavSearch.photonLabel(modelData),
                                    address: NavSearch.photonSubtitle(modelData)
                                }
                                favNameField.text = NavSearch.photonLabel(modelData)
                                favNameField.forceActiveFocus()
                            }
                        }
                    }

                    MouseArea {
                        id: rm
                        anchors { left: parent.left; right: favStarBtn.left; top: parent.top; bottom: parent.bottom }
                        onClicked: panel._pick(modelData)
                    }
                }
            }
        }

        // ── Vista idle / routed ────────────────────────────────────────────
        Flickable {
            anchors {
                top:    parent.top
                left:   parent.left
                right:  panel.isLandscape ? stickyArea.left : parent.right
                bottom: panel.isLandscape ? parent.bottom   : stickyArea.top
            }
            visible: panel._st === "idle" || panel._st === "routed"
            contentHeight: mainCol.implicitHeight + units.gu(1)
            clip: true

            Column {
                id: mainCol
                width: parent.width
                topPadding: units.gu(1.5)
                spacing: units.gu(1.2)

                // ── Planes guardados ──────────────────────────────────────────
                Column {
                    visible: panel._savedPlans.length > 0 && panel._st === "idle"
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    spacing: units.gu(0.8)

                    Label { text: i18n.tr("Planes guardados"); color: "#90A4AE"; font.pixelSize: ts(1.5) }

                    Repeater {
                        model: panel._savedPlans
                        Rectangle {
                            anchors { left: parent.left; right: parent.right }
                            height: units.gu(7.5); color: "#1C1C2E"; radius: units.gu(0.8)
                            Row {
                                anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1) }
                                spacing: units.gu(1)
                                Label { anchors.verticalCenter: parent.verticalCenter
                                    text: "📋"; font.pixelSize: ts(1.8) }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(10)
                                    Label {
                                        width: parent.width
                                        text: panel._planName(modelData)
                                        color: "white"; font.pixelSize: ts(1.5); elide: Text.ElideRight
                                    }
                                    Label {
                                        width: parent.width
                                        text: panel._planDepLabel(modelData)
                                        color: "#B0BEC5"; font.pixelSize: ts(1.2); elide: Text.ElideRight
                                    }
                                }
                                Item { width: units.gu(1); height: 1; anchors.verticalCenter: parent.verticalCenter }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(3.5); height: units.gu(3.5); radius: width/2; color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#B0BEC5"; font.pixelSize: ts(1.4) }
                                    MouseArea { anchors.fill: parent; onClicked: panel._removePlan(index) }
                                }
                            }
                            MouseArea {
                                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
                                anchors.rightMargin: units.gu(5)
                                onClicked: { focusDummy.forceActiveFocus(); Qt.inputMethod.hide(); panel._loadPlan(index) }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    height: units.gu(5.5); color: "#1C1C2E"; radius: units.gu(0.8)
                    Row {
                        anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1) }
                        spacing: units.gu(1)
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "◉"; color: "#4CAF50"; font.pixelSize: ts(1.8)
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - units.gu(panel.simMode ? 9 : 4)
                            text: (panel.simMode && panel._simOrigin) ? panel._simOrigin.name
                                                                      : i18n.tr("Mi posición (GPS)")
                            color: (panel.simMode && panel._simOrigin) ? "white" : "#78909C"
                            font.pixelSize: ts(1.8); elide: Text.ElideRight
                        }
                        Label {
                            visible: panel.simMode && !panel._simOrigin
                            anchors.verticalCenter: parent.verticalCenter
                            text: "✎"; color: "#29B6F6"; font.pixelSize: ts(1.8)
                        }
                        Rectangle {
                            visible: panel.simMode && panel._simOrigin !== null
                            anchors.verticalCenter: parent.verticalCenter
                            width: units.gu(3.2); height: units.gu(3.2); radius: width/2; color: "#2A2A3E"
                            Label { anchors.centerIn: parent; text: "✕"; color: "#B0BEC5"; font.pixelSize: ts(1.3) }
                            MouseArea { anchors.fill: parent; onClicked: panel._simOrigin = null }
                        }
                    }
                    MouseArea {
                        // No cubrir el botón ✕ cuando está visible (evita que el MA exterior lo tape)
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width - (panel.simMode && panel._simOrigin !== null ? units.gu(5) : 0)
                        enabled: panel.simMode
                        onClicked: {
                            panel._settingOrigin = true
                            searchField.forceActiveFocus()
                        }
                    }
                }

                // Opción "mi posición actual" al buscar origen en modo sim
                Rectangle {
                    visible: panel._settingOrigin && panel.simMode
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    height: units.gu(6); radius: units.gu(0.8)
                    color: "#1E3A5F"
                    border.color: "#29B6F6"; border.width: units.gu(0.12)

                    Row {
                        anchors { fill: parent; leftMargin: units.gu(1.5) }
                        spacing: units.gu(1.2)
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "◉"; color: "#4CAF50"; font.pixelSize: ts(2)
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: i18n.tr("Mi posición actual")
                            color: "white"; font.pixelSize: ts(1.6); font.bold: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            panel._simOrigin = null
                            panel._settingOrigin = false
                            Qt.inputMethod.hide()
                        }
                    }
                }

                Repeater {
                    model: panel._dests
                    Column {
                        anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                        spacing: 0
                        property int   _idx:     index
                        property var   _dest:    modelData
                        property string _newTodo: ""

                        // Fila waypoint
                        Rectangle {
                            width: parent.width; height: units.gu(6.5)
                            color: "#1C1C2E"; radius: units.gu(0.8)
                            Row {
                                anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1) }
                                spacing: units.gu(0.8)
                                Label { anchors.verticalCenter: parent.verticalCenter; text: "📍"; font.pixelSize: ts(2.1) }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(17.5)
                                    text: modelData.name; color: "white"; font.pixelSize: ts(1.8); elide: Text.ElideRight
                                }
                                // Botón TODO con badge
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(5); height: units.gu(4); radius: units.gu(0.5)
                                    color: panel._todoEditIdx === _idx ? "#1E3A5F" : "#2A2A3E"
                                    border.color: panel._todoEditIdx === _idx ? "#29B6F6" : "transparent"; border.width: 1
                                    Row {
                                        anchors.centerIn: parent; spacing: units.gu(0.3)
                                        Label { text: "📝"; font.pixelSize: ts(1.6) }
                                        Label {
                                            visible: !!(_dest.todos && _dest.todos.length > 0)
                                            text: _dest.todos ? _dest.todos.length : ""
                                            color: "#29B6F6"; font.pixelSize: ts(1.4); font.bold: true
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            var next = (panel._todoEditIdx === _idx ? -1 : _idx)
                                            panel._todoEditIdx = next
                                            if (next >= 0) panel._loadPastTodos(_dest.lat, _dest.lon)
                                            else { panel._pastTodos = []; panel._pastTodosOpen = false }
                                        }
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: units.gu(0.3)
                                    Rectangle {
                                        width: units.gu(3.2); height: units.gu(2.6); radius: units.gu(0.4)
                                        color: upMa.pressed ? "#1E3A5F" : "#2A2A3E"
                                        opacity: _idx > 0 ? 1.0 : 0.25
                                        Label { anchors.centerIn: parent; text: "↑"; color: "#90A4AE"; font.pixelSize: ts(1.5) }
                                        MouseArea { id: upMa; anchors.fill: parent; enabled: _idx > 0; onClicked: panel._moveDest(_idx, -1) }
                                    }
                                    Rectangle {
                                        width: units.gu(3.2); height: units.gu(2.6); radius: units.gu(0.4)
                                        color: downMa.pressed ? "#1E3A5F" : "#2A2A3E"
                                        opacity: _idx < panel._dests.length - 1 ? 1.0 : 0.25
                                        Label { anchors.centerIn: parent; text: "↓"; color: "#90A4AE"; font.pixelSize: ts(1.5) }
                                        MouseArea { id: downMa; anchors.fill: parent; enabled: _idx < panel._dests.length - 1; onClicked: panel._moveDest(_idx, 1) }
                                    }
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(3.2); height: units.gu(3.2); radius: width/2; color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#B0BEC5"; font.pixelSize: ts(1.3) }
                                    MouseArea { anchors.fill: parent; onClicked: { panel._todoEditIdx = -1; panel._remove(_idx) } }
                                }
                            }
                        }

                        // Editor TODO (visible cuando este waypoint está seleccionado)
                        Rectangle {
                            visible: panel._todoEditIdx === _idx
                            width: parent.width
                            height: visible ? todoEditorCol.implicitHeight + units.gu(1.5) : 0
                            color: "#111827"; radius: units.gu(0.8)
                            border.color: "#29B6F6"; border.width: 1

                            Column {
                                id: todoEditorCol
                                anchors { left: parent.left; right: parent.right; top: parent.top
                                          margins: units.gu(1) }
                                spacing: units.gu(0.6)

                                // Items existentes
                                Repeater {
                                    model: _dest.todos || []
                                    delegate: Rectangle {
                                        id: todoItemRect
                                        width: todoEditorCol.width
                                        height: _editing ? units.gu(5.5) : units.gu(4.5)
                                        color: "#1C2533"; radius: units.gu(0.5)
                                        clip: true

                                        property bool   _editing:  false
                                        property string _editText: modelData.text
                                        property int    _tIdx:     index

                                        // ── Vista normal ──────────────────────────
                                        Item {
                                            visible: !todoItemRect._editing
                                            anchors.fill: parent

                                            Label {
                                                id: tBullet
                                                anchors { left: parent.left; leftMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                                                text: "•"; color: "#B0BEC5"; font.pixelSize: ts(1.8)
                                            }
                                            Rectangle {
                                                id: tDel
                                                anchors { right: parent.right; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                                                width: units.gu(3); height: units.gu(3); radius: width/2
                                                color: tDelMa.pressed ? "#3A1414" : "#1E2A3A"
                                                Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.3) }
                                                MouseArea {
                                                    id: tDelMa; anchors.fill: parent
                                                    onClicked: {
                                                        if (panel._movingDestIdx === _idx && panel._movingTodoIdx === todoItemRect._tIdx) {
                                                            panel._movingDestIdx = -1; panel._movingTodoIdx = -1
                                                        }
                                                        var todos = (_dest.todos || []).slice()
                                                        todos.splice(todoItemRect._tIdx, 1)
                                                        panel._setDestTodos(_idx, todos)
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                id: tEdit
                                                anchors { right: tDel.left; rightMargin: units.gu(0.4); verticalCenter: parent.verticalCenter }
                                                width: units.gu(3); height: units.gu(3); radius: units.gu(0.4)
                                                color: tEditMa.pressed ? "#1A3040" : "#1E2A3A"
                                                Label { anchors.centerIn: parent; text: "✎"; color: "#B0BEC5"; font.pixelSize: ts(1.4) }
                                                MouseArea {
                                                    id: tEditMa; anchors.fill: parent
                                                    onClicked: {
                                                        todoItemRect._editText = modelData.text
                                                        todoItemRect._editing = true
                                                        panel._movingDestIdx = -1; panel._movingTodoIdx = -1
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                id: tMove
                                                visible: panel._dests.length > 1
                                                anchors { right: tEdit.left; rightMargin: units.gu(0.4); verticalCenter: parent.verticalCenter }
                                                width: units.gu(3); height: units.gu(3); radius: units.gu(0.4)
                                                color: (panel._movingDestIdx === _idx && panel._movingTodoIdx === todoItemRect._tIdx) ? "#1A3A5F" : (tMoveMa.pressed ? "#1A3040" : "#1E2A3A")
                                                border.color: (panel._movingDestIdx === _idx && panel._movingTodoIdx === todoItemRect._tIdx) ? "#29B6F6" : "transparent"; border.width: 1
                                                Label { anchors.centerIn: parent; text: "⇄"; color: "#B0BEC5"; font.pixelSize: ts(1.3) }
                                                MouseArea {
                                                    id: tMoveMa; anchors.fill: parent
                                                    onClicked: {
                                                        if (panel._movingDestIdx === _idx && panel._movingTodoIdx === todoItemRect._tIdx) {
                                                            panel._movingDestIdx = -1; panel._movingTodoIdx = -1
                                                        } else {
                                                            panel._movingDestIdx = _idx
                                                            panel._movingTodoIdx = todoItemRect._tIdx
                                                        }
                                                    }
                                                }
                                            }
                                            Label {
                                                anchors {
                                                    left: tBullet.right; leftMargin: units.gu(0.8)
                                                    right: tMove.visible ? tMove.left : tEdit.left
                                                    rightMargin: units.gu(0.4)
                                                    verticalCenter: parent.verticalCenter
                                                }
                                                text: modelData.text; color: "#B0BEC5"
                                                font.pixelSize: ts(1.8); elide: Text.ElideRight
                                            }
                                        }

                                        // ── Modo edición ──────────────────────────
                                        Item {
                                            visible: todoItemRect._editing
                                            anchors.fill: parent

                                            Rectangle {
                                                id: eConfirm
                                                anchors { right: parent.right; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                                                width: units.gu(3.5); height: units.gu(3.5); radius: units.gu(0.4)
                                                color: eConfirmMa.pressed ? "#1B5E20" : "#2E7D32"
                                                Label { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: ts(1.6); font.bold: true }
                                                function doConfirm() {
                                                    var t = todoItemRect._editText.trim()
                                                    if (t.length === 0) { todoItemRect._editing = false; return }
                                                    var todos = (_dest.todos || []).slice()
                                                    todos[todoItemRect._tIdx] = Object.assign({}, todos[todoItemRect._tIdx], {text: t})
                                                    panel._setDestTodos(_idx, todos)
                                                    todoItemRect._editing = false
                                                }
                                                MouseArea { id: eConfirmMa; anchors.fill: parent; onClicked: eConfirm.doConfirm() }
                                            }
                                            Rectangle {
                                                id: eCancel
                                                anchors { right: eConfirm.left; rightMargin: units.gu(0.4); verticalCenter: parent.verticalCenter }
                                                width: units.gu(3.5); height: units.gu(3.5); radius: units.gu(0.4)
                                                color: eCancelMa.pressed ? "#3A1414" : "#1E2A3A"
                                                Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.4) }
                                                MouseArea { id: eCancelMa; anchors.fill: parent; onClicked: todoItemRect._editing = false }
                                            }
                                            Item {
                                                anchors { left: parent.left; leftMargin: units.gu(1.5); right: eCancel.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                                                height: units.gu(3)
                                                Rectangle { anchors.fill: parent; color: "#0D1B2A"; radius: units.gu(0.3) }
                                                NavTextInput {
                                                    anchors { left: parent.left; leftMargin: units.gu(0.5); right: parent.right; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                                                    text: todoItemRect._editText
                                                    onTextChanged: todoItemRect._editText = text
                                                    color: "#ECEFF1"; font.pixelSize: ts(1.8)
                                                    onAccepted: eConfirm.doConfirm()
                                                    Component.onCompleted: if (todoItemRect._editing) forceActiveFocus()
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── Selector destino para mover tarea ────────
                                Column {
                                    visible: panel._movingDestIdx === _idx
                                    width: todoEditorCol.width
                                    spacing: units.gu(0.3)

                                    Rectangle {
                                        width: parent.width; height: units.gu(3.5)
                                        color: "#0A1929"; radius: units.gu(0.4)
                                        Label {
                                            anchors { left: parent.left; leftMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                                            text: "⇄ " + i18n.tr("Mover a:")
                                            color: "#29B6F6"; font.pixelSize: ts(1.5); font.bold: true
                                        }
                                        MouseArea {
                                            anchors { right: parent.right; rightMargin: units.gu(1); top: parent.top; bottom: parent.bottom }
                                            width: units.gu(3)
                                            onClicked: { panel._movingDestIdx = -1; panel._movingTodoIdx = -1 }
                                            Label { anchors.centerIn: parent; text: "✕"; color: "#B0BEC5"; font.pixelSize: ts(1.3) }
                                        }
                                    }
                                    Repeater {
                                        model: {
                                            var res = []
                                            for (var i = 0; i < panel._dests.length; i++)
                                                if (i !== _idx) res.push({dName: panel._dests[i].name || (i18n.tr("Destino") + " " + (i+1)), dIdx: i})
                                            return res
                                        }
                                        delegate: Rectangle {
                                            width: todoEditorCol.width; height: units.gu(4.5)
                                            color: moveDstMa.pressed ? "#1A3A2A" : "#101E14"
                                            radius: units.gu(0.4)
                                            border.color: "#2E4A2E"; border.width: 1
                                            Row {
                                                anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(0.5) }
                                                spacing: units.gu(0.8)
                                                Label { anchors.verticalCenter: parent.verticalCenter; text: "📍"; font.pixelSize: ts(1.6) }
                                                Label {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - units.gu(5)
                                                    text: modelData.dName; color: "#90A4AE"; font.pixelSize: ts(1.7); elide: Text.ElideRight
                                                }
                                            }
                                            MouseArea {
                                                id: moveDstMa; anchors.fill: parent
                                                onClicked: {
                                                    var fromDest  = panel._movingDestIdx
                                                    var todoIdxMv = panel._movingTodoIdx
                                                    var toDest    = modelData.dIdx
                                                    panel._movingDestIdx = -1; panel._movingTodoIdx = -1
                                                    var srcTodos = (panel._dests[fromDest].todos || []).slice()
                                                    if (todoIdxMv < 0 || todoIdxMv >= srcTodos.length) return
                                                    var movedTodo = srcTodos[todoIdxMv]
                                                    srcTodos.splice(todoIdxMv, 1)
                                                    panel._setDestTodos(fromDest, srcTodos)
                                                    var dstTodos = (panel._dests[toDest].todos || []).slice()
                                                    dstTodos.push(movedTodo)
                                                    panel._setDestTodos(toDest, dstTodos)
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── TODOs anteriores (historial DB) ──────────
                                Column {
                                    visible: panel._todoEditIdx === _idx && panel._pastTodos.length > 0
                                    width: todoEditorCol.width
                                    spacing: units.gu(0.4)

                                    Rectangle {
                                        width: parent.width; height: units.gu(3.5); color: "transparent"
                                        Row {
                                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                            spacing: units.gu(0.6)
                                            Label { text: "📋"; font.pixelSize: ts(1.4) }
                                            Label { text: i18n.tr("Anteriores"); color: "#90A4AE"; font.pixelSize: ts(1.4) }
                                            Label {
                                                text: panel._pastTodosOpen ? "▼" : "▶"
                                                color: "#90A4AE"; font.pixelSize: ts(1.2)
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: panel._pastTodosOpen = !panel._pastTodosOpen
                                        }
                                    }

                                    Repeater {
                                        model: (panel._todoEditIdx === _idx && panel._pastTodosOpen) ? panel._pastTodos : []
                                        delegate: Rectangle {
                                            width: todoEditorCol.width; height: units.gu(4.5)
                                            color: pastAddMa.pressed ? "#1A2E1A" : "#141E2C"
                                            radius: units.gu(0.5)
                                            border.color: "#2E4A2E"; border.width: 1
                                            Row {
                                                anchors { fill: parent; leftMargin: units.gu(1); rightMargin: units.gu(0.5) }
                                                spacing: units.gu(0.8)
                                                Label {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.done ? "☑" : "☐"
                                                    color: modelData.done ? "#29B6F6" : "#90A4AE"
                                                    font.pixelSize: ts(1.8)
                                                }
                                                Label {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: parent.width - units.gu(7)
                                                    text: modelData.text
                                                    color: modelData.done ? "#78909C" : "#90A4AE"
                                                    font.pixelSize: ts(1.7)
                                                    font.strikeout: modelData.done
                                                    elide: Text.ElideRight
                                                }
                                                Label {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "＋"; color: "#4CAF50"; font.pixelSize: ts(1.8); font.bold: true
                                                }
                                            }
                                            MouseArea {
                                                id: pastAddMa; anchors.fill: parent
                                                onClicked: {
                                                    var existing = (_dest.todos || [])
                                                    for (var ei = 0; ei < existing.length; ei++)
                                                        if (existing[ei].text === modelData.text) return
                                                    var todos = existing.slice()
                                                    todos.push({ text: modelData.text, done: modelData.done })
                                                    panel._setDestTodos(_idx, todos)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Añadir nuevo TODO
                                Rectangle {
                                    width: todoEditorCol.width; height: units.gu(5)
                                    color: "#1C2533"; radius: units.gu(0.5)
                                    border.color: "#37474F"; border.width: 1
                                    Row {
                                        anchors { fill: parent; leftMargin: units.gu(1); rightMargin: units.gu(0.5) }
                                        spacing: units.gu(0.8)
                                        Item {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - units.gu(6)
                                            height: units.gu(2.5)
                                            NavTextInput {
                                                id: newTodoInput
                                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                                onTextChanged: _newTodo = text
                                                color: "#ECEFF1"; font.pixelSize: ts(1.8)
                                                onAccepted: addTodoBtn.doAdd()
                                            }
                                            Label {
                                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                                visible: newTodoInput.text.length === 0 && newTodoInput.preeditText.length === 0
                                                text: i18n.tr("TODO tarea") + " " + ((_dest.todos ? _dest.todos.length : 0) + 1)
                                                color: "#B0BEC5"; font.pixelSize: ts(1.8)
                                            }
                                        }
                                        Rectangle {
                                            id: addTodoBtn
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: units.gu(4.5); height: units.gu(3.5); radius: units.gu(0.5)
                                            color: addTodoMa.pressed ? "#1B5E20" : "#2E7D32"
                                            Label { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: ts(2.2); font.bold: true }
                                            function doAdd() {
                                                var t = newTodoInput.text.trim()
                                                if (t.length === 0) return
                                                var todos = (_dest.todos || []).slice()
                                                todos.push({text: t, done: false})
                                                panel._setDestTodos(_idx, todos)
                                                _newTodo = ""
                                                newTodoInput.text = ""
                                            }
                                            MouseArea { id: addTodoMa; anchors.fill: parent; onClicked: addTodoBtn.doAdd() }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── POI: Cerca de mí ──────────────────────────────────────────
                Column {
                    visible: panel.hasFix && (panel._st === "idle" || panel._st === "routed")
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    spacing: units.gu(0.8)

                    // Cabecera desplegable
                    Rectangle {
                        width: parent.width; height: units.gu(3.5); color: "transparent"
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            spacing: units.gu(0.8)
                            Label { text: i18n.tr("Puntos de interés"); color: "#90A4AE"; font.pixelSize: ts(1.5) }
                            Label { text: panel._poiExpanded ? "▼" : "▶"; color: "#90A4AE"; font.pixelSize: ts(1.3) }
                        }
                        MouseArea { anchors.fill: parent; onClicked: panel._poiExpanded = !panel._poiExpanded }
                    }

                    // Contenido desplegable
                    Column {
                        visible: panel._poiExpanded
                        width: parent.width
                        spacing: units.gu(0.8)

                    // ── Selector modo + tiempo ────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: units.gu(0.5)

                        // Fila de modo (visible cuando navActive o hay destinos)
                        Row {
                            visible: panel.navActive || panel._dests.length > 0
                            width: parent.width
                            spacing: units.gu(0.8)
                            Repeater {
                                model: {
                                    var items = [{ m: "cerca", l: i18n.tr("Cercanos") }]
                                    if (panel.navActive) items.push({ m: "en_ruta", l: i18n.tr("En ruta") })
                                    if (panel._dests.length > 0) items.push({ m: "destino", l: i18n.tr("Cerca destino") })
                                    return items
                                }
                                Rectangle {
                                    width: {
                                        var n = 1 + (panel.navActive ? 1 : 0) + (panel._dests.length > 0 ? 1 : 0)
                                        return (parent.width - (n - 1) * units.gu(0.8)) / n
                                    }
                                    height: units.gu(4.5); radius: height/2
                                    color:  panel.poiMode === modelData.m ? "#1E3A5F" : "#2A2A3E"
                                    border.color: panel.poiMode === modelData.m ? "#29B6F6" : "transparent"
                                    border.width: units.gu(0.12)
                                    Label {
                                        anchors.centerIn: parent
                                        text: modelData.l
                                        color: panel.poiMode === modelData.m ? "#29B6F6" : "#78909C"
                                        font.pixelSize: ts(1.8)
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: panel.poiMode = modelData.m }
                                }
                            }
                        }

                        // Fila de tiempo
                        Row {
                            width: parent.width
                            spacing: units.gu(0.8)
                            Repeater {
                                model: [5, 10, 20]
                                Rectangle {
                                    width: (parent.width - 2 * units.gu(0.8)) / 3
                                    height: units.gu(4.5); radius: height/2
                                    color:  panel.poiMinutes === modelData ? "#1E3A5F" : "#2A2A3E"
                                    border.color: panel.poiMinutes === modelData ? "#29B6F6" : "transparent"
                                    border.width: units.gu(0.12)
                                    Label {
                                        anchors.centerIn: parent
                                        text: (panel.poiMode === "en_ruta" ? "±" : "") + modelData + " min"
                                        color: panel.poiMinutes === modelData ? "#29B6F6" : "#78909C"
                                        font.pixelSize: ts(1.8)
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: panel.poiMinutes = modelData }
                                }
                            }
                        }
                    }

                    Label {
                        text: panel.poiMode === "en_ruta"  ? i18n.tr("En ruta") :
                              panel.poiMode === "destino"  ? i18n.tr("Cerca del destino") :
                                                             i18n.tr("Cerca de mí")
                        color: "#B0BEC5"; font.pixelSize: ts(1.8)
                    }

                    Grid {
                        width: parent.width
                        columns: 4
                        spacing: units.gu(0.8)

                        Repeater {
                            model: [
                                { type: "fuel",        icon: "⛽", label: i18n.tr("Gasolina")   },
                                { type: "parking",     icon: "🅿",  label: i18n.tr("Parking")    },
                                { type: "restaurant",  icon: "🍽",  label: i18n.tr("Comer")      },
                                { type: "hotel",       icon: "🏨", label: i18n.tr("Hotel")      },
                                { type: "cafe",        icon: "☕", label: i18n.tr("Café")       },
                                { type: "supermarket", icon: "🛒", label: i18n.tr("Súper")      },
                                { type: "hospital",    icon: "🏥", label: i18n.tr("Hospital")   },
                                { type: "atm",         icon: "🏧", label: i18n.tr("Cajero")     }
                            ]
                            delegate: Rectangle {
                                width:  (parent.width - 3 * units.gu(0.8)) / 4
                                height: units.gu(7.5); radius: units.gu(0.8)
                                color:  poiCatArea.pressed ? "#1E3A5F" : "#1C1C2E"
                                Column {
                                    anchors.centerIn: parent; spacing: units.gu(0.3)
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.icon; font.pixelSize: ts(2.2)
                                    }
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.label; color: "#90A4AE"
                                        font.pixelSize: ts(1.8)
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                                MouseArea {
                                    id: poiCatArea; anchors.fill: parent
                                    onClicked: panel._searchPoi(modelData.type)
                                }
                            }
                        }
                    }
                    }  // fin Column contenido desplegable POI
                }

                // ── Favoritos ─────────────────────────────────────────────────
                Column {
                    visible: panel._favorites.length > 0 && panel._st === "idle"
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    spacing: units.gu(0.8)

                    Rectangle {
                        width: parent.width; height: units.gu(3.5); color: "transparent"
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            spacing: units.gu(0.8)
                            Label {
                                text: i18n.tr("Favoritos"); color: "#90A4AE"
                                font.pixelSize: ts(1.5)
                            }
                            Label {
                                text: panel._favsExpanded ? "▼" : "▶"
                                color: "#90A4AE"; font.pixelSize: ts(1.3)
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { panel._favsExpanded = !panel._favsExpanded; uiSt.favsExpanded = panel._favsExpanded } }
                    }

                    Repeater {
                        model: panel._favsExpanded ? panel._favorites : []
                        Rectangle {
                            anchors { left: parent.left; right: parent.right }
                            height: units.gu(7); color: "#1C1C2E"; radius: units.gu(0.8)
                            Row {
                                anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1) }
                                spacing: units.gu(1)
                                Label { anchors.verticalCenter: parent.verticalCenter
                                    text: "★"; color: "#FFD600"; font.pixelSize: ts(1.8) }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(10)
                                    Label {
                                        width: parent.width
                                        text: modelData.name; color: "white"
                                        font.pixelSize: ts(1.8); elide: Text.ElideRight
                                    }
                                    Label {
                                        width: parent.width
                                        text: modelData.address || ""; color: "#B0BEC5"
                                        font.pixelSize: ts(1.4); elide: Text.ElideRight
                                        visible: text.length > 0
                                    }
                                }
                                Item { width: units.gu(1); height: 1; anchors.verticalCenter: parent.verticalCenter }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(3.2); height: units.gu(3.2); radius: width/2; color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#B0BEC5"; font.pixelSize: ts(1.3) }
                                    MouseArea { anchors.fill: parent; onClicked: panel._removeFavorite(index) }
                                }
                            }
                            MouseArea {
                                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
                                anchors.rightMargin: units.gu(5)
                                onClicked: {
                                    focusDummy.forceActiveFocus()
                                    Qt.inputMethod.hide()
                                    if (panel._settingOrigin) {
                                        panel._simOrigin = {lat: modelData.lat, lon: modelData.lon, name: modelData.name}
                                        panel._settingOrigin = false
                                    } else {
                                        panel._addDest(modelData.lat, modelData.lon, modelData.name)
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Destinos recientes ────────────────────────────────────────
                Column {
                    visible: panel._history.length > 0 && panel._st === "idle"
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    spacing: units.gu(0.8)

                    Rectangle {
                        width: parent.width; height: units.gu(3.5); color: "transparent"
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            spacing: units.gu(0.8)
                            Label {
                                text: i18n.tr("Destinos recientes"); color: "#90A4AE"
                                font.pixelSize: ts(1.5)
                            }
                            Label {
                                text: panel._histExpanded ? "▼" : "▶"
                                color: "#90A4AE"; font.pixelSize: ts(1.3)
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { panel._histExpanded = !panel._histExpanded; uiSt.histExpanded = panel._histExpanded } }
                    }

                    Repeater {
                        model: panel._histExpanded ? panel._history : []
                        Rectangle {
                            id: histDelegate
                            anchors { left: parent.left; right: parent.right }
                            height: units.gu(9); color: "#1C1C2E"; radius: units.gu(0.8)
                            Row {
                                anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1) }
                                spacing: units.gu(0.8)
                                Label { anchors.verticalCenter: parent.verticalCenter
                                    text: "◷"; color: "#B0BEC5"; font.pixelSize: ts(1.8) }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(18)
                                    text: modelData.name; color: "#B0BEC5"
                                    font.pixelSize: ts(1.8); elide: Text.ElideRight
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(7.5); height: units.gu(7.5); radius: width/2
                                    color: panel._isFavorite(modelData.lat, modelData.lon) ? "#2A2A1A" : "transparent"
                                    Label {
                                        anchors.centerIn: parent
                                        text: panel._isFavorite(modelData.lat, modelData.lon) ? "★" : "☆"
                                        color: panel._isFavorite(modelData.lat, modelData.lon) ? "#FFD600" : "#78909C"
                                        font.pixelSize: ts(3.5)
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            panel._favPending = {lat: modelData.lat, lon: modelData.lon,
                                                                  name: modelData.name, address: ""}
                                            favNameField.text = modelData.name
                                            favNameField.forceActiveFocus()
                                        }
                                    }
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(4); height: units.gu(4); radius: width/2; color: "#2A2A3E"
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#B0BEC5"; font.pixelSize: ts(1.6) }
                                    MouseArea { anchors.fill: parent; onClicked: panel._removeFromHistory(index) }
                                }
                            }
                            MouseArea {
                                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
                                anchors.rightMargin: units.gu(14)
                                onClicked: {
                                    focusDummy.forceActiveFocus()
                                    Qt.inputMethod.hide()
                                    if (panel._settingOrigin) {
                                        panel._simOrigin = {lat: modelData.lat, lon: modelData.lon, name: modelData.name}
                                        panel._settingOrigin = false
                                    } else {
                                        panel._addDest(modelData.lat, modelData.lon, modelData.name)
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    visible: panel._st === "routed" && panel._routes.length > 0
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    spacing: units.gu(1)

                    Label { text: i18n.tr("Rutas disponibles"); color: "#90A4AE"; font.pixelSize: ts(1.8) }

                    Repeater {
                        model: panel._routes
                        Rectangle {
                            anchors { left: parent.left; right: parent.right }
                            height: units.gu(9); radius: units.gu(0.8)
                            color: panel._selRoute===index ? "#1E3A5F" : "#1C1C2E"
                            border.color: panel._selRoute===index ? "#29B6F6" : "transparent"
                            border.width: units.gu(0.2)
                            Column {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter
                                          leftMargin: units.gu(1.5) }
                                spacing: units.gu(0.2)
                                Label {
                                    text: index===0 ? i18n.tr("Ruta más rápida") : i18n.tr("Alternativa ") + index
                                    color: panel._selRoute===index ? "#29B6F6" : "white"
                                    font.pixelSize: ts(1.8); font.bold: true
                                }
                                Label {
                                    text: NavSearch.formatDist(modelData.length, panel.imperial) + "  ·  " + NavSearch.formatTime(modelData.time)
                                    color: "#B0BEC5"; font.pixelSize: ts(1.8)
                                }
                            }
                            MouseArea { anchors.fill: parent; onClicked: {
                                panel._selRoute = index
                                panel.routeReady(panel._routes, index)
                            }}
                        }
                    }

                }
            }
        }

        // ── Diálogo: nombre de favorito ───────────────────────────────────────
        Rectangle {
            id: favNameDialog
            anchors.fill: parent
            visible: panel._favPending !== null
            color: "#CC000000"
            z: 30
            onVisibleChanged: if (!visible) panel._kbdH = 0

            Connections {
                target: Qt.inputMethod
                function onVisibleChanged()          { if (!Qt.inputMethod.visible) panel._kbdH = 0; else favKbdTimer.restart() }
                function onKeyboardRectangleChanged(){ if ( Qt.inputMethod.visible && favNameDialog.visible) favKbdTimer.restart() }
            }
            Timer {
                id: favKbdTimer; interval: 50
                onTriggered: {
                    if (!Qt.inputMethod.visible || !panel._kbdFocusItem || !favNameDialog.visible) { panel._kbdH = 0; return }
                    var kbdTop = favNameDialog.height - Qt.inputMethod.keyboardRectangle.height
                    var pos    = panel._kbdFocusItem.mapToItem(favNameDialog, 0, panel._kbdFocusItem.height)
                    var fieldBottomAtZero = pos.y + panel._kbdH
                    panel._kbdH = Math.max(0, fieldBottomAtZero + units.gu(1.5) - kbdTop)
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter:   parent.verticalCenter
                anchors.verticalCenterOffset: -panel._kbdH
                width: parent.width - units.gu(6)
                height: units.gu(26)
                radius: units.gu(1.5)
                color: "#1C1C2E"

                Column {
                    anchors { fill: parent; margins: units.gu(2.5) }
                    spacing: units.gu(2)

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: i18n.tr("Guardar favorito")
                        color: "white"; font.pixelSize: ts(2); font.bold: true
                    }

                    Rectangle {
                        width: parent.width; height: units.gu(5.5)
                        color: "#12122A"; radius: units.gu(0.8)
                        Row {
                            anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1) }
                            spacing: units.gu(1)
                            Label { anchors.verticalCenter: parent.verticalCenter
                                text: "★"; color: "#FFD600"; font.pixelSize: ts(2) }
                            NavTextInput {
                                id: favNameField
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - units.gu(5)
                                color: "white"; font.pixelSize: ts(1.8)
                                inputMethodHints: Qt.ImhNoPredictiveText
                                onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                                Label {
                                    visible: parent.text.length === 0
                                    text: i18n.tr("Nombre del favorito"); color: "#90A4AE"
                                    font.pixelSize: parent.font.pixelSize
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    Label {
                        width: parent.width
                        text: panel._favPending ? (panel._favPending.address || "") : ""
                        color: "#90A4AE"; font.pixelSize: ts(1.2)
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: units.gu(2)

                        Rectangle {
                            width: units.gu(13); height: units.gu(5.5)
                            radius: units.gu(0.8); color: "#2A2A3E"
                            Label { anchors.centerIn: parent; text: i18n.tr("Cancelar")
                                color: "#B0BEC5"; font.pixelSize: ts(1.6) }
                            MouseArea { anchors.fill: parent; onClicked: {
                                Qt.inputMethod.hide()
                                panel._favPending = null
                            }}
                        }

                        Rectangle {
                            width: units.gu(13); height: units.gu(5.5)
                            radius: units.gu(0.8); color: "#1565C0"
                            Label { anchors.centerIn: parent; text: i18n.tr("Guardar")
                                color: "white"; font.pixelSize: ts(1.6); font.bold: true }
                            MouseArea { anchors.fill: parent; onClicked: {
                                var n = favNameField.text.trim()
                                if (n.length === 0 && panel._favPending) n = panel._favPending.name
                                if (panel._favPending)
                                    panel._saveFavorite(n, panel._favPending.lat,
                                                        panel._favPending.lon, panel._favPending.address)
                                Qt.inputMethod.hide()
                                panel._favPending = null
                            }}
                        }
                    }
                }
            }
        }

        // ── Spinner de routing ─────────────────────────────────────────────
        Column {
            anchors.centerIn: parent
            visible: panel._st === "routing"
            spacing: units.gu(2)
            Label { anchors.horizontalCenter: parent.horizontalCenter
                text: "⟳"; color: "#29B6F6"; font.pixelSize: ts(5)
                RotationAnimation on rotation { running: panel._st==="routing"; loops: Animation.Infinite; from:0; to:360; duration:1000 }
            }
            Label { anchors.horizontalCenter: parent.horizontalCenter
                text: i18n.tr("Calculando ruta…"); color: "white"; font.pixelSize: ts(2) }
        }
    }
}
