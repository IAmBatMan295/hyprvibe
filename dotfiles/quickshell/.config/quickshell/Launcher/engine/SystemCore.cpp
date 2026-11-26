#include "SystemCore.hpp"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <unistd.h>

namespace {

bool readSmallFile(const QString& path, QByteArray& out) {
  const QByteArray nativePath = QFile::encodeName(path);
  const int fd = ::open(nativePath.constData(), O_RDONLY | O_CLOEXEC);
  if (fd < 0) return false;
  out.clear();
  char buf[4096];
  ssize_t n = 0;
  while ((n = ::read(fd, buf, sizeof(buf))) > 0) {
    out.append(buf, static_cast<qsizetype>(n));
    if (out.size() > 262144) break;
  }
  ::close(fd);
  return !out.isEmpty();
}

bool readDoubleFile(const QString& path, double& out) {
  QByteArray raw;
  if (!readSmallFile(path, raw)) return false;
  bool ok = false;
  const double v = QString::fromUtf8(raw).trimmed().toDouble(&ok);
  if (!ok) return false;
  out = v;
  return true;
}

bool readInt64File(const QString& path, qint64& out) {
  QByteArray raw;
  if (!readSmallFile(path, raw)) return false;
  bool ok = false;
  const qint64 v = QString::fromUtf8(raw).trimmed().toLongLong(&ok);
  if (!ok) return false;
  out = v;
  return true;
}

QString entryIdOf(const QVariant& entry) {
  if (entry.typeId() == QMetaType::QString) return entry.toString();
  if (entry.typeId() == QMetaType::QVariantMap) {
    return entry.toMap().value(QStringLiteral("id")).toString();
  }
  return {};
}

QString formatTomlScalar(const QVariant& value) {
  if (value.typeId() == QMetaType::Bool) {
    return value.toBool() ? QStringLiteral("true") : QStringLiteral("false");
  }
  if (value.typeId() == QMetaType::Int || value.typeId() == QMetaType::LongLong ||
      value.typeId() == QMetaType::Double || value.typeId() == QMetaType::UInt) {
    const double d = value.toDouble();
    if (!std::isfinite(d)) return QStringLiteral("0");
    if (value.typeId() == QMetaType::Double && std::floor(d) != d) {
      return QString::number(d);
    }
    return QString::number(value.toDouble(), 'f', 0);
  }
  const QString s = value.toString().trimmed();
  if (s == QStringLiteral("true") || s == QStringLiteral("false")) return s;
  static const QRegularExpression numRe(QStringLiteral("^-?\\d+(?:\\.\\d+)?$"));
  if (numRe.match(s).hasMatch()) return s;
  QString escaped = s;
  escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
  escaped.replace(QLatin1Char('"'), QStringLiteral("\\\""));
  return QLatin1Char('"') + escaped + QLatin1Char('"');
}

QVariantMap normalizeHyprMap(const QVariantMap& s, const QVariantMap& def) {
  auto clampInt = [&](const char* key, int lo, int hi) -> int {
    bool ok = false;
    const QVariant val = s.contains(QLatin1String(key)) ? s.value(QLatin1String(key)) : def.value(QLatin1String(key));
    const int n = static_cast<int>(std::llround(val.toDouble(&ok)));
    const int fb = def.value(QLatin1String(key)).toInt();
    return ok ? std::clamp(n, lo, hi) : fb;
  };
  auto clampReal = [&](const char* key, double lo, double hi) -> double {
    bool ok = false;
    const QVariant val = s.contains(QLatin1String(key)) ? s.value(QLatin1String(key)) : def.value(QLatin1String(key));
    double n = val.toDouble(&ok);
    const double fb = def.value(QLatin1String(key)).toDouble();
    if (!ok || !std::isfinite(n)) return fb;
    n = std::clamp(n, lo, hi);
    return std::round(n * 100.0) / 100.0;
  };
  auto boolVal = [&](const char* key) -> bool {
    if (!s.contains(QLatin1String(key))) return def.value(QLatin1String(key)).toBool();
    const QVariant val = s.value(QLatin1String(key));
    if (val.typeId() == QMetaType::QString) {
      const QString low = val.toString().trimmed().toLower();
      return low == QStringLiteral("true") || low == QStringLiteral("1") || low == QStringLiteral("yes");
    }
    return val.toBool();
  };

  QVariantMap out;
  out.insert(QStringLiteral("gaps_in"), clampInt("gaps_in", 0, 48));
  out.insert(QStringLiteral("gaps_out"), clampInt("gaps_out", 0, 64));
  out.insert(QStringLiteral("border_size"), clampInt("border_size", 0, 12));
  out.insert(QStringLiteral("rounding"), clampInt("rounding", 0, 32));
  out.insert(QStringLiteral("active_opacity"), clampReal("active_opacity", 0.2, 1.0));
  out.insert(QStringLiteral("inactive_opacity"), clampReal("inactive_opacity", 0.2, 1.0));
  out.insert(QStringLiteral("blur_enabled"), boolVal("blur_enabled"));
  out.insert(QStringLiteral("blur_size"), clampInt("blur_size", 1, 20));
  out.insert(QStringLiteral("blur_passes"), clampInt("blur_passes", 1, 6));
  out.insert(QStringLiteral("shadow_enabled"), boolVal("shadow_enabled"));
  out.insert(QStringLiteral("animations_enabled"), boolVal("animations_enabled"));
  out.insert(QStringLiteral("follow_mouse"), clampInt("follow_mouse", 0, 3));
  out.insert(QStringLiteral("natural_scroll"), boolVal("natural_scroll"));
  out.insert(QStringLiteral("vrr"), clampInt("vrr", 0, 2));
  return out;
}

}  // namespace

