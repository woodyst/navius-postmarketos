use cpp::cpp;
use qmetaobject::*;

// Phosh (phosh-osk-stevia) no implementa el protocolo estándar Wayland
// text-input-v3 para mostrar/ocultar el teclado en pantalla al enfocar un
// campo de texto -- usa su propia interfaz D-Bus (sm.puri.OSK0), que solo
// GTK integra de forma nativa vía un módulo propio de Phosh. Qt5 no tiene
// ninguna integración con esto (confirmado: no existe plugin
// platforminputcontexts "wayland" en este sistema, y QT_IM_MODULE=ibus no
// dispara nada -- ni siquiera arranca ibus-daemon). Se llama a la API de
// Phosh directamente en vez de depender de Qt.inputMethod.show()/hide(),
// que en este dispositivo nunca surte efecto.
cpp! {{
    #include <QtDBus/QDBusConnection>
    #include <QtDBus/QDBusMessage>
    #include <QtCore/QString>

    extern "C" void navius_osk_set_visible(bool visible) {
        QDBusMessage msg = QDBusMessage::createMethodCall(
            QStringLiteral("sm.puri.OSK0"),
            QStringLiteral("/sm/puri/OSK0"),
            QStringLiteral("sm.puri.OSK0"),
            QStringLiteral("SetVisible"));
        msg << visible;
        QDBusConnection::sessionBus().asyncCall(msg);
    }
}}

extern "C" {
    fn navius_osk_set_visible(visible: bool);
}

#[derive(QObject, Default)]
pub struct NavOsk {
    base: qt_base_class!(trait QObject),

    // QML: navOsk.set_visible(true/false)
    pub set_visible: qt_method!(fn set_visible(&mut self, visible: bool) {
        unsafe { navius_osk_set_visible(visible) }
    }),
}
