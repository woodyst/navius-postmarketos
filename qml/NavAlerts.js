.pragma library

var _serverUrl = "https://navius-api.egpsistemas.com"

function setServerUrl(url) { _serverUrl = url }

// Qt 5.12 bug: for 4xx/5xx responses QML XHR resets status=0 and clears
// responseText at readyState=4. Status and body are still available at
// readyState=2 (HEADERS_RECEIVED) and readyState=3 (LOADING).
// This wrapper captures them early and restores at DONE.
function _xhrPost(url, token, body, callback) {
    // callback(status, responseText)
    var xhr = new XMLHttpRequest()
    var savedStatus = 0
    var savedBody   = ""
    xhr.open("POST", url)
    xhr.setRequestHeader("Content-Type", "application/json")
    if (token) xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.onreadystatechange = function() {
        if (xhr.readyState >= 2 && xhr.status !== 0)      savedStatus = xhr.status
        if (xhr.readyState >= 3 && xhr.responseText !== "") savedBody  = xhr.responseText
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        var st = xhr.status       !== 0  ? xhr.status       : savedStatus
        var rb = xhr.responseText !== "" ? xhr.responseText : savedBody
        callback(st, rb)
    }
    xhr.send(JSON.stringify(body))
}

function _xhrGet(url, callback) {
    // callback(status, responseText)
    var xhr = new XMLHttpRequest()
    var savedStatus = 0
    var savedBody   = ""
    xhr.open("GET", url)
    xhr.onreadystatechange = function() {
        if (xhr.readyState >= 2 && xhr.status !== 0)      savedStatus = xhr.status
        if (xhr.readyState >= 3 && xhr.responseText !== "") savedBody  = xhr.responseText
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        var st = xhr.status       !== 0  ? xhr.status       : savedStatus
        var rb = xhr.responseText !== "" ? xhr.responseText : savedBody
        callback(st, rb)
    }
    xhr.send()
}

function login(email, password, callback) {
    // callback(ok, token_o_null, id_usuario, mensaje_error)
    _xhrPost(_serverUrl + "/api/v1/usuarios/login", null,
             { email: email, password: password },
             function(status, body) {
                 if (status === 200) {
                     try {
                         var data = JSON.parse(body)
                         callback(true, data.token, data.id || 0, "")
                     } catch(e) { callback(false, null, 0, "Respuesta inválida") }
                 } else if (status === 401) {
                     callback(false, null, 0, "Email o contraseña incorrectos")
                 } else if (status === 403) {
                     callback(false, null, 0, "Confirma tu email antes de iniciar sesión")
                 } else {
                     callback(false, null, 0, "Error " + status)
                 }
             })
}

function registro(email, password, callback) {
    // callback(ok, mensaje, puedeReenviar)
    _xhrPost(_serverUrl + "/api/v1/usuarios/registro", null,
             { email: email, password: password },
             function(status, body) {
                 if (status === 201) {
                     callback(true, "", false)
                 } else if (status === 409) {
                     try {
                         var data = JSON.parse(body)
                         if (data.error === "email_no_verificado")
                             callback(false, "Este email está registrado pero no verificado.", true)
                         else
                             callback(false, "Ese email ya está registrado.", false)
                     } catch(e) { callback(false, "Ese email ya está registrado.", false) }
                 } else {
                     callback(false, "Error " + status, false)
                 }
             })
}

function reenviarVerificacion(email, callback) {
    _xhrPost(_serverUrl + "/api/v1/usuarios/reenviar-verificacion", null,
             { email: email, password: "" },
             function(status, body) { callback(status === 200) })
}

function enviarAlerta(token, params, callback) {
    _xhrPost(_serverUrl + "/api/v1/alertas", token, params,
             function(status, body) { callback(status === 201, status) })
}

function _b64Decode(s) {
    var t = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    s = s.replace(/-/g,'+').replace(/_/g,'/')
    while (s.length%4) s+='='
    var r=''
    for(var i=0;i<s.length;i+=4){
        var b0=t.indexOf(s[i]),b1=t.indexOf(s[i+1]),b2=t.indexOf(s[i+2]),b3=t.indexOf(s[i+3])
        r+=String.fromCharCode((b0<<2)|(b1>>4))
        if(s[i+2]!=='=') r+=String.fromCharCode(((b1&0xf)<<4)|(b2>>2))
        if(s[i+3]!=='=') r+=String.fromCharCode(((b2&0x3)<<6)|b3)
    }
    return r
}

function jwtSub(token) {
    try { return JSON.parse(_b64Decode(token.split('.')[1])).sub || 0 }
    catch(e) { return 0 }
}