SystemCore::SystemCore(QObject* parent) : QObject(parent), m_pulse(this), m_dbus(this) {
  connect(&m_pulse, &PulseEngine::stateUpdated, this, [this]() { emit audioStateChanged(); });
  connect(&m_dbus, &DBusEngine::powerProfileUpdated, this, [this]() { emit powerProfileChanged(); });
  connect(&m_dbus, &DBusEngine::bluetoothPairPrompt, this, &SystemCore::bluetoothPairPrompt);
  connect(&m_dbus, &DBusEngine::bluetoothPairFinished, this, &SystemCore::bluetoothPairFinished);
  connect(&m_dbus, &DBusEngine::wifiBandUpdated, this,
          [this](const QString& current, const QString& selected, const QStringList& available) {
            m_wifiBandCurrent = current;
            m_wifiBandSelected = selected.isEmpty() ? QStringLiteral("auto") : selected;
            m_wifiBandAvailable = available;
            emit wifiBandUpdated();
          });
  connect(&m_dbus, &DBusEngine::wifiBandSetFinished, this, &SystemCore::wifiBandSetFinished);
  connect(&m_dbus, &DBusEngine::wifiEnterpriseFinished, this, &SystemCore::wifiEnterpriseFinished);

  m_pulse.start();
  m_dbus.start();
}

void SystemCore::refreshAudioState() { m_pulse.refreshState(); }
void SystemCore::setDefaultAudioSink(const QString& sinkName) { m_pulse.setDefaultSink(sinkName); }
void SystemCore::setDefaultAudioSource(const QString& sourceName) { m_pulse.setDefaultSource(sourceName); }

void SystemCore::refreshPowerProfile() { m_dbus.refreshPowerProfile(); }
bool SystemCore::setPowerProfile(const QString& profile) { return m_dbus.setPowerProfile(profile); }
void SystemCore::setBluetoothEnabled(bool enabled) { m_dbus.setBluetoothEnabled(enabled); }
void SystemCore::forgetBluetoothDevice(const QString& address) { m_dbus.forgetBluetoothDevice(address); }
void SystemCore::pairBluetoothDevice(const QString& address) { m_dbus.pairBluetoothDevice(address); }
void SystemCore::confirmBluetoothPair(const QString& response) { m_dbus.confirmBluetoothPair(response); }
void SystemCore::cancelBluetoothPair() { m_dbus.cancelBluetoothPair(); }
void SystemCore::refreshWifiBand() { m_dbus.refreshWifiBand(); }
void SystemCore::setWifiBand(const QString& targetBand) { m_dbus.setWifiBand(targetBand); }
void SystemCore::connectWifiEnterprise(const QString& ssid, const QString& identity, const QString& password) {
  m_dbus.connectWifiEnterprise(ssid, identity, password);
}

