import QtQuick 2.7
import QtQuick.Controls 2.15

Item {
    id: sld
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false
    z: 30

    property real   lat:       0
    property real   lon:       0
    property string locName:   ""
    property bool   navActive: false
    property bool   hasDests:  false
    property bool   debugMode: false

    signal destRequested(real lat, real lon, string name)
    signal originRequested(real lat, real lon, string name)
    signal waypointRequested(real lat, real lon, string name)
    signal dismissed()

    onVisibleChanged: if (visible) nameInput.text = sld.locName

    property real _kbdH: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    Behavior on _kbdH { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // Fondo semitransparente
    Rectangle {
        anchors.fill: parent
        color: "#88000000"
        MouseArea { anchors.fill: parent; onClicked: sld.dismissed() }
    }

    // Panel inferior
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: sld._kbdH
        height: sheetCol.implicitHeight + units.gu(4)
        color: "#EE07111E"

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.12); color: "#29B6F6"; opacity: 0.5
        }

        Column {
            id: sheetCol
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: units.gu(2); rightMargin: units.gu(2); topMargin: units.gu(2)
            }
            spacing: units.gu(1)

            // Cabecera
            Column {
                width: parent.width
                spacing: units.gu(0.3)
                Label {
                    text: "📍 " + (sld.locName || i18n.tr("Ubicación compartida"))
                    color: "white"; font.pixelSize: ts(1.8); font.bold: true
                    elide: Text.ElideRight; width: parent.width
                }
                Label {
                    text: sld.lat.toFixed(6) + ", " + sld.lon.toFixed(6)
                    color: "#90A4AE"; font.pixelSize: ts(1.4)
                    font.family: "Ubuntu Mono"
                }
            }

            // Campo de nombre editable
            Rectangle {
                width: parent.width; height: units.gu(5)
                color: "#1C2A3A"; radius: units.gu(0.6)
                border.color: nameInput.activeFocus ? "#29B6F6" : "#37474F"
                border.width: units.gu(0.12)
                NavTextInput {
                    id: nameInput
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: units.gu(1.2); rightMargin: units.gu(1.2)
                    }
                    color: "white"; font.pixelSize: ts(1.7)
                    clip: true
                    Label {
                        anchors.fill: parent; anchors.leftMargin: 0
                        visible: nameInput.text.length === 0
                        text: i18n.tr("Nombre del lugar")
                        color: "#90A4AE"; font.pixelSize: ts(1.7)
                    }
                }
            }

            Rectangle { width: parent.width; height: units.gu(0.08); color: "#29B6F6"; opacity: 0.3 }

            // Opción: Establecer destino
            Rectangle {
                width: parent.width; height: units.gu(6.5); radius: units.gu(0.8)
                color: destArea.pressed ? "#1E3A5F" : "#1C1C2E"
                border.color: "#29B6F6"; border.width: units.gu(0.15)
                Row {
                    anchors { left: parent.left; leftMargin: units.gu(1.8)
                              verticalCenter: parent.verticalCenter }
                    spacing: units.gu(1.2)
                    Label { text: "🏁"; font.pixelSize: ts(2.2)
                            anchors.verticalCenter: parent.verticalCenter }
                    Label { text: i18n.tr("Establecer destino"); color: "#29B6F6"
                            font.pixelSize: ts(1.7)
                            anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: destArea; anchors.fill: parent
                    onClicked: sld.destRequested(sld.lat, sld.lon, nameInput.text.trim() || sld.locName) }
            }

            // Opción: Establecer origen (sim GPS) — solo en debug
            Rectangle {
                visible: sld.debugMode
                width: parent.width; height: units.gu(6.5); radius: units.gu(0.8)
                color: origArea.pressed ? "#1E3A5F" : "#1C1C2E"
                border.color: "#90A4AE"; border.width: units.gu(0.15)
                Row {
                    anchors { left: parent.left; leftMargin: units.gu(1.8)
                              verticalCenter: parent.verticalCenter }
                    spacing: units.gu(1.2)
                    Label { text: "📌"; font.pixelSize: ts(2.2)
                            anchors.verticalCenter: parent.verticalCenter }
                    Label { text: i18n.tr("Establecer origen (sim GPS)"); color: "#90A4AE"
                            font.pixelSize: ts(1.7)
                            anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: origArea; anchors.fill: parent
                    onClicked: sld.originRequested(sld.lat, sld.lon, nameInput.text.trim() || sld.locName) }
            }

            // Opción: Añadir como siguiente destino (si hay destinos o nav activa)
            Rectangle {
                visible: sld.hasDests || sld.navActive
                width: parent.width; height: units.gu(6.5); radius: units.gu(0.8)
                color: wpArea.pressed ? "#1E3A5F" : "#1C1C2E"
                border.color: "#90A4AE"; border.width: units.gu(0.15)
                Row {
                    anchors { left: parent.left; leftMargin: units.gu(1.8)
                              verticalCenter: parent.verticalCenter }
                    spacing: units.gu(1.2)
                    Label { text: "➕"; font.pixelSize: ts(2.2)
                            anchors.verticalCenter: parent.verticalCenter }
                    Label { text: i18n.tr("Añadir como siguiente destino"); color: "#90A4AE"
                            font.pixelSize: ts(1.7)
                            anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { id: wpArea; anchors.fill: parent
                    onClicked: sld.waypointRequested(sld.lat, sld.lon, nameInput.text.trim() || sld.locName) }
            }

            // Cancelar
            Rectangle {
                width: parent.width; height: units.gu(6); radius: units.gu(0.8)
                color: "transparent"
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Cancelar"); color: "#B0BEC5"
                    font.pixelSize: ts(1.6)
                }
                MouseArea { anchors.fill: parent; onClicked: sld.dismissed() }
            }
        }
    }
}
