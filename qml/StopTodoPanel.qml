import QtQuick 2.7
import QtQuick.Controls 2.15
import QtQuick.LocalStorage 2.0
import "TodoDB.js" as TodoDB

Rectangle {
    id: panel
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    z: 55
    color: "#07111E"
    visible: false

    property var navWaypoints: []
    property int _highlightIdx: -1
    property bool _showHistory: false
    property var  _histGroups:  []

    signal closed()
    signal todoToggled(int wpIdx, int todoIdx, bool done)
    signal todoDeleted(int wpIdx, int todoIdx)
    signal todoRenamed(int wpIdx, int todoIdx, string newText)

    function _refreshHistory() { _histGroups = TodoDB.loadAllDestGroups() }

    function openAtWaypoint(idx) {
        _highlightIdx = idx
        visible = true
        if (idx >= 0)
            Qt.callLater(function() { wpList.positionViewAtIndex(idx, ListView.Beginning) })
    }

    function _pendingCount(todos) {
        var c = 0
        for (var i = 0; i < todos.length; i++) if (!todos[i].done) c++
        return c
    }

    function _doneCount(todos) {
        var c = 0
        for (var i = 0; i < todos.length; i++) if (todos[i].done) c++
        return c
    }

    // ── Header ────────────────────────────────────────────────────────────
    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(7)
        color: "#0D1B2A"

        Label {
            anchors.centerIn: parent
            text: panel._showHistory ? i18n.tr("Historial de tareas") : i18n.tr("Lista de tareas")
            color: "white"; font.pixelSize: ts(2.2); font.bold: true
        }

        Rectangle {
            anchors { left: parent.left; leftMargin: units.gu(1.5)
                      verticalCenter: parent.verticalCenter }
            width: units.gu(4.5); height: units.gu(4.5); radius: width / 2
            color: histBtn.pressed ? "#1E3A5F" : (panel._showHistory ? "#1E3A5F" : "#1E2A3A")
            Label { anchors.centerIn: parent; text: "📚"; font.pixelSize: ts(2) }
            MouseArea {
                id: histBtn; anchors.fill: parent
                onClicked: {
                    panel._showHistory = !panel._showHistory
                    if (panel._showHistory) panel._refreshHistory()
                }
            }
        }

        Rectangle {
            anchors { right: parent.right; rightMargin: units.gu(1.5)
                      verticalCenter: parent.verticalCenter }
            width: units.gu(4.5); height: units.gu(4.5); radius: width / 2
            color: "#1E2A3A"
            Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: ts(2.2) }
            MouseArea { anchors.fill: parent; onClicked: panel.closed() }
        }

        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1; color: "#1E2A3A"
        }
    }

    // ── Empty state (solo en vista normal) ────────────────────────────────
    Label {
        anchors.centerIn: parent
        visible: !panel._showHistory && panel.navWaypoints.length === 0
        text: i18n.tr("No hay destinos en la ruta")
        color: "#B0BEC5"; font.pixelSize: ts(1.9)
    }

    // ── Waypoints list ─────────────────────────────────────────────────────
    ListView {
        id: wpList
        visible: !panel._showHistory
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: panel.navWaypoints
        spacing: 0

        delegate: Column {
            id: wpDelegate
            width: wpList.width
            property int  _wpIdx: index
            property var  _wp:    modelData
            property var  _todos: _wp && _wp.todos ? _wp.todos : []
            property bool _isHL:  panel._highlightIdx === _wpIdx

            // ── Destination header ───────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(5.5)
                color: wpDelegate._isHL ? "#0D2244" : "#0A1929"

                Label {
                    id: destIcon
                    anchors { left: parent.left; leftMargin: units.gu(1.5)
                              verticalCenter: parent.verticalCenter }
                    text: "🏁"; font.pixelSize: ts(2.2)
                }
                Label {
                    anchors { left: destIcon.right; leftMargin: units.gu(0.8)
                              right: parent.right; rightMargin: units.gu(1.5)
                              verticalCenter: parent.verticalCenter }
                    text: wpDelegate._wp
                          ? (wpDelegate._wp.name || i18n.tr("Destino %1").arg(wpDelegate._wpIdx + 1))
                          : ""
                    color: wpDelegate._isHL ? "#29B6F6" : "#90A4AE"
                    font.pixelSize: ts(1.9); font.bold: true; elide: Text.ElideRight
                }
                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 1; color: "#1E2A3A"
                }
            }

            // ── No tasks ─────────────────────────────────────────────────
            Rectangle {
                visible: wpDelegate._todos.length === 0
                width: parent.width; height: units.gu(4.5)
                color: "#060E16"
                Label {
                    anchors { left: parent.left; leftMargin: units.gu(4)
                              verticalCenter: parent.verticalCenter }
                    text: i18n.tr("Sin tareas"); color: "#B0BEC5"; font.pixelSize: ts(1.7)
                }
            }

            // ── Pendientes header ─────────────────────────────────────────
            Rectangle {
                visible: panel._pendingCount(wpDelegate._todos) > 0
                width: parent.width; height: units.gu(3.5)
                color: "#0A1929"
                Label {
                    anchors { left: parent.left; leftMargin: units.gu(2)
                              verticalCenter: parent.verticalCenter }
                    text: "📋 " + i18n.tr("Pendientes")
                    color: "#90A4AE"; font.pixelSize: ts(1.5); font.bold: true
                }
            }

            Repeater {
                model: wpDelegate._todos
                delegate: Rectangle {
                    id: pendRow
                    width: wpList.width
                    visible: !modelData.done
                    height: units.gu(5.5)
                    color: "#081420"
                    clip: true

                    property int    _tIdx:     index
                    property int    _wIdx:     wpDelegate._wpIdx
                    property bool   _editing:  false
                    property string _editText: modelData.text

                    // ── Vista normal ─────────────────────────────
                    Item {
                        visible: !pendRow._editing
                        anchors.fill: parent

                        Label {
                            id: pendChk
                            anchors { left: parent.left; leftMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                            text: "☐"; color: "#90A4AE"; font.pixelSize: ts(2.4)
                        }
                        Rectangle {
                            id: pendDel
                            anchors { right: parent.right; rightMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                            width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                            color: pendDelMa.pressed ? "#3E2121" : "#1E2A3A"
                            Label { anchors.centerIn: parent; text: "✕"; color: "#FF5252"; font.pixelSize: ts(1.8) }
                            MouseArea { id: pendDelMa; anchors.fill: parent; onClicked: panel.todoDeleted(pendRow._wIdx, pendRow._tIdx) }
                        }
                        Rectangle {
                            id: pendEdit
                            anchors { right: pendDel.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                            color: pendEditMa.pressed ? "#1A3040" : "#1E2A3A"
                            Label { anchors.centerIn: parent; text: "✎"; color: "#B0BEC5"; font.pixelSize: ts(1.6) }
                            MouseArea { id: pendEditMa; anchors.fill: parent; onClicked: { pendRow._editText = modelData.text; pendRow._editing = true } }
                        }
                        Label {
                            anchors { left: pendChk.right; leftMargin: units.gu(1); right: pendEdit.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            text: modelData.text; color: "#B0BEC5"; font.pixelSize: ts(1.8); elide: Text.ElideRight
                        }
                        MouseArea {
                            id: pendTgl
                            anchors { fill: parent; rightMargin: units.gu(9.5) }
                            onClicked: panel.todoToggled(pendRow._wIdx, pendRow._tIdx, true)
                        }
                    }

                    // ── Modo edición ─────────────────────────────
                    Item {
                        visible: pendRow._editing
                        anchors.fill: parent

                        Rectangle {
                            id: pConfirm
                            anchors { right: parent.right; rightMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                            width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                            color: pConfirmMa.pressed ? "#1B5E20" : "#2E7D32"
                            Label { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                            function doConfirm() {
                                var t = pendRow._editText.trim()
                                if (t.length > 0) panel.todoRenamed(pendRow._wIdx, pendRow._tIdx, t)
                                pendRow._editing = false
                            }
                            MouseArea { id: pConfirmMa; anchors.fill: parent; onClicked: pConfirm.doConfirm() }
                        }
                        Rectangle {
                            id: pCancelBtn
                            anchors { right: pConfirm.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                            color: pCancelMa.pressed ? "#3E2121" : "#1E2A3A"
                            Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.6) }
                            MouseArea { id: pCancelMa; anchors.fill: parent; onClicked: pendRow._editing = false }
                        }
                        Item {
                            anchors { left: parent.left; leftMargin: units.gu(2); right: pCancelBtn.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            height: units.gu(3.5)
                            Rectangle { anchors.fill: parent; color: "#0D1B2A"; radius: units.gu(0.3) }
                            TextInput {
                                anchors { left: parent.left; leftMargin: units.gu(0.5); right: parent.right; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                                text: pendRow._editText
                                onTextChanged: pendRow._editText = text
                                color: "#ECEFF1"; font.pixelSize: ts(1.8)
                                onAccepted: pConfirm.doConfirm()
                            }
                        }
                    }

                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(2) }
                        height: 1; color: "#1E2A3A"
                    }
                }
            }

            // ── Completadas header ────────────────────────────────────────
            Rectangle {
                visible: panel._doneCount(wpDelegate._todos) > 0
                width: parent.width; height: units.gu(3.5)
                color: "#0A1929"
                Label {
                    anchors { left: parent.left; leftMargin: units.gu(2)
                              verticalCenter: parent.verticalCenter }
                    text: "✅ " + i18n.tr("Completadas")
                    color: "#90A4AE"; font.pixelSize: ts(1.5); font.bold: true
                }
            }

            Repeater {
                model: wpDelegate._todos
                delegate: Rectangle {
                    id: doneRow
                    width: wpList.width
                    visible: modelData.done
                    height: units.gu(5.5)
                    color: "#060E16"
                    clip: true

                    property int    _tIdx:     index
                    property int    _wIdx:     wpDelegate._wpIdx
                    property bool   _editing:  false
                    property string _editText: modelData.text

                    // ── Vista normal ─────────────────────────────
                    Item {
                        visible: !doneRow._editing
                        anchors.fill: parent

                        Label {
                            id: doneChk
                            anchors { left: parent.left; leftMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                            text: "☑"; color: "#29B6F6"; font.pixelSize: ts(2.4)
                        }
                        Rectangle {
                            id: doneDel
                            anchors { right: parent.right; rightMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                            width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                            color: doneDelMa.pressed ? "#3E2121" : "#1E2A3A"
                            Label { anchors.centerIn: parent; text: "✕"; color: "#FF5252"; font.pixelSize: ts(1.8) }
                            MouseArea { id: doneDelMa; anchors.fill: parent; onClicked: panel.todoDeleted(doneRow._wIdx, doneRow._tIdx) }
                        }
                        Rectangle {
                            id: doneEdit
                            anchors { right: doneDel.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                            color: doneEditMa.pressed ? "#1A3040" : "#1E2A3A"
                            Label { anchors.centerIn: parent; text: "✎"; color: "#90A4AE"; font.pixelSize: ts(1.6) }
                            MouseArea { id: doneEditMa; anchors.fill: parent; onClicked: { doneRow._editText = modelData.text; doneRow._editing = true } }
                        }
                        Label {
                            anchors { left: doneChk.right; leftMargin: units.gu(1); right: doneEdit.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            text: modelData.text; color: "#607D8B"; font.pixelSize: ts(1.8)
                            font.strikeout: true; elide: Text.ElideRight
                        }
                        MouseArea {
                            id: doneTgl
                            anchors { fill: parent; rightMargin: units.gu(9.5) }
                            onClicked: panel.todoToggled(doneRow._wIdx, doneRow._tIdx, false)
                        }
                    }

                    // ── Modo edición ─────────────────────────────
                    Item {
                        visible: doneRow._editing
                        anchors.fill: parent

                        Rectangle {
                            id: dConfirm
                            anchors { right: parent.right; rightMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                            width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                            color: dConfirmMa.pressed ? "#1B5E20" : "#2E7D32"
                            Label { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                            function doConfirm() {
                                var t = doneRow._editText.trim()
                                if (t.length > 0) panel.todoRenamed(doneRow._wIdx, doneRow._tIdx, t)
                                doneRow._editing = false
                            }
                            MouseArea { id: dConfirmMa; anchors.fill: parent; onClicked: dConfirm.doConfirm() }
                        }
                        Rectangle {
                            id: dCancelBtn
                            anchors { right: dConfirm.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                            color: dCancelMa.pressed ? "#3E2121" : "#1E2A3A"
                            Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.6) }
                            MouseArea { id: dCancelMa; anchors.fill: parent; onClicked: doneRow._editing = false }
                        }
                        Item {
                            anchors { left: parent.left; leftMargin: units.gu(2); right: dCancelBtn.left; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                            height: units.gu(3.5)
                            Rectangle { anchors.fill: parent; color: "#0D1B2A"; radius: units.gu(0.3) }
                            TextInput {
                                anchors { left: parent.left; leftMargin: units.gu(0.5); right: parent.right; rightMargin: units.gu(0.5); verticalCenter: parent.verticalCenter }
                                text: doneRow._editText
                                onTextChanged: doneRow._editText = text
                                color: "#ECEFF1"; font.pixelSize: ts(1.8)
                                onAccepted: dConfirm.doConfirm()
                            }
                        }
                    }

                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(2) }
                        height: 1; color: "#1E2A3A"
                    }
                }
            }

            // ── Bottom spacing ─────────────────────────────────────────────
            Rectangle {
                visible: wpDelegate._todos.length > 0
                width: parent.width; height: units.gu(0.8)
                color: "#0A1929"
            }
        }
    }

    // ── Historial de tareas ────────────────────────────────────────────────
    ListView {
        id: histList
        visible: panel._showHistory
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: panel._histGroups
        spacing: 0

        Label {
            anchors.centerIn: parent
            visible: panel._histGroups.length === 0
            text: i18n.tr("Sin historial de tareas")
            color: "#B0BEC5"; font.pixelSize: ts(1.9)
        }

        delegate: Column {
            id: histDelegate
            width: histList.width
            property var _grp: modelData

            // Cabecera del grupo (dest + fecha)
            Rectangle {
                width: parent.width; height: units.gu(6)
                color: "#0A1929"
                Row {
                    anchors { left: parent.left; leftMargin: units.gu(1.5)
                              right: delGrpBtn.left; rightMargin: units.gu(1)
                              verticalCenter: parent.verticalCenter }
                    spacing: units.gu(0.8)
                    Label { text: "🏁"; font.pixelSize: ts(2) }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Label {
                            text: histDelegate._grp.destName || histDelegate._grp.destKey
                            color: "#90A4AE"; font.pixelSize: ts(1.8); font.bold: true
                            elide: Text.ElideRight
                            width: histList.width - units.gu(12)
                        }
                        Label {
                            text: histDelegate._grp.date
                            color: "#B0BEC5"; font.pixelSize: ts(1.4)
                        }
                    }
                }
                Rectangle {
                    id: delGrpBtn
                    anchors { right: parent.right; rightMargin: units.gu(1.5)
                              verticalCenter: parent.verticalCenter }
                    width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                    color: delGrpMa.pressed ? "#3E2121" : "#1E2A3A"
                    Label { anchors.centerIn: parent; text: "🗑"; font.pixelSize: ts(1.8) }
                    MouseArea {
                        id: delGrpMa; anchors.fill: parent
                        onClicked: {
                            TodoDB.deleteDestGroup(histDelegate._grp.destKey, histDelegate._grp.date)
                            panel._refreshHistory()
                        }
                    }
                }
                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 1; color: "#1E2A3A"
                }
            }

            // Items del grupo
            Repeater {
                model: histDelegate._grp.todos
                delegate: Rectangle {
                    id: histTodoRow
                    width: histList.width; height: units.gu(5.5)
                    color: "#060E16"
                    property int _id: modelData.id

                    Label {
                        id: histChk
                        anchors { left: parent.left; leftMargin: units.gu(2.5)
                                  verticalCenter: parent.verticalCenter }
                        text: modelData.done ? "☑" : "☐"
                        color: modelData.done ? "#29B6F6" : "#90A4AE"
                        font.pixelSize: ts(2.2)
                    }
                    Label {
                        anchors { left: histChk.right; leftMargin: units.gu(1)
                                  right: histDelBtn.left; rightMargin: units.gu(1)
                                  verticalCenter: parent.verticalCenter }
                        text: modelData.text
                        color: modelData.done ? "#37474F" : "#B0BEC5"
                        font.strikeout: modelData.done
                        font.pixelSize: ts(1.8); wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        id: histDelBtn
                        anchors { right: parent.right; rightMargin: units.gu(1)
                                  verticalCenter: parent.verticalCenter }
                        width: units.gu(4); height: units.gu(4); radius: units.gu(0.4)
                        color: histDelMa.pressed ? "#3E2121" : "#1E2A3A"
                        Label { anchors.centerIn: parent; text: "✕"; color: "#FF5252"; font.pixelSize: ts(1.8) }
                        MouseArea {
                            id: histDelMa; anchors.fill: parent
                            onClicked: {
                                TodoDB.deleteHistTodo(histTodoRow._id)
                                panel._refreshHistory()
                            }
                        }
                    }
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                                  leftMargin: units.gu(2) }
                        height: 1; color: "#1E2A3A"
                    }
                    MouseArea {
                        anchors { fill: parent; rightMargin: units.gu(5.5) }
                        onClicked: {
                            TodoDB.setHistTodoDone(histTodoRow._id, !modelData.done)
                            panel._refreshHistory()
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width; height: units.gu(0.8)
                color: "#0A1929"
            }
        }
    }
}
