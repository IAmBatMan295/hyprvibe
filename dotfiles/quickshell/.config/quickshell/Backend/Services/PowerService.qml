pragma Singleton
import QtQuick
import Quickshell.Services.UPower
import HyprVibeLauncher

// Shared UPower battery & native sysfs/proc stats service (zero subprocess workers).
QtObject {
  id: root

  property var batteryInfo: ({})
  property var systemInfo: ({})
  property int activeConsumers: 0
  readonly property bool panelOpen: activeConsumers > 0

  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  readonly property real batteryFraction: {
    var device = UPower.displayDevice
    return (device && device.isPresent) ? Math.max(0, Math.min(1, device.percentage)) : 0
  }

  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }

  readonly property bool chargeThresholdActive: {
    var d = UPower.displayDevice
    if (!(d && d.isPresent && !discharging)) return false
    var fraction = batteryFraction
    if (d.state === UPowerDeviceState.Discharging) return false
    if (d.state === UPowerDeviceState.PendingCharge) return true
    if (d.state === UPowerDeviceState.FullyCharged && fraction < 0.99) return true
    if (d.state !== UPowerDeviceState.Charging || fraction >= 0.99) return false
    return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive)
  }

  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  readonly property bool charging: {
    var d = UPower.displayDevice
    return !!(d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle)
  }

  function batteryIcon() {
    var d = UPower.displayDevice
    if (!d || !d.isPresent) return ""
    if (!discharging) {
      if (d.state === UPowerDeviceState.Charging && !chargeThresholdActive && Number(d.percentage || 0) < 0.99) {
        return "󰂄"
      }
      return "󰚥"
    }
    var verticalIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    var pct = Math.max(0, Math.min(1, Number(d.percentage || 0)))
    if (d.state === UPowerDeviceState.FullyCharged || pct >= 0.99) return "󰁹"
    var index = Math.max(0, Math.min(9, Math.floor(pct * 10)))
    return verticalIcons[index]
  }

  function modeLabel() {
    var d = UPower.displayDevice
    if (!d || !d.isPresent) return ""
    if (chargeThresholdActive) return "Threshold"
    if (discharging) return "On battery"
    if (Number(d.percentage || 0) >= 1) return "Fully charged"
    return "Charging"
  }

  function formatRemaining(seconds) {
    var secs = Math.round(Number(seconds || 0))
    if (!isFinite(secs) || secs <= 0) return ""
    var mins = Math.floor(secs / 60)
    if (mins <= 0) return ""
    var h = Math.floor(mins / 60)
    var m = mins % 60
    if (h > 0) return h + "h" + (m > 0 ? (" " + m + "m") : "")
    return m + "m"
  }

  function acquireConsumer() {
    activeConsumers += 1
    refresh()
  }

  function releaseConsumer() {
    activeConsumers = Math.max(0, activeConsumers - 1)
  }

  function refresh() {
    if (!batteryPresent) return
    var d = UPower.displayDevice
    var sys = SystemCore.readBatterySysfs() || {}
    var pct = Math.round(batteryFraction * 100) + "%"
    var secs = discharging ? (d ? d.timeToEmpty : 0) : (d ? d.timeToFull : 0)
    var timeStr = (batteryFlowIdle || sys.chargeIdle) ? "-" : (formatRemaining(secs) || "—")
    var rateStr = sys.rate ? String(sys.rate) : ((d && d.energyRate > 0) ? (d.energyRate.toFixed(1) + "W") : "")
    batteryInfo = {
      percentage: pct,
      state: sys.chargeIdle ? "Holding" : modeLabel(),
      rate: rateStr,
      size: sys.size || "",
      time: timeStr,
      cycles: sys.cycles || "—",
      threshold: sys.threshold || "-"
    }

    var cpu = SystemCore.sampleCpu() || {}
    var mem = SystemCore.readMemory() || {}
    systemInfo = {
      cpu: (cpu.frequency || "—") + (cpu.hasUsage ? ("  " + cpu.usage) : ""),
      memory: mem.text || "— GB"
    }
  }

  property Timer pollTimer: Timer {
    interval: 5000
    running: root.panelOpen
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()
}
