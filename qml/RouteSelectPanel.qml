import QtQuick 2.7
import QtQuick.Controls 2.15
import "NavSearch.js" as NavSearch

Item {
    id: rsp
    property real textScale: 1.0
    // Mismo 1.5x que el buscador: esta pantalla se mira parado, para decidir
    // por donde ir. De los nueve usos de ts() ocho son font.pixelSize; el otro
    // es la estimacion del alto del panel, que precisamente tiene que crecer
    // con el texto.
    readonly property real textFactor: 1.5
    function ts(v) { return units.gu(v * textScale * textFactor) }
    anchors.fill: parent
    visible: false
    z: 26

    property real navBarHeight:  0
    property bool isLandscape:   false
    property var  routes:        []
    property int  selIdx:        0
    property bool imperial:      false
    property var  radarCounts:   []   // nº radares por ruta, paralelo a routes (-1 = cargando/error)
    // Salida elegida en el buscador, en milisegundos; 0 es «ahora».
    property double departureMs: 0

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
        // Siempre sobre el mapa, pegado al panel: en portrait encima del
        // bottom sheet, en landscape a la izquierda del panel lateral.
        //
        // Posicion con x/y, no con anclas: ver la nota del panel de abajo.
        // Aqui pasaba lo mismo —quedaban puestas left y right a la vez—, asi
        // que en landscape el boton se estiraba de lado a lado y la ✕, centrada
        // en el, aparecia en mitad de la pantalla. Dentro del panel tampoco
        // cabe: lo primero que hay ahi es la fila de vehiculos, que ademas se
        // desplaza con el dedo. Y estando declarado antes que el panel, el
        // panel lo tapaba entero; de ahi tambien el z.
        x: rsp.isLandscape ? bottomSheet.x - width - units.gu(1.5)
                           : parent.width - width - units.gu(1.5)
        y: rsp.navBarHeight + units.gu(1)
        z: 1
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
    // Es una ESTIMACION, solo para encuadrar el mapa. Quedarse corto o pasarse
    // un poco solo sube o baja el trazado; el panel se mide aparte, abajo.
    // Lo que Main.qml usa para encuadrar el mapa. Se prefiere el alto REAL del
    // contenido; la formula solo vale para el primer tick, cuando todavia no ha
    // habido pase de layout y _altoContenido no significa nada.
    //
    // Con la formula mandando, tres rutas alternativas daban un panel mas alto
    // de lo estimado y la ruta se quedaba dibujada por detras.
    readonly property real _estimado: ts(13 + 7 * routes.length)
    property real sheetHeight: isLandscape ? 0
                                           : Math.min(_altoContenido > units.gu(10)
                                                      ? _altoContenido : _estimado,
                                                      parent.height * 0.75)

    // Lo que el panel le quita al mapa por la derecha. El equivalente lateral de
    // sheetHeight: en portrait tapa por abajo y no por los lados, en landscape
    // al reves. Lo lee Main.qml para que RouteViewPanel encuadre la ruta en el
    // trozo de mapa que queda a la vista y no por debajo del panel.
    readonly property real sheetWidth: isLandscape ? Math.round(width * 0.42) : 0

    // Lo que pide de verdad el contenido, que es lo que mide el panel. Esto SI
    // puede mirar el layout, porque solo lo usa el propio panel; sheetHeight no,
    // que Main.qml la lee en el mismo tick en que asigna las rutas, antes de que
    // haya pase de layout.
    readonly property real _altoContenido:
        sheetCol.implicitHeight + startBtn.height + units.gu(4)

    // ── Panel: landscape = lateral derecho; portrait = bottom sheet ──────────
    Rectangle {
        id: bottomSheet
        // Landscape: panel lateral derecho (mapa visible a la izquierda)
        // Portrait:  bottom sheet con altura máxima del 62% de pantalla
        //
        // NO se usa `anchors.left: cond ? x : undefined`. Una vez que un ancla
        // esta puesta, reevaluar su expresion a undefined NO la quita (Qt 6.8,
        // comprobado aparte). En landscape quedaban left Y right a la vez, que
        // mandan sobre width, y el panel salia a pantalla completa: tapaba el
        // mapa entero y la ruta solo se adivinaba por detras. Con solo right y
        // bottom no hay conflicto y width manda.
        anchors.right:  parent.right
        anchors.bottom: parent.bottom
        width:  rsp.isLandscape ? rsp.sheetWidth : parent.width
        // El alto es el del contenido, ni mas ni menos: con la formula mandando
        // sobraba hueco entre la ultima ruta y el boton. El tope del 75% deja
        // que la lista se desplace cuando hay varias alternativas.
        height: rsp.isLandscape
                ? parent.height
                : Math.min(rsp._altoContenido, parent.height * 0.75)
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
                                      + "  ·  " + i18n.tr("llega ")
                                      + NavSearch.formatArrival(rsp.departureMs, modelData.time)
                                      + (index < rsp.radarCounts.length && rsp.radarCounts[index] >= 0
                                         ? "  ·  📷 " + rsp.radarCounts[index] : "")
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
