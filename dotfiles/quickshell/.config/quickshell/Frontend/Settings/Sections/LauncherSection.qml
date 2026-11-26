import QtQuick
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui
import ".."

// Dedicated Launcher stylesheet & behavior controls wired live via LauncherStyle & shell.toml.
Column {
  id: root

  width: parent ? parent.width : Style.space(540)
  spacing: Style.space(12)

  readonly property string currentAnchor: LauncherStyle.normalizeAnchor(
    SettingsService.effectiveShellStr(["launcher.anchor"], "center")
  )

  PanelSectionHeader {
    text: "POSITION & ANCHORING"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingRow {
    label: "Default screen anchor"
    hint: "Applied when no explicit --anchor flag is passed"

    Grid {
      columns: 3
      columnSpacing: Style.space(4)
      rowSpacing: Style.space(4)

      Repeater {
        model: [
          { label: "↖", value: "top-left" },
          { label: "↑", value: "top" },
          { label: "↗", value: "top-right" },
          { label: "←", value: "left" },
          { label: "●", value: "center" },
          { label: "→", value: "right" },
          { label: "↙", value: "bottom-left" },
          { label: "↓", value: "bottom" },
          { label: "↘", value: "bottom-right" }
        ]

        delegate: Button {
          required property var modelData
          readonly property bool isCurrent: modelData.value === root.currentAnchor

          width: Style.space(34)
          text: modelData.label
          bordered: true
          selected: isCurrent
          active: isCurrent
          foreground: isCurrent ? PanelStyle.accent : PanelStyle.foreground
          fontFamily: PanelStyle.fontFamily
          fontSize: PanelStyle.smallSize
          verticalPadding: Style.space(4)
          onClicked: SettingsService.setShellOverride("launcher.anchor", modelData.value)
        }
      }
    }
  }

  SettingSlider {
    label: "Horizontal offset (X)"
    value: SettingsService.effectiveShellInt(["launcher.x-offset"], 0)
    minimum: -200
    maximum: 200
    step: 8
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("launcher.x-offset", Math.round(v)) }
  }

  SettingSlider {
    label: "Vertical offset (Y)"
    value: SettingsService.effectiveShellInt(["launcher.y-offset"], 0)
    minimum: -200
    maximum: 200
    step: 8
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("launcher.y-offset", Math.round(v)) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  PanelSectionHeader {
    text: "MATCHING, ANIMATION & CHROME"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingChoices {
    label: "Matching mode"
    currentValue: SettingsService.effectiveShellStr(["launcher.matching"], "fuzzy")
    options: [
      { label: "Fuzzy", value: "fuzzy" },
      { label: "Prefix", value: "prefix" },
      { label: "Exact", value: "exact" }
    ]
    onSelectedValue: function(v) { SettingsService.setShellOverride("launcher.matching", v) }
  }

  SettingChoices {
    label: "Open animation"
    currentValue: SettingsService.effectiveShellStr(["launcher.animation", "effects.launcher-animation"], "none")
    options: [
      { label: "Instant", value: "none" },
      { label: "Fade", value: "fade" },
      { label: "Pop", value: "pop" }
    ]
    onSelectedValue: function(v) { SettingsService.setShellOverride("launcher.animation", v) }
  }

  SettingToggle {
    label: "Show footer stats"
    hint: "Displays menu title and match count"
    checked: SettingsService.effectiveShellBool(["launcher.show-footer"], true)
    onToggledValue: function(v) { SettingsService.setShellOverride("launcher.show-footer", v) }
  }

  SettingToggle {
    label: "Frecency / score sorting"
    checked: SettingsService.effectiveShellBool(["launcher.sort"], true)
    onToggledValue: function(v) { SettingsService.setShellOverride("launcher.sort", v) }
  }

  SettingFontPicker {
    label: "Launcher font family"
    currentFamily: SettingsService.effectiveShellStr(["launcher.font-family", "font.launcher-family"], Style.font.family)
    overrideKey: "launcher.font-family"
    allowInherit: true
    onPickedFamily: function(f) { SettingsService.setShellOverride("launcher.font-family", f) }
    onClearedOverride: SettingsService.setShellOverride("launcher.font-family", "")
  }

  SettingSlider {
    label: "Launcher font size"
    value: SettingsService.effectiveShellInt(["launcher.font-size"], Style.font.subtitle)
    minimum: 10
    maximum: 22
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("launcher.font-size", Math.round(v)) }
  }

  SettingSlider {
    label: "Card corner radius"
    value: SettingsService.effectiveShellInt(["launcher.border-radius"], Style.cornerRadius)
    minimum: 0
    maximum: 24
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("launcher.border-radius", Math.round(v)) }
  }

  SettingSlider {
    label: "Card border width"
    value: SettingsService.effectiveShellInt(["launcher.border-width"], Math.max(3, Style.borderSize + 1))
    minimum: 0
    maximum: 6
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("launcher.border-width", Math.round(v)) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  Row {
    anchors.right: parent.right
    Button {
      text: "Reset Launcher Overrides"
      bordered: true
      foreground: PanelStyle.urgent
      fontFamily: PanelStyle.fontFamily
      fontSize: PanelStyle.captionSize
      onClicked: SettingsService.resetShellPrefix("launcher.")
    }
  }
}
