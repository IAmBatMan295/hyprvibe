#include "DBusEngine.hpp"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusError>
#include <QDBusInterface>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusVariant>
#include <QProcess>
#include <QSet>
#include <QUuid>
#include <QVariantMap>

#include <algorithm>
#include <fcntl.h>
#include <linux/rfkill.h>
#include <unistd.h>

using NmSettingsMap = QMap<QString, QVariantMap>;
using ManagedObjectMap = QMap<QDBusObjectPath, QMap<QString, QVariantMap>>;

Q_DECLARE_METATYPE(NmSettingsMap)
Q_DECLARE_METATYPE(ManagedObjectMap)

namespace {

const auto kAgentPath = QStringLiteral("/org/bluez/hyprvibe/agent");

bool registerNmMetatypes() {
  static const bool registered = []() {
    qDBusRegisterMetaType<NmSettingsMap>();
    qDBusRegisterMetaType<ManagedObjectMap>();
    return true;
  }();
  return registered;
}

bool setRfkillBluetooth(bool blocked) {
  const int fd = ::open("/dev/rfkill", O_RDWR | O_CLOEXEC);
  if (fd < 0) return false;
  struct rfkill_event ev {};
  ev.op = RFKILL_OP_CHANGE_ALL;
  ev.type = RFKILL_TYPE_BLUETOOTH;
  ev.soft = blocked ? 1 : 0;
  const ssize_t n = ::write(fd, &ev, sizeof(ev));
  ::close(fd);
  return n == static_cast<ssize_t>(sizeof(ev));
}

QVariant readDbusProp(const QString& path, const QString& iface, const QString& prop, QDBusConnection& bus) {
  QDBusInterface props(QStringLiteral("org.freedesktop.NetworkManager"), path,
                       QStringLiteral("org.freedesktop.DBus.Properties"), bus);
  const QDBusReply<QDBusVariant> reply = props.call(QStringLiteral("Get"), iface, prop);
  return reply.isValid() ? reply.value().variant() : QVariant();
}

}  // namespace

BluezAgentObject::BluezAgentObject(DBusEngine* owner) : QObject(owner), m_owner(owner) {}

void BluezAgentObject::Release() {
  if (m_owner) m_owner->completePendingAgentPrompt(false, QString());
}

QString BluezAgentObject::RequestPinCode(const QDBusObjectPath&) {
  if (calledFromDBus() && m_owner) {
    setDelayedReply(true);
    m_owner->m_hasPendingAgentMsg = true;
    m_owner->m_pendingPromptType = QStringLiteral("pin");
    m_owner->m_pendingAgentMsg = message();
    m_owner->deliverAgentPrompt(QStringLiteral("pin"), QString());
  }
  return {};
}

uint BluezAgentObject::RequestPasskey(const QDBusObjectPath&) {
  if (calledFromDBus() && m_owner) {
    setDelayedReply(true);
    m_owner->m_hasPendingAgentMsg = true;
    m_owner->m_pendingPromptType = QStringLiteral("passkey");
    m_owner->m_pendingAgentMsg = message();
    m_owner->deliverAgentPrompt(QStringLiteral("passkey"), QString());
  }
  return 0;
}

void BluezAgentObject::DisplayPinCode(const QDBusObjectPath&, const QString& pincode) {
  if (m_owner) m_owner->deliverAgentPrompt(QStringLiteral("display_pin"), pincode);
}

void BluezAgentObject::DisplayPasskey(const QDBusObjectPath&, uint passkey, quint16) {
  if (m_owner) {
    m_owner->deliverAgentPrompt(QStringLiteral("display"),
                               QStringLiteral("%1").arg(passkey, 6, 10, QLatin1Char('0')));
  }
}

void BluezAgentObject::RequestConfirmation(const QDBusObjectPath&, uint passkey) {
  if (calledFromDBus() && m_owner) {
    setDelayedReply(true);
    m_owner->m_hasPendingAgentMsg = true;
    m_owner->m_pendingPromptType = QStringLiteral("confirmation");
    m_owner->m_pendingAgentMsg = message();
    m_owner->deliverAgentPrompt(QStringLiteral("confirmation"),
                               QStringLiteral("%1").arg(passkey, 6, 10, QLatin1Char('0')));
  }
}

void BluezAgentObject::RequestAuthorization(const QDBusObjectPath&) {
  if (calledFromDBus() && m_owner) {
    setDelayedReply(true);
    m_owner->m_hasPendingAgentMsg = true;
    m_owner->m_pendingPromptType = QStringLiteral("authorize");
    m_owner->m_pendingAgentMsg = message();
    m_owner->deliverAgentPrompt(QStringLiteral("authorize"), QString());
  }
}

