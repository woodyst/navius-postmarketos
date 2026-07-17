// Compact speed widget – overlaid on map.
import QtQuick 2.7
import QtQuick.Controls 2.15

Rectangle {
    id: root
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    property var satModel: null

    width:  units.gu(13)
    height: units.gu(11.5)
    radius: units.gu(1.2)
    color:  "#CC0D0D1A"

    // ── GPS searching (no fix) ───────────────────────────────────────────────
    Column {
        visible: !satModel || !satModel.pos_has_fix
        anchors.centerIn: parent
        spacing: units.gu(0.5)

        Canvas {
            id: satCanvas
            anchors.horizontalCenter: parent.horizontalCenter
            width: units.gu(7); height: units.gu(7)
            Component.onCompleted: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var W = width, cx = W/2, cy = W/2
                var col = "#757575"
                ctx.fillStyle = col; ctx.strokeStyle = col

                // Ring
                var rMid = W * 0.33
                var rW   = W * 0.085
                ctx.lineWidth = rW
                ctx.beginPath(); ctx.arc(cx, cy, rMid, 0, Math.PI * 2); ctx.stroke()

                // Center dot
                ctx.beginPath(); ctx.arc(cx, cy, W * 0.145, 0, Math.PI * 2); ctx.fill()

                // 4 tick marks
                var tI = rMid + rW / 2   // inner edge (= ring outer)
                var tO = W * 0.49        // outer edge
                ctx.lineCap = "butt"
                ctx.beginPath(); ctx.moveTo(cx, cy - tI); ctx.lineTo(cx, cy - tO); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cx, cy + tI); ctx.lineTo(cx, cy + tO); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cx - tI, cy); ctx.lineTo(cx - tO, cy); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(cx + tI, cy); ctx.lineTo(cx + tO, cy); ctx.stroke()
            }
            SequentialAnimation on opacity {
                running: parent.visible; loops: Animation.Infinite
                NumberAnimation { to: 0.15; duration: 750 }
                NumberAnimation { to: 1.0;  duration: 750 }
            }
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text:  i18n.tr("Buscando GPS…")
            color: "#FFA726"
            font.pixelSize: ts(1.4)
        }
    }

    // ── Speed (has fix) ──────────────────────────────────────────────────────
    Column {
        visible: satModel && satModel.pos_has_fix
        anchors.centerIn: parent
        spacing: 0

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: satModel ? satModel.pos_speed_kmh.toFixed(0) : "0"
            color: "white"
            font.pixelSize: ts(6); font.bold: true
            lineHeight: 0.9
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text:  "km/h"
            color: "white"; opacity: 0.75
            font.pixelSize: ts(2.0); font.bold: true
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text:  satModel && satModel.pos_accuracy >= 0
                   ? "±" + satModel.pos_accuracy.toFixed(0) + " m" : ""
            color: "white"; opacity: 0.55
            font.pixelSize: ts(1.5)
        }
    }
}