QVariantMap SystemCore::sampleCpu(const QString& procRoot, const QString& sysCpuRoot) {
  const QString pRoot = procRoot.isEmpty() ? QStringLiteral("/proc") : procRoot;
  const QString sRoot = sysCpuRoot.isEmpty() ? QStringLiteral("/sys/devices/system/cpu/cpufreq") : sysCpuRoot;

  double curSumGhz = 0.0;
  int curCount = 0;
  double minGhz = 0.0;
  double maxGhz = 0.0;

  QDir freqDir(sRoot);
  if (freqDir.exists()) {
    const QStringList policies = freqDir.entryList({QStringLiteral("policy*")}, QDir::Dirs | QDir::NoDotAndDotDot);
    double bestMinKhz = 1e12;
    double bestMaxKhz = 0.0;
    for (const QString& pol : policies) {
      const QString base = sRoot + QLatin1Char('/') + pol;
      double khz = 0.0;
      if (readDoubleFile(base + QStringLiteral("/scaling_cur_freq"), khz) && khz > 0.0) {
        curSumGhz += khz / 1000000.0;
        curCount++;
      }
      if (readDoubleFile(base + QStringLiteral("/cpuinfo_min_freq"), khz) && khz > 0.0) {
        bestMinKhz = std::min(bestMinKhz, khz);
      } else if (readDoubleFile(base + QStringLiteral("/scaling_min_freq"), khz) && khz > 0.0) {
        bestMinKhz = std::min(bestMinKhz, khz);
      }
      if (readDoubleFile(base + QStringLiteral("/cpuinfo_max_freq"), khz) && khz > 0.0) {
        bestMaxKhz = std::max(bestMaxKhz, khz);
      } else if (readDoubleFile(base + QStringLiteral("/scaling_max_freq"), khz) && khz > 0.0) {
        bestMaxKhz = std::max(bestMaxKhz, khz);
      }
    }
    if (bestMinKhz < 1e12) minGhz = bestMinKhz / 1000000.0;
    if (bestMaxKhz > 0.0) maxGhz = bestMaxKhz / 1000000.0;
  }

  double curGhz = curCount > 0 ? (curSumGhz / curCount) : 0.0;
  if (curGhz <= 0.0) {
    QByteArray infoRaw;
    if (readSmallFile(pRoot + QStringLiteral("/cpuinfo"), infoRaw)) {
      const QList<QByteArray> lines = infoRaw.split('\n');
      double mhzSum = 0.0;
      int mhzCount = 0;
      for (const QByteArray& line : lines) {
        if (!line.startsWith("cpu MHz")) continue;
        const int colon = line.indexOf(':');
        if (colon < 0) continue;
        bool ok = false;
        const double mhz = line.mid(colon + 1).trimmed().toDouble(&ok);
        if (ok && mhz > 0.0) {
          mhzSum += mhz;
          mhzCount++;
        }
      }
      if (mhzCount > 0) curGhz = (mhzSum / mhzCount) / 1000.0;
    }
  }

  double usageRatio = -1.0;
  QByteArray statRaw;
  if (readSmallFile(pRoot + QStringLiteral("/stat"), statRaw)) {
    const int nl = statRaw.indexOf('\n');
    const QString firstLine = QString::fromUtf8(nl > 0 ? statRaw.left(nl) : statRaw).trimmed();
    if (firstLine.startsWith(QStringLiteral("cpu "))) {
      const QStringList cols = firstLine.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
      if (cols.size() >= 9) {
        uint64_t total = 0;
        for (int i = 1; i <= 8; ++i) total += cols[i].toULongLong();
        const uint64_t idleAll = cols[4].toULongLong() + cols[5].toULongLong();
        if (m_prevCpuTotal > 0 && total > m_prevCpuTotal) {
          const double diffTotal = static_cast<double>(total - m_prevCpuTotal);
          const double diffIdle = idleAll >= m_prevCpuIdle ? static_cast<double>(idleAll - m_prevCpuIdle) : 0.0;
          usageRatio = std::clamp((diffTotal - diffIdle) / diffTotal, 0.0, 1.0);
        }
        m_prevCpuTotal = total;
        m_prevCpuIdle = idleAll;
      }
    }
  }

  QVariantMap res;
  res.insert(QStringLiteral("valid"), curGhz > 0.0 || usageRatio >= 0.0);
  res.insert(QStringLiteral("curGhz"), curGhz);
  res.insert(QStringLiteral("minGhz"), minGhz);
  res.insert(QStringLiteral("maxGhz"), maxGhz);
  res.insert(QStringLiteral("frequency"), curGhz > 0.0 ? (QString::number(curGhz, 'f', 1) + QStringLiteral(" GHz")) : QStringLiteral("— GHz"));
  res.insert(QStringLiteral("hasUsage"), usageRatio >= 0.0);
  if (usageRatio >= 0.0) {
    res.insert(QStringLiteral("usageRatio"), usageRatio);
    res.insert(QStringLiteral("usage"), QString::number(std::llround(usageRatio * 100.0)) + QStringLiteral("%"));
  } else {
    res.insert(QStringLiteral("usageRatio"), 0.0);
    res.insert(QStringLiteral("usage"), QStringLiteral("0%"));
  }
  return res;
}

