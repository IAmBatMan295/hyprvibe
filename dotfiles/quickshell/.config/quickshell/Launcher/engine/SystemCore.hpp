#pragma once

#include "DBusEngine.hpp"
#include "PulseEngine.hpp"

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <cstdint>

// Single native C++ backend singleton exposed alongside LauncherModel inside
// HyprVibeLauncher. Unifies POSIX hardware telemetry, TOML/Lua codecs,
// libpulse event-driven audio control, and Qt6 DBus / rfkill integration for
// PowerProfiles, BlueZ Agent1 + power/remove, and NetworkManager Wi-Fi band / EAP.
class SystemCore : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool powerProfileAvailable READ powerProfileAvailable NOTIFY powerProfileChanged)
  Q_PROPERTY(QString powerProfile READ powerProfile NOTIFY powerProfileChanged)
  Q_PROPERTY(QString audioVolumeSink READ audioVolumeSink NOTIFY audioStateChanged)
  Q_PROPERTY(QVariantMap audioSinkAvailability READ audioSinkAvailability NOTIFY audioStateChanged)
  Q_PROPERTY(QString wifiBandCurrent READ wifiBandCurrent NOTIFY wifiBandUpdated)
  Q_PROPERTY(QString wifiBandSelected READ wifiBandSelected NOTIFY wifiBandUpdated)
  Q_PROPERTY(QStringList wifiBandAvailable READ wifiBandAvailable NOTIFY wifiBandUpdated)

public:
  explicit SystemCore(QObject* parent = nullptr);

  bool powerProfileAvailable() const { return m_dbus.powerProfileAvailable(); }
  QString powerProfile() const { return m_dbus.powerProfile(); }
  QString audioVolumeSink() const { return m_pulse.volumeSinkName(); }
  QVariantMap audioSinkAvailability() const { return m_pulse.sinkAvailability(); }
  QString wifiBandCurrent() const { return m_wifiBandCurrent; }
  QString wifiBandSelected() const { return m_wifiBandSelected; }
  QStringList wifiBandAvailable() const { return m_wifiBandAvailable; }

  // Hardware & kernel telemetry (POSIX direct read, zero subprocess forks)
  Q_INVOKABLE QVariantMap sampleCpu(const QString& procRoot = QString(),
                                    const QString& sysCpuRoot = QString());
  Q_INVOKABLE QVariantMap readMemory(const QString& meminfoPath = QString()) const;
  Q_INVOKABLE QVariantMap readBacklight(const QString& backlightRoot = QString()) const;
  Q_INVOKABLE bool setBacklightPercent(int percent,
                                       const QString& backlightRoot = QString()) const;
  Q_INVOKABLE QVariantMap readBatterySysfs(const QString& powerSupplyRoot = QString()) const;
  Q_INVOKABLE bool isMpdListening(const QString& procNetTcpPath = QString(),
                                  const QString& runtimeDir = QString()) const;

  // Native audio (libpulse)
  Q_INVOKABLE void refreshAudioState();
  Q_INVOKABLE void setDefaultAudioSink(const QString& sinkName);
  Q_INVOKABLE void setDefaultAudioSource(const QString& sourceName);

  // Native DBus + rfkill (PowerProfiles, BlueZ, NetworkManager)
  Q_INVOKABLE void refreshPowerProfile();
  Q_INVOKABLE bool setPowerProfile(const QString& profile);
  Q_INVOKABLE void setBluetoothEnabled(bool enabled);
  Q_INVOKABLE void forgetBluetoothDevice(const QString& address);
  Q_INVOKABLE void pairBluetoothDevice(const QString& address);
  Q_INVOKABLE void confirmBluetoothPair(const QString& response);
  Q_INVOKABLE void cancelBluetoothPair();
  Q_INVOKABLE void refreshWifiBand();
  Q_INVOKABLE void setWifiBand(const QString& targetBand);
  Q_INVOKABLE void connectWifiEnterprise(const QString& ssid,
                                         const QString& identity,
                                         const QString& password);

  // System discovery & safe atomic file helpers
  Q_INVOKABLE QStringList listFontFamilies() const;
  Q_INVOKABLE QString monospaceFontFamily() const;
  Q_INVOKABLE QStringList listThemes(const QString& repoThemesDir,
                                     const QString& userThemesDir) const;
  Q_INVOKABLE bool pathExists(const QString& path) const;
  Q_INVOKABLE bool ensureDir(const QString& path) const;
  Q_INVOKABLE QString readFileText(const QString& path) const;
  Q_INVOKABLE bool writeFileAtomic(const QString& path, const QString& content) const;

  // TOML, Hyprland Lua override, & bar widget layout codecs
  Q_INVOKABLE QVariantMap parseShellToml(const QString& raw) const;
  Q_INVOKABLE QString renderShellToml(const QVariantMap& values) const;
  Q_INVOKABLE QVariantMap defaultHyprOverrides() const;
  Q_INVOKABLE QVariantMap parseHyprOverrides(const QString& raw) const;
  Q_INVOKABLE QString renderHyprOverrides(const QVariantMap& rawState) const;
  Q_INVOKABLE bool layoutHasWidget(const QVariantMap& layout,
                                  const QString& region,
                                  const QString& widgetId) const;
  Q_INVOKABLE QVariantMap toggleBarWidget(const QVariantMap& layout,
                                          const QString& region,
                                          const QString& widgetId,
                                          bool enabled) const;
  Q_INVOKABLE QVariantMap moveBarWidget(const QVariantMap& layout,
                                        const QString& region,
                                        int fromIndex,
                                        int toIndex) const;

signals:
  void powerProfileChanged();
  void audioStateChanged();
  void bluetoothPairPrompt(const QString& address, const QString& promptType, const QString& passkey);
  void bluetoothPairFinished(const QString& address, bool success, const QString& error);
  void wifiBandUpdated();
  void wifiBandSetFinished(bool success, const QString& error);
  void wifiEnterpriseFinished(const QString& ssid, bool success, const QString& error);

private:
  uint64_t m_prevCpuTotal = 0;
  uint64_t m_prevCpuIdle = 0;
  QString m_wifiBandCurrent;
  QString m_wifiBandSelected = QStringLiteral("auto");
  QStringList m_wifiBandAvailable;
  PulseEngine m_pulse;
  DBusEngine m_dbus;
};
