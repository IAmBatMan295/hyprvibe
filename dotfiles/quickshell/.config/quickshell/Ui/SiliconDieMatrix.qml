import QtQuick
import qs.Commons

// 2x4 silicon die matrix visualizing normalized RAM capacity usage (0..1).
// Event-driven Grid of 8 crisp cells: zero timers, zero Canvas, 0% idle CPU.
Grid {
  id: root

  property real ratio: 0.0
  property int cellCount: 8
  property bool animate: Style.effects.animations
  property color normalColor: ThemeColor.bar.text
  property color urgentColor: ThemeColor.bar.active
  property color inactiveColor: Qt.rgba(ThemeColor.muted.r, ThemeColor.muted.g, ThemeColor.muted.b, 0.35)

  readonly property real clampedRatio: Math.max(0, Math.min(1, ratio))
  readonly property color activeColor: Style.loadStateColor(clampedRatio, normalColor, urgentColor)
  readonly property int cellSize: Math.max(3, Style.space(4))

  columns: 4
  spacing: Math.max(1, Style.space(2))

  Repeater {
    model: root.cellCount

    Rectangle {
      required property int index
      readonly property bool lit: root.clampedRatio >= ((index + 0.5) / root.cellCount)
      width: root.cellSize
      height: root.cellSize
      radius: 1
      color: lit ? root.activeColor : root.inactiveColor

      Behavior on color {
        enabled: root.animate && root.visible
        ColorAnimation { duration: 220 }
      }
    }
  }
}