QVariantMap SystemCore::readMemory(const QString& meminfoPath) const {
  const QString path = meminfoPath.isEmpty() ? QStringLiteral("/proc/meminfo") : meminfoPath;
  QByteArray raw;
  if (!readSmallFile(path, raw)) return {{QStringLiteral("valid"), false}};

  double memTotal = 0.0;
  double memAvail = -1.0;
  double memFree = 0.0;
  double buffers = 0.0;
  double cached = 0.0;
  double swapTotal = 0.0;
  double swapFree = 0.0;

  const QList<QByteArray> lines = raw.split('\n');
  for (const QByteArray& line : lines) {
    const int colon = line.indexOf(':');
    if (colon <= 0) continue;
    const QByteArray key = line.left(colon);
    const QList<QByteArray> rest = line.mid(colon + 1).trimmed().split(' ');
    if (rest.isEmpty()) continue;
    const double kb = rest.first().toDouble();
    if (key == "MemTotal") memTotal = kb;
    else if (key == "MemAvailable") memAvail = kb;
    else if (key == "MemFree") memFree = kb;
    else if (key == "Buffers") buffers = kb;
    else if (key == "Cached") cached = kb;
    else if (key == "SwapTotal") swapTotal = kb;
    else if (key == "SwapFree") swapFree = kb;
  }

  if (memTotal <= 0.0) return {{QStringLiteral("valid"), false}};
  if (memAvail < 0.0) memAvail = memFree + buffers + cached;

  const double divGb = 1024.0 * 1024.0;
  const double usedGb = std::max(0.0, (memTotal - memAvail) / divGb);
  const double totalGb = memTotal / divGb;
  const double swapUsedGb = std::max(0.0, (swapTotal - swapFree) / divGb);
  const double swapTotalGb = std::max(0.0, swapTotal / divGb);

  const QString text = QString::number(usedGb, 'f', 1) + QStringLiteral(" GB");
  const QString tooltip = QStringLiteral("Used: ") + QString::number(usedGb, 'f', 1)
      + QStringLiteral("G / ") + QString::number(totalGb, 'f', 1)
      + QStringLiteral("G\nSwap: ") + QString::number(swapUsedGb, 'f', 1)
      + QStringLiteral("G / ") + QString::number(swapTotalGb, 'f', 1) + QStringLiteral("G");

  QVariantMap res;
  res.insert(QStringLiteral("valid"), true);
  res.insert(QStringLiteral("usedGb"), usedGb);
  res.insert(QStringLiteral("totalGb"), totalGb);
  res.insert(QStringLiteral("text"), text);
  res.insert(QStringLiteral("tooltip"), tooltip);
  return res;
}

QVariantMap SystemCore::readBacklight(const QString& backlightRoot) const {
  QString root = backlightRoot;
  if (root.isEmpty()) {
    const QByteArray envPath = qgetenv("HYPRVIBE_BACKLIGHT_PATH");
    root = envPath.isEmpty() ? QStringLiteral("/sys/class/backlight") : QString::fromUtf8(envPath);
  }
  QDir dir(root);
  if (!dir.exists()) return {{QStringLiteral("available"), false}, {QStringLiteral("percent"), 40}};

  const QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
  for (const QString& name : entries) {
    const QString devDir = root + QLatin1Char('/') + name;
    qint64 cur = 0;
    qint64 maxVal = 0;
    if (readInt64File(devDir + QStringLiteral("/brightness"), cur) &&
        readInt64File(devDir + QStringLiteral("/max_brightness"), maxVal) && maxVal > 0) {
      const int pct = std::clamp(static_cast<int>(std::llround((static_cast<double>(cur) * 100.0) / static_cast<double>(maxVal))), 0, 100);
      return {
        {QStringLiteral("available"), true},
        {QStringLiteral("percent"), pct},
        {QStringLiteral("device"), name}
      };
    }
  }
  return {{QStringLiteral("available"), false}, {QStringLiteral("percent"), 40}};
}

bool SystemCore::setBacklightPercent(int percent, const QString& backlightRoot) const {
  const int target = std::clamp(percent, 1, 100);
  QString root = backlightRoot;
  if (root.isEmpty()) {
    const QByteArray envPath = qgetenv("HYPRVIBE_BACKLIGHT_PATH");
    root = envPath.isEmpty() ? QStringLiteral("/sys/class/backlight") : QString::fromUtf8(envPath);
  }
  QDir dir(root);
  if (dir.exists()) {
    const QStringList entries = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString& name : entries) {
      const QString devDir = root + QLatin1Char('/') + name;
      qint64 maxVal = 0;
      if (readInt64File(devDir + QStringLiteral("/max_brightness"), maxVal) && maxVal > 0) {
        const qint64 raw = std::clamp<qint64>(std::llround(static_cast<double>(target) * maxVal / 100.0), 1, maxVal);
        QFile f(devDir + QStringLiteral("/brightness"));
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
          f.write(QByteArray::number(raw));
          f.close();
          return true;
        }
        break;
      }
    }
  }
  if (!backlightRoot.isEmpty()) return false;
  return QProcess::startDetached(QStringLiteral("brightnessctl"), {QStringLiteral("set"), QString::number(target) + QLatin1Char('%')});
}

