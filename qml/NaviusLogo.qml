import QtQuick 2.7
import QtQuick.Controls 2.15

// Logo completo: icono SVG + "NAVIUS" + tagline "Navegación comunitaria"
// Uso: NaviusLogo { size: units.gu(4) }
Item {
    id: root
    property real size: units.gu(4)

    implicitWidth:  logoRow.implicitWidth
    implicitHeight: col.implicitHeight

    Column {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: size * 0.2

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "qrc:/assets/logo.svg"
            width:  root.size * 2.2
            height: root.size * 2.2
            smooth: true
            fillMode: Image.PreserveAspectFit
        }

        Row {
            id: logoRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0
            Label {
                text: "NAV"
                color: "white"
                font.pixelSize: root.size
                font.bold: true
                font.letterSpacing: root.size * 0.12
            }
            Label {
                text: "IUS"
                color: "#2196F3"
                font.pixelSize: root.size
                font.bold: true
                font.letterSpacing: root.size * 0.12
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: i18n.tr("Navegación comunitaria")
            color: "#888"
            font.pixelSize: root.size * 0.38
            font.letterSpacing: root.size * 0.03
        }
    }
}
