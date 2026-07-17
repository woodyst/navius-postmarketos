import QtQuick 2.7
import QtQuick.Controls 2.15
import "NavSearch.js" as NavSearch

Item {
    id: rsp
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false
    z: 26

    property real navBarHeight:  0
    property bool isLandscape:   false
    property var  routes:        []
    property int  selIdx:        0
    property bool imperial:      false

    property var    vehicleMgr:    null
    property var    _vehList:      []
    property string _activeId:     ""
    property bool   _recalculating: false

    onVisibleChanged: if (visible && vehicleMgr) _refreshVehicles()

    function _refreshVehicles() {
        _vehList = vehicleMgr.allVehicles()
        var av = vehicleMgr.activeVehicle()
        _activeId = av ? av.id : ""
    }

    signal closed()
    signal routeSelected(int idx)
    signal navigationRequested(int idx)
    signal vehicleChangeRequested(string vehicleId)

    // ── Botón cerrar ──────────────────────────────────────────────────────────
    Rectangle {
        anchors {
            // Portrait: esquina superior derecha libre del mapa
            // Landscape: esquina superior izquierda del panel lateral
            left:        rsp.isLandscape ? bottomSheet.left : undefined
            leftMargin:  rsp.isLandscape ? units.gu(1.5)    : 0
            right:       rsp.isLandscape ? undefined         : parent.right
            rightMargin: rsp.isLandscape ? 0                 : units.gu(1.5)
            top:         parent.top
            topMargin:   navBarHeight + units.gu(1)
        }
        width: units.gu(5.5); height: units.gu(5.5); radius: width / 2
        color: "#CC1C1C2E"
        border.color: "#90A4AE"; border.width: units.gu(0.12)
        Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: ts(2.2) }
        MouseArea { anchors.fill: parent; onClicked: rsp.closed() }
    }

    // Altura del panel para que Main.qml ajuste el centro del mapa.
    // En landscape: 0 (panel lateral, no tapa el mapa). En portrait: fórmula directa (no layout-dependent).
    // IMPORTANTE: NO usar bottomSheet.height — se calcula en el pase de layout, demasiado tarde para
    // routeViewPanel.open() que lo lee en el mismo tick JS en que se setean las rutas.
    property real sheetHeight: isLandscape ? 0
                                           : Math.min(units.gu(18 + 8 * routes.length), parent.height * 0.62)

    // ── Panel: landscape = lateral derecho; portrait = bottom sheet ──────────
    Rectangle {
        id: bottomSheet
        // Landscape: panel lateral derecho (mapa visible a la izquierda)
        // Portrait:  bottom sheet con altura máxima del 62% de pantalla
        anchors {
            left:   rsp.isLandscape ? undefined   : parent.left
            right:  parent.right
            bottom: parent.bottom
            top:    rsp.isLandscape ? parent.top  : undefined
        }
        width:  rsp.isLandscape ? Math.round(parent.width * 0.42) : parent.width
        height: rsp.isLandscape ? parent.height : rsp.sheetHeight
        color: "#EE07111E"

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.12); color: "#29B6F6"; opacity: 0.5
        }

        // ── Área scrollable: vehículos + rutas ───────────────────────────────
        Flickable {
            id: routeFlick
            anchors {
                left: parent.left; right: parent.right
                top: parent.top; bottom: startBtn.top
                leftMargin: units.gu(2); rightMargin: units.gu(2)
                topMargin: units.gu(1.5); bottomMargin: units.gu(1)
            }
            contentHeight: sheetCol.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            clip: true

            Column {
                id: sheetCol
                width: routeFlick.width
                spacing: units.gu(1)

                // ── Selector de vehículo ──────────────────────────────
                Flickable {
                    width: parent.width; height: units.gu(4.5)
                    contentWidth: _vehRow.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick
                    clip: true
                    visible: rsp._vehList.length > 0

                    Row {
                        id: _vehRow
                        spacing: units.gu(0.8)
                        Repeater {
                            model: rsp._vehList
                            delegate: Rectangle {
                                property bool _sel: rsp._activeId === modelData.id
                                height: units.gu(4.5)
                                width: Math.max(units.gu(9), _pillLbl.implicitWidth + units.gu(2.6))
                                radius: height / 2
                                color:  _sel ? "#1E3A5F" : "#1C1C2E"
                                border.color: _sel ? "#29B6F6" : "#37474F"
                                border.width: units.gu(0.15)
                                opacity: rsp._recalculating ? 0.55 : 1.0
                                Label {
                                    id: _pillLbl
                                    anchors.centerIn: parent
                                    text: (_sel ? "✓ " : "") + modelData.alias
                                    color: _sel ? "#29B6F6" : "#90A4AE"
                                    font.pixelSize: ts(1.8); font.bold: _sel
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !rsp._recalculating && !_sel
                                    onClicked: {
                                        rsp._activeId = modelData.id
                                        rsp._recalculating = true
                                        rsp.vehicleChangeRequested(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                Label {
                    text: i18n.tr("Rutas disponibles")
                    color: "#90A4AE"; font.pixelSize: ts(1.8)
                }

                Repeater {
                    model: rsp.routes
                    delegate: Rectangle {
                        width: parent.width; height: units.gu(7)
                        radius: units.gu(0.8)
                        color: rsp.selIdx === index ? "#1E3A5F" : "#1C1C2E"
                        border.color: rsp.selIdx === index ? "#29B6F6" : "transparent"
                        border.width: units.gu(0.2)

                        Rectangle {
                            anchors { left: parent.left; leftMargin: units.gu(1.2)
                                      verticalCenter: parent.verticalCenter }
                            width: units.gu(0.5); height: units.gu(3.5); radius: width / 2
                            color: rsp.selIdx === index ? "#29B6F6" : "#546E7A"
                        }

                        Column {
                            anchors { left: parent.left; leftMargin: units.gu(3)
                                      verticalCenter: parent.verticalCenter }
                            spacing: units.gu(0.3)
                            Label {
                                text: index === 0 ? i18n.tr("Ruta más rápida")
                                                  : i18n.tr("Alternativa ") + index
                                color: rsp.selIdx === index ? "#29B6F6" : "white"
                                font.pixelSize: ts(1.8); font.bold: rsp.selIdx === index
                            }
                            Label {
                                text: NavSearch.formatDist(modelData.length) + "  ·  "
                                      + NavSearch.formatTime(modelData.time)
                                color: rsp.selIdx === index ? "#90CAF9" : "#78909C"
                                font.pixelSize: ts(1.8)
                            }
                        }

                        Label {
                            anchors { right: parent.right; rightMargin: units.gu(1.5)
                                      verticalCenter: parent.verticalCenter }
                            visible: rsp.selIdx === index
                            text: "✓"; color: "#29B6F6"; font.pixelSize: ts(2.2)
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: { rsp.selIdx = index; rsp.routeSelected(index) }
                        }
                    }
                }
            }
        }

        // ── Botón INICIAR: siempre visible, fuera del scroll ─────────────────
        Rectangle {
            id: startBtn
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                      leftMargin: units.gu(2); rightMargin: units.gu(2); bottomMargin: units.gu(1.5) }
            height: units.gu(5.5)
            radius: units.gu(0.8); color: "#2E7D32"
            Label {
                anchors.centerIn: parent
                text: "▶  " + i18n.tr("INICIAR NAVEGACIÓN")
                color: "white"; font.pixelSize: ts(1.8); font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                onClicked: rsp.navigationRequested(rsp.selIdx)
            }
        }
    }
}
