import QtQuick 2.7
import QtQuick.Controls 2.15

// Diálogo de creación de vehículo.
// Uso: vehicleSetupDialog.openDialog(isFirst)
// Señales: accepted(alias, costing)  cancelled()

Item {
    id: dlg
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false
    z: 210

    property bool isFirst: true

    signal accepted(string alias, string costing)
    signal cancelled()

    function openDialog(first) {
        isFirst = (first === true)
        aliasField.text = "Mi coche"
        typeIdx = 0
        visible = true
    }

    property int typeIdx: 0

    property real _kbdH: 0
    Behavior on _kbdH { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    property Item _kbdFocusItem: null

    Connections {
        target: Qt.inputMethod
        function onVisibleChanged()          { if (!Qt.inputMethod.visible) dlg._kbdH = 0; else vehKbdTimer.restart() }
        function onKeyboardRectangleChanged(){ if ( Qt.inputMethod.visible) vehKbdTimer.restart() }
    }
    Timer {
        id: vehKbdTimer; interval: 50
        onTriggered: {
            if (!Qt.inputMethod.visible || !dlg._kbdFocusItem) { dlg._kbdH = 0; return }
            var kbdTop = dlg.height - Qt.inputMethod.keyboardRectangle.height
            var pos    = dlg._kbdFocusItem.mapToItem(dlg, 0, dlg._kbdFocusItem.height)
            var fieldBottomAtZero = pos.y + dlg._kbdH
            dlg._kbdH = Math.max(0, fieldBottomAtZero + units.gu(1.5) - kbdTop)
        }
    }

    readonly property var typeList: [
        { label: i18n.tr("Coche"),     value: "auto"          },
        { label: i18n.tr("Moto"),      value: "motorcycle"    },
        { label: i18n.tr("Scooter"),   value: "motor_scooter" },
        { label: i18n.tr("Camión"),    value: "truck"         },
        { label: i18n.tr("Bicicleta"), value: "bicycle"       }
    ]

    // Fondo oscurecido
    Rectangle {
        anchors.fill: parent
        color: "#BB000010"
        MouseArea { anchors.fill: parent }
    }

    // Tarjeta central
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter:   parent.verticalCenter
        anchors.verticalCenterOffset: -dlg._kbdH
        width:  Math.min(parent.width  * 0.92, units.gu(46))
        height: colMain.implicitHeight + units.gu(4)
        color: "#1A1A2E"; radius: units.gu(1.5)
        border.color: "#29B6F6"; border.width: 1

        Column {
            id: colMain
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
            spacing: units.gu(1.4)

            // Título
            Label {
                text: dlg.isFirst ? i18n.tr("Bienvenido a Navius") : i18n.tr("Nuevo vehículo")
                font.pixelSize: ts(2.8); font.bold: true; color: "#29B6F6"
            }
            Label {
                visible: dlg.isFirst
                width: parent.width; wrapMode: Text.WordWrap
                text: i18n.tr("Crea tu primer vehículo para empezar a navegar.")
                color: "#B0BEC5"; font.pixelSize: ts(1.9)
            }

            // Nombre
            Label { text: i18n.tr("Nombre"); color: "#90A4AE"; font.pixelSize: ts(1.8) }
            Rectangle {
                width: parent.width; height: units.gu(5)
                color: "#252540"; radius: units.gu(0.7)
                border.color: aliasField.activeFocus ? "#29B6F6" : "#37474F"; border.width: 1
                NavTextInput {
                    id: aliasField
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: units.gu(1.2); rightMargin: units.gu(1.2) }
                    text: i18n.tr("Mi coche")
                    color: "#ECEFF1"; font.pixelSize: ts(2.0)
                    selectionColor: "#29B6F6"
                    onActiveFocusChanged: if (activeFocus) dlg._kbdFocusItem = this
                }
            }

            // Tipo
            Label { text: i18n.tr("Tipo"); color: "#90A4AE"; font.pixelSize: ts(1.8) }
            Flow {
                width: parent.width; spacing: units.gu(0.7)
                Repeater {
                    model: dlg.typeList
                    Rectangle {
                        width:  (colMain.width - 2 * units.gu(0.7)) / 3
                        height: units.gu(5.2)
                        radius: height / 2
                        color:  dlg.typeIdx === index ? "#29B6F6" : "#1E2A3A"
                        border.color: "#29B6F6"; border.width: 1
                        Label {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: dlg.typeIdx === index ? "#0A0A1A" : "#90A4AE"
                            font.pixelSize: ts(1.8); font.bold: dlg.typeIdx === index
                        }
                        MouseArea { anchors.fill: parent; onClicked: dlg.typeIdx = index }
                    }
                }
            }

            // Botones
            Row {
                width: parent.width; spacing: units.gu(1); layoutDirection: Qt.RightToLeft
                bottomPadding: units.gu(0.5)

                Rectangle {
                    width: units.gu(14); height: units.gu(5.5)
                    radius: height / 2; color: "#29B6F6"
                    Label {
                        anchors.centerIn: parent; text: i18n.tr("Crear")
                        font.pixelSize: ts(2.1); font.bold: true; color: "#0A0A1A"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            dlg.visible = false
                            var name = aliasField.text.trim()
                            dlg.accepted(name.length > 0 ? name : "Mi vehículo",
                                         dlg.typeList[dlg.typeIdx].value)
                        }
                    }
                }
                Rectangle {
                    visible: !dlg.isFirst
                    width: units.gu(14); height: units.gu(5.5)
                    radius: height / 2; color: "#1E2A3A"
                    border.color: "#90A4AE"; border.width: 1
                    Label {
                        anchors.centerIn: parent; text: i18n.tr("Cancelar")
                        font.pixelSize: ts(2.0); color: "#90A4AE"
                    }
                    MouseArea { anchors.fill: parent; onClicked: { dlg.visible = false; dlg.cancelled() } }
                }
            }
        }
    }
}
