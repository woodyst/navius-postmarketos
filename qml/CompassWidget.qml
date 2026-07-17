import QtQuick 2.7
import QtQuick.Controls 2.15

Item {
    id: compassWidget
    width:  units.gu(9)
    height: units.gu(9)

    property real   bearing:     0
    property bool   nightMode:   false
    property string bearingMode: "north"   // "north" | "heading"
    property bool   hasArrow:    false
    property real   dispHeadRad: 0
    property bool   is3d:        false     // mapMode es "3d"
    property color  fgColor:      "white"   // color texto según tema del mapa
    property color  borderColor:  "white"   // color contorno círculo (= _mapBtnBorder)

    // bearingMode + is3d → compassMode para display
    readonly property string compassMode:
        bearingMode === "north"   ? "north" :
        is3d                      ? "heading3d" : "heading"

    signal cycleRequested()

    // ── Fondo ─────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent; radius: width / 2
        color: "transparent"
        border.color: compassWidget.borderColor; border.width: units.gu(0.15)
    }

    // ── Aguja (roja=N, gris=S) — rota con el mapa ────────────────────────
    Canvas {
        id: needleCanvas
        anchors.fill: parent
        rotation: -compassWidget.bearing

        property bool nightMode: compassWidget.nightMode
        onNightModeChanged: requestPaint()
        Component.onCompleted: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var cx = width / 2, cy = height / 2, R = width / 2
            var nw    = R * 0.09   // ancho aguja
            var inner = R * 0.30   // hueco botón interior
            var outer = R * 0.86   // borde exterior

            // Mitad N (roja)
            ctx.beginPath()
            ctx.moveTo(cx - nw, cy - inner)
            ctx.lineTo(cx,      cy - outer)
            ctx.lineTo(cx + nw, cy - inner)
            ctx.closePath()
            ctx.fillStyle = "#EF5350"
            ctx.fill()

            // Mitad S (blanco tenue)
            ctx.beginPath()
            ctx.moveTo(cx - nw, cy + inner)
            ctx.lineTo(cx,      cy + outer)
            ctx.lineTo(cx + nw, cy + inner)
            ctx.closePath()
            ctx.fillStyle = nightMode ? "rgba(255,255,255,0.30)" : "rgba(255,255,255,0.45)"
            ctx.fill()

            // Punto central
            ctx.beginPath()
            ctx.arc(cx, cy, nw * 1.1, 0, 2 * Math.PI)
            ctx.fillStyle = "rgba(255,255,255,0.85)"
            ctx.fill()
        }
    }

    // ── Flecha heading del vehículo (verde) ──────────────────────────────
    Canvas {
        id: headingArrow
        anchors.fill: parent
        visible: compassWidget.hasArrow
        rotation: compassWidget.dispHeadRad * 180 / Math.PI
        onVisibleChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var cx = width / 2, cy = height / 2, R = width / 2
            ctx.beginPath()
            ctx.moveTo(cx,             cy - R * 0.94)
            ctx.lineTo(cx - R * 0.06,  cy - R * 0.76)
            ctx.lineTo(cx + R * 0.06,  cy - R * 0.76)
            ctx.closePath()
            ctx.fillStyle = "#4CAF50"
            ctx.fill()
        }
    }

    // ── Botón interior: modo actual ───────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width: units.gu(6); height: units.gu(6); radius: width / 2
        color: "transparent"

        Column {
            anchors.centerIn: parent; spacing: 0

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: compassWidget.compassMode === "north" ? "N" : "↑"
                color: compassWidget.fgColor
                font.pixelSize: units.gu(2.6)
                font.bold: true
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: compassWidget.compassMode === "heading3d" ? "3D" : "2D"
                color: compassWidget.fgColor
                font.pixelSize: units.gu(1.3)
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: compassWidget.cycleRequested()
        }
    }
}
