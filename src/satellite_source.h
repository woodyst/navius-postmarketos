#pragma once
#include <QtCore/QObject>
#include <QtCore/QList>
#include <QtCore/QString>
#include <QtCore/QTimer>
#include <QtCore/QFile>
#include <QtCore/QTextStream>
#include <QtCore/QCoreApplication>
#include <ctime>
#include <atomic>
#include <QtCore/QThread>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusObjectPath>
#include <QtDBus/QDBusPendingCallWatcher>
#include <QtDBus/QDBusPendingReply>
#include <QtPositioning/QGeoSatelliteInfoSource>
#include <QtPositioning/QGeoSatelliteInfo>
#include <QtPositioning/QGeoPositionInfoSource>
#include <QtPositioning/QGeoPositionInfo>
#include <QtPositioning/QGeoCoordinate>
#include "location_props.h"
#include "nmea_sat_source.h"

// Plain C struct for crossing the Rust FFI boundary.
struct SatDataC {
    int   id;
    float signal;     // dBHz  (0 if unavailable)
    float azimuth;    // 0-360°
    float elevation;  // 0-90°
    bool  in_use;
    int   system;     // QGeoSatelliteInfo::SatelliteSystem cast to int
};

// Plain C struct for position data.
struct PosDataC {
    double lat;
    double lon;
    double speed_ms;    // m/s  (-1 = unavailable)
    double accuracy_m;  // m    (-1 = unavailable)
    bool   has_fix;
};

// NOT a QObject subclass – avoids needing MOC.
// Must always be heap-allocated (lambdas capture 'this').
class SatelliteSource {
    // --- satellite bridge file (/run/navius-sat.txt written by navius-sat-bridge.py) ---
    QVector<SatDataC> m_bridge_sats;
    time_t            m_bridge_ts   = 0;
    bool              m_bridge_updated = false;
    static constexpr int BRIDGE_MAX_AGE_S = 10;

    // Returns true if fresh bridge data was loaded.
    bool try_read_bridge() {
        QFile f(QStringLiteral("/run/user/32011/navius.woodyst/navius-sat.txt"));
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return false;

        QTextStream in(&f);
        bool ok = false;

        time_t ts = in.readLine().toLongLong(&ok);
        if (!ok) return false;

        time_t now = time(nullptr);
        if (now - ts > BRIDGE_MAX_AGE_S) return false;  // datos obsoletos

        int count = in.readLine().toInt(&ok);
        if (!ok || count < 0 || count > 200) return false;

        // Line 3: lat lon acc speed has_fix
        {
            QString posLine = in.readLine();
            QStringList pp = posLine.split(' ');
            if (pp.size() >= 5) {
                PosDataC p{};
                p.lat        = pp[0].toDouble();
                p.lon        = pp[1].toDouble();
                p.accuracy_m = pp[2].toDouble();
                p.speed_ms   = pp[3].toDouble();
                p.has_fix    = pp[4].toInt() != 0;
                if (p.has_fix || p.lat != 0.0 || p.lon != 0.0) {
                    m_pos         = p;
                    m_pos_updated = true;
                }
            }
        }

        QVector<SatDataC> sats;
        sats.reserve(count);
        for (int i = 0; i < count; ++i) {
            QString line = in.readLine();
            QStringList p = line.split(' ');
            if (p.size() < 6) return false;
            SatDataC d{};
            d.id        = p[0].toInt();
            d.signal    = p[1].toFloat();
            d.azimuth   = p[2].toFloat();
            d.elevation = p[3].toFloat();
            d.in_use    = p[4].toInt() != 0;
            d.system    = p[5].toInt();
            sats.append(d);
        }

        if (ts != m_bridge_ts) {
            m_bridge_sats    = sats;
            m_bridge_ts      = ts;
            m_bridge_updated = true;
            NAVIUS_TRACE("[navius] bridge: %d sats (ts=%ld)\n", count, (long)ts);
        }
        return true;
    }

    // --- satellite via PropertiesChanged signal ---
    LocationPropsWatcher *m_watcher = nullptr;

    // --- satélites vía NMEA de ModemManager (postmarketOS: geoclue no
    // reporta datos por-satélite en este sistema, ver create_best_satellite) ---
    NmeaSatSource *m_nmea = nullptr;

