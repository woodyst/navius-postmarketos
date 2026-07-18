import QtQuick 2.7
import QtWebEngine 1.9
import QtQuick.Controls 2.15

Item {
    id: gmp
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false
    z: 35

    signal locationSelected(real lat, real lon, string name)
    signal dismissed()

    property real   _detLat:   0
    property real   _detLon:   0
    property string _detName:  ""
    property string _barState: "empty"   // "empty" | "loading" | "found"

    // UA móvil: mismo que Maps Exporter (funciona con Google)
    readonly property string _mobileUA: "Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    onVisibleChanged: {
        if (!visible) {
            pollTimer.stop()
        }
    }

    function clearCache() {
        webView.profile.clearHttpCache()
        webView.reload()
    }

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

    // ── Fondo opaco ────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: "#07111E" }

    // ── Barra superior ─────────────────────────────────────────────────────
    Rectangle {
        id: topBar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(6.5)
        color: "#0D1B2A"

        Rectangle {
            anchors { left: parent.left; leftMargin: units.gu(1); verticalCenter: parent.verticalCenter }
            width: units.gu(5); height: units.gu(5); radius: width / 2
            color: closeArea.pressed ? "#1C2C3C" : "transparent"
            Label { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: ts(2.2) }
            MouseArea { id: closeArea; anchors.fill: parent; onClicked: gmp.dismissed() }
        }

        Label {
            anchors { left: parent.left; leftMargin: units.gu(7.5); verticalCenter: parent.verticalCenter }
            text: "Google Maps"; color: "white"; font.pixelSize: ts(1.9); font.bold: true
        }

        Rectangle {
            anchors { right: parent.right; rightMargin: units.gu(1); verticalCenter: parent.verticalCenter }
            width: units.gu(5); height: units.gu(5); radius: width / 2
            visible: !webView.loading
            color: cacheArea.pressed ? "#1C2C3C" : "transparent"
            Label { anchors.centerIn: parent; text: "🗑"; font.pixelSize: ts(2.2) }
            MouseArea {
                id: cacheArea; anchors.fill: parent
                onClicked: {
                    webView.profile.clearHttpCache()
                    webView.reload()
                }
            }
        }

        BusyIndicator {
            anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
            width: units.gu(3.5); height: units.gu(3.5)
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
            persistentStoragePath: cacheDirPath + "/WebEngine"
            offTheRecord: false
        }

        userScripts: [
            WebEngineScript {
                name: "navius-mobile-ua"
                worldId: WebEngineScript.MainWorld
                injectionPoint: WebEngineScript.DocumentCreation
                sourceCode: "(function(){
                    var ua = '" + gmp._mobileUA + "';
                    Object.defineProperty(navigator, 'userAgent',   {get: function(){return ua;}, configurable:true});
                    Object.defineProperty(navigator, 'appVersion',  {get: function(){return ua.substring(8);}, configurable:true});
                    Object.defineProperty(navigator, 'platform',    {get: function(){return 'Linux armv8l';}, configurable:true});
                    Object.defineProperty(navigator, 'maxTouchPoints', {get: function(){return 5;}, configurable:true});
                })();"
            },
            WebEngineScript {
                name: "navius-dismiss-appbanner"
                worldId: WebEngineScript.MainWorld
                injectionPoint: WebEngineScript.DocumentCreation
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

        Component.onCompleted: url = "https://www.google.com/maps"

        onNavigationRequested: function(request) {
            var u = request.url.toString()
            if (!u.startsWith("https://") && !u.startsWith("http://")
                    && !u.startsWith("about:") && !u.startsWith("data:")) {
                request.action = WebEngineNavigationRequest.IgnoreRequest
            }
        }

        onFeaturePermissionRequested: function(origin, feature) {
            grantFeaturePermission(origin, feature, false)
        }

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
        height: units.gu(8)
        color: "#0D1B2A"

        Label {
            anchors.centerIn: parent
            visible: gmp._barState === "empty"
            text: i18n.tr("Busca un lugar en el mapa")
            color: "#90A4AE"; font.pixelSize: ts(1.6)
        }

        Row {
            anchors.centerIn: parent; spacing: units.gu(1)
            visible: gmp._barState === "loading"
            BusyIndicator {
                width: units.gu(3.5); height: units.gu(3.5)
                running: gmp._barState === "loading"
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: i18n.tr("Detectando coordenadas…")
                color: "#90A4AE"; font.pixelSize: ts(1.6)
            }
        }

        Rectangle {
            anchors { fill: parent; margins: units.gu(1) }
            visible: gmp._barState === "found"
            radius: units.gu(0.8)
            color: useArea.pressed ? "#1B5E20" : "#2E7D32"
            Row {
                anchors.centerIn: parent; spacing: units.gu(1)
                Label { anchors.verticalCenter: parent.verticalCenter
                    text: "🏁"; font.pixelSize: ts(2.2) }
                Column {
                    anchors.verticalCenter: parent.verticalCenter; spacing: 0
                    Label { text: i18n.tr("Usar este destino")
                        color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                    Label {
                        visible: gmp._detName.length > 0
                        text: gmp._detName; color: "#A5D6A7"
                        font.pixelSize: ts(1.3); elide: Text.ElideRight
                        width: Math.min(implicitWidth, gmp.width - units.gu(12))
                    }
                }
            }
            MouseArea {
                id: useArea; anchors.fill: parent
                onClicked: gmp.locationSelected(gmp._detLat, gmp._detLon, gmp._detName)
            }
        }
    }
}
