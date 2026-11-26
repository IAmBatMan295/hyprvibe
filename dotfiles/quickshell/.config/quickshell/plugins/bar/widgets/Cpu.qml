import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.cpu"

  readonly property string cpuFrequency: Telemetry.cpuFrequency
  readonly property string cpuUsage: Telemetry.cpuUsage
  readonly property string indicatorStyle: Style.barWidgetStyle("cpu", "text")
  readonly property bool isArcReactor: indicatorStyle === "arc-reactor"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component {
    id: arcGaugeComponent

    ArcReactorGauge {
      ratio: Telemetry.cpuSpeedRatio
      speedRatio: Math.max(Telemetry.cpuUsageRatio, Telemetry.cpuSpeedRatio)
      suspended: GlitchBus.suspended || !root.visible
      normalColor: button.effectiveColor
      urgentColor: button.activeColor
      reticleColor: ThemeColor.muted
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.cpuFrequency
    tooltipText: "Usage: " + root.cpuUsage
    fontBold: false
    fontSize: Style.font.body
    horizontalMargin: 8
    verticalPadding: 2
    fixedHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal
    leadingComponent: (root.isArcReactor && !root.vertical) ? arcGaugeComponent : null

    onPressed: function() {
      Quickshell.execDetached(["bash", "-c", "${TERMINAL:-foot} -e btop"])
    }
  }
}