    // --- lomiri-location-service session (keeps satellite updates flowing) ---
    QDBusInterface *m_lls_session = nullptr;

    // --- satellite fallback (Qt QGeoSatelliteInfoSource) ---
    QGeoSatelliteInfoSource  *m_sat_src    = nullptr;
    QList<QGeoSatelliteInfo>  m_in_view;
    QList<QGeoSatelliteInfo>  m_in_use;
    bool                      m_sat_updated  = false;
    int                       m_error_code   = 0;

    // --- position (lomiri plugin – triggers trust-store dialog) ---
    QGeoPositionInfoSource   *m_pos_src    = nullptr;
    PosDataC                  m_pos        = {0, 0, -1, -1, false};
    bool                      m_pos_updated  = false;
    bool                      m_start_called = false;
    // Shared flag to safely cancel the background pos-source callback if we're destroyed.
    std::shared_ptr<std::atomic<bool>> m_alive { std::make_shared<std::atomic<bool>>(true) };

    // -------------------------------------------------------------------------
    // Internal: create lomiri session (deferred 300 ms).
    // -------------------------------------------------------------------------
    void do_create_lomiri_session() {
        NAVIUS_TRACE("[navius] lls: attempting CreateSessionForCriteria\n");
        QDBusInterface svc(
            QStringLiteral("com.lomiri.location.Service"),
            QStringLiteral("/com/lomiri/location/Service"),
            QStringLiteral("com.lomiri.location.Service"),
            QDBusConnection::systemBus());
        NAVIUS_TRACE("[navius] lls: svc.isValid=%d\n", svc.isValid() ? 1 : 0);
        if (!svc.isValid()) return;

        QList<QVariant> args;
        args << QVariant(true)    // requires_position
             << QVariant(false)   // requires_altitude
             << QVariant(false)   // requires_heading
             << QVariant(false)   // requires_velocity
             << QVariant(3000.0)  // horizontal_accuracy metres
             << QVariant(false)   // has_vertical_accuracy
             << QVariant(false)   // has_velocity_accuracy
             << QVariant(false);  // has_heading_accuracy

        QDBusPendingCall pending = svc.asyncCallWithArgumentList(
            QStringLiteral("CreateSessionForCriteria"), args);

        auto *watcher = new QDBusPendingCallWatcher(pending);
        QObject::connect(watcher, &QDBusPendingCallWatcher::finished,
            [this, watcher]() {
                watcher->deleteLater();
                QDBusPendingReply<QDBusObjectPath> reply = *watcher;
                if (reply.isError()) {
                    NAVIUS_TRACE("[navius] CreateSessionForCriteria err: %s\n",
                            reply.error().message().toUtf8().constData());
                    return;
                }
                QString sessionPath = reply.value().path();
                NAVIUS_TRACE("[navius] lls session: %s\n",
                        sessionPath.toUtf8().constData());
                // Delete any stale session before setting the new one.
                delete m_lls_session;
                m_lls_session = new QDBusInterface(
                    QStringLiteral("com.lomiri.location.Service"),
                    sessionPath,
                    QStringLiteral("com.lomiri.location.Service.Session"),
                    QDBusConnection::systemBus());
                m_lls_session->call(QDBus::NoBlock,
                                    QStringLiteral("StartPositionUpdates"));
                NAVIUS_TRACE("[navius] lls: StartPositionUpdates sent\n");
            });
    }

    void create_lomiri_session() {
        NAVIUS_TRACE("[navius] lls: scheduling session creation\n");
        QTimer::singleShot(300, [this]() {
            do_create_lomiri_session();
        });
    }

    // Try providers in order; geoclue2 first (Ubuntu 24.04), then default.
    static QGeoSatelliteInfoSource* create_best_satellite(QObject *parent) {
        for (const QString &name : {QStringLiteral("geoclue2"),
                                    QStringLiteral("geoclue")}) {
            auto *src = QGeoSatelliteInfoSource::createSource(name, parent);
            if (src) return src;
        }
        return QGeoSatelliteInfoSource::createDefaultSource(parent);
    }