QVariantMap SystemCore::readBatterySysfs(const QString& powerSupplyRoot) const {
  QString root = powerSupplyRoot;
  if (root.isEmpty()) {
    const QByteArray envPath = qgetenv("HYPRVIBE_POWER_SUPPLY_PATH");
    root = envPath.isEmpty() ? QStringLiteral("/sys/class/power_supply") : QString::fromUtf8(envPath);
  }

  bool acOnline = false;
  double rateWatts = 0.0;
  bool hasRate = false;
  double capacityWh = 0.0;
  bool hasCapacity = false;
  qint64 cycles = -1;
  int thresholdStart = -1;
  int thresholdEnd = -1;

  QDir dir(root);
  if (dir.exists()) {
    const QStringList supplies = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString& name : supplies) {
      const QString sDir = root + QLatin1Char('/') + name;
      QByteArray typeRaw;
      readSmallFile(sDir + QStringLiteral("/type"), typeRaw);
      const QString supplyType = QString::fromUtf8(typeRaw).trimmed();

      if (supplyType == QStringLiteral("Mains")) {
        qint64 online = 0;
        if (readInt64File(sDir + QStringLiteral("/online"), online) && online == 1) acOnline = true;
        continue;
      }

      if (supplyType == QStringLiteral("Battery") || name.startsWith(QStringLiteral("BAT")) || name.startsWith(QStringLiteral("CMB"))) {
        if (!hasRate) {
          double val = 0.0;
          if (readDoubleFile(sDir + QStringLiteral("/power_now"), val)) {
            rateWatts = std::abs(val) / 1000000.0;
            hasRate = true;
          } else {
            double amps = 0.0, volts = 0.0;
            if (readDoubleFile(sDir + QStringLiteral("/current_now"), amps) &&
                readDoubleFile(sDir + QStringLiteral("/voltage_now"), volts)) {
              rateWatts = std::abs(amps * volts) / 1000000000000.0;
              hasRate = true;
            }
          }
        }
        if (!hasCapacity) {
          double ef = 0.0;
          if (readDoubleFile(sDir + QStringLiteral("/energy_full"), ef) && ef > 0.0) {
            capacityWh = ef / 1000000.0;
            hasCapacity = true;
          } else {
            double cf = 0.0, vn = 0.0;
            if (readDoubleFile(sDir + QStringLiteral("/charge_full"), cf) &&
                readDoubleFile(sDir + QStringLiteral("/voltage_now"), vn) && cf > 0.0 && vn > 0.0) {
              capacityWh = (cf * vn) / 1000000000000.0;
              hasCapacity = true;
            }
          }
        }
        if (cycles < 0) {
          qint64 c = -1;
          if (readInt64File(sDir + QStringLiteral("/cycle_count"), c) && c >= 0) cycles = c;
        }
        if (thresholdEnd < 0) {
          qint64 te = -1;
          if (readInt64File(sDir + QStringLiteral("/charge_control_end_threshold"), te) && te > 0) {
            thresholdEnd = static_cast<int>(te);
          }
        }
        if (thresholdStart < 0) {
          qint64 ts = -1;
          if (readInt64File(sDir + QStringLiteral("/charge_control_start_threshold"), ts) && ts >= 0) {
            thresholdStart = static_cast<int>(ts);
          }
        }
      }
    }
  }

  if (thresholdEnd < 0 && powerSupplyRoot.isEmpty()) {
    const QStringList candidates = {
      QStringLiteral("/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"),
      QStringLiteral("/sys/devices/platform/ideapad_acpi/VPC2004:00/conservation_mode")
    };
    for (const QString& cand : candidates) {
      qint64 v = 0;
      if (readInt64File(cand, v) && v == 1) {
        thresholdEnd = 60;
        break;
      }
    }
  }

  QString rateStr = QString::number(rateWatts, 'f', 1);
  if (rateStr.endsWith(QStringLiteral(".0"))) rateStr.chop(2);
  rateStr += QLatin1Char('W');

  QString thresholdStr;
  if (thresholdEnd > 0) {
    if (thresholdStart >= 0 && thresholdStart != thresholdEnd) {
      thresholdStr = QString::number(thresholdStart) + QLatin1Char('-') + QString::number(thresholdEnd) + QLatin1Char('%');
    } else {
      thresholdStr = QString::number(thresholdEnd) + QLatin1Char('%');
    }
  }

  QVariantMap res;
  res.insert(QStringLiteral("acOnline"), acOnline);
  res.insert(QStringLiteral("hasRate"), hasRate);
  res.insert(QStringLiteral("rateWatts"), rateWatts);
  res.insert(QStringLiteral("rate"), rateStr);
  res.insert(QStringLiteral("chargeIdle"), rateWatts <= 0.2);
  res.insert(QStringLiteral("size"), hasCapacity ? (QString::number(std::llround(capacityWh)) + QStringLiteral("Wh")) : QString());
  res.insert(QStringLiteral("cycles"), cycles >= 0 ? QString::number(cycles) : QString());
  res.insert(QStringLiteral("thresholdEnd"), thresholdEnd);
  res.insert(QStringLiteral("threshold"), thresholdStr);
  return res;
}

