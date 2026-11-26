import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Date/time label for the bar. No popup panel, clicks are no-op.
BarWidget {
  id: root
  moduleName: "hyprvibe.clock"

  property date displayDate: clock.date

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "ddd d MMM h:mm AP")

  readonly property string activeFormat: configuredFormat
  readonly property string displayText: formatted(displayDate)
  readonly property var verticalLines: displayText.split("\n")
  readonly property string clockStyle: Style.barWidgetStyle("clock", "text")
  readonly property bool isChronosPip: clockStyle === "chronos-pip"
  readonly property var splitParts: {
    var raw = String(displayText || "")
    var m = raw.match(/^(.*?)\s+(\d{1,2}:\d{2}.*)$/)
    if (m) return { date: m[1], time: m[2] }
    return { date: "", time: raw }
  }

  function scrambledText(s) {
    return (root.bar && root.bar.dataEffect && root.bar.dataEffect.active)
      ? root.bar.dataEffect.scrambleText(s)
      : s
  }

  function refresh() {
    displayDate = new Date()
  }

  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  IpcHandler {
    target: "hyprvibe.clock"

    function refresh() { root.refresh() }
  }

  Component {
    id: chronosComponent

    ChronosOrbitClock {
      dateText: root.scrambledText(root.splitParts.date)
      timeText: root.scrambledText(root.splitParts.time)
      fontFamily: button.fontFamily
      datePixelSize: Style.font.bodySmall
      timePixelSize: Style.font.body
      dateColor: ThemeColor.muted
      timeColor: button.effectiveColor
      accentColor: ThemeColor.accent
      suspended: GlitchBus.suspended || !root.visible
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical && !root.isChronosPip
    fontBold: true
    fontSize: Style.font.body
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedWidth: (!root.vertical && root.isChronosPip && chronosLoader.item)
      ? Math.ceil(chronosLoader.item.implicitWidth + button.scaledHorizontalMargin * 2)
      : -1
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    contentVisualWidth: (!root.vertical && root.isChronosPip && chronosLoader.item)
      ? chronosLoader.item.implicitWidth
      : button.labelWidth
    horizontalMargin: 8
    verticalPadding: 2
    pressable: false
    interactive: false
    highlightOnHover: false

    Loader {
      id: chronosLoader
      anchors.centerIn: parent
      active: !root.vertical && root.isChronosPip
      sourceComponent: chronosComponent
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3
            ? button.fontSize * 0.9
            : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
