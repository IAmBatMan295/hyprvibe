import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.backlight"

  visible: Telemetry.backlightAvailable
  readonly property int percent: Telemetry.backlightPercent
  readonly property var icons: ["󰃚", "󰃛", "󰃜", "󰃞", "󰃟", "󰃠"]
  readonly property string currentIcon: {
    var p = Math.max(0, Math.min(100, percent))
    var idx = Math.min(icons.length - 1, Math.max(0, Math.floor((p / 100) * (icons.length - 1))))
    return icons[idx]
  }

  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.currentIcon
    tooltipText: "Brightness: " + root.percent + "%"

    onWheelMoved: function(delta) {
      Telemetry.adjustBacklight(delta)
    }

    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        Telemetry.adjustBacklight(1)
      } else if (b === Qt.RightButton) {
        Telemetry.adjustBacklight(-1)
      }
    }
  }
}
