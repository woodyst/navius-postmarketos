#include "location_props.h"
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusPendingCall>
#include <algorithm>
#include <cstdio>

LocationPropsWatcher::LocationPropsWatcher(QObject *parent) : QObject(parent) {}

void LocationPropsWatcher::onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner)
{
    // Detect when LLS restarts: name appears (oldOwner empty, newOwner non-empty)
    if (name == QLatin1String("com.lomiri.location.Service") &&
        oldOwner.isEmpty() && !newOwner.isEmpty()) {
        NAVIUS_TRACE("[navius] lls: NameOwnerChanged – daemon restarted (new owner %s)\n",
                newOwner.toUtf8().constData());
        emit llsRestarted();
    }
}

LocationPropsWatcher::~LocationPropsWatcher() {
    stop_polling();
}

void LocationPropsWatcher::start_polling() {
    if (m_poll_timer) return;
    m_poll_timer = new QTimer(this);
    m_poll_timer->setInterval(1000);
    connect(m_poll_timer, &QTimer::timeout, this, &LocationPropsWatcher::onPollTimeout);
    m_poll_timer->start();
    // First poll immediately (once the event loop runs)
    QTimer::singleShot(0, this, &LocationPropsWatcher::onPollTimeout);
}

void LocationPropsWatcher::stop_polling() {
    if (!m_poll_timer) return;
    m_poll_timer->stop();
    delete m_poll_timer;
    m_poll_timer = nullptr;
    // m_pending (child of this) will fire onPollReply which checks m_poll_timer
}

bool LocationPropsWatcher::take_updated() {
    bool v = m_updated;
    m_updated = false;
    return v;
}

QVector<SpVehicle> LocationPropsWatcher::vehicles() const {
    return m_vehicles;
}


// LLS SpaceVehicle::Type (space_vehicle.h): 0=unknown 1=beidou 2=galileo
// 3=glonass 4=gps 5=compass 6=irnss 7=qzss. The rest of the app (bridge file,
// QGeoSatelliteInfoSource) uses Qt's QGeoSatelliteInfo::SatelliteSystem
// numbering: 0=Undefined 1=GPS 2=GLONASS 3=GALILEO 4=BEIDOU 5=QZSS.
static int lls_type_to_qt_system(quint32 t) {
    switch (t) {
    case 4: return 1;             // gps
    case 3: return 2;             // glonass
    case 2: return 3;             // galileo
    case 1: case 5: return 4;     // beidou / compass
    case 7: return 5;             // qzss
    default: return 0;            // unknown / irnss
    }
}

void LocationPropsWatcher::parse_svs_arg(const QDBusArgument &arg) {
    int prev_count = m_vehicles.size();
    m_vehicles.clear();
    int count = 0;

    // D-Bus type is a(uudbbbdd): array of SpaceVehicle structs where each is:
    //   u=key.type (LLS enum, see lls_type_to_qt_system)
    //   u=key.id   (PRN)
    //   d=snr
    //   b=has_almanac  b=has_ephimeris  b=used_in_fix
    //   d=azimuth  d=elevation
    arg.beginArray();
    while (!arg.atEnd()) {
        arg.beginStructure();
        quint32 sys_type = 0, prn = 0;
        double  snr = 0, azimuth = 0, elevation = 0;
        bool    has_almanac = false, has_ephimeris = false, used_in_fix = false;
        arg >> sys_type >> prn >> snr
            >> has_almanac >> has_ephimeris >> used_in_fix
            >> azimuth >> elevation;
        arg.endStructure();

        SpVehicle sv{};
        sv.prn       = (int)prn;
        sv.snr       = (float)snr;
        sv.used      = used_in_fix;
        sv.azimuth   = (float)azimuth;
        sv.elevation = (float)elevation;
        sv.system    = lls_type_to_qt_system(sys_type);
        m_vehicles.append(sv);
        ++count;
    }
    arg.endArray();

    // Unpatched LLS cross-assigns azimuth/elevation in on_sv_status_update, so
    // elevation arrives with azimuth values (up to 360°). Elevation can never
    // exceed 90°, so any such value means the whole batch is swapped — undo it.
    // Works with both patched and unpatched LLS.
    for (const SpVehicle &sv : m_vehicles) {
        if (sv.elevation > 90.0f) {
            for (SpVehicle &v : m_vehicles)
                std::swap(v.azimuth, v.elevation);
            NAVIUS_TRACE("[navius] poll svs: swapped az/el detected, normalized\n");
            break;
        }
    }

    // Signal update if satellites appeared, changed count, or just disappeared
    m_updated = (count > 0) || (prev_count > 0);
    if (NAVIUS_DEBUG) {
        fprintf(stderr, "[navius] poll svs: %d sats", count);
        for (int i = 0; i < qMin(4, (int)m_vehicles.size()); ++i)
            fprintf(stderr, " %.1f", m_vehicles[i].snr);
        fprintf(stderr, "\n");
    }
}