void BluezAgentObject::AuthorizeService(const QDBusObjectPath&, const QString&) {}

void BluezAgentObject::Cancel() {
  if (m_owner) {
    m_owner->completePendingAgentPrompt(false, QString());
    m_owner->deliverAgentPrompt(QStringLiteral("canceled"), QString());
  }
}

DBusEngine::DBusEngine(QObject* parent) : QObject(parent) {
  registerNmMetatypes();
  m_pairTimer.setInterval(35000);
  m_pairTimer.setSingleShot(true);
  connect(&m_pairTimer, &QTimer::timeout, this, &DBusEngine::onPairTimeout);

  m_nmDebounce.setInterval(120);
  m_nmDebounce.setSingleShot(true);
  connect(&m_nmDebounce, &QTimer::timeout, this, &DBusEngine::refreshWifiBand);
}

DBusEngine::~DBusEngine() {
  if (m_hasPendingAgentMsg) completePendingAgentPrompt(false, QString());
  if (m_agentRegistered) {
    QDBusConnection bus = QDBusConnection::systemBus();
    if (bus.isConnected()) {
      QDBusMessage msg = QDBusMessage::createMethodCall(
          QStringLiteral("org.bluez"), QStringLiteral("/org/bluez"),
          QStringLiteral("org.bluez.AgentManager1"), QStringLiteral("UnregisterAgent"));
      msg << QVariant::fromValue(QDBusObjectPath(kAgentPath));
      bus.asyncCall(msg);
      bus.unregisterObject(kAgentPath);
    }
    m_agentRegistered = false;
  }
}

QString DBusEngine::bandForFrequency(uint mhz) {
  if (mhz >= 2400 && mhz < 2500) return QStringLiteral("2.4");
  if (mhz >= 4900 && mhz < 5925) return QStringLiteral("5");
  if (mhz >= 5925 && mhz < 7125) return QStringLiteral("6");
  return {};
}

QString DBusEngine::nmBandFromUi(const QString& uiBand) {
  if (uiBand == QStringLiteral("2.4")) return QStringLiteral("bg");
  if (uiBand == QStringLiteral("5")) return QStringLiteral("a");
  if (uiBand == QStringLiteral("6")) return QStringLiteral("6GHz");
  return {};
}

QString DBusEngine::uiBandFromNm(const QString& nmBand) {
  if (nmBand == QStringLiteral("bg")) return QStringLiteral("2.4");
  if (nmBand == QStringLiteral("a")) return QStringLiteral("5");
  if (nmBand == QStringLiteral("6GHz")) return QStringLiteral("6");
  return QStringLiteral("auto");
}

void DBusEngine::start() {
  if (m_started) return;
  if (qEnvironmentVariableIsSet("HYPRVIBE_NO_DAEMONS") ||
      qEnvironmentVariable("QT_QPA_PLATFORM") == QStringLiteral("offscreen")) {
    return;
  }
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) return;
  m_started = true;

  bus.connect(QStringLiteral("net.hadess.PowerProfiles"),
              QStringLiteral("/net/hadess/PowerProfiles"),
              QStringLiteral("org.freedesktop.DBus.Properties"),
              QStringLiteral("PropertiesChanged"),
              this, SLOT(onPowerProfilePropertiesChanged(QString, QVariantMap, QStringList)));

  bus.connect(QStringLiteral("org.freedesktop.NetworkManager"),
              QStringLiteral("/org/freedesktop/NetworkManager"),
              QStringLiteral("org.freedesktop.NetworkManager"),
              QStringLiteral("StateChanged"),
              this, SLOT(onNmChanged()));
  bus.connect(QStringLiteral("org.freedesktop.NetworkManager"),
              QString(),
              QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless"),
              QStringLiteral("PropertiesChanged"),
              this, SLOT(onNmChanged()));
  bus.connect(QStringLiteral("org.freedesktop.NetworkManager"),
              QString(),
              QStringLiteral("org.freedesktop.NetworkManager.Connection.Active"),
              QStringLiteral("PropertiesChanged"),
              this, SLOT(onNmChanged()));

  refreshPowerProfile();
  refreshWifiBand();
}

void DBusEngine::onNmChanged() {
  if (!m_nmDebounce.isActive()) m_nmDebounce.start();
}