    // -------------------------------------------------------------------------
    // Creates the position source and lomiri session (called once at startup).
    // -------------------------------------------------------------------------
    void init_pos_and_session() {
        NAVIUS_TRACE("[navius] pos_src: starting background creation...\n");
        auto *posThread = QThread::create([this, alive = m_alive]() {
            auto *src = QGeoPositionInfoSource::createDefaultSource(nullptr);
            NAVIUS_TRACE("[navius] pos_src plugin: %s\n",
                    src ? src->sourceName().toUtf8().constData() : "NULL");
            // Grab last cached position (fast, no event loop needed in background thread).
            QGeoPositionInfo lastKnown;
            if (src) {
                lastKnown = src->lastKnownPosition(false);
                // Move to main thread BEFORE startUpdates() — the Qt LLS plugin
                // uses QEventLoop internally for D-Bus replies, which requires a
                // running event loop. Calling startUpdates() in this background
                // thread (which has no event loop) blocks forever.
                src->moveToThread(QCoreApplication::instance()->thread());
            }
            QMetaObject::invokeMethod(QCoreApplication::instance(), [this, alive, src, lastKnown]() {
                if (!alive->load()) {
                    NAVIUS_TRACE("[navius] pos_src: source destroyed, discarding\n");
                    delete src; return;
                }
                // Use last known position immediately (no satellite fix required).
                if (lastKnown.isValid()) {
                    QGeoCoordinate c = lastKnown.coordinate();
                    if (c.isValid() && (c.latitude() != 0.0 || c.longitude() != 0.0)) {
                        m_pos.lat        = c.latitude();
                        m_pos.lon        = c.longitude();
                        m_pos.speed_ms   = -1;
                        m_pos.accuracy_m = lastKnown.hasAttribute(QGeoPositionInfo::HorizontalAccuracy)
                                         ? lastKnown.attribute(QGeoPositionInfo::HorizontalAccuracy) : -1;
                        m_pos.has_fix    = false;  // cached, not current fix
                        m_pos_updated    = true;
                        NAVIUS_TRACE("[navius] pos_src: last known %.4f,%.4f acc=%.0f\n",
                                c.latitude(), c.longitude(), m_pos.accuracy_m);
                    }
                }
                m_pos_src = src;
                if (m_pos_src) {
                    QObject::connect(m_pos_src, &QGeoPositionInfoSource::positionUpdated,
                        [this](const QGeoPositionInfo &p) {
                            if (p.isValid()) {
                                QGeoCoordinate c = p.coordinate();
                                m_pos.lat        = c.latitude();
                                m_pos.lon        = c.longitude();
                                m_pos.speed_ms   = p.hasAttribute(QGeoPositionInfo::GroundSpeed)
                                                 ? p.attribute(QGeoPositionInfo::GroundSpeed) : -1;
                                m_pos.accuracy_m = p.hasAttribute(QGeoPositionInfo::HorizontalAccuracy)
                                                 ? p.attribute(QGeoPositionInfo::HorizontalAccuracy) : -1;
                                m_pos.has_fix    = true;
                                m_pos_updated    = true;
                                NAVIUS_TRACE("[navius] pos_src: fix %.5f,%.5f acc=%.1f\n",
                                        m_pos.lat, m_pos.lon, m_pos.accuracy_m);
                            }
                        });
                    QObject::connect(m_pos_src,
                        qOverload<QGeoPositionInfoSource::Error>(&QGeoPositionInfoSource::error),
                        [](QGeoPositionInfoSource::Error e) {
                            NAVIUS_TRACE("[navius] pos_src error: %d\n", (int)e);
                        });
                    // startUpdates() on main thread: D-Bus replies are processed by
                    // the main event loop — no blocking.
                    m_pos_src->startUpdates();
                    NAVIUS_TRACE("[navius] pos_src: startUpdates called on main thread\n");
                }
            }, Qt::QueuedConnection);
        });
        QObject::connect(posThread, &QThread::finished, posThread, &QObject::deleteLater);
        posThread->start();

        create_lomiri_session();
    }

public:
    // Called once at startup (from a QTimer::singleShot(0) to let the UI render first).
    void init_sources() {
        // --- satellite source (geoclue; created once, not reconnected) ---
        m_sat_src = create_best_satellite(nullptr);
        NAVIUS_TRACE("[navius] sat_src plugin: %s\n",
                m_sat_src ? m_sat_src->sourceName().toUtf8().constData() : "NULL");
        if (m_sat_src) {
            QObject::connect(m_sat_src, &QGeoSatelliteInfoSource::satellitesInViewUpdated,
                [this](const QList<QGeoSatelliteInfo> &s) {
                    m_in_view = s;
                    m_sat_updated = true;
                    NAVIUS_TRACE("[navius] sat in_view: %d\n", s.size());
                });
            QObject::connect(m_sat_src, &QGeoSatelliteInfoSource::satellitesInUseUpdated,
                [this](const QList<QGeoSatelliteInfo> &s) {
                    m_in_use = s;
                    m_sat_updated = true;
                });
            QObject::connect(m_sat_src,
                qOverload<QGeoSatelliteInfoSource::Error>(&QGeoSatelliteInfoSource::error),
                [this](QGeoSatelliteInfoSource::Error e) {
                    m_error_code = static_cast<int>(e);
                    NAVIUS_TRACE("[navius] sat_src error: %d\n", (int)e);
                });
            if (m_start_called) m_sat_src->startUpdates();
        }

        // --- position source + lomiri session (recreated on each reconnect) ---
        init_pos_and_session();

        // Wire up LLS restart handler once – not inside init_pos_and_session()
        // to avoid accumulating a new connection on every LLS restart.
        QDBusConnection::systemBus().connect(
            QStringLiteral("org.freedesktop.DBus"),
            QStringLiteral("/org/freedesktop/DBus"),
            QStringLiteral("org.freedesktop.DBus"),
            QStringLiteral("NameOwnerChanged"),
            m_watcher,
            SLOT(onNameOwnerChanged(QString,QString,QString)));
        auto alive = m_alive;
        QObject::connect(m_watcher, &LocationPropsWatcher::llsRestarted,
            [this, alive]() {
                if (!alive->load()) return;
                NAVIUS_TRACE("[navius] lls: restarted – reconnecting pos+session\n");
                if (m_lls_session) {
                    delete m_lls_session;
                    m_lls_session = nullptr;
                }
                if (m_pos_src) {
                    m_pos_src->stopUpdates();
                    m_pos_src->deleteLater();
                    m_pos_src = nullptr;
                }
                init_pos_and_session();
            });
    }