bool SystemCore::isMpdListening(const QString& procNetTcpPath, const QString& runtimeDir) const {
  const QString rt = runtimeDir.isEmpty() ? QString::fromUtf8(qgetenv("XDG_RUNTIME_DIR")) : runtimeDir;
  if (!rt.isEmpty()) {
    const QByteArray sockPath = QFile::encodeName(rt + QStringLiteral("/mpd/socket"));
    if (::access(sockPath.constData(), F_OK) == 0) return true;
  }
  const QString tcpPath = procNetTcpPath.isEmpty() ? QStringLiteral("/proc/net/tcp") : procNetTcpPath;
  QByteArray raw;
  if (readSmallFile(tcpPath, raw)) {
    // Port 6600 == 0x19C8, LISTEN state == "0A"
    if (raw.contains(":19C8 ") && raw.contains(" 0A ")) return true;
  }
  return false;
}

QStringList SystemCore::listFontFamilies() const {
  QStringList list = QFontDatabase::families();
  list.removeDuplicates();
  list.sort(Qt::CaseInsensitive);
  return list;
}

QString SystemCore::monospaceFontFamily() const {
  const QString fam = QFontDatabase::systemFont(QFontDatabase::FixedFont).family().trimmed();
  return fam.isEmpty() ? QStringLiteral("JetBrainsMono Nerd Font") : fam;
}

QStringList SystemCore::listThemes(const QString& repoThemesDir, const QString& userThemesDir) const {
  QStringList out;
  QSet<QString> seen;
  for (const QString& dirPath : {repoThemesDir, userThemesDir}) {
    if (dirPath.isEmpty()) continue;
    QDir dir(dirPath);
    if (!dir.exists()) continue;
    const QStringList subs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QString& slug : subs) {
      if (seen.contains(slug)) continue;
      if (QFileInfo::exists(dirPath + QLatin1Char('/') + slug + QStringLiteral("/colors.toml"))) {
        seen.insert(slug);
        out.append(slug);
      }
    }
  }
  return out;
}

bool SystemCore::pathExists(const QString& path) const {
  if (path.isEmpty()) return false;
  const QByteArray p = QFile::encodeName(path);
  return ::access(p.constData(), F_OK) == 0;
}

bool SystemCore::ensureDir(const QString& path) const {
  if (path.isEmpty()) return false;
  return QDir().mkpath(path);
}

QString SystemCore::readFileText(const QString& path) const {
  QFile f(path);
  if (!f.open(QIODevice::ReadOnly)) return {};
  return QString::fromUtf8(f.readAll());
}

bool SystemCore::writeFileAtomic(const QString& path, const QString& content) const {
  if (path.isEmpty()) return false;
  QFileInfo fi(path);
  QDir().mkpath(fi.absolutePath());
  QSaveFile out(path);
  if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
  out.write(content.toUtf8());
  return out.commit();
}

QVariantMap SystemCore::parseShellToml(const QString& raw) const {
  QVariantMap parsed;
  if (raw.isEmpty()) return parsed;

  static const QRegularExpression secRe(QStringLiteral("^\\[([A-Za-z0-9_.-]+)\\]\\s*(?:#.*)?$"));
  static const QRegularExpression strRe(QStringLiteral("^([A-Za-z0-9_-]+)\\s*=\\s*[\"']([^\"']+)[\"']\\s*(?:#.*)?$"));
  static const QRegularExpression numRe(QStringLiteral("^([A-Za-z0-9_-]+)\\s*=\\s*(-?\\d+(?:\\.\\d+)?)\\s*(?:#.*)?$"));
  static const QRegularExpression widthRe(QStringLiteral("^([A-Za-z0-9_-]+)\\s*=\\s*(-?\\d+(?:\\.\\d+)?(?:\\s+-?\\d+(?:\\.\\d+)?){1,3})\\s*(?:#.*)?$"));
  static const QRegularExpression bareRe(QStringLiteral("^([A-Za-z0-9_-]+)\\s*=\\s*([A-Za-z][A-Za-z0-9_-]*)\\s*(?:#.*)?$"));

  QString section;
  const QStringList lines = raw.split(QLatin1Char('\n'));
  for (const QString& rawLine : lines) {
    const QString line = rawLine.trimmed();
    if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) continue;
    const QRegularExpressionMatch sm = secRe.match(line);
    if (sm.hasMatch()) {
      section = sm.captured(1);
      continue;
    }
    if (section.isEmpty()) continue;

    QRegularExpressionMatch m = strRe.match(line);
    if (!m.hasMatch()) m = numRe.match(line);
    if (!m.hasMatch()) m = widthRe.match(line);
    if (!m.hasMatch()) m = bareRe.match(line);
    if (m.hasMatch()) {
      QString val = m.captured(2);
      val.replace(QStringLiteral("\\\\"), QStringLiteral("\\"));
      val.replace(QStringLiteral("\\\""), QStringLiteral("\""));
      parsed.insert(section + QLatin1Char('.') + m.captured(1), val);
    }
  }
  return parsed;
}

