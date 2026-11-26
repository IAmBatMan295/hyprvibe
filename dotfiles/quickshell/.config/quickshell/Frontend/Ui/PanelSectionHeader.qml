import QtQuick
import qs.Backend.Config

// Small-caps-style label that introduces a panel section ("DNS provider",
// "Wi-Fi networks", "Output device", "Paired devices"). Exposes font/topPadding
// aliases so adjacent controls can align to glyphs without breaking text bindings.
Item {
  id: root

  property string text: ""
  property color foreground: ThemeStore.foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.caption
  readonly property alias font: label.font
  readonly property alias topPadding: label.topPadding

  implicitWidth: label.implicitWidth
  implicitHeight: label.implicitHeight

  Text {
    id: label
    anchors.fill: parent
    textFormat: Text.PlainText
    text: GlitchBus.panelText(root.text)
    color: Util.alpha(root.foreground, 0.72)
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: true
    // Glyphs can paint above the box Text reserves for them; reserve top overshoot.
    topPadding: Math.ceil(root.fontSize * 0.15)
  }
}
