import QtQuick 2.7
import QtQuick.Controls 2.15

Rectangle {
    id: root
    visible: hasTrack
    height: ts(5.5)
    color: "#D00F1420"
    radius: height / 2
    border.color: "#2196F3"; border.width: ts(0.15)

    property real   textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }

    property bool   isPlaying: false
    property bool   hasTrack:  false
    property string trackName: ""

    signal playPauseClicked()
    signal nextClicked()
    signal prevClicked()
    signal openRequested()
    signal closeClicked()

    Row {
        id: btnRow
        anchors { left: parent.left; leftMargin: ts(1.5); verticalCenter: parent.verticalCenter }
        spacing: ts(0.8)

        Label {
            text: "⏮"; color: "#78909C"; font.pixelSize: ts(2.4)
            anchors.verticalCenter: parent.verticalCenter
            MouseArea { anchors.fill: parent; onClicked: root.prevClicked() }
        }
        Label {
            text: root.isPlaying ? "⏸" : "▶"
            color: "#2196F3"; font.pixelSize: ts(2.6)
            anchors.verticalCenter: parent.verticalCenter
            MouseArea { anchors.fill: parent; onClicked: root.playPauseClicked() }
        }
        Label {
            text: "⏭"; color: "#78909C"; font.pixelSize: ts(2.4)
            anchors.verticalCenter: parent.verticalCenter
            MouseArea { anchors.fill: parent; onClicked: root.nextClicked() }
        }
    }

    Label {
        id: closeBtn
        anchors { right: parent.right; rightMargin: ts(1.2); verticalCenter: parent.verticalCenter }
        text: "✕"; color: "#546E7A"; font.pixelSize: ts(2.0)
        MouseArea { anchors.fill: parent; anchors.margins: -ts(0.5); onClicked: root.closeClicked() }
    }

    Label {
        anchors {
            left: btnRow.right; leftMargin: ts(1)
            right: closeBtn.left; rightMargin: ts(0.8)
            verticalCenter: parent.verticalCenter
        }
        text: root.trackName
        color: "#B0BEC5"; font.pixelSize: ts(1.7)
        elide: Text.ElideRight
        MouseArea { anchors.fill: parent; onClicked: root.openRequested() }
    }
}
