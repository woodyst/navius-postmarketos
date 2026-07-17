import QtQuick 2.7
import Qt.labs.settings 1.0
import QtQuick.Controls 2.15

Item {
    id: wnd
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false
    z: 200

    property bool showAtStartup: true

    // Actualizar en cada deploy (formato: YYYY-MM-DD HH:mm:ss)
    readonly property string currentVersion: "2026-05-02 12:09:00"

    readonly property var changelog: [
        {
            date:    "2 mayo 2026 · 12:09",
            changes: [
                { icon: "📍", text: i18n.tr("Búsqueda de puntos de interés cerca de ti: gasolineras, parking, restaurantes, hoteles y más") },
                { icon: "🚦", text: i18n.tr("Detección automática de rutas más rápidas por tráfico durante la navegación") },
                { icon: "🗑",  text: i18n.tr("Opción para limpiar caché de Google Maps en el menú de Ajustes") },
                { icon: "🔔", text: i18n.tr("Pantalla de novedades al iniciar con opción para desactivarla en Ajustes") }
            ]
        }
    ]

    Settings {
        id: wndSettings
        category: "whatsNew"
        property string lastSeenVersion: ""
    }

    function checkShowAtStartup() {
        if (wnd.showAtStartup && wndSettings.lastSeenVersion !== currentVersion)
            wnd.visible = true
    }

    function show() { wnd.visible = true }

    function dismiss() {
        wndSettings.lastSeenVersion = currentVersion
        wnd.visible = false
    }

    // Fondo oscuro semitransparente
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.72
        MouseArea { anchors.fill: parent }
    }

    // Card centrado
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - units.gu(6), units.gu(44))
        height: cardCol.implicitHeight + units.gu(5)
        radius: units.gu(1.5)
        color: "#0D1B2A"
        border.color: "#1E3A5F"
        border.width: units.gu(0.1)

        // Franja de color superior (sin gradient para compat Qt5)
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.4)
            radius: parent.radius
            color: "#1565C0"
        }

        Column {
            id: cardCol
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                margins: units.gu(2.5)
                topMargin: units.gu(3)
            }
            spacing: units.gu(2)

            // Cabecera
            Column {
                width: parent.width
                spacing: units.gu(0.6)

                Label {
                    text: "🚀  " + i18n.tr("Novedades")
                    color: "white"
                    font.pixelSize: ts(2.4)
                    font.bold: true
                }

                Rectangle {
                    height: units.gu(2.4)
                    width: verLabel.implicitWidth + units.gu(2)
                    radius: units.gu(0.5)
                    color: "#1565C0"
                    Label {
                        id: verLabel
                        anchors.centerIn: parent
                        text: changelog[0].date
                        color: "#90CAF9"
                        font.pixelSize: ts(1.3)
                    }
                }
            }

            Rectangle { width: parent.width; height: units.gu(0.05); color: "#1E3A5F" }

            // Lista de cambios
            Column {
                width: parent.width
                spacing: units.gu(1.4)

                Repeater {
                    model: changelog[0].changes
                    delegate: Row {
                        width: parent.width
                        spacing: units.gu(1.2)

                        Label {
                            text: modelData.icon
                            font.pixelSize: ts(2)
                            anchors.top: parent.top
                        }

                        Label {
                            text: modelData.text
                            color: "#CFD8DC"
                            font.pixelSize: ts(1.55)
                            wrapMode: Text.WordWrap
                            width: parent.width - units.gu(3.2)
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: units.gu(0.05); color: "#1E3A5F" }

            Rectangle {
                width: parent.width
                height: units.gu(5.5)
                radius: units.gu(0.9)
                color: okArea.pressed ? "#0D47A1" : "#1565C0"

                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Entendido")
                    color: "white"
                    font.pixelSize: ts(1.8)
                    font.bold: true
                }

                MouseArea {
                    id: okArea
                    anchors.fill: parent
                    onClicked: wnd.dismiss()
                }
            }
        }
    }
}
