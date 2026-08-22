// navius-gmaps.qml — visor de Google Maps para elegir un destino (postmarketOS).
//
// Equivalente al GoogleMapsPanel.qml de la versión Ubuntu Touch, pero en un
// PROCESO APARTE con Qt6: en Alpine no hay QtWebEngine para Qt5, solo
// qt6-qtwebengine. Lo lanza Navius con el qmlscene de Qt6 (ver
// src/nav_proc.rs). Navius genera una copia de este fichero sustituyendo el
// marcador /*@ARGS@*/ por un objeto JS con:
//   { ua: string, cache: string, lat: number, lon: number,
//     strings: { title, hint, detecting, use, close } }
// Cuando el usuario pulsa "Usar este destino" se escribe por stderr
//   NAVIUS_SEL<TAB>lat<TAB>lon<TAB>nombre
// (console.log) y el proceso termina; Navius recoge esa línea.
//
// Qt6: QtQuick sin versiones, WebEngineNavigationRequest.reject() en vez de
// request.action, permissionRequested en vez de featurePermissionRequested.

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtWebEngine

Item {
    id: gmp
    width: 360; height: 720

    readonly property var args: /*@ARGS@*/ ({})
    readonly property var strs: {
        var d = { title: "Google Maps", hint: "Busca un lugar en el mapa",
                  detecting: "Detectando coordenadas…", use: "Usar este destino",
                  close: "Cerrar" }
        var s = (args && args.strings) ? args.strings : {}
        for (var k in s) if (s[k]) d[k] = s[k]
        return d
    }
    // Unidad de medida: 1/48 del ancho (≈ 7.5 px en 360 de ancho), parecida
    // a la escala de la UI de Navius en este dispositivo.
    function gu(v) { return Math.round(width / 48 * v) }

    property real   _detLat:   0
    property real   _detLon:   0
    property string _detName:  ""
    property string _barState: "empty"   // "empty" | "loading" | "found"

    // UA móvil: mismo que Maps Exporter (funciona con Google)
    readonly property string _mobileUA: (args && args.ua) ? args.ua
        : "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    function _extractCoords(urlStr) {
        var m = urlStr.match(/@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)/)
        if (m) return { lat: parseFloat(m[1]), lon: parseFloat(m[2]) }
        var latM = urlStr.match(/!3d(-?\d+\.?\d+)/)
        var lonM = urlStr.match(/!4d(-?\d+\.?\d+)/)
        if (latM && lonM) return { lat: parseFloat(latM[1]), lon: parseFloat(lonM[1]) }
        return null
    }

    function _extractName(title) {
        return title.replace(/\s*[-–]\s*Google Maps\s*$/, "").split(" – ")[0].trim()
    }

    function _select() {
        // Una sola línea, tabulada; el nombre sin saltos de línea ni tabs.
        var name = gmp._detName.replace(/[\t\r\n]+/g, " ")
        console.log("NAVIUS_SEL\t" + gmp._detLat + "\t" + gmp._detLon + "\t" + name)
        Qt.quit()
    }

    // ── Fondo opaco ────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "#07111E" }

    // ── Barra superior ─────────────────────────────────────────────────────
    Rectangle {
        id: topBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: gu(6.5)
        color: "#0D1B2A"

        Rectangle {
            anchors { left: parent.left; leftMargin: gu(1); verticalCenter: parent.verticalCenter }
            width: gu(5); height: gu(5); radius: width / 2
            color: closeArea.pressed ? "#1C2C3C" : "transparent"
            Label { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: gu(2.2) }
            MouseArea { id: closeArea; anchors.fill: parent; onClicked: Qt.quit() }
        }

        Label {
            anchors { left: parent.left; leftMargin: gu(7.5); verticalCenter: parent.verticalCenter }
            text: gmp.strs.title; color: "white"; font.pixelSize: gu(1.9); font.bold: true
        }

        Rectangle {
            anchors { right: parent.right; rightMargin: gu(1); verticalCenter: parent.verticalCenter }
            width: gu(5); height: gu(5); radius: width / 2
            visible: !webView.loading
            color: cacheArea.pressed ? "#1C2C3C" : "transparent"
            Label { anchors.centerIn: parent; text: "🗑"; font.pixelSize: gu(2.2) }
            MouseArea {
                id: cacheArea; anchors.fill: parent
                onClicked: {
                    webView.profile.clearHttpCache()
                    webView.reload()
                }
            }
        }

        BusyIndicator {
            anchors { right: parent.right; rightMargin: gu(2); verticalCenter: parent.verticalCenter }
            width: gu(3.5); height: gu(3.5)
            running: webView.loading; visible: webView.loading
        }
    }

    // ── WebView ────────────────────────────────────────────────────────────
    WebEngineView {
        id: webView
        anchors { top: topBar.bottom; left: parent.left; right: parent.right; bottom: bottomBar.top }
        zoomFactor: width > 0 ? width / 360 : 1.0

        profile: WebEngineProfile {
            // UA declarado en el perfil (para las peticiones HTTP)
            httpUserAgent: gmp._mobileUA
            storageName: "NaviusMaps"
            persistentStoragePath: (gmp.args && gmp.args.cache) ? gmp.args.cache + "/WebEngine" : ""
            offTheRecord: false
        }

        // Qt6: WebEngineScript ya no es un elemento instanciable; los scripts de
        // usuario son objetos JS que se meten en userScripts.collection.
        property var _userScripts: [
            {
                name: "navius-mobile-ua",
                worldId: WebEngineScript.MainWorld,
                injectionPoint: WebEngineScript.DocumentCreation,
                sourceCode: "(function(){
                    var ua = '" + gmp._mobileUA + "';
                    Object.defineProperty(navigator, 'userAgent',   {get: function(){return ua;}, configurable:true});
                    Object.defineProperty(navigator, 'appVersion',  {get: function(){return ua.substring(8);}, configurable:true});
                    Object.defineProperty(navigator, 'platform',    {get: function(){return 'Linux armv8l';}, configurable:true});
                    Object.defineProperty(navigator, 'maxTouchPoints', {get: function(){return 5;}, configurable:true});
                })();"
            },
            {
                name: "navius-dismiss-appbanner",
                worldId: WebEngineScript.MainWorld,
                injectionPoint: WebEngineScript.DocumentCreation,
                sourceCode: "(function(){
                    var dismissKeywords = ['seguir usando','continuar en el sitio','seguir en el sitio',
                                    'continuar en el navegador','continue on web','stay on web',
                                    'use web','no thanks','not now','continuar','seguir','cancelar'];
                    var hideKeywords = ['abrir aplicación','abrir aplicacion','open app','open in app',
                                        'abrir en la aplicación','ver en la app'];
                    function isVisible(el) {
                        var r = el.getBoundingClientRect();
                        return r.width > 0 || r.height > 0;
                    }
                    function hideModal(el) {
                        var p = el;
                        for (var i = 0; i < 15; i++) {
                            p = p.parentElement;
                            if (!p || p === document.body) break;
                            var cs = window.getComputedStyle(p);
                            if (cs.position === 'fixed' || p.getAttribute('role') === 'dialog'
                                    || p.getAttribute('role') === 'alertdialog') {
                                p.style.setProperty('display','none','important');
                                return;
                            }
                        }
                        el.style.setProperty('display','none','important');
                    }
                    function hideOpenAppButtons() {
                        var els = document.querySelectorAll('button,a,[role=\"button\"]');
                        for (var i = 0; i < els.length; i++) {
                            var t = (els[i].textContent||'').trim().toLowerCase();
                            for (var k = 0; k < hideKeywords.length; k++) {
                                if (t.indexOf(hideKeywords[k]) !== -1 && isVisible(els[i])) {
                                    hideModal(els[i]);
                                    break;
                                }
                            }
                        }
                    }
                    function tryDismiss() {
                        hideOpenAppButtons();
                        // Por jsaction dismiss
                        var dis = document.querySelectorAll('[jsaction*=\"dismiss_action\"]');
                        for (var j = 0; j < dis.length; j++) {
                            if (!isVisible(dis[j])) continue;
                            dis[j].click();
                            hideModal(dis[j]);
                            return;
                        }
                        // Por clase conocida del botón
                        var byClass = document.querySelector('button.vfi8qf, button.l6mLne');
                        if (byClass && isVisible(byClass)) {
                            byClass.click(); hideModal(byClass); return;
                        }
                        // Por texto (banners de continuar en web)
                        var els = document.querySelectorAll('button,[role=\"button\"]');
                        for (var i = 0; i < els.length; i++) {
                            var t = (els[i].textContent||'').trim().toLowerCase();
                            for (var k = 0; k < dismissKeywords.length; k++) {
                                if (t.indexOf(dismissKeywords[k]) !== -1) {
                                    els[i].click(); hideModal(els[i]); return;
                                }
                            }
                        }
                    }
                    document.addEventListener('DOMContentLoaded', tryDismiss);
                    var obs = new MutationObserver(function(){ setTimeout(tryDismiss, 80); });
                    function startObs() {
                        obs.observe(document.documentElement, {childList:true, subtree:true});
                    }
                    if (document.documentElement) startObs();
                    else document.addEventListener('DOMContentLoaded', startObs);
                    setInterval(tryDismiss, 600);
                })();"
            }
        ]

        Component.onCompleted: {
            userScripts.collection = _userScripts
            // Con posición conocida, abrir el mapa centrado ahí.
            var a = gmp.args
            if (a && typeof a.lat === "number" && typeof a.lon === "number" && (a.lat !== 0 || a.lon !== 0))
                url = "https://www.google.com/maps/@" + a.lat.toFixed(6) + "," + a.lon.toFixed(6) + ",15z"
            else
                url = "https://www.google.com/maps"
        }

        onNavigationRequested: function(request) {
            var u = request.url.toString()
            if (!u.startsWith("https://") && !u.startsWith("http://")
                    && !u.startsWith("about:") && !u.startsWith("data:")) {
                request.reject()
            }
        }

        // Geolocalización, micrófono, etc.: siempre denegados (el visor solo
        // sirve para buscar; la posición ya la tiene Navius).
        onPermissionRequested: function(permission) { permission.deny() }

        onUrlChanged: {
            var urlStr = url.toString()
            var isPlace = urlStr.indexOf("/place/") !== -1 || urlStr.indexOf("/search/") !== -1
            var coords  = gmp._extractCoords(urlStr)
            if (coords && isPlace) {
                gmp._detLat   = coords.lat
                gmp._detLon   = coords.lon
                gmp._detName  = gmp._extractName(webView.title)
                gmp._barState = "found"
                pollTimer.stop()
            } else if (isPlace) {
                gmp._barState = "loading"
                pollTimer.restart()
            } else {
                gmp._barState = "empty"
                pollTimer.stop()
            }
        }

        onTitleChanged: {
            if (gmp._barState === "found")
                gmp._detName = gmp._extractName(webView.title)
        }
    }

    // ── Timer de polling cuando /place/ pero aún sin coordenadas ───────────
    Timer {
        id: pollTimer
        interval: 600; repeat: true
        onTriggered: {
            var coords = gmp._extractCoords(webView.url.toString())
            if (coords) {
                gmp._detLat   = coords.lat
                gmp._detLon   = coords.lon
                gmp._detName  = gmp._extractName(webView.title)
                gmp._barState = "found"
                stop()
            }
        }
    }

    // ── Barra inferior ─────────────────────────────────────────────────────
    Rectangle {
        id: bottomBar
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: gu(8)
        color: "#0D1B2A"

        Label {
            anchors.centerIn: parent
            visible: gmp._barState === "empty"
            text: gmp.strs.hint
            color: "#90A4AE"; font.pixelSize: gu(1.6)
        }

        Row {
            anchors.centerIn: parent; spacing: gu(1)
            visible: gmp._barState === "loading"
            BusyIndicator {
                width: gu(3.5); height: gu(3.5)
                running: gmp._barState === "loading"
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: gmp.strs.detecting
                color: "#90A4AE"; font.pixelSize: gu(1.6)
            }
        }

        Rectangle {
            anchors { fill: parent; margins: gu(1) }
            visible: gmp._barState === "found"
            radius: gu(0.8)
            color: useArea.pressed ? "#1B5E20" : "#2E7D32"
            Row {
                anchors.centerIn: parent; spacing: gu(1)
                Label { anchors.verticalCenter: parent.verticalCenter
                    text: "🏁"; font.pixelSize: gu(2.2) }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 0
                    Label { text: gmp.strs.use
                        color: "white"; font.pixelSize: gu(1.8); font.bold: true }
                    Label {
                        visible: gmp._detName.length > 0
                        text: gmp._detName; color: "#A5D6A7"
                        font.pixelSize: gu(1.3); elide: Text.ElideRight
                        width: Math.min(implicitWidth, gmp.width - gu(12))
                    }
                }
            }
            MouseArea {
                id: useArea; anchors.fill: parent
                onClicked: gmp._select()
            }
        }
    }
}
