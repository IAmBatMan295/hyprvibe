pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Shared hardware & media telemetry singleton so multi-monitor bar instances
// never spawn duplicate polling processes or crash/spin on missing laptop daemons.
QtObject {
  id: root

  // ----------------------------------------------------------- Backlight
  property bool backlightAvailable: false
  property int backlightPercent: 40
  property int backlightTarget: 40

  property Timer blHoldoffTimer: Timer {
    interval: 800
    repeat: false
    onTriggered: if (root.backlightAvailable && !blProc.running) blProc.running = true
  }

  property Process blProc: Process {
    command: ["sh", "-c", "ls /sys/class/backlight/* >/dev/null 2>&1 && brightnessctl -m info 2>/dev/null || true"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text || "").trim()
        var parts = line ? line.split(",") : []
        if (parts.length >= 4) {
          root.backlightAvailable = true
          var num = parseInt(parts[3].replace("%", ""), 10)
          if (!isNaN(num) && !blHoldoffTimer.running) {
            root.backlightPercent = num
            root.backlightTarget = num
          }
        } else {
          root.backlightAvailable = false
        }
      }
    }
  }

  property Timer blPollTimer: Timer {
    interval: 5000
    repeat: true
    running: root.backlightAvailable
    onTriggered: if (!blHoldoffTimer.running && !blProc.running) blProc.running = true
  }

  function adjustBacklight(delta) {
    if (!backlightAvailable) return
    var step = 1
    var next = Math.max(1, Math.min(100, backlightTarget + (delta > 0 ? step : -step)))
    backlightTarget = next
    backlightPercent = next
    blHoldoffTimer.restart()
    Quickshell.execDetached(["brightnessctl", "set", next + "%"])
  }

  // ----------------------------------------------------------- Power Profile
  property bool powerProfileAvailable: false
  property string powerProfile: "balanced"

  property Process ppInitProc: Process {
    command: ["powerprofilesctl", "get"]
    running: true
    onExited: function(exitCode) {
      if (exitCode !== 0) root.powerProfileAvailable = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p) {
          root.powerProfileAvailable = true
          root.powerProfile = p
        }
      }
    }
  }

  property Process ppMonitorProc: Process {
    command: ["gdbus", "monitor", "--system", "--dest", "net.hadess.PowerProfiles"]
    running: root.powerProfileAvailable
    stdout: SplitParser {
      onRead: function(line) {
        var m = String(line || "").match(/'ActiveProfile':\s*<'([^']+)'/)
        if (m && m[1]) root.powerProfile = m[1]
      }
    }
    onExited: if (root.powerProfileAvailable) ppRestartTimer.restart()
  }

  property Timer ppRestartTimer: Timer {
    interval: 3000
    repeat: false
    onTriggered: if (root.powerProfileAvailable && !ppMonitorProc.running) ppMonitorProc.running = true
  }

  function setPowerProfileName(p) {
    if (p) powerProfile = p
  }

  function refreshPowerProfile() {
    if (!ppInitProc.running) ppInitProc.running = true
  }

  // ----------------------------------------------------------- CPU & Memory
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
  property real _cpuPrevTotal: 0
  property real _cpuPrevIdle: 0

  property Process cpuProc: Process {
    command: [
      "sh", "-c",
      "cur=$(cat /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq 2>/dev/null | awk '{s+=$1; c++} END {if(c>0) printf \"%.3f\\n\", (s/c)/1000000}'); " +
      "if [ -n \"$cur\" ]; then printf 'cur %s\\n' \"$cur\"; " +
      "else awk '/cpu MHz/ {sum+=$4; count++} END {if (count>0) printf \"cur %.3f\\n\", sum/count/1000}' /proc/cpuinfo; fi; " +
      "min=$(cat /sys/devices/system/cpu/cpufreq/policy*/cpuinfo_min_freq /sys/devices/system/cpu/cpufreq/policy*/scaling_min_freq 2>/dev/null | awk 'BEGIN{m=999999999} {if($1>0 && $1<m) m=$1} END {if(m<999999999) printf \"%.3f\\n\", m/1000000}'); " +
      "if [ -n \"$min\" ]; then printf 'min %s\\n' \"$min\"; fi; " +
      "max=$(cat /sys/devices/system/cpu/cpufreq/policy*/cpuinfo_max_freq /sys/devices/system/cpu/cpufreq/policy*/scaling_max_freq 2>/dev/null | awk 'BEGIN{m=0} {if($1>m) m=$1} END {if(m>0) printf \"%.3f\\n\", m/1000000}'); " +
      "if [ -n \"$max\" ]; then printf 'max %s\\n' \"$max\"; fi; " +
      "awk '/^cpu / {printf \"cpu %s %s %s %s %s %s %s %s\\n\", $2, $3, $4, $5, $6, $7, $8, $9; exit}' /proc/stat"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        for (var li = 0; li < lines.length; li++) {
          var line = lines[li].trim()
          if (line.indexOf("cur ") === 0) {
            var curVal = parseFloat(line.substr(4))
            if (isFinite(curVal) && curVal > 0) {
              root.cpuGhz = curVal
              root.cpuFrequency = curVal.toFixed(1) + " GHz"
              if (root.cpuMaxGhz < curVal) root.cpuMaxGhz = curVal
            }
          } else if (line.indexOf("min ") === 0) {
            var minVal = parseFloat(line.substr(4))
            if (isFinite(minVal) && minVal > 0) root.cpuMinGhz = minVal
          } else if (line.indexOf("max ") === 0) {
            var maxVal = parseFloat(line.substr(4))
            if (isFinite(maxVal) && maxVal > 0) root.cpuMaxGhz = maxVal
          } else if (line.indexOf("cpu ") === 0) {
            var parts = line.split(/\s+/)
            var total = 0
            for (var pi = 1; pi <= 8; pi++) total += Number(parts[pi]) || 0
            var idleAll = (Number(parts[4]) || 0) + (Number(parts[5]) || 0)
            if (root._cpuPrevTotal > 0 && total > root._cpuPrevTotal) {
              var diffTotal = total - root._cpuPrevTotal
              var diffIdle = idleAll - root._cpuPrevIdle
              var frac = Math.max(0, Math.min(1, (diffTotal - diffIdle) / diffTotal))
              root.cpuUsageRatio = frac
              root.cpuUsage = Math.round(frac * 100) + "%"
            }
            root._cpuPrevTotal = total
            root._cpuPrevIdle = idleAll
          }
        }
      }
    }
  }

  property Timer cpuPollTimer: Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!cpuProc.running) cpuProc.running = true
  }

  property string memoryText: "— GB"
  property string memoryTooltip: "Memory"
  property real memoryUsedGb: 0.0
  property real memoryTotalGb: 0.0
  readonly property real memoryUsageRatio: memoryTotalGb > 0 ? Math.max(0, Math.min(1, memoryUsedGb / memoryTotalGb)) : 0

  property Process memProc: Process {
    command: [
      "awk",
      "/MemTotal:/ {total=$2} /MemAvailable:/ {avail=$2} /SwapTotal:/ {stotal=$2} /SwapFree:/ {sfree=$2} END {used=(total-avail)/(1024*1024); tot=total/(1024*1024); sused=(stotal-sfree)/(1024*1024); stot=stotal/(1024*1024); printf \"%.3f|%.3f|%.1f GB|Used: %.1fG / %.1fG\\nSwap: %.1fG / %.1fG\\n\", used, tot, used, used, tot, sused, stot}",
      "/proc/meminfo"
    ]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").trim().split("|")
        if (parts.length >= 4) {
          var used = parseFloat(parts[0])
          var tot = parseFloat(parts[1])
          if (isFinite(used) && used >= 0) root.memoryUsedGb = used
          if (isFinite(tot) && tot > 0) root.memoryTotalGb = tot
          root.memoryText = parts[2].trim()
          root.memoryTooltip = parts.slice(3).join("|").trim()
        }
      }
    }
  }

  property Timer memPollTimer: Timer {
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!memProc.running) memProc.running = true
  }

  // ----------------------------------------------------------- Media (MPRIS-first + shared fallback)
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
    onTriggered: if (!rmpcPollProc.running) rmpcPollProc.running = true
  }

  property Timer mediaRefreshTimer: Timer {
    interval: 200
    repeat: false
    onTriggered: {
      if (!root.activeMprisPlayer && !rmpcPollProc.running) rmpcPollProc.running = true
    }
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
