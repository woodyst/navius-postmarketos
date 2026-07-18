#pragma once
#include <QtCore/QObject>
#include <QtCore/QVector>
#include <QtCore/QString>
#include <QtCore/QStringList>
#include <QtCore/QTimer>
#include <QtCore/QMap>
#include <QtCore/QPair>
#include <QtCore/QRegExp>
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusMessage>
#include <QtDBus/QDBusPendingCall>
#include <QtDBus/QDBusPendingCallWatcher>
#include <QtDBus/QDBusPendingReply>
#include <QtDBus/QDBusReply>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusVariant>
#include <QtDBus/QDBusObjectPath>
#include <QtDBus/QDBusMetaType>
#include "location_props.h"  // SpVehicle, NAVIUS_TRACE

// Lee satélites en vista directamente de ModemManager (NMEA GSV/GSA), sin
// pasar por geoclue. Necesario en postmarketOS porque el plugin Qt
// "geoclue2" no expone datos por-satélite (solo posición agregada), y el
// plugin legacy "geoclue" (v1) falla siempre porque ese servicio D-Bus ya
// no existe. ModemManager sí puede reportar el NMEA crudo del chip GNSS del
// propio módem (MMModemLocationSource::GPS_NMEA, bit 4).
//
// MMModemLocationSource (org.freedesktop.ModemManager1 enums):
//   3GPP_LAC_CI=1  GPS_RAW=2  GPS_NMEA=4  CDMA_BS=8
//   GPS_UNMANAGED=16  AGPS_MSA=32  AGPS_MSB=64
static constexpr unsigned int MM_LOC_SOURCE_GPS_RAW  = 2;
static constexpr unsigned int MM_LOC_SOURCE_GPS_NMEA = 4;

class NmeaSatSource {
    QString m_modem_path;
    QTimer *m_poll_timer = nullptr;
    QDBusPendingCallWatcher *m_pending = nullptr;

    QVector<SpVehicle> m_vehicles;
    bool m_updated   = false;
    bool m_available = false;  // true tras localizar un módem con Location

    // --- localizar el módem con capacidad Location ---
    // Prueba las rutas de objeto habituales de ModemManager (casi todos los
    // teléfonos solo tienen un módem, en /Modem/0) en vez de parsear a mano
    // GetManagedObjects (firma D-Bus anidada a{oa{sa{sv}}}, propensa a
    // errores al leer los "v" como QVariant en vez de QDBusVariant).
    void find_modem() {
        for (int i = 0; i < 4 && m_modem_path.isEmpty(); ++i) {
            QString candidate = QStringLiteral("/org/freedesktop/ModemManager1/Modem/%1").arg(i);
            QDBusInterface props(QStringLiteral("org.freedesktop.ModemManager1"),
                                  candidate,
                                  QStringLiteral("org.freedesktop.DBus.Properties"),
                                  QDBusConnection::systemBus());
            QDBusReply<QVariant> r = props.call(
                QStringLiteral("Get"),
                QStringLiteral("org.freedesktop.ModemManager1.Modem.Location"),
                QStringLiteral("Capabilities"));
            if (r.isValid()) m_modem_path = candidate;
        }
        if (!m_modem_path.isEmpty()) {
            m_available = true;
            NAVIUS_TRACE("[navius] nmea: modem found at %s\n",
                    m_modem_path.toUtf8().constData());
        } else {
            NAVIUS_TRACE("[navius] nmea: no modem with Location interface\n");
        }
    }

    // Añade GPS_RAW|GPS_NMEA a las fuentes ya habilitadas (no las sustituye,
    // para no pisar lo que geoclue necesite, p.ej. 3gpp-lac-ci).
    void enable_gps_sources() {
        if (m_modem_path.isEmpty()) return;

        QDBusInterface props(QStringLiteral("org.freedesktop.ModemManager1"),
                              m_modem_path,
                              QStringLiteral("org.freedesktop.DBus.Properties"),
                              QDBusConnection::systemBus());
        QDBusReply<QVariant> enabledReply = props.call(
            QStringLiteral("Get"),
            QStringLiteral("org.freedesktop.ModemManager1.Modem.Location"),
            QStringLiteral("Enabled"));
        unsigned int enabled = enabledReply.isValid() ? enabledReply.value().toUInt() : 0;
        unsigned int wanted  = enabled | MM_LOC_SOURCE_GPS_RAW | MM_LOC_SOURCE_GPS_NMEA;
        if (wanted == enabled) return;  // ya están activas

        QDBusInterface loc(QStringLiteral("org.freedesktop.ModemManager1"),
                            m_modem_path,
                            QStringLiteral("org.freedesktop.ModemManager1.Modem.Location"),
                            QDBusConnection::systemBus());
        QDBusReply<void> r = loc.call(QStringLiteral("Setup"), wanted, false);
        NAVIUS_TRACE("[navius] nmea: Setup(sources=%u) valid=%d err=%s\n",
                wanted, r.isValid() ? 1 : 0, r.error().message().toUtf8().constData());
    }

    static int talker_to_system(const QString &talker) {
        // Mismo mapeo que lls_type_to_qt_system en location_props.cpp:
        // 0=Undefined 1=GPS 2=GLONASS 3=GALILEO 4=BEIDOU 5=QZSS
        if (talker == QLatin1String("GP")) return 1;
        if (talker == QLatin1String("GL")) return 2;
        if (talker == QLatin1String("GA")) return 3;
        if (talker == QLatin1String("GB") || talker == QLatin1String("BD")) return 4;
        if (talker == QLatin1String("GQ")) return 5;
        return 0;  // GN (multi-constelación) u otro: desconocido
    }

