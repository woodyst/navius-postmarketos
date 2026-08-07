// NavSearch.js — NO .pragma library para que XMLHttpRequest esté disponible

// Photon: geocoding basado en OSM. Servidor propio con índice mundial.
// Valhalla:  routing con filtros, sin API key

var PHOTON   = "https://navius-maps.egpsistemas.com/photon"
var VALHALLA = "https://valhalla1.openstreetmap.de"

// Geocoder local de OSM Scout Server, para buscar destinos sin conexión. Mismo
// esquema que Valhalla: si el servidor está activo pasa a ser el primario y el
// online queda de respaldo; si no lo está, no cambia nada.
var OSMSCOUT_SEARCH   = "http://127.0.0.1:8553/v2/search"
var OSMSCOUT_GUIDE    = "http://127.0.0.1:8553/v1/guide"
var _osmScoutSearchOk = false
// Lo que dice el sondeo de OfflineBanner. Solo sirve para tomar atajos: sin red
// no tiene sentido recorrer los diez servidores de Overpass, a 30 s de espera
// cada uno, para acabar preguntándole al geocoder del dispositivo.
var _networkOffline   = false

var _log         = null
var _fileLog     = null
var _navHttp     = null
var _statusPush  = null
var _poiCbs      = {}
var _poiMeta     = {}
var _poiNextId   = 0
var _fallbackUrl = null
var _routeGeneration = 0
var _routeBlocked = false
var _pendingRoute = null
var _activeCosting = "auto"

function setActiveCosting(c) { _activeCosting = c || "auto" }

function setRouteBlocked(v) {
    _routeBlocked = v
    if (!v && _pendingRoute) {
        var pr = _pendingRoute
        _pendingRoute = null
        pr()
    }
}

var MINETUR_URL     = "https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/PreciosCarburantes/EstacionesTerrestres/"
var _mineturReady   = false
var _mineturLoading = false
var _mineturDbRef   = null
var _mineturTTL     = 43200000  // 12 h en ms
var _defer          = null      // Qt.callLater pasado desde QML

function setLogCallback(fn)          { _log         = fn }
function setFileLogCallback(fn)      { _fileLog     = fn }
function setNavHttp(http)            { _navHttp     = http }
function setDeferFn(fn)              { _defer       = fn }
function setStatusPushCallback(fn)   { _statusPush  = fn }
function setValhallaUrl(url)     { if (url && url.length > 4) VALHALLA = url }
function setFallbackUrl(url)     { _fallbackUrl = (url && url.length > 4) ? url : null }
function valhallaHost()          { return VALHALLA.replace(/^https?:\/\//, "").replace(/\/.*$/, "") }
// La llama Main.qml con el resultado de detectOsmScout(): mismo interruptor que
// ya conmuta las rutas y el mapa.
function setOsmScoutSearch(ok)   { _osmScoutSearchOk = !!ok }
// La llama Main.qml cuando OfflineBanner cambia de estado.
function setOffline(v)           { _networkOffline = !!v }

// autoLaunch: false = solo comprobar si ya está corriendo (arranque de la app,
// preferOsmScout pasivo — NO debe arrancar el servidor solo). true = intención
// explícita del usuario de usar OSM Scout (botón "detectar", diálogo de fallback,
// elegirlo como fuente de mapa) — sí lo arranca por activación D-Bus si hace falta.
function detectOsmScout(cb, autoLaunch) {
    // Fase 1: intento rápido — ya está corriendo
    _detectOsmScoutTry(function(found) {
        if (found) { cb(true); return }
        if (!autoLaunch) { cb(false); return }
        // Fase 2: lo arrancamos nosotros por activación D-Bus (io.github.rinigus.
        // OSMScoutServer, ver ensure_osmscout_running en NavHttp) y esperamos
        // hasta 30s a que cargue mapas y responda.
        _fileDump("OSM Scout: no estaba corriendo — activando por D-Bus (hasta 30s)…")
        _logMsg("OSM Scout: activando…")
        if (_navHttp) _navHttp.ensure_osmscout_running()
        _detectOsmScoutTry(cb, 1, 99, 30000)
    }, 2, 0, 2000)
}

function _detectOsmScoutTry(cb, left, attempt, timeout) {
    var xhr = new XMLHttpRequest()
    var _done = false
    var tag = "OSM Scout (intento " + (attempt + 1) + ")"
    _fileDump(tag + ": GET 127.0.0.1:8553/v1/activate timeout=" + timeout)
    xhr.open("GET", "http://127.0.0.1:8553/v1/activate")
    xhr.timeout = timeout
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4 || _done) return
        _done = true
        if (xhr.status > 0) {
            _fileDump(tag + ": OK status=" + xhr.status)
            _logMsg("OSM Scout: disponible (status " + xhr.status + ")")
            cb(true)
        } else if (left > 1) {
            _fileDump(tag + ": status=0, reintentando…")
            if (_defer) _defer(function() { _detectOsmScoutTry(cb, left - 1, attempt + 1, timeout) }, 500)
        } else {
            _fileDump(tag + ": status=0, sin más intentos")
            _logMsg("OSM Scout: no disponible")
            cb(false)
        }
    }
    xhr.ontimeout = function() {
        if (_done) return; _done = true
        if (left > 1) {
            _fileDump(tag + ": timeout, reintentando…")
            if (_defer) _defer(function() { _detectOsmScoutTry(cb, left - 1, attempt + 1, timeout) }, 500)
        } else {
            _fileDump(tag + ": timeout final")
            _logMsg("OSM Scout: no disponible")
            cb(false)
        }
    }
    xhr.onerror = function() {
        if (_done) return; _done = true
        if (left > 1) {
            _fileDump(tag + ": onerror, reintentando…")
            if (_defer) _defer(function() { _detectOsmScoutTry(cb, left - 1, attempt + 1, timeout) }, 500)
        } else {
            _fileDump(tag + ": onerror final")
            _logMsg("OSM Scout: no disponible")
            cb(false)
        }
    }
    xhr.send()
}

function pingOsmScout(cb) {
    var xhr = new XMLHttpRequest()
    xhr.open("GET", "http://127.0.0.1:8553/v1/activate")
    xhr.timeout = 2500
    var _done = false
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4 || _done) return
        _done = true
        cb(xhr.status > 0)
    }
    xhr.ontimeout = function() { if (!_done) { _done = true; cb(false) } }
    xhr.onerror   = function() { if (!_done) { _done = true; cb(false) } }
    xhr.send()
}

function pingTileServer(tileBaseUrl, lat, lon, cb) {
    var z = 10
    var x = Math.floor((lon + 180) / 360 * (1 << z))
    var latRad = lat * Math.PI / 180
    var y = Math.floor((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2 * (1 << z))
    var xhr = new XMLHttpRequest()
    xhr.open("GET", tileBaseUrl + z + "/" + x + "/" + y)
    xhr.timeout = 8000
    var _done = false
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4 || _done) return
        _done = true
        cb(xhr.status >= 200 && xhr.status < 400)
    }
    xhr.ontimeout = function() { if (!_done) { _done = true; cb(false) } }
    xhr.onerror   = function() { if (!_done) { _done = true; cb(false) } }
    xhr.send()
}

function _logMsg(msg)            { if (_log)     _log(msg) }
function _fileDump(msg)          { if (_fileLog) _fileLog(msg) }

function _inSpain(lat, lon) {
    return lat > 35.5 && lat < 44.5 && lon > -9.5 && lon < 4.5
}

// Llamar desde QML (donde LocalStorage sí está disponible) pasando el objeto DB abierto.
function setMineturDb(db) {
    _mineturDbRef = db
    if (!_mineturDbRef) return
    try {
        _mineturDbRef.transaction(function(tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
            tx.executeSql("CREATE TABLE IF NOT EXISTS stations (lat REAL, lon REAL, g95 TEXT, diesel TEXT, g98 TEXT)")
            tx.executeSql("CREATE INDEX IF NOT EXISTS idx_ll ON stations(lat, lon)")
        })
    } catch(e) { _logMsg("✗ MINETUR DB init: " + e); _mineturDbRef = null }
}

function _mineturDb() { return _mineturDbRef }

function _mineturCacheTs() {
    var db = _mineturDb(); if (!db) return 0
    var ts = 0
    try { db.readTransaction(function(tx) {
        var r = tx.executeSql("SELECT value FROM meta WHERE key='ts'")
        if (r.rows.length > 0) ts = parseInt(r.rows.item(0).value) || 0
    }) } catch(e) {}
    return ts
}

function _mineturPopulate(stations) {
    var db = _mineturDb(); if (!db) { _mineturReady = true; return }
    try { db.transaction(function(tx) { tx.executeSql("DELETE FROM stations") }) }
    catch(e) { _logMsg("✗ MINETUR clear: " + e); _mineturReady = true; return }
    _mineturBatch(stations, 0)
}

function _mineturBatch(stations, offset) {
    var db = _mineturDb(); if (!db) { _mineturReady = true; return }
    var BATCH = 500
    var end = Math.min(offset + BATCH, stations.length)
    try {
        db.transaction(function(tx) {
            for (var i = offset; i < end; i++) {
                var s   = stations[i]
                var lat = parseFloat((s["Latitud"] || "").replace(",", "."))
                var lon = parseFloat((s["Longitud (WGS84)"] || s["Longitud"] || "").replace(",", "."))
                if (isNaN(lat) || isNaN(lon)) continue
                var g95 = (s["Precio Gasolina 95 E5"] || "").trim().replace(",", ".")
                var die = (s["Precio Gasoleo A"]       || "").trim().replace(",", ".")
                var g98 = (s["Precio Gasolina 98 E5"]  || "").trim().replace(",", ".")
                tx.executeSql("INSERT INTO stations VALUES (?,?,?,?,?)", [lat, lon, g95, die, g98])
            }
        })
    } catch(e) { _logMsg("✗ MINETUR batch " + offset + ": " + e) }
    if (end < stations.length) {
        var nextOff = end
        if (_defer) _defer(function() { _mineturBatch(stations, nextOff) })
        else        _mineturBatch(stations, nextOff)
    } else {
        try { db.transaction(function(tx) {
            tx.executeSql("INSERT OR REPLACE INTO meta VALUES ('ts',?)", [String(Date.now())])
        }) } catch(e) {}
        _logMsg("MINETUR: " + stations.length + " est. en BD")
        _mineturReady = true
    }
}

function mineturCacheDate() {
    var ts = _mineturCacheTs()
    if (ts <= 0) return ""
    var d = new Date(ts)
    var now = new Date()
    var p = function(n) { return n < 10 ? "0" + n : "" + n }
    var timeStr = p(d.getHours()) + ":" + p(d.getMinutes())
    var daysDiff = Math.floor((now - d) / 86400000)
    if (daysDiff === 0) return "hoy a las " + timeStr
    if (daysDiff === 1) return "ayer a las " + timeStr
    return "hace " + daysDiff + " días a las " + timeStr
}

function _mineturPriceFromDb(elLat, elLon) {
    var db = _mineturDb(); if (!db) return ""
    var dlat = 0.005
    var dlon = dlat / Math.cos(elLat * Math.PI / 180)
    var result = ""
    try {
        db.readTransaction(function(tx) {
            var r = tx.executeSql(
                "SELECT lat,lon,g95,diesel,g98 FROM stations WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
                [elLat-dlat, elLat+dlat, elLon-dlon, elLon+dlon])
            var best = null, bestD = 0.5
            for (var i = 0; i < r.rows.length; i++) {
                var s = r.rows.item(i)
                var d = _haversineKm(elLat, elLon, s.lat, s.lon)
                if (d < bestD) { bestD = d; best = s }
            }
            if (best) {
                var parts = []
                if (best.g95)    parts.push("G95 "    + best.g95    + " €")
                if (best.diesel) parts.push("Diésel "  + best.diesel + " €")
                if (best.g98)    parts.push("G98 "    + best.g98    + " €")
                result = parts.join(" · ")
            }
        })
    } catch(e) {}
    return result
}

function _fetchMinetur() {
    if (_mineturLoading) return
    _mineturLoading = true
    _logMsg("Consultando precios de combustible…")
    _xhr("GET", MINETUR_URL, null, function(err, text) {
        _mineturLoading = false
        if (!err) {
            try { _mineturPopulate(JSON.parse(text).ListaEESSPrecio || []) }
            catch(e) { _logMsg("✗ MINETUR parse: " + e); _mineturReady = true }
        } else { _logMsg("✗ MINETUR: " + err); _mineturReady = true }
    }, 5000)
}

// Llamar al arrancar la app: usa BD local si es reciente, si no descarga.
function initMinetur() {
    var ts = _mineturCacheTs()
    if (ts > 0 && (Date.now() - ts) < _mineturTTL) {
        _mineturReady = true
        _logMsg("MINETUR: BD local (" + Math.round((Date.now()-ts)/3600000) + " h)")
        return
    }
    _fetchMinetur()
}

// Llamar desde el Timer de 12 h.
function refreshMinetur() {
    if (_mineturReady && (Date.now() - _mineturCacheTs()) < _mineturTTL) return
    _mineturReady = false
    _fetchMinetur()
}

