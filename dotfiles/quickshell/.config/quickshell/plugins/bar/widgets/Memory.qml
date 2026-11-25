import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.memory"

  readonly property string memoryText: Telemetry.memoryText
  readonly property string memoryTooltip: Telemetry.memoryTooltip

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

    onPressed: function() {
      Quickshell.execDetached(["bash", "-c", "${TERMINAL:-foot} -e btop"])
    }
  }
}
