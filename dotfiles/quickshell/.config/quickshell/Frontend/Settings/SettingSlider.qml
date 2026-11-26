import QtQuick
import qs.Backend.Config
import qs.Frontend.Styles
import qs.Frontend.Ui

// Labeled slider with live numeric readout backed by PanelSlider.
SettingRow {
  id: root

  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  property string suffix: ""
  property real displayScale: 1
  property int decimals: 0

  signal movedValue(real val)

  controlWidth: Style.space(230)

  Row {
    spacing: Style.space(10)

    PanelSlider {
      id: slider
      width: Style.space(170)
      anchors.verticalCenter: parent.verticalCenter
      minimum: root.minimum
      maximum: root.maximum
      step: root.step
      integer: root.integer
      value: root.value
      fillColor: PanelStyle.accent
      knobColor: PanelStyle.foreground
      onMoved: function(v) { root.movedValue(v) }
    }

    Text {
      width: Style.space(50)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: {
        var scaled = slider.liveValue * root.displayScale
        var formatted = root.integer ? String(Math.round(scaled)) : scaled.toFixed(root.decimals)
        return formatted + root.suffix
      }
      color: PanelStyle.mutedText
      font.family: PanelStyle.fontFamily
      font.pixelSize: PanelStyle.captionSize
      font.bold: true
    }
  }
}