function _poiDetail(type, tags) {
    if (type === "fuel") {
        var fuels = []
        if (tags["fuel:octane_95"] === "yes") fuels.push("G95")
        if (tags["fuel:octane_98"] === "yes") fuels.push("G98")
        if (tags["fuel:diesel"]    === "yes") fuels.push("Diésel")
        else if (tags["fuel:diesel_B"] === "yes") fuels.push("Diésel B")
        if (tags["fuel:lpg"]       === "yes") fuels.push("GLP")
        if (tags["fuel:electric"]  === "yes") fuels.push("Eléctrico")
        if (tags["fuel:adblue"]    === "yes") fuels.push("AdBlue")
        return fuels.join(" · ")
    }
    if (type === "hotel") {
        var parts = []
        var stars = parseInt(tags["stars"])
        if (stars > 0) { var s = ""; for (var i = 0; i < stars && i < 5; i++) s += "★"; parts.push(s) }
        if (tags["rooms"]) parts.push(tags["rooms"] + " hab.")
        if (tags["opening_hours"]) parts.push(tags["opening_hours"])
        return parts.join(" · ")
    }
    if (type === "restaurant" || type === "cafe") {
        var parts = []
        if (tags["cuisine"]) parts.push(tags["cuisine"].replace(/;/g, ", ").replace(/_/g, " "))
        if (tags["opening_hours"]) parts.push(tags["opening_hours"])
        return parts.join(" · ")
    }
    if (type === "parking") {
        var parts = []
        if      (tags["fee"] === "no")  parts.push("Gratis")
        else if (tags["fee"] === "yes") parts.push("De pago")
        if (tags["capacity"]) parts.push(tags["capacity"] + " plazas")
        if (tags["maxstay"])  parts.push("Máx. " + tags["maxstay"])
        return parts.join(" · ")
    }
    if (type === "hospital") {
        if (tags["emergency"] === "yes") return "Urgencias 24h"
        if (tags["emergency"] === "no")  return "Sin urgencias"
        return ""
    }
    if (type === "atm") {
        var parts = []
        if (tags["operator"])        parts.push(tags["operator"])
        if (tags["opening_hours"])   parts.push(tags["opening_hours"])
        return parts.join(" · ")
    }
    if (type === "supermarket") {
        return tags["opening_hours"] || ""
    }
    return ""
}

function processOverpassResult(cbId, json, err) {
    var cb   = _poiCbs[cbId]
    var meta = _poiMeta[cbId] || {}
    if (!cb) return
    delete _poiCbs[cbId]; delete _poiMeta[cbId]
    if (err) { _logMsg("✗ POI proxy: " + err); _fileDump("POI ERROR: " + err); cb(err, []); return }
    _fileDump("--- POI RESPONSE (" + (json ? json.length : 0) + " bytes): " + (json ? json.substring(0, 500) : "(vacío)"))
    try {
        var data    = JSON.parse(json)
        _fileDump("POI elementos raw: " + (data.elements ? data.elements.length : 0))
        var results = []
        var lat = meta.lat || 0, lon = meta.lon || 0, def = meta.def || {}
        for (var i = 0; i < data.elements.length; i++) {
            var el    = data.elements[i]
            var elLat = el.lat !== undefined ? el.lat : (el.center ? el.center.lat : undefined)
            var elLon = el.lon !== undefined ? el.lon : (el.center ? el.center.lon : undefined)
            if (elLat === undefined || elLon === undefined) continue
            var t    = el.tags || {}
            var name = t.name || t.brand || def.label
            var dist = _haversineKm(lat, lon, elLat, elLon)
            var addr = t["addr:street"]
                     ? t["addr:street"] + (t["addr:housenumber"] ? " " + t["addr:housenumber"] : "")
                     : (t["addr:city"] || t.brand || "")
            var distStr = _distLabel(dist)
            var spd = meta.navSpeedKmh || 0
            var skipResult = false
            if (spd > 0) {
                // Desvío: distancia desde el punto de ruta más cercano al POI (no desde posición actual)
                var deviationKm = dist
                var seg = meta.routeSegment
                if (seg && seg.length > 0) {
                    var bestD2 = 1e18, nearLat2 = seg[0][1], nearLon2 = seg[0][0]
                    var cosEl = Math.cos(elLat * Math.PI / 180)
                    for (var si = 0; si < seg.length; si++) {
                        var dla2 = (elLat - seg[si][1]) * 111319
                        var dlo2 = (elLon - seg[si][0]) * 111319 * cosEl
                        var d2sq = dla2*dla2 + dlo2*dlo2
                        if (d2sq < bestD2) { bestD2 = d2sq; nearLat2 = seg[si][1]; nearLon2 = seg[si][0] }
                    }
                    deviationKm = _haversineKm(nearLat2, nearLon2, elLat, elLon)
                }
                var oneWayMin = Math.max(1, Math.round(dist * 60 / spd))
                var detourMin = Math.max(1, Math.round(2 * deviationKm * 60 / spd))
                if (meta.maxDetourMin > 0 && detourMin > meta.maxDetourMin) { skipResult = true }
                else distStr = oneWayMin + " min · +" + detourMin + " min · " + distStr
            }
            if (skipResult) continue
            var sub    = addr ? (distStr + " · " + addr) : distStr
            var detail = _poiDetail(meta.type || "", t)
            results.push({
                _isPoi: true, _dist: dist,
                geometry:   { coordinates: [elLon, elLat] },
                properties: { name: def.icon + " " + name, city: sub, detail: detail }
            })
        }
        results.sort(function(a, b) { return a._dist - b._dist })
        if (meta.type === "fuel" && _mineturReady && _inSpain(lat, lon)) {
            for (var j = 0; j < results.length; j++) {
                var coords = results[j].geometry.coordinates
                var priceStr = _mineturPriceFromDb(coords[1], coords[0])
                if (priceStr) results[j].properties.detail = priceStr
            }
        }
        _logMsg("POI: " + results.length + " resultado(s)")
        _fileDump("POI resultados: " + results.length)
        for (var ri = 0; ri < Math.min(results.length, 10); ri++) {
            var r = results[ri]
            _fileDump("  " + (ri+1) + ". " + r.properties.name + " | " + r.properties.city
                      + " | " + r.geometry.coordinates[1].toFixed(5) + "," + r.geometry.coordinates[0].toFixed(5))
        }
        cb(null, results)
    } catch(e) { cb("Error POI: " + e, []) }
}

// Photon soporta: de, en, fr. Usamos el idioma del sistema si es uno de esos, si no 'en'.
function _photonLang() {
    // Servidor propio: solo soporta de/en/fr/default. Usamos default (nombre local OSM).
    return "default"
}

var PHOTON_FALLBACK = "https://photon.komoot.io"

// Busca lugares con Photon. aroundLat/Lon: centro para biasing (0,0 para ignorar).
// callback(error, resultArray)  — results son GeoJSON Features
function geocode(query, aroundLat, aroundLon, callback) {
    var qs = "/api/?q=" + encodeURIComponent(query) + "&limit=6&lang=" + _photonLang()
    if (aroundLat !== 0 || aroundLon !== 0)
        qs += "&lat=" + aroundLat + "&lon=" + aroundLon
    var url = PHOTON + qs
    _logMsg("Geocoding: «" + query + "»")
    _fileDump("=== GEOCODE: " + query
              + " | gps=" + aroundLat.toFixed(5) + "," + aroundLon.toFixed(5)
              + " | url=" + url)
    function _parse(text, cb) {
        try {
            var fc = JSON.parse(text)
            var results = fc.features || []
            _logMsg("Resultados: " + results.length + " lugar(es)")
            cb(null, results)
        } catch(e) { _logMsg("✗ Parse error: " + e); cb("Parse error", []) }
    }
    // El geocoder local devuelve {title, admin_region, lat, lng, type}, no
    // GeoJSON. Se convierte a Feature de Photon para que photonLabel() y todo
    // lo que consume estos resultados sigan funcionando sin enterarse.
    function _parseOsmScout(text, cb) {
        try {
            var raw = JSON.parse(text)
            var arr = raw.result || raw   // /v2 envuelve en {result}, /v1 no
            var results = []
            var conRef = (aroundLat !== 0 || aroundLon !== 0)
            for (var i = 0; i < arr.length; i++) {
                var r = arr[i]
                if (r.lat === undefined || r.lng === undefined) continue
                results.push({
                    _n:  results.length,
                    _km: conRef ? _haversineKm(aroundLat, aroundLon, r.lat, r.lng) : 0,
                    geometry:   { coordinates: [r.lng, r.lat] },
                    properties: { name: r.title || "", city: r.admin_region || "",
                                  osm_value: r.type || "" }
                })
            }
            // El geocoder local NO ordena por cercanía aunque se le pase el punto
            // de referencia: su sesgo por distancia tiene el radio clavado en
            // 250 m, así que más allá de dos kilómetros da igual dónde estés.
            // Buscando «Barcelona» desde Barcelona los primeros eran calles de
            // Salamanca, León y Jaén. Se ordena aquí, no en el servidor, porque
            // UT y postmarketOS hablan con el OSM Scout de rinigus, que no
            // podemos tocar. El desempate por _n mantiene el orden del servidor
            // entre los que están igual de lejos.
            if (conRef) {
                results.sort(function(a, b) { return (a._km - b._km) || (a._n - b._n) })
                // Al servidor se le piden 25 justo para poder elegir: si solo se
                // le pidieran 6, ordenarlos no serviría de nada cuando los seis
                // que manda están todos al otro lado del país.
                results = results.slice(0, 6)
            }
            _logMsg("Resultados: " + results.length + " lugar(es) · offline")
            cb(null, results)
        } catch(e) { _logMsg("✗ Parse error geocoder local: " + e); cb("Parse error", []) }
    }

    function _tryOsmScout(cb) {
        // 25 y no 6: los que sobran son el margen con el que _parseOsmScout
        // puede quedarse con los más cercanos. Son unos pocos kB de más y el
        // servidor está en el propio dispositivo.
        var lu = OSMSCOUT_SEARCH + "?search=" + encodeURIComponent(query) + "&limit=25"
        if (aroundLat !== 0 || aroundLon !== 0)
            lu += "&lat=" + aroundLat + "&lng=" + aroundLon
        _fileDump("GEOCODE local: " + lu)
        // 6 s como en las rutas locales: es el mismo dispositivo, si tarda más
        // es que algo va mal, no que la red esté lenta.
        _xhr("GET", lu, null, function(errL, textL) {
            if (errL) { cb(errL, []); return }
            _parseOsmScout(textL, cb)
        }, 6000)
    }

    function _tryKomoot(cb) {
        // Fallback a photon.komoot.io (soporta de/en/fr/it, no es → lang=en)
        var fbLang = (["de","en","fr","it"].indexOf(_photonLang()) >= 0) ? _photonLang() : "en"
        var fbUrl = PHOTON_FALLBACK + "/api/?q=" + encodeURIComponent(query) + "&limit=6&lang=" + fbLang
        if (aroundLat !== 0 || aroundLon !== 0)
            fbUrl += "&lat=" + aroundLat + "&lon=" + aroundLon
        _fileDump("GEOCODE fallback: " + fbUrl)
        _logMsg("Photon: servidor propio no disponible · usando komoot…")
        _xhr("GET", fbUrl, null, function(errFb, textFb) {
            if (errFb) { cb(errFb, []); return }
            _parse(textFb, cb)
        }, 6000)
    }

    // Orden: online primero y el geocoder local de respaldo. A diferencia de las
    // rutas, aquí el online NO se sustituye aunque haya servidor local, porque
    // su índice es mundial y está más al día; el local es una instantánea de los
    // territorios que se hayan instalado.
    //
    // El local va antes que komoot a propósito: si Photon ha fallado suele ser
    // por falta de cobertura, y entonces komoot fallaría igual tras otros 6 s de
    // espera, mientras que el local responde en el acto.
    _xhr("GET", url, null, function(err, text) {
        if (!err) { _parse(text, callback); return }

        if (!_osmScoutSearchOk) { _tryKomoot(callback); return }

        _fileDump("GEOCODE: Photon falló (" + err + "), probando el geocoder local")
        _logMsg("Sin red · buscando en los mapas del dispositivo…")
        _tryOsmScout(function(errL, resL) {
            if (!errL && resL.length > 0) { callback(null, resL); return }
            _tryKomoot(callback)
        })
    }, 6000)
}

// Construye texto de display para un resultado Photon (GeoJSON Feature)
function photonLabel(f) {
    var p    = f.properties
    var name = p.name || p.city || p.town || p.village || ""
    var parts = []
    if (name) parts.push(name)
    if (p.city   && p.city   !== name) parts.push(p.city)
    if (p.state  && p.state  !== name) parts.push(p.state)
    if (p.country)                     parts.push(p.country)
    return parts.join(", ")
}

function photonShortName(f) {
    var p = f.properties
    return p.name || p.city || p.town || p.village || photonLabel(f)
}

function photonSubtitle(f) {
    var p    = f.properties
    var name = p.name || p.city || p.town || p.village || ""
    var parts = []
    if (p.city    && p.city    !== name) parts.push(p.city)
    if (p.county  && p.county  !== name) parts.push(p.county)
    if (p.state   && p.state   !== name) parts.push(p.state)
    if (p.country)                       parts.push(p.country)
    return parts.join(", ")
}

