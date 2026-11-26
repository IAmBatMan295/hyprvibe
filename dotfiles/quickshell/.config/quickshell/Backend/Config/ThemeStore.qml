pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import HyprVibeLauncher
import "."
import "BorderGeometry.js" as Geometry

// Central color palette & TOML override store for HyprVibe Quickshell surfaces.
// Merges ~/.local/state/hyprvibe/current/shell.toml (theme base) with
// ~/.config/hyprvibe/shell.toml (persistent user / Settings GUI overrides).
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentThemePath: stateHome + "/hyprvibe/current"

  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"
  property color muted: "#707880"

  property var themeShellValues: ({})
  property var userShellValues: ({})
  property var shellValues: ({})

  function pick(key, fallback) {
    var v = shellValues[key]
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  function pickAlpha(key, fallback) {
    var v = shellValues[key]
    if (typeof v !== "string" || v.length === 0) return fallback
    var n = Number(v)
    return isFinite(n) ? Util.clampAlpha(n) : fallback
  }

  // Typed cascade helpers shared across Style, Frontend.Styles, and Launcher.
  // First matching key in `keys` wins, so callers pass [scopedKey, globalKey, fallbackKey].
  function valStr(keys, fallback) {
    var list = Array.isArray(keys) ? keys : [keys]
    for (var i = 0; i < list.length; ++i) {
      var v = shellValues[list[i]]
      if (v !== undefined && v !== null) {
        var s = String(v).trim()
        if (s.length > 0) return s
      }
    }
    return fallback
  }

  function valInt(keys, fallback) {
    var list = Array.isArray(keys) ? keys : [keys]
    for (var i = 0; i < list.length; ++i) {
      var v = shellValues[list[i]]
      if (v !== undefined) {
        var n = parseInt(String(v), 10)
        if (isFinite(n)) return n
      }
    }
    return fallback
  }

  function valReal(keys, fallback) {
    var list = Array.isArray(keys) ? keys : [keys]
    for (var i = 0; i < list.length; ++i) {
      var v = shellValues[list[i]]
      if (v !== undefined) {
        var n = Number(v)
        if (isFinite(n)) return n
      }
    }
    return fallback
  }

  function valBool(keys, fallback) {
    var list = Array.isArray(keys) ? keys : [keys]
    for (var i = 0; i < list.length; ++i) {
      var v = shellValues[list[i]]
      if (v !== undefined && v !== null) {
        var low = String(v).trim().toLowerCase()
        if (low === "true" || low === "1" || low === "yes" || low === "on") return true
        if (low === "false" || low === "0" || low === "no" || low === "off") return false
      }
    }
    return fallback
  }

  function firstColorToken(value) {
    var parts = String(value || "").replace(/^\s+|\s+$/g, "").split(/\s+/)
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i].match(/^-?\d+(?:\.\d+)?deg$/)) return parts[i]
    }
    return value
  }

  function flatColor(value, fallback) {
    var token = firstColorToken(value)
    var role = String(token || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    if (root.shellValues[role] && root.shellValues[role] !== token) return flatColor(root.shellValues[role], fallback)
    if (role === "foreground" || role === "text") return root.foreground
    if (role === "accent") return root.accent
    if (role === "urgent") return root.urgent
    if (role === "muted") return root.muted
    if (role === "background") return root.background
    if (role === "transparent") return Qt.rgba(0, 0, 0, 0)

    var color = Geometry.canonicalColor(token, 1)
    if (typeof color === "string" && color === token && token.charAt(0) !== "#") return fallback
    return color
  }

  function composed(colorKey, alphaKey, colorFallback, alphaFallback) {
    return Util.alpha(flatColor(pick(colorKey, colorFallback), colorFallback), pickAlpha(alphaKey, alphaFallback))
  }

  function colorFrom(keys, fallbackColor) {
    var list = Array.isArray(keys) ? keys : [keys]
    for (var i = 0; i < list.length; ++i) {
      var v = shellValues[list[i]]
      if (typeof v === "string" && v.trim().length > 0) return flatColor(v, fallbackColor)
    }
    return fallbackColor
  }

  function composedFrom(colorKeys, alphaKeys, fallbackColor, fallbackAlpha) {
    var c = colorFrom(colorKeys, fallbackColor)
    var a = Util.clampAlpha(valReal(alphaKeys, fallbackAlpha))
    return Util.alpha(c, a)
  }

  readonly property QtObject bar: QtObject {
    property color background: root.composed("bar.background", "bar.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("bar.text", root.foreground), root.foreground)
    property color active: root.flatColor(root.pick("bar.active", root.urgent), root.urgent)
  }
  readonly property QtObject popups: QtObject {
    property color background: root.composed("popups.background", "popups.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("popups.text", root.foreground), root.foreground)
    property color border: root.composed("popups.border", "popups.border-alpha", root.accent, 1.0)
  }
  readonly property QtObject tooltip: QtObject {
    property color background: root.composed("tooltip.background", "tooltip.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("tooltip.text", root.foreground), root.foreground)
    property color border: root.composed("tooltip.border", "tooltip.border-alpha", root.foreground, 1.0)
  }
  readonly property QtObject notifications: QtObject {
    property color background: root.composed("notifications.background", "notifications.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("notifications.text", root.foreground), root.foreground)
    property color border: root.composed("notifications.border", "notifications.border-alpha", root.accent, 1.0)
    property color countdown: root.flatColor(root.pick("notifications.countdown", root.accent), root.accent)
  }
  readonly property QtObject menu: QtObject {
    property color background: root.composed("menu.background", "menu.background-alpha", root.background, 1.0)
    property color text: root.flatColor(root.pick("menu.text", root.foreground), root.foreground)
    property color border: root.composed("menu.border", "menu.border-alpha", root.foreground, 1.0)
    property color scrim: root.composed("menu.scrim", "menu.scrim-alpha", root.background, 0.5)
    property color selectedBackground: root.composed("menu.selected-background", "menu.selected-background-alpha", root.foreground, 0.08)
    property color selectedText: root.flatColor(root.pick("menu.selected-text", root.accent), root.accent)
    property color selectedBorder: root.composed("menu.selected-border", "menu.selected-border-alpha", root.foreground, 0.0)
  }

  function loadColors(raw) {
    var lines = String(raw || "").split("\n")
    var foundAccent = false
    var foundMuted = false
    var loadedForeground = false
    var loadedBackground = false
    var color0Value = ""
    var color4Value = ""
    var color7Value = ""
    var color8Value = ""
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (match[1] === "foreground") { foreground = match[2]; loadedForeground = true }
      else if (match[1] === "background") { background = match[2]; loadedBackground = true }
      else if (match[1] === "accent") { accent = match[2]; foundAccent = true }
      else if (match[1] === "muted") { muted = match[2]; foundMuted = true }
      else if (match[1] === "color0") color0Value = match[2]
      else if (match[1] === "color4") color4Value = match[2]
      else if (match[1] === "color7") color7Value = match[2]
      else if (match[1] === "color8") color8Value = match[2]
      else if (match[1] === "red" || match[1] === "color1") urgent = match[2]
    }
    if (!loadedBackground && color0Value.length > 0) background = color0Value
    if (!loadedForeground && color7Value.length > 0) foreground = color7Value
    if (!foundAccent && color4Value.length > 0) accent = color4Value
    if (!foundMuted) muted = color8Value.length > 0 ? color8Value : foreground
  }

  function parseShell(raw) {
    return SystemCore.parseShellToml(String(raw || ""))
  }

  function mergeShell() {
    var merged = {}
    for (var tk in themeShellValues) merged[tk] = themeShellValues[tk]
    for (var uk in userShellValues) merged[uk] = userShellValues[uk]
    shellValues = merged
    Style.applyShellValues(merged)
  }

  function loadShell(raw) {
    themeShellValues = parseShell(raw)
    mergeShell()
  }

  function loadUserShell(raw) {
    userShellValues = parseShell(raw)
    mergeShell()
  }

  property FileView colorsFile: FileView {
    id: colorsFile
    path: root.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadColors(text())
    onFileChanged: reload()
  }
  property FileView shellFile: FileView {
    id: shellFile
    path: root.currentThemePath + "/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadShell(text())
    onFileChanged: reload()
    onLoadFailed: root.loadShell("")
  }
  property FileView userShellFile: FileView {
    id: userShellFile
    path: root.home + "/.config/hyprvibe/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadUserShell(text())
    onFileChanged: reload()
    onLoadFailed: root.loadUserShell("")
  }
}
