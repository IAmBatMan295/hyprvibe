pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import HyprVibeLauncher

// Shared hardware & media telemetry singleton across all monitors.
QtObject {
  id: root

  // Backlight
  property bool backlightAvailable: false
  property int backlightPercent: 40
  property int backlightTarget: 40

  function refreshBacklight() {
    var info = SystemCore.readBacklight()
    if (info && info.available) {
      root.backlightAvailable = true
      var num = Number(info.percent)
      if (!isNaN(num) && !blHoldoffTimer.running) {
        root.backlightPercent = num
        root.backlightTarget = num
      }
    } else {
      root.backlightAvailable = false
    }
  }

  property Timer blHoldoffTimer: Timer {
    interval: 800
    repeat: false
    onTriggered: if (root.backlightAvailable) root.refreshBacklight()
  }

  property Timer blPollTimer: Timer {
    interval: 5000
    repeat: true
    running: root.backlightAvailable
    onTriggered: if (!blHoldoffTimer.running) root.refreshBacklight()
  }

  function adjustBacklight(delta) {
    if (!backlightAvailable) return
    var step = 1
    var next = Math.max(1, Math.min(100, backlightTarget + (delta > 0 ? step : -step)))
    backlightTarget = next
    backlightPercent = next
    blHoldoffTimer.restart()
    if (!SystemCore.setBacklightPercent(next)) {
      Quickshell.execDetached(["brightnessctl", "set", next + "%"])
    }
  }

  // Power Profile (native Qt6 DBus binding via SystemCore)
  readonly property bool powerProfileAvailable: SystemCore.powerProfileAvailable
  readonly property string powerProfile: SystemCore.powerProfile

  function setPowerProfileName(p) {
    if (p) SystemCore.setPowerProfile(p)
  }

  function refreshPowerProfile() {
    SystemCore.refreshPowerProfile()
  }

  // CPU & Memory
  property string cpuFrequency: "— GHz"
  property string cpuUsage: "0%"
  property real cpuGhz: 0.0
  property real cpuMinGhz: 0.0
  property real cpuMaxGhz: 0.0
  readonly property real cpuSpeedRatio: {
    if (cpuMaxGhz <= 0) return 0
    if (cpuMinGhz > 0 && cpuMaxGhz > cpuMinGhz + 0.05) {
      return Math.max(0, Math.min(1, (cpuGhz - cpuMinGhz) / (cpuMaxGhz - cpuMinGhz)))
    }
    return Math.max(0, Math.min(1, cpuGhz / cpuMaxGhz))
  }
  property real cpuUsageRatio: 0.0

  function pollCpu() {
    var s = SystemCore.sampleCpu()
    if (!s || !s.valid) return
    var curVal = Number(s.curGhz)
    if (isFinite(curVal) && curVal > 0) {
      root.cpuGhz = curVal
      root.cpuFrequency = s.frequency || (curVal.toFixed(1) + " GHz")
      if (root.cpuMaxGhz < curVal) root.cpuMaxGhz = curVal
    }
    var minVal = Number(s.minGhz)
    if (isFinite(minVal) && minVal > 0) root.cpuMinGhz = minVal
    var maxVal = Number(s.maxGhz)
    if (isFinite(maxVal) && maxVal > 0) root.cpuMaxGhz = maxVal
    if (s.hasUsage) {
      root.cpuUsageRatio = Number(s.usageRatio) || 0
      root.cpuUsage = s.usage || "0%"
    }
  }

  property Timer cpuPollTimer: Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.pollCpu()
  }

  property string memoryText: "— GB"
  property string memoryTooltip: "Memory"
  property real memoryUsedGb: 0.0
  property real memoryTotalGb: 0.0
  readonly property real memoryUsageRatio: memoryTotalGb > 0 ? Math.max(0, Math.min(1, memoryUsedGb / memoryTotalGb)) : 0

  function pollMemory() {
    var m = SystemCore.readMemory()
    if (!m || !m.valid) return
    var used = Number(m.usedGb)
    var tot = Number(m.totalGb)
    if (isFinite(used) && used >= 0) root.memoryUsedGb = used
    if (isFinite(tot) && tot > 0) root.memoryTotalGb = tot
    if (m.text) root.memoryText = m.text
    if (m.tooltip) root.memoryTooltip = m.tooltip
  }

  property Timer memPollTimer: Timer {
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.pollMemory()
  }

  // Media (MPRIS-first + rmpc fallback)
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var activeMprisPlayer: {
    var players = mprisPlayers || []
    for (var i = 0; i < players.length; i++) {
      if (players[i] && players[i].playbackState === MprisPlaybackState.Playing) return players[i]
    }
    for (var j = 0; j < players.length; j++) {
      if (players[j] && (String(players[j].identity || "").toLowerCase().indexOf("mpd") !== -1 || players[j].trackTitle)) return players[j]
    }
    return players.length > 0 ? players[0] : null
  }

  property string _rmpcState: "Pause"
  property string _rmpcTitle: ""
  property string _rmpcArtist: ""
  property string _rmpcFile: ""

  readonly property string playbackState: {
    if (activeMprisPlayer) {
      if (activeMprisPlayer.playbackState === MprisPlaybackState.Playing) return "Play"
      if (activeMprisPlayer.playbackState === MprisPlaybackState.Stopped) return "Stop"
      return "Pause"
    }
    return _rmpcState
  }
  readonly property string songTitle: activeMprisPlayer ? (activeMprisPlayer.trackTitle || _rmpcTitle) : _rmpcTitle
  readonly property string songArtist: activeMprisPlayer ? (activeMprisPlayer.trackArtist || _rmpcArtist) : _rmpcArtist
  readonly property string songFile: _rmpcFile

  property Process rmpcPollProc: Process {
    command: ["bash", "-c", "rmpc status 2>/dev/null; echo '---'; rmpc song 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var str = String(text || "").trim()
        if (!str) { root._rmpcState = "Stop"; return }
        var parts = str.split("---")
        if (parts.length >= 1) {
          try {
            var st = JSON.parse(parts[0].trim())
            if (st && st.state) root._rmpcState = st.state
          } catch (e) { root._rmpcState = "Stop" }
        }
        if (parts.length >= 2) {
          try {
            var sg = JSON.parse(parts[1].trim())
            if (sg) {
              root._rmpcFile = sg.file || ""
              root._rmpcTitle = sg.metadata ? (sg.metadata.title || "") : ""
              root._rmpcArtist = sg.metadata ? (sg.metadata.artist || "") : ""
            }
          } catch (e2) {
            root._rmpcTitle = ""
            root._rmpcArtist = ""
          }
        }
      }
    }
  }

  property Timer mediaPollTimer: Timer {
    interval: root.playbackState === "Play" ? 2000 : 5000
    repeat: true
    running: !root.activeMprisPlayer
    triggeredOnStart: true
    onTriggered: {
      if (SystemCore.isMpdListening()) {
        if (!rmpcPollProc.running) rmpcPollProc.running = true
      } else {
        root._rmpcState = "Stop"
        root._rmpcFile = ""
        root._rmpcTitle = ""
        root._rmpcArtist = ""
      }
    }
  }

  property Timer mediaRefreshTimer: Timer {
    interval: 200
    repeat: false
    onTriggered: {
      if (!root.activeMprisPlayer && SystemCore.isMpdListening() && !rmpcPollProc.running) {
        rmpcPollProc.running = true
      }
    }
  }

  Component.onCompleted: {
    refreshBacklight()
    pollCpu()
    pollMemory()
  }

  function triggerMediaAction(action) {
    if (activeMprisPlayer) {
      if (action === "prev" && activeMprisPlayer.canGoPrevious) { activeMprisPlayer.previous(); return }
      if (action === "next" && activeMprisPlayer.canGoNext) { activeMprisPlayer.next(); return }
      if (action === "toggle" && activeMprisPlayer.canTogglePlaying) { activeMprisPlayer.togglePlaying(); return }
    }
    if (action === "prev") Quickshell.execDetached(["rmpc", "prev"])
    else if (action === "toggle") Quickshell.execDetached(["rmpc", "togglepause"])
    else if (action === "next") Quickshell.execDetached(["rmpc", "next"])
    mediaRefreshTimer.restart()
  }
}
