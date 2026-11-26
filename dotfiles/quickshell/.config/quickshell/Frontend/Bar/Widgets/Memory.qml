import QtQuick
import Quickshell
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.memory"

  readonly property string memoryText: TelemetryService.memoryText
  readonly property string memoryTooltip: TelemetryService.memoryTooltip
  readonly property bool isSiliconDie: BarStyle.ramStyle === "silicon-die"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component {
    id: siliconDieComponent

    SiliconDieMatrix {
      ratio: TelemetryService.memoryUsageRatio
      normalColor: button.effectiveColor
      urgentColor: button.activeColor
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.memoryText
    tooltipText: root.memoryTooltip
    fontBold: false
    fontSize: BarStyle.fontSize
    horizontalMargin: 8
    verticalPadding: 2
    fixedHeight: root.bar ? root.bar.barSize : BarStyle.sizeHorizontal
    leadingComponent: (root.isSiliconDie && !root.vertical) ? siliconDieComponent : null

    onPressed: function() {
      Quickshell.execDetached(["bash", "-c", "${TERMINAL:-foot} -e btop"])
    }
  }
}
