import QtQuick
import qs.Backend.Services
import qs.Frontend.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.powerprofile"

  visible: TelemetryService.powerProfileAvailable
  readonly property string profile: TelemetryService.powerProfile

  readonly property string currentIcon: {
    if (profile === "performance") return "󰓅"
    if (profile === "power-saver") return "󰌪"
    return "󰊚"
  }

  readonly property string currentTooltip: {
    if (profile === "performance") return "Performance"
    if (profile === "power-saver") return "Power Saver"
    if (profile === "balanced") return "Balanced"
    return profile ? (profile.charAt(0).toUpperCase() + profile.slice(1)) : "Power Profile"
  }

  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.currentIcon
    tooltipText: root.currentTooltip
    pressable: false
  }
}
