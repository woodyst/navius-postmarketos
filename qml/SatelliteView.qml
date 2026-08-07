/*
 * Pantalla de información de satélites GPS.
 * `satModel` debe ser una instancia de SatelliteModel (Navius 1.0).
 *
 * Nota: los nombres de propiedad/método/señal en QML reflejan el campo Rust
 * tal cual (snake_case): sat_ids, start_updates, on_data_changed, etc.
 */

import QtQuick 2.7
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15

Item {
    id: root

    property var  satModel:    null
    property bool isLandscape: false

    // Sistema: 0=desconocido 1=GPS 2=GLONASS 3=Galileo 4=BeiDou 5=QZSS
    // (ver src/nmea_sat_source.h y src/location_props.cpp)
    function systemColor(sys) {
        switch (sys) {
        case 2:  return "#29B6F6"   // GLONASS
        case 3:  return "#FFA726"   // Galileo
        case 4:  return "#AB47BC"   // BeiDou
        case 5:  return "#EC407A"   // QZSS
        default: return "#66BB6A"   // GPS (y desconocido)
        }
    }

    // El color dice SIEMPRE de qué constelación es; en uso o no lo dice el
    // brillo. Antes los no fijados iban todos al mismo gris, así que un GLONASS
    // sin fijar era indistinguible de un GPS sin fijar y parecía que el módem
    // solo daba GPS.
    function signalColor(inUse, sys) {
        return inUse ? systemColor(sys) : Qt.darker(systemColor(sys), 2.6)
    }

    // Dibuja la esfera celeste en el contexto dado. Llamado desde ambos modos.
    function drawSky(ctx, w, h) {
        var cx = w / 2
        var cy = h / 2
        var r  = Math.min(w, h) / 2 - units.gu(3)

        ctx.clearRect(0, 0, w, h)

        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
        ctx.fillStyle = "#1A237E"
        ctx.fill()

        ctx.strokeStyle = "rgba(255,255,255,0.2)"
        ctx.lineWidth = 1
        ;[0, 30, 60].forEach(function(el) {
            var pr = r * (1 - el / 90)
            ctx.beginPath()
            ctx.arc(cx, cy, pr, 0, 2 * Math.PI)
            ctx.stroke()
        })

        ctx.beginPath()
        ctx.moveTo(cx, cy - r); ctx.lineTo(cx, cy + r)
        ctx.moveTo(cx - r, cy); ctx.lineTo(cx + r, cy)
        ctx.strokeStyle = "rgba(255,255,255,0.25)"
        ctx.stroke()

        var off = units.gu(1.5)
        ctx.fillStyle    = "rgba(255,255,255,0.6)"
        ctx.font         = units.gu(1.4) + "px sans-serif"
        ctx.textAlign    = "center"
        ctx.textBaseline = "middle"
        ctx.fillText("N", cx,           cy - r - off)
        ctx.fillText("S", cx,           cy + r + off)
        ctx.fillText("E", cx + r + off, cy)
        ctx.fillText("O", cx - r - off, cy)

        ctx.font = units.gu(1) + "px sans-serif"
        ctx.fillStyle = "rgba(255,255,255,0.35)"
        ;[{el:0,lbl:"0°"},{el:30,lbl:"30°"},{el:60,lbl:"60°"}].forEach(function(o){
            var pr = r * (1 - o.el / 90)
            ctx.fillText(o.lbl, cx + pr + units.gu(0.4), cy - units.gu(0.8))
        })

        if (!satModel || satModel.sat_ids.length === 0) return

        var ids  = satModel.sat_ids
        var azs  = satModel.sat_azimuths
        var els  = satModel.sat_elevations
        var uses = satModel.sat_in_use
        var syss = satModel.sat_systems
        var dotR = units.gu(1.3)

        for (var i = 0; i < ids.length; i++) {
            var az_rad = azs[i] * Math.PI / 180
            var dist   = r * (1 - els[i] / 90)
            var sx     = cx + dist * Math.sin(az_rad)
            var sy     = cy - dist * Math.cos(az_rad)

            ctx.beginPath()
            ctx.arc(sx, sy, dotR + 1, 0, 2 * Math.PI)
            ctx.fillStyle = "rgba(0,0,0,0.5)"
            ctx.fill()

            ctx.beginPath()
            ctx.arc(sx, sy, dotR, 0, 2 * Math.PI)
            ctx.fillStyle = signalColor(uses[i], syss[i])
            ctx.fill()

            ctx.fillStyle    = "white"
            ctx.font         = "bold " + units.gu(1) + "px sans-serif"
            ctx.textAlign    = "center"
            ctx.textBaseline = "middle"
            ctx.fillText(ids[i].toString(), sx, sy)
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // PORTRAIT — ColumnLayout existente (sin cambios)
    // ══════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        visible: !root.isLandscape
        spacing: 0

        // --- barra de estado -------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            height: units.gu(5)
            color: "#1C1C2E"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin:  units.gu(2)
                anchors.rightMargin: units.gu(2)

                Label {
                    text: {
                        if (!satModel) return "0/0 sat"
                        if (satModel.in_view_count > 0)
                            return satModel.in_use_count + "/" + satModel.in_view_count + " sat"
                        if (satModel.pos_has_fix) return "GPS activo"
                        return "0/0 sat"
                    }
                    color: "white"; font.pixelSize: units.gu(2); font.bold: true
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: units.gu(1.5); height: units.gu(1.5); radius: width / 2
                    color: (satModel && satModel.is_active) ? "#66BB6A" : "#546E7A"
                    SequentialAnimation on opacity {
                        running: satModel && satModel.is_active && satModel.error_string === ""
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 800 }
                        NumberAnimation { to: 1.0; duration: 800 }
                    }
                }
                Label {
                    text: satModel && satModel.pos_has_fix ? i18n.tr("Activo") : i18n.tr("Buscando…")
                    color: satModel && satModel.pos_has_fix ? "#66BB6A" : "#FFA726"
                    font.pixelSize: units.gu(1.75)
                }
            }
        }

        // --- vista polar del cielo (portrait) -------------------------
        Rectangle {
            id: pSkyContainer
            Layout.fillWidth: true
            Layout.preferredHeight: width
            color: "#0D0D1A"
            clip: true

            Canvas {
                id: pSkyCanvas
                anchors.fill: parent
                antialiasing: true
                onWidthChanged:  requestPaint()
                onHeightChanged: requestPaint()
                onPaint: root.drawSky(getContext("2d"), width, height)
                Connections {
                    target: satModel
                    function onData_changed() { pSkyCanvas.requestPaint() }
                }
            }
        }

        // --- posición GPS (portrait) -----------------------------------
        Rectangle {
            Layout.fillWidth: true
            height: units.gu(4.5)
            color: "#0D1A0D"
            visible: satModel && satModel.pos_has_fix

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin:  units.gu(2)
                anchors.rightMargin: units.gu(2)
                spacing: units.gu(1.5)

                Label { text: satModel ? satModel.pos_lat.toFixed(6) + "°" : ""; color: "#A5D6A7"; font.pixelSize: units.gu(1.75); font.family: "Monospace" }
                Label { text: satModel ? satModel.pos_lon.toFixed(6) + "°" : ""; color: "#A5D6A7"; font.pixelSize: units.gu(1.75); font.family: "Monospace" }
                Item { Layout.fillWidth: true }
                Label { visible: satModel && satModel.pos_speed_kmh >= 0; text: satModel ? satModel.pos_speed_kmh.toFixed(1) + " km/h" : ""; color: "#81C784"; font.pixelSize: units.gu(1.75) }
                Label { visible: satModel && satModel.pos_accuracy >= 0;  text: satModel ? "±" + satModel.pos_accuracy.toFixed(0) + " m" : "";    color: "#B0BEC5";  font.pixelSize: units.gu(1.5) }
            }
        }

        // --- barras de señal (portrait) --------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: units.gu(16)
            color: "#0D0D1A"

            Label {
                visible: !satModel || satModel.sat_ids.length === 0
                anchors.centerIn: parent
                text: {
                    if (!satModel) return i18n.tr("Esperando satélites…")
                    if (satModel.error_string !== "") return satModel.error_string
                    if (satModel.pos_has_fix) return i18n.tr("Sin satélites visibles\n(se necesita visibilidad del cielo)")
                    if (satModel.is_active)   return i18n.tr("Esperando satélites…")
                    return i18n.tr("Pulsa Iniciar para activar el GPS")
                }
                color: satModel && satModel.pos_has_fix ? "#FFA726" : "#78909C"
                font.pixelSize: units.gu(1.75); horizontalAlignment: Text.AlignHCenter
            }

            Flickable {
                anchors.fill: parent; anchors.margins: units.gu(1)
                contentWidth: pBarsRow.width; clip: true
                visible: satModel && satModel.sat_ids.length > 0

                Row {
                    id: pBarsRow
                    spacing: units.gu(0.6); height: parent.height

                    Repeater {
                        model: satModel ? satModel.sat_ids.length : 0
                        delegate: Column {
                            width: units.gu(3); height: pBarsRow.height; spacing: units.gu(0.3)

                            Item { width: parent.width; height: parent.height - pBarRect.height - pIdLbl.height - units.gu(0.3) }

                            Rectangle {
                                id: pBarRect
                                width: parent.width - units.gu(0.4)
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: Math.max(units.gu(0.5), (satModel.sat_signals[index] / 50) * units.gu(10))
                                color: root.signalColor(satModel.sat_in_use[index], satModel.sat_systems[index])
                                radius: units.gu(0.3)
                                Behavior on height { NumberAnimation { duration: 400 } }
                            }

                            Label {
                                id: pIdLbl
                                text: satModel.sat_ids[index].toString()
                                font.pixelSize: units.gu(1.5); color: "#B0BEC5"
                                horizontalAlignment: Text.AlignHCenter; width: parent.width
                            }
                        }
                    }
                }
            }
        }

        // --- leyenda (portrait) ----------------------------------------
        Rectangle {
            Layout.fillWidth: true
            height: units.gu(3)
            color: "#1C1C2E"

            RowLayout {
                anchors.centerIn: parent; spacing: units.gu(2)
                Repeater {
                    model: [
                        { color: "#66BB6A", label: "GPS"      },
                        { color: "#29B6F6", label: "GLONASS"  },
                        { color: "#FFA726", label: "Galileo"  },
                        { color: "#AB47BC", label: "BeiDou"   },
                        { color: Qt.darker("#66BB6A", 2.6), label: "No en uso" },
                    ]
                    delegate: Row {
                        spacing: units.gu(0.5)
                        Rectangle { width: units.gu(1.2); height: units.gu(1.2); radius: width/2; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: modelData.label; font.pixelSize: units.gu(1.5); color: "#90A4AE"; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // LANDSCAPE — columna izquierda: esfera (60%); columna derecha: todo lo demás
    // ══════════════════════════════════════════════════════════════════════
    Item {
        anchors.fill: parent
        visible: root.isLandscape

        // ── Columna izquierda: esfera celeste ──────────────────────────
        Item {
            id: lsLeftCol
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: Math.round(parent.width * 0.6)

            Rectangle {
                // Cuadrado centrado: tamaño = min(ancho disponible, alto total)
                property real sz: Math.min(lsLeftCol.width, lsLeftCol.height)
                anchors.centerIn: parent
                width: sz; height: sz
                color: "#0D0D1A"; clip: true

                Canvas {
                    id: lsSkyCanvas
                    anchors.fill: parent
                    antialiasing: true
                    onWidthChanged:  requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: root.drawSky(getContext("2d"), width, height)
                    Connections {
                        target: satModel
                        function onData_changed() { lsSkyCanvas.requestPaint() }
                    }
                }
            }
        }

        // ── Columna derecha: header + barras + posbar + leyenda ────────
        Item {
            id: lsRightCol
            anchors { top: parent.top; bottom: parent.bottom; left: lsLeftCol.right; right: parent.right }

            // -- Barra de estado (arriba) --------------------------------
            Rectangle {
                id: lsHeader
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: units.gu(5)
                color: "#1C1C2E"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  units.gu(1.5)
                    anchors.rightMargin: units.gu(1.5)

                    Label {
                        text: {
                            if (!satModel) return "0/0 sat"
                            if (satModel.in_view_count > 0)
                                return satModel.in_use_count + "/" + satModel.in_view_count + " sat"
                            if (satModel.pos_has_fix) return "GPS activo"
                            return "0/0 sat"
                        }
                        color: "white"; font.pixelSize: units.gu(2); font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: units.gu(1.5); height: units.gu(1.5); radius: width / 2
                        color: (satModel && satModel.is_active) ? "#66BB6A" : "#546E7A"
                        SequentialAnimation on opacity {
                            running: satModel && satModel.is_active && satModel.error_string === ""
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 800 }
                            NumberAnimation { to: 1.0; duration: 800 }
                        }
                    }
                    Label {
                        text: satModel && satModel.pos_has_fix ? i18n.tr("Activo") : i18n.tr("Buscando…")
                        color: satModel && satModel.pos_has_fix ? "#66BB6A" : "#FFA726"
                        font.pixelSize: units.gu(1.75)
                    }
                }
            }

            // -- Leyenda (abajo del todo) --------------------------------
            Rectangle {
                id: lsLegend
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: units.gu(3)
                color: "#1C1C2E"

                RowLayout {
                    anchors.centerIn: parent; spacing: units.gu(1.5)
                    Repeater {
                        model: [
                            { color: "#66BB6A", label: "GPS"     },
                            { color: "#29B6F6", label: "GLONASS" },
                            { color: "#FFA726", label: "GAL"     },
                            { color: "#AB47BC", label: "BDS"     },
                            { color: Qt.darker("#66BB6A", 2.6), label: "No uso" },
                        ]
                        delegate: Row {
                            spacing: units.gu(0.4)
                            Rectangle { width: units.gu(1.1); height: units.gu(1.1); radius: width/2; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                            Label { text: modelData.label; font.pixelSize: units.gu(1.5); color: "#90A4AE"; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }

            // -- Posición GPS (sobre la leyenda) -------------------------
            Rectangle {
                id: lsPosBar
                anchors { bottom: lsLegend.top; left: parent.left; right: parent.right }
                height: units.gu(4)
                visible: satModel && satModel.pos_has_fix
                color: "#0D1A0D"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  units.gu(1.5)
                    anchors.rightMargin: units.gu(1.5)
                    spacing: units.gu(1)

                    Label { text: satModel ? satModel.pos_lat.toFixed(5) + "°" : ""; color: "#A5D6A7"; font.pixelSize: units.gu(1.5); font.family: "Monospace" }
                    Label { text: satModel ? satModel.pos_lon.toFixed(5) + "°" : ""; color: "#A5D6A7"; font.pixelSize: units.gu(1.5); font.family: "Monospace" }
                    Item { Layout.fillWidth: true }
                    Label { visible: satModel && satModel.pos_accuracy >= 0; text: satModel ? "±" + satModel.pos_accuracy.toFixed(0) + " m" : ""; color: "#B0BEC5"; font.pixelSize: units.gu(1.5) }
                }
            }

            // -- Barras de señal horizontales (zona central) -------------
            Item {
                anchors {
                    top:    lsHeader.bottom
                    bottom: lsPosBar.visible ? lsPosBar.top : lsLegend.top
                    left:   parent.left
                    right:  parent.right
                }

                Label {
                    visible: !satModel || satModel.sat_ids.length === 0
                    anchors.centerIn: parent
                    text: {
                        if (!satModel) return i18n.tr("Esperando satélites…")
                        if (satModel.error_string !== "") return satModel.error_string
                        if (satModel.pos_has_fix) return i18n.tr("Sin satélites visibles")
                        if (satModel.is_active)   return i18n.tr("Esperando satélites…")
                        return i18n.tr("Pulsa Iniciar para activar el GPS")
                    }
                    color: "#78909C"; font.pixelSize: units.gu(1.5); horizontalAlignment: Text.AlignHCenter
                }

                // Filas horizontales: [barra crece desde la derecha] [número]
                Flickable {
                    anchors { fill: parent; topMargin: units.gu(0.6); bottomMargin: units.gu(0.6); leftMargin: units.gu(0.5); rightMargin: units.gu(0.5) }
                    contentHeight: lsHBarsCol.implicitHeight
                    flickableDirection: Flickable.VerticalFlick
                    clip: true
                    visible: satModel && satModel.sat_ids.length > 0

                    Column {
                        id: lsHBarsCol
                        width: parent.width
                        spacing: units.gu(0.35)

                        Repeater {
                            model: satModel ? satModel.sat_ids.length : 0

                            delegate: Item {
                                width: lsHBarsCol.width
                                height: units.gu(2.5)

                                // Número a la derecha
                                Label {
                                    id: lsIdLbl
                                    anchors { right: parent.right; rightMargin: units.gu(0.8); verticalCenter: parent.verticalCenter }
                                    text: satModel.sat_ids[index].toString()
                                    font.pixelSize: units.gu(1.5); color: "#B0BEC5"
                                    width: units.gu(2.4); horizontalAlignment: Text.AlignHCenter
                                }

                                // Pista: del margen izquierdo hasta el número
                                Item {
                                    id: lsBarTrack
                                    anchors { left: parent.left; leftMargin: units.gu(0.5); right: lsIdLbl.left; rightMargin: units.gu(0.3); verticalCenter: parent.verticalCenter }
                                    height: units.gu(1.4)

                                    // Barra anclada a la derecha, crece hacia la izquierda
                                    Rectangle {
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        width: Math.max(units.gu(0.3), (satModel.sat_signals[index] / 50) * lsBarTrack.width)
                                        height: parent.height
                                        color: root.signalColor(satModel.sat_in_use[index], satModel.sat_systems[index])
                                        radius: units.gu(0.2)
                                        Behavior on width { NumberAnimation { duration: 400 } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
