import QtQuick 2.7
import QtQuick.Controls 2.15

// Diálogo: navegar al vehículo aparcado.
// Uso: parkingDialog.openNavigate()
// Señal: navigateRequested(destLat, destLon, costing)

Item {
    id: dlg
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false
    z: 210

    signal navigateRequested(real destLat, real destLon, string costing)

    property var _vehicles: []    // vehículos con aparcamiento guardado
    property int _selIdx:  0      // índice seleccionado en _vehicles
    property bool _onFoot: true   // true = a pie, false = en el vehículo seleccionado

    function openNavigate() {
        _vehicles = vehicleManager.vehiclesWithParking().filter(function(v) { return v.costing !== "pedestrian" })
        if (_vehicles.length === 0) return
        // Pre-seleccionar vehículo activo si tiene parking
        var av = vehicleManager.activeVehicle()
        _selIdx = 0
        if (av) {
            for (var i = 0; i < _vehicles.length; i++) {
                if (_vehicles[i].id === av.id) { _selIdx = i; break }
            }
        }
        _onFoot = true
        visible = true
    }

    readonly property var _selVehicle: _vehicles.length > 0 ? _vehicles[_selIdx] : null

    // Fondo
    Rectangle {
        anchors.fill: parent
        color: "#BB000010"
        MouseArea { anchors.fill: parent }
    }

    // Tarjeta
    Rectangle {
        anchors.centerIn: parent
        width:  Math.min(parent.width * 0.92, units.gu(46))
        height: colDlg.implicitHeight + units.gu(4)
        color: "#1A1A2E"; radius: units.gu(1.5)
        border.color: "#4CAF50"; border.width: 1

        Column {
            id: colDlg
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
            spacing: units.gu(1.4)

            // Título
            Label {
                text: "🅿 " + i18n.tr("Ir al aparcamiento")
                font.pixelSize: ts(2.6); font.bold: true; color: "#4CAF50"
            }
            Label {
                visible: dlg._selVehicle !== null
                text: dlg._selVehicle ? (i18n.tr("Vehículo: ") + dlg._selVehicle.alias) : ""
                color: "#B0BEC5"; font.pixelSize: ts(2.0)
            }

            // Selector de vehículo (solo si hay más de uno con parking)
            Column {
                visible: dlg._vehicles.length > 1
                width: parent.width; spacing: units.gu(0.5)
                Label { text: i18n.tr("Vehículo aparcado"); color: "#90A4AE"; font.pixelSize: ts(1.8) }
                Repeater {
                    model: dlg._vehicles
                    Rectangle {
                        width: parent.width; height: units.gu(5.5)
                        radius: units.gu(0.6)
                        color: dlg._selIdx === index ? "#1B3A1B" : "#1E2A2E"
                        border.color: dlg._selIdx === index ? "#4CAF50" : "#37474F"; border.width: 1
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(1.5) }
                            spacing: units.gu(1)
                            Label {
                                text: dlg._selIdx === index ? "●" : "○"
                                color: "#4CAF50"; font.pixelSize: ts(2.2)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Label {
                                text: modelData.alias + " (" + vehicleManager.costingLabel(modelData.costing) + ")"
                                color: "#ECEFF1"; font.pixelSize: ts(1.9)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: dlg._selIdx = index }
                    }
                }
            }

            // Modo de desplazamiento
            Label { text: i18n.tr("Modo de desplazamiento"); color: "#90A4AE"; font.pixelSize: ts(1.8) }
            Row {
                width: parent.width; spacing: units.gu(1)
                Rectangle {
                    width: (parent.width - units.gu(1)) / 2; height: units.gu(5.5)
                    radius: height / 2
                    color: dlg._onFoot ? "#29B6F6" : "#1E2A3A"
                    border.color: "#29B6F6"; border.width: 1
                    Label {
                        anchors.centerIn: parent; text: "🚶 " + i18n.tr("A pie")
                        color: dlg._onFoot ? "#0A0A1A" : "#90A4AE"
                        font.pixelSize: ts(2.0); font.bold: dlg._onFoot
                    }
                    MouseArea { anchors.fill: parent; onClicked: dlg._onFoot = true }
                }
                Rectangle {
                    width: (parent.width - units.gu(1)) / 2; height: units.gu(5.5)
                    radius: height / 2
                    color: !dlg._onFoot ? "#4CAF50" : "#1E2A3A"
                    border.color: "#4CAF50"; border.width: 1
                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("En ") + (dlg._selVehicle ? vehicleManager.costingLabel(dlg._selVehicle.costing) : i18n.tr("vehículo"))
                        color: !dlg._onFoot ? "#0A0A1A" : "#90A4AE"
                        font.pixelSize: ts(2.0); font.bold: !dlg._onFoot
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: if (dlg._selVehicle) dlg._onFoot = false
                    }
                }
            }

            // Botones acción
            Row {
                width: parent.width; spacing: units.gu(1)
                bottomPadding: units.gu(0.5)

                Rectangle {
                    width: (parent.width - units.gu(2)) / 3 * 2; height: units.gu(5.5)
                    radius: height / 2; color: "#4CAF50"
                    Label {
                        anchors.centerIn: parent; text: i18n.tr("Navegar")
                        font.pixelSize: ts(2.1); font.bold: true; color: "#0A0A1A"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (!dlg._selVehicle) return
                            var costing = dlg._onFoot ? "pedestrian" : dlg._selVehicle.costing
                            dlg.visible = false
                            dlg.navigateRequested(dlg._selVehicle.parkLat, dlg._selVehicle.parkLon, costing)
                        }
                    }
                }
                Rectangle {
                    width: (parent.width - units.gu(2)) / 3; height: units.gu(5.5)
                    radius: height / 2; color: "#1E2A3A"
                    border.color: "#90A4AE"; border.width: 1
                    Label {
                        anchors.centerIn: parent; text: i18n.tr("Cerrar")
                        font.pixelSize: ts(2.0); color: "#90A4AE"
                    }
                    MouseArea { anchors.fill: parent; onClicked: dlg.visible = false }
                }
            }
        }
    }
}