function votar(token, alertaId, confirma, callback) {
    _xhrPost(_serverUrl + "/api/v1/alertas/" + alertaId + "/voto", token,
             { voto: confirma },
             function(status, body) { callback(status === 200) })
}

function eliminarAlerta(token, alertaId, callback) {
    var xhr = new XMLHttpRequest()
    var savedStatus = 0
    xhr.open("DELETE", _serverUrl + "/api/v1/alertas/" + alertaId)
    if (token) xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.onreadystatechange = function() {
        if (xhr.readyState >= 2 && xhr.status !== 0) savedStatus = xhr.status
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        var st = xhr.status !== 0 ? xhr.status : savedStatus
        callback(st === 200)
    }
    xhr.send()
}

function eliminarLimite(token, limiteId, callback) {
    var xhr = new XMLHttpRequest()
    var savedStatus = 0
    xhr.open("DELETE", _serverUrl + "/api/v1/limites/" + limiteId)
    if (token) xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.onreadystatechange = function() {
        if (xhr.readyState >= 2 && xhr.status !== 0) savedStatus = xhr.status
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        var st = xhr.status !== 0 ? xhr.status : savedStatus
        callback(st === 200)
    }
    xhr.send()
}

function obtenerAlertas(lat, lng, radio, callback) {
    var url = _serverUrl + "/api/v1/alertas?lat=" + lat + "&lng=" + lng + "&radio=" + (radio || 10000)
    _xhrGet(url, function(status, body) {
        if (status === 200) {
            try { callback(true, JSON.parse(body)) }
            catch(e) { callback(false, []) }
        } else {
            callback(false, [])
        }
    })
}

function obtenerLimites(lat, lng, callback) {
    var url = _serverUrl + "/api/v1/limites?lat=" + lat + "&lng=" + lng + "&radio=5"
    _xhrGet(url, function(status, body) {
        if (status === 200) {
            try { callback(true, JSON.parse(body)) }
            catch(e) { callback(false, []) }
        } else {
            callback(false, [])
        }
    })
}

function enviarLimite(token, lat, lng, bearing, velocidad, callback) {
    _xhrPost(_serverUrl + "/api/v1/limites", token,
        { lat: lat, lng: lng, bearing: bearing, velocidad: velocidad },
        function(st, body) {
            callback(st === 201)
        })
}

function obtenerBillboards(lat, lng, radio, token, callback) {
    var url = _serverUrl + "/api/v1/billboards?lat=" + lat + "&lng=" + lng + "&radio=" + (radio || 30)
    var xhr = new XMLHttpRequest()
    var savedStatus = 0, savedBody = ""
    xhr.open("GET", url)
    if (token) xhr.setRequestHeader("Authorization", "Bearer " + token)
    xhr.onreadystatechange = function() {
        if (xhr.readyState >= 2 && xhr.status !== 0)       savedStatus = xhr.status
        if (xhr.readyState >= 3 && xhr.responseText !== "") savedBody   = xhr.responseText
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        var st = xhr.status !== 0 ? xhr.status : savedStatus
        var rb = xhr.responseText !== "" ? xhr.responseText : savedBody
        if (st === 200) {
            try { callback(true, JSON.parse(rb)) } catch(e) { callback(false, []) }
        } else { callback(false, []) }
    }
    xhr.send()
}

function logRuta(token, deviceId, shapeJson) {
    if (!token || !shapeJson) return
    _xhrPost(_serverUrl + "/api/v1/rutas", token,
             { device_id: deviceId || "", shape_json: shapeJson }, function() {})
}

function enviarTelemetria(token, deviceId, puntos, debug) {
    if (!token || !puntos || puntos.length === 0) return
    var body = { device_id: deviceId || "", puntos: puntos }
    if (debug) body.debug = true
    _xhrPost(_serverUrl + "/api/v1/telemetria", token, body, function() {})
}

function registrarImpresion(token, deviceId, billboardId) {
    if (!billboardId) return
    var xhr = new XMLHttpRequest()
    xhr.open("POST", _serverUrl + "/api/v1/billboards/" + billboardId + "/impresion")
    xhr.setRequestHeader("Content-Type", "application/json")
    if (token) xhr.setRequestHeader("Authorization", "Bearer " + token)
    if (deviceId) xhr.setRequestHeader("X-Device-Id", deviceId)
    xhr.onreadystatechange = function() {}
    xhr.send("{}")
}

function clickUrl(billboardId, token) {
    var url = _serverUrl + "/api/v1/billboards/" + billboardId + "/click"
    if (token) url += "?token=" + encodeURIComponent(token)
    return url
}