// ── POI (Puntos de Interés) via Overpass API ─────────────────────────────────
var OVERPASS          = "https://z.overpass-api.de/api/interpreter"  // legacy
var OVERPASS_FALLBACK = "https://z.overpass-api.de/api/interpreter"
var OVERPASS_NAVIUS       = "https://navius-maps.egpsistemas.com/overpass/api/interpreter"
var OVERPASS_NAVIUS_WORLD = "https://navius-maps.egpsistemas.com/overpass-world/api/interpreter"
var _overpassNaviusEnabled = true

// Lista de servidores públicos Overpass — excluir overpass-api.de (rate limit estricto
// en queries reales aunque pase el probe con node(1))
var OVERPASS_CANDIDATES = [
    "https://z.overpass-api.de/api/interpreter",
    "https://overpass.osm.ch/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.openstreetmap.ru/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
    "https://overpass.datagrepper.online/api/interpreter",
    "https://overpass.nchc.org.tw/api/interpreter",
    "https://overpass.openstreetmap.fr/api/interpreter"
]

// Pool activo: se rellena al arrancar con los que responden. Mín. 1 (fallback garantizado)
var _overpassActivePool = ["https://z.overpass-api.de/api/interpreter"]

function setNaviusServer(enabled) {
    _overpassNaviusEnabled = enabled
}

// Sondea todos los candidatos con una query mínima y construye _overpassActivePool.
// Llamar desde Main.qml al arrancar la app (una sola vez).
function probeOverpassServers() {
    var probe = "[out:json][timeout:8];node(1);out ids;"
    var found = []
    var pending = OVERPASS_CANDIDATES.length
    for (var i = 0; i < OVERPASS_CANDIDATES.length; i++) {
        (function(url) {
            var xhr = new XMLHttpRequest()
            xhr.open("POST", url)
            xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
            xhr.timeout = 9000
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                if (xhr.status === 200) {
                    found.push(url)
                    _logMsg("Overpass OK: " + url)
                } else {
                    _logMsg("Overpass KO: " + url + " (" + xhr.status + ")")
                }
                pending--
                if (pending === 0) {
                    _overpassActivePool = found.length > 0 ? found : [OVERPASS_FALLBACK]
                    _logMsg("Pool Overpass activo: " + _overpassActivePool.length + " servidor(es)")
                }
            }
            xhr.send("data=" + encodeURIComponent(probe))
        })(OVERPASS_CANDIDATES[i])
    }
}

// Elige servidor: navius mundial primero (réplica minutal, siempre al día).
// El servidor de España tiene la replicación rota y
// puede llevar semanas de desfase, así que solo se usa como fallback.
function _overpassForPos(lat, lon) {
    if (!_overpassNaviusEnabled) return _overpassActivePool[Math.floor(Math.random() * _overpassActivePool.length)]
    return OVERPASS_NAVIUS_WORLD
}

// Siguiente servidor no intentado: navius España (si aplica) → pool público
function _overpassNext(tried, lat, lon) {
    if (_overpassNaviusEnabled && lat !== undefined && _inSpain(lat, lon) && tried.indexOf(OVERPASS_NAVIUS) < 0)
        return OVERPASS_NAVIUS
    var fromPool = _overpassActivePool.filter(function(u) { return tried.indexOf(u) < 0 })
    if (fromPool.length > 0) return fromPool[0]
    var fromAll = OVERPASS_CANDIDATES.filter(function(u) { return tried.indexOf(u) < 0 })
    return fromAll.length > 0 ? fromAll[0] : null
}


function poiDef(type) { return _poiDefs[type] || null }

var _poiDefs = {
    "fuel":        { tag: "amenity", val: "fuel",        icon: "⛽", label: "Gasolinera",   q: "fuel station"  },
    "parking":     { tag: "amenity", val: "parking",     icon: "🅿",  label: "Aparcamiento", q: "parking"       },
    "hotel":       { tag: "tourism", val: "hotel",       icon: "🏨", label: "Hotel",         q: "hotel"         },
    "restaurant":  { tag: "amenity", val: "restaurant",  icon: "🍽",  label: "Restaurante",  q: "restaurant"    },
    "hospital":    { tag: "amenity", val: "hospital",    icon: "🏥", label: "Hospital",      q: "hospital"      },
    "cafe":        { tag: "amenity", val: "cafe",        icon: "☕", label: "Cafetería",     q: "cafe"          },
    "supermarket": { tag: "shop",    val: "supermarket", icon: "🛒", label: "Supermercado",  q: "supermarket"   },
    "atm":         { tag: "amenity", val: "atm",         icon: "🏧", label: "Cajero",        q: "ATM"           }
}

function _haversineKm(lat1, lon1, lat2, lon2) {
    var R = 6371, d2r = Math.PI / 180
    var dLat = (lat2 - lat1) * d2r, dLon = (lon2 - lon1) * d2r
    var a = Math.sin(dLat/2)*Math.sin(dLat/2)
          + Math.cos(lat1*d2r)*Math.cos(lat2*d2r)*Math.sin(dLon/2)*Math.sin(dLon/2)
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

function _distLabel(km) {
    return km < 1 ? Math.round(km * 1000) + " m" : km.toFixed(1) + " km"
}

// Los POIs del dispositivo, vía /v1/guide de OSM Scout Server. Devuelve por el
// mismo callback y con la misma forma que Overpass ({elements:[…]}) para que
// _poiProcess no tenga que enterarse de por dónde vinieron.
//
// El tipo del geocoder es la etiqueta OSM con guión bajo: amenity=fuel es
// "amenity_fuel", que es justo tag + "_" + val de _poiDefs.
var POI_LOCAL_MAX_PTS = 40

function _poiOsmScout(meta, callback) {
    var def  = meta.def || {}
    var type = (def.tag && def.val) ? def.tag + "_" + def.val : ""
    if (!type) { callback("Sin tipo de POI para el geocoder local", null, meta); return }

    // El geocoder consulta un punto y un radio, no una unión de «around» como
    // Overpass, así que en modo «en ruta» hay que repetir por cada muestra.
    var pts = (meta.samples && meta.samples.length > 0)
              ? meta.samples
              : [{ lat: (meta.qLat !== undefined ? meta.qLat : meta.lat),
                   lon: (meta.qLon !== undefined ? meta.qLon : meta.lon) }]
    if (pts.length > POI_LOCAL_MAX_PTS) {
        _logMsg("POI local: ruta larga · se consultan " + POI_LOCAL_MAX_PTS
                + " de " + pts.length + " puntos")
        pts = pts.slice(0, POI_LOCAL_MAX_PTS)
    }

    var radius = meta.radiusM || 1000
    var elements = [], seen = {}, idx = 0, errs = 0

    // En serie, no en paralelo: son consultas locales de milisegundos y no
    // merece la pena echarle cuarenta peticiones simultáneas al servidor.
    function _step() {
        if (idx >= pts.length) {
            if (elements.length === 0 && errs === pts.length) {
                callback("El geocoder del dispositivo no respondió", null, meta)
            } else {
                _logMsg("POI: " + elements.length + " en los mapas del dispositivo")
                callback(null, { elements: elements }, meta)
            }
            return
        }
        var p = pts[idx++]
        var u = OSMSCOUT_GUIDE + "?poitype=" + encodeURIComponent(type)
              + "&lat=" + p.lat.toFixed(6) + "&lng=" + p.lon.toFixed(6)
              + "&radius=" + Math.round(radius) + "&limit=50"
        _xhr("GET", u, null, function(err, text) {
            if (err) { errs++; _step(); return }
            try {
                var arr = JSON.parse(text).results || []
                for (var k = 0; k < arr.length; k++) {
                    var r = arr[k]
                    if (r.lat === undefined || r.lng === undefined) continue
                    var key = r.lat.toFixed(6) + "," + r.lng.toFixed(6)
                    if (seen[key]) continue   // las muestras de la ruta se solapan
                    seen[key] = true
                    // El «title» del geocoder viene como «Nombre, número, calle»
                    // y el «admin_region» arrastra hasta el país. Se parte por
                    // la primera coma: el nombre a la primera línea y el resto
                    // de dirección al subtítulo, que es lo que hace Overpass.
                    var t = (r.title || "").split(",")
                    var nombre = t.shift().trim()
                    elements.push({
                        lat: r.lat, lon: r.lng,
                        tags: { name: nombre || def.label,
                                "addr:street": t.join(",").trim() }
                    })
                }
            } catch(e) { errs++ }
            _step()
        }, 6000)
    }
    _step()
}

// Envía query Overpass via XHR y llama callback(json|null)
function _poiPost(q, meta, callback, _tried, _zeroRetries) {
    if (!_tried) _tried = []
    if (!_zeroRetries) _zeroRetries = 0
    // Sin red y con servidor local: derecho al geocoder del dispositivo. El
    // online sigue siendo el primario cuando hay cobertura, igual que en la
    // búsqueda de destinos, porque su índice está más al día.
    if (_tried.length === 0 && _networkOffline && _osmScoutSearchOk) {
        _logMsg("Sin red · buscando POIs en los mapas del dispositivo…")
        _poiOsmScout(meta, callback)
        return
    }
    var sLat = meta.qLat !== undefined ? meta.qLat : meta.lat
    var sLon = meta.qLon !== undefined ? meta.qLon : meta.lon
    var _srv = _tried.length === 0 ? _overpassForPos(sLat, sLon) : _overpassNext(_tried, sLat, sLon)
    if (!_srv) {
        if (_osmScoutSearchOk) {
            _logMsg("Overpass agotado · probando los mapas del dispositivo")
            _poiOsmScout(meta, callback)
            return
        }
        if (_statusPush) _statusPush("Sin red · búsqueda POI", "#EF9A9A")
        callback("Sin servidores Overpass disponibles", null, meta)
        return
    }
    _tried = _tried.concat([_srv])
    _logMsg("→ Overpass POI " + _srv + (_tried.length > 1 ? " (intento " + _tried.length + ")" : ""))
    _fileDump("--- POI QUERY: " + q)
    var xhr = new XMLHttpRequest()
    xhr.open("POST", _srv)
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    xhr.setRequestHeader("Accept", "*/*")
    xhr.setRequestHeader("User-Agent", "Navius/1.0 (navigation app)")
    xhr.timeout = 30000
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status === 200) {
            _fileDump("--- POI RESPONSE (" + xhr.responseText.length + " bytes): " + xhr.responseText.substring(0, 500))
            try {
                var data = JSON.parse(xhr.responseText)
                var n = data.elements ? data.elements.length : 0
                _fileDump("POI elementos raw: " + n)
                if (n === 0 && _zeroRetries < 2) {
                    _logMsg("Overpass POI 0 resultados en " + _srv + ", reintentando")
                    _poiPost(q, meta, callback, _tried, _zeroRetries + 1)
                } else {
                    callback(null, data, meta)
                }
            } catch(e) { callback("Error parse: " + e, null, meta) }
        } else {
            _fileDump("POI ERROR HTTP: " + xhr.status + " | " + _srv)
            _poiPost(q, meta, callback, _tried, _zeroRetries)
        }
    }
    xhr.ontimeout = function() {
        _fileDump("POI ERROR: timeout " + _srv)
        _poiPost(q, meta, callback, _tried, _zeroRetries)
    }
    xhr.send("data=" + encodeURIComponent(q))
}

// Procesa datos Overpass y construye lista de resultados
function _poiProcess(err, data, meta, callback) {
    if (err) { _logMsg("✗ POI: " + err); callback(err, []); return }
    try {
        var results = []
        var lat = meta.lat || 0, lon = meta.lon || 0, def = meta.def || {}
        for (var i = 0; i < data.elements.length; i++) {
            var el    = data.elements[i]
            var elLat = el.lat !== undefined ? el.lat : (el.center ? el.center.lat : undefined)
            var elLon = el.lon !== undefined ? el.lon : (el.center ? el.center.lon : undefined)
            if (elLat === undefined || elLon === undefined) continue
            var t    = el.tags || {}
            var name = t.name || t.brand || def.label
            var dist = _haversineKm(lat, lon, elLat, elLon)
            var addr = t["addr:street"]
                     ? t["addr:street"] + (t["addr:housenumber"] ? " " + t["addr:housenumber"] : "")
                     : (t["addr:city"] || t.brand || "")
            var distStr = _distLabel(dist)
            var spd = meta.navSpeedKmh || 0
            var skipResult = false
            if (spd > 0) {
                var deviationKm = dist
                var seg = meta.routeSegment
                if (seg && seg.length > 0) {
                    var bestD2 = 1e18
                    var cosEl = Math.cos(elLat * Math.PI / 180)
                    var nearLat2 = seg[0][1], nearLon2 = seg[0][0]
                    for (var si = 0; si < seg.length; si++) {
                        var dla2 = (elLat - seg[si][1]) * 111319
                        var dlo2 = (elLon - seg[si][0]) * 111319 * cosEl
                        var d2sq = dla2*dla2 + dlo2*dlo2
                        if (d2sq < bestD2) { bestD2 = d2sq; nearLat2 = seg[si][1]; nearLon2 = seg[si][0] }
                    }
                    deviationKm = _haversineKm(nearLat2, nearLon2, elLat, elLon)
                }
                var oneWayMin = Math.max(1, Math.round(dist * 60 / spd))
                var detourMin = Math.max(1, Math.round(2 * deviationKm * 60 / spd))
                if (meta.maxDetourMin > 0 && detourMin > meta.maxDetourMin) { skipResult = true }
                else distStr = oneWayMin + " min · +" + detourMin + " min · " + distStr
            }
            if (skipResult) continue
            var sub    = addr ? (distStr + " · " + addr) : distStr
            var detail = _poiDetail(meta.type || "", t)
            results.push({
                _isPoi: true, _dist: dist,
                geometry:   { coordinates: [elLon, elLat] },
                properties: { name: def.icon + " " + name, city: sub, detail: detail }
            })
        }
        results.sort(function(a, b) { return a._dist - b._dist })
        if (meta.type === "fuel" && _mineturReady && _inSpain(lat, lon)) {
            for (var j = 0; j < results.length; j++) {
                var coords = results[j].geometry.coordinates
                var priceStr = _mineturPriceFromDb(coords[1], coords[0])
                if (priceStr) results[j].properties.detail = priceStr
            }
        }
        _logMsg("POI: " + results.length + " resultado(s)")
        _fileDump("POI resultados: " + results.length)
        for (var ri = 0; ri < Math.min(results.length, 10); ri++) {
            var r = results[ri]
            _fileDump("  " + (ri+1) + ". " + r.properties.name + " | " + r.properties.city
                      + " | " + r.geometry.coordinates[1].toFixed(5) + "," + r.geometry.coordinates[0].toFixed(5))
        }
        callback(null, results)
    } catch(e) { callback("Error POI: " + e, []) }
}

