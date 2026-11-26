#pragma once

#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>

class BluezAgentObject;

// Native system DBus + /dev/rfkill backend for PowerProfiles, BlueZ Agent1 + power/remove,
// and NetworkManager Wi-Fi band / 802.1X EAP configuration.
// Eliminates `gdbus monitor`, `powerprofilesctl`, `hyprvibe-bluetooth-power`,
// `hyprvibe-bluetooth-device`, Python `hyprvibe-bluetooth-pair`, and `nmcli`/`iw` loops.
class DBusEngine : public QObject {
  Q_OBJECT

public:
  explicit DBusEngine(QObject* parent = nullptr);
  ~DBusEngine() override;

  void start();

  // Power profiles
  bool powerProfileAvailable() const { return m_powerProfileAvailable; }
  QString powerProfile() const { return m_powerProfile; }
  void refreshPowerProfile();
  bool setPowerProfile(const QString& profile);

  // Bluetooth (rfkill + BlueZ DBus + native Agent1)
  void setBluetoothEnabled(bool enabled);
  void forgetBluetoothDevice(const QString& address);
  void pairBluetoothDevice(const QString& address);
  void confirmBluetoothPair(const QString& response);
  void cancelBluetoothPair();

  // NetworkManager Wi-Fi band + Enterprise EAP
  void refreshWifiBand();
  void setWifiBand(const QString& targetBand);
  void connectWifiEnterprise(const QString& ssid, const QString& identity, const QString& password);

  // Pure mappers (exposed for C++ unit tests & shared conversion)
  static QString bandForFrequency(uint mhz);
  static QString nmBandFromUi(const QString& uiBand);
  static QString uiBandFromNm(const QString& nmBand);

signals:
  void powerProfileUpdated(const QString& profile, bool available);
  void bluetoothPairPrompt(const QString& address, const QString& promptType, const QString& passkey);
  void bluetoothPairFinished(const QString& address, bool success, const QString& error);
  void wifiBandUpdated(const QString& currentBand, const QString& selectedBand, const QStringList& availableBands);
  void wifiBandSetFinished(bool success, const QString& error);
  void wifiEnterpriseFinished(const QString& ssid, bool success, const QString& error);

private slots:
  void onPowerProfilePropertiesChanged(const QString& iface, const QVariantMap& changed, const QStringList& invalidated);
  void onNmChanged();

private:
  friend class BluezAgentObject;

  void ensureAgentRegistered();
  void finishPair(bool success, const QString& error);
  void deliverAgentPrompt(const QString& type, const QString& passkey);
  void completePendingAgentPrompt(bool accept, const QString& text);
  void onPairTimeout();

  bool m_started = false;
  bool m_powerProfileAvailable = false;
  QString m_powerProfile = QStringLiteral("balanced");

  BluezAgentObject* m_agent = nullptr;
  bool m_agentRegistered = false;
  QString m_pairingAddress;
  QString m_pairingDevPath;
  bool m_hasPendingAgentMsg = false;
  QString m_pendingPromptType;
  QDBusMessage m_pendingAgentMsg;
  QTimer m_pairTimer;
  QTimer m_nmDebounce;
};

class BluezAgentObject : public QObject, protected QDBusContext {
  Q_OBJECT
  Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")

public:
  explicit BluezAgentObject(DBusEngine* owner);

public Q_SLOTS:
  Q_SCRIPTABLE void Release();
  Q_SCRIPTABLE QString RequestPinCode(const QDBusObjectPath& device);
  Q_SCRIPTABLE uint RequestPasskey(const QDBusObjectPath& device);
  Q_SCRIPTABLE void DisplayPinCode(const QDBusObjectPath& device, const QString& pincode);
  Q_SCRIPTABLE void DisplayPasskey(const QDBusObjectPath& device, uint passkey, quint16 entered);
  Q_SCRIPTABLE void RequestConfirmation(const QDBusObjectPath& device, uint passkey);
  Q_SCRIPTABLE void RequestAuthorization(const QDBusObjectPath& device);
  Q_SCRIPTABLE void AuthorizeService(const QDBusObjectPath& device, const QString& uuid);
  Q_SCRIPTABLE void Cancel();

private:
  DBusEngine* m_owner = nullptr;
};
