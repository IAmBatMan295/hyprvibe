import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.powerprofile"

  property string profile: "balanced"

  readonly property string currentIcon: {
    if (profile === "performance") return ""
    if (profile === "power-saver") return "󰌪"
    return ""
  }

  readonly property string currentTooltip: {
    if (profile === "performance") return "Performance"
    if (profile === "power-saver") return "Power Saver"
    if (profile === "balanced") return "Balanced"
    return profile ? (profile.charAt(0).toUpperCase() + profile.slice(1)) : "Power Profile"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // One-time startup fetch
  Process {
    id: initProc
    command: ["powerprofilesctl", "get"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = text.trim()
        if (p) root.profile = p
      }
    }
  }

  // Event-driven DBus signal listener: 0.0% CPU at idle (blocked on epoll)
  Process {
    id: monitorProc
    command: ["gdbus", "monitor", "--system", "--dest", "net.hadess.PowerProfiles"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        var m = line.match(/'ActiveProfile':\s*<'([^']+)'/)
        if (m && m[1]) root.profile = m[1]
      }
    }
    onExited: restartTimer.restart()
  }

  Timer {
    id: restartTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (!monitorProc.running) monitorProc.running = true
    }
  }

  IpcHandler {
    target: "hyprvibe.powerprofile"
    function setProfile(p: string) { if (p) root.profile = p }
    function refresh() { if (!initProc.running) initProc.running = true }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: 14
    text: root.currentIcon
    tooltipText: root.currentTooltip
    pressable: false
  }
}
