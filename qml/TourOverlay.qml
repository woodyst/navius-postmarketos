import QtQuick 2.7
import Qt.labs.settings 1.0
import QtQuick.Controls 2.15

Item {
    id: overlay
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false
    z: 210

    signal tourClosed()
    signal voicesRequested()

    Settings {
        id: tourSettings
        category: "tour"
        property bool showOnStart: true
    }

    property var steps: []

    function _buildSteps() { return [
        {
            icon: "🧭",
            title: i18n.tr("Bienvenido a Navius"),
            body: i18n.tr("Navius es un navegador GPS para Ubuntu Touch. Combina mapas vectoriales offline, navegación turn-by-turn con voz, planificación avanzada de rutas y soporte completo para moverse por todo el mundo.\n\nEste asistente te guiará por todas las funciones de la aplicación. Puedes consultar este tour en cualquier momento desde Ajustes → Ayuda.")
        },
        {
            icon: "🗺️",
            title: i18n.tr("El mapa"),
            body: i18n.tr("El mapa es vectorial (MapLibre GL) — se ve nítido a cualquier zoom y funciona sin conexión una vez descargados los tiles.\n\n• Pellizca para zoom o usa la barra lateral\n• Toca el botón de brújula para recentrar y activar seguimiento\n• Desliza un dedo para explorar libremente\n• El botón 3D/2D alterna entre vista plana y perspectiva de conducción\n• En modo noche el mapa cambia automáticamente a paleta oscura")
        },
        {
            icon: "🔍",
            title: i18n.tr("Buscar un destino"),
            body: i18n.tr("Toca el botón «Iniciar navegación» en la parte superior para abrir el panel de planificación.\n\nEscribe el nombre de un lugar, dirección o punto de interés. La búsqueda usa Photon/Komoot con datos de OpenStreetMap y funciona para cualquier lugar del mundo.\n\n• Toca un resultado para añadirlo como destino\n• Puedes añadir varios destinos en secuencia (ruta multistop)\n• El historial y los favoritos aparecen automáticamente")
        },
        {
            icon: "📍",
            title: i18n.tr("Planificación de ruta"),
            body: i18n.tr("Con el panel abierto puedes configurar todos los detalles de tu viaje:\n\n• Añade múltiples destinos — la ruta pasa por todos en orden\n• Reordena o elimina destinos con los botones junto a cada uno\n• Opciones de ruta: sin peajes, sin autopistas, sin ferries, sin tierra\n• Busca POI cercanos: gasolineras (con precio del combustible), parking, restaurantes, hoteles…\n• Pulsa CALCULAR RUTA para ver las alternativas disponibles")
        },
        {
            icon: "✅",
            title: i18n.tr("TODOs por destino"),
            body: i18n.tr("Puedes añadir una lista de tareas pendientes a cada destino del viaje.\n\n• Toca '+ Tarea' junto a un destino para añadir un TODO\n• Las tareas se guardan asociadas a la ubicación (por coordenadas)\n• Al llegar al destino aparece un aviso para abrir la lista\n• Marca las tareas como hechas directamente en el panel\n\nLos TODOs se conservan entre sesiones y se muestran la próxima vez que visites el mismo lugar.")
        },
        {
            icon: "🕐",
            title: i18n.tr("Hora de salida y planes guardados"),
            body: i18n.tr("Activa «Hora de salida» para planificar un viaje futuro. Selecciona el día y la hora de partida — la ruta se calculará usando el tráfico previsto para ese momento.\n\n• Pulsa ⊕ junto a CALCULAR RUTA para guardar el plan completo\n• Los planes incluyen destinos, TODOs, hora de salida y opciones de ruta\n• Aparecen en la sección «Planes guardados» en la parte superior del panel\n• Toca un plan para cargarlo, o el icono de papelera para borrarlo")
        },
        {
            icon: "🔀",
            title: i18n.tr("Selección de ruta y alternativas"),
            body: i18n.tr("Navius solicita hasta 3 alternativas de ruta a Valhalla. Tras calcular, aparece el panel de selección:\n\n• Cada alternativa muestra distancia, tiempo y ruta en el mapa\n• Elige el tipo de vehículo: coche, moto, bicicleta, a pie y más\n• Toca una alternativa para verla; confirma para iniciar la navegación\n• También puedes ver la lista completa de instrucciones antes de salir")
        },
        {
            icon: "🏁",
            title: i18n.tr("Navegación turn-by-turn"),
            body: i18n.tr("Durante la navegación, la barra superior muestra:\n\n• La instrucción actual con icono de maniobra\n• Distancia al siguiente giro\n• Nombre de la calle actual y la siguiente\n• Hora de llegada estimada (ETA)\n• Tu velocidad actual y el límite de velocidad del tramo\n\nLas instrucciones se anuncian por voz con antelación suficiente para reaccionar a tiempo.")
        },
        {
            icon: "⚠️",
            title: i18n.tr("Alertas comunitarias"),
            body: i18n.tr("Otros conductores de Navius reportan incidencias en tiempo real que aparecen en tu mapa.\n\n• Accidentes, radar móvil, policía, tráfico, peligros, obras…\n• Toca el botón triangular de advertencia en el mapa para reportar\n• Las alertas activas en tu ruta se muestran con aviso sonoro\n• Confirma o desmiente las alertas de otros usuarios con los botones de voto\n\nRequiere cuenta Navius activa.")
        },
        {
            icon: "📡",
            title: i18n.tr("Compartir viaje"),
            body: i18n.tr("Comparte tu posición y ruta en tiempo real con cualquier persona, sin que necesite tener Navius instalado.\n\n• Menú ≡ → Compartir viaje → Crear enlace\n• Copia el enlace y compártelo por el medio que prefieras\n• El seguidor ve tu posición actualizada cada 5 segundos en su navegador\n• El enlace es válido durante 24 horas\n• Detén el share desde el mismo menú en cualquier momento\n\nRequiere cuenta Navius activa.")
        },
        {
            icon: "🔊",
            title: i18n.tr("Instrucciones de voz (TTS)"),
            body: i18n.tr("La voz usa el motor seleccionado en Ajustes → Voz:\n\n• Piper (neural): la más natural, ~300 ms de latencia, descarga voces .onnx\n• Mimic HTS: español integrado, ~100 ms, buena calidad\n• PicoTTS: motor de reserva, ~50 ms, calidad básica\n\nPiper pre-genera los WAVs de las próximas instrucciones en segundo plano para que la voz suene sin retraso perceptible.")
        },
        {
            icon: "🎵",
            title: i18n.tr("Reproductor de música"),
            body: i18n.tr("Navius incluye un reproductor de música integrado. Importa pistas vía Content Hub — Menú ≡ → Música → Añadir música.\n\n• Toca una pista para reproducir\n• Soporta mp3, ogg, flac, m4a, opus, wav y más\n• El widget compacto queda visible sobre la barra de estado\n• La música baja automáticamente cuando el navegador habla (ducking)\n  y se restaura 600 ms después")
        },
        {
            icon: "📊",
            title: i18n.tr("Velocímetro y límites de velocidad"),
            body: i18n.tr("El velocímetro circular muestra tu velocidad en tiempo real.\n\n• El límite de velocidad del tramo actual aparece en la barra de navegación\n• Si superas el límite, el indicador cambia de color (configurable en Ajustes)\n• Los límites provienen de los datos OSM con el estándar Legal Default Speeds")
        },
        {
            icon: "🛰️",
            title: i18n.tr("Vista de satélites"),
            body: i18n.tr("La vista de satélites muestra en tiempo real:\n\n• Posición de cada satélite en el cielo (vista polar acimutal)\n• Intensidad de señal (SNR) de cada satélite en uso\n• Número de satélites visibles y en uso\n• Estado del fix GPS (sin fix / fix 2D / fix 3D)\n\nÚtil para diagnosticar problemas de recepción GPS o comparar señal en distintas ubicaciones.")
        },
        {
            icon: "✉️",
            title: i18n.tr("Mensajes del servidor"),
            body: i18n.tr("El servidor de Navius puede enviarte mensajes: avisos, novedades o notificaciones.\n\n• Menú ≡ → Mensajes para ver tu bandeja\n• El contador junto al icono indica mensajes sin leer\n• Los mensajes nuevos muestran un banner de notificación\n• Algunos mensajes incluyen un botón Navegar con un destino directo\n\nRequiere cuenta Navius activa.")
        },
        {
            icon: "📍",
            title: i18n.tr("Grabación de tracks"),
            body: i18n.tr("Navius puede grabar tu trayecto GPS en tiempo real.\n\n• Activa «Grabar track» en Ajustes → Navegación\n• Los tracks grabados aparecen en Ajustes → Navegación → Tracks grabados\n• Opciones: ver en mapa, exportar a GPX, simular o eliminar\n• La simulación reproduce el track como si fuera un viaje real:\n  todas las funciones de navegación funcionan sobre el track grabado")
        },
        {
            icon: "🌐",
            title: i18n.tr("Servidor oficial Valhalla"),
            body: i18n.tr("Navius incluye el servidor valhalla.egpsistemas.com configurado por defecto.\n\n• Cobertura mundial: planeta completo (OpenStreetMap)\n• Tráfico predicho por hora del día y día de semana en toda la red viaria\n• Todos los tipos de vehículo: coche, moto, camión, bicicleta, a pie…\n• Alternativas de ruta, sin peajes, sin autopistas, sin ferries\n• Alta disponibilidad, sin límite de uso para usuarios de Navius\n\nTambién puedes configurar tu propio servidor en Ajustes → Servidor Valhalla.\n\n🗺 Mapas offline: instala OSM Scout Server en Ubuntu Touch para calcular rutas y buscar lugares sin conexión a internet, directamente en el dispositivo.")
        },
        {
            icon: "⚙️",
            title: i18n.tr("Ajustes"),
            body: i18n.tr("El panel de Ajustes organiza la configuración en secciones:\n\n• Ajustes rápidos: modo día/noche, zoom automático, orientación del mapa\n• General: interpolación GPS, dead-reckoning, alertas de velocidad\n• Servidor Valhalla: URL del servidor, detección de servidor local\n• Navegación: tipo de vehículo, aparcamiento, grabación de tracks\n• Voz: motor TTS, idioma, voces disponibles, test de voz\n• Ayuda: este tour, manual de usuario, información de la app\n\nTus ajustes se sincronizan automáticamente si tienes cuenta Navius activa.")
        },
        {
            icon: "🎉",
            title: i18n.tr("¡Listo para navegar!"),
            body: i18n.tr("Ya conoces Navius. Aquí un resumen rápido:\n\n① Toca «Iniciar navegación» para buscar un destino\n② Elige ruta y pulsa Iniciar\n③ Sigue las instrucciones de voz\n④ Reporta alertas a otros conductores\n⑤ Al llegar, marca los TODOs completados\n\nMás funciones: música 🎵 · compartir viaje 📡 · mensajes ✉️ · tracks 📍\n\nPuedes volver a este tour en cualquier momento desde\nAjustes → Ayuda → Abrir asistente.")
        }
    ] }

    property int  _step: 0
    property bool _voiceTipMode: false

    function show() {
        _voiceTipMode = false
        steps = _buildSteps()
        _step = 0
        overlay.visible = true
    }

    function showVoiceTip() {
        if (overlay.visible) return
        _voiceTipMode = true
        steps = [{
            icon: "🔊",
            title: i18n.tr("Descarga una voz Piper"),
            body: i18n.tr("Navius usa el motor Piper para voz de alta calidad.\n\nNo hay ninguna voz Piper instalada para tu idioma. Sin ella, las instrucciones de navegación usarán PicoTTS o espeak-ng, que suenan menos naturales.\n\nPulsa «Gestionar voces» para descargar una voz Piper.")
        }]
        _step = 0
        overlay.visible = true
    }

    function dismiss() {
        overlay.visible = false
        _voiceTipMode = false
        overlay.tourClosed()
    }

    function checkShowAtStartup() {
        if (tourSettings.showOnStart)
            show()
    }

    // Fondo oscuro semitransparente
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.80
        MouseArea { anchors.fill: parent }
    }

    // Card centrado
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - units.gu(4), units.gu(48))
        height: Math.min(parent.height - units.gu(8), units.gu(72))
        radius: units.gu(1.5)
        color: "#0D1B2A"
        border.color: "#1E3A5F"
        border.width: units.gu(0.1)
        clip: true

        // Franja azul superior
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: units.gu(0.5)
            color: "#1565C0"
        }

        // Indicador de paso (puntitos)
        Row {
            id: dotsRow
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: units.gu(1.2) }
            spacing: units.gu(0.7)
            Repeater {
                model: overlay.steps.length
                delegate: Rectangle {
                    width: index === overlay._step ? units.gu(1.8) : units.gu(0.8)
                    height: units.gu(0.8)
                    radius: height / 2
                    color: index === overlay._step ? "#1565C0" : "#2A3A4A"
                    Behavior on width { NumberAnimation { duration: 150 } }
                }
            }
        }

        // Contenido del paso
        Flickable {
            id: stepFlick
            anchors {
                top: dotsRow.bottom; left: parent.left; right: parent.right; bottom: btnRow.top
                topMargin: units.gu(1); bottomMargin: units.gu(1)
                leftMargin: units.gu(2.5); rightMargin: units.gu(2.5)
            }
            contentHeight: stepCol.implicitHeight
            clip: true

            Column {
                id: stepCol
                width: parent.width
                spacing: units.gu(1.5)

                // Icono
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: overlay.steps.length > overlay._step ? overlay.steps[overlay._step].icon : ""
                    font.pixelSize: ts(5)
                }

                // Título
                Label {
                    width: parent.width
                    text: overlay.steps.length > overlay._step ? overlay.steps[overlay._step].title : ""
                    color: "white"
                    font.pixelSize: ts(2.4)
                    font.bold: true
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                // Separador
                Rectangle {
                    width: parent.width * 0.4
                    height: units.gu(0.05)
                    color: "#1E3A5F"
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // Cuerpo
                Label {
                    width: parent.width
                    text: overlay.steps.length > overlay._step ? overlay.steps[overlay._step].body : ""
                    color: "#CFD8DC"
                    font.pixelSize: ts(1.65)
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                }

                // Toggle "no mostrar al inicio" (solo último paso)
                Rectangle {
                    visible: overlay._step === overlay.steps.length - 1
                    width: parent.width
                    height: units.gu(5.5)
                    radius: units.gu(0.8)
                    color: "#131F2E"
                    border.color: "#1E3A5F"
                    border.width: 1

                    Row {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                  leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                        spacing: units.gu(1)

                        Label {
                            text: i18n.tr("No mostrar al inicio")
                            color: "#90A4AE"
                            font.pixelSize: ts(1.7)
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - units.gu(8)
                            wrapMode: Text.WordWrap
                        }

                        Switch {
                            id: noStartSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: !tourSettings.showOnStart
                            onCheckedChanged: tourSettings.showOnStart = !checked
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            tourSettings.showOnStart = !tourSettings.showOnStart
                            noStartSwitch.checked = !tourSettings.showOnStart
                        }
                    }
                }
            }
        }

        // Botones inferiores
        Row {
            id: btnRow
            anchors {
                bottom: parent.bottom; left: parent.left; right: parent.right
                margins: units.gu(2.5); bottomMargin: units.gu(2.5)
            }
            spacing: units.gu(1.5)

            // Botón izquierdo: "Saltar tour" / "Anterior" / "Cerrar" (tip)
            Rectangle {
                width: (parent.width - units.gu(1.5)) / 2
                height: units.gu(5.5)
                radius: units.gu(0.9)
                color: prevMa.pressed ? "#1A2535" : "#1C2D40"
                border.color: "#2A4060"
                border.width: 1

                Label {
                    anchors.centerIn: parent
                    text: overlay._voiceTipMode ? i18n.tr("Cerrar")
                          : (overlay._step === 0 ? i18n.tr("Saltar tour")
                             : (overlay._step === overlay.steps.length - 1 ? i18n.tr("Atrás") : i18n.tr("Anterior")))
                    color: "#90A4AE"
                    font.pixelSize: ts(1.8)
                }
                MouseArea {
                    id: prevMa; anchors.fill: parent
                    onClicked: {
                        if (overlay._voiceTipMode) { overlay.dismiss(); return }
                        if (overlay._step === 0) overlay.dismiss()
                        else { overlay._step--; stepFlick.contentY = 0 }
                    }
                }
            }

            // Botón derecho: "Siguiente" / "¡Comenzar!" / "Gestionar voces" (tip)
            Rectangle {
                width: (parent.width - units.gu(1.5)) / 2
                height: units.gu(5.5)
                radius: units.gu(0.9)
                color: nextMa.pressed ? "#0D47A1" : "#1565C0"

                Label {
                    anchors.centerIn: parent
                    text: overlay._voiceTipMode ? i18n.tr("Gestionar voces")
                          : (overlay._step === overlay.steps.length - 1 ? i18n.tr("¡Comenzar!") : i18n.tr("Siguiente"))
                    color: "white"
                    font.pixelSize: ts(1.8)
                    font.bold: true
                }
                MouseArea {
                    id: nextMa; anchors.fill: parent
                    onClicked: {
                        if (overlay._voiceTipMode) {
                            overlay.dismiss()
                            overlay.voicesRequested()
                            return
                        }
                        if (overlay._step < overlay.steps.length - 1) {
                            overlay._step++; stepFlick.contentY = 0
                        } else {
                            overlay.dismiss()
                        }
                    }
                }
            }
        }
    }
}
