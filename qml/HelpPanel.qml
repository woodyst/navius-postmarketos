import QtQuick 2.7
import QtQuick.Controls 2.15

Rectangle {
    id: panel
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    color: "#0D0D1A"
    visible: false

    signal closed()

    function show() { panel.visible = true }

    // Cabecera
    Rectangle {
        id: helpHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: units.gu(6)
        color: "#1C1C2E"

        Label {
            anchors.centerIn: parent
            text: i18n.tr("Manual de usuario")
            color: "white"
            font.pixelSize: units.gu(2.5)
            font.bold: true
        }

        Rectangle {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: units.gu(2) }
            width: units.gu(4); height: units.gu(4); radius: width / 2; color: "#2A2A3E"
            Label { anchors.centerIn: parent; text: "✕"; color: "#90A4AE"; font.pixelSize: ts(1.8) }
            MouseArea { anchors.fill: parent; onClicked: { panel.visible = false; panel.closed() } }
        }
    }

    Flickable {
        anchors { top: helpHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: helpCol.implicitHeight + units.gu(6)
        clip: true

        Column {
            id: helpCol
            anchors { left: parent.left; right: parent.right; leftMargin: units.gu(2); rightMargin: units.gu(2) }
            topPadding: units.gu(2)
            spacing: units.gu(2)

            // ── Componente reutilizable: sección ─────────────────────────────
            // (se construye inline con Repeater sobre un modelo de secciones)

            Repeater {
                model: [
                    {
                        icon: "🗺️",
                        title: i18n.tr("El mapa"),
                        items: [
                            { q: i18n.tr("Navegar por el mapa"),
                              a: i18n.tr("Desliza un dedo para mover el mapa. Pellizca para hacer zoom o usa la barra lateral. Toca la brújula para recentrar en tu posición y activar el seguimiento GPS.") },
                            { q: i18n.tr("Modo 2D y 3D"),
                              a: i18n.tr("El botón 2D/3D alterna entre vista plana y perspectiva inclinada de conducción. En 3D puedes ver los edificios extruidos en el área urbana.") },
                            { q: i18n.tr("Modo día / noche / automático"),
                              a: i18n.tr("En Ajustes → Ajustes rápidos puedes fijar el modo de color del mapa, o dejarlo en «auto» para que cambie con la hora del día.") },
                            { q: i18n.tr("Orientación del mapa"),
                              a: i18n.tr("Cambia entre Norte arriba y Rumbo arriba en Ajustes → Ajustes rápidos.") },
                            { q: i18n.tr("Estilos de mapa"),
                              a: i18n.tr("El botón de estilo del mapa (en el mapa) te permite ciclar entre varios estilos: Auto (cambia con el sol), Satélite (fotos aéreas), Positron (claro), Vivo/Bright (colores vivos), Fiord (oscuro suave, usado por Auto de noche) y Noche/Dark (oscuro intenso). El nombre del estilo actual aparece bajo el icono.") }
                        ]
                    },
                    {
                        icon: "🔍",
                        title: i18n.tr("Buscar y planificar"),
                        items: [
                            { q: i18n.tr("Buscar un destino"),
                              a: i18n.tr("Toca el botón «Iniciar navegación» en la parte superior para abrir el panel de planificación. Escribe el nombre de un lugar, dirección o coordenadas. La búsqueda usa OpenStreetMap.") },
                            { q: i18n.tr("Ruta con múltiples paradas"),
                              a: i18n.tr("Añade tantos destinos como necesites. La ruta pasará por todos en el orden indicado. Puedes reordenarlos o eliminarlos.") },
                            { q: i18n.tr("Opciones de ruta"),
                              a: i18n.tr("Antes de calcular puedes excluir: peajes, autopistas, ferries y pistas de tierra. También puedes elegir el tipo de vehículo en la pantalla de selección de ruta.") },
                            { q: i18n.tr("Buscar POI cercanos"),
                              a: i18n.tr("En el panel de planificación aparece la sección «POI cercanos». Selecciona la categoría y elige el resultado para añadirlo como destino. Las gasolineras muestran el precio del combustible cuando está disponible en OSM. Otros POIs muestran información adicional: horario, teléfono, web, etc.") },
                            { q: i18n.tr("Historial y favoritos"),
                              a: i18n.tr("Los últimos 50 destinos se guardan en el historial. Puedes marcar cualquier lugar como favorito y darle un nombre personalizado.") }
                        ]
                    },
                    {
                        icon: "✅",
                        title: i18n.tr("TODOs por destino"),
                        items: [
                            { q: i18n.tr("Añadir tareas a un destino"),
                              a: i18n.tr("Toca «+ Tarea» junto a cualquier destino del panel para añadir un TODO. Las tareas quedan asociadas a esa ubicación geográfica.") },
                            { q: i18n.tr("Gestionar TODOs durante la navegación"),
                              a: i18n.tr("Al llegar a un destino con TODOs, aparece un aviso en la pantalla. Toca «Abrir» para ver la lista y marcar las tareas como completadas.") },
                            { q: i18n.tr("Persistencia de TODOs"),
                              a: i18n.tr("Los TODOs se guardan por coordenadas y persisten entre sesiones. La próxima vez que planifiques una ruta al mismo lugar, aparecerán de nuevo.") }
                        ]
                    },
                    {
                        icon: "🕐",
                        title: i18n.tr("Hora de salida y planes guardados"),
                        items: [
                            { q: i18n.tr("Programar hora de salida"),
                              a: i18n.tr("Activa «Hora de salida» en la parte inferior del panel de planificación. Selecciona el día (hoy, mañana…) y la hora con los selectores. La ruta usará el tráfico predicho para ese momento.") },
                            { q: i18n.tr("Guardar un plan"),
                              a: i18n.tr("Pulsa el botón ⊕ junto a CALCULAR RUTA para guardar el plan completo (destinos + TODOs + hora de salida + opciones de ruta).") },
                            { q: i18n.tr("Cargar un plan guardado"),
                              a: i18n.tr("Los planes aparecen en la sección «Planes guardados» al inicio del panel. Toca un plan para cargarlo. Si su fecha de salida ya pasó, se actualiza automáticamente al próximo día.") },
                            { q: i18n.tr("Eliminar un plan"),
                              a: i18n.tr("Toca el icono de papelera junto al plan para borrarlo definitivamente.") }
                        ]
                    },
                    {
                        icon: "🏁",
                        title: i18n.tr("Navegación"),
                        items: [
                            { q: i18n.tr("Instrucciones de voz"),
                              a: i18n.tr("La voz avisa con antelación de cada maniobra. Las instrucciones se generan en el motor TTS configurado en Ajustes → Voz.") },
                            { q: i18n.tr("Barra de navegación"),
                              a: i18n.tr("La barra superior muestra: icono de maniobra, distancia al giro, nombre de la calle, velocidad actual, límite de velocidad y ETA (hora de llegada estimada).") },
                            { q: i18n.tr("Recálculo de ruta"),
                              a: i18n.tr("Si te desvías, Navius recalcula la ruta automáticamente.") },
                            { q: i18n.tr("Finalizar navegación"),
                              a: i18n.tr("Toca el botón de stop en la barra de navegación o cierra el panel.") }
                        ]
                    },
                    {
                        icon: "🔊",
                        title: i18n.tr("Voz (TTS)"),
                        items: [
                            { q: i18n.tr("Motores disponibles"),
                              a: i18n.tr("Piper (neural, alta calidad), Mimic HTS (español, buena calidad) y PicoTTS (básico, muy rápido). Configúralo en Ajustes → Voz.") },
                            { q: i18n.tr("Voces Piper"),
                              a: i18n.tr("Piper soporta múltiples idiomas y voces .onnx. Descarga voces adicionales desde Ajustes → Voz → Ver voces disponibles.") },
                            { q: i18n.tr("Test de voz"),
                              a: i18n.tr("En Ajustes → Voz hay un campo para escribir texto de prueba y escucharlo con el motor actual.") }
                        ]
                    },
                    {
                        icon: "🛰️",
                        title: i18n.tr("GPS y satélites"),
                        items: [
                            { q: i18n.tr("Vista de satélites"),
                              a: i18n.tr("El panel de satélites (icono de antena) muestra la posición y señal SNR de cada satélite en una vista polar acimutal.") },
                            { q: i18n.tr("Fix GPS"),
                              a: i18n.tr("El indicador de fix muestra: sin señal, fix 2D (posición sin altitud) o fix 3D (posición + altitud). La navegación requiere fix 3D.") },
                            { q: i18n.tr("Dead-reckoning"),
                              a: i18n.tr("Navius interpola la posición GPS a 10-30 Hz entre lecturas reales para que el icono de posición se mueva con fluidez. Configúralo en Ajustes → General.") },
                            { q: i18n.tr("Velocidad GPS Doppler"),
                              a: i18n.tr("Los chips GPS modernos calculan la velocidad por efecto Doppler de la señal satelital, lo que es más preciso que calcularla por diferencia de posiciones consecutivas, especialmente a baja velocidad y en arranques o frenadas bruscas. Activa esta opción en Ajustes → Navegación para usar la velocidad del hardware directamente. Si observas valores erráticos con tu dispositivo concreto, desactívala para volver al cálculo clásico.") }
                        ]
                    },
                    {
                        icon: "📈",
                        title: i18n.tr("Grabación de tracks"),
                        items: [
                            { q: i18n.tr("Grabar un track GPS"),
                              a: i18n.tr("Activa la grabación en Ajustes → Navegación. El track se guarda en SQLite con marca de tiempo y distancia acumulada.") },
                            { q: i18n.tr("Exportar a GPX"),
                              a: i18n.tr("En el panel de tracks puedes exportar cualquier track grabado al formato GPX estándar, compatible con aplicaciones externas.") }
                        ]
                    },
                    {
                        icon: "📡",
                        title: i18n.tr("Compartir viaje"),
                        items: [
                            { q: i18n.tr("¿Qué es el compartir viaje?"),
                              a: i18n.tr("Permite que otras personas sigan tu posición y ruta en tiempo real desde cualquier navegador web, sin necesidad de tener Navius instalado. Necesitas una cuenta Navius activa (sesión iniciada).") },
                            { q: i18n.tr("Cómo activar el share"),
                              a: i18n.tr("Abre el menú ≡ → toca «Compartir viaje» → «Crear enlace». Navius genera un enlace único que puedes copiar o compartir directamente por WhatsApp, Telegram o cualquier otra app. Mientras el share está activo, el ítem del menú aparece en rojo con el texto «Compartiendo».") },
                            { q: i18n.tr("¿Qué ve el seguidor?"),
                              a: i18n.tr("La página web del seguidor muestra el mapa con tu posición actualizada cada 5 segundos, tu velocidad, la ruta activa (solo el tramo restante) y los destinos con distancia y ETA. El seguidor puede cambiar el estilo del mapa (día/noche/positron/bright) y usar el botón ◎ Centrar para volver a seguir tu posición si mueve el mapa.") },
                            { q: i18n.tr("¿Qué pasa si cierro Navius?"),
                              a: i18n.tr("Si Navius se cierra o pasa a segundo plano, el seguidor ve el aviso «Navius cerrado · Última posición conocida». El enlace sigue siendo válido 24 horas.") },
                            { q: i18n.tr("Renovación automática de sesión"),
                              a: i18n.tr("Si tu sesión ha expirado al intentar compartir, Navius renueva el token automáticamente (hasta 90 días tras la caducidad) sin que tengas que volver a hacer login.") },
                            { q: i18n.tr("Cómo detener el share"),
                              a: i18n.tr("Menú ≡ → «Compartiendo» (en rojo) → «Detener». El enlace se revoca inmediatamente.") }
                        ]
                    },
                    {
                        icon: "🌐",
                        title: i18n.tr("Servidor Valhalla"),
                        items: [
                            { q: i18n.tr("Servidor oficial"),
                              a: i18n.tr("valhalla.egpsistemas.com está preconfigurado y ofrece rutas para todo el mundo con tráfico predicho, sin límite de uso para usuarios de Navius.") },
                            { q: i18n.tr("Servidor propio"),
                              a: i18n.tr("Puedes instalar tu propio servidor Valhalla y configurar su URL en Ajustes → Servidor Valhalla. Útil si quieres datos locales o privacidad total.") },
                            { q: i18n.tr("Tráfico predicho"),
                              a: i18n.tr("Valhalla usa perfiles sintéticos por hora del día y día de la semana para estimar velocidades según el tipo de vía. Las rutas programadas con hora de salida aplican automáticamente el perfil correspondiente.") },
                            { q: i18n.tr("Mapas offline con OSM Scout Server"),
                              a: i18n.tr("Instala OSM Scout Server desde la OpenStore de Ubuntu Touch para calcular rutas y buscar lugares completamente sin conexión. Navius lo detecta automáticamente en Ajustes → Servidor Valhalla → Detectar servidor local.") }
                        ]
                    },
                    {
                        icon: "⚙️",
                        title: i18n.tr("Ajustes"),
                        items: [
                            { q: i18n.tr("Nivel de opciones: Mínimo, Medio, Avanzado"),
                              a: i18n.tr("El selector de nivel en la parte superior del panel de ajustes oculta o muestra opciones según su complejidad. Mínimo: solo lo esencial. Medio: opciones adicionales de navegación. Avanzado: configuración técnica completa.") },
                            { q: i18n.tr("Controles [−] y [+]"),
                              a: i18n.tr("Los valores numéricos (frecuencia GPS, distancias, tiempos...) se ajustan con botones [−] y [+] en lugar de sliders. Esto evita que al hacer scroll por el panel se cambie el valor accidentalmente.") },
                            { q: i18n.tr("Indicador ↺ de valor por defecto"),
                              a: i18n.tr("Junto a cada opción con valor personalizado aparece el valor por defecto con el símbolo ↺ (por ejemplo: ↺ 8 m, ↺ 15 s, ↺ act.). Si el valor ya es el predeterminado, el indicador no aparece.") },
                            { q: i18n.tr("Restaurar valores por defecto"),
                              a: i18n.tr("En la parte superior del panel hay un botón ↺ Restaurar valores por defecto. Requiere dos toques para confirmar: el primero muestra el aviso ⚠, el segundo (en menos de 3 segundos) aplica el reinicio. Si no confirmas a tiempo, la acción se cancela automáticamente.") }
                        ]
                    },
                    {
                        icon: "📢",
                        title: i18n.tr("Anuncios"),
                        items: [
                            { q: i18n.tr("¿Qué son los anuncios de Navius?"),
                              a: i18n.tr("Navius puede mostrar ocasionalmente carteles de negocios locales y de la propia app en la carretera. Están diseñados para ser discretos: aparecen como señales al borde de la vía y en un pequeño panel en la parte inferior de la pantalla, sin interrumpir la navegación.") },
                            { q: i18n.tr("¿Son intrusivos?"),
                              a: i18n.tr("No. Los anuncios respetan un intervalo mínimo de 1 hora entre apariciones, no producen sonido adicional ni bloquean el mapa. Puedes cerrarlos en cualquier momento tocando la X del panel.") },
                            { q: i18n.tr("¿Cómo colaboran con Navius?"),
                              a: i18n.tr("Navius es una aplicación gratuita y de código abierto. Ver un anuncio ya supone una pequeña ayuda; si además haces click en él, contribuyes directamente a financiar el desarrollo y mantenimiento de la app. ¡Gracias por tu apoyo!") },
                            { q: i18n.tr("¿Qué datos se registran?"),
                              a: i18n.tr("Cuando el panel de anuncio aparece se registra una impresión anónima. Si haces click, el servidor anota el momento del click para estadísticas de rendimiento del anuncio. No se comparten datos con terceros.") }
                        ]
                    }
                ]

                delegate: Column {
                    width: parent.width
                    spacing: units.gu(1)

                    // Cabecera de sección
                    Rectangle {
                        width: parent.width
                        height: units.gu(5.5)
                        color: "#1C1C2E"
                        radius: units.gu(0.8)

                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter
                                      leftMargin: units.gu(1.5) }
                            spacing: units.gu(1)
                            Label {
                                text: modelData.icon
                                font.pixelSize: ts(2.5)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Label {
                                text: modelData.title
                                color: "#29B6F6"
                                font.pixelSize: ts(2.0)
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // Items Q&A
                    Column {
                        width: parent.width
                        spacing: units.gu(1.2)

                        Repeater {
                            model: modelData.items
                            delegate: Rectangle {
                                width: parent.width
                                height: qaCol.implicitHeight + units.gu(2)
                                color: "#131F2E"
                                radius: units.gu(0.6)
                                border.color: "#1E3A5F"
                                border.width: 1

                                Column {
                                    id: qaCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top
                                              margins: units.gu(1.5) }
                                    spacing: units.gu(0.5)

                                    Label {
                                        width: parent.width
                                        text: "● " + modelData.q
                                        color: "white"
                                        font.pixelSize: ts(1.7)
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                    }
                                    Label {
                                        width: parent.width
                                        text: modelData.a
                                        color: "#CFD8DC"
                                        font.pixelSize: ts(1.55)
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.3
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Donación Liberapay
            Column {
                width: parent.width
                spacing: units.gu(1)
                bottomPadding: units.gu(2)

                Rectangle {
                    width: parent.width
                    height: units.gu(5.5)
                    color: "#1C1C2E"
                    radius: units.gu(0.8)
                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter
                                  leftMargin: units.gu(1.5) }
                        spacing: units.gu(1)
                        Label { text: "❤️"; font.pixelSize: ts(2.5); anchors.verticalCenter: parent.verticalCenter }
                        Label {
                            text: i18n.tr("Apoya el desarrollo")
                            color: "#29B6F6"; font.pixelSize: ts(2.0); font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Label {
                    width: parent.width
                    text: i18n.tr("Si Navius te resulta útil, considera hacer una donación para ayudar a mantener los servidores y seguir mejorando la app.")
                    color: "#B0BEC5"
                    font.pixelSize: ts(1.55)
                    wrapMode: Text.WordWrap
                    lineHeight: 1.3
                }

                Rectangle {
                    width: parent.width
                    height: units.gu(5.5)
                    radius: units.gu(0.9)
                    color: helpDonateMa.pressed ? "#D4A800" : "#F6C915"
                    Row {
                        anchors.centerIn: parent
                        spacing: units.gu(1)
                        Label {
                            text: "♥"; color: "#1A1A1A"; font.pixelSize: ts(1.8)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: i18n.tr("Donar con Liberapay"); color: "#1A1A1A"
                            font.pixelSize: ts(1.8); font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    MouseArea {
                        id: helpDonateMa
                        anchors.fill: parent
                        onClicked: Qt.openUrlExternally("https://liberapay.com/Navius-GPS/donate")
                    }
                }
            }
        }
    }
}
