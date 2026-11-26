import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Backend.Config
import qs.Frontend.Styles
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
  property bool viewDynamicHeight: false
  property string viewResultFormat: "s"
  property string viewFontFamily: Style.font.family
  property int viewFontSize: Math.max(10, Style.font.subtitle)
  property int viewBorderWidth: Math.max(3, Style.borderSize + 1)
  property int viewBorderRadius: Style.cornerRadius
  property string viewAnimStyle: "none"
  property int viewAnimMs: 110
  property string viewPrompt: " "
  property string viewHeaderIcon: ""
  property string viewPlaceholder: "Search applications..."
  property int viewWidth: 440
  property int viewLines: 7
  property int viewRowHeight: 46
  property int viewInitialRow: 0
  property bool viewBenchAutoAck: false
  property string viewAnchor: "center"
  property int viewXOffset: 0
  property int viewYOffset: 0
  property int viewMargin: 16

  // Resolved via LauncherStyle + Style/ThemeStore singletons so theme switches & shell.toml edits apply live
  readonly property var palette: LauncherStyle.palette

  function applyPreset(name, overrides) {
    var r = LauncherStyle.resolve(name, overrides)
    root.activePreset = r.presetName
    root.viewPrintOnly = r.printOnly
    root.viewFontFamily = r.fontFamily
    root.viewFontSize = r.fontSize
    root.viewBorderWidth = r.borderWidth
    root.viewBorderRadius = r.borderRadius
    root.viewAnimStyle = r.animStyle
    root.viewAnimMs = r.animMs

    root.viewPrompt = r.prompt
    root.viewHeaderIcon = r.headerIcon
    root.viewPlaceholder = r.placeholder
    root.viewWidth = r.width
    root.viewLines = r.lines
    root.viewRowHeight = r.rowHeight

    root.viewShowSearch = r.showSearch
    root.viewShowNumbers = r.showNumbers
    root.viewShowIcons = r.showIcons
    root.viewShowSubtext = r.showSubtext
    root.viewShowPrompt = r.showPrompt
    root.viewShowFooter = r.showFooter
    root.viewDynamicHeight = r.dynamicHeight
    root.viewCenterText = r.centerText

    root.viewAllowCustomInput = r.allowCustomInput
    root.viewOnlyMatch = r.onlyMatch
    root.viewResultFormat = r.resultFormat
    root.viewBenchAutoAck = r.benchAutoAck

    root.viewAnchor = r.anchor
    root.viewXOffset = r.xOffset
    root.viewYOffset = r.yOffset
    root.viewMargin = r.margin

    cppModel.matchingMode = r.matchingMode
    cppModel.caseSensitive = r.caseSensitive
    cppModel.sortEnabled = r.sortEnabled
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
      var idStem = String(d.id || "").replace(/\.desktop$/i, "")
      apps.push({
        label: d.name || d.id,
        subtext: d.genericName || d.comment || "",
        icon: d.icon || "",
        actionValue: d.id,
        keywords: ((d.keywords ? d.keywords.join(" ") : "") + " " + (d.categories ? d.categories.join(" ") : "") + " " + idStem).trim()
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
    historyPath: root.homeDir + "/.local/state/hyprvibe/launcher-frecency.tsv"
    highlightColor: String(root.palette.accent)

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

  readonly property var activeScreen: {
    var focused = Hyprland.focusedMonitor
    var list = Quickshell.screens || []
    if (focused && focused.name) {
      for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].name === focused.name) return list[i]
      }
    }
    return list.length > 0 ? list[0] : null
  }

  function focusOverlay(): void {
    if (!root.open) return
    launcherView.focusDefault()
    Qt.callLater(function() {
      if (root.open) launcherView.focusDefault()
    })
  }

  PanelWindow {
    id: overlayWin

    readonly property string anc: LauncherStyle.normalizeAnchor(root.viewAnchor)
    readonly property bool ancLeft: anc === "left" || anc === "top-left" || anc === "bottom-left"
    readonly property bool ancRight: anc === "right" || anc === "top-right" || anc === "bottom-right"
    readonly property bool ancTop: anc === "top" || anc === "top-left" || anc === "top-right"
    readonly property bool ancBottom: anc === "bottom" || anc === "bottom-left" || anc === "bottom-right"

    screen: root.activeScreen
    visible: root.open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hyprvibe-launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    onVisibleChanged: {
      if (visible) {
        Qt.callLater(() => {
          launcherView.prepareOpen(true)
          root.focusOverlay()
        })
      }
    }

    onBackingWindowVisibleChanged: if (backingWindowVisible && root.open) root.focusOverlay()

    // Full-screen invisible click/hover catcher prevents follow_mouse focus leak
    // to windows below and enables outside click-to-exit without any dim shadow.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      hoverEnabled: true
      onPressed: {
        if (cppModel.hasActiveIpc()) cppModel.replyIpc("CANCEL\n")
        root.closeAndFree()
      }
    }

    Item {
      id: cardContainer
      width: launcherView.width
      height: launcherView.height
      x: {
        var base = overlayWin.ancLeft
          ? root.viewMargin
          : (overlayWin.ancRight
            ? Math.max(0, overlayWin.width - width - root.viewMargin)
            : (overlayWin.width - width) / 2)
        return Math.round(Math.max(0, Math.min(Math.max(0, overlayWin.width - width), base + root.viewXOffset)))
      }
      y: {
        var base = overlayWin.ancTop
          ? root.viewMargin
          : (overlayWin.ancBottom
            ? Math.max(0, overlayWin.height - height - root.viewMargin)
            : (overlayWin.height - height) / 2)
        return Math.round(Math.max(0, Math.min(Math.max(0, overlayWin.height - height), base + root.viewYOffset)))
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: function(mouse) {
          mouse.accepted = true
          launcherView.focusDefault()
        }
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
        headerIcon: root.viewHeaderIcon
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
            cppModel.recordLaunch(actionValue)
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

        onClearRequested: {
          if (root.activePreset !== "clipboard") return
          if (cppModel.hasActiveIpc()) {
            cppModel.replyIpc("CLEAR\n")
            root.closeAndFree()
          } else {
            Quickshell.execDetached(["sh", "-c", "cliphist wipe && wl-copy --clear"])
            root.closeAndFree()
          }
        }
      }
    }
  }

  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: root.open && !!overlayWin.screen && modelData.name !== overlayWin.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "hyprvibe-launcher-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: {
            if (cppModel.hasActiveIpc()) cppModel.replyIpc("CANCEL\n")
            root.closeAndFree()
          }
        }
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
    target: ThemeStore
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
