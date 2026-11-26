pragma Singleton
import QtQuick
import Quickshell.Hyprland
import qs.Backend.Config

// Shared coordinator for synchronized glitch bursts (`5000ms` single master clock),
// panel Data glitch (Effect 4), and generalized Hyprland fullscreen cost-saving.
QtObject {
  id: root

  signal burstTriggered()

  property int openPopupCount: 0
  property bool barHidden: false

  readonly property bool popupsEnabled: Style.componentHasEffect("popups", "data")
  readonly property bool barClockEnabled: Style.componentGlitchMode("bar") !== "none"
  readonly property int intervalMs: Style.effects.glitchIntervalMs
  readonly property int burstMs: Style.effects.glitchBurstMs

  // Generalized Hyprland fullscreen detection across active outputs / focused workspace
  readonly property bool hyprFullscreen: {
    if (Hyprland.focusedWorkspace && (Hyprland.focusedWorkspace.hasFullscreen || Hyprland.focusedWorkspace.hasfullscreen)) {
      return true
    }
    var mons = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < mons.length; i++) {
      var ws = mons[i] ? mons[i].activeWorkspace : null
      if (ws && (ws.hasFullscreen || ws.hasfullscreen)) return true
    }
    return false
  }

  readonly property bool allMonitorsFullscreen: {
    var mons = Hyprland.monitors ? Hyprland.monitors.values : []
    if (!mons || mons.length === 0) return hyprFullscreen
    for (var i = 0; i < mons.length; i++) {
      var ws = mons[i] ? mons[i].activeWorkspace : null
      if (!ws || !(ws.hasFullscreen || ws.hasfullscreen)) return false
    }
    return true
  }

  // Suspend global master clock when effects disabled, all outputs fullscreen, or bar hidden with no open popups
  readonly property bool suspended: !Style.effects.enabled
    || !Style.effects.animations
    || allMonitorsFullscreen
    || (barHidden && openPopupCount === 0)

  readonly property bool _needsSyncedClock: !suspended && (
    (!barHidden && barClockEnabled) || (openPopupCount > 0 && popupsEnabled)
  )

  property DataGlitchEffect popupsData: DataGlitchEffect {}

  onSuspendedChanged: if (suspended) popupsData.reset()
  onAllMonitorsFullscreenChanged: if (allMonitorsFullscreen) popupsData.reset()

  function fireSyncedBurst() {
    if (suspended) return
    if (openPopupCount > 0 && popupsEnabled && !hyprFullscreen) {
      popupsData.fire(burstMs)
    }
    root.burstTriggered()
  }

  function registerPopupOpen() {
    openPopupCount += 1
    if (popupsEnabled && !suspended && !hyprFullscreen) {
      popupsData.fire(burstMs)
    }
  }

  function unregisterPopupOpen() {
    if (openPopupCount > 0) openPopupCount -= 1
    if (openPopupCount === 0) popupsData.reset()
  }

  function panelText(orig) {
    return (popupsEnabled && !suspended && popupsData.active) ? popupsData.scrambleText(orig) : orig
  }

  function panelGlyph(orig) {
    return (popupsEnabled && !suspended && popupsData.active) ? popupsData.scrambleGlyph(orig) : orig
  }

  property Timer _syncedBurstTimer: Timer {
    id: syncedBurstTimer
    interval: Math.max(500, root.intervalMs)
    repeat: true
    running: root._needsSyncedClock
    onTriggered: root.fireSyncedBurst()
  }

  property Connections _hyprEvents: Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event) return
      if (event.name === "fullscreen" || event.name === "fullscreenv2"
          || event.name === "workspace" || event.name === "focusedmon") {
        Hyprland.refreshWorkspaces()
      }
    }
  }
}
