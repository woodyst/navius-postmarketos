import QtQuick 2.7

// Sustituye Lomiri.Components Icon{} para los 2 únicos nombres usados en
// PreferencesPanel.qml ("go-up"/"go-down"): un simple glifo unicode, sin
// depender de un theme de iconos del sistema.
Item {
    property string name: ""
    property color  color: "black"

    Text {
        anchors.centerIn: parent
        text: name === "go-up" ? "▲" : "▼"
        color: parent.color
        font.pixelSize: Math.round(Math.min(parent.width, parent.height) * 0.6)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