void DBusEngine::refreshPowerProfile() {
  if (!m_started) start();
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) return;

  QDBusMessage msg = QDBusMessage::createMethodCall(
      QStringLiteral("net.hadess.PowerProfiles"),
      QStringLiteral("/net/hadess/PowerProfiles"),
      QStringLiteral("org.freedesktop.DBus.Properties"),
      QStringLiteral("Get"));
  msg << QStringLiteral("net.hadess.PowerProfiles") << QStringLiteral("ActiveProfile");

  auto* w = new QDBusPendingCallWatcher(bus.asyncCall(msg), this);
  connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* call) {
    call->deleteLater();
    QDBusPendingReply<QDBusVariant> reply = *call;
    if (reply.isError()) {
      m_powerProfileAvailable = false;
      emit powerProfileUpdated(m_powerProfile, false);
      return;
    }
    const QString prof = reply.value().variant().toString().trimmed();
    m_powerProfileAvailable = !prof.isEmpty();
    if (!prof.isEmpty()) m_powerProfile = prof;
    emit powerProfileUpdated(m_powerProfile, m_powerProfileAvailable);
  });
}

void DBusEngine::onPowerProfilePropertiesChanged(const QString& iface, const QVariantMap& changed, const QStringList&) {
  if (iface != QStringLiteral("net.hadess.PowerProfiles")) return;
  if (changed.contains(QStringLiteral("ActiveProfile"))) {
    const QString p = changed.value(QStringLiteral("ActiveProfile")).toString().trimmed();
    if (!p.isEmpty()) {
      m_powerProfileAvailable = true;
      m_powerProfile = p;
      emit powerProfileUpdated(m_powerProfile, true);
    }
  }
}

bool DBusEngine::setPowerProfile(const QString& profile) {
  if (profile.isEmpty()) return false;
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) return false;

  QDBusMessage msg = QDBusMessage::createMethodCall(
      QStringLiteral("net.hadess.PowerProfiles"),
      QStringLiteral("/net/hadess/PowerProfiles"),
      QStringLiteral("org.freedesktop.DBus.Properties"),
      QStringLiteral("Set"));
  msg << QStringLiteral("net.hadess.PowerProfiles")
      << QStringLiteral("ActiveProfile")
      << QVariant::fromValue(QDBusVariant(profile));
  bus.asyncCall(msg);
  m_powerProfile = profile;
  emit powerProfileUpdated(m_powerProfile, true);
  return true;
}

void DBusEngine::setBluetoothEnabled(bool enabled) {
  if (!setRfkillBluetooth(!enabled)) {
    QProcess::startDetached(QStringLiteral("rfkill"), {enabled ? QStringLiteral("unblock") : QStringLiteral("block"), QStringLiteral("bluetooth")});
  }
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) return;

  // Set BlueZ Adapter1.Powered directly too in case an adapter was unpowered without soft-block.
  QDBusMessage om = QDBusMessage::createMethodCall(
      QStringLiteral("org.bluez"), QStringLiteral("/"),
      QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("GetManagedObjects"));
  auto* w = new QDBusPendingCallWatcher(bus.asyncCall(om), this);
  connect(w, &QDBusPendingCallWatcher::finished, this, [enabled](QDBusPendingCallWatcher* call) {
    call->deleteLater();
    QDBusPendingReply<ManagedObjectMap> reply = *call;
    if (reply.isError()) return;
    const ManagedObjectMap objs = reply.value();
    QDBusConnection b = QDBusConnection::systemBus();
    for (auto it = objs.constBegin(); it != objs.constEnd(); ++it) {
      if (!it.value().contains(QStringLiteral("org.bluez.Adapter1"))) continue;
      QDBusMessage setMsg = QDBusMessage::createMethodCall(
          QStringLiteral("org.bluez"), it.key().path(),
          QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
      setMsg << QStringLiteral("org.bluez.Adapter1")
             << QStringLiteral("Powered")
             << QVariant::fromValue(QDBusVariant(enabled));
      b.asyncCall(setMsg);
    }
  });
}

