#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusReply>
#include <QtCore/QDebug>

static const char* UNITY_SERVICE  = "com.canonical.Unity.Screen";
static const char* UNITY_PATH     = "/com/canonical/Unity/Screen";
static const char* UNITY_IFACE    = "com.canonical.Unity.Screen";

extern "C" int navius_power_keep_on() {
    QDBusInterface iface(UNITY_SERVICE, UNITY_PATH, UNITY_IFACE,
                         QDBusConnection::systemBus());
    if (!iface.isValid()) {
        qWarning() << "[NavPower] Unity.Screen not available";
        return -1;
    }
    QDBusReply<int> reply = iface.call("keepDisplayOn");
    if (reply.isValid()) {
        qDebug() << "[NavPower] keepDisplayOn cookie=" << reply.value();
        return reply.value();
    }
    qWarning() << "[NavPower] keepDisplayOn failed:" << reply.error().message();
    return -1;
}

extern "C" void navius_power_release(int cookie) {
    if (cookie < 0) return;
    QDBusInterface iface(UNITY_SERVICE, UNITY_PATH, UNITY_IFACE,
                         QDBusConnection::systemBus());
    if (iface.isValid()) {
        iface.call("removeDisplayOnRequest", cookie);
        qDebug() << "[NavPower] removeDisplayOnRequest cookie=" << cookie;
    }
}
