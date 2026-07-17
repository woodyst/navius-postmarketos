import QtQuick 2.7
import Qt.labs.settings 1.0
import QtQuick.Controls 2.15
import "NavAlerts.js" as NavAlerts

Item {
    id: root
    property real textScale: 1.0
    function ts(v) { return units.gu(v * textScale) }
    anchors.fill: parent
    visible: false

    signal loginOk()
    signal logoutOk()
    signal cerrado()
    signal privacyRequired()

    property bool privacyAccepted: false

    Settings {
        id: authSettings
        category: "auth"
        property string token:      ""
        property string email:      ""
        property bool   recordar:   true   // false → limpiar token al arrancar
        property int    userId:     0
    }

    function open() {
        root.visible = true
        if (authSettings.token !== "") return   // muestra estado sesión
        _modoRegistro = false
        _limpiar()
    }
    function cerrar() { root.visible = false; root.cerrado() }

    property bool _modoRegistro: false
    property bool _ocupado: false
    property bool _puedeReenviar: false
    property bool _consentido: false

    readonly property string currentToken: authSettings.token
    readonly property string currentEmail: authSettings.email

    function _limpiar() {
        emailField.text    = ""
        passField.text     = ""
        pass2Field.text    = ""
        statusLbl.text     = ""
        statusLbl.color    = "#EF5350"
        _ocupado           = false
        _puedeReenviar     = false
        _consentido        = false
    }

    function _limpiarStatus() {
        pass2Field.text = ""
        statusLbl.text  = ""
        statusLbl.color = "#EF5350"
        _ocupado        = false
        _puedeReenviar  = false
    }

    // Fondo oscuro — bloquea clics al mapa pero no cierra el panel
    Rectangle {
        anchors.fill: parent
        color: "#000000"; opacity: 0.55
        MouseArea { anchors.fill: parent }
    }

    // Panel bottom-sheet
    Rectangle {
        id: panel
        anchors {
            bottom: parent.bottom
            bottomMargin: Qt.inputMethod.keyboardRectangle.height > 0
                          ? Qt.inputMethod.keyboardRectangle.height : 0
            left: parent.left; right: parent.right
        }
        height: contentCol.implicitHeight + units.gu(3)
        radius: units.gu(2)
        color:  "#0D1B2A"
        border.color: "#1E3A5F"
        clip: true

        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Column {
            id: contentCol
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: units.gu(1.5); leftMargin: units.gu(2); rightMargin: units.gu(2) }
            spacing: units.gu(1.2)

            // Barra de arrastre
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: units.gu(5); height: units.gu(0.5); radius: height/2; color: "#2A3A4A"
            }

            // Logo
            NaviusLogo {
                anchors.horizontalCenter: parent.horizontalCenter
                size: ts(2.6)
            }

            // Título
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: authSettings.token !== "" ? i18n.tr("Mi cuenta") : (_modoRegistro ? i18n.tr("Crear cuenta") : i18n.tr("Iniciar sesión"))
                color: "#90A4AE"; font.pixelSize: ts(2.2); font.bold: false
            }

            // ── Sesión activa ─────────────────────────────────────────
            Column {
                visible: authSettings.token !== ""
                width: parent.width; spacing: units.gu(1.2)

                Rectangle {
                    width: parent.width; height: units.gu(6.5)
                    color: "#131F2E"; radius: units.gu(0.8); border.color: "#1E3A5F"
                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                        spacing: units.gu(1.5)
                        Label { text: "✅"; font.pixelSize: ts(2.8); anchors.verticalCenter: parent.verticalCenter }
                        Label {
                            text: authSettings.email; color: "#66BB6A"
                            font.pixelSize: ts(2.1); anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: units.gu(6.5); radius: units.gu(0.8)
                    color: logoutMa.pressed ? "#1A2535" : "#1C2D40"; border.color: "#2A4060"
                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: units.gu(2) }
                        spacing: units.gu(1.5)
                        Label { text: "🚪"; font.pixelSize: ts(2.5); anchors.verticalCenter: parent.verticalCenter }
                        Label { text: i18n.tr("Cerrar sesión"); color: "#EF5350"; font.pixelSize: ts(2.3); anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                        id: logoutMa; anchors.fill: parent
                        onClicked: { authSettings.token = ""; authSettings.email = ""; root.logoutOk() }
                    }
                }

                Rectangle {
                    width: parent.width; height: units.gu(6); radius: units.gu(0.8)
                    color: closeMa.pressed ? "#1A2535" : "#1C2D40"; border.color: "#2A4060"
                    Label { anchors.centerIn: parent; text: i18n.tr("Cerrar"); color: "#90A4AE"; font.pixelSize: ts(2.3) }
                    MouseArea { id: closeMa; anchors.fill: parent; onClicked: root.cerrar() }
                }

                Item { width: 1; height: units.gu(0.5) }
            }

            // ── Aviso privacidad no aceptada ─────────────────────────
            Column {
                visible: authSettings.token === "" && !root.privacyAccepted
                width: parent.width; spacing: units.gu(1.2)
                Label {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: i18n.tr("Para iniciar sesión debes aceptar la política de privacidad de Navius.")
                    color: "#EF5350"; font.pixelSize: ts(2.0); horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    width: parent.width; height: units.gu(6); radius: units.gu(0.8)
                    color: privReqMa.pressed ? "#1565C0" : "#1976D2"; border.color: "#29B6F6"
                    Label { anchors.centerIn: parent; text: i18n.tr("Ver política de privacidad"); color: "white"; font.pixelSize: ts(2.2); font.bold: true }
                    MouseArea { id: privReqMa; anchors.fill: parent; onClicked: root.privacyRequired() }
                }
                Item { width: 1; height: units.gu(0.5) }
            }

            // ── Formulario (solo sin sesión y privacidad aceptada) ────
            Column {
                visible: authSettings.token === "" && root.privacyAccepted
                width: parent.width; spacing: units.gu(1.2)

            // Selector Entrar / Registro
            Row {
                width: parent.width
                spacing: units.gu(1)

                Rectangle {
                    width: (parent.width - units.gu(1)) / 2; height: units.gu(5)
                    color: !_modoRegistro ? "#1E3A5F" : "#131F2E"
                    border.color: "#1E3A5F"; radius: units.gu(0.8)
                    Label {
                        anchors.centerIn: parent; text: i18n.tr("Entrar")
                        color: !_modoRegistro ? "white" : "#607D8B"
                        font.pixelSize: ts(2.3); font.bold: !_modoRegistro
                    }
                    MouseArea { anchors.fill: parent; onClicked: { _modoRegistro = false; _limpiarStatus() } }
                }
                Rectangle {
                    width: (parent.width - units.gu(1)) / 2; height: units.gu(5)
                    color: _modoRegistro ? "#1E3A5F" : "#131F2E"
                    border.color: "#1E3A5F"; radius: units.gu(0.8)
                    Label {
                        anchors.centerIn: parent; text: i18n.tr("Registro")
                        color: _modoRegistro ? "white" : "#607D8B"
                        font.pixelSize: ts(2.3); font.bold: _modoRegistro
                    }
                    MouseArea { anchors.fill: parent; onClicked: { _modoRegistro = true; _limpiarStatus() } }
                }
            }

            // Campo email
            Label { text: i18n.tr("Email"); color: "#90A4AE"; font.pixelSize: ts(1.9) }
            Rectangle {
                width: parent.width; height: units.gu(5.5)
                color: "#131F2E"; radius: units.gu(0.8)
                border.color: emailField.activeFocus ? "#29B6F6" : "#1E3A5F"; border.width: 1
                TextInput {
                    id: emailField
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                    color: "#ECEFF1"; font.pixelSize: ts(2.3)
                    inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoPredictiveText
                    selectionColor: "#29B6F6"
                    KeyNavigation.tab: passField
                    Label {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "correo@ejemplo.com"
                        color: "#37474F"; font.pixelSize: ts(2.3)
                        visible: parent.text === "" && !parent.activeFocus
                    }
                }
            }

            // Campo contraseña
            Label { text: i18n.tr("Contraseña"); color: "#90A4AE"; font.pixelSize: ts(1.9) }
            Rectangle {
                width: parent.width; height: units.gu(5.5)
                color: "#131F2E"; radius: units.gu(0.8)
                border.color: passField.activeFocus ? "#29B6F6" : "#1E3A5F"; border.width: 1
                TextInput {
                    id: passField
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                    color: "#ECEFF1"; font.pixelSize: ts(2.3)
                    echoMode: TextInput.Password
                    selectionColor: "#29B6F6"
                    KeyNavigation.tab: _modoRegistro ? pass2Field : null
                    Label {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "········"
                        color: "#37474F"; font.pixelSize: ts(2.3)
                        visible: parent.text === "" && !parent.activeFocus
                    }
                }
            }

            // Confirmar contraseña (solo registro)
            Label {
                visible: _modoRegistro
                text: i18n.tr("Confirmar contraseña"); color: "#90A4AE"; font.pixelSize: ts(1.9)
            }
            Rectangle {
                visible: _modoRegistro
                width: parent.width; height: units.gu(5.5)
                color: "#131F2E"; radius: units.gu(0.8)
                border.color: pass2Field.activeFocus ? "#29B6F6" : "#1E3A5F"; border.width: 1
                TextInput {
                    id: pass2Field
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: units.gu(1.5); rightMargin: units.gu(1.5) }
                    color: "#ECEFF1"; font.pixelSize: ts(2.3)
                    echoMode: TextInput.Password
                    selectionColor: "#29B6F6"
                    Label {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "········"
                        color: "#37474F"; font.pixelSize: ts(2.3)
                        visible: parent.text === "" && !parent.activeFocus
                    }
                }
            }

            // Recordar sesión (solo en modo login)
            Rectangle {
                visible: !_modoRegistro
                width: parent.width; height: units.gu(5.5)
                color: "transparent"
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: units.gu(1.5)
                    Rectangle {
                        width: units.gu(3.2); height: units.gu(3.2); radius: units.gu(0.5)
                        color: authSettings.recordar ? "#1976D2" : "#131F2E"
                        border.color: authSettings.recordar ? "#29B6F6" : "#37474F"; border.width: 1
                        Label {
                            anchors.centerIn: parent; text: "✓"; color: "white"
                            font.pixelSize: ts(2.2); visible: authSettings.recordar
                        }
                    }
                    Label {
                        text: i18n.tr("Recordar sesión"); color: "#90A4AE"
                        font.pixelSize: ts(2.1); anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: authSettings.recordar = !authSettings.recordar }
            }

            // Mensaje de estado (error / éxito)
            Label {
                id: statusLbl
                width: parent.width
                text: ""
                color: "#EF5350"
                font.pixelSize: ts(2.0)
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                visible: text !== ""
            }

            // Botón reenviar verificación (solo cuando aplica)
            Rectangle {
                visible: _puedeReenviar
                width: parent.width; height: units.gu(5.5)
                radius: units.gu(0.8)
                color: reenviarMa.pressed ? "#1A2535" : "#1C2D40"
                border.color: "#29B6F6"
                Label {
                    anchors.centerIn: parent
                    text: i18n.tr("Reenviar email de verificación")
                    color: "#29B6F6"; font.pixelSize: ts(2.0)
                }
                MouseArea {
                    id: reenviarMa; anchors.fill: parent
                    onClicked: {
                        _ocupado = true
                        NavAlerts.reenviarVerificacion(emailField.text.trim(), function(ok) {
                            _ocupado = false
                            _puedeReenviar = false
                            statusLbl.color = "#66BB6A"
                            statusLbl.text  = ok ? "Email enviado. Revisa tu bandeja de entrada."
                                                  : "No se pudo enviar. Inténtalo más tarde."
                        })
                    }
                }
            }

            // Checkbox de consentimiento de privacidad
            Rectangle {
                width: parent.width
                height: consentRow.implicitHeight + units.gu(1)
                color: "transparent"
                Row {
                    id: consentRow
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: units.gu(1.2)
                    Rectangle {
                        width: units.gu(3.2); height: units.gu(3.2); radius: units.gu(0.5)
                        color: _consentido ? "#1976D2" : "#131F2E"
                        border.color: _consentido ? "#29B6F6" : "#37474F"; border.width: 1
                        anchors.top: consentLbl.top; anchors.topMargin: units.gu(0.2)
                        Label {
                            anchors.centerIn: parent; text: "✓"; color: "white"
                            font.pixelSize: ts(2.2); visible: _consentido
                        }
                    }
                    Label {
                        id: consentLbl
                        width: consentRow.width - units.gu(3.2) - units.gu(1.2)
                        text: i18n.tr("Acepto que mi ubicación se use para mostrar anuncios cercanos, alertas comunitarias y estadísticas de uso mientras tengo sesión iniciada.")
                        color: "#90A4AE"; font.pixelSize: ts(1.8)
                        wrapMode: Text.WordWrap
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: _consentido = !_consentido }
            }

            // Botón principal
            Rectangle {
                width: parent.width; height: units.gu(7)
                radius: units.gu(0.8)
                color: (!_consentido || _ocupado) ? "#1A2535" : (submitMa.pressed ? "#1565C0" : "#1976D2")
                border.color: _consentido ? "#29B6F6" : "#37474F"
                opacity: _consentido ? 1.0 : 0.5
                Label {
                    anchors.centerIn: parent
                    text: _ocupado ? "..." : (_modoRegistro ? i18n.tr("Crear cuenta") : i18n.tr("Entrar"))
                    color: "white"; font.pixelSize: ts(2.7); font.bold: true
                }
                MouseArea {
                    id: submitMa; anchors.fill: parent
                    enabled: !_ocupado && _consentido
                    onClicked: _submit()
                }
            }

            // Botón cancelar
            Rectangle {
                width: parent.width; height: units.gu(6)
                radius: units.gu(0.8); color: cancelMa.pressed ? "#1A2535" : "#1C2D40"
                border.color: "#2A4060"
                Label { anchors.centerIn: parent; text: i18n.tr("Cancelar"); color: "#90A4AE"; font.pixelSize: ts(2.3) }
                MouseArea { id: cancelMa; anchors.fill: parent; onClicked: root.cerrar() }
            }

            Item { width: 1; height: units.gu(0.5) }
            } // Column formulario

            Item { width: 1; height: units.gu(0.5) }
        }
    }

    function _submit() {
        if (!_consentido) return
        var email = emailField.text.trim()
        var pass  = passField.text

        if (email === "" || pass === "") {
            statusLbl.color = "#EF5350"
            statusLbl.text  = "Rellena todos los campos"
            return
        }

        if (_modoRegistro) {
            if (pass !== pass2Field.text) {
                statusLbl.color = "#EF5350"
                statusLbl.text  = "Las contraseñas no coinciden"
                return
            }
            _ocupado = true
            NavAlerts.registro(email, pass, function(ok, msg, puedeReenviar) {
                _ocupado = false
                statusLbl.color = ok ? "#66BB6A" : "#EF5350"
                statusLbl.text  = msg
                _puedeReenviar  = puedeReenviar || false
                if (ok) {
                    passField.text  = ""
                    pass2Field.text = ""
                    _modoRegistro   = false
                    statusLbl.color = "#66BB6A"
                    statusLbl.text  = "Cuenta creada. Revisa tu email para verificarla."
                }
            })
        } else {
            _ocupado = true
            NavAlerts.login(email, pass, function(ok, token, userId, msg) {
                _ocupado = false
                if (ok) {
                    passField.text      = ""
                    authSettings.token  = token
                    authSettings.email  = email
                    authSettings.userId = userId
                    root.visible = false
                    root.loginOk()
                } else {
                    statusLbl.color = "#EF5350"
                    statusLbl.text  = msg
                }
            })
        }
    }
}
