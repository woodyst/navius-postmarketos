import QtQuick 2.7
import QtQuick.Controls 2.15

Rectangle {
    id: dlg
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.centerIn: parent
    z: 150
    width: units.gu(38); height: units.gu(16)
    color: "#CC0D0D1A"; radius: units.gu(1.2)
    border.color: "#29B6F6"; border.width: units.gu(0.2)

    signal restoreAccepted()
    signal restoreDeclined()

    Column {
        anchors.centerIn: parent; spacing: units.gu(1.8)
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: i18n.tr("Ruta activa al cerrar la app")
            color: "white"; font.bold: true; font.pixelSize: ts(2.2)
        }
        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: i18n.tr("¿Continuar con la ruta anterior?")
            color: "#AAAAAA"; font.pixelSize: ts(1.9)
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; spacing: units.gu(3)
            Rectangle {
                width: units.gu(14); height: units.gu(4.5); radius: units.gu(0.8)
                color: "#29B6F6"
                Label { anchors.centerIn: parent; text: i18n.tr("Sí, continuar")
                        color: "white"; font.bold: true; font.pixelSize: ts(1.9) }
                MouseArea { anchors.fill: parent; onClicked: dlg.restoreAccepted() }
            }
            Rectangle {
                width: units.gu(14); height: units.gu(4.5); radius: units.gu(0.8)
                color: "#90A4AE"
                Label { anchors.centerIn: parent; text: i18n.tr("No, cancelar")
                        color: "white"; font.bold: true; font.pixelSize: ts(1.9) }
                MouseArea { anchors.fill: parent; onClicked: dlg.restoreDeclined() }
            }
        }
    }
}