void DBusEngine::forgetBluetoothDevice(const QString& address) {
  const QString target = address.trimmed().toUpper();
  if (target.isEmpty()) return;
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) return;

  QDBusMessage om = QDBusMessage::createMethodCall(
      QStringLiteral("org.bluez"), QStringLiteral("/"),
      QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("GetManagedObjects"));
  auto* w = new QDBusPendingCallWatcher(bus.asyncCall(om), this);
  connect(w, &QDBusPendingCallWatcher::finished, this, [target](QDBusPendingCallWatcher* call) {
    call->deleteLater();
    QDBusPendingReply<ManagedObjectMap> reply = *call;
    if (reply.isError()) return;
    const ManagedObjectMap objs = reply.value();
    QDBusConnection b = QDBusConnection::systemBus();
    for (auto it = objs.constBegin(); it != objs.constEnd(); ++it) {
      const auto devIt = it.value().constFind(QStringLiteral("org.bluez.Device1"));
      if (devIt == it.value().constEnd()) continue;
      if (devIt.value().value(QStringLiteral("Address")).toString().toUpper() != target) continue;
      const QString adapterPath = devIt.value().value(QStringLiteral("Adapter")).value<QDBusObjectPath>().path();
      if (adapterPath.isEmpty()) continue;
      QDBusMessage rem = QDBusMessage::createMethodCall(
          QStringLiteral("org.bluez"), adapterPath,
          QStringLiteral("org.bluez.Adapter1"), QStringLiteral("RemoveDevice"));
      rem << QVariant::fromValue(it.key());
      b.asyncCall(rem);
      return;
    }
  });
}

void DBusEngine::ensureAgentRegistered() {
  if (m_agentRegistered) return;
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) return;

  if (!m_agent) m_agent = new BluezAgentObject(this);
  bus.registerObject(kAgentPath, m_agent, QDBusConnection::ExportScriptableSlots);

  QDBusMessage reg = QDBusMessage::createMethodCall(
      QStringLiteral("org.bluez"), QStringLiteral("/org/bluez"),
      QStringLiteral("org.bluez.AgentManager1"), QStringLiteral("RegisterAgent"));
  reg << QVariant::fromValue(QDBusObjectPath(kAgentPath)) << QStringLiteral("KeyboardDisplay");
  bus.call(reg, QDBus::Block, 1000);

  QDBusMessage req = QDBusMessage::createMethodCall(
      QStringLiteral("org.bluez"), QStringLiteral("/org/bluez"),
      QStringLiteral("org.bluez.AgentManager1"), QStringLiteral("RequestDefaultAgent"));
  req << QVariant::fromValue(QDBusObjectPath(kAgentPath));
  bus.asyncCall(req);
  m_agentRegistered = true;
}

void DBusEngine::deliverAgentPrompt(const QString& type, const QString& passkey) {
  emit bluetoothPairPrompt(m_pairingAddress, type, passkey);
}

void DBusEngine::completePendingAgentPrompt(bool accept, const QString& text) {
  if (!m_hasPendingAgentMsg) return;
  m_hasPendingAgentMsg = false;
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) return;

  if (!accept) {
    bus.send(m_pendingAgentMsg.createErrorReply(QStringLiteral("org.bluez.Error.Rejected"), QStringLiteral("Rejected")));
    return;
  }

  if (m_pendingPromptType == QStringLiteral("pin")) {
    if (text.isEmpty()) {
      bus.send(m_pendingAgentMsg.createErrorReply(QStringLiteral("org.bluez.Error.Rejected"), QStringLiteral("Empty PIN")));
    } else {
      bus.send(m_pendingAgentMsg.createReply(text));
    }
  } else if (m_pendingPromptType == QStringLiteral("passkey")) {
    bool ok = false;
    const uint pk = text.toUInt(&ok);
    if (!ok) {
      bus.send(m_pendingAgentMsg.createErrorReply(QStringLiteral("org.bluez.Error.Rejected"), QStringLiteral("Invalid passkey")));
    } else {
      bus.send(m_pendingAgentMsg.createReply(pk));
    }
  } else {
    bus.send(m_pendingAgentMsg.createReply());
  }
}

void DBusEngine::finishPair(bool success, const QString& error) {
  m_pairTimer.stop();
  const QString addr = m_pairingAddress;
  m_pairingAddress.clear();
  m_pairingDevPath.clear();
  emit bluetoothPairFinished(addr, success, error);
}

void DBusEngine::onPairTimeout() {
  completePendingAgentPrompt(false, QString());
  if (!m_pairingDevPath.isEmpty()) {
    QDBusMessage cancelMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.bluez"), m_pairingDevPath,
        QStringLiteral("org.bluez.Device1"), QStringLiteral("CancelPairing"));
    QDBusConnection::systemBus().asyncCall(cancelMsg);
  }
  finishPair(false, QStringLiteral("Pairing timed out"));
}

