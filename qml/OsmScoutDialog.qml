import QtQuick 2.7
import QtQuick.Controls 2.15

Item {
    id: dlg
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    visible: false

    signal cancelled()

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: col.implicitHeight + units.gu(2.5)
        color: "#0D1B2A"

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.1); color: "#90A4AE"; opacity: 0.6
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
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OSM Scout Server"
                    color: "white"; font.pixelSize: ts(1.8); font.bold: true
                }
            }

            Label {
                width: parent.width
                text: i18n.tr("Abre OSM Scout Server para usar rutas offline.\nDetectando automáticamente cada 3 s…")
                color: "#B0BEC5"; font.pixelSize: ts(1.55)
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: parent.width; height: units.gu(0.05); color: "#263238"
            }

            Row {
                width: parent.width

                Rectangle {
                    width: parent.width
                    height: units.gu(5); radius: units.gu(0.8)
                    color: cancelArea.pressed ? "#263238" : "#1C2C3C"
                    border.color: "#37474F"; border.width: units.gu(0.1)

                    Label {
                        anchors.centerIn: parent
                        text: i18n.tr("Usar servidor público")
                        color: "#90A4AE"; font.pixelSize: ts(1.6)
                    }

                    MouseArea {
                        id: cancelArea
                        anchors.fill: parent
                        onClicked: dlg.cancelled()
                    }
                }
            }
        }
    }
}
