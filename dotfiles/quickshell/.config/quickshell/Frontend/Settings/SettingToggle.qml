import QtQuick
import qs.Frontend.Styles
import qs.Frontend.Ui

// Labeled boolean toggle row backed by Frontend.Ui ToggleSwitch.
SettingRow {
  id: root

  property bool checked: false
  signal toggledValue(bool value)

  ToggleSwitch {
    checked: root.checked
    foreground: PanelStyle.foreground
    accent: PanelStyle.accent
    onToggled: root.toggledValue(!root.checked)
  }
}