// Busca POIs usando Overpass. lat/lon: posición actual. radiusM: radio en metros. type: clave de _poiDefs.
// callback(error, resultArray) — results son objetos compatibles con photonShortName/photonSubtitle
function fetchPois(lat, lon, radiusM, type, navSpeedKmh, callback) {
    var def = _poiDefs[type]
    if (!def) { callback("Tipo POI desconocido", []); return }
    var q = "[out:json][timeout:25];("
          + "node(around:" + radiusM + "," + lat.toFixed(6) + "," + lon.toFixed(6) + ")"
          + "[\"" + def.tag + "\"=\"" + def.val + "\"];"
          + "way(around:" + radiusM + "," + lat.toFixed(6) + "," + lon.toFixed(6) + ")"
          + "[\"" + def.tag + "\"=\"" + def.val + "\"];"
          + ");out center;"
    var meta = { lat: lat, lon: lon, def: def, type: type, radiusM: radiusM,
                 navSpeedKmh: navSpeedKmh || 0 }
    _poiPost(q, meta, function(err, data, m) { _poiProcess(err, data, m, callback) })
}

// Busca POIs a lo largo de la ruta. shape: [[lon,lat],...]. Samplea desde posición actual hacia adelante.
// maxDetourMin: filtro de desvío máximo en minutos (0 = sin filtro).
function fetchPoisAlongRoute(curLat, curLon, shape, radiusM, type, navSpeedKmh, maxDetourMin, callback) {
    var def = _poiDefs[type]
    if (!def) { callback("Tipo POI desconocido", []); return }
    if (!shape || shape.length === 0) { fetchPois(curLat, curLon, radiusM, type, navSpeedKmh, callback); return }
    if (typeof maxDetourMin === "function") { callback = maxDetourMin; maxDetourMin = 0 }

    // Encontrar el índice del punto de ruta más cercano a la posición actual
    var startIdx = 0, minD = 1e18
    var cosLat = Math.cos(curLat * Math.PI / 180)
    for (var i = 0; i < shape.length; i++) {
        var dlat = (curLat - shape[i][1]) * 111319
        var dlon = (curLon - shape[i][0]) * 111319 * cosLat
        var d = dlat*dlat + dlon*dlon
        if (d < minD) { minD = d; startIdx = i }
    }

    // Una muestra cada stepM metros (80 km/h × poiMinutes min), desde posición actual al final
    var stepM = 80.0 * (maxDetourMin > 0 ? maxDetourMin : 10) / 60.0 * 1000
    var samples = [], cumM = 0, nextThreshM = 0
    for (var j = startIdx; j < shape.length; j++) {
        if (j > startIdx) {
            var dla = (shape[j][1] - shape[j-1][1]) * 111319
            var dlo = (shape[j][0] - shape[j-1][0]) * 111319 * cosLat
            cumM += Math.sqrt(dla*dla + dlo*dlo)
        }
        if (cumM >= nextThreshM) {
            samples.push({lat: shape[j][1], lon: shape[j][0]})
            nextThreshM += stepM
        }
    }

    // Construir query Overpass con unión de around por cada punto muestreado
    var tag = def.tag, val = def.val
    var clauses = ""
    for (var k = 0; k < samples.length; k++) {
        var pt = samples[k].lat.toFixed(5) + "," + samples[k].lon.toFixed(5)
        clauses += "node(around:" + radiusM + "," + pt + ")[\"" + tag + "\"=\"" + val + "\"];"
        clauses += "way(around:"  + radiusM + "," + pt + ")[\"" + tag + "\"=\"" + val + "\"];"
    }
    var q = "[out:json][timeout:30];(" + clauses + ");out center;"

    // Centro geográfico de los puntos muestreados (para elegir servidor Overpass correcto)
    var qLat = curLat, qLon = curLon
    if (samples.length > 0) {
        var mid = samples[Math.floor(samples.length / 2)]
        qLat = mid.lat; qLon = mid.lon
    }
    _logMsg("POI «" + def.label + "» en ruta (" + samples.length + " pts, r=" + radiusM + "m) qCenter=" + qLat.toFixed(2) + "," + qLon.toFixed(2))
    var meta = { lat: curLat, lon: curLon, qLat: qLat, qLon: qLon, def: def, type: type,
                 radiusM: radiusM, samples: samples,
                 navSpeedKmh: navSpeedKmh || 0, routeSegment: shape.slice(startIdx), maxDetourMin: maxDetourMin || 0 }
    _poiPost(q, meta, function(err, data, m) { _poiProcess(err, data, m, callback) })
}

// Calcula ruta con Valhalla.
// waypoints: [{lat, lon}, ...]  (primer elemento = origen)
// opts: {no_tolls, no_ferry, no_dirt}
// callback(error, routes[])  — routes[0] es la principal
function _valhallaLang() {
    var map = {
        "bg":"bg-BG","ca":"ca-ES","cs":"cs-CZ","da":"da-DK","de":"de-DE",
        "el":"el-GR","en":"en-US","es":"es-ES","et":"et-EE","fi":"fi-FI",
        "fr":"fr-FR","hi":"hi-IN","hu":"hu-HU","it":"it-IT","ja":"ja-JP",
        "nb":"nb-NO","nl":"nl-NL","pl":"pl-PL","pt":"pt-PT","ro":"ro-RO",
        "ru":"ru-RU","sk":"sk-SK","sl":"sl-SI","sv":"sv-SE","tr":"tr-TR",
        "uk":"uk-UA","vi":"vi-VN","zh":"zh-CN"
    }
    var lang = Qt.locale().name.split("_")[0]
    return map[lang] || "en-US"
}

function route(waypoints, opts, callback) {
    var locs = []
    for (var i = 0; i < waypoints.length; i++) {
        var loc = {lon: waypoints[i].lon, lat: waypoints[i].lat}
        if (waypoints[i].heading !== undefined) {
            loc.heading           = waypoints[i].heading
            loc.heading_tolerance = waypoints[i].heading_tolerance !== undefined
                                    ? waypoints[i].heading_tolerance : 45
        }
        locs.push(loc)
    }

    var coOpts = {}
    if (opts) {
        if (opts.no_tolls)   coOpts.use_tolls    = 0.0
        if (opts.no_ferry)   coOpts.use_ferry    = 0.0
        if (opts.no_dirt)    coOpts.use_tracks   = 0.0
        if (opts.no_highway) coOpts.use_highways = 0.0
    }

    var costingType = (opts && opts.costing) ? opts.costing : _activeCosting
    var costingOpts = {}
    costingOpts[costingType] = (costingType === "auto") ? coOpts : {}

    var dtObj = (opts && opts.date_time) ? opts.date_time : {type: 0, value: "current"}
    var body = JSON.stringify({
        locations: locs,
        costing: costingType,
        costing_options: costingOpts,
        alternates: 2,
        directions_options: {units: "kilometers", language: _valhallaLang()},
        date_time: dtObj
    })

    if (_routeBlocked) {
        _fileDump("ROUTE: bloqueado — petición guardada para cuando haya servidor")
        _pendingRoute = function() { route(waypoints, opts, callback) }
        return
    }

    _routeGeneration++
    var _myGen = _routeGeneration

    _logMsg("Ruta: " + waypoints.length + " puntos → Valhalla")
    _fileDump("=== ROUTE: " + JSON.stringify(locs) + " opts=" + JSON.stringify(coOpts))

    function _parseRouteText(text, cb) {
        if (!text || (text.charAt(0) !== '{' && text.charAt(0) !== '[')) {
            cb("Servidor: " + (text || "sin respuesta").substring(0, 80), null)
            return
        }
        try {
            var raw = JSON.parse(text)
            if (raw.error_code !== undefined)
                { cb(raw.error_code + ": " + (raw.error || ""), null); return }
            var trips = [raw.trip]
            if (raw.alternates)
                for (var i = 0; i < raw.alternates.length; i++)
                    trips.push(raw.alternates[i].trip)
            var routes = trips.map(function(t) {
                var allShape = [], allMans = [], shapeOff = 0
                var legShapeEnds = []
                for (var li = 0; li < t.legs.length; li++) {
                    var leg = t.legs[li]
                    var legShape = decodePolyline6(leg.shape)
                    var legN = legShape.length
                    var startPt = li === 0 ? 0 : 1
                    for (var pi = startPt; pi < legN; pi++) allShape.push(legShape[pi])
                    for (var mi = 0; mi < leg.maneuvers.length; mi++) {
                        var m = leg.maneuvers[mi], am = {}
                        for (var key in m) am[key] = m[key]
                        am.begin_shape_index = m.begin_shape_index + shapeOff
                        am.end_shape_index   = m.end_shape_index   + shapeOff
                        allMans.push(am)
                    }
                    shapeOff += legN - 1
                    legShapeEnds.push(shapeOff)
                }
                return { shape: allShape, maneuvers: allMans, legShapeEnds: legShapeEnds,
                         length: t.summary.length, time: t.summary.time }
            })
            var altCount = routes.length - 1
            _logMsg("Ruta: " + routes[0].length.toFixed(1) + " km · " +
                    routes[0].maneuvers.length + " maniobras" +
                    (altCount > 0 ? " · " + altCount + " alt." : ""))
            cb(null, routes)
        } catch(e) { _logMsg("✗ Parse error ruta: " + e); cb("Parse error: " + e, null) }
    }

    function _tryFallback(reason) {
        _fileDump("FALLBACK: reason=" + reason + " _fallbackUrl=" + _fallbackUrl + " VALHALLA=" + VALHALLA)
        if (_fallbackUrl && _fallbackUrl !== VALHALLA) {
            var fbHost = _fallbackUrl.replace(/https?:\/\/([^\/]+).*/, "$1")
            _logMsg(reason.substring(0, 50) + " · usando " + fbHost + "…")
            _xhr("POST", _fallbackUrl + "/route", body, function(errFb, textFb) {
                if (errFb) {
                    if (_statusPush) {
                        var isConn = errFb === "Timeout" || errFb.indexOf("HTTP 0") >= 0 || errFb.indexOf("HTTP 5") >= 0
                        if (isConn) _statusPush("Sin red · ruta no calculada", "#EF9A9A")
                    }
                    callback(errFb, null); return
                }
                _parseRouteText(textFb, callback)
            })
        } else {
            _fileDump("FALLBACK: sin fallback disponible — callback con error")
            if (_statusPush) {
                var isConn = reason === "Timeout" || reason.indexOf("HTTP 0") >= 0 || reason.indexOf("HTTP 5") >= 0
                if (isConn) _statusPush("Sin red · ruta no calculada", "#EF9A9A")
            }
            callback(reason, null)
        }
    }

    var _routeTry = 0, _routeMaxTry = 3
    function _routeAttempt() {
        if (_routeGeneration !== _myGen) return  // petición obsoleta, descartada
        _routeTry++
        if (_routeTry > 1) _logMsg("Reintento " + _routeTry + "/" + _routeMaxTry + "…")
        var _isLocal = VALHALLA.indexOf("127.0.0.1") >= 0
        var _url  = _isLocal ? VALHALLA + "/route?json=" + encodeURIComponent(body) : VALHALLA + "/route"
        var _meth = _isLocal ? "GET" : "POST"
        var _body = _isLocal ? null : body
        var _tms  = _isLocal ? 6000 : 15000
        _xhr(_meth, _url, _body, function(err, text) {
            if (_routeGeneration !== _myGen) return  // respuesta obsoleta, descartada
            if (err && (err === "Timeout" || err.indexOf("HTTP 0") === 0) && _routeTry < _routeMaxTry) {
                var _delay = _isLocal ? 500 : 3000
                _logMsg("Sin red · reintentando en " + (_delay/1000) + "s…")
                if (_defer) _defer(_routeAttempt, _delay); else _routeAttempt()
                return
            }
            if (err) { _tryFallback(err); return }
            if (!text || (text.charAt(0) !== '{' && text.charAt(0) !== '[')) {
                _tryFallback("Servidor: " + (text || "sin respuesta").substring(0, 60))
                return
            }
            _parseRouteText(text, callback)
        }, _tms)
    }
    _routeAttempt()
}

