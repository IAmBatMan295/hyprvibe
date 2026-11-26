import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.memory"

  readonly property string memoryText: Telemetry.memoryText
  readonly property string memoryTooltip: Telemetry.memoryTooltip
  readonly property string indicatorStyle: Style.barWidgetStyle("ram", "text")
  readonly property bool isSiliconDie: indicatorStyle === "silicon-die"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component {
    id: siliconDieComponent

    SiliconDieMatrix {
      ratio: Telemetry.memoryUsageRatio
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
    fontSize: Style.font.body
    horizontalMargin: 8
    verticalPadding: 2
    fixedHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal
    leadingComponent: (root.isSiliconDie && !root.vertical) ? siliconDieComponent : null

    onPressed: function() {
      Quickshell.execDetached(["bash", "-c", "${TERMINAL:-foot} -e btop"])
    }
  }
}
