import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Backend.Config
import qs.Frontend.Styles
import qs.Frontend.Ui
import "../../Backend/Models/BarModel.js" as BarModel

Item {
  id: root

  required property WidgetRegistry widgetRegistry

  property var barConfig: ShellConfig.barConfig
  readonly property bool barHidden: ShellConfig.barHidden

  DataGlitchEffect {
    id: barDataGlitch
  }
  readonly property alias dataEffect: barDataGlitch

  Binding {
    target: GlitchBus
    property: "barHidden"
    value: root.barHidden
  }

  property string home: ShellConfig.home
  property var fallbackBarConfig: ShellConfig.builtinShellConfig.bar
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  property bool centerSectionHovered: false
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property int barHoverCount: 0
  readonly property bool barHovered: barHoverCount > 0
  property bool autohide: false
  property bool edgeHovered: false
  property bool barRevealed: true
  property string position: "top"

  property string fontFamily: BarStyle.fontFamily
  property color themeForeground: BarStyle.foreground
  property color transparentForeground: BarStyle.foreground
  property color foreground: themeForeground
  property color barForeground: useTransparentForeground ? transparentForeground : themeForeground
  property bool foregroundAnimationEnabled: true
  property color background: BarStyle.background
  property color urgent: BarStyle.active

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: BarStyle.foregroundFadeMs; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: BarStyle.foregroundFadeMs; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: BarStyle.foregroundFadeMs; easing.type: Easing.InOutCubic } }

  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var clickTargets: []
  property var moduleSlots: []

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: vertical ? BarStyle.sizeVertical : BarStyle.sizeHorizontal

  readonly property bool hasFullscreen: {
    if (Hyprland.focusedWorkspace) {
      return !!(Hyprland.focusedWorkspace.hasFullscreen || Hyprland.focusedWorkspace.hasfullscreen)
    }
    return false
  }

  readonly property color panelSurfaceColor: root.transparent
    ? Util.alpha(root.background, 0.72)
    : (root.background.a < 0.999 ? root.background : Util.alpha(root.background, 0.85))

  Timer {
    id: revealTimer
    interval: 500
    repeat: false
    onTriggered: {
      if (root.edgeHovered && !root.hasFullscreen) {
        autohideTimer.stop()
        root.barRevealed = true
      }
    }
  }

  Timer {
    id: autohideTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (root.autohide && !root.barHovered && !root.edgeHovered) {
        root.barRevealed = false
      }
    }
  }

  function onEdgeEntered() {
    if (root.hasFullscreen) return
    root.edgeHovered = true
    if (!root.barRevealed) revealTimer.restart()
    else autohideTimer.stop()
  }

  function onEdgeExited() {
    root.edgeHovered = false
    revealTimer.stop()
    if (!root.barHovered && root.autohide && root.barRevealed) autohideTimer.restart()
  }

  function onBarEntered() {
    revealTimer.stop()
    autohideTimer.stop()
    root.barRevealed = true
  }

  function onBarLeft() {
    if (!root.barHovered && !root.edgeHovered && root.autohide) autohideTimer.restart()
  }

  function ipcShow() {
    if (root.hasFullscreen) return
    revealTimer.stop()
    autohideTimer.stop()
    root.barRevealed = true
    if (root.autohide) autohideTimer.restart()
  }

  function ipcHide() {
    revealTimer.stop()
    autohideTimer.stop()
    root.barRevealed = false
  }

  function ipcToggle() {
    if (root.hasFullscreen) return
    if (root.barRevealed) ipcHide()
    else ipcShow()
  }

  function setBarHovered(hovered) { barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1)) }
  function setCenterHoverRevealSuppressed(value) { centerHoverRevealSuppressed = !!value }
  function run(command) { if (command) Util.execDetached(command) }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    clickTargets = clickTargets.filter(function(item) { return item !== target })
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    moduleSlots = moduleSlots.filter(function(item) { return item !== slot })
  }

  function targetWindow(target) { return target && target.QsWindow ? target.QsWindow.window : null }
  function targetBelongsToWindow(target, window) { return !!target && !!window && targetWindow(target) === window }
  function slotWindow(slot) { return slot ? (targetWindow(slot.activeItem) || targetWindow(slot)) : null }
  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(id) {
    var item = findPanelWidget(id)
    if (!item || typeof item.open !== "function") return false
    item.open()
    return true
  }

  function hideBarWidget(id) {
    var item = findPanelWidget(id)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function toggleBarWidget(id) {
    var item = findPanelWidget(id)
    if (!item) return false
    if (item.opened === true) item.close()
    else item.open()
    return true
  }

  function isBarWidgetOpen(id) {
    var item = findPanelWidget(id)
    return !!item && item.opened === true
  }

  function normalizePosition(value) { return BarModel.normalizePosition(value) }
  function entrySettings(entry) { return BarModel.entrySettings(entry) }
  function entryId(entry) { return BarModel.entryId(entry) }
  function customModuleType(entry) { return BarModel.customModuleType(entry) }

  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   BarModel.pinTrayToInner(normalized.left,   "left"),
      center: BarModel.pinTrayToInner(normalized.center, "center"),
      right:  BarModel.pinTrayToInner(normalized.right,  "right")
    }
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig
    position = normalizePosition(config.position)
    setRequestedTransparency(config.transparent === true)
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")
    root.autohide = (config.autohide === true)
    if (root.autohide) {
      root.barRevealed = true
      autohideTimer.restart()
    } else {
      autohideTimer.stop()
      root.barRevealed = true
    }

    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false
    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) { currentSlot = slot; break }
    }
    if (!currentSlot) return false
    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false
    var currentIndex = slots.indexOf(currentSlot)
    if (currentIndex < 0) return false
    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false
    nextSlot.activeItem.open()
    return true
  }

  function moduleTargetClickable(target) {
    return target && target.visible !== false && target.opacity !== 0
      && target.interactive !== false && target.pressable !== false
      && target.concealed !== true && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue
      var targetPoint = { x: localX, y: localY }
      try { targetPoint = slot.mapToItem(target, localX, localY) } catch (e) { continue }
      if (targetPoint.x >= 0 && targetPoint.x <= target.width && targetPoint.y >= 0 && targetPoint.y <= target.height)
        return target
    }
    return moduleTargetClickable(slot.activeItem) ? slot.activeItem : null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false
    if (typeof target.triggerPressAt === "function") {
      var mappedX = localX, mappedY = localY
      try {
        var pt = slot.mapToItem(target, localX, localY)
        mappedX = pt.x; mappedY = pt.y
      } catch (e) {}
      target.triggerPressAt(button, mappedX, mappedY)
    } else {
      target.triggerPress(button)
    }
    return true
  }

  function setRequestedTransparency(value) {
    requestedTransparent = value === true
    if (!requestedTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      Qt.callLater(function() { Qt.callLater(function() { root.foregroundAnimationEnabled = true }) })
      return
    }
    transparent = true
  }

  function toggleTransparency() { setRequestedTransparency(!root.requestedTransparent) }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try { point = slot.mapToItem(null, 0, 0) } catch (e) {}
      out.push({
        id: slot.moduleName, section: slot.region,
        x: Math.round(point.x), y: Math.round(point.y),
        width: Math.round(slot.width), height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function showTooltip(target, text) {
    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      clearTooltip()
      return
    }
    if (tooltipTarget === target && tooltipShown) {
      tooltipText = text
      return
    }
    clearTooltip()
    var request = ++tooltipRequest
    pendingTooltipTarget = target
    pendingTooltipText = text
    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) { clearTooltip(); return }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return
    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  Component.onCompleted: applyBarConfig()

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: edgeTriggerWindow
        required property var modelData
        screen: modelData
        visible: root.autohide && !root.hasFullscreen
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "hyprvibe-bar-trigger"
        WlrLayershell.layer: WlrLayer.Top
        anchors { top: true; left: true; right: true }
        implicitWidth: 0
        implicitHeight: 4

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: root.onEdgeEntered()
          onExited: root.onEdgeExited()
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      BarPanel {
        required property var modelData
        screen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    readonly property bool effectivelyHidden: root.barHidden || !root.barRevealed
    readonly property var _hyprMonitor: barWindow.screen ? Hyprland.monitorFor(barWindow.screen) : null
    readonly property bool screenHasFullscreen: {
      var ws = _hyprMonitor ? _hyprMonitor.activeWorkspace : null
      if (ws) return !!(ws.hasFullscreen || ws.hasfullscreen)
      return root.hasFullscreen
    }
    readonly property bool effectsSuspended: barWindow.effectivelyHidden || barWindow.screenHasFullscreen

    visible: !remapGuard.remapping
    exclusionMode: effectivelyHidden ? ExclusionMode.Ignore : ExclusionMode.Auto

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins {
      top: effectivelyHidden && root.position === "top" ? -root.barSize : 0
      bottom: effectivelyHidden && root.position === "bottom" ? -root.barSize : 0
      left: effectivelyHidden && root.position === "left" ? -root.barSize : 0
      right: effectivelyHidden && root.position === "right" ? -root.barSize : 0
      Behavior on top { NumberAnimation { duration: BarStyle.slideAnimMs; easing.type: Easing.OutCubic } }
      Behavior on bottom { NumberAnimation { duration: BarStyle.slideAnimMs; easing.type: Easing.OutCubic } }
      Behavior on left { NumberAnimation { duration: BarStyle.slideAnimMs; easing.type: Easing.OutCubic } }
      Behavior on right { NumberAnimation { duration: BarStyle.slideAnimMs; easing.type: Easing.OutCubic } }
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: root.vertical ? 0 : root.barSize
    color: root.panelSurfaceColor
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "hyprvibe-bar"
    WlrLayershell.layer: WlrLayer.Top

    ComboGlitchEffect {
      anchors.fill: parent
      componentId: "bar"
      sharedDataEffect: root.dataEffect
      useSyncedClock: true
      suspended: barWindow.effectsSuspended

      Loader {
        anchors.fill: parent
        sourceComponent: root.vertical ? verticalBar : horizontalBar

        HoverHandler {
          onHoveredChanged: {
            root.setBarHovered(hovered)
            if (hovered) root.onBarEntered()
            else root.onBarLeft()
          }
          Component.onDestruction: if (hovered) root.setBarHovered(false)
        }
      }
    }

    BarTooltip {
      bar: root
      barWindow: barWindow
    }

    Component {
      id: horizontalBar
      Item {
        anchors.fill: parent
        CenterModules { anchors.fill: parent }
        BarModuleList {
          id: leftModules
          bar: root
          entries: root.layoutEntries("left")
          region: "left"
          anchors.left: parent.left
          anchors.leftMargin: Math.round(Style.windowInnerInset + 1 - leftModules.firstVisibleEdgeInset)
          anchors.verticalCenter: parent.verticalCenter
        }
        BarModuleList {
          id: rightModules
          bar: root
          entries: root.layoutEntries("right")
          region: "right"
          anchors.right: parent.right
          anchors.rightMargin: Math.round(Style.windowInnerInset + 1 - rightModules.lastVisibleEdgeInset)
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    Component {
      id: verticalBar
      Item {
        anchors.fill: parent
        CenterModules { anchors.fill: parent }
        BarModuleList {
          bar: root
          entries: root.layoutEntries("left")
          region: "left"
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
        BarModuleList {
          bar: root
          entries: root.layoutEntries("right")
          region: "right"
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = BarModel.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component CenterModules: Item {
    id: centerRoot
    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: BarModel.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules
      Item {
        anchors.fill: parent
        BarModuleList { visible: !centerRoot.hasAnchor; bar: root; entries: centerRoot.entries; region: "center"; anchors.centerIn: parent }
        BarModuleList { visible: centerRoot.hasAnchor; bar: root; entries: BarModel.entriesBefore(centerRoot.entries, root.centerAnchor); region: "center"; anchors.right: centerAnchorModule.left; anchors.verticalCenter: centerAnchorModule.verticalCenter }
        BarModuleSlot { id: centerAnchorModule; visible: centerRoot.hasAnchor; bar: root; entry: centerRoot.anchorEntry; region: "center"; anchors.centerIn: parent }
        BarModuleList { visible: centerRoot.hasAnchor; bar: root; entries: BarModel.entriesAfter(centerRoot.entries, root.centerAnchor); region: "center"; anchors.left: centerAnchorModule.right; anchors.verticalCenter: centerAnchorModule.verticalCenter }
      }
    }

    Component {
      id: verticalCenterModules
      Item {
        anchors.fill: parent
        BarModuleList { visible: !centerRoot.hasAnchor; bar: root; entries: centerRoot.entries; region: "center"; anchors.centerIn: parent }
        BarModuleList { visible: centerRoot.hasAnchor; bar: root; entries: BarModel.entriesBefore(centerRoot.entries, root.centerAnchor); region: "center"; anchors.bottom: centerAnchorModule.top; anchors.horizontalCenter: centerAnchorModule.horizontalCenter }
        BarModuleSlot { id: centerAnchorModule; visible: centerRoot.hasAnchor; bar: root; entry: centerRoot.anchorEntry; region: "center"; anchors.centerIn: parent }
        BarModuleList { visible: centerRoot.hasAnchor; bar: root; entries: BarModel.entriesAfter(centerRoot.entries, root.centerAnchor); region: "center"; anchors.top: centerAnchorModule.bottom; anchors.horizontalCenter: centerAnchorModule.horizontalCenter }
      }
    }
  }
}
