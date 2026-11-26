import QtQuick
import qs.Commons

// Lightweight GPU-translated scanline blip bar divider. Replaces plain "|"
// dividers when enabled by theme or user config, pausing automatically when
// suspended/hidden for zero idle overhead.
Item {
  id: root

  property bool vertical: false
  property bool suspended: false
  property bool animate: Style.effects.animations
  property int intervalMs: Style.effects.barBlipIntervalMs
  property color trackColor: Qt.rgba(ThemeColor.muted.r, ThemeColor.muted.g, ThemeColor.muted.b, 0.28)
  property color blipColor: ThemeColor.accent

  readonly property int trackLength: Style.space(16)
  readonly property int trackThickness: Math.max(2, Style.space(2))
  readonly property int blipSize: Math.max(4, Style.space(5))
  readonly property int maxTravel: Math.max(1, trackLength - blipSize)
  readonly property bool _animActive: visible && animate && !suspended
  readonly property int _legMs: Math.max(500, Math.round(intervalMs * 0.44))
  readonly property int _pauseMs: Math.max(80, Math.round(intervalMs * 0.06))

  implicitWidth: vertical ? trackLength : trackThickness
  implicitHeight: vertical ? trackThickness : trackLength

  Rectangle {
    id: track
    anchors.fill: parent
    radius: root.trackThickness / 2
    color: root.trackColor
    clip: true

    Rectangle {
      id: blip
      width: root.vertical ? root.blipSize : parent.width
      height: root.vertical ? parent.height : root.blipSize
      radius: parent.radius
      color: root.blipColor
      x: root.vertical ? Math.round(root.maxTravel / 2) : 0
      y: root.vertical ? 0 : Math.round(root.maxTravel / 2)

      SequentialAnimation on y {
        running: root._animActive && !root.vertical
        loops: Animation.Infinite
        NumberAnimation {
          from: 0
          to: root.maxTravel
          duration: root._legMs
          easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: root._pauseMs }
        NumberAnimation {
          from: root.maxTravel
          to: 0
          duration: root._legMs
          easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: root._pauseMs }
      }

      SequentialAnimation on x {
        running: root._animActive && root.vertical
        loops: Animation.Infinite
        NumberAnimation {
          from: 0
          to: root.maxTravel
          duration: root._legMs
          easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: root._pauseMs }
        NumberAnimation {
          from: root.maxTravel
          to: 0
          duration: root._legMs
          easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: root._pauseMs }
      }
    }
  }
}