// Decodifica encoded polyline de Valhalla (precisión 6).
// Devuelve [[lon, lat], ...]
function decodePolyline6(str) {
    var idx = 0, lat = 0, lng = 0, out = []
    while (idx < str.length) {
        var b, shift = 0, result = 0
        do {
            if (idx >= str.length) return out
            b = str.charCodeAt(idx++) - 63; result |= (b & 0x1f) << shift; shift += 5
        } while (b >= 0x20)
        lat += (result & 1) ? ~(result >> 1) : (result >> 1)
        shift = 0; result = 0
        do {
            if (idx >= str.length) return out
            b = str.charCodeAt(idx++) - 63; result |= (b & 0x1f) << shift; shift += 5
        } while (b >= 0x20)
        lng += (result & 1) ? ~(result >> 1) : (result >> 1)
        out.push([lng / 1e6, lat / 1e6])
    }
    return out
}

function formatDist(km, imperial) {
    if (!km || km <= 0) return ""
    if (imperial) {
        var mi = km * 0.621371
        if (mi < 0.1)  return Math.round(km * 3280.84) + " ft"
        if (mi < 10.0) return mi.toFixed(1) + " mi"
        return Math.round(mi) + " mi"
    }
    if (km < 0.3)  return Math.round(km * 1000) + " m"
    if (km < 10.0) return km.toFixed(1) + " km"
    return Math.round(km) + " km"
}

function formatSpeed(kmh, imperial) {
    if (imperial) return Math.round(kmh * 0.621371)
    return Math.round(kmh)
}

function speedUnit(imperial) {
    return imperial ? "mph" : "km/h"
}

function formatTime(secs) {
    if (!secs || secs <= 0) return ""
    var m = Math.round(secs / 60)
    if (m < 1)  return "< 1 min"
    if (m < 60) return m + " min"
    var h = Math.floor(m / 60), min = m % 60
    return h + " h " + (min < 10 ? "0" : "") + min + " min"
}

function formatEta(secs) {
    if (!secs || secs <= 0) return ""
    var d = new Date(Date.now() + secs * 1000)
    var h = d.getHours(), m = d.getMinutes()
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
}

// Icono de maniobra Valhalla (tipo 0-28+)
function maneuverIcon(type) {
    var t = type || 0
    if (t === 1  || t === 2)  return "↗"  // start / start-right
    if (t === 3)              return "↖"  // start-left
    if (t === 4  || t === 5 || t === 6) return "⬛"  // destination
    if (t === 9  || t === 17) return "↗"  // slight right / ramp straight
    if (t === 10 || t === 18) return "→"  // right / ramp right
    if (t === 11 || t === 12) return "↪"  // sharp right / u-turn right
    if (t === 13 || t === 14) return "↩"  // u-turn left / sharp left
    if (t === 15 || t === 19) return "←"  // left / ramp left
    if (t === 16)             return "↖"  // slight left
    if (t === 26 || t === 27) return "⟳"  // roundabout
    return "↑"  // straight / continue / merge
}

// Descarga velocidades Valhalla (edge.speed, km/h) para cada punto de una ruta sim grabada.
// Devuelve array paralelo a simPts con la velocidad típica por tramo (0 = desconocida).
// callback(speeds) — llamado al completar (o al fallar, con null).
function fetchSimRouteSpeedsKmh(simPts, callback) {
    if (!simPts || simPts.length < 2) { callback(null); return }
    var CHUNK = 500
    var speeds = []
    for (var z = 0; z < simPts.length; z++) speeds.push(0)

    var chunks = []
    for (var s = 0; s < simPts.length; s += CHUNK - 1) {
        var end = Math.min(s + CHUNK, simPts.length)
        chunks.push({ start: s, pts: simPts.slice(s, end) })
    }

    function processChunk(ci) {
        if (ci >= chunks.length) { callback(speeds); return }
        var ch = chunks[ci]
        var shape = []
        for (var i = 0; i < ch.pts.length; i++)
            shape.push({ lat: ch.pts[i].lat, lon: ch.pts[i].lon, type: "via" })
        var body = JSON.stringify({
            shape: shape, costing: "auto", shape_match: "map_snap",
            filters: { attributes: ["edge.speed"], action: "include" }
        })
        var isLocal = VALHALLA.indexOf("127.0.0.1") >= 0
        var url = isLocal ? VALHALLA + "/trace_attributes?json=" + encodeURIComponent(body)
                          : VALHALLA + "/trace_attributes"
        _xhr(isLocal ? "GET" : "POST", url, isLocal ? null : body, function(err, text) {
            if (!err) {
                try {
                    var data = JSON.parse(text)
                    var edges = data.edges || [], mpts = data.matched_points || []
                    for (var j = 0; j < mpts.length && j < ch.pts.length; j++) {
                        var mp = mpts[j]
                        if (mp.type !== "matched" && mp.type !== "interpolated") continue
                        var eIdx = mp.edge_index
                        if (eIdx === undefined || eIdx < 0 || eIdx >= edges.length) continue
                        var spd = edges[eIdx].speed
                        if (spd && spd > 0) speeds[ch.start + j] = spd
                    }
                } catch(e) {}
            }
            processChunk(ci + 1)
        })
    }
    processChunk(0)
}

// Enriquece los maneuvers de una ruta con speed_limit real via /trace_attributes.
// Estrategia paramétrica: emite un punto cada STEP_KM km con interpolación lineal,
// garantizando que ningún par consecutivo supere el límite de 10 km del servidor.
// Agrupa en chunks de ≤CHUNK_KM. Proceso secuencial. Degradación silenciosa si falla.
function enrichSpeedLimits(shape, maneuvers, callback) {
    if (!shape || !maneuvers || maneuvers.length === 0) { callback(maneuvers); return }

    var STEP_KM  = 2    // paso de emisión: garantiza cobertura de tramos cortos (<10 km límite)
    var CHUNK_KM = 140  // km máximo por petición (< 200 km, límite path del servidor)

    // ── 1. Distancia acumulada por shape point ────────────────────────────────
    var cumDist = [0]
    for (var si = 1; si < shape.length; si++) {
        var dLa = (shape[si][1] - shape[si-1][1]) * Math.PI / 180
        var dLo = (shape[si][0] - shape[si-1][0]) * Math.PI / 180
        var r1  = shape[si-1][1] * Math.PI / 180, r2 = shape[si][1] * Math.PI / 180
        var sa  = Math.sin(dLa/2), so = Math.sin(dLo/2)
        var av  = sa*sa + Math.cos(r1)*Math.cos(r2)*so*so
        cumDist.push(cumDist[si-1] + 6371 * 2 * Math.atan2(Math.sqrt(av), Math.sqrt(Math.max(0, 1-av))))
    }
    var totalKm = cumDist[cumDist.length - 1]
    if (totalKm < 0.001) { callback(maneuvers); return }

    // ── 2. Emisión paramétrica: un punto cada STEP_KM km ─────────────────────
    var samples = []   // {lon, lat, manIdx}
    var shPtr = 0, mPtr = 0
    for (var emitKm = 0; emitKm < totalKm + STEP_KM * 0.5; emitKm += STEP_KM) {
        var km = Math.min(emitKm, totalKm)
        while (shPtr < shape.length - 1 && cumDist[shPtr + 1] < km) shPtr++
        var lon1 = shape[shPtr][0], lat1 = shape[shPtr][1]
        var lon2 = lon1, lat2 = lat1, frac = 0
        if (shPtr < shape.length - 1) {
            lon2 = shape[shPtr+1][0]; lat2 = shape[shPtr+1][1]
            var sl2 = cumDist[shPtr+1] - cumDist[shPtr]
            frac = sl2 > 0.0001 ? (km - cumDist[shPtr]) / sl2 : 0
        }
        while (mPtr < maneuvers.length - 1 && shPtr >= maneuvers[mPtr].end_shape_index) mPtr++
        samples.push({lon: lon1 + (lon2-lon1)*frac, lat: lat1 + (lat2-lat1)*frac, manIdx: mPtr})
    }
    if (samples.length < 2) { callback(maneuvers); return }

    // ── 3. Agrupa en chunks de ≤CHUNK_KM ─────────────────────────────────────
    // Los puntos consecutivos son siempre ≤STEP_KM, así que solo limitamos el total.
    var chunks = [], curPts = [], curMap = [], curKm2 = 0
    for (var j = 0; j < samples.length; j++) {
        if (curPts.length > 0) {
            var prev = curPts[curPts.length-1]
            var dLa2 = (samples[j].lat - prev.lat) * Math.PI / 180
            var dLo2 = (samples[j].lon - prev.lon) * Math.PI / 180
            var r1b  = prev.lat * Math.PI / 180, r2b = samples[j].lat * Math.PI / 180
            var sb   = Math.sin(dLa2/2), ob = Math.sin(dLo2/2)
            var avb  = sb*sb + Math.cos(r1b)*Math.cos(r2b)*ob*ob
            var segb = 6371 * 2 * Math.atan2(Math.sqrt(avb), Math.sqrt(Math.max(0, 1-avb)))
            if (curKm2 + segb > CHUNK_KM && curPts.length >= 2) {
                chunks.push({pts: curPts.slice(), map: curMap.slice()})
                curPts = []; curMap = []; curKm2 = 0
            } else { curKm2 += segb }
        }
        curPts.push({lon: samples[j].lon, lat: samples[j].lat, type: "via"})
        curMap.push(samples[j].manIdx)
    }
    if (curPts.length >= 2) chunks.push({pts: curPts, map: curMap})
    if (chunks.length === 0) { callback(maneuvers); return }

    // ── 4. Clona maneuvers ────────────────────────────────────────────────────
    var enriched = [], totalFound = 0
    for (var k = 0; k < maneuvers.length; k++) {
        var em = {}; for (var key in maneuvers[k]) em[key] = maneuvers[k][key]
        enriched.push(em)
    }
    var foundMans = {}

    _logMsg("Límites de velocidad (" + chunks.length + " chunk(s), " + samples.length + " pts)…")

    // ── 5. Peticiones secuenciales ────────────────────────────────────────────
    function processChunk(ci) {
        if (ci >= chunks.length) {
            _logMsg("Límites: " + totalFound + "/" + maneuvers.length + " tramos con dato")
            callback(enriched); return
        }
        var chunk = chunks[ci]
        var body = JSON.stringify({
            shape: chunk.pts, costing: "auto", shape_match: "map_snap",
            filters: {attributes: ["edge.speed_limit", "edge.speed", "edge.road_class",
                                   "edge.admin_index",
                                   "matched.edge_index", "matched.type"], action: "include"}
        })
        _logMsg("  chunk " + (ci+1) + "/" + chunks.length + " · " + chunk.pts.length + " pts")
        var _taLocal = VALHALLA.indexOf("127.0.0.1") >= 0
        var _taUrl = _taLocal ? VALHALLA + "/trace_attributes?json=" + encodeURIComponent(body) : VALHALLA + "/trace_attributes"
        _xhr(_taLocal ? "GET" : "POST", _taUrl, _taLocal ? null : body, function(err, text) {
            if (!err) {
                try {
                    var data = JSON.parse(text)
                    if (data.error_code !== undefined) {
                        _logMsg("  ✗ chunk " + (ci+1) + ": " + (data.error || data.error_code))
                    } else {
                        var edges = data.edges || [], mpts = data.matched_points || []
                        var admins = data.admins || []
                        for (var j2 = 0; j2 < mpts.length && j2 < chunk.map.length; j2++) {
                            var mp = mpts[j2], mi = chunk.map[j2]
                            if (mp.type !== "matched" && mp.type !== "interpolated") continue
                            if (foundMans[mi]) continue
                            var eIdx = mp.edge_index
                            if (eIdx === undefined || eIdx < 0 || eIdx >= edges.length) continue
                            var sl  = edges[eIdx].speed_limit
                            var spd = edges[eIdx].speed
                            var rc  = edges[eIdx].road_class || ""
                            var ai  = edges[eIdx].admin_index
                            var cc  = (ai !== undefined && admins[ai]) ? (admins[ai].country_code || "ES") : "ES"
                            var slOsm   = (sl  !== undefined && sl  > 0) ? Math.round(sl)  : 0
                            var slVal   = (spd !== undefined && spd >= 10) ? Math.round(spd) : 0
                            var slLegal = _legalSpeedByClass(rc, spd, cc)
                            var finalSl = 0, src = ""
                            if (slOsm > 0) {
                                finalSl = slOsm;   src = "OSM"
                            } else if (slVal > 0) {
                                finalSl = slVal;   src = "valhalla"
                            } else if (slLegal > 0) {
                                finalSl = slLegal; src = "dflt(" + cc + "/" + rc + ")"
                            }
                            if (finalSl > 0) {
                                enriched[mi].speed_limit          = finalSl
                                enriched[mi].speed_limit_verified = (slOsm > 0)
                                enriched[mi].speed_limit_src      = src
                                enriched[mi]._dbgSpeed            = spd
                                enriched[mi]._slOsm               = slOsm
                                enriched[mi]._slVal               = slVal
                                enriched[mi]._slLegal             = slLegal
                                enriched[mi].road_class           = rc
                                foundMans[mi] = true; totalFound++
                                _logMsg("    man[" + mi + "] → " + finalSl + " km/h (" + src + ")"
                                        + " («" + (maneuvers[mi].instruction||"").substring(0,35) + "»)")
                            } else { _logMsg("    man[" + mi + "] sin speed_limit") }
                        }
                    }
                } catch(e2) { _logMsg("  ✗ chunk " + (ci+1) + " parse: " + e2) }
            } else { _logMsg("  ✗ chunk " + (ci+1) + ": " + err) }
            processChunk(ci + 1)
        })
    }
    processChunk(0)
}

