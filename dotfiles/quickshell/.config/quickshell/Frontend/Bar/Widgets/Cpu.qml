import QtQuick
import Quickshell
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.cpu"

  readonly property string cpuFrequency: TelemetryService.cpuFrequency
  readonly property string cpuUsage: TelemetryService.cpuUsage
  readonly property bool isArcReactor: BarStyle.cpuStyle === "arc-reactor"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component {
    id: arcGaugeComponent

    ArcReactorGauge {
      ratio: TelemetryService.cpuSpeedRatio
      speedRatio: Math.max(TelemetryService.cpuUsageRatio, TelemetryService.cpuSpeedRatio)
      suspended: GlitchBus.suspended || !root.visible
      normalColor: button.effectiveColor
      urgentColor: button.activeColor
      reticleColor: BarStyle.muted
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.cpuFrequency
    tooltipText: "Usage: " + root.cpuUsage
    fontBold: false
    fontSize: BarStyle.fontSize
    horizontalMargin: 8
    verticalPadding: 2
    fixedHeight: root.bar ? root.bar.barSize : BarStyle.sizeHorizontal
    leadingComponent: (root.isArcReactor && !root.vertical) ? arcGaugeComponent : null

    onPressed: function() {
      Quickshell.execDetached(["bash", "-c", "${TERMINAL:-foot} -e btop"])
    }
  }
}
