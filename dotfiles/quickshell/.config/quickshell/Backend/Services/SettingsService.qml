pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import HyprVibeLauncher
import "../Config"

// Central persistence service for the Settings GUI:
// - Writes `~/.config/hyprvibe/shell.toml` atomically via SystemCore.writeFileAtomic
// - Mutates `~/.config/quickshell/user-shell.json` (bar position/autohide/widgets via ShellConfig)
// - Writes `~/.config/hyprvibe/hypr-overrides.lua` atomically & reloads Hyprland
// - Triggers live theme swaps via `hyprvibe-theme set <slug>`
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string userShellPath: home + "/.config/hyprvibe/shell.toml"
  readonly property string hyprOverridesPath: home + "/.config/hyprvibe/hypr-overrides.lua"
  readonly property string currentThemePath: home + "/.local/state/hyprvibe/current/theme.name"
  readonly property string repoThemesDir: Quickshell.env("HYPRVIBE_THEMES_DIR") || (home + "/hyprvibe/themes")
  readonly property string userThemesDir: home + "/.config/hyprvibe/themes"

  property var themes: []
  property string currentTheme: ""
  property var fontFamilies: ["JetBrainsMono Nerd Font", "monospace"]
  property var userShellOverrides: ({})
  property var hyprState: SystemCore.defaultHyprOverrides()

  readonly property var builtInWidgets: [
    { id: "hyprvibe.media", label: "Media", region: "left" },
    { id: "hyprvibe.workspaces", label: "Workspaces", region: "left" },
    { id: "hyprvibe.clock", label: "Clock", region: "center" },
    { id: "hyprvibe.cpu", label: "CPU", region: "right" },
    { id: "hyprvibe.memory", label: "Memory", region: "right" },
    { id: "hyprvibe.audio", label: "Audio", region: "right" },
    { id: "hyprvibe.bluetooth", label: "Bluetooth", region: "right" },
    { id: "hyprvibe.network", label: "Network", region: "right" },
    { id: "hyprvibe.backlight", label: "Backlight", region: "right" },
    { id: "hyprvibe.powerprofile", label: "Power Profile", region: "right" },
    { id: "hyprvibe.power", label: "Battery", region: "right" }
  ]

  function refreshEnvironment() {
    root.themes = SystemCore.listThemes(repoThemesDir, userThemesDir)
    var fonts = SystemCore.listFontFamilies()
    if (fonts && fonts.length > 0) root.fontFamilies = fonts.slice(0, 120)

    var shellRaw = SystemCore.readFileText(root.userShellPath)
    root.userShellOverrides = shellRaw ? SystemCore.parseShellToml(shellRaw) : ({})

    var hyprRaw = SystemCore.readFileText(root.hyprOverridesPath)
    root.hyprState = hyprRaw ? SystemCore.parseHyprOverrides(hyprRaw) : SystemCore.defaultHyprOverrides()

    themeNameFile.reload()
  }

  function effectiveShellStr(keys, fallback) { return ThemeStore.valStr(keys, fallback) }
  function effectiveShellInt(keys, fallback) { return ThemeStore.valInt(keys, fallback) }
  function effectiveShellReal(keys, fallback) { return ThemeStore.valReal(keys, fallback) }
  function effectiveShellBool(keys, fallback) { return ThemeStore.valBool(keys, fallback) }

  function setShellOverride(fullKey, value) {
    var next = Util.cloneJson(userShellOverrides || {})
    if (value === undefined || value === null || String(value).trim() === "") {
      delete next[fullKey]
    } else {
      next[fullKey] = value
    }
    userShellOverrides = next
    ThemeStore.loadUserShell(SystemCore.renderShellToml(next))
    shellWriteTimer.restart()
  }

  function resetShellPrefix(prefix) {
    var next = Util.cloneJson(userShellOverrides || {})
    var p = String(prefix || "")
    for (var k in next) {
      if (k.indexOf(p) === 0) delete next[k]
    }
    userShellOverrides = next
    ThemeStore.loadUserShell(SystemCore.renderShellToml(next))
    shellWriteTimer.restart()
  }

  function resetAllShellOverrides() {
    userShellOverrides = ({})
    ThemeStore.loadUserShell("")
    shellWriteTimer.restart()
  }

  function flushShellToml() {
    SystemCore.ensureDir(home + "/.config/hyprvibe")
    SystemCore.writeFileAtomic(root.userShellPath, SystemCore.renderShellToml(userShellOverrides))
  }

  function setBarField(key, value) {
    ShellConfig.mutateShellConfig(function(cfg) {
      if (!cfg.bar) cfg.bar = {}
      cfg.bar[key] = value
    })
  }

  function hasBarWidget(region, widgetId) {
    var bar = ShellConfig.barConfig
    return SystemCore.layoutHasWidget(bar ? bar.layout : null, region, widgetId)
  }

  function toggleBarWidget(region, widgetId, enabled) {
    ShellConfig.mutateShellConfig(function(cfg) {
      if (!cfg.bar) cfg.bar = {}
      cfg.bar.layout = SystemCore.toggleBarWidget(cfg.bar.layout, region, widgetId, enabled)
    })
  }

  function moveBarWidget(region, fromIndex, toIndex) {
    ShellConfig.mutateShellConfig(function(cfg) {
      if (!cfg.bar) cfg.bar = {}
      cfg.bar.layout = SystemCore.moveBarWidget(cfg.bar.layout, region, fromIndex, toIndex)
    })
  }

  function setClockFormat(fmt) {
    var cleaned = String(fmt || "").trim()
    if (!cleaned) return
    ShellConfig.mutateShellConfig(function(cfg) {
      if (!cfg.bar) cfg.bar = {}
      if (!cfg.bar.layout || !Array.isArray(cfg.bar.layout.center)) return
      for (var i = 0; i < cfg.bar.layout.center.length; i++) {
        var entry = cfg.bar.layout.center[i]
        if (entry && entry.id === "hyprvibe.clock") {
          entry.format = cleaned
        }
      }
    })
  }

  function currentClockFormat() {
    var bar = ShellConfig.barConfig
    var list = bar && bar.layout && Array.isArray(bar.layout.center) ? bar.layout.center : []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === "hyprvibe.clock" && list[i].format) return String(list[i].format)
    }
    return "ddd d MMM h:mm AP"
  }

  function setHyprField(key, value) {
    var next = Util.cloneJson(hyprState || SystemCore.defaultHyprOverrides())
    next[key] = value
    hyprState = next
    hyprWriteTimer.restart()
  }

  function resetHyprOverrides() {
    hyprState = SystemCore.defaultHyprOverrides()
    SystemCore.ensureDir(home + "/.config/hyprvibe")
    SystemCore.writeFileAtomic(root.hyprOverridesPath, "-- Empty HyprVibe user overrides (managed by Settings GUI)\n")
    Quickshell.execDetached(["hyprctl", "reload"])
    Style.scheduleRefresh()
  }

  function flushHyprOverrides() {
    SystemCore.ensureDir(home + "/.config/hyprvibe")
    SystemCore.writeFileAtomic(root.hyprOverridesPath, SystemCore.renderHyprOverrides(hyprState))
    Quickshell.execDetached(["hyprctl", "reload"])
    Style.scheduleRefresh()
  }

  function setTheme(slug) {
    var name = String(slug || "").trim()
    if (!name) return
    Quickshell.execDetached(["hyprvibe-theme", "set", name])
  }

  property Timer shellWriteTimer: Timer {
    interval: 120
    repeat: false
    onTriggered: root.flushShellToml()
  }

  property Timer hyprWriteTimer: Timer {
    interval: 180
    repeat: false
    onTriggered: root.flushHyprOverrides()
  }

  property FileView themeNameFile: FileView {
    path: root.currentThemePath
    watchChanges: true
    printErrors: false
    onLoaded: root.currentTheme = String(text() || "").trim()
    onFileChanged: reload()
  }

  Component.onCompleted: {
    SystemCore.ensureDir(home + "/.config/hyprvibe")
    refreshEnvironment()
  }
}
