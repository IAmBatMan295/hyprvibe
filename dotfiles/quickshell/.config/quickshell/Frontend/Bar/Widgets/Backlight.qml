import QtQuick
import qs.Backend.Services
import qs.Frontend.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.backlight"

  visible: TelemetryService.backlightAvailable
  readonly property int percent: TelemetryService.backlightPercent
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

    onWheelMoved: function(delta) { TelemetryService.adjustBacklight(delta) }
    onPressed: function(b) {
      if (b === Qt.LeftButton) TelemetryService.adjustBacklight(1)
      else if (b === Qt.RightButton) TelemetryService.adjustBacklight(-1)
    }
  }
}
