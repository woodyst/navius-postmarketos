import QtQuick 2.7
import QtQuick.Controls 2.15

Item {
    id: banner
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors { left: parent.left; right: parent.right }
    height: banner._offline ? units.gu(4.5) : 0

    property real topY:         0
    property bool osmScoutMaps: false
    property bool isOffline:    _offline

    property bool _offline: false

    y: topY

    Timer {
        interval: banner._offline ? 6000 : 30000
        repeat: true; running: true
        onTriggered: {
            var xhr = new XMLHttpRequest()
            xhr.open("HEAD", "https://tiles.openfreemap.org/health", true)
            xhr.timeout = 5000
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return
                banner._offline = (xhr.status === 0)
            }
            xhr.onerror   = function() { banner._offline = true }
            xhr.ontimeout = function() { banner._offline = true }
            xhr.send()
        }
    }

    Rectangle {
        visible: banner._offline
        anchors.fill: parent
        z: 120
        color: "#DD3E2723"

        Row {
            anchors.centerIn: parent; spacing: units.gu(1)
            Label { text: "⚠"; color: "#FFA726"; font.pixelSize: ts(2.2) }
            Label {
                text: banner.osmScoutMaps
                    ? i18n.tr("Sin conexión — Mapas disponibles vía OSM Scout")
                    : i18n.tr("Sin conexión — el mapa no está disponible")
                color: "white"; font.pixelSize: ts(1.6); font.bold: true
            }
        }
    }
}
