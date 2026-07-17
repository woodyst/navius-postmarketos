import QtQuick 2.7
import QtQuick.Controls 2.15
import "NavMessages.js" as NavMessages

Rectangle {
    id: popup
    anchors.fill: parent
    z: 100
    visible: false
    color: "#CC000814"

    property string deviceId:  ""
    property string authToken: ""
    property var    msgs:      []
    property int    _idx:      0

    property real textScale: 1.0
    function ts(v) { return units.gu(v * 0.9 * textScale) }

    signal closed()
    signal addDestRequested(real lat, real lon, string nombre)

    function open(msgsArray) {
        if (!msgsArray || msgsArray.length === 0) return
        msgs = msgsArray
        _idx = 0
        visible = true
    }

    function _msg() {
        return msgs.length > 0 && _idx < msgs.length ? msgs[_idx] : null
    }

    function _impIcon(imp) {
        if (imp === "urgente")    return "🔴"
        if (imp === "importante") return "🟠"
        if (imp === "publicidad") return "📢"
        if (imp === "alerta")     return "🚨"
        return "ℹ️"
    }

    function _impColor(imp) {
        if (imp === "urgente")    return "#FF5252"
        if (imp === "importante") return "#FF9800"
        if (imp === "publicidad") return "#78909C"
        return "#29B6F6"
    }

    function _markCurrentRead() {
        var m = _msg()
        if (!m || m.leido_en) return
        NavMessages.markRead(popup.deviceId, popup.authToken, m.id, null)
        var updated = popup.msgs.slice()
        for (var i = 0; i < updated.length; i++) {
            if (updated[i].id === m.id) {
                updated[i] = Object.assign({}, updated[i], {leido_en: "now"})
                break
            }
        }
        popup.msgs = updated
    }

    // Fondo semitransparente — tap cierra
    MouseArea { anchors.fill: parent; onClicked: popup.closed() }

    // ── Tarjeta de mensaje ────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors {
            left: parent.left; right: parent.right
            leftMargin: units.gu(2); rightMargin: units.gu(2)
            verticalCenter: parent.verticalCenter
        }
        height: Math.min(popup.height * 0.88, cardCol.implicitHeight + units.gu(3))
        radius: units.gu(1.2)
        color: "#0D1B2A"
        border.color: popup._msg() ? popup._impColor(popup._msg().importancia) : "#29B6F6"
        border.width: units.gu(0.3)
        clip: true

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            id: cardCol
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: units.gu(2.5); rightMargin: units.gu(2.5); topMargin: units.gu(2)
            }
            spacing: units.gu(1.5)

            // ── Cabecera: icono + importancia + contador + cerrar ─────────
            Item {
                width: parent.width; height: units.gu(6)

                Label {
                    id: impIconLbl
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: popup._msg() ? popup._impIcon(popup._msg().importancia) : ""
                    font.pixelSize: ts(4.8)
                }

                Column {
                    anchors { left: impIconLbl.right; leftMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                    Label {
                        text: popup._msg() ? popup._msg().importancia.toUpperCase() : ""
                        color: popup._msg() ? popup._impColor(popup._msg().importancia) : "#29B6F6"
                        font.pixelSize: ts(1.7); font.bold: true
                    }
                    Label {
                        visible: popup.msgs.length > 1
                        text: (popup._idx + 1) + " / " + popup.msgs.length
                        color: "#B0BEC5"; font.pixelSize: ts(1.6)
                    }
                }

                Rectangle {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: units.gu(4.5); height: units.gu(4.5); radius: width / 2
                    color: popCloseMa.pressed ? "#1E3A5F" : "#1E2A3A"
                    Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: ts(2.6) }
                    MouseArea { id: popCloseMa; anchors.fill: parent; onClicked: popup.closed() }
                }
            }

            // ── Título ───────────────────────────────────────────────────
            Label {
                width: parent.width
                text: popup._msg() ? popup._msg().titulo : ""
                color: "white"; font.pixelSize: ts(3.0); font.bold: true
                wrapMode: Text.WordWrap
            }

            // ── Cuerpo (scrollable) ──────────────────────────────────────
            Flickable {
                width: parent.width
                height: Math.min(units.gu(22), bodyLabel.implicitHeight)
                contentHeight: bodyLabel.implicitHeight
                clip: true
                Label {
                    id: bodyLabel
                    width: parent.width
                    text: popup._msg() ? popup._msg().cuerpo : ""
                    color: "#B0BEC5"; font.pixelSize: ts(2.3)
                    wrapMode: Text.WordWrap
                }
            }

            // ── Enlace web ───────────────────────────────────────────────
            Rectangle {
                visible: { var m = popup._msg(); return !!(m && m.url && m.url.length > 0) }
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.7)
                color: linkMa.pressed ? "#0D3B5E" : "#163552"
                Row {
                    anchors.centerIn: parent; spacing: units.gu(1.2)
                    Label { text: "🔗"; font.pixelSize: ts(2.6); anchors.verticalCenter: parent.verticalCenter }
                    Label { text: i18n.tr("Abrir enlace"); color: "#29B6F6"; font.pixelSize: ts(2.3); font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea {
                    id: linkMa; anchors.fill: parent
                    onClicked: { var m = popup._msg(); if (m && m.url) Qt.openUrlExternally(m.url) }
                }
            }

            // ── Añadir destino ───────────────────────────────────────────
            Rectangle {
                visible: { var m = popup._msg(); return !!(m && m.dest_lat != null) }
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.7)
                color: destMa.pressed ? "#0D3B27" : "#142B1C"
                Row {
                    anchors.centerIn: parent; spacing: units.gu(1.2)
                    Label { text: "📍"; font.pixelSize: ts(2.6); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: {
                            var m = popup._msg()
                            return (m && m.dest_nombre) ? i18n.tr("Ir a") + " " + m.dest_nombre : i18n.tr("Añadir destino")
                        }
                        color: "#4CAF50"; font.pixelSize: ts(2.3); font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, card.width - units.gu(14))
                    }
                }
                MouseArea {
                    id: destMa; anchors.fill: parent
                    onClicked: {
                        var m = popup._msg()
                        if (m && m.dest_lat != null)
                            popup.addDestRequested(m.dest_lat, m.dest_lon, m.dest_nombre || i18n.tr("Destino"))
                    }
                }
            }

            // ── Botones: Anterior / Leído / Siguiente ────────────────────
            // Posicionados con x explícito para controlar ancho sin depender
            // de si los elementos invisibles ocupan espacio en Row.
            Item {
                width: parent.width; height: units.gu(6)

                property bool hasPrev: popup._idx > 0
                property bool hasNext: popup._idx + 1 < popup.msgs.length
                property int  _cnt:   (hasPrev ? 1 : 0) + 1 + (hasNext ? 1 : 0)
                property real _btnW:  (width - (_cnt - 1) * units.gu(1)) / _cnt

                // ← Anterior
                Rectangle {
                    visible: parent.hasPrev
                    x: 0; width: parent._btnW; height: parent.height; radius: units.gu(0.7)
                    color: prevMa.pressed ? "#1C2C3C" : "#263238"
                    Label { anchors.centerIn: parent; text: "←  " + i18n.tr("Anterior")
                            color: "#B0BEC5"; font.pixelSize: ts(2.1) }
                    MouseArea { id: prevMa; anchors.fill: parent; onClicked: popup._idx-- }
                }

                // ✓ Leído
                Rectangle {
                    x: parent.hasPrev ? parent._btnW + units.gu(1) : 0
                    width: parent._btnW; height: parent.height; radius: units.gu(0.7)
                    color: readMa.pressed ? "#1C2C3C" : "#263238"
                    Label { anchors.centerIn: parent; text: "✓  " + i18n.tr("Leído")
                            color: "#90A4AE"; font.pixelSize: ts(2.3); font.bold: true }
                    MouseArea {
                        id: readMa; anchors.fill: parent
                        onClicked: {
                            popup._markCurrentRead()
                            if (popup._idx + 1 < popup.msgs.length) popup._idx++
                            else popup.closed()
                        }
                    }
                }

                // Siguiente →
                Rectangle {
                    visible: parent.hasNext
                    x: parent.width - parent._btnW
                    width: parent._btnW; height: parent.height; radius: units.gu(0.7)
                    color: nextMa.pressed ? "#1B3A6B" : "#1E3A5F"
                    Label { anchors.centerIn: parent; text: i18n.tr("Siguiente") + "  →"
                            color: "#29B6F6"; font.pixelSize: ts(2.3); font.bold: true }
                    MouseArea { id: nextMa; anchors.fill: parent; onClicked: popup._idx++ }
                }
            }

            Item { width: 1; height: units.gu(0.5) }
        }
    }
}