void DBusEngine::pairBluetoothDevice(const QString& address) {
  const QString target = address.trimmed().toUpper();
  if (target.isEmpty()) return;
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) {
    emit bluetoothPairFinished(target, false, QStringLiteral("D-Bus unavailable"));
    return;
  }

  if (m_hasPendingAgentMsg) completePendingAgentPrompt(false, QString());
  ensureAgentRegistered();
  m_pairingAddress = target;
  m_pairTimer.start();

  QDBusMessage om = QDBusMessage::createMethodCall(
      QStringLiteral("org.bluez"), QStringLiteral("/"),
      QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("GetManagedObjects"));
  auto* w = new QDBusPendingCallWatcher(bus.asyncCall(om), this);
  connect(w, &QDBusPendingCallWatcher::finished, this, [this, target](QDBusPendingCallWatcher* call) {
    call->deleteLater();
    QDBusPendingReply<ManagedObjectMap> reply = *call;
    QString devPath = QStringLiteral("/org/bluez/hci0/dev_") + QString(target).replace(QLatin1Char(':'), QLatin1Char('_'));
    if (!reply.isError()) {
      const ManagedObjectMap objs = reply.value();
      for (auto it = objs.constBegin(); it != objs.constEnd(); ++it) {
        const auto devIt = it.value().constFind(QStringLiteral("org.bluez.Device1"));
        if (devIt != it.value().constEnd() &&
            devIt.value().value(QStringLiteral("Address")).toString().toUpper() == target) {
          devPath = it.key().path();
          break;
        }
      }
    }
    if (m_pairingAddress != target) return;
    m_pairingDevPath = devPath;

    QDBusConnection bus2 = QDBusConnection::systemBus();
    QDBusMessage pairMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.bluez"), devPath,
        QStringLiteral("org.bluez.Device1"), QStringLiteral("Pair"));
    auto* pw = new QDBusPendingCallWatcher(bus2.asyncCall(pairMsg, 35000), this);
    connect(pw, &QDBusPendingCallWatcher::finished, this, [this, target, devPath](QDBusPendingCallWatcher* pcall) {
      pcall->deleteLater();
      if (m_pairingAddress != target) return;
      QDBusPendingReply<> pr = *pcall;
      if (pr.isError() && !pr.error().name().contains(QStringLiteral("AlreadyExists"))) {
        finishPair(false, pr.error().message());
        return;
      }

      QDBusConnection bus3 = QDBusConnection::systemBus();
      QDBusMessage trustMsg = QDBusMessage::createMethodCall(
          QStringLiteral("org.bluez"), devPath,
          QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
      trustMsg << QStringLiteral("org.bluez.Device1") << QStringLiteral("Trusted") << QVariant::fromValue(QDBusVariant(true));
      bus3.asyncCall(trustMsg);

      QDBusMessage connMsg = QDBusMessage::createMethodCall(
          QStringLiteral("org.bluez"), devPath,
          QStringLiteral("org.bluez.Device1"), QStringLiteral("Connect"));
      auto* cw = new QDBusPendingCallWatcher(bus3.asyncCall(connMsg, 20000), this);
      connect(cw, &QDBusPendingCallWatcher::finished, this, [this, target](QDBusPendingCallWatcher* ccall) {
        ccall->deleteLater();
        if (m_pairingAddress != target) return;
        QDBusPendingReply<> cr = *ccall;
        if (cr.isError()) finishPair(false, cr.error().message());
        else finishPair(true, QString());
      });
    });
  });
}

void DBusEngine::confirmBluetoothPair(const QString& response) {
  const QString r = response.trimmed();
  const bool accept = !(r.compare(QStringLiteral("no"), Qt::CaseInsensitive) == 0 ||
                        r.compare(QStringLiteral("n"), Qt::CaseInsensitive) == 0);
  completePendingAgentPrompt(accept, r);
}

void DBusEngine::cancelBluetoothPair() {
  completePendingAgentPrompt(false, QString());
  if (!m_pairingDevPath.isEmpty()) {
    QDBusMessage cancelMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.bluez"), m_pairingDevPath,
        QStringLiteral("org.bluez.Device1"), QStringLiteral("CancelPairing"));
    QDBusConnection::systemBus().asyncCall(cancelMsg);
  }
  if (!m_pairingAddress.isEmpty()) finishPair(false, QStringLiteral("Canceled"));
}

