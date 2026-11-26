import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import HyprVibeLauncher

// Single-process QML + C++ launcher controller hosted directly inside shell.qml's ShellRoot.
// Shares ThemeColor, Style, DesktopEntries, fonts, animations, and GPU/Wayland context cleanly
// with the bar, panels, and future Settings GUI — adding near-zero idle RAM.
Item {
  id: root
  visible: false

  readonly property string homeDir: Quickshell.env("HOME") || "/home/kunjan"
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string socketPath: Quickshell.env("HYPRVIBE_LAUNCHER_SOCKET")
                                       || (root.runtimeDir + "/hyprvibe-launcher.sock")

  property bool open: false
  property string activePreset: "drun"
  property bool viewPrintOnly: false

  property bool viewShowSearch: true
  property bool viewShowNumbers: false
  property bool viewShowIcons: true
  property bool viewShowSubtext: true
  property bool viewShowPrompt: true
  property bool viewShowFooter: true
  property bool viewCenterText: false
  property bool viewAllowCustomInput: false
  property bool viewOnlyMatch: false
  property bool viewDynamicHeight: true
  property string viewResultFormat: "s"
  property string viewFontFamily: Style.font.family
  property int viewFontSize: Math.max(10, Style.font.subtitle)
  property int viewBorderWidth: Math.max(1, Style.borderSize)
  property int viewBorderRadius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
  property string viewAnimStyle: "none"
  property int viewAnimMs: 110
  property string viewPrompt: " "
  property string viewPlaceholder: "Search applications..."
  property int viewWidth: 380
  property int viewLines: 6
  property int viewRowHeight: 42
  property int viewInitialRow: 0
  property bool viewBenchAutoAck: false
  property string viewAnchor: "center"
  property int viewXOffset: 0
  property int viewYOffset: 0
  property int viewMargin: 16

  // Derived seamlessly from ThemeColor & Style singletons so theme switches & shell.toml edits apply live
  readonly property var palette: ({
    background: ThemeColor.popups.background,
    dark_background: Qt.darker(ThemeColor.background, 1.35),
    lighter_background: ThemeColor.menu.selectedBackground,
    accent: ThemeColor.popups.border,
    selection: ThemeColor.menu.selectedBackground.a > 0.01 ? Qt.rgba(
      ThemeColor.accent.r, ThemeColor.accent.g, ThemeColor.accent.b, 0.28
    ) : ThemeColor.selectionFill,
    muted: ThemeColor.muted,
    foreground: ThemeColor.popups.text,
    light_foreground: Qt.lighter(ThemeColor.foreground, 1.18),
    red: ThemeColor.urgent,
    yellow: ThemeColor.accent
  })

  readonly property var anchorAliases: ({
    center: "center", north: "top", top: "top", south: "bottom", bottom: "bottom",
    west: "left", left: "left", east: "right", right: "right",
    northwest: "top-left", "top-left": "top-left",
    northeast: "top-right", "top-right": "top-right",
    southwest: "bottom-left", "bottom-left": "bottom-left",
    southeast: "bottom-right", "bottom-right": "bottom-right"
  })

  readonly property var presets: ({
    drun: {
      prompt: " ", placeholder: "Search applications...",
      width: 380, lines: 6, rowHeight: 42,
      showSearch: true, showNumbers: false, showIcons: true, showSubtext: true,
      showPrompt: true, centerText: false, allowCustom: false, sort: true
    },
    clipboard: {
      prompt: " ", placeholder: "Filter clipboard history...",
      width: 700, lines: 5, rowHeight: 40,
      showSearch: true, showNumbers: true, showIcons: false, showSubtext: false,
      showPrompt: true, centerText: false, allowCustom: false, sort: false
    },
    helpers: {
      prompt: " ", placeholder: "Select helper utility...",
      width: 480, lines: 5, rowHeight: 40,
      showSearch: true, showNumbers: false, showIcons: false, showSubtext: true,
      showPrompt: true, centerText: false, allowCustom: false, sort: true
    },
    power: {
      prompt: "Power", placeholder: "",
      width: 300, lines: 4, rowHeight: 42,
      showSearch: false, showNumbers: false, showIcons: false, showSubtext: false,
      showPrompt: true, centerText: false, allowCustom: false, sort: false
    },
    profiles: {
      prompt: "Profile", placeholder: "",
      width: 320, lines: 3, rowHeight: 42,
      showSearch: false, showNumbers: false, showIcons: false, showSubtext: false,
      showPrompt: true, centerText: false, allowCustom: false, sort: false
    },
    theme: {
      prompt: "Theme", placeholder: "Filter themes...",
      width: 300, lines: 5, rowHeight: 40,
      showSearch: true, showNumbers: false, showIcons: false, showSubtext: false,
      showPrompt: true, centerText: true, allowCustom: false, sort: true
    },
    compact: {
      prompt: "❯", placeholder: "Type to filter...",
      width: 480, lines: 6, rowHeight: 40,
      showSearch: true, showNumbers: false, showIcons: false, showSubtext: false,
      showPrompt: true, centerText: false, allowCustom: true, sort: true
    }
  })

  function normalizeAnchor(a) {
    var key = String(a || "center").toLowerCase().trim()
    return root.anchorAliases[key] || "center"
  }

  function cfgStr(keys, fallback) {
    var vals = ThemeColor.shellValues || ({})
    for (var i = 0; i < keys.length; ++i) {
      var v = vals[keys[i]]
      if (v !== undefined && v !== null && String(v).length > 0) return String(v)
    }
    return fallback
  }

  function cfgInt(keys, fallback) {
    var vals = ThemeColor.shellValues || ({})
    for (var i = 0; i < keys.length; ++i) {
      var v = vals[keys[i]]
      if (v !== undefined) {
        var n = parseInt(String(v), 10)
        if (isFinite(n)) return n
      }
    }
    return fallback
  }

  function cfgBool(keys, fallback) {
    var vals = ThemeColor.shellValues || ({})
    for (var i = 0; i < keys.length; ++i) {
      var v = vals[keys[i]]
      if (v !== undefined) {
        var low = String(v).trim().toLowerCase()
        if (low === "true" || low === "1" || low === "yes") return true
        if (low === "false" || low === "0" || low === "no") return false
      }
    }
    return fallback
  }

  function applyPreset(name, overrides) {
    var cfg = root.presets[name] || root.presets.compact
    var ov = overrides || {}
    var sec = "launcher." + name

    root.activePreset = name
    root.viewPrintOnly = !!ov.printOnly
    root.viewFontFamily = root.cfgStr([sec + ".font-family", "font.launcher-family"], Style.font.family)
    root.viewFontSize = Math.max(8, root.cfgInt([sec + ".font-size", "font.launcher-size"], Style.font.subtitle))
    root.viewBorderWidth = Math.max(0, root.cfgInt([sec + ".border-width", "launcher.border-width"], Math.max(1, Style.borderSize)))
    root.viewBorderRadius = Math.max(0, root.cfgInt([sec + ".border-radius", "launcher.border-radius"], Style.cornerRadius > 0 ? Style.cornerRadius : 8))
    root.viewAnimStyle = Style.effects.animations
                         ? root.cfgStr(["effects.launcher-animation", "launcher.animation"], "none").toLowerCase()
                         : "none"
    root.viewAnimMs = Math.max(0, root.cfgInt(["effects.launcher-animation-ms", "launcher.animation-ms"], 110))

    root.viewPrompt = ov.prompt !== undefined ? ov.prompt : root.cfgStr([sec + ".prompt"], cfg.prompt)
    root.viewPlaceholder = ov.placeholder !== undefined ? ov.placeholder : root.cfgStr([sec + ".placeholder"], cfg.placeholder)
    root.viewWidth = ov.width > 0 ? ov.width : Math.max(180, root.cfgInt([sec + ".width", "launcher.width"], cfg.width))
    root.viewLines = ov.lines > 0 ? ov.lines : Math.max(1, root.cfgInt([sec + ".lines", "launcher.lines"], cfg.lines))
    root.viewRowHeight = Math.max(24, root.cfgInt([sec + ".row-height", "launcher.row-height"], cfg.rowHeight))

    root.viewShowSearch = ov.showSearch !== undefined ? !!ov.showSearch : root.cfgBool([sec + ".show-search"], cfg.showSearch)
    root.viewShowNumbers = ov.showNumbers !== undefined ? !!ov.showNumbers : root.cfgBool([sec + ".show-numbers"], cfg.showNumbers)
    root.viewShowIcons = ov.showIcons !== undefined ? !!ov.showIcons : root.cfgBool([sec + ".show-icons"], cfg.showIcons)
    root.viewShowSubtext = root.cfgBool([sec + ".show-subtext"], cfg.showSubtext)
    root.viewShowPrompt = root.cfgBool([sec + ".show-prompt"], cfg.showPrompt)
    root.viewShowFooter = ov.showFooter !== undefined ? !!ov.showFooter : root.cfgBool([sec + ".show-footer", "launcher.show-footer"], true)
    root.viewDynamicHeight = root.cfgBool([sec + ".dynamic-height", "launcher.dynamic-height"], true)
    root.viewCenterText = ov.align === "center" ? true : (ov.align === "left" ? false : root.cfgBool([sec + ".center-text"], cfg.centerText))

    root.viewAllowCustomInput = !!ov.dmenu || cfg.allowCustom
    root.viewOnlyMatch = !!ov.onlyMatch
    root.viewResultFormat = ov.format !== undefined ? String(ov.format) : "s"
    root.viewBenchAutoAck = !!ov.benchAutoAck

    var defaultAnchor = root.cfgStr([sec + ".anchor", "launcher.anchor"], "center")
    root.viewAnchor = ov.anchor !== undefined ? root.normalizeAnchor(String(ov.anchor)) : root.normalizeAnchor(defaultAnchor)
    root.viewXOffset = ov.xOffset !== undefined ? Number(ov.xOffset) : root.cfgInt([sec + ".x-offset", "launcher.x-offset"], 0)
    root.viewYOffset = ov.yOffset !== undefined ? Number(ov.yOffset) : root.cfgInt([sec + ".y-offset", "launcher.y-offset"], 0)
    root.viewMargin = (ov.margin !== undefined && Number(ov.margin) >= 0) ? Number(ov.margin) : Math.max(0, root.cfgInt([sec + ".margin", "launcher.margin"], 16))

    cppModel.matchingMode = ov.matching !== undefined ? String(ov.matching) : root.cfgStr([sec + ".matching", "launcher.matching"], "fuzzy")
    cppModel.caseSensitive = ov.caseSensitive !== undefined ? !!ov.caseSensitive : root.cfgBool([sec + ".case-sensitive", "launcher.case-sensitive"], false)
    cppModel.sortEnabled = ov.sort !== undefined ? !!ov.sort : root.cfgBool([sec + ".sort", "launcher.sort"], cfg.sort)
  }

  function closeAndFree() {
    root.open = false
    root.viewBenchAutoAck = false
    Qt.callLater(function() {
      if (!root.open && !cppModel.hasActiveIpc()) {
        cppModel.clear()
        gc()
      }
    })
  }

  function loadDesktopEntries(queryStr) {
    var apps = []
    var entries = DesktopEntries.applications.values
    for (var i = 0; i < entries.length; ++i) {
      var d = entries[i]
      if (!d || d.noDisplay) continue
      apps.push({
        label: d.name || d.id,
        subtext: d.genericName || d.comment || "",
        icon: d.icon || "",
        actionValue: d.id,
        keywords: (d.keywords ? d.keywords.join(" ") : "") + " " + (d.categories ? d.categories.join(" ") : "")
      })
    }
    cppModel.loadItems(apps)
    if (queryStr !== undefined && queryStr !== null && String(queryStr).length > 0) {
      cppModel.query = String(queryStr)
    }
    return apps.length
  }

  function launchDesktopEntry(actionValue) {
    var d = DesktopEntries.byId(actionValue)
    if (!d) return
    if (d.runInTerminal && d.command && d.command.length > 0) {
      var term = Quickshell.env("TERMINAL") || "foot"
      Quickshell.execDetached([term, "-e"].concat(d.command))
    } else {
      d.execute()
    }
  }

  function openPreset(name, allowToggle) {
    var target = name || "drun"
    if (allowToggle && root.open && root.activePreset === target && !cppModel.hasActiveIpc()) {
      root.closeAndFree()
      return
    }
    if (cppModel.hasActiveIpc()) cppModel.replyIpc("CANCEL\n")
    root.applyPreset(target, null)
    root.viewInitialRow = 0
    cppModel.query = ""
    if (target === "drun") {
      root.loadDesktopEntries("")
      root.open = true
    } else if (target === "power") {
      cppModel.loadLines(["  Lock", "  Logout", "  Reboot", "  Shutdown"], false, false, "")
      root.open = true
    }
  }

  LauncherModel {
    id: cppModel

    onIpcRequestReceived: req => {
      var preset = req.preset || (req.dmenu ? "compact" : "drun")
      if (req.toggle && root.open && root.activePreset === preset && !req.dmenu) {
        cppModel.replyIpc("CANCEL\n")
        root.closeAndFree()
        return
      }
      root.applyPreset(preset, req)
      if (req.itemCount > 0 || req.dmenu) {
        if (req.selectRow !== undefined && req.selectRow >= 0) {
          root.viewInitialRow = Math.min(Math.max(0, Number(req.selectRow)), Math.max(0, cppModel.count - 1))
        } else {
          root.viewInitialRow = Math.max(0, req.activeRow !== undefined ? req.activeRow : 0)
        }
      } else {
        root.loadDesktopEntries(req.query ? String(req.query) : "")
        root.viewInitialRow = (req.selectRow !== undefined && req.selectRow >= 0)
                              ? Math.min(Number(req.selectRow), Math.max(0, cppModel.count - 1))
                              : 0
      }
      root.open = true
      if (overlayWin.visible) Qt.callLater(() => launcherView.prepareOpen(true))
    }

    onIpcClientCancelled: root.closeAndFree()
  }

  HyprlandFocusGrab {
    id: focusGrab
    active: root.open
    windows: [overlayWin]
    onCleared: {
      if (cppModel.hasActiveIpc()) cppModel.replyIpc("CANCEL\n")
      root.closeAndFree()
    }
  }

  PanelWindow {
    id: overlayWin

    readonly property string anc: root.normalizeAnchor(root.viewAnchor)
    readonly property bool ancLeft: anc === "left" || anc === "top-left" || anc === "bottom-left"
    readonly property bool ancRight: anc === "right" || anc === "top-right" || anc === "bottom-right"
    readonly property bool ancTop: anc === "top" || anc === "top-left" || anc === "top-right"
    readonly property bool ancBottom: anc === "bottom" || anc === "bottom-left" || anc === "bottom-right"

    visible: root.open
    implicitWidth: launcherView.width
    implicitHeight: launcherView.height
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hyprvibe-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
      top: ancTop
      bottom: ancBottom
      left: ancLeft
      right: ancRight
    }

    margins {
      top: (ancTop ? root.viewMargin : 0) + root.viewYOffset
      bottom: (ancBottom ? root.viewMargin : 0) - root.viewYOffset
      left: (ancLeft ? root.viewMargin : 0) + root.viewXOffset
      right: (ancRight ? root.viewMargin : 0) - root.viewXOffset
    }

    onVisibleChanged: {
      if (visible) Qt.callLater(() => launcherView.prepareOpen(true))
    }

    LauncherView {
      id: launcherView
      anchors.centerIn: parent
      model: cppModel
      palette: root.palette
      fontFamily: root.viewFontFamily
      fontBaseSize: root.viewFontSize
      borderWidth: root.viewBorderWidth
      borderRadius: root.viewBorderRadius
      animationStyle: root.viewAnimStyle
      animationDurationMs: root.viewAnimMs
      presetName: root.activePreset
      showSearch: root.viewShowSearch
      showNumbers: root.viewShowNumbers
      showIcons: root.viewShowIcons
      showSubtext: root.viewShowSubtext
      showPrompt: root.viewShowPrompt
      showFooter: root.viewShowFooter
      centerText: root.viewCenterText
      allowCustomInput: root.viewAllowCustomInput
      onlyMatch: root.viewOnlyMatch
      dynamicHeight: root.viewDynamicHeight
      resultFormat: root.viewResultFormat
      promptText: root.viewPrompt
      placeholderText: root.viewPlaceholder
      cardWidth: root.viewWidth
      visibleLines: root.viewLines
      rowHeight: root.viewRowHeight
      initialRow: root.viewInitialRow
      benchAutoAck: root.viewBenchAutoAck

      onViewReadyForBench: {
        if (cppModel.hasActiveIpc()) {
          cppModel.replyIpc("OK\tBENCH_ACK\t" + cppModel.count + "\t" + cppModel.lastFilterUs
                            + "\t" + launcherView.width + "x" + launcherView.height + "\n")
        }
        root.closeAndFree()
      }

      onAccepted: (actionValue, label, rowIndex) => {
        var shouldLaunchApp = (root.activePreset === "drun" && !root.viewPrintOnly)
        if (cppModel.hasActiveIpc()) {
          cppModel.replyIpc("OK\t" + actionValue + "\n")
        }
        if (shouldLaunchApp) {
          root.launchDesktopEntry(actionValue)
        }
        root.closeAndFree()
      }

      onCancelled: {
        if (cppModel.hasActiveIpc()) {
          cppModel.replyIpc("CANCEL\n")
        }
        root.closeAndFree()
      }
    }
  }

  // Coalesces bursts of DesktopEntries startup/package-install signals into a single refresh
  Timer {
    id: drunRefreshTimer
    interval: 60
    repeat: false
    onTriggered: {
      if (root.open && root.activePreset === "drun") {
        root.loadDesktopEntries(cppModel.query)
      }
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      if (root.open && root.activePreset === "drun") {
        drunRefreshTimer.restart()
      }
    }
  }

  Connections {
    target: ThemeColor
    function onShellValuesChanged() {
      if (root.open && !cppModel.hasActiveIpc()) {
        root.applyPreset(root.activePreset, null)
      }
    }
  }

  IpcHandler {
    target: "launcher"

    function ping(): string {
      return "ok"
    }

    function isOpen(): string {
      return root.open ? "true" : "false"
    }

    function drun(): string {
      root.openPreset("drun", false)
      return "ok"
    }

    function open(preset: string): string {
      root.openPreset(preset || "drun", false)
      return "ok"
    }

    function toggle(preset: string): string {
      root.openPreset(preset || "drun", true)
      return "ok"
    }

    function close(): void {
      if (cppModel.hasActiveIpc()) cppModel.replyIpc("CANCEL\n")
      root.closeAndFree()
    }
  }

  Component.onCompleted: {
    cppModel.startIpcServer(root.socketPath)
    void DesktopEntries.applications.values.length
  }
}