void LocationPropsWatcher::onPropertiesChanged(
    const QString &,
    const QVariantMap &changed,
    const QStringList &)
{
    if (!changed.contains(QStringLiteral("VisibleSpaceVehicles"))) return;

    QVariant outer = changed.value(QStringLiteral("VisibleSpaceVehicles"));
    if (outer.canConvert<QDBusVariant>())
        outer = qvariant_cast<QDBusVariant>(outer).variant();

    if (!outer.canConvert<QDBusArgument>()) {
        NAVIUS_TRACE("[navius] svs(sig): unexpected type %s\n", outer.typeName());
        return;
    }

    NAVIUS_TRACE("[navius] svs: PropertiesChanged\n");
    parse_svs_arg(qvariant_cast<QDBusArgument>(outer));
}

void LocationPropsWatcher::onPollTimeout() {
    if (m_pending) return;  // previous call still in flight

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("com.lomiri.location.Service"),
        QStringLiteral("/com/lomiri/location/Service"),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("Get"));
    msg.setArguments({
        QVariant(QStringLiteral("com.lomiri.location.Service")),
        QVariant(QStringLiteral("VisibleSpaceVehicles"))
    });

    QDBusPendingCall pending = QDBusConnection::systemBus().asyncCall(msg, 2000);
    m_pending = new QDBusPendingCallWatcher(pending, this);
    connect(m_pending, &QDBusPendingCallWatcher::finished,
            this, &LocationPropsWatcher::onPollReply);
}

void LocationPropsWatcher::onPollReply(QDBusPendingCallWatcher *watcher) {
    m_pending = nullptr;
    watcher->deleteLater();

    if (!m_poll_timer) return;  // polling was stopped while call was in flight

    QDBusMessage reply = watcher->reply();
    if (reply.type() != QDBusMessage::ReplyMessage) {
        // Transient error (ServiceUnknown, NoReply, etc.): daemon may have
        // restarted or property temporarily unavailable. Keep polling.
        NAVIUS_TRACE("[navius] poll: error %s, will retry\n",
                reply.errorName().toUtf8().constData());
        return;
    }
    m_svs_available = true;
    if (reply.arguments().isEmpty()) {
        NAVIUS_TRACE("[navius] poll svs: reply OK but empty args\n");
        return;
    }

    // Properties.Get returns v (Variant wrapping a(uudbbbdd)); unwrap all layers.
    QVariant arg0 = reply.arguments().at(0);
    while (arg0.canConvert<QDBusVariant>())
        arg0 = qvariant_cast<QDBusVariant>(arg0).variant();

    if (!arg0.canConvert<QDBusArgument>()) {
        NAVIUS_TRACE("[navius] poll svs: unexpected type %s\n", arg0.typeName());
        return;
    }

    parse_svs_arg(qvariant_cast<QDBusArgument>(arg0));
}
