import QtQuick 2.7
import QtQuick.Controls 2.15

// Sustituye Lomiri.Components ListItem + ListItemLayout + SlotsLayout,
// fusionados en un solo componente. title/subtitle mantienen la sintaxis de
// grouped properties (title.text/color/font.pixelSize, etc.) porque son
// alias a Label reales. El contenido por defecto (normalmente un único
// Switch) se ancla a la derecha, verticalmente centrado — sustituye a
// `SlotsLayout.position: SlotsLayout.Trailing` (esa línea se elimina en el
// sitio de uso, ya no hace falta).
//
// dividerColor es una propiedad plana (no grouped-property vía QtObject
// alias): el motor QML de Qt5.15 no resuelve en runtime la asignación
// dot-notation "divider.colorFrom"/"divider.colorTo" sobre un alias a un
// QtObject anónimo cuando el componente se carga desde un recurso qrc
// compilado ("Cannot assign to non-existent property"), aunque qmllint no
// lo detecta. En los 21 sitios de uso colorFrom y colorTo eran siempre el
// mismo valor, así que una sola propiedad basta.

Rectangle {
    id: root
    color: _pressed ? highlightColor : bgIdle

    property color bgIdle: "transparent"
    property color highlightColor: "transparent"
    property color dividerColor: "transparent"
    property bool  _pressed: false

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
        color: root.dividerColor
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed:  (mouse) => { root._pressed = true; mouse.accepted = false }
        onReleased: root._pressed = false
        onCanceled: root._pressed = false
    }
}