    SatelliteSource() {
        m_watcher = new LocationPropsWatcher(nullptr);
        m_nmea    = new NmeaSatSource();
        // Defer potentially-blocking source creation so the UI renders first.
        QTimer::singleShot(0, [this]() { init_sources(); });
    }

    ~SatelliteSource() {
        m_alive->store(false);   // cancel pending background callback
        delete m_lls_session;
        delete m_watcher;
        delete m_nmea;
        delete m_sat_src;
        delete m_pos_src;
    }

    SatelliteSource(const SatelliteSource &) = delete;
    SatelliteSource &operator=(const SatelliteSource &) = delete;

    // Returns false only if all sources are unavailable.
    bool is_available() const {
        return m_watcher != nullptr || m_sat_src != nullptr || m_pos_src != nullptr;
    }

    bool take_sat_updated() {
        // Priority: bridge file → modified-LLS watcher → NMEA/ModemManager →
        // QGeoSatelliteInfoSource. El watcher solo se usa si svs_available()
        // (LLS modificado, Ubuntu Touch). NMEA/ModemManager es la vía real en
        // postmarketOS: geoclue2 no reporta datos por-satélite en este
        // sistema y el geoclue legacy (v1) siempre falla (ver
        // create_best_satellite).
        try_read_bridge();
        if (m_bridge_updated) { m_bridge_updated = false; return true; }
        if (m_watcher && m_watcher->svs_available() && m_watcher->take_updated()) return true;
        if (m_nmea && m_nmea->available() && m_nmea->take_updated()) return true;
        bool v = m_sat_updated;
        m_sat_updated = false;
        return v;
    }

    int take_error_code() {
        int e = m_error_code;
        m_error_code = 0;
        return e;
    }

