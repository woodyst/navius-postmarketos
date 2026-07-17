.pragma library

var _serverUrl = "https://navius-api.egpsistemas.com"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function _xhr(method, path, deviceId, token, body, cb) {
    var r = new XMLHttpRequest()
    r.open(method, _serverUrl + path)
    r.setRequestHeader("X-Device-Id", deviceId)
    if (token) r.setRequestHeader("Authorization", "Bearer " + token)
    if (body)  r.setRequestHeader("Content-Type", "application/json")
    r.timeout = 10000
    r.onreadystatechange = function() {
        if (r.readyState !== 4) return
        var ok = (r.status >= 200 && r.status < 300)
        var data = null
        if (r.responseText) {
            try { data = JSON.parse(r.responseText) } catch(e) {}
        }
        cb(ok, data, r.status)
    }
    r.ontimeout = function() { cb(false, null, 0) }
    r.send(body ? JSON.stringify(body) : null)
}

// ---------------------------------------------------------------------------
// GET /api/v1/mensajes  — devuelve mensajes del buzón para este device.
// sinceId=0 para traer todos; >0 para polling incremental.
// callback(msgs_array, error_string)
// ---------------------------------------------------------------------------
function fetchMsgs(deviceId, token, sinceId, callback) {
    if (!deviceId) return
    var path = "/api/v1/mensajes" + (sinceId > 0 ? "?desde_id=" + sinceId : "")
    _xhr("GET", path, deviceId, token, null, function(ok, data) {
        if (ok && Array.isArray(data)) callback(data, null)
        else callback(null, "error")
    })
}

// ---------------------------------------------------------------------------
// POST /api/v1/mensajes/:id/leido
// ---------------------------------------------------------------------------
function markRead(deviceId, token, msgId, callback) {
    _xhr("POST", "/api/v1/mensajes/" + msgId + "/leido",
        deviceId, token, null, function(ok) { if (callback) callback(ok) })
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/mensajes/:id  — eliminación suave (solo para este device)
// ---------------------------------------------------------------------------
function deleteMsg(deviceId, token, msgId, callback) {
    _xhr("DELETE", "/api/v1/mensajes/" + msgId,
        deviceId, token, null, function(ok) { if (callback) callback(ok) })
}
