.pragma library

// ── Configuración del servidor ────────────────────────────────────────────────
var _serverUrl = "https://navius-api.egpsistemas.com"
function setServerUrl(u) { _serverUrl = u }
function serverUrl()     { return _serverUrl }

// ── Claves que se sincronizan con el servidor ─────────────────────────────────
// Nombres lógicos independientes de la categoría Qt Settings.
// Al mover un setting de categoría en la app, la clave aquí no cambia → no se pierde.
// NO incluir: posición GPS, estado runtime, rutas activas, opciones de debug/sim.
var SYNC_KEYS = [
    // Mapa
    "bearingMode", "autoZoomSecs", "mapMode", "navMapMode", "pitch3d",
    "mapStyleMode", "show3dBuildings", "showZoomSlider", "showSimScrubber",
    "mapCacheMaxMb", "mapOnlineSource", "mapOfflineMode", "mapTileServer",
    "mapNaviusDayStyle", "mapNaviusStyles",
    // Rutas / servidor
    "valhallaUrl", "valhallaCustomServers", "preferOsmScout",
    "overpassServer", "routeAdjustZoom", "routeAheadSecs",
    // GPS
    "drHz", "drEnabled", "useHardwareSpeed", "showGpsSmoothDebug",
    // Velocidad / radar
    "speedAlertPct", "speedAlertEnabled",
    "showRadarFijos", "showRadarTramo", "radarAlertDist",
    "showRoadSpeedLimit", "inhibitSuspend",
    // Voz / sonido
    "alertSound", "instrSound", "ttsLang", "ttsEngine",
    "ttsVoice", "ttsVoicePico", "ttsVoiceEspeak",
    // UI
    "textScale", "measureSystem", "showChangesAtStartup",
    // Vehículos (lista para recuperar en dispositivo nuevo)
    "vehiclesJson"
]

// ── Snapshot: extrae las claves sincronizables de appSettings ─────────────────
function snapshot(s) {
    var obj = {}
    for (var i = 0; i < SYNC_KEYS.length; i++) {
        var k = SYNC_KEYS[i]
        if (s[k] !== undefined) obj[k] = s[k]
    }
    return obj
}

// ── Apply: aplica datos del servidor a appSettings ────────────────────────────
// Ignora claves desconocidas (settings nuevos en la app, datos de versión anterior).
// Convierte tipos según el valor local actual para robustez.
function applySnapshot(s, data) {
    for (var k in data) {
        if (!data.hasOwnProperty(k)) continue
        if (s[k] === undefined) continue   // clave desconocida → ignorar
        var local = s[k]
        var val   = data[k]
        try {
            if      (typeof local === "boolean") s[k] = (val === true || val === "true")
            else if (typeof local === "number")  s[k] = Number(val)
            else                                 s[k] = String(val)
        } catch(e) { /* ignorar error en este key */ }
    }
}

// ── XHR helper con workaround Qt 5.12 ────────────────────────────────────────
function _xhr(method, url, token, body, callback) {
    // callback(status, responseText)
    // Qt 5.12 bug: en errores 4xx/5xx status=0 y responseText="" en readyState=4
    var xhr = new XMLHttpRequest()
    var savedStatus = 0, savedBody = ""
    xhr.open(method, url)
    xhr.setRequestHeader("Content-Type", "application/json")
    if (token) xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.onreadystatechange = function() {
        if (xhr.readyState >= 2 && xhr.status !== 0)       savedStatus = xhr.status
        if (xhr.readyState >= 3 && xhr.responseText !== "") savedBody   = xhr.responseText
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        var st = xhr.status       !== 0  ? xhr.status       : savedStatus
        var rb = xhr.responseText !== "" ? xhr.responseText : savedBody
        callback(st, rb)
    }
    xhr.send(body !== null ? JSON.stringify(body) : null)
}

// ── GET /api/v1/settings ──────────────────────────────────────────────────────
// callback(ok, settingsObj, updatedAt, errCode)
// errCode: "" = ok | "404" = servidor sin soporte | "401" = no auth | "net" = red | "ENN" = otro
function getSettings(token, callback) {
    _xhr("GET", _serverUrl + "/api/v1/settings", token, null, function(st, rb) {
        if (st === 200) {
            try {
                var d = JSON.parse(rb)
                callback(true, d.settings || {}, d.updated_at || "", "")
            } catch(e) {
                callback(false, {}, "", "parse")
            }
        } else if (st === 0) {
            callback(false, {}, "", "net")
        } else {
            callback(false, {}, "", String(st))
        }
    })
}

// ── PUT /api/v1/settings ─────────────────────────────────────────────────────
// callback(ok, errCode)
function putSettings(token, settingsObj, callback) {
    _xhr("PUT", _serverUrl + "/api/v1/settings", token,
         { settings: settingsObj },
         function(st, rb) {
             if (st === 200) callback(true, "")
             else if (st === 0) callback(false, "net")
             else callback(false, String(st))
         })
}