    // Analiza el texto NMEA acumulado (varias líneas $..GSV / $..GSA) y
    // actualiza m_vehicles. Sustituye la lista completa por lo encontrado en
    // este bloque (igual que hace LocationPropsWatcher con VisibleSpaceVehicles).
    void parse_nmea(const QString &text) {
        if (text.isEmpty()) return;

        QMap<QPair<int,int>, SpVehicle> bySystemPrn;  // (system,prn) -> vehicle
        QVector<QPair<int,int>> usedPrns;             // (system,prn) marcados en GSA

        const QStringList lines = text.split(QRegExp("[\r\n]"), Qt::SkipEmptyParts);
        for (const QString &rawLine : lines) {
            QString line = rawLine.trimmed();
            if (line.size() < 6 || line[0] != QLatin1Char('$')) continue;

            // Quita el checksum "*XX" si está presente para simplificar el split.
            QString body = line.section('*', 0, 0);
            QStringList f = body.split(',');
            if (f.isEmpty()) continue;

            QString sentence = f[0].mid(1);          // sin '$'
            QString talker   = sentence.left(2);      // GP/GL/GA/GB/GQ/GN
            QString type     = sentence.mid(2);       // GSV/GSA/...

            if (type == QLatin1String("GSV") && f.size() >= 4) {
                int system = talker_to_system(talker);
                // Campos 4..N en grupos de 4: prn, elev, azim, snr (el último
                // grupo puede venir incompleto; algunos receptores añaden un
                // signal-id al final que no encaja en grupos de 4 — se ignora
                // si no hay al menos 3 campos numéricos más tras el prn).
                for (int i = 4; i + 2 < f.size(); i += 4) {
                    bool ok = false;
                    int prn = f[i].toInt(&ok);
                    if (!ok || prn <= 0) continue;
                    SpVehicle sv{};
                    sv.prn       = prn;
                    sv.elevation = f[i+1].toFloat();
                    sv.azimuth   = f[i+2].toFloat();
                    sv.snr       = (i + 3 < f.size()) ? f[i+3].toFloat() : 0.0f;
                    sv.used      = false;
                    sv.system    = system;
                    bySystemPrn[{system, prn}] = sv;
                }
            } else if (type == QLatin1String("GSA") && f.size() >= 15) {
                int system = talker_to_system(talker);
                for (int i = 3; i <= 14; ++i) {
                    bool ok = false;
                    int prn = f[i].toInt(&ok);
                    if (ok && prn > 0) usedPrns.append({system, prn});
                }
            }
        }

        if (bySystemPrn.isEmpty()) return;  // bloque sin GSV útil: no pisar datos previos

        for (const auto &key : usedPrns) {
            auto it = bySystemPrn.find(key);
            if (it != bySystemPrn.end()) it->used = true;
        }

        m_vehicles = QVector<SpVehicle>(bySystemPrn.begin(), bySystemPrn.end());
        m_updated  = true;
        NAVIUS_TRACE("[navius] nmea: %d sats parsed\n", m_vehicles.size());
    }

    void poll() {
        if (m_modem_path.isEmpty() || m_pending) return;

        QDBusMessage msg = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.ModemManager1"),
            m_modem_path,
            QStringLiteral("org.freedesktop.ModemManager1.Modem.Location"),
            QStringLiteral("GetLocation"));
        QDBusPendingCall pending = QDBusConnection::systemBus().asyncCall(msg, 2000);
        m_pending = new QDBusPendingCallWatcher(pending);
        QObject::connect(m_pending, &QDBusPendingCallWatcher::finished,
            [this](QDBusPendingCallWatcher *w) {
                w->deleteLater();
                m_pending = nullptr;
                if (!m_poll_timer) return;  // stop_polling() llamado mientras estaba en vuelo

                // ModemManager devuelve a{uv} (claves uint32), no a{sv} —
                // QVariantMap (claves string) no encaja con esa firma D-Bus.
                QDBusPendingReply<QMap<uint, QDBusVariant>> reply = *w;
                if (reply.isError()) {
                    NAVIUS_TRACE("[navius] nmea: GetLocation error %s\n",
                            reply.error().message().toUtf8().constData());
                    return;
                }
                QMap<uint, QDBusVariant> locations = reply.value();
                auto it = locations.constFind(MM_LOC_SOURCE_GPS_NMEA);
                if (it == locations.constEnd()) return;
                parse_nmea(it.value().variant().toString());
            });
    }

public:
    NmeaSatSource() {
        // QMap<uint,QDBusVariant> no es uno de los tipos con marshalling
        // D-Bus registrado por defecto en Qt — sin este registro,
        // QDBusPendingReply<QMap<uint,QDBusVariant>> aborta el proceso
        // (qFatal) en vez de fallar con un error normal.
        qDBusRegisterMetaType<QMap<uint, QDBusVariant>>();
        find_modem();
        if (m_available) enable_gps_sources();
    }
    ~NmeaSatSource() { stop_polling(); }

    NmeaSatSource(const NmeaSatSource &) = delete;
    NmeaSatSource &operator=(const NmeaSatSource &) = delete;

    bool available() const { return m_available; }

    void start_polling() {
        if (!m_available || m_poll_timer) return;
        m_poll_timer = new QTimer(nullptr);
        m_poll_timer->setInterval(1000);
        QObject::connect(m_poll_timer, &QTimer::timeout, [this]() { poll(); });
        m_poll_timer->start();
        QTimer::singleShot(0, [this]() { poll(); });
    }

    void stop_polling() {
        if (!m_poll_timer) return;
        m_poll_timer->stop();
        delete m_poll_timer;
        m_poll_timer = nullptr;
    }

    bool take_updated() {
        bool v = m_updated;
        m_updated = false;
        return v;
    }

    const QVector<SpVehicle> &vehicles() const { return m_vehicles; }
};
