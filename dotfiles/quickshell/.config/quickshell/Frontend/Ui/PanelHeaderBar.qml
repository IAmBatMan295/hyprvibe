import QtQuick
import QtQuick.Layouts
import qs.Backend.Config
import qs.Frontend.Styles

// Compact, Launcher-aligned header bar replacing oversized Omarchy hero blocks across all panels.
// Pairs a tinted accent icon cell, title, and right-aligned action controls.
Rectangle {
  id: root

  property string iconText: ""
  property bool iconDimmed: false
  property string titleText: ""
  default property alias actions: actionRow.data

  width: parent ? parent.width : implicitWidth
  implicitWidth: Style.space(340)
  implicitHeight: Math.max(Style.space(38), titleLabel.implicitHeight + Style.space(16))
  height: implicitHeight
  radius: PanelStyle.cornerRadius
  color: PanelStyle.darkBackground
  border.width: 1
  border.color: PanelStyle.subtleBorder

  RowLayout {
    anchors.fill: parent
    spacing: 0

    Rectangle {
      id: iconCell
      visible: root.iconText !== ""
      Layout.preferredWidth: root.implicitHeight
      Layout.fillHeight: true
      radius: root.radius
      color: PanelStyle.selectionFill

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: GlitchBus.panelGlyph(root.iconText)
        color: PanelStyle.accent
        opacity: root.iconDimmed ? 0.5 : 1.0
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.titleSize
      }

      Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: PanelStyle.subtleBorder
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.leftMargin: Style.space(10)
      Layout.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        id: titleLabel
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: GlitchBus.panelText(root.titleText)
        color: PanelStyle.lightForeground
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.subtitleSize
        font.bold: true
        elide: Text.ElideRight
      }

      RowLayout {
        id: actionRow
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(6)
      }
    }
  }
}