    bool take_pos_updated() {
        bool v = m_pos_updated;
        m_pos_updated = false;
        return v;
    }

    PosDataC get_position() const { return m_pos; }

    void start() {
        m_start_called = true;
        NAVIUS_TRACE("[navius] start: sat=%d pos=%d\n",
                m_sat_src ? 1 : 0, m_pos_src ? 1 : 0);
        if (m_sat_src) m_sat_src->startUpdates();
        if (m_pos_src) m_pos_src->startUpdates();
        // Re-arm the LLS session after a stop() (app resumed from suspension);
        // harmless if it is already running.
        if (m_lls_session && m_lls_session->isValid())
            m_lls_session->call(QDBus::NoBlock, QStringLiteral("StartPositionUpdates"));
        m_watcher->start_polling();
        if (m_nmea) m_nmea->start_polling();
    }
    void stop() {
        NAVIUS_TRACE("[navius] stop\n");
        // Close the LLS session cleanly to avoid orphaned sessions accumulating in the daemon.
        if (m_lls_session && m_lls_session->isValid())
            m_lls_session->call(QDBus::NoBlock, QStringLiteral("StopPositionUpdates"));
        if (m_sat_src) m_sat_src->stopUpdates();
        if (m_pos_src) m_pos_src->stopUpdates();
        m_watcher->stop_polling();
        if (m_nmea) m_nmea->stop_polling();
    }

    int count_in_view() const {
        if (!m_bridge_sats.isEmpty()) return m_bridge_sats.size();
        if (m_watcher && m_watcher->svs_available()) {
            int n = m_watcher->vehicles().size();
            if (n > 0) return n;
        }
        if (m_nmea && m_nmea->available() && !m_nmea->vehicles().isEmpty())
            return m_nmea->vehicles().size();
        return m_in_view.size();
    }

    SatDataC get_sat(int i) const {
        if (!m_bridge_sats.isEmpty()) {
            if (i >= 0 && i < m_bridge_sats.size()) return m_bridge_sats.at(i);
            return SatDataC{};
        }
        if (m_watcher && m_watcher->svs_available()) {
            QVector<SpVehicle> svs = m_watcher->vehicles();
            if (i >= 0 && i < svs.size()) {
                const SpVehicle &sv = svs.at(i);
                SatDataC d{};
                d.id        = sv.prn;
                d.signal    = sv.snr;
                d.azimuth   = sv.azimuth;
                d.elevation = sv.elevation;
                d.in_use    = sv.used;
                d.system    = sv.system;
                return d;
            }
        }
        if (m_nmea && m_nmea->available() && !m_nmea->vehicles().isEmpty()) {
            const QVector<SpVehicle> &svs = m_nmea->vehicles();
            if (i >= 0 && i < svs.size()) {
                const SpVehicle &sv = svs.at(i);
                SatDataC d{};
                d.id        = sv.prn;
                d.signal    = sv.snr;
                d.azimuth   = sv.azimuth;
                d.elevation = sv.elevation;
                d.in_use    = sv.used;
                d.system    = sv.system;
                return d;
            }
        }
        SatDataC d{};
        if (i < 0 || i >= m_in_view.size()) return d;
        const QGeoSatelliteInfo &s = m_in_view.at(i);
        d.id        = s.satelliteIdentifier();
        d.signal    = static_cast<float>(s.signalStrength());
        d.azimuth   = s.hasAttribute(QGeoSatelliteInfo::Azimuth)
                        ? static_cast<float>(s.attribute(QGeoSatelliteInfo::Azimuth))   : 0.0f;
        d.elevation = s.hasAttribute(QGeoSatelliteInfo::Elevation)
                        ? static_cast<float>(s.attribute(QGeoSatelliteInfo::Elevation)) : 0.0f;
        d.system    = static_cast<int>(s.satelliteSystem());
        for (const QGeoSatelliteInfo &u : m_in_use) {
            if (u.satelliteIdentifier() == d.id) { d.in_use = true; break; }
        }
        return d;
    }
};

inline void sat_source_get(const SatelliteSource *src, int i, SatDataC *out) {
    *out = src->get_sat(i);
}
