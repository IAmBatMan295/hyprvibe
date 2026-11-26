import QtQuick
import qs.Backend.Config
import qs.Frontend.Styles

// Standard two-column labeled setting row shared across all Settings sections.
Item {
  id: root

  property string label: ""
  property string hint: ""
  property int controlWidth: 0
  default property alias control: controlSlot.children

  width: parent ? parent.width : Style.space(520)
  implicitHeight: Math.max(labelCol.implicitHeight, controlSlot.implicitHeight) + Style.space(8)

  Column {
    id: labelCol
    anchors.left: parent.left
    anchors.right: controlSlot.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: root.label
      color: PanelStyle.foreground
      font.family: PanelStyle.fontFamily
      font.pixelSize: PanelStyle.bodySize
      font.bold: true
      elide: Text.ElideRight
      width: parent.width
    }

    Text {
      visible: root.hint !== ""
      textFormat: Text.PlainText
      text: root.hint
      color: PanelStyle.mutedText
      font.family: PanelStyle.fontFamily
      font.pixelSize: PanelStyle.captionSize
      wrapMode: Text.WordWrap
      width: parent.width
    }
  }

  Item {
    id: controlSlot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    implicitWidth: root.controlWidth > 0 ? root.controlWidth : childrenRect.width
    implicitHeight: childrenRect.height
  }
}