QString SystemCore::renderShellToml(const QVariantMap& values) const {
  static const QStringList order = {
    QStringLiteral("font"), QStringLiteral("spacing"), QStringLiteral("corner"),
    QStringLiteral("effects"), QStringLiteral("bar"), QStringLiteral("panels"), QStringLiteral("launcher")
  };

  QMap<QString, QList<QPair<QString, QString>>> sections;
  for (auto it = values.constBegin(); it != values.constEnd(); ++it) {
    const QVariant val = it.value();
    if (!val.isValid() || val.isNull() || val.toString().trimmed().isEmpty()) continue;
    const int dot = it.key().indexOf(QLatin1Char('.'));
    if (dot <= 0 || dot == it.key().size() - 1) continue;
    const QString sec = it.key().left(dot);
    const QString key = it.key().mid(dot + 1);
    sections[sec].append({key, formatTomlScalar(val)});
  }

  if (sections.isEmpty()) {
    return QStringLiteral("# HyprVibe user overrides (managed by Settings GUI)\n");
  }

  QStringList allSections = sections.keys();
  std::sort(allSections.begin(), allSections.end(), [&](const QString& a, const QString& b) {
    const int ia = order.indexOf(a);
    const int ib = order.indexOf(b);
    if (ia >= 0 && ib >= 0) return ia < ib;
    if (ia >= 0) return true;
    if (ib >= 0) return false;
    return a < b;
  });

  QStringList lines = {QStringLiteral("# HyprVibe user overrides (managed by Settings GUI)"), QString()};
  for (const QString& sec : allSections) {
    lines.append(QLatin1Char('[') + sec + QLatin1Char(']'));
    auto& pairs = sections[sec];
    std::sort(pairs.begin(), pairs.end(), [](const auto& x, const auto& y) { return x.first < y.first; });
    for (const auto& kv : pairs) {
      lines.append(kv.first + QStringLiteral(" = ") + kv.second);
    }
    lines.append(QString());
  }
  return lines.join(QLatin1Char('\n'));
}

QVariantMap SystemCore::defaultHyprOverrides() const {
  return {
    {QStringLiteral("gaps_in"), 3},
    {QStringLiteral("gaps_out"), 5},
    {QStringLiteral("border_size"), 2},
    {QStringLiteral("rounding"), 0},
    {QStringLiteral("active_opacity"), 1.0},
    {QStringLiteral("inactive_opacity"), 0.8},
    {QStringLiteral("blur_enabled"), true},
    {QStringLiteral("blur_size"), 6},
    {QStringLiteral("blur_passes"), 2},
    {QStringLiteral("shadow_enabled"), true},
    {QStringLiteral("animations_enabled"), true},
    {QStringLiteral("follow_mouse"), 1},
    {QStringLiteral("natural_scroll"), true},
    {QStringLiteral("vrr"), 2}
  };
}

QVariantMap SystemCore::parseHyprOverrides(const QString& raw) const {
  const QVariantMap def = defaultHyprOverrides();
  static const QRegularExpression metaRe(QStringLiteral("^--\\s*hyprvibe-settings:\\s*(\\{[^\\n]*\\})"), QRegularExpression::MultilineOption);
  const QRegularExpressionMatch m = metaRe.match(raw);
  if (m.hasMatch()) {
    const QJsonDocument doc = QJsonDocument::fromJson(m.captured(1).toUtf8());
    if (doc.isObject()) {
      return normalizeHyprMap(doc.object().toVariantMap(), def);
    }
  }
  return def;
}

