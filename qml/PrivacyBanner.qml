import QtQuick 2.7
import QtQuick.Controls 2.15
import Qt.labs.settings 1.0

Item {
    id: root
    anchors.fill: parent
    visible: false

    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }

    property bool _consentido: false

    function show() { root.visible = true; root._consentido = false }

    signal accepted()
    signal dismissed()

    // Fondo oscuro
    Rectangle {
        anchors.fill: parent
        color: "#000000"; opacity: 0.65
        MouseArea { anchors.fill: parent }
    }

    // Panel bottom-sheet
    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: privCol.implicitHeight + units.gu(3)
        radius: units.gu(2); color: "#0D1B2A"; border.color: "#1E3A5F"; clip: true

        Flickable {
            anchors { fill: parent; topMargin: units.gu(1.5); bottomMargin: units.gu(1.5) }
            contentHeight: privCol.implicitHeight
            clip: true

            Column {
                id: privCol
                anchors { left: parent.left; right: parent.right; leftMargin: units.gu(2); rightMargin: units.gu(2) }
                spacing: units.gu(1.2)

                // Barra de arrastre
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: units.gu(5); height: units.gu(0.5); radius: height/2; color: "#2A3A4A"
                }

                // Título
                Label {
                    width: parent.width
                    text: i18n.tr("Privacidad y uso de datos")
                    color: "#29B6F6"; font.pixelSize: ts(2.4); font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                // Texto informativo
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#B0BEC5"; font.pixelSize: ts(1.9)
                    text: i18n.tr("Navius puede usarse sin cuenta y sin enviar ningún dato. Si utilizas los servidores públicos de Navius (rutas, mapas, alertas, anuncios), la aplicación enviará datos de posicionamiento al servidor para:")
                }

                // Lista de usos
                Column {
                    width: parent.width; spacing: units.gu(0.6)
                    Repeater {
                        model: [
                            i18n.tr("Calcular rutas y tráfico predictivo (Valhalla)"),
                            i18n.tr("Mostrar alertas comunitarias (accidentes, obras, radares)"),
                            i18n.tr("Mostrar anuncios en ruta según tu ubicación"),
                            i18n.tr("Compartir tu viaje en tiempo real (función opcional)")
                        ]
                        Row {
                            width: parent.width; spacing: units.gu(1)
                            Label { text: "•"; color: "#29B6F6"; font.pixelSize: ts(1.9) }
                            Label {
                                width: parent.width - units.gu(2)
                                text: modelData; color: "#ECEFF1"
                                font.pixelSize: ts(1.9); wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                // Nota sobre alternativa
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#78909C"; font.pixelSize: ts(1.8)
                    text: i18n.tr("Si no deseas compartir datos, puedes usar Navius con OSM Scout Server u otros servidores Valhalla públicos no operados por Navius. Sin aceptar no podrás iniciar sesión ni usar las funciones comunitarias.")
                }

                // Checkbox de consentimiento
                Rectangle {
                    width: parent.width; height: consentRow.implicitHeight + units.gu(1)
                    color: "transparent"
                    Row {
                        id: consentRow
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: units.gu(1.2)
                        Rectangle {
                            width: units.gu(3.2); height: units.gu(3.2); radius: units.gu(0.5)
                            color: root._consentido ? "#1976D2" : "#131F2E"
                            border.color: root._consentido ? "#29B6F6" : "#37474F"; border.width: 1
                            anchors.top: consentLbl.top; anchors.topMargin: units.gu(0.2)
                            Label {
                                anchors.centerIn: parent; text: "✓"; color: "white"
                                font.pixelSize: ts(2.2); visible: root._consentido
                            }
                        }
                        Label {
                            id: consentLbl
                            width: consentRow.width - units.gu(3.2) - units.gu(1.2)
                            text: i18n.tr("Acepto la política de privacidad de Navius y el uso de mis datos de posición para los servicios indicados.")
                            color: "#90A4AE"; font.pixelSize: ts(1.8); wrapMode: Text.WordWrap
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: root._consentido = !root._consentido }
                }

                // Enlace a la política
                Label {
                    text: "<a href='https://www.egpsistemas.com/site/navius/privacidad'>" + i18n.tr("Ver política de privacidad completa") + "</a>"
                    color: "#29B6F6"; font.pixelSize: ts(1.8)
                    anchors.horizontalCenter: parent.horizontalCenter
                    onLinkActivated: Qt.openUrlExternally(link)
                }

                // Botón aceptar
                Rectangle {
                    width: parent.width; height: units.gu(6.5); radius: units.gu(0.8)
                    color: root._consentido ? (acceptMa.pressed ? "#1565C0" : "#1976D2") : "#1A2535"
                    border.color: root._consentido ? "#29B6F6" : "#37474F"
                    opacity: root._consentido ? 1.0 : 0.5
                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Aceptar y continuar")
                        color: "white"; font.pixelSize: ts(2.3); font.bold: true
                    }
                    MouseArea {
                        id: acceptMa; anchors.fill: parent
                        enabled: root._consentido
                        onClicked: { root.visible = false; root.accepted() }
                    }
                }

                // Botón continuar sin aceptar
                Rectangle {
                    width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                    color: dismissMa.pressed ? "#1A2535" : "#1C2D40"; border.color: "#2A4060"
                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Continuar sin aceptar (sin funciones Navius)")
                        color: "#90A4AE"; font.pixelSize: ts(1.9)
                    }
                    MouseArea {
                        id: dismissMa; anchors.fill: parent
                        onClicked: { root.visible = false; root.dismissed() }
                    }
                }

                Item { width: 1; height: units.gu(0.5) }
            }
        }
    }
}
