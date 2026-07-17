import QtQuick 2.7
import QtQuick.Controls 2.15

Item {
    id: dlg
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false
    z: 205

    function show() { dlg.visible = true }
    function dismiss() { dlg.visible = false }

    // Fondo oscuro semitransparente
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.75
        MouseArea { anchors.fill: parent; onClicked: dlg.dismiss() }
    }

    // Card
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - units.gu(4), units.gu(48))
        height: aboutCol.implicitHeight + units.gu(5)
        radius: units.gu(1.5)
        color: "#0D1B2A"
        border.color: "#1E3A5F"
        border.width: units.gu(0.1)
        clip: true

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.5)
            color: "#1565C0"
        }

        Column {
            id: aboutCol
            anchors { top: parent.top; left: parent.left; right: parent.right
                      margins: units.gu(2.5); topMargin: units.gu(3) }
            spacing: units.gu(1.8)

            // Logo + nombre
            NaviusLogo {
                anchors.horizontalCenter: parent.horizontalCenter
                size: ts(3.2)
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "v" + ((typeof appVersion !== "undefined") ? appVersion : "?")
                color: "#64B5F6"
                font.pixelSize: ts(1.6)
                font.bold: true
            }

            Rectangle { width: parent.width; height: units.gu(0.05); color: "#1E3A5F" }

            // Servidor oficial
            Column {
                width: parent.width
                spacing: units.gu(0.8)

                Label {
                    text: "🌐  " + i18n.tr("Servidor oficial de rutas")
                    color: "#29B6F6"
                    font.pixelSize: ts(1.8)
                    font.bold: true
                }

                Column {
                    width: parent.width
                    spacing: units.gu(0.5)

                    Label {
                        text: "valhalla.egpsistemas.com"
                        color: "#64B5F6"
                        font.pixelSize: ts(1.7)
                        font.bold: true
                    }

                    Repeater {
                        model: [
                            i18n.tr("• Mapa del planeta completo (OpenStreetMap)"),
                            i18n.tr("• Tráfico predicho por hora y día de la semana"),
                            i18n.tr("• Todos los tipos de vehículo"),
                            i18n.tr("• Rutas alternativas, sin peajes, sin autopistas"),
                            i18n.tr("• Sin límite de uso para usuarios de Navius")
                        ]
                        delegate: Label {
                            width: parent.width
                            text: modelData
                            color: "#CFD8DC"
                            font.pixelSize: ts(1.55)
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: units.gu(0.05); color: "#1E3A5F" }

            // Stack tecnológico
            Column {
                width: parent.width
                spacing: units.gu(0.8)

                Label {
                    text: "⚙️  " + i18n.tr("Tecnología")
                    color: "#29B6F6"
                    font.pixelSize: ts(1.8)
                    font.bold: true
                }

                Repeater {
                    model: [
                        i18n.tr("Interfaz: QML + Lomiri Components"),
                        i18n.tr("Backend: Rust (QObjects)"),
                        i18n.tr("Mapas: MapLibre GL (vectorial)"),
                        i18n.tr("Rutas: Valhalla (motor de routing)"),
                        i18n.tr("GPS: lomiri-location-service (LLS)")
                    ]
                    delegate: Label {
                        width: parent.width
                        text: "• " + modelData
                        color: "#CFD8DC"
                        font.pixelSize: ts(1.55)
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle { width: parent.width; height: units.gu(0.05); color: "#1E3A5F" }

            // Anuncios y financiación
            Rectangle {
                width: parent.width
                color: "#0D1B2A"
                radius: units.gu(0.8)
                height: adSupportCol.implicitHeight + units.gu(2)
                Column {
                    id: adSupportCol
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              margins: units.gu(1) }
                    spacing: units.gu(0.5)
                    Label {
                        width: parent.width
                        text: "📢  " + i18n.tr("Anuncios y apoyo")
                        color: "#29B6F6"
                        font.pixelSize: ts(1.6)
                        font.bold: true
                    }
                    Label {
                        width: parent.width
                        text: i18n.tr("Navius es gratuita y de código abierto. Los anuncios son discretos " +
                                      "— aparecen como carteles en la carretera sin interrumpir la navegación. " +
                                      "Ver un anuncio ya ayuda; hacer click contribuye directamente al " +
                                      "desarrollo de la app. ¡Gracias!")
                        color: "#B0BEC5"
                        font.pixelSize: ts(1.45)
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle { width: parent.width; height: units.gu(0.05); color: "#1E3A5F" }

            // Donación Liberapay
            Column {
                width: parent.width
                spacing: units.gu(1)

                Label {
                    text: "❤️  " + i18n.tr("Apoya el desarrollo")
                    color: "#29B6F6"
                    font.pixelSize: ts(1.8)
                    font.bold: true
                }

                Label {
                    width: parent.width
                    text: i18n.tr("Si Navius te resulta útil, considera hacer una donación para ayudar a mantener los servidores y seguir mejorando la app.")
                    color: "#B0BEC5"
                    font.pixelSize: ts(1.45)
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    width: parent.width
                    height: units.gu(5.5)
                    radius: units.gu(0.9)
                    color: donateMa.pressed ? "#D4A800" : "#F6C915"

                    Row {
                        anchors.centerIn: parent
                        spacing: units.gu(1)
                        Label {
                            text: "♥"
                            color: "#1A1A1A"
                            font.pixelSize: ts(1.8)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: i18n.tr("Donar con Liberapay")
                            color: "#1A1A1A"
                            font.pixelSize: ts(1.8)
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: donateMa
                        anchors.fill: parent
                        onClicked: Qt.openUrlExternally("https://liberapay.com/Navius-GPS/donate")
                    }
                }
            }

            // Licencia y autor
            Column {
                width: parent.width
                spacing: units.gu(0.5)

                Label {
                    width: parent.width
                    text: "Copyright © 2026  Edi"
                    color: "#90A4AE"
                    font.pixelSize: ts(1.55)
                    wrapMode: Text.WordWrap
                }
                Label {
                    width: parent.width
                    text: i18n.tr("Licencia GNU GPL v3. Software libre.")
                    color: "#90A4AE"
                    font.pixelSize: ts(1.45)
                    wrapMode: Text.WordWrap
                }
            }

            // Botón cerrar
            Rectangle {
                width: parent.width
                height: units.gu(5.5)
                radius: units.gu(0.9)
                color: closeMa.pressed ? "#0D47A1" : "#1565C0"

                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Cerrar")
                    color: "white"
                    font.pixelSize: ts(1.8)
                    font.bold: true
                }

                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    onClicked: dlg.dismiss()
                }
            }
        }
    }
}
