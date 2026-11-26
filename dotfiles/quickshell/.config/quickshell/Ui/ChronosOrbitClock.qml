import QtQuick
import qs.Commons

// Dual-contrast bar clock displaying date + breathing 1Hz accent pip + bold time.
// Driven by caller's Minute-precision SystemClock text; only the 5px pip animates
// on GPU and pauses automatically when hidden or suspended.
Item {
  id: root

  property string dateText: ""
  property string timeText: ""
  property string fontFamily: Style.font.family
  property real datePixelSize: Style.font.bodySmall
  property real timePixelSize: Style.font.body
  property color dateColor: ThemeColor.muted
  property color timeColor: ThemeColor.bar.text
  property color accentColor: ThemeColor.accent
  property bool animate: Style.effects.animations
  property bool suspended: false
  property int spacing: Style.space(7)

  readonly property int pipSize: Math.max(4, Style.space(5))
  readonly property bool _pipVisible: dateText !== "" && timeText !== ""
  readonly property bool _animActive: visible && _pipVisible && animate && !suspended

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    spacing: root.spacing

    Text {
      visible: root.dateText !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.dateText
      color: root.dateColor
      font.family: root.fontFamily
      font.pixelSize: root.datePixelSize
      font.bold: false
      renderType: Text.NativeRendering
    }

    Rectangle {
      visible: root._pipVisible
      anchors.verticalCenter: parent.verticalCenter
      width: root.pipSize
      height: root.pipSize
      radius: root.pipSize / 2
      color: root.accentColor
      opacity: 0.72

      SequentialAnimation on opacity {
        running: root._animActive
        loops: Animation.Infinite
        NumberAnimation { from: 0.28; to: 1.0; duration: 500; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1.0; to: 0.28; duration: 500; easing.type: Easing.InOutSine }
      }
    }

    Text {
      visible: root.timeText !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.timeText
      color: root.timeColor
      font.family: root.fontFamily
      font.pixelSize: root.timePixelSize
      font.bold: true
      renderType: Text.NativeRendering
    }
  }
}