// Límites legales por defecto por país y clase de vía.
// Fuente: osm-legal-default-speeds (westnordost). Detección urbana/rural via edge.speed Valhalla.
// Campos: mw=motorway, tk=trunk, pr/pu=primary rural/urban, sr/su=secondary, tr/tu=tertiary+unclassified, re=residential, sv=service, ls=living_street
var _SPEED_CC = {
    ES: {mw:120, tk:90,  pr:90, pu:50, sr:90, su:30, tr:90, tu:30, re:30, sv:20, ls:20},  // DGT 2021
    PT: {mw:120, tk:100, pr:90, pu:50, sr:90, su:50, tr:90, tu:50, re:30, sv:20, ls:20},
    FR: {mw:130, tk:110, pr:80, pu:50, sr:80, su:50, tr:80, tu:50, re:30, sv:20, ls:20},
    DE: {mw:130, tk:100, pr:100,pu:50, sr:100,su:50, tr:100,tu:50, re:30, sv:10, ls:10},
    IT: {mw:130, tk:110, pr:90, pu:50, sr:90, su:50, tr:90, tu:50, re:30, sv:20, ls:10},
    GB: {mw:112, tk:96,  pr:96, pu:48, sr:96, su:48, tr:96, tu:48, re:48, sv:20, ls:10},
    NL: {mw:100, tk:100, pr:80, pu:50, sr:80, su:50, tr:60, tu:30, re:30, sv:15, ls:15},
    BE: {mw:120, tk:120, pr:90, pu:50, sr:90, su:50, tr:90, tu:50, re:30, sv:20, ls:20},
    AT: {mw:130, tk:100, pr:100,pu:50, sr:100,su:50, tr:100,tu:50, re:30, sv:20, ls:20},
    CH: {mw:120, tk:100, pr:80, pu:50, sr:80, su:50, tr:80, tu:50, re:30, sv:20, ls:20},
    _:  {mw:120, tk:90,  pr:90, pu:50, sr:90, su:50, tr:90, tu:50, re:30, sv:20, ls:20}
}

// road_class: motorway|trunk|primary|secondary|tertiary|unclassified|residential|service_other
// spdKmh: velocidad de routing Valhalla (proxy urbano/rural: ≤60 → urbano)
// cc: código ISO-3166-1 alpha-2 del país (de Valhalla admins)
function _legalSpeedByClass(roadClass, spdKmh, cc) {
    var t = _SPEED_CC[cc] || _SPEED_CC["_"]
    // Umbrales distintos por clase: Valhalla asigna ~90 a primary rural, ~60 a secondary rural, ~50 a tertiary rural
    var urban
    if      (roadClass === "motorway" || roadClass === "trunk")        urban = false
    else if (roadClass === "primary")                                  urban = spdKmh > 0 && spdKmh <= 55
    else if (roadClass === "secondary")                                urban = spdKmh > 0 && spdKmh <= 50
    else if (roadClass === "tertiary" || roadClass === "unclassified") urban = spdKmh > 0 && spdKmh <= 40
    else                                                               urban = true
    if (roadClass === "motorway")                                      return t.mw
    if (roadClass === "trunk")                                         return t.tk
    if (roadClass === "primary")                                       return urban ? t.pu : t.pr
    if (roadClass === "secondary")                                     return urban ? t.su : t.sr
    if (roadClass === "tertiary" || roadClass === "unclassified")      return urban ? t.tu : t.tr
    if (roadClass === "residential")                                   return t.re
    if (roadClass === "service_other")                                 return t.sv
    return urban ? t.tu : t.tr
}

// Velocidad estimada para un maneuver (km/h). Prioridad: comunitaria > Valhalla implícita > OSM speed_limit > legal por clase > 50.
function segSpeedKmh(m, commLimit) {
    if (commLimit > 0) return commLimit
    if (m.time > 0 && m.length > 0) return m.length * 3600 / m.time
    if (m.speed_limit > 0) return m.speed_limit
    var legal = m.road_class ? _legalSpeedByClass(m.road_class, 0) : 0
    return legal > 0 ? legal : 50
}

function _xhr(method, url, body, cb, timeoutMs) {
    var host = url.replace(/^https?:\/\/([^\/]+).*$/, "$1")
    var tms = timeoutMs || 15000
    _logMsg("→ " + method + " " + host + "…")
    _fileDump("--- REQUEST: " + method + " " + url)
    if (body) _fileDump("--- BODY: " + body)
    var req = new XMLHttpRequest()
    req.timeout = tms
    req.ontimeout = function() {
        _logMsg("✗ Timeout (" + (tms/1000) + "s) " + host)
        cb("Timeout", null)
    }
    req.onreadystatechange = function() {
        if (req.readyState === 2) {
            _logMsg("Conexión establecida")
        } else if (req.readyState === XMLHttpRequest.DONE) {
            _fileDump("--- RESPONSE: HTTP " + req.status
                      + " · " + req.responseText.length + " bytes")
            // Recortado a propósito: log_to_file() escribe con writeln! SÍNCRONO
            // en el hilo de UI. El endpoint de carburante del MINETUR devuelve
            // ~12 MB (todas las gasolineras de España), y volcarlo entero
            // suponía asignar un segundo string de 12 MB y escribirlo a flash
            // antes siquiera de parsearlo. Los manejadores de POI ya recortaban
            // a 500; esto faltaba por hacer aquí.
            _fileDump("--- BODY: " + req.responseText.substring(0, 2000)
                      + (req.responseText.length > 2000
                         ? "… [+" + (req.responseText.length - 2000) + " bytes]" : ""))
            if (req.status === 200) {
                _logMsg("HTTP 200 · " + req.responseText.length + " bytes")
                cb(null, req.responseText)
            } else {
                var snippet = req.responseText.length > 0
                    ? "  [" + req.responseText.substring(0, 120) + "]" : ""
                _logMsg("✗ HTTP " + req.status + snippet)
                cb("HTTP " + req.status, null)
            }
        }
    }
    req.open(method, url)
    if (body) req.setRequestHeader("Content-Type", "application/json")
    req.send(body || "")
}

// ── Radares de velocidad (Overpass API) ──────────────────────────────────

function _nearRoute(lat, lon, shape, threshM) {
    var cos = Math.cos(lat * Math.PI / 180)
    for (var i = 0; i < shape.length; i += 4) {
        var dlat = (lat - shape[i][1]) * 111319
        var dlon = (lon - shape[i][0]) * 111319 * cos
        if (dlat * dlat + dlon * dlon < threshM * threshM) return true
    }
    return false
}

// Une las vías role=section de una relación de tramo en una sola polilínea.
// Llegan en orden arbitrario y con sentidos mezclados, así que se pegan por extremos
// coincidentes: cada vía se engancha por delante o por detrás de la cadena, invirtiéndola
// si hace falta. Devuelve [] si no se puede formar nada de al menos dos puntos.
//
// El sentido resultante depende de qué vía tocara ser la primera y de cómo estuviera
// dibujada, así que hay que fijarlo con los nodos from/to de la relación: medido sobre
// 52 tramos de Cataluña, 12 salían del revés. Un tramo con el sentido invertido es peor
// que no tenerlo, porque hace pasar por bueno el radar de la calzada contraria.
function _chainSectionWays(ways, nodeById, fromN, toN) {
    var pend = []
    for (var i = 0; i < ways.length; i++) {
        var nd = ways[i].nodes || []
        if (nd.length >= 2) pend.push(nd.slice())
    }
    if (pend.length === 0) return []
    var chain = pend.shift()
    var progress = true
    while (pend.length > 0 && progress) {
        progress = false
        for (var k = 0; k < pend.length; k++) {
            var w = pend[k], wl = w.length
            var head = chain[0], tail = chain[chain.length - 1]
            if      (w[0]      === tail) chain = chain.concat(w.slice(1))
            else if (w[wl - 1] === tail) chain = chain.concat(w.slice(0, wl - 1).reverse())
            else if (w[wl - 1] === head) chain = w.slice(0, wl - 1).concat(chain)
            else if (w[0]      === head) chain = w.slice(1).reverse().concat(chain)
            else continue
            pend.splice(k, 1); progress = true; break
        }
    }
    var out = []
    for (var c = 0; c < chain.length; c++) {
        var n = nodeById[chain[c]]
        if (n && n.lat !== undefined) out.push([n.lon, n.lat])
    }
    if (out.length < 2) return []

    // Orientar de "from" hacia "to". Se compara por distancia y no por id de nodo porque
    // from/to no siempre son exactamente los extremos de las vías section.
    var ref = fromN || toN
    if (ref) {
        var kLat = 111319, kLon = 111319 * Math.cos(ref.lat * Math.PI / 180)
        var dIni = Math.sqrt(Math.pow((out[0][1] - ref.lat) * kLat, 2) +
                             Math.pow((out[0][0] - ref.lon) * kLon, 2))
        var dFin = Math.sqrt(Math.pow((out[out.length-1][1] - ref.lat) * kLat, 2) +
                             Math.pow((out[out.length-1][0] - ref.lon) * kLon, 2))
        // Con "from" el inicio debe quedar más cerca; con "to" (si no hay from), al revés.
        if (fromN ? (dFin < dIni) : (dIni < dFin)) out.reverse()
    }
    return out
}

