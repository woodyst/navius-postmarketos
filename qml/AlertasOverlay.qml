import QtQuick 2.7
import Qt.labs.settings 1.0
import QtQuick.Controls 2.15
import "NavAlerts.js" as NavAlerts

Item {
    id: root
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent

    // Coordenadas del vehículo (GPS en tiempo real)
    property real gpsLat:     0
    property real gpsLng:     0
    property int  gpsBearing: 0

    // Centro del mapa — usado para fetch cuando no hay GPS fix
    property real mapCenterLat: 0
    property real mapCenterLng: 0

    // Coordenadas efectivas para la alerta:
    //   - botón flotante → usa GPS
    //   - pulsación larga en mapa → el caller las sobreescribe antes de llamar a openAt()
    property real alertLat:   gpsLat
    property real alertLng:   gpsLng
    property bool isLandscape: false

    signal alertaEnviada(string categoria, string subtipo)
    signal alertasActualizadas(var lista)
    signal loginRequerido()    // emitido cuando se intenta abrir sin token

    function _fetchAlertas() {
        if (authSettings.token === "") return
        var lat = (gpsLat !== 0 || gpsLng !== 0) ? gpsLat : mapCenterLat
        var lng = (gpsLat !== 0 || gpsLng !== 0) ? gpsLng : mapCenterLng
        if (lat === 0 && lng === 0) return
        NavAlerts.obtenerAlertas(lat, lng, 15000, function(ok, lista) {
            if (ok) root.alertasActualizadas(lista)
        })
    }

    // Primer fetch: en cuanto tengamos coordenadas (GPS o centro del mapa)
    property bool _fetchedOnce: false
    function _intentarPrimerFetch() {
        if (_fetchedOnce || authSettings.token === "") return
        if (gpsLat !== 0 || gpsLng !== 0 || mapCenterLat !== 0 || mapCenterLng !== 0) {
            _fetchedOnce = true
            _fetchAlertas()
        }
    }
    onGpsLatChanged:       _intentarPrimerFetch()
    onGpsLngChanged:       _intentarPrimerFetch()
    onMapCenterLatChanged: _intentarPrimerFetch()
    onMapCenterLngChanged: _intentarPrimerFetch()

    Timer {
        id: alertasFetchTimer
        interval: 60000
        running: authSettings.token !== ""
        repeat: true
        onTriggered: root._fetchAlertas()
    }

    Settings {
        id: authSettings
        category: "auth"
        property string token: ""
        property string email: ""
        onTokenChanged: {
            if (token === "") {
                // Logout: limpiar alertas del mapa y reset del estado
                root.alertasActualizadas([])
                root._fetchedOnce = false
            } else {
                // Login: lanzar fetch inmediato
                root._fetchedOnce = false
                root._fetchAlertas()
            }
        }
    }

    Settings {
        id: colaSettings
        category: "alertas_cola"
        property string pendientes: "[]"   // JSON array de params
    }

    // Reintenta la cola al arrancar y cada 60 s
    Component.onCompleted: _enviarCola()
    Timer {
        interval: 60000; repeat: true; running: true
        onTriggered: _enviarCola()
    }

    // Solo para extracción con xgettext (ver comentario de `categorias`).
    readonly property var _i18nNoop: [
        i18n.tr("Accidente"), i18n.tr("Asistencia"), i18n.tr("Bache"),
        i18n.tr("Carril"), i18n.tr("Carril bloq."), i18n.tr("Central"),
        i18n.tr("Coche en arcén"), i18n.tr("Col. múltiple"), i18n.tr("Compañeros"),
        i18n.tr("Cortada"), i18n.tr("Cámara móvil"), i18n.tr("Denso"),
        i18n.tr("Derecho"), i18n.tr("Detenido"), i18n.tr("Emergencia"),
        i18n.tr("Error mapa"), i18n.tr("Hielo"), i18n.tr("Inundación"),
        i18n.tr("Izquierdo"), i18n.tr("Lugar"), i18n.tr("Mal tiempo"),
        i18n.tr("Niebla"), i18n.tr("Nieve"), i18n.tr("Obras"),
        i18n.tr("Oculto"), i18n.tr("Peligro"), i18n.tr("Policía"),
        i18n.tr("Resbaladiza"), i18n.tr("Semáforo roto"), i18n.tr("Tráfico")
    ]

    // ── DATOS ────────────────────────────────────────────────────────
    // Las etiquetas se guardan en español y se traducen AL PINTARLAS, con
    // i18n.tr(modelData.label) más abajo. No se envuelven aquí a propósito:
    // este overlay se instancia al arrancar (Main.qml, sin Loader), y un
    // `readonly property var` se evalúa en ese momento — posiblemente antes
    // de que i18n tenga el locale cargado. Es el mismo fallo que tuvo
    // TourOverlay (sesión 98) y que se arregló difiriendo la evaluación.
    //
    // Como xgettext no puede extraer cadenas de un array, la lista _i18nNoop
    // de abajo existe solo para que entren en el .pot. No se usa en runtime.
    readonly property var categorias: [
        { id: "trafico",           icon: "🚗", label: "Tráfico",     otroLado: false,
          subs: [
            { icon: "🚗", label: "Tráfico",   sub: "" },
            { icon: "🐢", label: "Denso",     sub: "denso" },
            { icon: "🛑", label: "Detenido",  sub: "detenido" }
          ]
        },
        { id: "policia",           icon: "👮", label: "Policía",     otroLado: true,
          subs: [
            { icon: "👮", label: "Policía",      sub: "" },
            { icon: "📸", label: "Cámara móvil", sub: "camara_movil" },
            { icon: "🫣", label: "Oculto",       sub: "oculto" }
          ]
        },
        { id: "accidente",         icon: "💥", label: "Accidente",   otroLado: true,
          subs: [
            { icon: "💥", label: "Accidente",        sub: "" },
            { icon: "🚨", label: "Col. múltiple",    sub: "colision_multiple" }
          ]
        },
        { id: "peligro",           icon: "⚠️", label: "Peligro",     otroLado: true,
          subs: [
            { icon: "⚠️", label: "Peligro",        sub: "" },
            { icon: "🦺", label: "Obras",           sub: "obras" },
            { icon: "🚗", label: "Coche en arcén",  sub: "coche_arcen" },
            { icon: "🚦", label: "Semáforo roto",   sub: "semaforo_estropeado" },
            { icon: "🕳️", label: "Bache",           sub: "bache" }
          ]
        },
        { id: "carretera_cortada", icon: "🚧", label: "Cortada",     otroLado: false, subs: [] },
        { id: "carril_bloqueado",  icon: "⛔", label: "Carril",      otroLado: false,
          subs: [
            { icon: "⛔", label: "Carril bloq.", sub: "" },
            { icon: "⬅️", label: "Izquierdo",   sub: "izquierdo" },
            { icon: "➡️", label: "Derecho",     sub: "derecho" },
            { icon: "⬆️", label: "Central",     sub: "central" }
          ]
        },
        { id: "error_mapa",        icon: "🗺️", label: "Error mapa", otroLado: false, subs: [] },
        { id: "mal_tiempo",        icon: "🌧️", label: "Mal tiempo", otroLado: false,
          subs: [
            { icon: "🌧️", label: "Mal tiempo",    sub: "" },
            { icon: "💧", label: "Resbaladiza",    sub: "calzada_resbaladiza" },
            { icon: "🌊", label: "Inundación",     sub: "inundacion" },
            { icon: "❄️", label: "Nieve",          sub: "nieve" },
            { icon: "🌫️", label: "Niebla",         sub: "niebla" },
            { icon: "🧊", label: "Hielo",          sub: "hielo" }
          ]
        },
        { id: "asistencia",        icon: "🆘", label: "Asistencia",  otroLado: false,
          subs: [
            { icon: "👥", label: "Compañeros",  sub: "companeros" },
            { icon: "🚨", label: "Emergencia",  sub: "emergencia" }
          ]
        },
        { id: "lugar",             icon: "📍", label: "Lugar",       otroLado: false, subs: [] }
    ]

    property int  fase:        0    // 0=categorías, 1=subopciones
    property int  catIdx:     -1
    property bool _otroLado:  false
    // Abre el panel usando coordenadas GPS del vehículo
    function open() {
        alertLat = gpsLat
        alertLng = gpsLng
        _resetPanel()
    }

    // Abre el panel con coordenadas arbitrarias (pulsación larga en mapa)
    function openAt(lat, lng) {
        alertLat = lat
        alertLng = lng
        _resetPanel()
    }

    // Llamado desde Main.qml tras login exitoso para continuar con la alerta pendiente
    function continuarTrasLogin() {
        if (alertLat !== 0 || alertLng !== 0) _resetPanel()
    }

    function _resetPanel() {
        fase       = 0
        catIdx     = -1
        _otroLado  = false
        panel.visible = true
    }

    // ── FONDO OSCURO ─────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color:   "#000000"
        opacity: 0.55
        visible: panel.visible
        MouseArea { anchors.fill: parent; onClicked: panel.visible = false }
    }

    // ── PANEL (bottom sheet en portrait, centrado en landscape) ─────────────
    Rectangle {
        id: panel
        visible: false
        anchors {
            bottom:           isLandscape ? undefined             : parent.bottom
            left:             isLandscape ? undefined             : parent.left
            right:            isLandscape ? undefined             : parent.right
            horizontalCenter: isLandscape ? parent.horizontalCenter : undefined
            verticalCenter:   isLandscape ? parent.verticalCenter   : undefined
        }
        width:  isLandscape ? Math.min(parent.width * 0.85, units.gu(80)) : parent.width
        height: Math.min(contentCol.implicitHeight + units.gu(3),
                         isLandscape ? parent.height * 0.88 : parent.height)
        radius: units.gu(2)
        color:  "#0D1B2A"
        border.color: "#1E3A5F"
        clip: true

        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Flickable {
            id: panelFlick
            anchors { fill: parent
                      topMargin: units.gu(1.5); leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
            contentHeight: contentCol.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            clip: true

        Column {
            id: contentCol
            width: panelFlick.width
            spacing: units.gu(1.2)

            // Barra de arrastre
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(5); height: units.gu(0.5); radius: height / 2; color: "#2A3A4A"
            }

            // Fila título + botón volver
            Item {
                width: parent.width
                height: titleLbl.implicitHeight

                Rectangle {
                    visible: fase === 1
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: units.gu(4); height: units.gu(4); color: "transparent"
                    Label { anchors.centerIn: parent; text: "◀"; color: "#90A4AE"; font.pixelSize: ts(3.3) }
                    MouseArea { anchors.fill: parent; onClicked: fase = 0 }
                }

                Label {
                    id: titleLbl
                    anchors.centerIn: parent
                    text: fase === 0 ? i18n.tr("Añadir alerta")
                                     : (catIdx >= 0 ? i18n.tr(categorias[catIdx].label) : "")
                    color: "white"
                    font.pixelSize: ts(3.3)
                    font.bold: true
                }
            }

            // ── Fase 0: grid de categorías ──────────────────────────
            Grid {
                id: catGrid
                visible: fase === 0
                width: parent.width
                columns: isLandscape ? 5 : 4
                spacing: units.gu(0.8)

                Repeater {
                    model: categorias
                    delegate: Rectangle {
                        width:  (catGrid.width - catGrid.spacing * (catGrid.columns - 1)) / catGrid.columns
                        height: isLandscape ? units.gu(9) : units.gu(14)
                        radius: units.gu(1)
                        color:  cma.pressed ? "#1A2535" : "#131F2E"
                        border.color: "#1E3A5F"

                        Column {
                            anchors.centerIn: parent
                            spacing: units.gu(0.4)
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                font.pixelSize: ts(4.8)
                            }
                            Label {
                                width: parent.parent.width - units.gu(0.6)
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: i18n.tr(modelData.label)
                                color: "#CFD8DC"
                                font.pixelSize: ts(2.1)
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        MouseArea {
                            id: cma; anchors.fill: parent
                            onClicked: {
                                catIdx    = index
                                _otroLado = false
                                fase      = 1
                            }
                        }
                    }
                }
            }

            // ── Fase 1: subopciones ─────────────────────────────────
            Grid {
                id: subGrid
                visible: fase === 1 && catIdx >= 0
                width: parent.width
                columns: 3
                spacing: units.gu(0.8)

                Repeater {
                    model: (fase === 1 && catIdx >= 0) ? categorias[catIdx].subs : []
                    delegate: Rectangle {
                        width:  (subGrid.width - subGrid.spacing * 2) / 3
                        height: isLandscape ? units.gu(9) : units.gu(14)
                        radius: units.gu(1)
                        color:  sma.pressed ? "#1A2535" : "#131F2E"
                        border.color: "#1E3A5F"

                        Column {
                            anchors.centerIn: parent
                            spacing: units.gu(0.4)
                            Label {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.icon
                                font.pixelSize: ts(4.8)
                            }
                            Label {
                                width: parent.parent.width - units.gu(0.6)
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: i18n.tr(modelData.label)
                                color: "#CFD8DC"
                                font.pixelSize: ts(2.1)
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                        MouseArea {
                            id: sma; anchors.fill: parent
                            onClicked: {
                                var cat = categorias[catIdx]
                                var carril = (cat.id === "carril_bloqueado") ? modelData.sub : ""
                                var sub    = (cat.id === "carril_bloqueado") ? "" : modelData.sub
                                _enviar(cat.id, sub, _otroLado, carril)
                            }
                        }
                    }
                }
            }

            // Botón Enviar (categorías sin subopciones)
            Rectangle {
                visible: fase === 1 && catIdx >= 0 && categorias[catIdx].subs.length === 0
                width: parent.width; height: units.gu(8); radius: units.gu(0.8)
                color: envSinSubMa.pressed ? "#1A3A1A" : "#1B5E20"
                border.color: "#2E7D32"
                Label {
                    anchors.centerIn: parent; text: i18n.tr("Enviar")
                    color: "white"; font.pixelSize: ts(2.7); font.bold: true
                }
                MouseArea {
                    id: envSinSubMa; anchors.fill: parent
                    onClicked: _enviar(categorias[catIdx].id, "", false, "")
                }
            }

            // Toggle "al otro lado" (solo categorías que lo soportan)
            Rectangle {
                visible: fase === 1 && catIdx >= 0 && categorias[catIdx].otroLado
                width: parent.width
                height: units.gu(8)
                radius: units.gu(0.8)
                color:  "#131F2E"
                border.color: "#1E3A5F"

                Row {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                    spacing: units.gu(1)
                    Label {
                        text: "↔  " + i18n.tr("Al otro lado")
                        color: "#90A4AE"
                        font.pixelSize: ts(2.55)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - otroSwitch.width - units.gu(1)
                    }
                    Switch {
                        id: otroSwitch
                        anchors.verticalCenter: parent.verticalCenter
                        checked: _otroLado
                        onCheckedChanged: _otroLado = checked
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { _otroLado = !_otroLado; otroSwitch.checked = _otroLado }
                }
            }

            // Botón cancelar
            Rectangle {
                width: parent.width
                height: units.gu(8)
                radius: units.gu(0.8)
                color: cancelMa.pressed ? "#1A2535" : "#1C2D40"
                border.color: "#2A4060"
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Cancelar")
                    color: "#90A4AE"
                    font.pixelSize: ts(2.7)
                }
                MouseArea { id: cancelMa; anchors.fill: parent; onClicked: panel.visible = false }
            }

            // Espaciado inferior de seguridad
            Item { width: 1; height: units.gu(0.5) }
        }  // fin contentCol

        }  // fin panelFlick
    }

    function _enviar(categoria, subtipo, otroLadoVal, carril) {
        panel.visible = false
        var params = { categoria: categoria, lat: alertLat, lng: alertLng, bearing: gpsBearing }
        if (subtipo)        params.subtipo   = subtipo
        if (otroLadoVal)    params.otro_lado = true
        if (carril)         params.carril    = carril

        NavAlerts.enviarAlerta(authSettings.token, params, function(ok, status) {
            if (ok) {
                root.alertaEnviada(categoria, subtipo || "")
                Qt.callLater(root._fetchAlertas)
            } else if (status === 0) {
                // Sin red — guardar en cola para reenviar después
                _encolar(params)
            } else {
                console.warn("Alerta rechazada por servidor, status:", status)
            }
        })
    }

    function _encolar(params) {
        try {
            var cola = JSON.parse(colaSettings.pendientes)
            cola.push(params)
            colaSettings.pendientes = JSON.stringify(cola)
        } catch(e) {
            colaSettings.pendientes = JSON.stringify([params])
        }
    }

    function _enviarCola() {
        if (authSettings.token === "") return
        var cola
        try { cola = JSON.parse(colaSettings.pendientes) } catch(e) { cola = [] }
        if (cola.length === 0) return

        var pendientes = cola.slice()
        colaSettings.pendientes = "[]"

        for (var i = 0; i < pendientes.length; i++) {
            (function(p) {
                NavAlerts.enviarAlerta(authSettings.token, p, function(ok, status) {
                    if (!ok && status === 0) _encolar(p)   // sigue sin red, vuelve a cola
                })
            })(pendientes[i])
        }
    }
}
