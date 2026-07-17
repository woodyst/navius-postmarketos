import QtQuick 2.7
import QtQuick.Controls 2.15

Item {
    id: dlg
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    visible: false

    // Nombre del servicio que ha fallado: "Valhalla", "Photon", "Overpass"
    property string serviceName: ""
    // Mensaje descriptivo
    property string message: ""
    // true mientras se detecta OSM Scout
    property bool _detecting: false
    // true si ya confirmamos que OSM Scout no está disponible
    property bool _osmNotFound: false
    // false para servicios donde OSM Scout no es alternativa (Photon)
    property bool showOsmScout: true

    property var _retryFn: null

    signal useOsmScout()
    signal retryRequested()
    signal cancelled()

    onRetryRequested: { if (_retryFn) _retryFn() }

    function open(service, msg) {
        serviceName = service
        message = msg
        _detecting = false
        _osmNotFound = false
        visible = true
    }

    // Fondo semitransparente que bloquea interacción con el mapa
    Rectangle {
        anchors.fill: parent
        color: "#80000000"
        MouseArea { anchors.fill: parent }  // absorbe toques
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: col.implicitHeight + units.gu(2.5)
        color: "#0D1B2A"

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.1); color: "#EF9A9A"; opacity: 0.8
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
                Label { anchors.verticalCenter: parent.verticalCenter; text: "⚠"; font.pixelSize: ts(2.2); color: "#EF9A9A" }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: dlg.serviceName + " " + i18n.tr("no disponible")
                    color: "white"; font.pixelSize: ts(1.8); font.bold: true
                }
            }

            Label {
                width: parent.width
                text: dlg.message || i18n.tr("El servidor no ha respondido en el tiempo esperado.")
                color: "#B0BEC5"; font.pixelSize: ts(1.55)
                wrapMode: Text.WordWrap
            }

            Label {
                width: parent.width
                visible: dlg._osmNotFound
                text: i18n.tr("OSM Scout Server no detectado. Instálalo desde la OpenStore para usar mapas y rutas offline.")
                color: "#EF9A9A"; font.pixelSize: ts(1.4)
                wrapMode: Text.WordWrap
            }

            Rectangle { width: parent.width; height: units.gu(0.05); color: "#263238" }

            // Botón principal: Usar OSM Scout
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                visible: dlg.showOsmScout
                color: osmArea.pressed ? "#1565C0" : "#1976D2"
                opacity: dlg._detecting ? 0.6 : 1.0

                Row {
                    anchors.centerIn: parent
                    spacing: units.gu(0.8)
                    BusyIndicator {
                        anchors.verticalCenter: parent.verticalCenter
                        running: dlg._detecting
                        visible: dlg._detecting
                        implicitWidth: ts(1.8); implicitHeight: ts(1.8)
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dlg._detecting ? i18n.tr("Detectando OSM Scout…") : i18n.tr("Usar OSM Scout Server")
                        color: "white"; font.pixelSize: ts(1.7); font.bold: true
                    }
                }
                MouseArea {
                    id: osmArea
                    anchors.fill: parent
                    enabled: !dlg._detecting
                    onClicked: dlg.useOsmScout()
                }
            }

            // Botón secundario: Reintentar
            Rectangle {
                width: parent.width; height: units.gu(5); radius: units.gu(0.8)
                color: retryArea.pressed ? "#1C3C1C" : "#1B3A1B"
                border.color: "#4CAF50"; border.width: units.gu(0.1)
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Reintentar")
                    color: "#81C784"; font.pixelSize: ts(1.65); font.bold: true
                }
                MouseArea {
                    id: retryArea
                    anchors.fill: parent
                    onClicked: { dlg.visible = false; dlg.retryRequested() }
                }
            }

            // Botón terciario: Cancelar
            Rectangle {
                width: parent.width; height: units.gu(4.5); radius: units.gu(0.8)
                color: cancelArea.pressed ? "#1C2C3C" : "#263238"
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Cancelar")
                    color: "#90A4AE"; font.pixelSize: ts(1.6)
                }
                MouseArea {
                    id: cancelArea
                    anchors.fill: parent
                    onClicked: { dlg.visible = false; dlg.cancelled() }
                }
            }
        }
    }
}
