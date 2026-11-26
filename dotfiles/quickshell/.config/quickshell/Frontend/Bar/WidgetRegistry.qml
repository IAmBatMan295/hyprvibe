import QtQuick
import "Widgets" as BarWidgets
import "../Panels" as Panels

// Static synchronous component catalogue replacing the legacy manifest-scan PluginRegistry.
// All built-in bar widgets and panel triggers remain toggleable and reorderable via shell.json.
QtObject {
  id: root

  readonly property Component compAudio:        Component { Panels.AudioPanel {} }
  readonly property Component compBacklight:    Component { BarWidgets.Backlight {} }
  readonly property Component compBluetooth:    Component { Panels.BluetoothPanel {} }
  readonly property Component compClock:        Component { BarWidgets.Clock {} }
  readonly property Component compCpu:          Component { BarWidgets.Cpu {} }
  readonly property Component compMedia:        Component { BarWidgets.Media {} }
  readonly property Component compMemory:       Component { BarWidgets.Memory {} }
  readonly property Component compNetwork:      Component { Panels.NetworkPanel {} }
  readonly property Component compPower:        Component { Panels.PowerPanel {} }
  readonly property Component compPowerProfile: Component { BarWidgets.PowerProfile {} }
  readonly property Component compWorkspaces:   Component { BarWidgets.Workspaces {} }

  function componentFor(id) {
    switch (String(id || "")) {
      case "hyprvibe.audio":        return compAudio
      case "hyprvibe.backlight":    return compBacklight
      case "hyprvibe.bluetooth":    return compBluetooth
      case "hyprvibe.clock":        return compClock
      case "hyprvibe.cpu":          return compCpu
      case "hyprvibe.media":        return compMedia
      case "hyprvibe.memory":       return compMemory
      case "hyprvibe.network":      return compNetwork
      case "hyprvibe.power":        return compPower
      case "hyprvibe.powerprofile": return compPowerProfile
      case "hyprvibe.workspaces":   return compWorkspaces
      default:                      return null
    }
  }
}