// Parsea la respuesta Overpass y filtra fijos/tramos.
// Detecta también tramos formados por DOS nodos speed_camera sin direction tag.
// nearShape: si se proporciona, filtra por proximidad; si null, devuelve todo.
function _parseRadarResponse(text, nearShape, callback) {
    try {
        var data = JSON.parse(text)
        var nodeById = {}, wayById = {}, wayNodeIds = {}
        for (var i = 0; i < data.elements.length; i++) {
            var el = data.elements[i]
            if (el.type === "node") nodeById[el.id] = el
            else if (el.type === "way") {
                wayById[el.id] = el
                // Solo los ways de tramo aportan nodos a descartar. Desde que pedimos
                // las relaciones llegan también vías corrientes, y sus vértices no deben
                // hacer desaparecer las cámaras que estén sobre ellas.
                if ((el.tags||{})["enforcement"] === "average_speed")
                    for (var j = 0; j < (el.nodes||[]).length; j++) wayNodeIds[el.nodes[j]] = true
            }
        }
        var fijos = [], tramos = []
        // Candidatos a tramo: nodos speed_camera sin etiqueta direction
        var tramoCands = []
        // Cámaras ya consumidas por una relación de tramo: no son fijos sueltos ni
        // deben entrar en el emparejamiento heurístico de más abajo.
        var relDeviceIds = {}

        // ── Radares de tramo declarados como relación ──────────────────────────
        for (var i = 0; i < data.elements.length; i++) {
            var rel = data.elements[i]
            if (rel.type !== "relation") continue
            var rt = rel.tags || {}
            if (rt["type"] !== "enforcement" || rt["enforcement"] !== "average_speed") continue
            var secWays = [], devIds = [], fromN = null, toN = null
            var mem = rel.members || []
            for (var m = 0; m < mem.length; m++) {
                var mb = mem[m]
                if (mb.role === "section" && mb.type === "way" && wayById[mb.ref])
                    secWays.push(wayById[mb.ref])
                else if (mb.role === "device" && mb.type === "node") {
                    devIds.push(mb.ref); relDeviceIds[mb.ref] = true
                } else if (mb.role === "from" && mb.type === "node") fromN = nodeById[mb.ref]
                else if (mb.role === "to"   && mb.type === "node") toN   = nodeById[mb.ref]
            }
            var rShape = _chainSectionWays(secWays, nodeById, fromN, toN)
            if (rShape.length < 2) {
                // Sin section utilizable: recta entre extremos y que la enriquezca
                // Valhalla igual que a los tramos sintéticos.
                var pA = fromN || nodeById[devIds[0]]
                var pB = toN   || nodeById[devIds[devIds.length - 1]]
                if (!pA || !pB) continue
                rShape = [[pA.lon, pA.lat], [pB.lon, pB.lat]]
            }
            if (nearShape) {
                var s0r = rShape[0], sNr = rShape[rShape.length - 1]
                if (!_nearRoute(s0r[1], s0r[0], nearShape, 200) &&
                    !_nearRoute(sNr[1], sNr[0], nearShape, 200)) continue
            }
            var rLen = 0
            for (var q2 = 1; q2 < rShape.length; q2++) {
                var dlaR = (rShape[q2][1] - rShape[q2-1][1]) * 111319
                var dloR = (rShape[q2][0] - rShape[q2-1][0]) * 111319 * Math.cos(rShape[q2][1] * Math.PI / 180)
                rLen += Math.sqrt(dlaR*dlaR + dloR*dloR)
            }
            tramos.push({
                id: "r" + rel.id,
                shape: rShape,
                maxspeed: parseInt(rt["maxspeed:enforcement"]) || parseInt(rt["maxspeed"]) || 0,
                lengthM: Math.round(rLen)
            })
        }

        for (var i = 0; i < data.elements.length; i++) {
            var el = data.elements[i]
            var t = el.tags || {}
            if (el.type === "node" && t["highway"] === "speed_camera") {
                if (wayNodeIds[el.id]) continue
                if (relDeviceIds[el.id]) continue   // ya va dentro de su relación de tramo
                if (nearShape && !_nearRoute(el.lat, el.lon, nearShape, 200)) continue
                var dirStr = t["direction"]
                var dirVal = parseInt(dirStr)
                var hasDir = (dirStr !== undefined && dirStr !== "" && !isNaN(dirVal))
                // Texto legible del radar, para mostrarlo en la alerta. No se usa "note",
                // que suele ser anotación interna del mapeador ("F080 SIPU C-31Nord Km…").
                var descr = t["description"] || t["name"] || t["loc_name"] || ""
                if (hasDir) {
                    fijos.push({ id: "n" + el.id, lat: el.lat, lon: el.lon,
                                 maxspeed: parseInt(t["maxspeed"]) || 0, direction: dirVal,
                                 descr: descr })
                } else {
                    tramoCands.push({ lat: el.lat, lon: el.lon,
                                      maxspeed: parseInt(t["maxspeed"]) || 0, id: el.id,
                                      descr: descr })
                }
            } else if (el.type === "way" && t["enforcement"] === "average_speed") {
                if (!el.nodes || el.nodes.length < 2) continue
                var wShape = []
                for (var j = 0; j < el.nodes.length; j++) {
                    var n = nodeById[el.nodes[j]]
                    if (n) wShape.push([n.lon, n.lat])
                }
                if (wShape.length < 2) continue
                if (nearShape) {
                    var s0w = wShape[0], sNw = wShape[wShape.length-1]
                    if (!_nearRoute(s0w[1], s0w[0], nearShape, 200) &&
                        !_nearRoute(sNw[1], sNw[0], nearShape, 200)) continue
                }
                var lenM = 0
                for (var j = 1; j < wShape.length; j++) {
                    var dlat = (wShape[j][1]-wShape[j-1][1])*111319
                    var dlon = (wShape[j][0]-wShape[j-1][0])*111319*Math.cos(wShape[j][1]*Math.PI/180)
                    lenM += Math.sqrt(dlat*dlat+dlon*dlon)
                }
                tramos.push({
                    id: "w" + el.id,
                    shape: wShape,
                    maxspeed: parseInt(t["maxspeed:enforcement"]) || parseInt(t["maxspeed"]) || parseInt(t["maxspeed:practical"]) || 0,
                    lengthM: Math.round(lenM)
                })
            }
        }

        // Emparejar candidatos sin direction: dos cámaras del mismo maxspeed separadas
        // entre 100 m y 40 000 m forman un tramo sintético (patrón habitual en España/OSM).
        // Los tramos de velocidad media en autopista pueden superar los 15-20 km
        // (ej. AP-7), 8 km se quedaba corto y dejaba cámaras de tramo reales sin emparejar.
        var paired = {}
        for (var a = 0; a < tramoCands.length; a++) {
            if (paired[tramoCands[a].id]) continue
            var ca = tramoCands[a]
            var bestB = -1, bestD = 1e9
            for (var b = a + 1; b < tramoCands.length; b++) {
                if (paired[tramoCands[b].id]) continue
                var cb = tramoCands[b]
                if (ca.maxspeed !== cb.maxspeed && (ca.maxspeed > 0 || cb.maxspeed > 0)) continue
                var dlat2 = (ca.lat - cb.lat) * 111319
                var dlon2 = (ca.lon - cb.lon) * 111319 * Math.cos(ca.lat * Math.PI / 180)
                var d2 = Math.sqrt(dlat2*dlat2 + dlon2*dlon2)
                if (d2 >= 100 && d2 <= 40000 && d2 < bestD) { bestD = d2; bestB = b }
            }
            if (bestB >= 0) {
                var cb = tramoCands[bestB]
                paired[ca.id] = true; paired[cb.id] = true
                var spd = ca.maxspeed || cb.maxspeed
                // Ordenar por longitud para que el shape vaya de oeste a este (heurístico)
                var ptA = { lon: ca.lon, lat: ca.lat }, ptB = { lon: cb.lon, lat: cb.lat }
                if (ptA.lon > ptB.lon) { var tmp = ptA; ptA = ptB; ptB = tmp }
                tramos.push({ id: "t" + ca.id + "_" + cb.id, shape: [[ptA.lon, ptA.lat], [ptB.lon, ptB.lat]],
                               maxspeed: spd, lengthM: Math.round(bestD) })
            } else {
                // Sin pareja → fijo sin dirección
                fijos.push({ id: "n" + ca.id, lat: ca.lat, lon: ca.lon, maxspeed: ca.maxspeed,
                             direction: -1, descr: ca.descr || "" })
            }
        }

        _enrichTramoShapes(tramos, nearShape, function(enriched) {
            callback({fijos: fijos, tramos: enriched})
        })
    } catch(e) { callback({fijos:[], tramos:[]}) }
}

// Proyecta (lat,lon) sobre una polilínea [[lon,lat],...] y devuelve {segIdx, frac, dist}.
function _projectOnShape(lat, lon, shape) {
    var bestDist = 1e9, bestIdx = 0, bestFrac = 0
    for (var i = 1; i < shape.length; i++) {
        var p1 = shape[i-1], p2 = shape[i]
        var dlat = (p2[1]-p1[1])*111319
        var dlon = (p2[0]-p1[0])*111319*Math.cos(lat*Math.PI/180)
        var seg2 = dlat*dlat + dlon*dlon
        if (seg2 < 1) continue
        var pdlat = (lat-p1[1])*111319
        var pdlon = (lon-p1[0])*111319*Math.cos(lat*Math.PI/180)
        var t = Math.max(0, Math.min(1, (pdlat*dlat + pdlon*dlon) / seg2))
        var pLat = p1[1] + t*(p2[1]-p1[1])
        var pLon = p1[0] + t*(p2[0]-p1[0])
        var dL = (pLat-lat)*111319, dLo = (pLon-lon)*111319*Math.cos(lat*Math.PI/180)
        var dist = Math.sqrt(dL*dL + dLo*dLo)
        if (dist < bestDist) { bestDist = dist; bestIdx = i-1; bestFrac = t }
    }
    return {segIdx: bestIdx, frac: bestFrac, dist: bestDist}
}

// Extrae el sub-segmento de routeShape entre las proyecciones de ptA y ptB ([lon,lat]).
// Devuelve null si la proyección de alguno supera maxDistM metros.
function _extractShapeSegment(ptA, ptB, routeShape, maxDistM) {
    var pA = _projectOnShape(ptA[1], ptA[0], routeShape)
    var pB = _projectOnShape(ptB[1], ptB[0], routeShape)
    if (pA.dist > maxDistM || pB.dist > maxDistM) return null
    var idxA = pA.segIdx + pA.frac, idxB = pB.segIdx + pB.frac
    if (idxA > idxB) { var tmp = pA; pA = pB; pB = tmp }
    var sub = []
    var s0 = routeShape[pA.segIdx], e0 = routeShape[pA.segIdx+1] || s0
    sub.push([s0[0]+pA.frac*(e0[0]-s0[0]), s0[1]+pA.frac*(e0[1]-s0[1])])
    for (var i = pA.segIdx+1; i <= pB.segIdx; i++) sub.push(routeShape[i])
    var sN = routeShape[pB.segIdx], eN = routeShape[pB.segIdx+1] || sN
    sub.push([sN[0]+pB.frac*(eN[0]-sN[0]), sN[1]+pB.frac*(eN[1]-sN[1])])
    return sub.length >= 2 ? sub : null
}

// Dado el shape Valhalla del tramo y la ruta de navegación, devuelve el sub-segmento
// de nearShape que recorre el tramo: desde la primera intersección con el shape Valhalla
// hasta el punto de nearShape más cercano a la cámara final.
function _findTramoOnRoute(valhShape, endCamLon, endCamLat, nearShape) {
    var ENTRY_THRESHOLD = 60   // metros: distancia para considerar "intersección"

    // 1. Primera intersección: primer segmento de nearShape dentro del umbral de valhShape
    var startSegIdx = -1
    outer:
    for (var ni = 0; ni < nearShape.length - 1; ni++) {
        var np = nearShape[ni]
        for (var vi = 0; vi < valhShape.length; vi++) {
            var vp = valhShape[vi]
            var dlat = (np[1] - vp[1]) * 111319
            var dlon = (np[0] - vp[0]) * 111319 * Math.cos(np[1] * Math.PI / 180)
            if (Math.sqrt(dlat*dlat + dlon*dlon) < ENTRY_THRESHOLD) {
                startSegIdx = ni
                break outer
            }
        }
    }
    if (startSegIdx < 0) return null

    // 2. Punto de nearShape más cercano a la cámara final
    var pEnd = _projectOnShape(endCamLat, endCamLon, nearShape)
    var endSegIdx = pEnd.segIdx
    if (endSegIdx < startSegIdx) return null

    // 3. Extraer sub-segmento de nearShape
    var sub = []
    for (var i = startSegIdx; i <= endSegIdx; i++) sub.push(nearShape[i])
    var sE = nearShape[endSegIdx], eE = nearShape[endSegIdx + 1] || sE
    sub.push([sE[0] + pEnd.frac * (eE[0] - sE[0]), sE[1] + pEnd.frac * (eE[1] - sE[1])])

    if (sub.length < 2) return null
    var lenM = 0
    for (var pi = 1; pi < sub.length; pi++) {
        var dlat2 = (sub[pi][1] - sub[pi-1][1]) * 111319
        var dlon2 = (sub[pi][0] - sub[pi-1][0]) * 111319 * Math.cos(sub[pi][1] * Math.PI / 180)
        lenM += Math.sqrt(dlat2*dlat2 + dlon2*dlon2)
    }
    return { shape: sub, lengthM: Math.round(lenM) }
}

// Para cada tramo sintético de 2 puntos, sustituye el shape recto por geometría real.
// Con nearShape: Valhalla para encontrar la vía correcta, luego sub-segmento de nearShape.
// Sin nearShape: Valhalla directamente.
function _enrichTramoShapes(tramos, nearShape, callback) {
    var toEnrich = []
    for (var i = 0; i < tramos.length; i++)
        if (tramos[i].shape.length === 2) toEnrich.push(i)
    if (toEnrich.length === 0) { callback(tramos); return }

    var pending = toEnrich.length
    for (var ei = 0; ei < toEnrich.length; ei++) {
        (function(idx) {
            var t = tramos[idx]
            tramos[idx].origShape = [t.shape[0].slice(), t.shape[1].slice()]
            var locA = {lon: t.shape[0][0], lat: t.shape[0][1]}
            var locB = {lon: t.shape[1][0], lat: t.shape[1][1]}

            var body = JSON.stringify({
                locations: [locA, locB],
                costing: "auto",
                directions_options: {units: "kilometers"}
            })
            var _erLocal = VALHALLA.indexOf("127.0.0.1") >= 0
            var _erUrl = _erLocal ? VALHALLA + "/route?json=" + encodeURIComponent(body) : VALHALLA + "/route"
            _xhr(_erLocal ? "GET" : "POST", _erUrl, _erLocal ? null : body, function(err, text) {
                if (!err && text) {
                    try {
                        var raw = JSON.parse(text)
                        if (!raw.error_code && raw.trip && raw.trip.legs.length > 0) {
                            var decoded = decodePolyline6(raw.trip.legs[0].shape)
                            if (decoded.length >= 2) {
                                // Con nearShape: usar sub-segmento de la ruta de navegación
                                if (nearShape && nearShape.length >= 2) {
                                    var seg = _findTramoOnRoute(decoded, locB.lon, locB.lat, nearShape)
                                    if (seg) {
                                        tramos[idx].shape   = seg.shape
                                        tramos[idx].lengthM = seg.lengthM
                                        if (--pending === 0) callback(tramos)
                                        return
                                    }
                                }
                                // Sin nearShape o sin intersección: usar Valhalla directamente
                                tramos[idx].shape = decoded
                                var lenM = 0
                                for (var pi = 1; pi < decoded.length; pi++) {
                                    var dlat = (decoded[pi][1]-decoded[pi-1][1])*111319
                                    var dlon = (decoded[pi][0]-decoded[pi-1][0])*111319*Math.cos(decoded[pi][1]*Math.PI/180)
                                    lenM += Math.sqrt(dlat*dlat+dlon*dlon)
                                }
                                tramos[idx].lengthM = Math.round(lenM)
                            }
                        }
                    } catch(e) {}
                }
                if (--pending === 0) callback(tramos)
            }, 10000)
        })(toEnrich[ei])
    }
}

