import QtQuick 2.7
import QtQuick.Controls 2.15
import "NavMessages.js" as NavMessages

Rectangle {
    id: panel
    anchors.fill: parent
    z: 55
    color: "#07111E"
    visible: false

    // Propiedades de entrada
    property string deviceId:   ""
    property string authToken:  ""
    property real   textScale:  1.0
    function ts(v) { return units.gu(v * 0.9 * textScale) }

    // Estado interno
    property var  _msgs:        []
    property int  _unreadCount: 0
    property bool _loading:     false
    property int  _openMsgId:   -1   // id a destacar al abrir

    signal closed()
    signal addDestRequested(real lat, real lon, string nombre)
    signal viewDetailRequested(var msg)

    // ---------------------------------------------------------------------------
    function open(highlightId) {
        _openMsgId = highlightId !== undefined ? highlightId : -1
        visible = true
        _refresh()
    }

    function addNewMsgs(newMsgs) {
        // Llamado por el timer de polling — integra mensajes nuevos sin limpiar lista
        if (!newMsgs || newMsgs.length === 0) return
        var updated = _msgs.slice()
        for (var i = 0; i < newMsgs.length; i++) {
            var found = false
            for (var k = 0; k < updated.length; k++) {
                if (updated[k].id === newMsgs[i].id) { updated[k] = newMsgs[i]; found = true; break }
            }
            if (!found) updated.unshift(newMsgs[i])
        }
        updated.sort(function(a,b) { return b.id - a.id })
        _msgs = updated
        _updateUnread()
    }

    function _refresh() {
        _loading = true
        NavMessages.fetchMsgs(deviceId, authToken, 0, function(msgs) {
            _loading = false
            if (!msgs) return
            msgs.sort(function(a,b) { return b.id - a.id })
            _msgs = msgs
            _updateUnread()
            if (_openMsgId > 0) {
                Qt.callLater(function() { _scrollTo(_openMsgId) })
            }
        })
    }

    function _updateUnread() {
        var c = 0
        for (var i = 0; i < _msgs.length; i++) if (!_msgs[i].leido_en) c++
        _unreadCount = c
    }

    function _scrollTo(id) {
        for (var i = 0; i < _msgs.length; i++) {
            if (_msgs[i].id === id) { msgList.positionViewAtIndex(i, ListView.Beginning); return }
        }
    }

    function _impColor(imp) {
        if (imp === "urgente")    return "#FF5252"
        if (imp === "importante") return "#FF9800"
        if (imp === "publicidad") return "#78909C"
        return "#29B6F6"
    }

    function _tipoIcon(tipo) {
        if (tipo === "alerta")  return "🔴"
        if (tipo === "aviso")   return "⚠️"
        if (tipo === "anuncio") return "📢"
        return "ℹ️"
    }

    function _fmtDate(dt) {
        return dt ? dt.toString().substring(0, 16).replace("T", " ") : ""
    }

    // ---------------------------------------------------------------------------
    // Header
    // ---------------------------------------------------------------------------
    Rectangle {
        id: panelHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(7)
        color: "#0D1B2A"

        Label {
            anchors.centerIn: parent
            text: i18n.tr("Mensajes")
            color: "white"; font.pixelSize: ts(2.7); font.bold: true
        }

        // Badge no leídos
        Rectangle {
            visible: panel._unreadCount > 0
            anchors { left: parent.left; leftMargin: units.gu(1.5)
                      verticalCenter: parent.verticalCenter }
            width: Math.max(units.gu(3.5), unreadLbl.width + units.gu(1.5))
            height: units.gu(3.5); radius: height / 2
            color: "#FF5722"
            Label {
                id: unreadLbl
                anchors.centerIn: parent
                text: panel._unreadCount
                color: "white"; font.pixelSize: ts(1.8); font.bold: true
            }
        }

        // Botón actualizar
        Rectangle {
            anchors { right: closeBtnHdr.left; rightMargin: units.gu(1)
                      verticalCenter: parent.verticalCenter }
            width: units.gu(4.5); height: units.gu(4.5); radius: width / 2
            color: refreshMa.pressed ? "#1E3A5F" : "#1E2A3A"
            opacity: panel._loading ? 0.4 : 1.0
            Label { anchors.centerIn: parent; text: "↻"; color: "#90A4AE"; font.pixelSize: ts(2.7) }
            MouseArea { id: refreshMa; anchors.fill: parent; enabled: !panel._loading; onClicked: panel._refresh() }
        }

        Rectangle {
            id: closeBtnHdr
            anchors { right: parent.right; rightMargin: units.gu(1.5)
                      verticalCenter: parent.verticalCenter }
            width: units.gu(4.5); height: units.gu(4.5); radius: width / 2
            color: "#1E2A3A"
            Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: ts(2.7) }
            MouseArea { anchors.fill: parent; onClicked: panel.closed() }
        }

        Rectangle {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 1; color: "#1E2A3A"
        }
    }

    // Loading indicator
    Label {
        anchors.centerIn: parent
        visible: panel._loading && panel._msgs.length === 0
        text: i18n.tr("Cargando mensajes…")
        color: "#90A4AE"; font.pixelSize: ts(2.3)
    }

    // Empty state
    Label {
        anchors.centerIn: parent
        visible: !panel._loading && panel._msgs.length === 0
        text: i18n.tr("Sin mensajes")
        color: "#B0BEC5"; font.pixelSize: ts(2.3)
    }

    // ---------------------------------------------------------------------------
    // Lista de mensajes
    // ---------------------------------------------------------------------------
    ListView {
        id: msgList
        anchors { top: panelHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: true
        model: panel._msgs
        spacing: 0

        delegate: Rectangle {
            id: msgDelegate
            width: msgList.width
            height: _expanded ? expandedCol.implicitHeight + units.gu(2.5) : units.gu(8.5)
            clip: true

            property bool _expanded: panel._openMsgId === modelData.id
            property bool _isUnread: !modelData.leido_en
            property bool _isHighlight: panel._openMsgId === modelData.id

            color: _isHighlight ? "#0D2244" : (_isUnread ? "#0A1929" : "#060E16")
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // Expandir/colapsar — declarado PRIMERO para quedar bajo la Column
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    var id = modelData.id
                    if (!msgDelegate._expanded) {
                        if (msgDelegate._isUnread) {
                            NavMessages.markRead(panel.deviceId, panel.authToken, id, null)
                            var updated = panel._msgs.slice()
                            for (var i = 0; i < updated.length; i++) {
                                if (updated[i].id === id) {
                                    updated[i] = Object.assign({}, updated[i], {leido_en: "now"})
                                    break
                                }
                            }
                            panel._msgs = updated
                            panel._updateUnread()
                        }
                        panel._openMsgId = id
                    } else {
                        panel._openMsgId = -1
                    }
                }
            }

            // Barra de color izquierda según importancia
            Rectangle {
                width: units.gu(0.5)
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                color: panel._impColor(modelData.importancia)
                opacity: msgDelegate._isUnread ? 1.0 : 0.3
            }

            Column {
                id: expandedCol
                anchors { left: parent.left; leftMargin: units.gu(1.5); right: parent.right
                          rightMargin: units.gu(0.5); top: parent.top; topMargin: units.gu(1) }
                spacing: units.gu(0.5)

                // ── Cabecera del mensaje ───────────────────────────────────
                Row {
                    width: parent.width
                    spacing: units.gu(0.8)

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel._tipoIcon(modelData.tipo)
                        font.pixelSize: ts(2)
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(14)
                        spacing: units.gu(0.2)

                        Label {
                            width: parent.width
                            text: modelData.titulo
                            color: msgDelegate._isUnread ? "white" : "#78909C"
                            font.pixelSize: ts(2.3)
                            font.bold: msgDelegate._isUnread
                            elide: Text.ElideRight
                        }
                        Row {
                            spacing: units.gu(0.6)
                            Label {
                                text: panel._fmtDate(modelData.creado_en)
                                color: "#B0BEC5"; font.pixelSize: ts(1.7)
                            }
                            Rectangle {
                                visible: modelData.importancia !== "normal"
                                width: impLbl.width + units.gu(1.2); height: units.gu(2.2); radius: height/2
                                color: panel._impColor(modelData.importancia) + "33"
                                border.color: panel._impColor(modelData.importancia); border.width: 1
                                Label {
                                    id: impLbl
                                    anchors.centerIn: parent
                                    text: modelData.importancia
                                    color: panel._impColor(modelData.importancia)
                                    font.pixelSize: ts(1.5)
                                }
                            }
                        }
                    }

                    // Botón expandir/colapsar
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: msgDelegate._expanded ? "▲" : "▼"
                        color: "#90A4AE"; font.pixelSize: ts(1.7)
                        width: units.gu(2.5)
                    }

                    // Botón eliminar
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4.5); height: units.gu(4.5); radius: units.gu(0.4)
                        color: delMa.pressed ? "#3E2121" : "#1E2A3A"
                        Label { anchors.centerIn: parent; text: "🗑"; font.pixelSize: ts(2.2) }
                        MouseArea {
                            id: delMa; anchors.fill: parent
                            onClicked: {
                                var id = modelData.id
                                NavMessages.deleteMsg(panel.deviceId, panel.authToken, id, null)
                                var updated = panel._msgs.slice()
                                for (var i = 0; i < updated.length; i++) {
                                    if (updated[i].id === id) { updated.splice(i, 1); break }
                                }
                                panel._msgs = updated
                                panel._updateUnread()
                            }
                        }
                    }
                }

                // ── Ver en grande ─────────────────────────────────────────
                Rectangle {
                    visible: msgDelegate._expanded
                    width: parent.width - units.gu(1); height: units.gu(4.5); radius: units.gu(0.6)
                    color: eyeMa.pressed ? "#1E3A5F" : "#1B2A3B"
                    Row {
                        anchors.centerIn: parent; spacing: units.gu(1)
                        Label { text: "👁"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                        Label { text: i18n.tr("Ver en grande"); color: "#90A4AE"; font.pixelSize: ts(2.0); anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: eyeMa; anchors.fill: parent; onClicked: panel.viewDetailRequested(modelData) }
                }

                // ── Cuerpo expandido ──────────────────────────────────────
                Label {
                    visible: msgDelegate._expanded
                    width: parent.width - units.gu(1)
                    text: modelData.cuerpo
                    color: "#B0BEC5"; font.pixelSize: ts(2.2)
                    wrapMode: Text.WordWrap
                }

                // ── Enlace web ────────────────────────────────────────────
                Rectangle {
                    visible: msgDelegate._expanded && modelData.url && modelData.url.length > 0
                    width: parent.width - units.gu(1); height: units.gu(5); radius: units.gu(0.6)
                    color: msgLinkMa.pressed ? "#0D3B5E" : "#163552"
                    Row {
                        anchors.centerIn: parent; spacing: units.gu(1)
                        Label { text: "🔗"; font.pixelSize: ts(2.3); anchors.verticalCenter: parent.verticalCenter }
                        Label { text: i18n.tr("Abrir enlace"); color: "#29B6F6"; font.pixelSize: ts(2.1); anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea { id: msgLinkMa; anchors.fill: parent; onClicked: Qt.openUrlExternally(modelData.url) }
                }

                // ── Añadir destino ────────────────────────────────────────
                Rectangle {
                    visible: msgDelegate._expanded && modelData.dest_lat != null
                    width: parent.width - units.gu(1); height: units.gu(5); radius: units.gu(0.6)
                    color: msgDestMa.pressed ? "#0D3B27" : "#142B1C"
                    Row {
                        anchors.centerIn: parent; spacing: units.gu(1)
                        Label { text: "📍"; font.pixelSize: ts(2.3); anchors.verticalCenter: parent.verticalCenter }
                        Label {
                            text: modelData.dest_nombre ? i18n.tr("Ir a") + " " + modelData.dest_nombre : i18n.tr("Añadir destino")
                            color: "#4CAF50"; font.pixelSize: ts(2.1); anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, parent.parent.width - units.gu(10))
                        }
                    }
                    MouseArea {
                        id: msgDestMa; anchors.fill: parent
                        onClicked: {
                            if (modelData.dest_lat != null)
                                panel.addDestRequested(modelData.dest_lat, modelData.dest_lon, modelData.dest_nombre || i18n.tr("Destino"))
                        }
                    }
                }
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: units.gu(1.5) }
                height: 1; color: "#1E2A3A"
            }
        }
    }
}
