import QtQuick
import Quickshell
import qs.Frontend.Styles
import qs.Frontend.Ui

// Static centered date/time label for the bar. No popup panel.
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

  function refresh() {
    displayDate = new Date()
  }

  function isoWeekLiteral(year, month, day) {
    var date = new Date(Date.UTC(year, month, day))
    var weekday = date.getUTCDay() || 7
    date.setUTCDate(date.getUTCDate() + 4 - weekday)
    var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
    var week = Math.ceil(((date.getTime() - yearStart.getTime()) / 86400000 + 1) / 7)
    return (week < 10 ? "0" : "") + week
  }

  function formatted(date) {
    return Qt.formatDateTime(date, activeFormat.replace(/ww/g, isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    fontBold: true
    fontSize: BarStyle.fontSize
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * BarStyle.iconSlot : -1
    horizontalMargin: 8
    verticalPadding: 2
    pressable: false
    interactive: false
    highlightOnHover: false

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: BarStyle.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
