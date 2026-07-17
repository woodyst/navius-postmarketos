#pragma once
#include <QtCore/QObject>

// Set to true to enable navius GPS debug traces on stderr.
static constexpr bool NAVIUS_DEBUG = false;
#define NAVIUS_TRACE(...) do { if (NAVIUS_DEBUG) fprintf(stderr, __VA_ARGS__); } while(0)
#include <QtCore/QVariantMap>
#include <QtCore/QStringList>
#include <QtCore/QVector>
#include <QtCore/QTimer>
#include <QtDBus/QDBusArgument>
#include <QtDBus/QDBusPendingCallWatcher>

struct SpVehicle {
    int   prn;
    float snr;
    float azimuth;
    float elevation;
    bool  used;
    int   system;   // 1=GPS, 2=GLONASS
};

class LocationPropsWatcher : public QObject {
    Q_OBJECT
public:
    explicit LocationPropsWatcher(QObject *parent = nullptr);
    ~LocationPropsWatcher();

    // Start/stop periodic polling of VisibleSpaceVehicles via GetProperty.
    void start_polling();
    void stop_polling();

    // True once the first successful VisibleSpaceVehicles reply is received.
    bool svs_available() const { return m_svs_available; }

    bool take_updated();
    QVector<SpVehicle> vehicles() const;

signals:
    void llsRestarted();

public slots:
    void onPropertiesChanged(const QString &iface,
                             const QVariantMap &changed,
                             const QStringList &invalidated);
    void onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);

private slots:
    void onPollTimeout();
    void onPollReply(QDBusPendingCallWatcher *watcher);

private:
    void parse_svs_arg(const QDBusArgument &arg);

    QVector<SpVehicle>       m_vehicles;
    bool                     m_updated       = false;
    bool                     m_svs_available = false;  // set true on first successful poll
    QTimer                  *m_poll_timer = nullptr;
    QDBusPendingCallWatcher *m_pending    = nullptr;
};
