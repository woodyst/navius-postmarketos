import QtQuick 2.7
import QtQuick.Controls 2.15

Item {
    id: trd
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    visible: false

    property int currentTimeSec: 0
    property int altTimeSec:     0
    property int timeSavedSec:   0

    signal routeAccepted()
    signal routeRejected()

    function _fmt(secs) {
        var h = Math.floor(secs / 3600)
        var m = Math.floor((secs % 3600) / 60)
        if (h > 0) return h + " h " + m + " min"
        return m > 0 ? m + " min" : "< 1 min"
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: col.implicitHeight + units.gu(2)
        color: "#0D1B2A"

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.1); color: "#4CAF50"; opacity: 0.7
        }

        Column {
            id: col
            anchors {
                left: parent.left; right: parent.right
                top: parent.top
                margins: units.gu(1.5)
            }
            spacing: units.gu(1.2)

            Row {
                spacing: units.gu(1)
                Label { anchors.verticalCenter: parent.verticalCenter; text: "🚦"; font.pixelSize: ts(2.2) }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: i18n.tr("Ruta más rápida disponible")
                    color: "white"; font.pixelSize: ts(1.8); font.bold: true
                }
            }

            Row {
                width: parent.width; spacing: units.gu(1)

                Rectangle {
                    width: (parent.width - units.gu(1)) / 2
                    height: units.gu(8.5); radius: units.gu(0.8)
                    color: "#1C2C3C"
                    border.color: "#37474F"; border.width: units.gu(0.1)
                    Column {
                        anchors.centerIn: parent; spacing: units.gu(0.4)
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: i18n.tr("Ruta actual")
                            color: "#B0BEC5"; font.pixelSize: ts(1.3)
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: trd._fmt(trd.currentTimeSec)
                            color: "white"; font.pixelSize: ts(2); font.bold: true
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - units.gu(1)) / 2
                    height: units.gu(8.5); radius: units.gu(0.8)
                    color: "#1B3A1B"
                    border.color: "#4CAF50"; border.width: units.gu(0.2)
                    Column {
                        anchors.centerIn: parent; spacing: units.gu(0.4)
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: i18n.tr("Ruta rápida")
                            color: "#81C784"; font.pixelSize: ts(1.3)
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: trd._fmt(trd.altTimeSec)
                            color: "#4CAF50"; font.pixelSize: ts(2); font.bold: true
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "-" + Math.round(trd.timeSavedSec / 60) + " min"
                            color: "#A5D6A7"; font.pixelSize: ts(1.3)
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: acceptArea.pressed ? "#1B5E20" : "#2E7D32"
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Usar ruta más rápida")
                    color: "white"; font.pixelSize: ts(1.7); font.bold: true
                }
                MouseArea { id: acceptArea; anchors.fill: parent; onClicked: trd.routeAccepted() }
            }

            Rectangle {
                width: parent.width; height: units.gu(4.5); radius: units.gu(0.8)
                color: rejectArea.pressed ? "#1C2C3C" : "#263238"
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Mantener ruta actual")
                    color: "#90A4AE"; font.pixelSize: ts(1.6)
                }
                MouseArea { id: rejectArea; anchors.fill: parent; onClicked: trd.routeRejected() }
            }
        }
    }
}