QString SystemCore::renderHyprOverrides(const QVariantMap& rawState) const {
  const QVariantMap s = normalizeHyprMap(rawState, defaultHyprOverrides());
  const QByteArray jsonMeta = QJsonDocument(QJsonObject::fromVariantMap(s)).toJson(QJsonDocument::Compact);

  const QStringList lines = {
    QStringLiteral("-- Auto-generated by HyprVibe Settings GUI (git-untracked user overrides)"),
    QStringLiteral("-- hyprvibe-settings: ") + QString::fromUtf8(jsonMeta),
    QStringLiteral("hl.config({"),
    QStringLiteral("\tgeneral = {"),
    QStringLiteral("\t\tgaps_in = ") + QString::number(s.value(QStringLiteral("gaps_in")).toInt()) + QLatin1Char(','),
    QStringLiteral("\t\tgaps_out = ") + QString::number(s.value(QStringLiteral("gaps_out")).toInt()) + QLatin1Char(','),
    QStringLiteral("\t\tborder_size = ") + QString::number(s.value(QStringLiteral("border_size")).toInt()) + QLatin1Char(','),
    QStringLiteral("\t},"),
    QStringLiteral("\tdecoration = {"),
    QStringLiteral("\t\trounding = ") + QString::number(s.value(QStringLiteral("rounding")).toInt()) + QLatin1Char(','),
    QStringLiteral("\t\tactive_opacity = ") + QString::number(s.value(QStringLiteral("active_opacity")).toDouble(), 'f', 2) + QLatin1Char(','),
    QStringLiteral("\t\tinactive_opacity = ") + QString::number(s.value(QStringLiteral("inactive_opacity")).toDouble(), 'f', 2) + QLatin1Char(','),
    QStringLiteral("\t\tblur = {"),
    QStringLiteral("\t\t\tenabled = ") + (s.value(QStringLiteral("blur_enabled")).toBool() ? QStringLiteral("true") : QStringLiteral("false")) + QLatin1Char(','),
    QStringLiteral("\t\t\tsize = ") + QString::number(s.value(QStringLiteral("blur_size")).toInt()) + QLatin1Char(','),
    QStringLiteral("\t\t\tpasses = ") + QString::number(s.value(QStringLiteral("blur_passes")).toInt()) + QLatin1Char(','),
    QStringLiteral("\t\t},"),
    QStringLiteral("\t\tshadow = {"),
    QStringLiteral("\t\t\tenabled = ") + (s.value(QStringLiteral("shadow_enabled")).toBool() ? QStringLiteral("true") : QStringLiteral("false")) + QLatin1Char(','),
    QStringLiteral("\t\t},"),
    QStringLiteral("\t},"),
    QStringLiteral("\tanimations = {"),
    QStringLiteral("\t\tenabled = ") + (s.value(QStringLiteral("animations_enabled")).toBool() ? QStringLiteral("true") : QStringLiteral("false")) + QLatin1Char(','),
    QStringLiteral("\t},"),
    QStringLiteral("\tmisc = {"),
    QStringLiteral("\t\tvrr = ") + QString::number(s.value(QStringLiteral("vrr")).toInt()) + QLatin1Char(','),
    QStringLiteral("\t},"),
    QStringLiteral("\tinput = {"),
    QStringLiteral("\t\tfollow_mouse = ") + QString::number(s.value(QStringLiteral("follow_mouse")).toInt()) + QLatin1Char(','),
    QStringLiteral("\t\ttouchpad = {"),
    QStringLiteral("\t\t\tnatural_scroll = ") + (s.value(QStringLiteral("natural_scroll")).toBool() ? QStringLiteral("true") : QStringLiteral("false")) + QLatin1Char(','),
    QStringLiteral("\t\t},"),
    QStringLiteral("\t},"),
    QStringLiteral("})"),
    QString()
  };
  return lines.join(QLatin1Char('\n'));
}

bool SystemCore::layoutHasWidget(const QVariantMap& layout, const QString& region, const QString& widgetId) const {
  const QVariantList list = layout.value(region).toList();
  for (const QVariant& entry : list) {
    if (entryIdOf(entry) == widgetId) return true;
  }
  return false;
}

QVariantMap SystemCore::toggleBarWidget(const QVariantMap& layout, const QString& region, const QString& widgetId, bool enabled) const {
  QVariantMap next = layout;
  QVariantList list = next.value(region).toList();
  int existsAt = -1;
  for (int i = 0; i < list.size(); ++i) {
    if (entryIdOf(list[i]) == widgetId) {
      existsAt = i;
      break;
    }
  }
  if (enabled && existsAt < 0) {
    list.append(QVariantMap{{QStringLiteral("id"), widgetId}});
  } else if (!enabled && existsAt >= 0) {
    list.removeAt(existsAt);
  }
  next.insert(region, list);
  return next;
}

QVariantMap SystemCore::moveBarWidget(const QVariantMap& layout, const QString& region, int fromIndex, int toIndex) const {
  QVariantMap next = layout;
  QVariantList list = next.value(region).toList();
  if (fromIndex >= 0 && fromIndex < list.size() && toIndex >= 0 && toIndex < list.size() && fromIndex != toIndex) {
    list.move(fromIndex, toIndex);
    next.insert(region, list);
  }
  return next;
}
