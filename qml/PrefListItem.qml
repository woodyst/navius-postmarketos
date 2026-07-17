import QtQuick 2.7
import QtQuick.Controls 2.15

// Sustituye Lomiri.Components ListItem + ListItemLayout + SlotsLayout,
// fusionados en un solo componente. Mantiene la misma sintaxis de
// "grouped properties" (divider.colorFrom/colorTo, title.text/color/
// font.pixelSize, subtitle.text/color/font.pixelSize/wrapMode) que los
// sitios de uso en PreferencesPanel.qml ya tenían, para minimizar el
// tamaño del diff al portarlos. El contenido por defecto (normalmente un
// único Switch) se ancla a la derecha, verticalmente centrado — sustituye
// a `SlotsLayout.position: SlotsLayout.Trailing` (esa línea se elimina en
// el sitio de uso, ya no hace falta).

Rectangle {
    id: root
    color: _pressed ? highlightColor : bgIdle

    property color bgIdle: "transparent"
    property color highlightColor: "transparent"
    property bool  _pressed: false

    QtObject {
        id: dividerObj
        property color colorFrom: "transparent"
        property color colorTo: "transparent"
    }
    property alias divider: dividerObj

    property alias title:    titleLabel
    property alias subtitle: subtitleLabel

    default property alias content: trailingRow.data

    implicitHeight: Math.max(contentCol.implicitHeight + 16, trailingRow.implicitHeight) + 16

    Column {
        id: contentCol
        anchors { left: parent.left; right: trailingRow.left; verticalCenter: parent.verticalCenter }
        anchors.leftMargin: 16
        anchors.rightMargin: 8
        spacing: 2

        Label { id: titleLabel;    width: parent.width }
        Label { id: subtitleLabel; width: parent.width; visible: text.length > 0 }
    }

    Row {
        id: trailingRow
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: dividerObj.colorFrom
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed:  (mouse) => { root._pressed = true; mouse.accepted = false }
        onReleased: root._pressed = false
        onCanceled: root._pressed = false
    }
}
