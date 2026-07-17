import QtQuick 2.7
import QtQuick.Controls 2.15

Item {
    id: root
    anchors.fill: parent
    visible: false
    z: 200

    property real   textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }

    property string shareUrl:  ""
    property bool   creating:  false
    property bool   active:    false
    property string errorMsg:  ""

    signal createRequested()
    signal stopRequested()
    signal dismissed()

    // Fondo oscuro — sin MouseArea para no cerrar al tocar
    Rectangle {
        anchors.fill: parent
        color: "#80000000"
    }

    // Panel inferior
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: col.implicitHeight + units.gu(4)
        color:  "#EE07111E"

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.12)
            color:  root.active ? "#FF5252" : "#29B6F6"
            opacity: 0.6
        }

        Column {
            id: col
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: units.gu(2); rightMargin: units.gu(2); topMargin: units.gu(2)
            }
            spacing: units.gu(1.2)

            // Título
            Label {
                text: root.active   ? i18n.tr("🔴 Compartiendo viaje")
                    : root.creating ? i18n.tr("Generando enlace…")
                    :                 i18n.tr("Compartir viaje")
                color: root.active ? "#FF5252" : "white"
                font.pixelSize: ts(2); font.bold: true
            }

            // Descripción (solo antes de activar)
            Label {
                visible: !root.active && !root.creating
                text: i18n.tr("Genera un enlace para que otros puedan seguir tu posición y ruta en tiempo real desde cualquier navegador.")
                color: "#90A4AE"; font.pixelSize: ts(1.5)
                wrapMode: Text.WordWrap; width: parent.width
            }

            // Error
            Label {
                visible: root.errorMsg !== "" && !root.creating && !root.active
                text: "⚠ " + root.errorMsg
                color: "#FF5252"; font.pixelSize: ts(1.45)
                wrapMode: Text.WordWrap; width: parent.width
            }

            // URL + botón Copiar (cuando activo)
            Row {
                visible: root.active
                width: parent.width; spacing: units.gu(1)

                Rectangle {
                    width: parent.width - copyBtn.width - units.gu(1)
                    height: units.gu(5.5)
                    color: "#1C2A3A"; radius: units.gu(0.6)
                    border { color: "#29B6F6"; width: units.gu(0.12) }

                    TextInput {
                        id: urlInput
                        anchors {
                            fill: parent
                            leftMargin: units.gu(1.2); rightMargin: units.gu(1.2)
                            topMargin: units.gu(1.2); bottomMargin: units.gu(1.2)
                        }
                        text: root.shareUrl
                        readOnly: true; selectByMouse: true; clip: true
                        color: "#29B6F6"
                        font.pixelSize: ts(1.35); font.family: "Ubuntu Mono"
                    }
                }

                // Botón Copiar
                Rectangle {
                    id: copyBtn
                    width: units.gu(10); height: units.gu(5.5)
                    radius: units.gu(0.6)
                    color: copyArea.pressed ? "#1E3A5F" : "#1C2A3A"
                    border { color: _copied ? "#66BB6A" : "#29B6F6"; width: units.gu(0.15) }

                    property bool _copied: false

                    Label {
                        anchors.centerIn: parent
                        text: parent._copied ? i18n.tr("✓ Copiado") : i18n.tr("Copiar")
                        color: parent._copied ? "#66BB6A" : "#29B6F6"
                        font.pixelSize: ts(1.4); font.bold: true
                    }

                    Timer {
                        id: copyFeedbackTimer
                        interval: 2000
                        onTriggered: copyBtn._copied = false
                    }

                    MouseArea {
                        id: copyArea; anchors.fill: parent
                        onClicked: {
                            urlInput.selectAll()
                            urlInput.copy()
                            copyBtn._copied = true
                            copyFeedbackTimer.restart()
                        }
                    }
                }
            }

            // Botones principales
            Row {
                width: parent.width; spacing: units.gu(1.2)

                Rectangle {
                    width: root.active ? parent.width * 0.57 - units.gu(0.6) : parent.width
                    height: units.gu(6.5); radius: units.gu(0.8)
                    color:  createArea.pressed ? "#1E3A5F" : "#1C1C2E"
                    border { color: root.creating ? "#546E7A" : "#29B6F6"; width: units.gu(0.15) }
                    opacity: root.creating ? 0.6 : 1.0

                    Label {
                        anchors.centerIn: parent
                        text: root.creating ? i18n.tr("Generando…")
                            : root.active   ? i18n.tr("Abrir en navegador")
                            :                 i18n.tr("Crear enlace")
                        color: root.creating ? "#546E7A" : "#29B6F6"
                        font.pixelSize: ts(1.6); font.bold: !root.creating
                    }
                    MouseArea {
                        id: createArea; anchors.fill: parent
                        enabled: !root.creating
                        onClicked: {
                            if (root.active) Qt.openUrlExternally(root.shareUrl)
                            else root.createRequested()
                        }
                    }
                }

                Rectangle {
                    visible: root.active
                    width: parent.width * 0.43 - units.gu(0.6)
                    height: units.gu(6.5); radius: units.gu(0.8)
                    color:  stopArea.pressed ? "#4A0000" : "#2A0000"
                    border { color: "#FF5252"; width: units.gu(0.15) }

                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Detener"); color: "#FF5252"
                        font.pixelSize: ts(1.6); font.bold: true
                    }
                    MouseArea {
                        id: stopArea; anchors.fill: parent
                        onClicked: root.stopRequested()
                    }
                }
            }

            // Cerrar — único punto de salida
            Rectangle {
                width: parent.width; height: units.gu(5.5); color: "transparent"
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Cerrar"); color: "#B0BEC5"; font.pixelSize: ts(1.5)
                }
                MouseArea { anchors.fill: parent; onClicked: root.dismissed() }
            }
        }
    }
}
