import QtQuick 2.7
import QtQuick.Controls 2.15
import Qt.labs.settings 1.0

Rectangle {
    id: panel
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    color: "#F2000000"

    // ── API ───────────────────────────────────────────────────────────────
    property var    cfg
    property var    ttsRef: null
    property var    trackerRef: null
    property var    vehicleMgr: null
    property bool   simSignalLost: false
    property bool   simFinished:   true
    property int    simSegIdx:     0
    property bool   navius:        false
    property string navMapStyles:  '["positron","bright","fiord","dark"]'

    readonly property var _mapStyleModes: {
        var base = [
            { key: "auto",      icon: "🗺",  label: i18n.tr("Auto")     },
            { key: "satellite", icon: "🛰",  label: i18n.tr("Satélite") }
        ]
        var extra = navius ? JSON.parse(navMapStyles) : ["positron", "bright"]
        var icons  = { positron: "☀", bright: "🌐", fiord: "🌊", dark: "🌙" }
        var labels = { positron: i18n.tr("Claro"), bright: i18n.tr("Vivo"),
                       fiord: i18n.tr("Fiord"),   dark: i18n.tr("Noche") }
        for (var i = 0; i < extra.length; i++)
            base.push({ key: extra[i], icon: icons[extra[i]] || "🗺",
                        label: labels[extra[i]] || extra[i] })
        return base
    }

    signal closed()
    signal soundTest(string mode, string context)
    signal langChanged(string lang)
    signal lightModeApplied()
    signal simToggled(bool active)
    signal signalLostToggled()
    signal debugOff()
    signal debugOn()
    signal debugFileDeleteRequested(string pattern)
    signal simRouteChanged(int idx)
    signal manualPosApplied(real lat, real lon)
    signal manualPosCleared()
    signal voicesRequested()
    signal voiceSelected(string voiceId)
    signal voicePicoSelected(string voiceId)
    signal voiceEspeakSelected(string voiceId)
    signal trackSimRequested(string trackId, string trackName, bool raw)
    signal trackGpxRequested(string trackId)
    signal trackAddToSim(string trackId, string trackName)
    signal trackRemovedFromSim(int simIdx)
    property bool ttsProcessing: false
    signal engineChanged(string engine)

    property real _kbdH: Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0
    Behavior on _kbdH { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    property Item _kbdFocusItem: null
    signal clearLiveCacheRequested()
    signal mapCacheClearRequested()
    signal googleMapsCacheClearRequested()
    signal allTracksClearRequested()
    signal osmScoutDetectRequested()

    property bool osmScoutActive: false

    // ── Estado secciones colapsables (persistido) ─────────────────────────
    Settings {
        id: secSettings
        category: "PrefPanelSections"
        property bool quick:      true
        property bool general:    false
        property bool servidor:   false
        property bool nav:        false
        property bool grabacion:  false
        property bool voz:        false
        property bool media:      false
        property bool cuenta:     false
        property bool privacidad: false
        property bool ayuda:      false
        property bool debug:      false
    }

    Settings {
        id: tourSt
        category: "tour"
        property bool showOnStart: true
    }

    signal helpRequested()
    signal loginRequested()
    signal logoutRequested()
    signal privacyBannerRequested()

    Settings {
        id: authSettings
        category: "auth"
        property string token: ""
        property string email: ""
    }
    signal aboutRequested()
    signal tourRequested()

    QtObject {
        id: pal
        readonly property bool isDark: !panel.cfg || panel.cfg.lightMode !== "day"

        readonly property color bgPanel:    isDark ? "#0D0D1A" : "#F5F5F5"
        readonly property color bgCard:     isDark ? "#1C1C2E" : "#FFFFFF"
        readonly property color bgHeader:   isDark ? "#1E1E30" : "#E8E8E8"
        readonly property color fgPrimary:  isDark ? "#FFFFFF"  : "#111111"
        readonly property color fgSecondary:isDark ? "#90A4AE" : "#757575"
        readonly property color bgInput:    isDark ? "#252540" : "#EEEEEE"
        readonly property color bgInputAlt: isDark ? pal.bgInput : "#E0E0E0"
        readonly property color bgBtn:      isDark ? "#37474F" : "#BDBDBD"
        readonly property color highlight:  isDark ? "#252540" : "#E3F2FD"
        readonly property color divider:    isDark ? pal.bgInput : "#DDDDDD"
        readonly property color fgData:     isDark ? "#ECEFF1" : "#212121"
        readonly property color fgDataSub:  isDark ? "#B0BEC5" : "#616161"
        readonly property color accent:     "#29B6F6"
        readonly property color bgSelBlue:  isDark ? "#1E3A5F" : "#BBDEFB"
        readonly property color bgSelGreen: isDark ? "#1A3A1A" : "#C8E6C9"
    }


    // ── Background ────────────────────────────────────────────────────────
    Rectangle { anchors.fill: parent; color: pal.bgPanel }

    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(6); color: pal.bgCard

        Label {
            anchors.centerIn: parent
            text: i18n.tr("Ajustes"); color: pal.fgPrimary
            font.pixelSize: units.gu(2.5); font.bold: true
        }

        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter
                      rightMargin: units.gu(2) }
            width: units.gu(4); height: units.gu(4)
            radius: width / 2; color: pal.bgInputAlt
            Label { anchors.centerIn: parent; text: "✕"; color: pal.fgSecondary; font.pixelSize: ts(1.8) }
            MouseArea { anchors.fill: parent; onClicked: panel.closed() }
        }
    }

    Flickable {
        id: prefsFlick
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.bottomMargin: panel._kbdH
        contentHeight: prefCol.implicitHeight + units.gu(4)
        clip: true

        onHeightChanged: {
            if (!panel._kbdFocusItem || !Qt.inputMethod.visible) return
            var pos        = panel._kbdFocusItem.mapToItem(contentItem, 0, 0)
            var itemTop    = pos.y - units.gu(1)
            var itemBottom = pos.y + panel._kbdFocusItem.height + units.gu(2)
            if (itemBottom > contentY + height)
                contentY = Math.min(itemBottom - height, contentHeight - height)
            else if (itemTop < contentY)
                contentY = Math.max(0, itemTop)
        }

    Column {
        id: prefCol
        anchors { left: parent.left; right: parent.right; leftMargin: units.gu(2); rightMargin: units.gu(2) }
        topPadding: units.gu(2)
        spacing: units.gu(1.5)

        // ── Restaurar valores por defecto ────────────────────────────────
        Rectangle {
            width: parent.width; height: units.gu(5)
            radius: units.gu(1); border.width: 1
            property bool _confirm: false
            property bool _done:    false
            color:        _confirm ? "#1A1200" : pal.bgCard
            border.color: _confirm ? "#F9A825" : (_done ? "#2E7D32" : pal.divider)
            Behavior on color        { ColorAnimation { duration: 120 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }
            Timer { id: resetConfirmTimer; interval: 3000; onTriggered: parent._confirm = false }
            Timer { id: resetDoneTimer;    interval: 3000; onTriggered: parent._done    = false }
            Row {
                anchors.centerIn: parent
                spacing: units.gu(1)
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent._done ? "✓" : (parent.parent._confirm ? "⚠" : "↺")
                    color: parent.parent._done ? "#66BB6A" : (parent.parent._confirm ? "#F9A825" : pal.fgSecondary)
                    font.pixelSize: ts(2.2)
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.parent._done    ? i18n.tr("Restaurado")
                        : parent.parent._confirm ? i18n.tr("Toca de nuevo para confirmar")
                        :                          i18n.tr("Restaurar valores por defecto")
                    color: parent.parent._done ? "#66BB6A" : (parent.parent._confirm ? "#F9A825" : pal.fgSecondary)
                    font.pixelSize: ts(1.75)
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (!panel.cfg) return
                    if (!parent._confirm) {
                        parent._confirm = true
                        resetConfirmTimer.restart()
                        return
                    }
                    // Confirmado: restaurar
                    resetConfirmTimer.stop()
                    parent._confirm = false
                    panel.cfg.lightMode           = "auto"
                    panel.cfg.autoZoom            = true
                    panel.cfg.bearingMode         = "north"
                    panel.cfg.autoZoomSecs        = 15
                    panel.cfg.mapMode             = "2d"
                    panel.cfg.navMapMode          = "3d"
                    panel.cfg.pitch3d             = 60
                    panel.cfg.mapStyleMode        = "auto"
                    panel.cfg.show3dBuildings     = true
                    panel.cfg.showZoomSlider      = false
                    panel.cfg.textScale           = 1.0
                    panel.cfg.uiScale             = 1.0
                    panel.cfg.measureSystem       = "metric"
                    panel.cfg.speedAlertEnabled   = true
                    panel.cfg.speedAlertPct       = 2
                    panel.cfg.showRoadSpeedLimit  = false
                    panel.cfg.showRadarFijos      = true
                    panel.cfg.showRadarTramo      = true
                    panel.cfg.radarAlertDist      = 400
                    panel.cfg.useHardwareSpeed    = true
                    panel.cfg.drEnabled           = true
                    panel.cfg.drHz                = 20
                    panel.cfg.alertSound          = "tts"
                    panel.cfg.instrSound          = "tts"
                    panel.cfg.ttsLang             = "system"
                    panel.cfg.ttsEngine           = "auto"
                    panel.cfg.duckVolume          = 0.70
                    panel.cfg.routeAdjustZoom     = true
                    panel.cfg.routeAheadSecs      = 10
                    panel.cfg.maxPredictiveTurnDeg = 30
                    panel.cfg.snapToRouteEnabled  = true
                    panel.cfg.snapDistM           = 11
                    panel.cfg.offRouteDistM       = 11
                    panel.cfg.inhibitSuspend      = true
                    panel.cfg.preferOsmScout      = true
                    panel.cfg.valhallaUrl         = "https://valhalla.egpsistemas.com"
                    panel.cfg.overpassServer      = "navius"
                    panel.cfg.mapCacheMaxMb       = 500
                    panel.cfg.mapOnlineSource     = "mapbox"
                    panel.cfg.mapOfflineMode      = "cache"
                    panel.cfg.mapTileServer       = "navius"
                    panel.cfg.tracesEnabled       = false
                    panel.cfg.showChangesAtStartup = true
                    parent._done = true
                    resetDoneTimer.restart()
                }
            }
        }

        // ── Nivel de opciones ────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: prefLevelCol.implicitHeight + units.gu(4)
            color: pal.bgCard; radius: 0
            Column {
                id: prefLevelCol
                anchors { fill: parent; margins: units.gu(2) }
                spacing: units.gu(1)
                Label { text: i18n.tr("Nivel de opciones"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                PrefOptionSelector {
                    width: parent.width
                    model: [i18n.tr("Mínimo"), i18n.tr("Medio"), i18n.tr("Avanzado")]
                    selectedIndex: panel.cfg ? panel.cfg.prefLevel : 0
                    containerHeight: units.gu(4.5) * 3
                    onSelectedIndexChanged: if (panel.cfg) panel.cfg.prefLevel = selectedIndex
                }
            }
        }

        // ════════════════════════════════════════════════════════════════
        // AJUSTES RÁPIDOS
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: quickCol.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Ajustes rápidos")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.quick ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.quick = !secSettings.quick }
        }

        Column {
            id: quickCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.quick && hasContent
            width: parent.width; spacing: 0

            // ── Modo de luz ──────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: lightModeCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0

                Column {
                    id: lightModeCol
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1.5)

                    Label { text: i18n.tr("Modo de luz"); color: pal.fgSecondary; font.pixelSize: ts(1.8) }

                    PrefOptionSelector {
                        width: parent.width
                        property var _keys: ["day", "night", "auto"]
                        model: ["☀ " + i18n.tr("Día"), "☽ " + i18n.tr("Noche"), "⊙ " + i18n.tr("Auto") + " ↺"]
                        selectedIndex: {
                            if (!panel.cfg) return 2
                            return _keys.indexOf(panel.cfg.lightMode) >= 0 ? _keys.indexOf(panel.cfg.lightMode) : 2
                        }
                        containerHeight: units.gu(4.5) * 3
                        onSelectedIndexChanged: {
                            if (!panel.cfg) return
                            panel.cfg.lightMode = _keys[selectedIndex]
                            panel.lightModeApplied()
                        }
                    }
                }
            }

            // ── Estilo de mapa ───────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: styleCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0

                Column {
                    id: styleCol
                    anchors { top: parent.top; left: parent.left; right: parent.right
                              margins: units.gu(2); topMargin: units.gu(2) }
                    spacing: units.gu(1)

                    Label { text: i18n.tr("Estilo de mapa"); color: pal.fgSecondary; font.pixelSize: ts(1.8) }

                    PrefOptionSelector {
                        width: parent.width
                        property var _modes: panel._mapStyleModes
                        model: {
                            var labels = []
                            for (var i = 0; i < _modes.length; i++)
                                labels.push(_modes[i].icon + " " + _modes[i].label + (_modes[i].key === "auto" ? " ↺" : ""))
                            return labels
                        }
                        selectedIndex: {
                            if (!panel.cfg) return 0
                            for (var i = 0; i < _modes.length; i++)
                                if (_modes[i].key === panel.cfg.mapStyleMode) return i
                            return 0
                        }
                        containerHeight: units.gu(4.5) * 8
                        onSelectedIndexChanged: {
                            if (panel.cfg) panel.cfg.mapStyleMode = _modes[selectedIndex].key
                        }
                    }
                }
            }

            // ── Vehículos ────────────────────────────────────────────────
            Rectangle {
                id: vehiclesSection
                width: parent.width
                color: pal.bgCard; radius: 0
                height: vehCol.implicitHeight + units.gu(4)

                property bool _addMode: false
                property int  _newTypeIdx: 0
                readonly property var _typeList: [
                    { label: i18n.tr("Coche"),     value: "auto"          },
                    { label: i18n.tr("Moto"),      value: "motorcycle"    },
                    { label: i18n.tr("Scooter"),   value: "motor_scooter" },
                    { label: i18n.tr("Camión"),    value: "truck"         },
                    { label: i18n.tr("Bicicleta"), value: "bicycle"       }
                ]

                Column {
                    id: vehCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1.2)

                    Row {
                        width: parent.width
                        Label {
                            text: "🚗 " + i18n.tr("Vehículos")
                            font.pixelSize: ts(2.2); font.bold: true; color: "#29B6F6"
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - addVehBtn.width
                        }
                        Rectangle {
                            id: addVehBtn
                            width: units.gu(11); height: units.gu(5); radius: height / 2
                            color: vehiclesSection._addMode ? pal.bgSelGreen : pal.bgInput
                            border.color: "#4CAF50"; border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Label {
                                anchors.centerIn: parent
                                text: vehiclesSection._addMode ? i18n.tr("Cancelar") : i18n.tr("+ Añadir")
                                color: "#4CAF50"; font.pixelSize: ts(1.9)
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    vehiclesSection._addMode = !vehiclesSection._addMode
                                    vehiclesSection._newTypeIdx = 0
                                }
                            }
                        }
                    }

                    Repeater {
                        model: panel.vehicleMgr.allVehicles()
                        delegate: Rectangle {
                            id: vehDelegate
                            width: parent.width; height: units.gu(6.5)
                            radius: units.gu(0.7)
                            color: modelData.id === panel.cfg.activeVehicleId ? pal.bgSelBlue : pal.bgCard
                            border.color: modelData.id === panel.cfg.activeVehicleId ? "#29B6F6" : pal.divider
                            border.width: modelData.id === panel.cfg.activeVehicleId ? 2 : 1
                            property bool _askDel: false

                            Row {
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(1.5); rightMargin: units.gu(1)
                                }
                                spacing: units.gu(1)

                                Rectangle {
                                    width: units.gu(1.2); height: units.gu(1.2); radius: width / 2
                                    color: modelData.id === panel.cfg.activeVehicleId ? "#29B6F6" : "transparent"
                                    border.color: "#29B6F6"; border.width: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(1.2) - units.gu(1) - delVehBtn.width - units.gu(1)
                                    Label {
                                        text: modelData.alias; color: pal.fgData
                                        font.pixelSize: ts(2.1)
                                        wrapMode: Text.NoWrap; elide: Text.ElideRight; width: parent.width
                                    }
                                    Label {
                                        text: panel.vehicleMgr.costingLabel(modelData.costing)
                                              + (modelData.hasPark && modelData.costing !== "pedestrian" ? "  🅿" : "")
                                        color: pal.fgDataSub; font.pixelSize: ts(2.1)
                                        wrapMode: Text.NoWrap; elide: Text.ElideRight; width: parent.width
                                    }
                                }
                                Item {
                                    id: delVehBtn
                                    visible: modelData.costing !== "pedestrian"
                                             && panel.vehicleMgr.allVehicles().length > 2
                                    width: vehDelegate._askDel ? units.gu(14) : units.gu(7)
                                    height: units.gu(4.5)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        visible: !vehDelegate._askDel
                                        anchors.fill: parent; radius: height / 2
                                        color: "#3A1414"; border.color: "#EF5350"; border.width: 1
                                        Label {
                                            anchors.centerIn: parent; text: i18n.tr("Borrar")
                                            color: "#EF5350"; font.pixelSize: ts(1.7)
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: vehDelegate._askDel = true
                                        }
                                    }
                                    Row {
                                        visible: vehDelegate._askDel
                                        anchors.fill: parent; spacing: units.gu(0.5)
                                        Rectangle {
                                            width: (parent.width - units.gu(0.5)) / 2; height: parent.height
                                            radius: height / 2
                                            color: "#3A1414"; border.color: "#EF5350"; border.width: 1
                                            Label {
                                                anchors.centerIn: parent; text: i18n.tr("Sí")
                                                color: "#EF5350"; font.pixelSize: ts(1.7)
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    vehDelegate._askDel = false
                                                    panel.vehicleMgr.removeVehicle(modelData.id)
                                                }
                                            }
                                        }
                                        Rectangle {
                                            width: (parent.width - units.gu(0.5)) / 2; height: parent.height
                                            radius: height / 2
                                            color: pal.bgInput; border.color: pal.fgSecondary; border.width: 1
                                            Label {
                                                anchors.centerIn: parent; text: i18n.tr("No")
                                                color: pal.fgSecondary; font.pixelSize: ts(1.7)
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: vehDelegate._askDel = false
                                            }
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                onClicked: panel.vehicleMgr.setActive(modelData.id)
                            }
                        }
                    }

                    Column {
                        visible: vehiclesSection._addMode
                        width: parent.width; spacing: units.gu(1)

                        Label { text: i18n.tr("Nombre"); color: pal.fgSecondary; font.pixelSize: ts(1.7) }
                        Rectangle {
                            width: parent.width; height: units.gu(5)
                            color: pal.bgInput; radius: units.gu(0.7)
                            border.color: newVehName.activeFocus ? "#29B6F6" : pal.divider; border.width: 1
                            NavTextInput {
                                id: newVehName
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: units.gu(1.2); rightMargin: units.gu(1.2)
                                }
                                text: "Mi vehículo"; color: pal.fgData; font.pixelSize: ts(2.0)
                                selectionColor: "#29B6F6"
                                onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                            }
                        }
                        Label { text: i18n.tr("Tipo"); color: pal.fgSecondary; font.pixelSize: ts(1.7) }
                        Flow {
                            width: parent.width; spacing: units.gu(0.6)
                            Repeater {
                                model: vehiclesSection._typeList
                                Rectangle {
                                    width: (vehCol.width - 2 * units.gu(0.6)) / 3
                                    height: units.gu(5); radius: height / 2
                                    color:  vehiclesSection._newTypeIdx === index ? "#29B6F6" : pal.bgInput
                                    border.color: "#29B6F6"; border.width: 1
                                    Label {
                                        anchors.centerIn: parent; text: modelData.label
                                        color: vehiclesSection._newTypeIdx === index ? "#0A0A1A" : pal.fgSecondary
                                        font.pixelSize: ts(1.8)
                                        font.bold: vehiclesSection._newTypeIdx === index
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: vehiclesSection._newTypeIdx = index
                                    }
                                }
                            }
                        }
                        Rectangle {
                            width: units.gu(16); height: units.gu(5.5); radius: height / 2; color: "#29B6F6"
                            Label {
                                anchors.centerIn: parent; text: i18n.tr("Crear vehículo")
                                color: "#0A0A1A"; font.pixelSize: ts(2.0); font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var name = newVehName.text.trim()
                                    if (name.length === 0) return
                                    var id = panel.vehicleMgr.addVehicle(
                                        name,
                                        vehiclesSection._typeList[vehiclesSection._newTypeIdx].value)
                                    panel.vehicleMgr.setActive(id)
                                    vehiclesSection._addMode = false
                                    newVehName.text = "Mi vehículo"
                                }
                            }
                        }
                    }
                }
            }
        } // Column Ajustes rápidos

        // ════════════════════════════════════════════════════════════════
        // GENERAL
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: generalCol.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("General")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.general ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.general = !secSettings.general }
        }

        Column {
            id: generalCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.general && hasContent
            width: parent.width; spacing: 0

            // ── Tamaño de texto ──────────────────────────────────────────
            Rectangle {
                width: parent.width; height: tsCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: tsCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Item {
                        width: parent.width; height: units.gu(3)
                        Label {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Tamaño de texto"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        }
                        Label {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: panel.cfg ? (Math.round(panel.cfg.textScale * 100) + " %  ↺ 100 %") : "100 %"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                        }
                    }
                    Slider {
                        width: parent.width
                        from: 0.70; to: 1.50; stepSize: 0.05; live: true
                        value: panel.cfg ? panel.cfg.textScale : 1.0
                        onValueChanged: if (panel.cfg) panel.cfg.textScale = Math.round(value / 0.05) * 0.05
                    }
                }
            }

            // ── Escala de interfaz ───────────────────────────────────────
            // Multiplica el grid unit (units.gu) → afecta a TODO: texto,
            // botones, márgenes. El valor base se calcula al arrancar a partir
            // del tamaño de pantalla para reproducir la escala de Ubuntu Touch
            // (ver src/i18n_units.rs); esto es solo el ajuste fino del usuario.
            // Los bindings de gu() no se re-evalúan en caliente → hace falta
            // reiniciar la app para que se aplique.
            Rectangle {
                width: parent.width; height: uiScaleCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: uiScaleCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Item {
                        width: parent.width; height: units.gu(3)
                        Label {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Escala de interfaz"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        }
                        Label {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: panel.cfg ? (Math.round(panel.cfg.uiScale * 100) + " %  ↺ 100 %") : "100 %"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                        }
                    }
                    Slider {
                        id: uiScaleSlider
                        width: parent.width
                        from: 0.60; to: 2.00; stepSize: 0.05; live: true
                        value: panel.cfg ? panel.cfg.uiScale : 1.0
                        onValueChanged: if (panel.cfg) panel.cfg.uiScale = Math.round(value / 0.05) * 0.05
                    }
                    Label {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: i18n.tr("Se aplica al reiniciar la aplicación") +
                              (units.grid_unit_px ? "  (1 gu = " + units.grid_unit_px.toFixed(1) + " px)" : "")
                        color: pal.fgSecondary; font.pixelSize: ts(1.5)
                    }
                }
            }

            // ── Sistema de unidades ──────────────────────────────────────
            Rectangle {
                width: parent.width
                height: medCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: medCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(0.8)
                    Label { text: i18n.tr("Sistema de medidas"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                    PrefOptionSelector {
                        width: parent.width
                        model: [i18n.tr("Métrico") + "  (km, m) ↺", i18n.tr("Imperial") + "  (mi, ft)"]
                        selectedIndex: panel.cfg && panel.cfg.measureSystem === "imperial" ? 1 : 0
                        containerHeight: units.gu(4.5) * 2
                        onSelectedIndexChanged: {
                            if (panel.cfg) panel.cfg.measureSystem = selectedIndex === 0 ? "metric" : "imperial"
                        }
                    }
                }
            }

            // ── Mostrar novedades al inicio ──────────────────────────────
            PrefListItem {
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Mostrar novedades al inicio")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Pantalla de cambios en cada deploy") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swShowChangesAtStartup
                    checked: panel.cfg ? panel.cfg.showChangesAtStartup : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.showChangesAtStartup = checked
                }
            }
        } // Column General

        // ════════════════════════════════════════════════════════════════
        // SERVIDOR DE RUTAS
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: srvColContent.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Servidor de rutas")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.servidor ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.servidor = !secSettings.servidor }
        }

        Column {
            id: srvColContent
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.servidor && hasContent
            width: parent.width; spacing: 0

            Rectangle {
                id: vhSection
                width: parent.width
                color: pal.bgCard; radius: 0
                height: vhCol.implicitHeight + units.gu(4)

                property var _custom: {
                    try { return JSON.parse(panel.cfg ? panel.cfg.valhallaCustomServers : "[]") }
                    catch(e) { return [] }
                }
                property bool _showForm: false

                function _setUrl(url) { if (panel.cfg) panel.cfg.valhallaUrl = url }
                function _saveCustom(lst) {
                    if (!panel.cfg) return
                    panel.cfg.valhallaCustomServers = JSON.stringify(lst)
                }

                Column {
                    id: vhCol
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    y: units.gu(2)
                    spacing: units.gu(1.2)

                    Label { text: i18n.tr("Servidor de rutas"); color: pal.fgSecondary; font.pixelSize: ts(1.8) }

                    // Toggle: preferir OSM Scout
                    Item {
                        width: parent.width; height: osmScoutToggleCol.implicitHeight
                        Switch {
                            id: swPreferOsmScout
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            checked: panel.cfg ? panel.cfg.preferOsmScout : false
                            onCheckedChanged: if (panel.cfg) panel.cfg.preferOsmScout = checked
                        }
                        Column {
                            id: osmScoutToggleCol
                            anchors { left: parent.left; right: swPreferOsmScout.left; rightMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                            Label { text: i18n.tr("Preferir OSM Scout Server si disponible"); color: pal.fgPrimary; font.pixelSize: ts(1.8); wrapMode: Text.WordWrap; width: parent.width }
                            Label { text: i18n.tr("Enrutamiento offline · se detecta al arrancar") + "  · ↺ act."; color: pal.fgSecondary; font.pixelSize: ts(1.6); wrapMode: Text.WordWrap; width: parent.width }
                        }
                    }

                    // OSM Scout Server (dispositivo)
                    Rectangle {
                        width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                        color: panel.cfg && panel.cfg.valhallaUrl === "http://127.0.0.1:8553/v2" ? pal.bgSelBlue : pal.bgInput
                        Row {
                            anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                            spacing: units.gu(1)
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - units.gu(10)
                                Label { text: "OSM Scout Server (dispositivo)"; color: pal.fgPrimary; font.pixelSize: ts(1.8); font.bold: true }
                                Label {
                                    text: panel.osmScoutActive ? "✓ activo · puerto 8553 · offline" : "✗ no detectado · puerto 8553"
                                    color: panel.osmScoutActive ? "#66BB6A" : "#EF5350"
                                    font.pixelSize: ts(1.5)
                                }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: units.gu(8.5); height: units.gu(3.5); radius: units.gu(0.8); color: "#263238"
                                Label { anchors.centerIn: parent; text: i18n.tr("Detectar"); color: "#29B6F6"; font.pixelSize: ts(1.6) }
                                MouseArea { anchors.fill: parent; onClicked: panel.osmScoutDetectRequested() }
                            }
                        }
                        MouseArea {
                            anchors { fill: parent; rightMargin: units.gu(10) }
                            onClicked: vhSection._setUrl("http://127.0.0.1:8553/v2")
                        }
                    }

                    // valhalla.egpsistemas.com (servidor principal)
                    Rectangle {
                        width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                        color: panel.cfg && panel.cfg.valhallaUrl === "https://valhalla.egpsistemas.com" ? pal.bgSelBlue : pal.bgInput
                        Row {
                            anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; width: parent.width
                                Label { text: i18n.tr("Servidor Navius"); color: pal.fgPrimary; font.pixelSize: ts(1.8); font.bold: true }
                                Label { text: "https://valhalla.egpsistemas.com · servidor propio"; color: pal.fgSecondary; font.pixelSize: ts(1.5) }
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: vhSection._setUrl("https://valhalla.egpsistemas.com") }
                    }

                    // OpenStreetMap.de
                    Rectangle {
                        width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                        color: panel.cfg && panel.cfg.valhallaUrl === "https://valhalla1.openstreetmap.de" ? pal.bgSelBlue : pal.bgInput
                        Row {
                            anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter; width: parent.width
                                Label { text: "OpenStreetMap.de"; color: pal.fgPrimary; font.pixelSize: ts(1.8); font.bold: true }
                                Label { text: "https://valhalla1.openstreetmap.de · gratuito online"; color: pal.fgSecondary; font.pixelSize: ts(1.5) }
                            }
                        }
                        MouseArea { anchors.fill: parent; onClicked: vhSection._setUrl("https://valhalla1.openstreetmap.de") }
                    }

                    // Servidores personalizados
                    Repeater {
                        model: vhSection._custom
                        Rectangle {
                            width: vhCol.width; height: units.gu(5.5); radius: units.gu(0.8)
                            color: panel.cfg && panel.cfg.valhallaUrl === modelData.url ? pal.bgSelBlue : pal.bgInput
                            Row {
                                anchors { fill: parent; leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                                spacing: units.gu(1)
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(5)
                                    Label { text: modelData.label; color: pal.fgPrimary; font.pixelSize: ts(1.8); font.bold: true; elide: Text.ElideRight; width: parent.width }
                                    Label { text: modelData.url;   color: pal.fgSecondary; font.pixelSize: ts(1.5); elide: Text.ElideRight; width: parent.width }
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(3.5); height: units.gu(3.5); radius: width / 2; color: pal.bgBtn
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.8) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            var lst = vhSection._custom.slice()
                                            var delUrl = lst[index].url
                                            lst.splice(index, 1)
                                            vhSection._saveCustom(lst)
                                            if (panel.cfg && panel.cfg.valhallaUrl === delUrl)
                                                vhSection._setUrl("https://valhalla1.openstreetmap.de")
                                        }
                                    }
                                }
                            }
                            MouseArea {
                                anchors { fill: parent; rightMargin: units.gu(5) }
                                onClicked: vhSection._setUrl(modelData.url)
                            }
                        }
                    }

                    // Botón añadir servidor
                    Rectangle {
                        visible: !vhSection._showForm
                        width: parent.width; height: units.gu(4.5); radius: units.gu(0.8); color: pal.bgInputAlt
                        Label { anchors.centerIn: parent; text: "+ " + i18n.tr("Añadir servidor"); color: "#29B6F6"; font.pixelSize: ts(1.8) }
                        MouseArea { anchors.fill: parent; onClicked: vhSection._showForm = true }
                    }

                    // Formulario añadir servidor
                    Column {
                        visible: vhSection._showForm
                        width: parent.width; spacing: units.gu(1)

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.8); color: pal.bgInputAlt
                            Label {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(1.5) }
                                text: i18n.tr("Nombre (ej. Mi servidor)"); color: pal.fgSecondary; font.pixelSize: ts(1.8)
                                visible: vhLabelIn.text.length === 0
                            }
                            NavTextInput {
                                id: vhLabelIn
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(1.5) }
                                color: pal.fgPrimary; font.pixelSize: ts(1.8); selectionColor: "#29B6F6"
                                onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                            }
                        }

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.8); color: pal.bgInputAlt
                            Label {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(1.5) }
                                text: "https://mi-valhalla.local"; color: pal.fgSecondary; font.pixelSize: ts(1.8)
                                visible: vhUrlIn.text.length === 0
                            }
                            NavTextInput {
                                id: vhUrlIn
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(1.5) }
                                color: pal.fgPrimary; font.pixelSize: ts(1.8); selectionColor: "#29B6F6"
                                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
                                onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                            }
                        }

                        Row {
                            width: parent.width; spacing: units.gu(1)
                            Rectangle {
                                width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                                color: pal.bgBtn; radius: units.gu(0.8)
                                Label { anchors.centerIn: parent; text: i18n.tr("Cancelar"); color: pal.fgSecondary; font.pixelSize: ts(1.8) }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { vhSection._showForm = false; vhLabelIn.text = ""; vhUrlIn.text = "" }
                                }
                            }
                            Rectangle {
                                width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                                color: vhUrlIn.text.trim().length > 7 ? "#1565C0" : "#263238"
                                radius: units.gu(0.8)
                                Label { anchors.centerIn: parent; text: i18n.tr("Guardar"); color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        var url = vhUrlIn.text.trim()
                                        if (url.length < 8) return
                                        if (url[url.length - 1] === "/") url = url.slice(0, -1)
                                        var lbl = vhLabelIn.text.trim() || url
                                        var lst = vhSection._custom.slice()
                                        lst.push({ label: lbl, url: url })
                                        vhSection._saveCustom(lst)
                                        vhSection._setUrl(url)
                                        vhSection._showForm = false
                                        vhLabelIn.text = ""; vhUrlIn.text = ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // ── Tiles de mapa ─────────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width
                color: pal.bgCard; radius: 0
                height: mapTilesCol.implicitHeight + units.gu(4)

                Column {
                    id: mapTilesCol
                    anchors { left: parent.left; right: parent.right; margins: units.gu(2) }
                    y: units.gu(2)
                    spacing: units.gu(1.5)

                    // ── Mapa online ───────────────────────────────────────
                    Label { text: i18n.tr("Mapa online"); color: pal.fgSecondary; font.pixelSize: ts(1.8) }

                    Row {
                        width: parent.width; spacing: units.gu(1)
                        property string _src: panel.cfg ? panel.cfg.mapOnlineSource : "mapbox"

                        Rectangle {
                            property bool _sel: parent._src === "mapbox"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? pal.bgSelBlue : pal.bgInput
                            border.color: _sel ? "#29B6F6" : pal.divider; border.width: units.gu(0.15)
                            Label {
                                anchors.centerIn: parent
                                text: "Mapbox ↺"
                                color: parent._sel ? "#29B6F6" : pal.fgPrimary
                                font.pixelSize: ts(1.7); font.bold: parent._sel
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapOnlineSource = "mapbox"
                            }
                        }

                        Rectangle {
                            property bool _sel: parent._src === "osmscout"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? pal.bgSelGreen : pal.bgInput
                            border.color: _sel ? "#66BB6A" : pal.divider; border.width: units.gu(0.15)
                            opacity: panel.osmScoutActive ? 1.0 : 0.6
                            Label {
                                anchors.centerIn: parent
                                text: "OSM Scout"
                                color: parent._sel ? "#66BB6A" : pal.fgPrimary
                                font.pixelSize: ts(1.7); font.bold: parent._sel
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapOnlineSource = "osmscout"
                            }
                        }
                    }

                    // ── Servidor de tiles ─────────────────────────────────
                    Label {
                        text: i18n.tr("Servidor de tiles")
                        color: pal.fgSecondary; font.pixelSize: ts(1.8)
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                    }

                    Row {
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                        width: parent.width; spacing: units.gu(1)
                        property string _srv: panel.cfg ? panel.cfg.mapTileServer : "external"

                        Rectangle {
                            property bool _sel: parent._srv === "navius"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? pal.bgSelGreen : pal.bgInput
                            border.color: _sel ? "#66BB6A" : pal.divider; border.width: units.gu(0.15)
                            Column {
                                anchors.centerIn: parent; spacing: units.gu(0.2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Navius ↺"
                                    color: parent.parent._sel ? "#66BB6A" : pal.fgPrimary
                                    font.pixelSize: ts(1.7); font.bold: parent.parent._sel
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "navius-maps"
                                    color: "#607D8B"; font.pixelSize: ts(1.3)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapTileServer = "navius"
                            }
                        }

                        Rectangle {
                            property bool _sel: parent._srv === "external"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? pal.bgSelBlue : pal.bgInput
                            border.color: _sel ? "#29B6F6" : pal.divider; border.width: units.gu(0.15)
                            Column {
                                anchors.centerIn: parent; spacing: units.gu(0.2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: i18n.tr("Externo")
                                    color: parent.parent._sel ? "#29B6F6" : pal.fgPrimary
                                    font.pixelSize: ts(1.7); font.bold: parent.parent._sel
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "OpenFreeMap"
                                    color: "#607D8B"; font.pixelSize: ts(1.3)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapTileServer = "external"
                            }
                        }
                    }

                    // ── Estilo día (solo servidor Navius) ─────────────────
                    Label {
                        text: i18n.tr("Tema de día")
                        color: pal.fgSecondary; font.pixelSize: ts(1.8)
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                                           && panel.cfg.mapTileServer === "navius"
                    }

                    PrefOptionSelector {
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                                           && panel.cfg.mapTileServer === "navius"
                        width: parent.width
                        property var _keys: ["liberty", "positron", "bright", "fiord"]
                        model: ["Liberty", "Positron", "Bright", "Fiord"]
                        selectedIndex: {
                            if (!panel.cfg) return 0
                            var idx = _keys.indexOf(panel.cfg.mapNaviusDayStyle)
                            return idx >= 0 ? idx : 0
                        }
                        containerHeight: units.gu(4.5) * 4
                        onSelectedIndexChanged: {
                            if (panel.cfg) panel.cfg.mapNaviusDayStyle = _keys[selectedIndex]
                        }
                    }

                    // ── Servidor de POIs y radares (Overpass) ────────────
                    Label {
                        text: i18n.tr("Servidor de POIs y radares")
                        color: pal.fgSecondary; font.pixelSize: ts(1.8)
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                    }

                    Row {
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                        width: parent.width; spacing: units.gu(1)
                        property string _srv: panel.cfg ? panel.cfg.overpassServer : "external"

                        Rectangle {
                            property bool _sel: parent._srv === "navius"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? pal.bgSelGreen : pal.bgInput
                            border.color: _sel ? "#66BB6A" : pal.divider; border.width: units.gu(0.15)
                            Column {
                                anchors.centerIn: parent; spacing: units.gu(0.2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Navius"
                                    color: parent.parent._sel ? "#66BB6A" : pal.fgPrimary
                                    font.pixelSize: ts(1.7); font.bold: parent.parent._sel
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "navius-maps"
                                    color: "#607D8B"; font.pixelSize: ts(1.3)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.overpassServer = "navius"
                            }
                        }

                        Rectangle {
                            property bool _sel: parent._srv === "external"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? pal.bgSelBlue : pal.bgInput
                            border.color: _sel ? "#29B6F6" : pal.divider; border.width: units.gu(0.15)
                            Column {
                                anchors.centerIn: parent; spacing: units.gu(0.2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: i18n.tr("Externo") + " ↺"
                                    color: parent.parent._sel ? "#29B6F6" : pal.fgPrimary
                                    font.pixelSize: ts(1.7); font.bold: parent.parent._sel
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "openstreetmap.fr"
                                    color: "#607D8B"; font.pixelSize: ts(1.3)
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.overpassServer = "external"
                            }
                        }
                    }

                    // ── Sin internet ──────────────────────────────────────
                    Label {
                        text: i18n.tr("Sin internet")
                        color: pal.fgSecondary; font.pixelSize: ts(1.8)
                        // solo relevante cuando online source es Mapbox
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                    }

                    Row {
                        width: parent.width; spacing: units.gu(1)
                        visible: panel.cfg && panel.cfg.mapOnlineSource === "mapbox"
                        property string _mode: panel.cfg ? panel.cfg.mapOfflineMode : "cache"

                        Rectangle {
                            property bool _sel: parent._mode === "cache"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? pal.bgSelBlue : pal.bgInput
                            border.color: _sel ? "#29B6F6" : pal.divider; border.width: units.gu(0.15)
                            Label {
                                anchors.centerIn: parent
                                text: i18n.tr("Caché") + " ↺"
                                color: parent._sel ? "#29B6F6" : pal.fgPrimary
                                font.pixelSize: ts(1.7); font.bold: parent._sel
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapOfflineMode = "cache"
                            }
                        }

                        Rectangle {
                            property bool _sel: parent._mode === "osmscout"
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(4.5)
                            radius: units.gu(0.8)
                            color: _sel ? pal.bgSelGreen : pal.bgInput
                            border.color: _sel ? "#66BB6A" : pal.divider; border.width: units.gu(0.15)
                            opacity: panel.osmScoutActive ? 1.0 : 0.6
                            Label {
                                anchors.centerIn: parent
                                text: "OSM Scout"
                                color: parent._sel ? "#66BB6A" : pal.fgPrimary
                                font.pixelSize: ts(1.7); font.bold: parent._sel
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (panel.cfg) panel.cfg.mapOfflineMode = "osmscout"
                            }
                        }
                    }

                    // ── Caché: tamaño + limpiar ───────────────────────────
                    Column {
                        // visible cuando se usa caché (Mapbox online o fallback caché sin internet)
                        visible: panel.cfg && (panel.cfg.mapOnlineSource === "mapbox")
                        width: parent.width; spacing: units.gu(1)

                        Label {
                            text: i18n.tr("Espacio máximo en disco")
                            color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        }

                        PrefOptionSelector {
                            width: parent.width
                            property var _vals: [100, 250, 500, 1000, 2000]
                            model: ["100 MB", "250 MB", "500 MB ↺", "1 GB", "2 GB"]
                            selectedIndex: {
                                if (!panel.cfg) return 2
                                var idx = _vals.indexOf(panel.cfg.mapCacheMaxMb)
                                return idx >= 0 ? idx : 2
                            }
                            containerHeight: units.gu(4.5) * 5
                            onSelectedIndexChanged: {
                                if (panel.cfg) panel.cfg.mapCacheMaxMb = _vals[selectedIndex]
                            }
                        }

                        Rectangle {
                            id: mapCacheBtn
                            width: parent.width; height: units.gu(4.5); radius: units.gu(0.8)
                            color: _confirm ? "#4A1010" : pal.bgInput
                            property bool _confirm: false
                            property bool _done: false
                            Timer { interval: 4000; running: parent._confirm && !parent._done; onTriggered: parent._confirm = false }
                            Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Label {
                                anchors.centerIn: parent
                                text:  mapCacheBtn._done    ? "✓ " + i18n.tr("Caché eliminada")
                                     : mapCacheBtn._confirm ? "⚠ " + i18n.tr("Toca de nuevo para confirmar")
                                     :                        i18n.tr("Limpiar caché de mapas")
                                color: mapCacheBtn._done    ? "#66BB6A"
                                     : mapCacheBtn._confirm ? "#FFCC02"
                                     :                       "#EF5350"
                                font.pixelSize: ts(1.8)
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (mapCacheBtn._confirm) { panel.mapCacheClearRequested(); mapCacheBtn._done = true; mapCacheBtn._confirm = false }
                                    else { mapCacheBtn._confirm = true }
                                }
                            }
                        }

                        Rectangle {
                            id: gmapsCacheBtn
                            // GoogleMapsPanel no existe en este port (QtWebEngine5
                            // no disponible en postmarketOS) — no hay caché que limpiar.
                            visible: false
                            width: parent.width; height: units.gu(4.5); radius: units.gu(0.8)
                            color: _confirm ? "#4A1010" : pal.bgInput
                            property bool _confirm: false
                            property bool _done: false
                            Timer { interval: 4000; running: parent._confirm && !parent._done; onTriggered: parent._confirm = false }
                            Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Label {
                                anchors.centerIn: parent
                                text:  gmapsCacheBtn._done    ? "✓ " + i18n.tr("Caché eliminada")
                                     : gmapsCacheBtn._confirm ? "⚠ " + i18n.tr("Toca de nuevo para confirmar")
                                     :                          i18n.tr("Limpiar caché Google Maps")
                                color: gmapsCacheBtn._done    ? "#66BB6A"
                                     : gmapsCacheBtn._confirm ? "#FFCC02"
                                     :                         "#EF5350"
                                font.pixelSize: ts(1.8)
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    if (gmapsCacheBtn._confirm) { panel.googleMapsCacheClearRequested(); gmapsCacheBtn._done = true; gmapsCacheBtn._confirm = false }
                                    else { gmapsCacheBtn._confirm = true }
                                }
                            }
                        }
                    }
                }
            }
        } // Column Servidor de rutas

        // ════════════════════════════════════════════════════════════════
        // NAVEGACIÓN
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: navCol.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Navegación")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.nav ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.nav = !secSettings.nav }
        }

        Column {
            id: navCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.nav && hasContent
            width: parent.width; spacing: 0

            // ── Sonido de alertas ────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: alertSoundCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: alertSoundCol
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Sonido de alertas"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                    PrefOptionSelector {
                        width: parent.width
                        property var _keys: ["tts", "beep", "off"]
                        model: [i18n.tr("Voz") + " ↺", i18n.tr("Pitido"), i18n.tr("No")]
                        selectedIndex: {
                            if (!panel.cfg) return 0
                            var k = panel.cfg.alertSound
                            return k === "beep" ? 1 : (k === "off" ? 2 : 0)
                        }
                        containerHeight: units.gu(4.5) * 3
                        onSelectedIndexChanged: {
                            if (!panel.cfg) return
                            var k = _keys[selectedIndex]
                            panel.cfg.alertSound = k
                            if (k !== "off") panel.soundTest(k, "alertas")
                        }
                    }
                }
            }

            // ── Sonido de indicaciones ───────────────────────────────────
            Rectangle {
                width: parent.width
                height: instrSoundCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: instrSoundCol
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Sonido de indicaciones"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                    PrefOptionSelector {
                        width: parent.width
                        property var _keys: ["tts", "beep", "off"]
                        model: [i18n.tr("Voz") + " ↺", i18n.tr("Pitido"), i18n.tr("No")]
                        selectedIndex: {
                            if (!panel.cfg) return 0
                            var k = panel.cfg.instrSound
                            return k === "beep" ? 1 : (k === "off" ? 2 : 0)
                        }
                        containerHeight: units.gu(4.5) * 3
                        onSelectedIndexChanged: {
                            if (!panel.cfg) return
                            var k = _keys[selectedIndex]
                            panel.cfg.instrSound = k
                            if (k !== "off") panel.soundTest(k, "indicaciones")
                        }
                    }
                }
            }

            // ── Radares fijos ────────────────────────────────────────────
            PrefListItem {
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Radares fijos")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Iconos y alertas de radares de velocidad fijos") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swShowRadarFijos
                    checked: panel.cfg ? panel.cfg.showRadarFijos : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.showRadarFijos = checked
                }
            }

            // ── Radares de tramo ─────────────────────────────────────────
            PrefListItem {
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Radares de tramo")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Zonas de control de velocidad media + barra de progreso") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swShowRadarTramo
                    checked: panel.cfg ? panel.cfg.showRadarTramo : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.showRadarTramo = checked
                }
            }

            // ── Aviso de exceso de velocidad ─────────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Aviso de exceso de velocidad")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Parpadeo al superar el límite") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swSpeedAlertEnabled
                    checked: panel.cfg ? panel.cfg.speedAlertEnabled : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.speedAlertEnabled = checked
                }
            }

            // ── Margen exceso de velocidad ───────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width
                height: marginSpeedCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: marginSpeedCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Margen exceso de velocidad"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                    PrefOptionSelector {
                        width: parent.width
                        property var _vals: [0, 1, 2, 5, 10, 15, 20]
                        model: [i18n.tr("Sin margen"), "+1%", "+2% ↺", "+5%", "+10%", "+15%", "+20%"]
                        selectedIndex: {
                            if (!panel.cfg) return 2
                            var idx = _vals.indexOf(panel.cfg.speedAlertPct)
                            return idx >= 0 ? idx : 2
                        }
                        containerHeight: units.gu(4.5) * 7
                        onSelectedIndexChanged: {
                            if (panel.cfg) panel.cfg.speedAlertPct = _vals[selectedIndex]
                        }
                    }
                }
            }

            // ── Zoom automático ──────────────────────────────────────────
            PrefListItem {
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Zoom automático")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Ajusta el zoom según la velocidad") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swAutoZoom
                    checked: panel.cfg ? panel.cfg.autoZoom : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.autoZoom = checked
                }
            }

            // ── Anticipación zoom automático ─────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: azCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: azCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Item {
                        width: parent.width; height: units.gu(3)
                        Label {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Anticipación zoom automático"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        }
                        Label {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: panel.cfg ? (panel.cfg.autoZoomSecs + " s  ↺ 15 s") : "15 s"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                        }
                    }
                    Label {
                        text: i18n.tr("Ajuste de zoom automático para que se vea al menos la distancia a recorrer en este tiempo")
                        color: pal.fgSecondary; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Slider {
                        width: parent.width
                        from: 5; to: 60; stepSize: 1; live: true
                        value: panel.cfg ? panel.cfg.autoZoomSecs : 15
                        onValueChanged: if (panel.cfg) panel.cfg.autoZoomSecs = Math.round(value)
                    }
                }
            }

            // ── Ajustar movimiento a ruta ────────────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Ajustar movimiento a ruta")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Zoom según velocidades Valhalla de los tramos por delante") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swRouteAdjustZoom
                    checked: panel.cfg ? panel.cfg.routeAdjustZoom : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.routeAdjustZoom = checked
                }
            }

            // ── Anticipación giro de ruta ────────────────────────────────
            Rectangle {
                width: parent.width; height: raCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                visible: panel.cfg && panel.cfg.routeAdjustZoom && panel.cfg.prefLevel >= 2
                Column {
                    id: raCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Item {
                        width: parent.width; height: units.gu(3)
                        Label {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Anticipación giro de ruta"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        }
                        Label {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: panel.cfg ? (panel.cfg.routeAheadSecs + " s  ↺ 10 s") : "10 s"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                        }
                    }
                    Label {
                        text: i18n.tr("Segundos de ruta por delante para anticipar el giro del mapa")
                        color: pal.fgSecondary; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Slider {
                        width: parent.width
                        from: 1; to: 45; stepSize: 1; live: true
                        value: panel.cfg ? panel.cfg.routeAheadSecs : 10
                        onValueChanged: if (panel.cfg) panel.cfg.routeAheadSecs = Math.round(value)
                    }
                }
            }

            // ── Ángulo máximo de giro predictivo ─────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width; height: mtCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: mtCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Item {
                        width: parent.width; height: units.gu(3)
                        Label {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Ángulo máximo de giro predictivo"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        }
                        Label {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: panel.cfg ? (panel.cfg.maxPredictiveTurnDeg + "°  ↺ 30°") : "30°"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                        }
                    }
                    Label {
                        text: i18n.tr("Máximo desvío angular del mapa respecto al heading real en modo giro")
                        color: pal.fgSecondary; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Slider {
                        width: parent.width
                        from: 0; to: 90; stepSize: 1; live: true
                        value: panel.cfg ? panel.cfg.maxPredictiveTurnDeg : 30
                        onValueChanged: if (panel.cfg) panel.cfg.maxPredictiveTurnDeg = Math.round(value)
                    }
                }
            }

            // ── Ajuste de posición a la ruta ─────────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Ajuste de posición a la ruta")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Centrar el vehículo sobre el shape de la ruta") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swSnapToRouteEnabled
                    checked: panel.cfg ? panel.cfg.snapToRouteEnabled : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.snapToRouteEnabled = checked
                }
            }

            // ── Distancia máxima de ajuste ────────────────────────────────
            Rectangle {
                width: parent.width; height: sdCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                visible: panel.cfg && panel.cfg.snapToRouteEnabled && panel.cfg.prefLevel >= 2
                Column {
                    id: sdCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Item {
                        width: parent.width; height: units.gu(3)
                        Label {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Distancia máxima de ajuste"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        }
                        Label {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: panel.cfg ? (panel.cfg.snapDistM + " m  ↺ 11 m") : "11 m"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                        }
                    }
                    Label {
                        text: i18n.tr("Ajustar posición visual si el GPS está a menos de esta distancia de la ruta")
                        color: pal.fgSecondary; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Slider {
                        width: parent.width
                        from: 5; to: 15; stepSize: 1; live: true
                        value: panel.cfg ? panel.cfg.snapDistM : 11
                        onValueChanged: if (panel.cfg) panel.cfg.snapDistM = Math.round(value)
                    }
                }
            }

            // ── Distancia de desvío antes de recalcular ruta ─────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: orCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: orCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Item {
                        width: parent.width; height: units.gu(3)
                        Label {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Desvío para recalcular ruta"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        }
                        Label {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: panel.cfg ? (panel.cfg.offRouteDistM + " m  ↺ 11 m") : "11 m"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                        }
                    }
                    Label {
                        text: i18n.tr("Distancia fuera de la ruta antes de recalcular")
                        color: pal.fgSecondary; font.pixelSize: ts(1.6)
                        wrapMode: Text.WordWrap; width: parent.width
                    }
                    Slider {
                        width: parent.width
                        from: 5; to: 15; stepSize: 1; live: true
                        value: panel.cfg ? panel.cfg.offRouteDistM : 11
                        onValueChanged: if (panel.cfg) panel.cfg.offRouteDistM = Math.round(value)
                    }
                }
            }

            // ── Suavizado GPS ────────────────────────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Suavizado GPS")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Suavizar el movimiento del vehículo y el mapa entre ticks GPS") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swDrEnabled
                    checked: panel.cfg ? panel.cfg.drEnabled : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.drEnabled = checked
                }
            }

            // ── Frecuencia de suavizado ──────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.drEnabled && panel.cfg.prefLevel >= 2
                width: parent.width
                height: drHzCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: drHzCol
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Frecuencia de suavizado"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                    PrefOptionSelector {
                        width: parent.width
                        property var _vals: [10, 20, 30]
                        model: ["10 Hz", "20 Hz ↺", "30 Hz"]
                        selectedIndex: {
                            if (!panel.cfg) return 1
                            var idx = _vals.indexOf(panel.cfg.drHz)
                            return idx >= 0 ? idx : 1
                        }
                        containerHeight: units.gu(4.5) * 3
                        onSelectedIndexChanged: {
                            if (panel.cfg) panel.cfg.drHz = _vals[selectedIndex]
                        }
                    }
                }
            }

            // ── Slider de zoom ───────────────────────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Slider de zoom")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Barra lateral para ajustar el zoom") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swShowZoomSlider
                    checked: panel.cfg ? panel.cfg.showZoomSlider : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.showZoomSlider = checked
                }
            }

            // ── Inhibir suspensión de pantalla ───────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Inhibir suspensión de pantalla")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Mantiene la pantalla encendida mientras la app está abierta") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swInhibitSuspend
                    checked: panel.cfg ? panel.cfg.inhibitSuspend : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.inhibitSuspend = checked
                }
            }

            // ── Mostrar velocidad máxima de la vía ───────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.prefLevel >= 2
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Mostrar velocidad máxima de la vía")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Fuente no fiable (OSM/Valhalla). Solo activa si hay radar comunitario") + "  · ↺ desact."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swShowRoadSpeedLimit
                    checked: panel.cfg ? panel.cfg.showRoadSpeedLimit : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.showRoadSpeedLimit = checked
                }
            }

            // ── Velocidad GPS hardware (Doppler) ─────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Velocidad GPS Doppler")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Usa la velocidad Doppler del chip GPS en vez de calcularla por diferencia de posiciones. Más precisa a baja velocidad y en aceleraciones. Desactiva si notas velocidades erráticas.") + "  · ↺ act."
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swUseHardwareSpeed
                    checked: panel.cfg ? panel.cfg.useHardwareSpeed : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.useHardwareSpeed = checked
                }
            }

        } // Column Navegación

        // ════════════════════════════════════════════════════════════════
        // GRABACIÓN DE RUTAS
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: grabacionCol.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Grabación de rutas")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.grabacion ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.grabacion = !secSettings.grabacion }
        }

        Column {
            id: grabacionCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.grabacion && hasContent
            width: parent.width; spacing: 0

        // ── Grabación GPS + Rutas grabadas ───────────────────────────
        Rectangle {
            id: tracksSection
            width: parent.width
            color: pal.bgCard; radius: 0
            height: tracksCol.implicitHeight + units.gu(4)

            property var    _tracks:    []
            property string _renameId:  ""
            property string _deleteId:  ""
            property string _addSimId:  ""
            property string _addSimName: ""
            property string _gpxMsg:    ""

            function _refresh() {
                if (!panel.trackerRef) { _tracks = []; return }
                panel.trackerRef.list_tracks_async()
            }

            onVisibleChanged: if (visible) _refresh()
            Timer {
                id: trackSaveTimer
                interval: 1200; repeat: false
                onTriggered: tracksSection._refresh()
            }
            Connections {
                target: panel.trackerRef
                function onRecording_changed() {
                    if (panel.trackerRef && !panel.trackerRef.recording)
                        trackSaveTimer.restart()
                    else
                        Qt.callLater(function() { tracksSection._refresh() })
                }
                function onTracks_ready(json) {
                    try { tracksSection._tracks = JSON.parse(json) }
                    catch(e) { tracksSection._tracks = [] }
                }
                function onTrack_deleted(id) {
                    tracksSection._refresh()
                }
                function onGpx_ready(id, path) {
                    tracksSection._gpxMsg = path !== "" ? "✓ GPX: " + path.split("/").pop() : "✗ Error al exportar"
                    gpxMsgTimer.restart()
                }
            }
            Timer {
                id: gpxMsgTimer
                interval: 4000; repeat: false
                onTriggered: tracksSection._gpxMsg = ""
            }

            Column {
                id: tracksCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                spacing: units.gu(1)

                // Toggle grabación
                Item {
                    width: parent.width; height: gpsTrackingCol.implicitHeight
                    Switch {
                        id: swGpsTracking
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        checked: panel.cfg ? panel.cfg.gpsTracking : false
                        onCheckedChanged: if (panel.cfg) panel.cfg.gpsTracking = checked
                    }
                    Column {
                        id: gpsTrackingCol
                        anchors { left: parent.left; right: swGpsTracking.left; rightMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                        Label { text: i18n.tr("Grabación GPS"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                        Label {
                            text: panel.cfg && panel.cfg.gpsTracking
                                  ? (panel.trackerRef
                                     ? i18n.tr("Grabando") + " · " + panel.trackerRef.get_point_count() + " pts"
                                     : i18n.tr("Grabando…"))
                                  : i18n.tr("Graba posición y velocidad")
                            color: panel.cfg && panel.cfg.gpsTracking ? "#EF5350" : pal.bgBtn
                            font.pixelSize: ts(1.6); wrapMode: Text.WordWrap; width: parent.width
                        }
                    }
                }

                // Borrar todas las rutas
                Rectangle {
                    id: allTracksBtn
                    width: parent.width; height: units.gu(4.5); radius: units.gu(0.8)
                    color: _confirm ? "#4A1010" : pal.bgInput
                    property bool _confirm: false
                    property bool _done: false
                    Timer { interval: 4000; running: parent._confirm && !parent._done; onTriggered: parent._confirm = false }
                    Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Label {
                        anchors.centerIn: parent
                        text:  allTracksBtn._done    ? "✓ " + i18n.tr("Rutas eliminadas")
                             : allTracksBtn._confirm ? "⚠ " + i18n.tr("Toca de nuevo para confirmar")
                             :                         i18n.tr("Borrar todas las rutas grabadas")
                        color: allTracksBtn._done    ? "#66BB6A"
                             : allTracksBtn._confirm ? "#FFCC02"
                             :                        "#EF5350"
                        font.pixelSize: ts(1.8)
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (allTracksBtn._confirm) {
                                panel.allTracksClearRequested()
                                allTracksBtn._done = true; allTracksBtn._confirm = false
                            } else { allTracksBtn._confirm = true }
                        }
                    }
                }

                // Lista de rutas
                Label {
                    visible: true
                    text: i18n.tr("Rutas grabadas"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                }
                Label {
                    visible: tracksSection._gpxMsg !== ""
                    text: tracksSection._gpxMsg
                    color: tracksSection._gpxMsg.charAt(0) === "✓" ? "#66BB6A" : "#EF5350"
                    font.pixelSize: ts(1.6)
                    wrapMode: Text.WordWrap; width: parent.width
                }
                Label {
                    visible: tracksSection._tracks.length === 0
                    text: i18n.tr("Ninguna ruta grabada aún")
                    color: pal.fgSecondary; font.pixelSize: ts(1.8)
                }

                Repeater {
                    model: tracksSection._tracks
                    delegate: Rectangle {
                        id: trackDelegate
                        property var td: modelData
                        width: tracksCol.width
                        height: tdMain.implicitHeight
                                + (deleteRow.visible ? deleteRow.height + units.gu(0.8) : 0)
                                + (renameRow.visible ? renameRow.height + units.gu(0.8) : 0)
                                + (addSimRow.visible ? addSimRow.height + units.gu(0.8) : 0)
                                + units.gu(1.5)
                        color: pal.bgCard; radius: units.gu(0.6)
                        border.color: "#22334455"; border.width: units.gu(0.1)

                        Column {
                            id: tdMain
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(1) }
                            spacing: units.gu(0.4)
                            Label {
                                width: parent.width; text: td.name
                                color: pal.fgPrimary; font.pixelSize: ts(1.7); font.bold: true
                                elide: Text.ElideRight
                            }
                            Label {
                                text: td.date + "  ·  " + td.dur + "  ·  " + td.dist + "  ·  " + td.npts + " pts"
                                      + (td.has_route ? "  ·  con ruta" : "")
                                color: pal.fgDataSub; font.pixelSize: ts(1.5)
                                wrapMode: Text.WordWrap; width: parent.width
                            }
                            Row {
                                spacing: units.gu(0.6)
                                Rectangle {
                                    width: units.gu(7.5); height: units.gu(4); radius: units.gu(0.5)
                                    color: td.has_route ? "#1565C3" : pal.bgBtn
                                    Label {
                                        anchors.centerIn: parent
                                        text: i18n.tr("Simular")
                                        color: td.has_route ? "white" : pal.fgSecondary
                                        font.pixelSize: ts(1.6)
                                    }
                                    MouseArea { anchors.fill: parent; onClicked: panel.trackSimRequested(td.id, td.name, false) }
                                }
                                Rectangle {
                                    width: units.gu(9); height: units.gu(4); radius: units.gu(0.5); color: pal.bgBtn
                                    Label { anchors.centerIn: parent; text: i18n.tr("GPS crudo"); color: pal.isDark ? "#FFB74D" : "#E65100"; font.pixelSize: ts(1.5) }
                                    MouseArea { anchors.fill: parent; onClicked: panel.trackSimRequested(td.id, td.name, true) }
                                }
                                Rectangle {
                                    width: units.gu(5.5); height: units.gu(4); radius: units.gu(0.5); color: pal.bgInputAlt
                                    Label { anchors.centerIn: parent; text: "GPX"; color: "#4CAF50"; font.pixelSize: ts(1.6); font.bold: true }
                                    MouseArea { anchors.fill: parent; onClicked: panel.trackGpxRequested(td.id) }
                                }
                                Rectangle {
                                    width: units.gu(8); height: units.gu(4); radius: units.gu(0.5); color: pal.bgInputAlt
                                    Label { anchors.centerIn: parent; text: "+ Sim"; color: "#9C27B0"; font.pixelSize: ts(1.6) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            tracksSection._addSimId   = td.id
                                            tracksSection._addSimName = td.name
                                        }
                                    }
                                }
                                Rectangle {
                                    width: units.gu(5.5); height: units.gu(4); radius: units.gu(0.5); color: pal.bgInputAlt
                                    Label { anchors.centerIn: parent; text: "✎"; color: "#29B6F6"; font.pixelSize: ts(1.8) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: tracksSection._renameId = (tracksSection._renameId === td.id ? "" : td.id)
                                    }
                                }
                                Rectangle {
                                    width: units.gu(4); height: units.gu(4); radius: units.gu(0.5)
                                    color: tracksSection._deleteId === td.id ? "#4A1010" : pal.bgInput
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.8) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: tracksSection._deleteId = (tracksSection._deleteId === td.id ? "" : td.id)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: deleteRow
                            visible: tracksSection._deleteId === td.id
                            anchors { left: parent.left; right: parent.right; top: tdMain.bottom
                                      margins: units.gu(1); topMargin: units.gu(0.8) }
                            height: units.gu(4.5); radius: units.gu(0.5); color: "#2C1010"
                            border.color: "#EF5350"; border.width: units.gu(0.1)
                            Row {
                                anchors.centerIn: parent; spacing: units.gu(1)
                                Rectangle {
                                    width: units.gu(12); height: units.gu(3.5); radius: units.gu(0.5); color: pal.bgBtn
                                    Label { anchors.centerIn: parent; text: i18n.tr("Cancelar"); color: pal.fgPrimary; font.pixelSize: ts(1.7) }
                                    MouseArea { anchors.fill: parent; onClicked: tracksSection._deleteId = "" }
                                }
                                Rectangle {
                                    width: units.gu(12); height: units.gu(3.5); radius: units.gu(0.5); color: "#C62828"
                                    Label { anchors.centerIn: parent; text: i18n.tr("Eliminar"); color: "white"; font.pixelSize: ts(1.7) }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (panel.trackerRef) panel.trackerRef.delete_track_async(td.id)
                                            tracksSection._deleteId = ""
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: renameRow
                            visible: tracksSection._renameId === td.id
                            anchors { left: parent.left; right: parent.right; top: tdMain.bottom
                                      margins: units.gu(1); topMargin: units.gu(0.8) }
                            height: units.gu(4.5); radius: units.gu(0.5); color: pal.bgCard
                            border.color: "#29B6F6"; border.width: units.gu(0.1)
                            Row {
                                anchors { fill: parent; margins: units.gu(0.8) }
                                spacing: units.gu(0.6)
                                NavTextInput {
                                    id: renameInput
                                    width: parent.width - units.gu(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: pal.fgPrimary; font.pixelSize: ts(1.7)
                                    text: tracksSection._renameId === td.id ? td.name : ""
                                    selectionColor: "#29B6F6"
                                    onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(5); height: units.gu(3.5); radius: units.gu(0.5); color: "#1565C3"
                                    Label { anchors.centerIn: parent; text: i18n.tr("OK"); color: "white"; font.pixelSize: ts(1.6); font.bold: true }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            var n = renameInput.text.trim()
                                            if (n.length > 0 && panel.trackerRef) {
                                                panel.trackerRef.rename_track(td.id, n)
                                                // Actualizar nombre localmente sin ir a BD (evita race con hilo rename)
                                                var arr = tracksSection._tracks
                                                for (var k = 0; k < arr.length; k++) {
                                                    if (arr[k].id === td.id) { arr[k].name = n; break }
                                                }
                                                tracksSection._tracks = arr.slice()
                                            }
                                            tracksSection._renameId = ""
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            id: addSimRow
                            visible: tracksSection._addSimId === td.id
                            anchors { left: parent.left; right: parent.right
                                      top: renameRow.visible ? renameRow.bottom : tdMain.bottom
                                      margins: units.gu(1); topMargin: units.gu(0.8) }
                            height: units.gu(4.5); radius: units.gu(0.5); color: pal.bgCard
                            border.color: "#9C27B0"; border.width: units.gu(0.1)
                            Row {
                                anchors { fill: parent; margins: units.gu(0.8) }
                                spacing: units.gu(0.6)
                                NavTextInput {
                                    id: addSimInput
                                    width: parent.width - units.gu(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: pal.fgPrimary; font.pixelSize: ts(1.7)
                                    text: tracksSection._addSimId === td.id ? td.name : ""
                                    selectionColor: "#9C27B0"
                                    onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(5); height: units.gu(3.5); radius: units.gu(0.5); color: "#9C27B0"
                                    Label { anchors.centerIn: parent; text: "+ Sim"; color: "white"; font.pixelSize: ts(1.5); font.bold: true }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            var n = addSimInput.text.trim() || td.name
                                            panel.trackAddToSim(td.id, n)
                                            tracksSection._addSimId = ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        } // Column Grabación de rutas

        // ════════════════════════════════════════════════════════════════
        // VOZ
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: vozCol.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Voz")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.voz ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.voz = !secSettings.voz }
        }

        Column {
            id: vozCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.voz && hasContent
            width: parent.width; spacing: 0

            // ── Idioma de voz + Motor TTS ────────────────────────────────
            Rectangle {
                width: parent.width
                height: ttsColumn.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0

                property var  _piperVoices:  []
                property var  _picoVoices:   []
                property var  _espeakVoices: []
                property string _effLang: {
                    if (!panel.cfg) return ""
                    var l = panel.cfg.ttsLang
                    return l === "system" ? Qt.locale().name.split("_")[0] : l
                }

                function _refreshVoices() {
                    if (!panel.ttsRef || !panel.cfg) {
                        _piperVoices = []; _picoVoices = []; _espeakVoices = []; return
                    }
                    var raw = panel.ttsRef.installed_piper_voices(_effLang)
                    _piperVoices = raw ? raw.split(",").filter(function(v) { return v.length > 0 }) : []
                    var rawPico = panel.ttsRef.available_pico_voices(_effLang)
                    _picoVoices = rawPico ? rawPico.split(",").filter(function(v) { return v.length > 0 }) : []
                    var rawEspeak = panel.ttsRef.available_espeak_voices(_effLang)
                    _espeakVoices = rawEspeak ? rawEspeak.split(",").filter(function(v) { return v.length > 0 }) : []
                }
                function _voiceLabel(id) {
                    var d = id.indexOf("-"); if (d < 0) return id
                    var rest = id.substring(d + 1)
                    var ld   = rest.lastIndexOf("-")
                    var name = ld >= 0 ? rest.substring(0, ld)  : rest
                    var qual = ld >= 0 ? rest.substring(ld + 1) : ""
                    var prefix = id.substring(0, d)
                    var u      = prefix.indexOf("_")
                    var locale = u >= 0 ? prefix.substring(u + 1) : ""
                    return locale ? name + " (" + locale + " · " + qual + ")"
                                  : name + " (" + qual + ")"
                }
                function _picoVoiceLabel(id) {
                    var map = {
                        "en-US": "English (US)", "en-GB": "English (GB)",
                        "de-DE": "Deutsch",      "es-ES": "Español",
                        "fr-FR": "Français",     "it-IT": "Italiano"
                    }
                    return map[id] || id
                }
                function _espeakVoiceLabel(id) {
                    var map = {
                        "es": "Español",           "es-la": "Español (Latino)",
                        "en-us": "English (US)",   "en-gb": "English (GB)",
                        "en-sc": "English (Scotland)", "en-wls": "English (Wales)",
                        "fr": "Français",          "fr-be": "Français (Belgique)",
                        "fr-ch": "Français (Suisse)",
                        "pt": "Português (BR)",    "pt-pt": "Português (PT)"
                    }
                    return map[id] || id
                }

                onVisibleChanged: if (visible) _refreshVoices()
                on_EffLangChanged: _refreshVoices()

                Column {
                    id: ttsColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)

                    // ── Idioma de voz ──────────────────────────────────────
                    Label { text: i18n.tr("Idioma de voz"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }

                    PrefOptionSelector {
                        width: parent.width
                        property var _keys: ["system","es","en","fr","de","pt","it","ca","eu","ru","zh","ar","fa"]
                        model: [i18n.tr("Sistema") + " ↺", "Español", "English", "Français", "Deutsch",
                                "Português", "Italiano", "Català", "Euskera", "Русский", "中文", "العربية", "فارسی"]
                        selectedIndex: {
                            if (!panel.cfg) return 0
                            var idx = _keys.indexOf(panel.cfg.ttsLang)
                            return idx >= 0 ? idx : 0
                        }
                        containerHeight: units.gu(4.5) * 6
                        onSelectedIndexChanged: {
                            if (!panel.cfg) return
                            var k = _keys[selectedIndex]
                            if (panel.cfg.ttsLang === k) return
                            panel.cfg.ttsLang = k
                            panel.langChanged(k)
                        }
                    }

                    // ── Selector voz Piper ─────────────────────────────────
                    Column {
                        id: voiceSel
                        property var  _r:    parent.parent
                        property bool _open: false
                        width: parent.width; spacing: units.gu(0.5)
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                                 && _r && _r._piperVoices && _r._piperVoices.length > 1
                                 && (panel.cfg.ttsEngine === "auto" || panel.cfg.ttsEngine === "piper")

                        Label { text: i18n.tr("Voz Piper"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.6)
                            color: pal.bgInput; border.color: "#29B6F6"; border.width: units.gu(0.12)
                            Row {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                          leftMargin: units.gu(1.2); rightMargin: units.gu(1) }
                                Label {
                                    width: parent.width - units.gu(2.5)
                                    text: {
                                        if (!panel.cfg || panel.cfg.ttsVoice === "") return i18n.tr("Automático")
                                        return voiceSel._r ? voiceSel._r._voiceLabel(panel.cfg.ttsVoice) : panel.cfg.ttsVoice
                                    }
                                    color: "#29B6F6"; font.pixelSize: ts(1.7); elide: Text.ElideRight
                                }
                                Label { text: voiceSel._open ? "▲" : "▼"; color: "#29B6F6"; font.pixelSize: ts(1.4)
                                        anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { anchors.fill: parent; onClicked: voiceSel._open = !voiceSel._open }
                        }

                        Column {
                            visible: voiceSel._open
                            width: parent.width; spacing: units.gu(0.3)
                            Repeater {
                                model: voiceSel._r ? voiceSel._r._piperVoices : []
                                delegate: Rectangle {
                                    property string vid: modelData
                                    property bool   sel: panel.cfg && panel.cfg.ttsVoice === vid
                                    width: parent.width; height: units.gu(4.5); radius: units.gu(0.5)
                                    color:        sel ? pal.bgSelBlue : pal.bgCard
                                    border.color: sel ? "#29B6F6" : "#22334455"; border.width: units.gu(0.1)
                                    Row {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(1) }
                                        spacing: units.gu(0.6)
                                        Label { text: sel ? "●" : "○"; color: sel ? "#29B6F6" : pal.bgBtn
                                                font.pixelSize: ts(1.4); anchors.verticalCenter: parent.verticalCenter }
                                        Label {
                                            text: voiceSel._r ? voiceSel._r._voiceLabel(vid) : vid
                                            color: sel ? "#29B6F6" : pal.fgSecondary
                                            font.pixelSize: ts(1.6); font.bold: sel
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsVoice = vid
                                            panel.voiceSelected(vid)
                                            voiceSel._open = false
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Selector voz PicoTTS ───────────────────────────────
                    Column {
                        id: picoVoiceSel
                        property var  _r:    parent.parent
                        property bool _open: false
                        width: parent.width; spacing: units.gu(0.5)
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                                 && _r && _r._picoVoices && _r._picoVoices.length > 0
                                 && panel.cfg.ttsEngine === "picotts"

                        Label { text: i18n.tr("Voz PicoTTS"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.6)
                            color: pal.bgInput; border.color: "#29B6F6"; border.width: units.gu(0.12)
                            Row {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                          leftMargin: units.gu(1.2); rightMargin: units.gu(1) }
                                Label {
                                    width: parent.width - units.gu(2.5)
                                    text: {
                                        if (!panel.cfg || panel.cfg.ttsVoicePico === "") return i18n.tr("Automático")
                                        return picoVoiceSel._r ? picoVoiceSel._r._picoVoiceLabel(panel.cfg.ttsVoicePico)
                                                               : panel.cfg.ttsVoicePico
                                    }
                                    color: "#29B6F6"; font.pixelSize: ts(1.7); elide: Text.ElideRight
                                }
                                Label { text: picoVoiceSel._open ? "▲" : "▼"; color: "#29B6F6"; font.pixelSize: ts(1.4)
                                        anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { anchors.fill: parent; onClicked: picoVoiceSel._open = !picoVoiceSel._open }
                        }

                        Column {
                            visible: picoVoiceSel._open
                            width: parent.width; spacing: units.gu(0.3)
                            Repeater {
                                model: picoVoiceSel._r ? picoVoiceSel._r._picoVoices : []
                                delegate: Rectangle {
                                    property string vid: modelData
                                    property bool   sel: panel.cfg && panel.cfg.ttsVoicePico === vid
                                    width: parent.width; height: units.gu(4.5); radius: units.gu(0.5)
                                    color:        sel ? pal.bgSelBlue : pal.bgCard
                                    border.color: sel ? "#29B6F6" : "#22334455"; border.width: units.gu(0.1)
                                    Row {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(1) }
                                        spacing: units.gu(0.6)
                                        Label { text: sel ? "●" : "○"; color: sel ? "#29B6F6" : pal.bgBtn
                                                font.pixelSize: ts(1.4); anchors.verticalCenter: parent.verticalCenter }
                                        Label {
                                            text: picoVoiceSel._r ? picoVoiceSel._r._picoVoiceLabel(vid) : vid
                                            color: sel ? "#29B6F6" : pal.fgSecondary
                                            font.pixelSize: ts(1.6); font.bold: sel
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsVoicePico = vid
                                            panel.voicePicoSelected(vid)
                                            picoVoiceSel._open = false
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Selector voz espeak-ng ─────────────────────────────
                    Column {
                        id: espeakVoiceSel
                        property var  _r:    parent.parent
                        property bool _open: false
                        width: parent.width; spacing: units.gu(0.5)
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                                 && _r && _r._espeakVoices && _r._espeakVoices.length > 0
                                 && panel.cfg.ttsEngine === "espeak"

                        Label { text: i18n.tr("Voz espeak-ng"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }

                        Rectangle {
                            width: parent.width; height: units.gu(5); radius: units.gu(0.6)
                            color: pal.bgInput; border.color: "#29B6F6"; border.width: units.gu(0.12)
                            Row {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                          leftMargin: units.gu(1.2); rightMargin: units.gu(1) }
                                Label {
                                    width: parent.width - units.gu(2.5)
                                    text: {
                                        if (!panel.cfg || panel.cfg.ttsVoiceEspeak === "") return i18n.tr("Automático")
                                        return espeakVoiceSel._r ? espeakVoiceSel._r._espeakVoiceLabel(panel.cfg.ttsVoiceEspeak)
                                                                 : panel.cfg.ttsVoiceEspeak
                                    }
                                    color: "#29B6F6"; font.pixelSize: ts(1.7); elide: Text.ElideRight
                                }
                                Label { text: espeakVoiceSel._open ? "▲" : "▼"; color: "#29B6F6"; font.pixelSize: ts(1.4)
                                        anchors.verticalCenter: parent.verticalCenter }
                            }
                            MouseArea { anchors.fill: parent; onClicked: espeakVoiceSel._open = !espeakVoiceSel._open }
                        }

                        Column {
                            visible: espeakVoiceSel._open
                            width: parent.width; spacing: units.gu(0.3)
                            Repeater {
                                model: espeakVoiceSel._r ? espeakVoiceSel._r._espeakVoices : []
                                delegate: Rectangle {
                                    property string vid: modelData
                                    property bool   sel: panel.cfg && panel.cfg.ttsVoiceEspeak === vid
                                    width: parent.width; height: units.gu(4.5); radius: units.gu(0.5)
                                    color:        sel ? pal.bgSelBlue : pal.bgCard
                                    border.color: sel ? "#29B6F6" : "#22334455"; border.width: units.gu(0.1)
                                    Row {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(1) }
                                        spacing: units.gu(0.6)
                                        Label { text: sel ? "●" : "○"; color: sel ? "#29B6F6" : pal.bgBtn
                                                font.pixelSize: ts(1.4); anchors.verticalCenter: parent.verticalCenter }
                                        Label {
                                            text: espeakVoiceSel._r ? espeakVoiceSel._r._espeakVoiceLabel(vid) : vid
                                            color: sel ? "#29B6F6" : pal.fgSecondary
                                            font.pixelSize: ts(1.6); font.bold: sel
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsVoiceEspeak = vid
                                            panel.voiceEspeakSelected(vid)
                                            espeakVoiceSel._open = false
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Indicador procesando voz ───────────────────────────
                    Rectangle {
                        width: parent.width
                        height: panel.ttsProcessing ? units.gu(4) : 0
                        clip: true; color: "transparent"
                        Behavior on height { NumberAnimation { duration: 180 } }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: units.gu(1)
                            BusyIndicator {
                                running: panel.ttsProcessing
                                width: units.gu(2.2); height: units.gu(2.2)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Label {
                                text: i18n.tr("Procesando voz…")
                                color: "#29B6F6"; font.pixelSize: ts(1.6)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // ── Motor TTS ──────────────────────────────────────────
                    Label {
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                        text: i18n.tr("Motor TTS"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                    }

                    Column {
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                        width: parent.width; spacing: units.gu(0.8)
                        Row {
                            width: parent.width; spacing: units.gu(0.8)
                            Repeater {
                                model: [
                                    { key: "auto",  label: "Auto ↺" },
                                    { key: "piper", label: "Piper"   },
                                    { key: "mimic", label: "Mimic"   }
                                ]
                                delegate: Rectangle {
                                    property string k:   modelData.key
                                    property bool   sel: panel.cfg && panel.cfg.ttsEngine === k
                                    width: (parent.width - 2 * units.gu(0.8)) / 3
                                    height: units.gu(4.5); radius: units.gu(0.6)
                                    color:        sel ? pal.bgSelBlue : pal.bgInput
                                    border.color: sel ? "#29B6F6" : "transparent"; border.width: units.gu(0.15)
                                    Label {
                                        anchors.centerIn: parent; text: modelData.label
                                        color: sel ? "#29B6F6" : "#78909C"
                                        font.pixelSize: ts(1.7); font.bold: sel
                                        elide: Text.ElideRight
                                        width: parent.width - units.gu(0.4)
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsEngine = k
                                            panel.engineChanged(k)
                                        }
                                    }
                                }
                            }
                        }
                        Row {
                            width: parent.width; spacing: units.gu(0.8)
                            Repeater {
                                model: [
                                    { key: "picotts", label: "PicoTTS"   },
                                    { key: "espeak",  label: "espeak-ng" }
                                ]
                                delegate: Rectangle {
                                    property string k:   modelData.key
                                    property bool   sel: panel.cfg && panel.cfg.ttsEngine === k
                                    width: (parent.width - units.gu(0.8)) / 2
                                    height: units.gu(4.5); radius: units.gu(0.6)
                                    color:        sel ? pal.bgSelBlue : pal.bgInput
                                    border.color: sel ? "#29B6F6" : "transparent"; border.width: units.gu(0.15)
                                    Label {
                                        anchors.centerIn: parent; text: modelData.label
                                        color: sel ? "#29B6F6" : "#78909C"
                                        font.pixelSize: ts(1.7); font.bold: sel
                                        elide: Text.ElideRight
                                        width: parent.width - units.gu(0.4)
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            if (!panel.cfg) return
                                            panel.cfg.ttsEngine = k
                                            panel.engineChanged(k)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Botones ────────────────────────────────────────────
                    Rectangle {
                        visible: panel.cfg && panel.cfg.prefLevel >= 0
                        width: parent.width; height: units.gu(5); radius: units.gu(0.8); color: "#1565C3"
                        Label { anchors.centerIn: parent; text: i18n.tr("Gestionar voces TTS"); color: "white"; font.pixelSize: ts(1.9) }
                        MouseArea { anchors.fill: parent; onClicked: panel.voicesRequested() }
                    }

                    Rectangle {
                        visible: panel.cfg && panel.cfg.prefLevel >= 1
                        id: audioCacheBtn
                        width: parent.width; height: units.gu(5); radius: units.gu(0.8)
                        color: _confirm ? "#4A3010" : pal.bgBtn
                        property bool _confirm: false
                        property bool _done: false
                        Timer { interval: 4000; running: parent._confirm && !parent._done; onTriggered: parent._confirm = false }
                        Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Label {
                            anchors.centerIn: parent
                            text:  audioCacheBtn._done    ? "✓ " + i18n.tr("Caché eliminada")
                                 : audioCacheBtn._confirm ? "⚠ " + i18n.tr("Toca de nuevo para confirmar")
                                 :                          i18n.tr("Limpiar caché audio en ruta")
                            color: audioCacheBtn._done    ? "#66BB6A"
                                 : audioCacheBtn._confirm ? "#FFCC02"
                                 :                         pal.fgPrimary
                            font.pixelSize: ts(1.9)
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (audioCacheBtn._confirm) { panel.clearLiveCacheRequested(); audioCacheBtn._done = true; audioCacheBtn._confirm = false }
                                else { audioCacheBtn._confirm = true }
                            }
                        }
                    }
                }
            }
        } // Column Voz

        // ════════════════════════════════════════════════════════════════
        // MEDIA
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: mediaColContent.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Media")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.media ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.media = !secSettings.media }
        }

        Column {
            id: mediaColContent
            property int  _sectionMinLevel: 1
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.media && hasContent
            width: parent.width; spacing: 0

            // ── Volumen durante locuciones ────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.prefLevel >= 1
                width: parent.width; height: dvCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: dvCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Item {
                        width: parent.width; height: units.gu(3)
                        Label {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: i18n.tr("Volumen al hablar"); color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        }
                        Label {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: panel.cfg ? (Math.round(panel.cfg.duckVolume * 100) + " %  ↺ 70 %") : "70 %"
                            color: "#29B6F6"; font.pixelSize: ts(1.7)
                        }
                    }
                    Slider {
                        width: parent.width
                        from: 0.10; to: 1.00; stepSize: 0.05; live: true
                        value: panel.cfg ? panel.cfg.duckVolume : 0.70
                        onValueChanged: if (panel.cfg) panel.cfg.duckVolume = Math.round(value / 0.05) * 0.05
                    }
                }
            }
        } // Column Media

        // ════════════════════════════════════════════════════════════════
        // CUENTA NAVIUS
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: cuentaCol.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Cuenta Navius")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.cuenta ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.cuenta = !secSettings.cuenta }
        }

        Column {
            id: cuentaCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.cuenta && hasContent
            width: parent.width; spacing: 0

            // Estado de sesión
            Rectangle {
                width: parent.width; height: units.gu(6)
                color: pal.bgCard; radius: units.gu(0.8)
                border.color: "#29B6F6"
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: authSettings.token !== "" ? "✅" : "👤"; font.pixelSize: ts(2.5); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: authSettings.token !== "" ? authSettings.email : i18n.tr("No identificado")
                        color: authSettings.token !== "" ? "#66BB6A" : pal.fgSecondary
                        font.pixelSize: ts(2.0); anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Botón entrar / cerrar sesión
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: cuentaAccMa.pressed ? pal.bgInputAlt : pal.bgCard
                border.color: "#29B6F6"
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: authSettings.token !== "" ? "🚪" : "🔑"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: authSettings.token !== "" ? i18n.tr("Cerrar sesión") : i18n.tr("Iniciar sesión / Registro")
                        color: pal.fgPrimary; font.pixelSize: ts(1.9); anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                    text: "▶"; color: "#29B6F6"; font.pixelSize: ts(1.6)
                }
                MouseArea {
                    id: cuentaAccMa; anchors.fill: parent
                    onClicked: {
                        if (authSettings.token !== "") {
                            panel.logoutRequested()
                        } else {
                            panel.loginRequested()
                        }
                    }
                }
            }
        } // Column cuenta

        // ════════════════════════════════════════════════════════════════
        // PRIVACIDAD
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Privacidad")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.privacidad ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.privacidad = !secSettings.privacidad }
        }

        Column {
            id: privacidadCol
            visible: secSettings.privacidad
            width: parent.width; spacing: 0

            // Estado de consentimiento
            Rectangle {
                width: parent.width; height: units.gu(6.5)
                color: pal.bgCard; radius: 0
                Row {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label {
                        text: panel.cfg && panel.cfg.privacyAccepted ? "✅" : "⚠️"
                        font.pixelSize: ts(2.4); anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        text: panel.cfg && panel.cfg.privacyAccepted
                              ? i18n.tr("Política de privacidad aceptada")
                              : i18n.tr("Política de privacidad no aceptada")
                        color: panel.cfg && panel.cfg.privacyAccepted ? "#66BB6A" : pal.fgSecondary
                        font.pixelSize: ts(1.9); anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Cambiar estado
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: privChgMa.pressed ? pal.bgInputAlt : pal.bgCard
                border.color: panel.cfg && panel.cfg.privacyAccepted ? "#EF5350" : "#29B6F6"
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: panel.cfg && panel.cfg.privacyAccepted ? "❌" : "✔"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: panel.cfg && panel.cfg.privacyAccepted
                              ? i18n.tr("Retirar consentimiento")
                              : i18n.tr("Aceptar política de privacidad")
                        color: pal.fgPrimary; font.pixelSize: ts(1.9); anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: privChgMa; anchors.fill: parent
                    onClicked: {
                        if (panel.cfg) {
                            if (panel.cfg.privacyAccepted) {
                                panel.cfg.privacyAccepted = false
                                panel.logoutRequested()
                            } else {
                                panel.privacyBannerRequested()
                            }
                        }
                    }
                }
            }

            // Ver política de privacidad
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: privLinkMa.pressed ? pal.bgInputAlt : pal.bgCard
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: "🔗"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: i18n.tr("Ver política de privacidad")
                        color: "#29B6F6"; font.pixelSize: ts(1.9); anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea {
                    id: privLinkMa; anchors.fill: parent
                    onClicked: Qt.openUrlExternally("https://www.egpsistemas.com/site/navius/privacidad")
                }
            }
        } // Column privacidad

        // ════════════════════════════════════════════════════════════════
        // AYUDA
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: ayudaCol.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Ayuda")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.ayuda ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.ayuda = !secSettings.ayuda }
        }

        Column {
            id: ayudaCol
            property int  _sectionMinLevel: 0
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.ayuda && hasContent
            width: parent.width; spacing: 0

            // ── Manual de usuario ─────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: helpMa.pressed ? pal.bgInputAlt : pal.bgCard
                border.color: "#29B6F6"; border.width: 1

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: "📖"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: i18n.tr("Manual de usuario")
                        color: pal.fgPrimary; font.pixelSize: ts(1.9)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                    text: "▶"; color: "#29B6F6"; font.pixelSize: ts(1.6)
                }
                MouseArea { id: helpMa; anchors.fill: parent; onClicked: panel.helpRequested() }
            }

            // ── Asistente de bienvenida ───────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: tourMa.pressed ? pal.bgInputAlt : pal.bgCard
                border.color: "#29B6F6"; border.width: 1

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: "🧭"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: i18n.tr("Abrir asistente")
                        color: pal.fgPrimary; font.pixelSize: ts(1.9)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                    text: "▶"; color: "#29B6F6"; font.pixelSize: ts(1.6)
                }
                MouseArea { id: tourMa; anchors.fill: parent; onClicked: panel.tourRequested() }
            }

            // ── Mostrar asistente al inicio ───────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: pal.bgCard; border.color: "#29B6F6"; border.width: 1

                Row {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: units.gu(2); rightMargin: units.gu(1.5) }
                    spacing: units.gu(1)
                    Label {
                        text: i18n.tr("Mostrar asistente al inicio")
                        color: pal.fgPrimary; font.pixelSize: ts(1.8)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(9)
                        wrapMode: Text.WordWrap
                    }
                    Switch {
                        id: tourStartSwitch
                        anchors.verticalCenter: parent.verticalCenter
                        checked: tourSt.showOnStart
                        onCheckedChanged: tourSt.showOnStart = checked
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        tourSt.showOnStart = !tourSt.showOnStart
                        tourStartSwitch.checked = tourSt.showOnStart
                    }
                }
            }

            // ── Acerca de… ────────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: units.gu(5.5); radius: units.gu(0.8)
                color: aboutMa.pressed ? pal.bgInputAlt : pal.bgCard
                border.color: "#29B6F6"; border.width: 1

                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                    spacing: units.gu(1.5)
                    Label { text: "ℹ️"; font.pixelSize: ts(2.2); anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        text: i18n.tr("Acerca de…")
                        color: pal.fgPrimary; font.pixelSize: ts(1.9)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Label {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
                    text: "▶"; color: "#29B6F6"; font.pixelSize: ts(1.6)
                }
                MouseArea { id: aboutMa; anchors.fill: parent; onClicked: panel.aboutRequested() }
            }

        } // Column Ayuda

        // ════════════════════════════════════════════════════════════════
        // DEBUG
        // ════════════════════════════════════════════════════════════════
        Rectangle {
            visible: debugCol.hasContent
            width: parent.width; height: units.gu(6)
            color: pal.bgHeader; radius: units.gu(1)
            Label {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                text: i18n.tr("Debug")
                color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
            }
            PrefIcon {
                anchors { right: parent.right; rightMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                width: units.gu(2.5); height: units.gu(2.5)
                name: secSettings.debug ? "go-up" : "go-down"
                color: "#29B6F6"
            }
            MouseArea { anchors.fill: parent; onClicked: secSettings.debug = !secSettings.debug }
        }

        Column {
            id: debugCol
            property int  _sectionMinLevel: 2
            property bool hasContent: panel.cfg ? panel.cfg.prefLevel >= _sectionMinLevel : false
            visible: secSettings.debug && hasContent
            width: parent.width; spacing: 0

            // ── Modo debug ───────────────────────────────────────────────
            PrefListItem {
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Modo Debug")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Sim GPS, POI")
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swDebugMode
                    checked: panel.cfg ? panel.cfg.debugMode : false
                    onCheckedChanged: {
                        if (!panel.cfg) return
                        panel.cfg.debugMode = checked
                        if (!checked) {
                            panel.cfg.simMode = false
                            if (panel.cfg.manualPosActive) panel.manualPosCleared()
                            panel.debugOff()
                        } else {
                            panel.debugOn()
                        }
                    }
                }
            }

            // ── Activar trazas y TUI ─────────────────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Activar trazas y TUI")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("net_debug.log · tts_debug.log · piper_limit.log · control remoto")
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swTracesEnabled
                    checked: panel.cfg ? panel.cfg.tracesEnabled : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.tracesEnabled = checked
                }
            }

            // ── Simulación GPS ───────────────────────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Simulación GPS")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Muntaner → Gran Via (Barcelona)") + " · " + i18n.tr("Sustituye al GPS real para pruebas en interior")
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swSimMode
                    checked: panel.cfg ? panel.cfg.simMode : false
                    onCheckedChanged: {
                        if (!panel.cfg) return
                        panel.cfg.simMode = checked
                        if (!checked && panel.cfg.manualPosActive) panel.manualPosCleared()
                        panel.simToggled(panel.cfg.simMode)
                    }
                }
            }

            // ── Ruta de simulación ───────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width
                height: routeSelCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: routeSelCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Ruta de simulación"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                    PrefOptionSelector {
                        id: routeSelector
                        width: parent.width
                        model: [
                            "Muntaner → Gran Via (BCN)",
                            "Test radar fijo 1",
                            "Test radar fijo 2",
                            "Test radar tramo",
                            "Ruta del usuario"
                        ]
                        selectedIndex: panel.cfg ? panel.cfg.simRouteIdx : 0
                        onSelectedIndexChanged: {
                            if (panel.cfg && selectedIndex !== panel.cfg.simRouteIdx)
                                panel.simRouteChanged(selectedIndex)
                        }
                    }
                    Rectangle {
                        width: parent.width; height: units.gu(5); radius: units.gu(0.6); color: "#1565C3"
                        Label { anchors.centerIn: parent; text: i18n.tr("Aplicar ruta"); color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (panel.cfg) panel.simRouteChanged(routeSelector.selectedIndex) }
                        }
                    }
                    Label {
                        text: i18n.tr("Grabaciones en sim"); color: pal.fgSecondary; font.pixelSize: ts(1.6)
                        visible: {
                            try { return JSON.parse(panel.cfg ? panel.cfg.customSimTracks : "[]").length > 0 }
                            catch(e) { return false }
                        }
                    }
                    Repeater {
                        id: customSimRepeater
                        model: {
                            try { return JSON.parse(panel.cfg ? panel.cfg.customSimTracks : "[]") }
                            catch(e) { return [] }
                        }
                        delegate: Rectangle {
                            width: routeSelCol.width; height: units.gu(5); radius: units.gu(0.6)
                            color: panel.cfg && panel.cfg.simRouteIdx === (5 + index) ? pal.bgSelBlue : pal.bgInput
                            border.color: panel.cfg && panel.cfg.simRouteIdx === (5 + index) ? "#29B6F6" : "transparent"
                            border.width: units.gu(0.12)
                            Row {
                                anchors { fill: parent; leftMargin: units.gu(1.2); rightMargin: units.gu(1) }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - units.gu(4.5)
                                    text: modelData.name
                                    color: panel.cfg && panel.cfg.simRouteIdx === (5 + index) ? "#29B6F6" : pal.fgPrimary
                                    font.pixelSize: ts(1.7); elide: Text.ElideRight
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: units.gu(3.5); height: units.gu(3.5); radius: width / 2; color: pal.bgBtn
                                    Label { anchors.centerIn: parent; text: "✕"; color: "#EF5350"; font.pixelSize: ts(1.8) }
                                    MouseArea { anchors.fill: parent; onClicked: panel.trackRemovedFromSim(index) }
                                }
                            }
                            MouseArea {
                                anchors { fill: parent; rightMargin: units.gu(5) }
                                onClicked: panel.simRouteChanged(5 + index)
                            }
                        }
                    }
                }
            }

            // ── Perder señal GPS ─────────────────────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: panel.simSignalLost ? i18n.tr("Señal perdida (simulado)") : i18n.tr("Perder señal GPS")
                title.color: panel.simSignalLost ? "#FF5252" : pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: panel.simSignalLost ? i18n.tr("El vehículo sigue avanzando internamente")
                                                   : i18n.tr("Simula túnel o zona sin cobertura")
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swSimSignalLost
                    checked: panel.simSignalLost
                    onCheckedChanged: { if (panel.simSignalLost !== checked) panel.signalLostToggled() }
                }
            }

            // ── Deslizable posición en ruta sim ──────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Deslizable posición en ruta sim")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Desplegable lateral para mover la posición GPS simulada")
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swShowSimScrubber
                    checked: panel.cfg ? panel.cfg.showSimScrubber : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.showSimScrubber = checked
                }
            }

            // ── Velocidad mínima sim (km/h) ──────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width
                height: minSpeedCol.implicitHeight + units.gu(4)
                color: pal.bgCard; radius: 0
                Column {
                    id: minSpeedCol
                    anchors { fill: parent; margins: units.gu(2) }
                    spacing: units.gu(1)
                    Label { text: i18n.tr("Velocidad mínima sim (km/h)"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                    PrefOptionSelector {
                        width: parent.width
                        property var _vals: [0, 30, 50, 80, 120, 200]
                        model: [i18n.tr("Off"), "30 km/h", "50 km/h", "80 km/h", "120 km/h", "200 km/h"]
                        selectedIndex: {
                            if (!panel.cfg) return 0
                            var idx = _vals.indexOf(panel.cfg.simMinSpeedKmh)
                            return idx >= 0 ? idx : 0
                        }
                        containerHeight: units.gu(4.5) * 6
                        onSelectedIndexChanged: {
                            if (panel.cfg) panel.cfg.simMinSpeedKmh = _vals[selectedIndex]
                        }
                    }
                }
            }

            // ── Posición manual ──────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && (panel.cfg.debugMode || panel.cfg.simMode)
                width: parent.width
                height: visible ? manPosCol.implicitHeight + units.gu(4) : 0
                color: pal.bgCard; radius: 0
                Column {
                    id: manPosCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1.2)
                    Label { text: i18n.tr("Posición manual"); color: pal.fgPrimary; font.pixelSize: ts(1.8) }
                    Label {
                        visible: panel.cfg && panel.cfg.manualPosActive
                        width: parent.width
                        text: panel.cfg ? (panel.cfg.manualLat.toFixed(6) + ",  " + panel.cfg.manualLon.toFixed(6)) : ""
                        color: "#4CAF50"; font.pixelSize: ts(1.8); font.bold: true
                    }
                    TextField {
                        id: manLatField
                        width: parent.width
                        placeholderText: "Latitud  (ej. 40.322130)"
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                    }
                    TextField {
                        id: manLonField
                        width: parent.width
                        placeholderText: "Longitud  (ej. -3.515801)"
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                    }
                    Row {
                        width: parent.width; spacing: units.gu(1)
                        Rectangle {
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(5)
                            radius: units.gu(0.6); color: "#1565C3"
                            Label { anchors.centerIn: parent; text: i18n.tr("Fijar"); color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    var lat = parseFloat(manLatField.text)
                                    var lon = parseFloat(manLonField.text)
                                    if (!isNaN(lat) && !isNaN(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180)
                                        panel.manualPosApplied(lat, lon)
                                }
                            }
                        }
                        Rectangle {
                            width: (parent.width - units.gu(1)) / 2; height: units.gu(5)
                            radius: units.gu(0.6)
                            color: panel.cfg && panel.cfg.manualPosActive ? "#C62828" : pal.bgBtn
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Label { anchors.centerIn: parent; text: i18n.tr("Liberar GPS"); color: pal.fgPrimary; font.pixelSize: ts(1.8); font.bold: true }
                            MouseArea { anchors.fill: parent; onClicked: panel.manualPosCleared() }
                        }
                    }
                }
            }

            // ── Panel debug velocidades (v_sim) ──────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Panel debug velocidades (v_sim)")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Muestra vValhalla, límite y velocidad genérica")
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swShowVSimDebug
                    checked: panel.cfg ? panel.cfg.showVSimDebug : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.showVSimDebug = checked
                }
            }

            // ── Overlay límites de velocidad por tramo ───────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Overlay límites de velocidad")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Muestra límite, velocidad Valhalla y fuente por tramo")
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swShowSlDebug
                    checked: panel.cfg ? panel.cfg.showSlDebug : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.showSlDebug = checked
                }
            }

            // ── Mostrar ticks GPS ────────────────────────────────────────
            PrefListItem {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Mostrar ticks GPS (isReal)")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                subtitle.text: i18n.tr("Puntos cian en el mapa por cada fix real")
                subtitle.color: pal.fgSecondary
                subtitle.font.pixelSize: ts(1.5)
                subtitle.wrapMode: Text.WordWrap
                Switch {
                    id: swShowGpsTicks
                    checked: panel.cfg ? panel.cfg.showGpsTicks : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.showGpsTicks = checked
                }
            }

            // ── Simulación de fallos GPS ─────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode && panel.cfg.simMode
                width: parent.width
                height: visible ? gpsFailCol.implicitHeight + units.gu(4) : 0
                color: pal.bgCard; radius: 0
                Column {
                    id: gpsFailCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: units.gu(2) }
                    spacing: units.gu(1.2)
                    // Toggle
                    Item {
                        width: parent.width; height: units.gu(3)
                        Switch {
                            id: swGpsFailEnabled
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            checked: panel.cfg ? panel.cfg.gpsFailEnabled : false
                            onCheckedChanged: if (panel.cfg) panel.cfg.gpsFailEnabled = checked
                        }
                        Label {
                            text: i18n.tr("Simulación fallos GPS")
                            color: pal.fgPrimary; font.pixelSize: ts(1.8)
                            anchors { left: parent.left; right: swGpsFailEnabled.left; rightMargin: units.gu(1); verticalCenter: parent.verticalCenter }
                        }
                    }
                    // Probabilidad
                    Label { text: i18n.tr("Probabilidad de fallo (%)"); color: "#90CAF9"; font.pixelSize: ts(1.6) }
                    TextField {
                        id: gpsFailProbField
                        width: parent.width
                        placeholderText: "ej. 5.00"
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        text: panel.cfg ? panel.cfg.gpsFailProb.toFixed(2) : "5.00"
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                        onTextChanged: {
                            var v = parseFloat(text)
                            if (!isNaN(v) && v >= 0 && v <= 100 && panel.cfg)
                                panel.cfg.gpsFailProb = v
                        }
                    }
                    // Distancia
                    Label { text: i18n.tr("Distancia de desvío (m)"); color: "#90CAF9"; font.pixelSize: ts(1.6) }
                    TextField {
                        id: gpsFailDistField
                        width: parent.width
                        placeholderText: "ej. 50"
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        text: panel.cfg ? panel.cfg.gpsFailDist.toFixed(0) : "50"
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                        onTextChanged: {
                            var v = parseFloat(text)
                            if (!isNaN(v) && v >= 0 && panel.cfg)
                                panel.cfg.gpsFailDist = v
                        }
                    }
                    // Ticks
                    Label { text: i18n.tr("Ticks sin señal (isReal=true)"); color: "#90CAF9"; font.pixelSize: ts(1.6) }
                    TextField {
                        id: gpsFailTicksField
                        width: parent.width
                        placeholderText: "ej. 3"
                        inputMethodHints: Qt.ImhDigitsOnly
                        text: panel.cfg ? panel.cfg.gpsFailTicks.toString() : "3"
                        onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                        onTextChanged: {
                            var v = parseInt(text)
                            if (!isNaN(v) && v >= 1 && panel.cfg)
                                panel.cfg.gpsFailTicks = v
                        }
                    }
                }
            }

            // ── Test TTS ─────────────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width
                height: units.gu(8); color: pal.bgCard; radius: 0
                property string _ttsText: ""
                Row {
                    anchors { fill: parent; margins: units.gu(1.5) }
                    spacing: units.gu(1)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - ttsSayBtn.width - units.gu(1)
                        height: units.gu(5); radius: units.gu(0.6)
                        color: "#0D1B2A"; border.color: pal.bgBtn; border.width: 1
                        NavTextInput {
                            id: ttsTestInput
                            anchors { fill: parent; leftMargin: units.gu(1); rightMargin: units.gu(1) }
                            verticalAlignment: TextInput.AlignVCenter
                            color: pal.fgPrimary; font.pixelSize: ts(1.9)
                            onTextChanged: parent.parent.parent._ttsText = text
                            onAccepted: if (panel.ttsRef && parent.parent.parent._ttsText.length > 0)
                                            panel.ttsRef.say(parent.parent.parent._ttsText)
                            onActiveFocusChanged: if (activeFocus) panel._kbdFocusItem = this
                        }
                        Label {
                            anchors { fill: parent; leftMargin: units.gu(1) }
                            verticalAlignment: Text.AlignVCenter
                            visible: ttsTestInput.text.length === 0
                            text: i18n.tr("Texto para reproducir…")
                            color: pal.fgSecondary; font.pixelSize: ts(1.9)
                        }
                    }
                    Rectangle {
                        id: ttsSayBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(8); height: units.gu(5); radius: units.gu(0.6)
                        color: ttsSayMa.pressed ? "#1B5E20" : "#2E7D32"
                        Label { anchors.centerIn: parent; text: "▶ " + i18n.tr("Decir")
                                color: pal.fgPrimary; font.pixelSize: ts(1.9); font.bold: true }
                        MouseArea {
                            id: ttsSayMa; anchors.fill: parent
                            onClicked: if (panel.ttsRef && parent.parent.parent._ttsText.length > 0)
                                           panel.ttsRef.say(parent.parent.parent._ttsText)
                        }
                    }
                }
            }

            // ── Ficheros debug ────────────────────────────────────────────
            Rectangle {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width
                height: units.gu(4); color: pal.bgCard; radius: 0
                Label {
                    anchors { left: parent.left; leftMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                    text: i18n.tr("Ficheros debug")
                    color: "#90CAF9"; font.pixelSize: ts(2); font.bold: true
                }
            }

            // Borrar al salir
            PrefListItem {
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width
                dividerColor: pal.divider
                bgIdle: pal.bgCard
                highlightColor: pal.highlight
                title.text: i18n.tr("Borrar todos los ficheros debug al salir")
                title.color: pal.fgPrimary
                title.font.pixelSize: ts(1.8)
                Switch {
                    id: swDebugCleanOnExit
                    checked: panel.cfg ? panel.cfg.debugCleanOnExit : false
                    onCheckedChanged: if (panel.cfg) panel.cfg.debugCleanOnExit = checked
                }
            }

            // Borrar todos
            Rectangle {
                id: dbgAllBtn
                visible: panel.cfg && panel.cfg.debugMode
                width: parent.width; height: units.gu(6.5); color: pal.bgCard; radius: 0
                property bool _done: false
                Timer { interval: 2500; running: parent._done; onTriggered: parent._done = false }
                Row {
                    anchors { fill: parent; margins: units.gu(1.5) }
                    spacing: units.gu(1.5)
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.55
                        text: i18n.tr("Todos los ficheros debug")
                        color: pal.fgPrimary; font.pixelSize: ts(1.9); wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - parent.width * 0.55 - units.gu(1.5); height: units.gu(4.5)
                        radius: units.gu(0.6)
                        color: dbgAllBtn._done ? "#2E7D32" : (dbgAllMa.pressed ? "#7B1FA2" : "#6A1B9A")
                        Label {
                            anchors.centerIn: parent
                            text: dbgAllBtn._done ? "✓ " + i18n.tr("Borrados") : i18n.tr("Borrar todo")
                            color: dbgAllBtn._done ? "#66BB6A" : pal.fgPrimary
                            font.pixelSize: ts(1.8); font.bold: true
                        }
                        MouseArea {
                            id: dbgAllMa; anchors.fill: parent
                            onClicked: { panel.debugFileDeleteRequested("all"); dbgAllBtn._done = true }
                        }
                    }
                }
            }

            Repeater {
                visible: panel.cfg && panel.cfg.debugMode
                model: panel.cfg && panel.cfg.debugMode ? [
                    { label: "navius_ack",         pattern: "navius_ack" },
                    { label: "navius_autostart",    pattern: "navius_autostart" },
                    { label: "navius_cmd",          pattern: "navius_cmd" },
                    { label: "navius_route",        pattern: "navius_route" },
                    { label: "navius_sl_debug.txt", pattern: "navius_sl_debug.txt" },
                    { label: "navius_trace*",       pattern: "navius_trace" },
                    { label: "net_debug.log",       pattern: "net_debug.log" },
                    { label: "piper_limit.log",     pattern: "piper_limit.log" },
                    { label: "tts_debug.log",       pattern: "tts_debug.log" }
                ] : []
                delegate: Rectangle {
                    visible: panel.cfg && panel.cfg.debugMode
                    width: parent ? parent.width : 0; height: units.gu(6); color: pal.bgCard; radius: 0
                    property bool _done: false
                    Timer { interval: 2500; running: _done; onTriggered: _done = false }
                    Row {
                        anchors { fill: parent; margins: units.gu(1.5) }
                        spacing: units.gu(1.5)
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.62
                            text: modelData.label
                            color: pal.fgDataSub; font.pixelSize: ts(1.75)
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - parent.width * 0.62 - units.gu(1.5); height: units.gu(4)
                            radius: units.gu(0.6)
                            color: parent.parent._done ? "#1B5E20" : (delMa.pressed ? "#B71C1C" : "#C62828")
                            Label {
                                anchors.centerIn: parent
                                text: parent.parent.parent._done ? "✓ " + i18n.tr("Borrado") : i18n.tr("Borrar")
                                color: parent.parent.parent._done ? "#66BB6A" : pal.fgPrimary
                                font.pixelSize: ts(1.75); font.bold: true
                            }
                            MouseArea {
                                id: delMa; anchors.fill: parent
                                onClicked: {
                                    panel.debugFileDeleteRequested(modelData.pattern)
                                    parent.parent.parent._done = true
                                }
                            }
                        }
                    }
                }
            }

        } // Column Debug

    }
    } // Flickable
}
