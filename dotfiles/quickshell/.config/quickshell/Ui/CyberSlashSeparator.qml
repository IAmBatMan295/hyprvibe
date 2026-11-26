import QtQuick
import qs.Commons

// Thin vertical twin-rail "||" separator glowing with theme accent.
// Pure GPU opacity animation using TOML palette tokens; pauses cleanly when
// suspended or hidden.
Item {
  id: root

  property bool vertical: false
  property bool suspended: false
  property bool animate: Style.effects.animations
  property color accentColor: ThemeColor.accent

  readonly property int railLength: Style.space(12)
  readonly property int railSpacing: Math.max(2, Style.space(2))
  readonly property bool _animActive: visible && animate && !suspended

  implicitWidth: vertical ? railLength : (2 + railSpacing)
  implicitHeight: vertical ? (2 + railSpacing) : railLength

  Grid {
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 2
    spacing: root.railSpacing

    Repeater {
      model: 2

      Rectangle {
        required property int index
        width: root.vertical ? root.railLength : 1
        height: root.vertical ? 1 : root.railLength
        color: root.accentColor
        opacity: 0.45

        SequentialAnimation on opacity {
          running: root._animActive
          loops: Animation.Infinite
          PauseAnimation { duration: index * 480 }
          NumberAnimation { to: 1.0; duration: 480; easing.type: Easing.InOutSine }
          NumberAnimation { to: 0.25; duration: 960; easing.type: Easing.InOutSine }
          PauseAnimation { duration: (1 - index) * 480 + 320 }
        }
      }
    }
  }
}