function _overpassPost(bbox, callback, _tried) {
    if (!_tried) _tried = []
    // Los radares de tramo están en OSM como relación type=enforcement con
    // enforcement=average_speed: los miembros device son las cámaras, los section las
    // vías recorridas y from/to los extremos. La etiqueta average_speed va en la
    // relación, no en los ways, así que la línea de way no devuelve nada casi nunca;
    // se mantiene por si algún sitio la usa. ">>" (recursivo) hace falta para bajar de
    // la relación a sus vías y de estas a sus nodos con coordenadas.
    var q = "[out:json][timeout:25];(" +
            "node[\"highway\"=\"speed_camera\"]("+bbox+");" +
            "way[\"enforcement\"=\"average_speed\"]("+bbox+");" +
            "relation[\"type\"=\"enforcement\"][\"enforcement\"=\"average_speed\"]("+bbox+");" +
            ");out body;>>;out skel qt;"
    var _bparts = bbox.split(",")
    var _cLat = (_bparts.length === 4) ? (parseFloat(_bparts[0]) + parseFloat(_bparts[2])) / 2 : 40
    var _cLon = (_bparts.length === 4) ? (parseFloat(_bparts[1]) + parseFloat(_bparts[3])) / 2 : -3
    var _srv = _tried.length === 0 ? _overpassForPos(_cLat, _cLon) : _overpassNext(_tried, _cLat, _cLon)
    if (!_srv) { _logMsg("Overpass radares: todos los servidores agotados"); callback(null, true); return }
    _tried = _tried.concat([_srv])
    _logMsg("→ Overpass radares " + _srv + (_tried.length > 1 ? " (intento " + _tried.length + ")" : ""))
    var xhr = new XMLHttpRequest()
    xhr.open("POST", _srv)
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    xhr.setRequestHeader("Accept", "*/*")
    xhr.setRequestHeader("User-Agent", "Navius/1.0 (navigation app)")
    xhr.timeout = 25000
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (xhr.status !== 200) {
            _logMsg("Overpass radares error " + xhr.status + " " + _srv)
            _overpassPost(bbox, callback, _tried)
            return
        }
        callback(xhr.responseText)
    }
    xhr.ontimeout = function() {
        _logMsg("Overpass radares timeout " + _srv)
        _overpassPost(bbox, callback, _tried)
    }
    xhr.send("data=" + encodeURIComponent(q))
}

// ── Caché local de radares (SQLite vía LocalStorage) ────────────────────────
// Persiste entre rutas y reinicios: la BD nunca se borra al terminar de
// navegar. Cada consulta con éxito a Overpass revalida (upsert + poda) la
// zona consultada, y un barrido diario revalida en segundo plano el resto.
var _radarDbRef = null

function setRadarDb(db) {
    _radarDbRef = db
    if (!_radarDbRef) return
    try {
        _radarDbRef.transaction(function(tx) {
            tx.executeSql('CREATE TABLE IF NOT EXISTS radares (' +
                'id TEXT PRIMARY KEY, kind TEXT, lat REAL, lon REAL, lat2 REAL, lon2 REAL, ' +
                'maxspeed INTEGER, direction INTEGER, updated_at INTEGER)')
            tx.executeSql('CREATE TABLE IF NOT EXISTS radares_meta (key TEXT PRIMARY KEY, value TEXT)')
        })
        // Columna añadida después: en bases ya creadas el CREATE de arriba no la añade.
        // Falla si ya existe, que es el caso normal, así que se ignora el error.
        try {
            _radarDbRef.transaction(function(tx) {
                tx.executeSql('ALTER TABLE radares ADD COLUMN descr TEXT')
            })
        } catch(e2) { /* la columna ya existía */ }
    } catch(e) { _logMsg("✗ Radar DB init: " + e); _radarDbRef = null }
}

function _radarDb() { return _radarDbRef }

function _saveRadarsToDb(fijos, tramos) {
    var db = _radarDb(); if (!db) return
    var now = Math.floor(Date.now() / 1000)
    try {
        db.transaction(function(tx) {
            for (var i = 0; i < fijos.length; i++) {
                var f = fijos[i]
                if (!f.id) continue
                tx.executeSql('INSERT OR REPLACE INTO radares (id,kind,lat,lon,lat2,lon2,maxspeed,direction,updated_at,descr) VALUES (?,?,?,?,?,?,?,?,?,?)',
                    [f.id, 'fijo', f.lat, f.lon, null, null, f.maxspeed || 0, f.direction, now, f.descr || ''])
            }
            for (var j = 0; j < tramos.length; j++) {
                var t = tramos[j]
                if (!t.id) continue
                var s0 = t.origShape ? t.origShape[0] : t.shape[0]
                var sN = t.origShape ? t.origShape[1] : t.shape[t.shape.length - 1]
                tx.executeSql('INSERT OR REPLACE INTO radares (id,kind,lat,lon,lat2,lon2,maxspeed,direction,updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
                    [t.id, 'tramo', s0[1], s0[0], sN[1], sN[0], t.maxspeed || 0, -1, now])
            }
        })
    } catch(e) { _logMsg("✗ Radar DB save: " + e) }
}

// Borra de la zona consultada los radares que YA NO aparecen en la respuesta
// fresca de Overpass (decomisionados/movidos en OSM).
function _pruneRadarsDb(minLat, minLon, maxLat, maxLon, keepIds) {
    var db = _radarDb(); if (!db) return
    try {
        db.transaction(function(tx) {
            var rs = tx.executeSql(
                'SELECT id FROM radares WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
                [minLat, maxLat, minLon, maxLon])
            for (var i = 0; i < rs.rows.length; i++) {
                var id = rs.rows.item(i).id
                if (keepIds.indexOf(id) < 0) tx.executeSql('DELETE FROM radares WHERE id = ?', [id])
            }
        })
    } catch(e) { _logMsg("✗ Radar DB prune: " + e) }
}

// Consulta local, instantánea y offline-capable (sin filtro de proximidad a ruta:
// aproximación rápida, el merge con Overpass la corrige cuando responde).
function _queryRadarsDb(minLat, minLon, maxLat, maxLon) {
    var db = _radarDb()
    var out = { fijos: [], tramos: [] }
    if (!db) return out
    try {
        db.readTransaction(function(tx) {
            var rs = tx.executeSql(
                'SELECT * FROM radares WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?',
                [minLat, maxLat, minLon, maxLon])
            for (var i = 0; i < rs.rows.length; i++) {
                var r = rs.rows.item(i)
                if (r.kind === 'fijo') {
                    out.fijos.push({ id: r.id, lat: r.lat, lon: r.lon, maxspeed: r.maxspeed,
                                     direction: r.direction, descr: r.descr || "" })
                } else {
                    var shp = [[r.lon, r.lat], [r.lon2, r.lat2]]
                    out.tramos.push({ id: r.id, shape: shp, origShape: shp, maxspeed: r.maxspeed, lengthM: 0 })
                }
            }
        })
    } catch(e) { _logMsg("✗ Radar DB query: " + e) }
    return out
}

function _radarKeepIds(result) {
    return result.fijos.map(function(f) { return f.id }).concat(result.tramos.map(function(t) { return t.id }))
}

// Remoto (b) tiene prioridad sobre local (a) cuando coinciden ids (datos más frescos).
function _mergeRadarSets(remote, local) {
    var seen = {}, fijos = [], tramos = []
    function addF(f) { if (seen['f'+f.id]) return; seen['f'+f.id] = true; fijos.push(f) }
    function addT(t) { if (seen['t'+t.id]) return; seen['t'+t.id] = true; tramos.push(t) }
    remote.fijos.forEach(addF);  local.fijos.forEach(addF)
    remote.tramos.forEach(addT); local.tramos.forEach(addT)
    return { fijos: fijos, tramos: tramos }
}

function _radarMetaGet(key) {
    var db = _radarDb(); if (!db) return null
    var val = null
    try {
        db.readTransaction(function(tx) {
            var rs = tx.executeSql('SELECT value FROM radares_meta WHERE key=?', [key])
            if (rs.rows.length > 0) val = rs.rows.item(0).value
        })
    } catch(e) {}
    return val
}

function _radarMetaSet(key, value) {
    var db = _radarDb(); if (!db) return
    try {
        db.transaction(function(tx) {
            tx.executeSql('INSERT OR REPLACE INTO radares_meta (key,value) VALUES (?,?)', [key, value])
        })
    } catch(e) {}
}

// Barrido diario: revalida contra Overpass, celda a celda (~0.3°), toda la zona
// cubierta por la caché local, podando lo que ya no exista. Una celda cada 3 s
// para no saturar el servidor. Se relanza solo una vez al día.
function maybeRunDailyRadarSweep() {
    var db = _radarDb(); if (!db) return
    var today = new Date().toISOString().slice(0, 10)
    if (_radarMetaGet('radar_sweep_date') === today) return
    _radarMetaSet('radar_sweep_date', today)
    _logMsg("Barrido diario de radares: iniciado")
    _sweepRadarCells(0)
}

function _sweepRadarCells(cellIdx) {
    var db = _radarDb(); if (!db) return
    var CELL = 0.3
    db.readTransaction(function(tx) {
        var rs = tx.executeSql(
            'SELECT cy, cx FROM (SELECT DISTINCT CAST(lat/? AS INT) AS cy, CAST(lon/? AS INT) AS cx FROM radares) LIMIT 1 OFFSET ?',
            [CELL, CELL, cellIdx])
        if (rs.rows.length === 0) { _logMsg("Barrido diario de radares: completado (" + cellIdx + " celdas)"); return }
        var cell = rs.rows.item(0)
        var minLat = cell.cy * CELL, maxLat = minLat + CELL
        var minLon = cell.cx * CELL, maxLon = minLon + CELL
        var bbox = minLat.toFixed(5) + "," + minLon.toFixed(5) + "," + maxLat.toFixed(5) + "," + maxLon.toFixed(5)
        _overpassPost(bbox, function(text) {
            if (text) {
                _parseRadarResponse(text, null, function(remote) {
                    _saveRadarsToDb(remote.fijos, remote.tramos)
                    _pruneRadarsDb(minLat, minLon, maxLat, maxLon, _radarKeepIds(remote))
                    if (_defer) _defer(function() { _sweepRadarCells(cellIdx + 1) }, 3000)
                })
            } else if (_defer) {
                _defer(function() { _sweepRadarCells(cellIdx + 1) }, 3000)
            }
        })
    })
}

// Carga radares a lo largo de una ruta (filtra por proximidad al shape).
// Responde primero con la caché local si hay algo (instantáneo/offline), y
// otra vez con el resultado fusionado con Overpass en cuanto responde.
function fetchRadars(shape, callback) {
    if (!shape || shape.length < 2) { callback({fijos:[], tramos:[]}); return }
    var minLat = shape[0][1], maxLat = shape[0][1], minLon = shape[0][0], maxLon = shape[0][0]
    for (var i = 1; i < shape.length; i++) {
        if (shape[i][1] < minLat) minLat = shape[i][1]
        if (shape[i][1] > maxLat) maxLat = shape[i][1]
        if (shape[i][0] < minLon) minLon = shape[i][0]
        if (shape[i][0] > maxLon) maxLon = shape[i][0]
    }
    var buf = 0.025
    minLat -= buf; maxLat += buf; minLon -= buf; maxLon += buf
    var bbox = minLat.toFixed(5)+","+minLon.toFixed(5)+","+
               maxLat.toFixed(5)+","+maxLon.toFixed(5)
    var local = _queryRadarsDb(minLat, minLon, maxLat, maxLon)
    if (local.fijos.length || local.tramos.length)
        callback({fijos: local.fijos, tramos: local.tramos, fromCache: true})
    _overpassPost(bbox, function(text, failed) {
        if (!text) {
            if (!local.fijos.length && !local.tramos.length) callback({fijos:[], tramos:[], error: !!failed})
            return
        }
        _parseRadarResponse(text, shape, function(remote) {
            _saveRadarsToDb(remote.fijos, remote.tramos)
            _pruneRadarsDb(minLat, minLon, maxLat, maxLon, _radarKeepIds(remote))
            callback(_mergeRadarSets(remote, local))
        })
    })
}

// Carga radares en un bounding box (sin filtrar por ruta; para vista de mapa).
// Mismo patrón local-primero + merge con Overpass que fetchRadars.
function fetchRadarsBbox(minLat, minLon, maxLat, maxLon, callback) {
    var bbox = minLat.toFixed(5)+","+minLon.toFixed(5)+","+
               maxLat.toFixed(5)+","+maxLon.toFixed(5)
    var local = _queryRadarsDb(minLat, minLon, maxLat, maxLon)
    if (local.fijos.length || local.tramos.length)
        callback({fijos: local.fijos, tramos: local.tramos, fromCache: true})
    _overpassPost(bbox, function(text, failed) {
        if (!text) {
            if (!local.fijos.length && !local.tramos.length) callback({fijos:[], tramos:[], error: !!failed})
            return
        }
        _parseRadarResponse(text, null, function(remote) {
            _saveRadarsToDb(remote.fijos, remote.tramos)
            _pruneRadarsDb(minLat, minLon, maxLat, maxLon, _radarKeepIds(remote))
            callback(_mergeRadarSets(remote, local))
        })
    })
}
