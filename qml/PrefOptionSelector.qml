import QtQuick 2.7

// Sustituye Lomiri.Components OptionSelector (single-selection, modelo de
// strings) usado en PreferencesPanel.qml. Misma API mínima: model,
// selectedIndex (+ onSelectedIndexChanged), containerHeight, width.
Column {
    id: root

    property var model: []
    property int selectedIndex: 0
    property real containerHeight: 0

    property color bgColor:        "#222222"
    property color bgSelectedColor: "#2196F3"
    property color textColor:      "white"
    property real  fontSize:       16

    height: containerHeight

    Repeater {
        model: root.model
        delegate: Rectangle {
            width: root.width
            height: root.containerHeight / Math.max(root.model.length, 1)
            color: index === root.selectedIndex ? root.bgSelectedColor : root.bgColor
            border.color: root.bgSelectedColor
            border.width: index === root.selectedIndex ? 1 : 0

            Text {
                anchors.centerIn: parent
                text: modelData
                color: root.textColor
                font.pixelSize: root.fontSize
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.selectedIndex = index
            }
        }
    }
}
