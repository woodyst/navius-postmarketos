#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusReply>
#include <QtCore/QDebug>

// Mantener la pantalla encendida mientras se navega.
//
// En Ubuntu Touch esto lo daba com.canonical.Unity.Screen (keepDisplayOn /
// removeDisplayOnRequest) en el bus del sistema. Fuera de Lomiri ese servicio no
// existe, y el port arrastraba el "[NavPower] Unity.Screen not available" de
// cada arranque: la pantalla se apagaba navegando.
//
// El equivalente en Phosh es la API estándar org.freedesktop.ScreenSaver, en el
// bus de SESIÓN (la sirve gsd-screensaver). Comprobado en el dispositivo:
//
//   org.freedesktop.ScreenSaver  →  gsd-screensaver
//     .Inhibit    (ss → u)   app_name, reason  →  cookie
//     .UnInhibit  (u)        cookie
//
// El cookie es un uint32 y aquí 0 significa "sin inhibición": es lo que asume
// el lado Rust (ver src/nav_power.rs). La API no documenta 0 como valor
// reservado, pero ningún servidor conocido lo entrega, y es el convenio que
// usan el resto de clientes de esta interfaz.
static const char* SS_SERVICE = "org.freedesktop.ScreenSaver";
static const char* SS_PATH    = "/org/freedesktop/ScreenSaver";
static const char* SS_IFACE   = "org.freedesktop.ScreenSaver";

extern "C" unsigned int navius_power_keep_on() {
    QDBusInterface iface(SS_SERVICE, SS_PATH, SS_IFACE,
                         QDBusConnection::sessionBus());
    if (!iface.isValid()) {
        qWarning() << "[NavPower] org.freedesktop.ScreenSaver no disponible";
        return 0;
    }
    QDBusReply<unsigned int> reply = iface.call(
        QStringLiteral("Inhibit"),
        QStringLiteral("Navius"),
        QStringLiteral("Navegación activa"));
    if (reply.isValid()) {
        qDebug() << "[NavPower] pantalla inhibida, cookie=" << reply.value();
        return reply.value();
    }
    qWarning() << "[NavPower] Inhibit falló:" << reply.error().message();
    return 0;
}

extern "C" void navius_power_release(unsigned int cookie) {
    if (cookie == 0) return;
    QDBusInterface iface(SS_SERVICE, SS_PATH, SS_IFACE,
                         QDBusConnection::sessionBus());
    if (iface.isValid()) {
        iface.call(QStringLiteral("UnInhibit"), cookie);
        qDebug() << "[NavPower] inhibición liberada, cookie=" << cookie;
    }
}
