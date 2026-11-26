import QtQuick
import qs.Backend.Config
import qs.Frontend.Styles
import qs.Frontend.Ui

// Multi-option pill selector row backed by Frontend.Ui Button.
SettingRow {
  id: root

  property var options: []
  property var currentValue: ""
  signal selectedValue(var value)

  Flow {
    width: Style.space(270)
    layoutDirection: Qt.RightToLeft
    spacing: Style.space(6)

    Repeater {
      model: root.options

      delegate: Button {
        required property var modelData
        readonly property bool isCurrent: modelData.value === root.currentValue

        text: String(modelData.label || modelData.value || "")
        bordered: true
        selected: isCurrent
        active: isCurrent
        foreground: isCurrent ? PanelStyle.accent : PanelStyle.foreground
        fontFamily: PanelStyle.fontFamily
        fontSize: PanelStyle.captionSize
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(4)
        onClicked: root.selectedValue(modelData.value)
      }
    }
  }
}
