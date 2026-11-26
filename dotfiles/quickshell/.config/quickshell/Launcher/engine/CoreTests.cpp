#include "LauncherModel.hpp"
#include "SystemCore.hpp"

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <cassert>
#include <cmath>
#include <cstdio>

static void writeText(const QString& path, const QByteArray& content) {
  QFileInfo fi(path);
  QDir().mkpath(fi.absolutePath());
  QFile f(path);
  assert(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
  f.write(content);
  f.close();
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  QGuiApplication app(argc, argv);

  SystemCore core;
  QTemporaryDir tmp;
  assert(tmp.isValid());
  const QString root = tmp.path();

  // 1. CPU sampling against synthetic /proc & cpufreq sysfs
  writeText(root + "/sys/policy0/scaling_cur_freq", "2400000\n");
  writeText(root + "/sys/policy0/cpuinfo_min_freq", "800000\n");
  writeText(root + "/sys/policy0/cpuinfo_max_freq", "4800000\n");
  writeText(root + "/proc/stat", "cpu  1000 0 200 8800 0 0 0 0 0 0\n");
  const QVariantMap c1 = core.sampleCpu(root + "/proc", root + "/sys");
  assert(c1.value("valid").toBool());
  assert(std::abs(c1.value("curGhz").toDouble() - 2.4) < 0.01);
  assert(std::abs(c1.value("minGhz").toDouble() - 0.8) < 0.01);
  assert(std::abs(c1.value("maxGhz").toDouble() - 4.8) < 0.01);

  writeText(root + "/proc/stat", "cpu  1400 0 300 9300 0 0 0 0 0 0\n");
  const QVariantMap c2 = core.sampleCpu(root + "/proc", root + "/sys");
  assert(c2.value("hasUsage").toBool());
  // delta total = 1000, delta idle = 500 -> 50%
  assert(c2.value("usage").toString() == "50%");

  // 2. /proc/meminfo parsing
  writeText(root + "/proc/meminfo",
            "MemTotal:       16777216 kB\n"
            "MemAvailable:    8388608 kB\n"
            "SwapTotal:       4194304 kB\n"
            "SwapFree:        3145728 kB\n");
  const QVariantMap mem = core.readMemory(root + "/proc/meminfo");
  assert(mem.value("valid").toBool());
  assert(std::abs(mem.value("usedGb").toDouble() - 8.0) < 0.01);
  assert(std::abs(mem.value("totalGb").toDouble() - 16.0) < 0.01);
  assert(mem.value("text").toString() == "8.0 GB");

  // 3. Backlight read + write sysfs
  writeText(root + "/bl/intel_backlight/max_brightness", "1000\n");
  writeText(root + "/bl/intel_backlight/brightness", "400\n");
  const QVariantMap bl1 = core.readBacklight(root + "/bl");
  assert(bl1.value("available").toBool());
  assert(bl1.value("percent").toInt() == 40);
  assert(core.setBacklightPercent(75, root + "/bl"));
  const QVariantMap bl2 = core.readBacklight(root + "/bl");
  assert(bl2.value("percent").toInt() == 75);

  // 4. Battery sysfs (AC online, power_now, energy_full, cycles, threshold)
  writeText(root + "/ps/AC/type", "Mains\n");
  writeText(root + "/ps/AC/online", "1\n");
  writeText(root + "/ps/BAT0/type", "Battery\n");
  writeText(root + "/ps/BAT0/power_now", "12500000\n");
  writeText(root + "/ps/BAT0/energy_full", "72000000\n");
  writeText(root + "/ps/BAT0/cycle_count", "42\n");
  writeText(root + "/ps/BAT0/charge_control_start_threshold", "55\n");
  writeText(root + "/ps/BAT0/charge_control_end_threshold", "80\n");
  const QVariantMap bat = core.readBatterySysfs(root + "/ps");
  assert(bat.value("acOnline").toBool());
  assert(bat.value("rate").toString() == "12.5W");
  assert(bat.value("size").toString() == "72Wh");
  assert(bat.value("cycles").toString() == "42");
  assert(bat.value("threshold").toString() == "55-80%");

  // 5. MPD socket /proc/net/tcp gate
  writeText(root + "/tcp_idle", "  0: 00000000:0016 00000000:0000 0A 0:0 0:0 0 0 0 1 1 0 0\n");
  assert(!core.isMpdListening(root + "/tcp_idle", root + "/rt_none"));
  writeText(root + "/tcp_mpd", "  0: 0100007F:19C8 00000000:0000 0A 0:0 0:0 0 0 0 1 1 0 0\n");
  assert(core.isMpdListening(root + "/tcp_mpd", root + "/rt_none"));

  // 6. TOML round-trip
  const QVariantMap vals = {
    {"font.family", QString("JetBrainsMono Nerd Font")},
    {"font.base-size", 15},
    {"effects.animations", false},
    {"launcher.anchor", QString("top")},
    {"launcher.width", 440}
  };
  const QString toml = core.renderShellToml(vals);
  const QVariantMap parsed = core.parseShellToml(toml);
  assert(parsed.value("font.family").toString() == "JetBrainsMono Nerd Font");
  assert(parsed.value("font.base-size").toString() == "15");
  assert(parsed.value("effects.animations").toString() == "false");
  assert(parsed.value("launcher.anchor").toString() == "top");
  assert(parsed.value("launcher.width").toString() == "440");

  // 7. Hyprland overrides round-trip & optional luac -p validation
  const QString luaOut = core.renderHyprOverrides({
    {"gaps_in", 4}, {"gaps_out", 8}, {"border_size", 2}, {"rounding", 6},
    {"active_opacity", 0.98}, {"inactive_opacity", 0.85},
    {"blur_enabled", true}, {"blur_size", 6}, {"blur_passes", 2},
    {"shadow_enabled", false}, {"animations_enabled", true},
    {"follow_mouse", 1}, {"natural_scroll", true}, {"vrr", 2}
  });
  const QVariantMap hyprParsed = core.parseHyprOverrides(luaOut);
  assert(hyprParsed.value("gaps_in").toInt() == 4);
  assert(hyprParsed.value("shadow_enabled").toBool() == false);
  assert(core.writeFileAtomic(root + "/hypr-overrides.lua", luaOut));
  if (!QStandardPaths::findExecutable("luac").isEmpty()) {
    assert(QProcess::execute("luac", {"-p", root + "/hypr-overrides.lua"}) == 0);
  }

  // 8. Atomic file write + theme directory discovery + layout helpers + fonts
  writeText(root + "/themes/iron-man/colors.toml", "foreground=\"#ffffff\"\n");
  writeText(root + "/themes/invalid/notes.txt", "ignore\n");
  const QStringList th = core.listThemes(root + "/themes", root + "/user_themes");
  assert(th.size() == 1 && th.first() == "iron-man");
  assert(!core.monospaceFontFamily().isEmpty());

  QVariantMap layout;
  layout = core.toggleBarWidget(layout, "right", "hyprvibe.audio", true);
  layout = core.toggleBarWidget(layout, "right", "hyprvibe.network", true);
  assert(core.layoutHasWidget(layout, "right", "hyprvibe.audio"));
  layout = core.moveBarWidget(layout, "right", 0, 1);
  assert(layout.value("right").toList().first().toMap().value("id").toString() == "hyprvibe.network");

  // 9. LauncherModel Rofi-style frecency (highest-used always on top + FZF fuzzy) & persistence
  LauncherModel lm;
  lm.setHistoryPath(root + "/launcher-frecency.tsv");
  lm.recordLaunch("qt5ct.desktop");
  lm.recordLaunch("qt5ct.desktop");
  lm.recordLaunch("qt6ct.desktop");
  lm.loadItems({
    QVariantMap{{"label", "Qt Linguist"}, {"actionValue", "linguist.desktop"}, {"keywords", "translation"}},
    QVariantMap{{"label", "Qt5 Settings"}, {"actionValue", "qt5ct.desktop"}, {"keywords", "qt5"}},
    QVariantMap{{"label", "Qt6 Settings"}, {"actionValue", "qt6ct.desktop"}, {"keywords", "qt6"}},
    QVariantMap{{"label", "Zed"}, {"actionValue", "dev.zed.Zed.desktop"}, {"keywords", "editor"}},
    QVariantMap{{"label", "Bottles"}, {"subtext", "Run Windows software"}, {"actionValue", "com.usebottles.bottles.desktop"}, {"keywords", "wine Application Utility"}},
    QVariantMap{{"label", "LocalSend"}, {"subtext", "Share files"}, {"actionValue", "localsend.desktop"}, {"keywords", "network"}},
    QVariantMap{{"label", "System Settings"}, {"actionValue", "systemsettings.desktop"}, {"keywords", "config"}},
    QVariantMap{{"label", "C++ & Qt"}, {"actionValue", "cppqt.desktop"}, {"keywords", "ide"}},
  });
  // Empty query puts highest-used on top (qt5ct=2, qt6ct=1, then alphabetical)
  assert(lm.labelAt(0) == "Qt5 Settings");
  assert(lm.labelAt(1) == "Qt6 Settings");
  lm.setQuery("qt");
  assert(lm.count() == 4);
  assert(lm.labelAt(0) == "Qt5 Settings");
  assert(lm.labelAt(1) == "Qt6 Settings");
  // Query "local" must match LocalSend and NOT scatter-match Bottles across categories/comment
  lm.setHighlightColor("#a63232");
  lm.setQuery("local");
  assert(lm.count() == 1);
  assert(lm.labelAt(0) == "LocalSend");
  assert(lm.data(lm.index(0), LauncherModel::HighlightedLabelRole).toString()
         == QStringLiteral("<b><font color=\"#a63232\">Local</font></b>Send"));
  // Contiguous substring still matches descriptions/keywords
  lm.setQuery("software");
  assert(lm.count() == 1 && lm.labelAt(0) == "Bottles");
  // Optimal word-boundary alignment in "System Settings" highlights "Se", not "S...e"
  lm.setQuery("se");
  assert(lm.count() >= 1);
  for (int i = 0; i < lm.count(); ++i) {
    if (lm.labelAt(i) == "System Settings") {
      assert(lm.data(lm.index(i), LauncherModel::HighlightedLabelRole).toString()
             == QStringLiteral("System <b><font color=\"#a63232\">Se</font></b>ttings"));
    }
  }
  // Safe HTML escaping in StyledText
  lm.setQuery("c");
  for (int i = 0; i < lm.count(); ++i) {
    if (lm.labelAt(i) == "C++ & Qt") {
      assert(lm.data(lm.index(i), LauncherModel::HighlightedLabelRole).toString()
             == QStringLiteral("<b><font color=\"#a63232\">C</font></b>++ &amp; Qt"));
    }
  }
  // Prefix/label match beats description/keyword fuzzy even if another app had launches
  lm.recordLaunch("dev.zed.Zed.desktop");
  lm.recordLaunch("dev.zed.Zed.desktop");
  lm.recordLaunch("dev.zed.Zed.desktop");
  lm.setQuery("lin");
  assert(lm.labelAt(0) == "Qt Linguist");

  LauncherModel lmReloaded;
  lmReloaded.setHistoryPath(root + "/launcher-frecency.tsv");
  lmReloaded.loadItems({
    QVariantMap{{"label", "Qt Linguist"}, {"actionValue", "linguist.desktop"}},
    QVariantMap{{"label", "Qt5 Settings"}, {"actionValue", "qt5ct"}},
  });
  assert(lmReloaded.labelAt(0) == "Qt5 Settings");

  // 10. DBusEngine band mappers & PulseEngine smoke
  assert(DBusEngine::bandForFrequency(2412) == "2.4");
  assert(DBusEngine::bandForFrequency(5180) == "5");
  assert(DBusEngine::bandForFrequency(6115) == "6");
  assert(DBusEngine::bandForFrequency(0).isEmpty());
  assert(DBusEngine::nmBandFromUi("2.4") == "bg");
  assert(DBusEngine::nmBandFromUi("5") == "a");
  assert(DBusEngine::nmBandFromUi("6") == "6GHz");
  assert(DBusEngine::uiBandFromNm("bg") == "2.4");
  assert(DBusEngine::uiBandFromNm("a") == "5");
  assert(DBusEngine::uiBandFromNm("6GHz") == "6");
  assert(DBusEngine::uiBandFromNm("") == "auto");

  // Verify PulseEngine invoke slots exist cleanly in meta-object (regression check against invokeMethod warnings)
  PulseEngine pulse;
  assert(pulse.metaObject()->indexOfMethod("refreshState()") >= 0 || pulse.metaObject()->indexOfSlot("scheduleRefresh()") >= 0);
  assert(pulse.metaObject()->indexOfSlot("applySnapshot(QString,QVariantMap)") >= 0);

  std::printf("hyprvibe-core-tests: ALL ASSERTIONS PASSED\n");
  return 0;
}