void DBusEngine::refreshWifiBand() {
  if (!m_started) start();
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) return;

  QDBusMessage getDevs = QDBusMessage::createMethodCall(
      QStringLiteral("org.freedesktop.NetworkManager"),
      QStringLiteral("/org/freedesktop/NetworkManager"),
      QStringLiteral("org.freedesktop.NetworkManager"),
      QStringLiteral("GetAllDevices"));
  auto* w = new QDBusPendingCallWatcher(bus.asyncCall(getDevs), this);
  connect(w, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher* call) {
    call->deleteLater();
    QDBusPendingReply<QList<QDBusObjectPath>> reply = *call;
    if (reply.isError()) {
      emit wifiBandUpdated(QString(), QStringLiteral("auto"), {});
      return;
    }

    QDBusConnection bus2 = QDBusConnection::systemBus();
    QString wifiDevPath;
    for (const QDBusObjectPath& dp : reply.value()) {
      const uint dtype = readDbusProp(dp.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("DeviceType"), bus2).toUInt();
      const uint dstate = readDbusProp(dp.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("State"), bus2).toUInt();
      if (dtype == 2 && dstate == 100) {
        wifiDevPath = dp.path();
        break;
      }
    }

    if (wifiDevPath.isEmpty()) {
      emit wifiBandUpdated(QString(), QStringLiteral("auto"), {});
      return;
    }

    const QString activeApPath = readDbusProp(wifiDevPath, QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless"), QStringLiteral("ActiveAccessPoint"), bus2).value<QDBusObjectPath>().path();
    const QString activeConnPath = readDbusProp(wifiDevPath, QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("ActiveConnection"), bus2).value<QDBusObjectPath>().path();

    QByteArray activeSsid;
    QString currentBand;
    if (!activeApPath.isEmpty() && activeApPath != QStringLiteral("/")) {
      const uint freq = readDbusProp(activeApPath, QStringLiteral("org.freedesktop.NetworkManager.AccessPoint"), QStringLiteral("Frequency"), bus2).toUInt();
      activeSsid = readDbusProp(activeApPath, QStringLiteral("org.freedesktop.NetworkManager.AccessPoint"), QStringLiteral("Ssid"), bus2).toByteArray();
      currentBand = bandForFrequency(freq);
    }

    QSet<QString> bandsSet;
    if (!currentBand.isEmpty()) bandsSet.insert(currentBand);

    QDBusInterface wifiIface(QStringLiteral("org.freedesktop.NetworkManager"), wifiDevPath,
                             QStringLiteral("org.freedesktop.NetworkManager.Device.Wireless"), bus2);
    QDBusReply<QList<QDBusObjectPath>> apsReply = wifiIface.call(QStringLiteral("GetAllAccessPoints"));
    if (apsReply.isValid() && !activeSsid.isEmpty()) {
      for (const QDBusObjectPath& ap : apsReply.value()) {
        const QByteArray apSsid = readDbusProp(ap.path(), QStringLiteral("org.freedesktop.NetworkManager.AccessPoint"), QStringLiteral("Ssid"), bus2).toByteArray();
        if (apSsid != activeSsid) continue;
        const uint f = readDbusProp(ap.path(), QStringLiteral("org.freedesktop.NetworkManager.AccessPoint"), QStringLiteral("Frequency"), bus2).toUInt();
        const QString b = bandForFrequency(f);
        if (!b.isEmpty()) bandsSet.insert(b);
      }
    }

    QStringList available = bandsSet.values();
    std::sort(available.begin(), available.end(), [](const QString& a, const QString& b) {
      return a.toDouble() < b.toDouble();
    });

    QString selectedBand = QStringLiteral("auto");
    if (!activeConnPath.isEmpty() && activeConnPath != QStringLiteral("/")) {
      const QString connPath = readDbusProp(activeConnPath, QStringLiteral("org.freedesktop.NetworkManager.Connection.Active"), QStringLiteral("Connection"), bus2).value<QDBusObjectPath>().path();
      if (!connPath.isEmpty() && connPath != QStringLiteral("/")) {
        QDBusInterface connIface(QStringLiteral("org.freedesktop.NetworkManager"), connPath,
                                 QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"), bus2);
        QDBusReply<NmSettingsMap> settingsReply = connIface.call(QStringLiteral("GetSettings"));
        if (settingsReply.isValid()) {
          const QString rawBand = settingsReply.value().value(QStringLiteral("802-11-wireless")).value(QStringLiteral("band")).toString();
          selectedBand = uiBandFromNm(rawBand);
        }
      }
    }

    emit wifiBandUpdated(currentBand, selectedBand, available);
  });
}

