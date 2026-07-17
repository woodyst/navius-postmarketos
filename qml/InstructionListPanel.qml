import QtQuick 2.7
import QtQuick.Controls 2.15
import "NavSearch.js" as NavSearch

Rectangle {
    id: panel
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }

    property var  maneuvers:    []
    property var  navWaypoints: []   // [{lat,lon,name,todos}] — para mostrar TODOs por parada
    property int  currentStep:  0
    property int  currentWpIdx: 0   // índice del waypoint actual (navBar._completedLegs)
    property bool   hasFix:      false
    property bool   imperial:    false
    property real   gpsLat:      0
    property real   gpsLon:      0
    property bool   navActive:   false
    property string poiMode:     "cerca"
    property int    poiMinutes:  10

    onNavActiveChanged: { if (!navActive) poiMode = "cerca" }

    signal closed()
    signal editRouteRequested()
    signal poiRequested(string type, string mode, int minutes)
    signal todoToggled(int waypointIndex, int todoIndex, bool done)
    signal waypointCompleted(int waypointIndex)

    // Devuelve el índice en navWaypoints del maneuver Destination en posición manIdx
    function _wpIndexForMan(manIdx) {
        var count = 0
        for (var i = 0; i < manIdx; i++) {
            var t = panel.maneuvers[i] ? panel.maneuvers[i].type : 0
            if (t === 4 || t === 5 || t === 6) count++
        }
        return count
    }

    function _todosForMan(manIdx) {
        var wpIdx = _wpIndexForMan(manIdx)
        var wps = panel.navWaypoints
        return (wps && wps[wpIdx] && wps[wpIdx].todos) ? wps[wpIdx].todos : []
    }

    color: "#F007111E"

    // Header
    Rectangle {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(7)
        color: "#07111E"

        Label {
            anchors.centerIn: parent
            text: i18n.tr("Indicaciones")
            color: "white"; font.pixelSize: ts(2.2); font.bold: true
        }

        Rectangle {
            anchors { right: parent.right; rightMargin: units.gu(1.5)
                      verticalCenter: parent.verticalCenter }
            width: units.gu(4.5); height: units.gu(4.5); radius: width / 2
            color: "#1E2A3A"
            Label {
                anchors.centerIn: parent
                text: "✕"; color: "#90A4AE"; font.pixelSize: ts(2.2)
            }
            MouseArea { anchors.fill: parent; onClicked: panel.closed() }
        }
    }

    // Maneuver list
    ListView {
        id: listView
        anchors {
            top: header.bottom; left: parent.left; right: parent.right
            bottom: panel.hasFix ? poiStrip.top : editBtn.top
        }
        clip: true
        model: panel.maneuvers

        delegate: Column {
            width: listView.width
            property int   _manIdx:  index
            property var   _man:     modelData
            property var   _todos:   (_man && (_man.type === 4 || _man.type === 5 || _man.type === 6) && panel.navWaypoints !== undefined)
                                     ? panel._todosForMan(_manIdx) : []
            property int   _wpIdx:   panel._wpIndexForMan(_manIdx)

            // Fila de maniobra
            Rectangle {
                width: parent.width
                height: Math.max(units.gu(8), instrText.implicitHeight + units.gu(3))
                color: _manIdx === panel.currentStep ? "#0D2244" : (_manIdx % 2 === 0 ? "#0A1929" : "#0C1F33")

                Row {
                    anchors { fill: parent; leftMargin: units.gu(2); rightMargin: units.gu(2) }
                    spacing: units.gu(1.5)

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(4)
                        text: NavSearch.maneuverIcon(_man.type)
                        color: _manIdx === panel.currentStep ? "#29B6F6" : "#546E7A"
                        font.pixelSize: ts(3.2)
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(4) - units.gu(7) - units.gu(3)
                        spacing: units.gu(0.3)

                        Label {
                            id: instrText
                            width: parent.width
                            text: _man.verbal_pre_transition_instruction || _man.instruction || ""
                            color: _manIdx === panel.currentStep ? "white" : "#B0BEC5"
                            font.pixelSize: ts(1.8)
                            font.bold: _manIdx === panel.currentStep
                            wrapMode: Text.WordWrap
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(7)
                        text: NavSearch.formatDist(_man.length || 0, panel.imperial)
                        color: _manIdx === panel.currentStep ? "#29B6F6" : "#546E7A"
                        font.pixelSize: ts(1.6)
                        horizontalAlignment: Text.AlignRight
                    }
                }

                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 1; color: "#1E2A3A"
                }
            }

            // Botón "Completado" para el waypoint actual (destinos intermedios y final)
            Rectangle {
                visible: (_man.type === 4 || _man.type === 5 || _man.type === 6)
                         && _wpIdx === panel.currentWpIdx && panel.navActive
                width: parent.width; height: units.gu(6)
                color: "#07180A"
                Row {
                    anchors { fill: parent; leftMargin: units.gu(2); rightMargin: units.gu(2) }
                    spacing: units.gu(1)
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - units.gu(18)
                        text: (_wpIdx < panel.navWaypoints.length)
                              ? (panel.navWaypoints[_wpIdx].name || i18n.tr("Este destino"))
                              : i18n.tr("Este destino")
                        color: "#81C784"; font.pixelSize: ts(1.7); elide: Text.ElideRight
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: units.gu(14); height: units.gu(4.5); radius: height / 2
                        color: cmpManMa.pressed ? "#1B5E20" : "#2E7D32"
                        Label { anchors.centerIn: parent; text: "✓ " + i18n.tr("Completado")
                                color: "white"; font.pixelSize: ts(1.8); font.bold: true }
                        MouseArea {
                            id: cmpManMa; anchors.fill: parent
                            onClicked: panel.waypointCompleted(_wpIdx)
                        }
                    }
                }
                Rectangle {
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 1; color: "#1E2A3A"
                }
            }

            // TODOs de esta parada (solo para maneuvers Destination con todos)
            Column {
                visible: _todos.length > 0
                width: parent.width
                spacing: 0

                Rectangle {
                    width: parent.width; height: units.gu(3.5)
                    color: "#0A1929"
                    Row {
                        anchors { left: parent.left; leftMargin: units.gu(2); verticalCenter: parent.verticalCenter }
                        spacing: units.gu(0.5)
                        Label { text: "📝"; font.pixelSize: ts(1.6) }
                        Label {
                            text: i18n.tr("Tareas en esta parada")
                            color: "#90A4AE"; font.pixelSize: ts(1.5); font.bold: true
                        }
                    }
                }

                Repeater {
                    model: _todos
                    delegate: Rectangle {
                        width: listView.width
                        height: units.gu(5.5)
                        color: "#081420"
                        property bool _done: modelData.done

                        Row {
                            anchors { fill: parent; leftMargin: units.gu(3); rightMargin: units.gu(2) }
                            spacing: units.gu(1)

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: _done ? "☑" : "☐"
                                color: _done ? "#29B6F6" : "#546E7A"
                                font.pixelSize: ts(2.2)
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - units.gu(3.5)
                                text: modelData.text
                                color: _done ? "#546E7A" : "#B0BEC5"
                                font.pixelSize: ts(1.8)
                                font.strikeout: _done
                                wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                                      leftMargin: units.gu(3) }
                            height: 1; color: "#1E2A3A"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: panel.todoToggled(_wpIdx, index, !_done)
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: units.gu(0.5)
                    color: "#0A1929"
                }
            }
        }

        ScrollView {
            anchors.fill: parent
            visible: false
        }
    }

    // POI strip (visible only when GPS fix available)
    Rectangle {
        id: poiStrip
        visible: panel.hasFix
        anchors { left: parent.left; right: parent.right; bottom: editBtn.top }
        height: panel.navActive ? units.gu(19) : units.gu(15)
        color: "#0A1929"

        Rectangle {
            width: parent.width; height: units.gu(0.08)
            anchors.top: parent.top; color: "#1E2A3A"
        }

        Column {
            anchors {
                top: parent.top; topMargin: units.gu(0.8)
                left: parent.left; leftMargin: units.gu(1.5)
                right: parent.right; rightMargin: units.gu(1)
            }
            spacing: units.gu(0.6)

            // ── Selector modo + tiempo ────────────────────────────────────
            Column {
                width: parent.width
                spacing: units.gu(0.4)

                Row {
                    visible: panel.navActive
                    width: parent.width
                    spacing: units.gu(0.7)
                    Repeater {
                        model: [{ m: "cerca",   l: i18n.tr("Cercanos")      },
                                { m: "en_ruta", l: i18n.tr("En ruta")       },
                                { m: "destino", l: i18n.tr("Cerca destino") }]
                        Rectangle {
                            width: (parent.width - 2 * units.gu(0.7)) / 3
                            height: units.gu(4.5); radius: height/2
                            color:  panel.poiMode === modelData.m ? "#1E3A5F" : "#1C2C3A"
                            border.color: panel.poiMode === modelData.m ? "#29B6F6" : "transparent"
                            border.width: units.gu(0.12)
                            Label {
                                anchors.centerIn: parent
                                text: modelData.l
                                color: panel.poiMode === modelData.m ? "#29B6F6" : "#78909C"
                                font.pixelSize: ts(1.8)
                            }
                            MouseArea { anchors.fill: parent; onClicked: panel.poiMode = modelData.m }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: units.gu(0.7)
                    Repeater {
                        model: [5, 10, 20]
                        Rectangle {
                            width: (parent.width - 2 * units.gu(0.7)) / 3
                            height: units.gu(4.5); radius: height/2
                            color:  panel.poiMinutes === modelData ? "#1E3A5F" : "#1C2C3A"
                            border.color: panel.poiMinutes === modelData ? "#29B6F6" : "transparent"
                            border.width: units.gu(0.12)
                            Label {
                                anchors.centerIn: parent
                                text: (panel.poiMode === "en_ruta" ? "±" : "") + modelData + " min"
                                color: panel.poiMinutes === modelData ? "#29B6F6" : "#78909C"
                                font.pixelSize: ts(1.8)
                            }
                            MouseArea { anchors.fill: parent; onClicked: panel.poiMinutes = modelData }
                        }
                    }
                }
            }

            // ── Botones de categoría ──────────────────────────────────────
            Flickable {
                width: parent.width
                height: units.gu(9.5)
                contentWidth: poiRow.width
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick

                Row {
                    id: poiRow
                    height: parent.height
                    spacing: units.gu(0.8)

                    Repeater {
                        model: [
                            { type: "fuel",        icon: "⛽", label: i18n.tr("Gasolina")  },
                            { type: "parking",     icon: "🅿",  label: i18n.tr("Parking")   },
                            { type: "restaurant",  icon: "🍽",  label: i18n.tr("Comer")     },
                            { type: "hotel",       icon: "🏨", label: i18n.tr("Hotel")     },
                            { type: "cafe",        icon: "☕", label: i18n.tr("Café")      },
                            { type: "supermarket", icon: "🛒", label: i18n.tr("Súper")     },
                            { type: "hospital",    icon: "🏥", label: i18n.tr("Hospital")  },
                            { type: "atm",         icon: "🏧", label: i18n.tr("Cajero")    }
                        ]
                        delegate: Rectangle {
                            width: units.gu(9); height: units.gu(9.2); radius: units.gu(0.8)
                            color: poiMa.pressed ? "#1E3A5F" : "#1C2C3A"
                            Column {
                                anchors.centerIn: parent; spacing: units.gu(0.2)
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon; font.pixelSize: ts(2.4)
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label; color: "#90A4AE"
                                    font.pixelSize: ts(1.8)
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                            MouseArea {
                                id: poiMa; anchors.fill: parent
                                onClicked: panel.poiRequested(modelData.type, panel.poiMode, panel.poiMinutes)
                            }
                        }
                    }
                }
            }
        }
    }

    // Edit route button
    Rectangle {
        id: editBtn
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: units.gu(7)
        color: "#1A237E"

        Row {
            anchors.centerIn: parent
            spacing: units.gu(1)
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: "✏"
                color: "white"; font.pixelSize: ts(2.2)
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: i18n.tr("Editar ruta")
                color: "white"; font.pixelSize: ts(2); font.bold: true
            }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: panel.editRouteRequested()
        }
    }
}