void DBusEngine::setWifiBand(const QString& targetBand) {
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) {
    emit wifiBandSetFinished(false, QStringLiteral("D-Bus unavailable"));
    return;
  }

  const QString desiredNm = nmBandFromUi(targetBand);
  QDBusInterface nm(QStringLiteral("org.freedesktop.NetworkManager"),
                    QStringLiteral("/org/freedesktop/NetworkManager"),
                    QStringLiteral("org.freedesktop.NetworkManager"), bus);
  QDBusReply<QList<QDBusObjectPath>> devs = nm.call(QStringLiteral("GetAllDevices"));
  if (!devs.isValid()) {
    emit wifiBandSetFinished(false, devs.error().message());
    return;
  }

  QString wifiDevPath;
  QString activeConnObjPath;
  for (const QDBusObjectPath& dp : devs.value()) {
    if (readDbusProp(dp.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("DeviceType"), bus).toUInt() == 2 &&
        readDbusProp(dp.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("State"), bus).toUInt() == 100) {
      wifiDevPath = dp.path();
      activeConnObjPath = readDbusProp(dp.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("ActiveConnection"), bus).value<QDBusObjectPath>().path();
      break;
    }
  }
  if (wifiDevPath.isEmpty() || activeConnObjPath.isEmpty() || activeConnObjPath == QStringLiteral("/")) {
    emit wifiBandSetFinished(false, QStringLiteral("No active Wi-Fi connection"));
    return;
  }

  const QString connPath = readDbusProp(activeConnObjPath, QStringLiteral("org.freedesktop.NetworkManager.Connection.Active"), QStringLiteral("Connection"), bus).value<QDBusObjectPath>().path();
  if (connPath.isEmpty() || connPath == QStringLiteral("/")) {
    emit wifiBandSetFinished(false, QStringLiteral("No connection profile"));
    return;
  }

  QDBusInterface connIface(QStringLiteral("org.freedesktop.NetworkManager"), connPath,
                           QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"), bus);
  QDBusReply<NmSettingsMap> settingsReply = connIface.call(QStringLiteral("GetSettings"));
  if (!settingsReply.isValid()) {
    emit wifiBandSetFinished(false, settingsReply.error().message());
    return;
  }

  NmSettingsMap prevSettings = settingsReply.value();
  NmSettingsMap nextSettings = prevSettings;
  QVariantMap wireless = nextSettings.value(QStringLiteral("802-11-wireless"));
  const QString previousNm = wireless.value(QStringLiteral("band")).toString();
  if (previousNm == desiredNm) {
    emit wifiBandSetFinished(true, QString());
    return;
  }
  if (desiredNm.isEmpty()) wireless.remove(QStringLiteral("band"));
  else wireless.insert(QStringLiteral("band"), desiredNm);
  nextSettings.insert(QStringLiteral("802-11-wireless"), wireless);

  QDBusMessage upd = QDBusMessage::createMethodCall(
      QStringLiteral("org.freedesktop.NetworkManager"), connPath,
      QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"), QStringLiteral("Update"));
  upd << QVariant::fromValue(nextSettings);
  auto* uw = new QDBusPendingCallWatcher(bus.asyncCall(upd), this);
  connect(uw, &QDBusPendingCallWatcher::finished, this,
          [this, connPath, wifiDevPath, prevSettings](QDBusPendingCallWatcher* call) {
            call->deleteLater();
            QDBusPendingReply<> ur = *call;
            if (ur.isError()) {
              emit wifiBandSetFinished(false, ur.error().message());
              return;
            }
            QDBusConnection bus2 = QDBusConnection::systemBus();
            QDBusMessage act = QDBusMessage::createMethodCall(
                QStringLiteral("org.freedesktop.NetworkManager"),
                QStringLiteral("/org/freedesktop/NetworkManager"),
                QStringLiteral("org.freedesktop.NetworkManager"),
                QStringLiteral("ActivateConnection"));
            act << QVariant::fromValue(QDBusObjectPath(connPath))
                << QVariant::fromValue(QDBusObjectPath(wifiDevPath))
                << QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")));
            auto* aw = new QDBusPendingCallWatcher(bus2.asyncCall(act, 15000), this);
            connect(aw, &QDBusPendingCallWatcher::finished, this,
                    [this, connPath, wifiDevPath, prevSettings](QDBusPendingCallWatcher* acall) {
                      acall->deleteLater();
                      QDBusPendingReply<QDBusObjectPath> ar = *acall;
                      if (ar.isError()) {
                        QDBusConnection b3 = QDBusConnection::systemBus();
                        QDBusMessage rev = QDBusMessage::createMethodCall(
                            QStringLiteral("org.freedesktop.NetworkManager"), connPath,
                            QStringLiteral("org.freedesktop.NetworkManager.Settings.Connection"), QStringLiteral("Update"));
                        rev << QVariant::fromValue(prevSettings);
                        b3.asyncCall(rev);
                        emit wifiBandSetFinished(false, ar.error().message());
                      } else {
                        refreshWifiBand();
                        emit wifiBandSetFinished(true, QString());
                      }
                    });
          });
}

void DBusEngine::connectWifiEnterprise(const QString& ssid, const QString& identity, const QString& password) {
  if (ssid.isEmpty() || identity.isEmpty() || password.isEmpty()) {
    emit wifiEnterpriseFinished(ssid, false, QStringLiteral("Missing credentials"));
    return;
  }
  QDBusConnection bus = QDBusConnection::systemBus();
  if (!bus.isConnected()) {
    emit wifiEnterpriseFinished(ssid, false, QStringLiteral("D-Bus unavailable"));
    return;
  }

  QDBusInterface nm(QStringLiteral("org.freedesktop.NetworkManager"),
                    QStringLiteral("/org/freedesktop/NetworkManager"),
                    QStringLiteral("org.freedesktop.NetworkManager"), bus);
  QDBusReply<QList<QDBusObjectPath>> devs = nm.call(QStringLiteral("GetAllDevices"));
  if (!devs.isValid()) {
    emit wifiEnterpriseFinished(ssid, false, devs.error().message());
    return;
  }

  QString wifiDevPath;
  for (const QDBusObjectPath& dp : devs.value()) {
    if (readDbusProp(dp.path(), QStringLiteral("org.freedesktop.NetworkManager.Device"), QStringLiteral("DeviceType"), bus).toUInt() == 2) {
      wifiDevPath = dp.path();
      break;
    }
  }
  if (wifiDevPath.isEmpty()) {
    emit wifiEnterpriseFinished(ssid, false, QStringLiteral("No Wi-Fi adapter"));
    return;
  }

  const QString uuidStr = QUuid::createUuid().toString(QUuid::WithoutBraces);
  NmSettingsMap settings;

  QVariantMap conn;
  conn.insert(QStringLiteral("id"), ssid);
  conn.insert(QStringLiteral("uuid"), uuidStr);
  conn.insert(QStringLiteral("type"), QStringLiteral("802-11-wireless"));
  settings.insert(QStringLiteral("connection"), conn);

  QVariantMap wireless;
  wireless.insert(QStringLiteral("ssid"), ssid.toUtf8());
  wireless.insert(QStringLiteral("mode"), QStringLiteral("infrastructure"));
  settings.insert(QStringLiteral("802-11-wireless"), wireless);

  QVariantMap wsec;
  wsec.insert(QStringLiteral("key-mgmt"), QStringLiteral("wpa-eap"));
  settings.insert(QStringLiteral("802-11-wireless-security"), wsec);

  QVariantMap eap;
  eap.insert(QStringLiteral("eap"), QStringList{QStringLiteral("peap")});
  eap.insert(QStringLiteral("phase2-auth"), QStringLiteral("mschapv2"));
  eap.insert(QStringLiteral("identity"), identity);
  eap.insert(QStringLiteral("password"), password);
  eap.insert(QStringLiteral("auth-timeout"), 8);
  settings.insert(QStringLiteral("802-1x"), eap);

  QDBusMessage callMsg = QDBusMessage::createMethodCall(
      QStringLiteral("org.freedesktop.NetworkManager"),
      QStringLiteral("/org/freedesktop/NetworkManager"),
      QStringLiteral("org.freedesktop.NetworkManager"),
      QStringLiteral("AddAndActivateConnection"));
  callMsg << QVariant::fromValue(settings)
          << QVariant::fromValue(QDBusObjectPath(wifiDevPath))
          << QVariant::fromValue(QDBusObjectPath(QStringLiteral("/")));

  auto* w = new QDBusPendingCallWatcher(bus.asyncCall(callMsg, 20000), this);
  connect(w, &QDBusPendingCallWatcher::finished, this, [this, ssid](QDBusPendingCallWatcher* call) {
    call->deleteLater();
    QDBusPendingReply<QDBusObjectPath, QDBusObjectPath> reply = *call;
    if (reply.isError()) emit wifiEnterpriseFinished(ssid, false, reply.error().message());
    else emit wifiEnterpriseFinished(ssid, true, QString());
  });
}
