import QtQuick
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui
import ".."

// Hyprland compositor overrides written cleanly to ~/.config/hyprvibe/hypr-overrides.lua.
Column {
  id: root

  width: parent ? parent.width : Style.space(540)
  spacing: Style.space(12)

  PanelSectionHeader {
    text: "GAPS, BORDERS & ROUNDING"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingSlider {
    label: "Inner gaps (gaps_in)"
    value: SettingsService.hyprState.gaps_in
    minimum: 0
    maximum: 24
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setHyprField("gaps_in", Math.round(v)) }
  }

  SettingSlider {
    label: "Outer gaps (gaps_out)"
    value: SettingsService.hyprState.gaps_out
    minimum: 0
    maximum: 36
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setHyprField("gaps_out", Math.round(v)) }
  }

  SettingSlider {
    label: "Window border size"
    value: SettingsService.hyprState.border_size
    minimum: 0
    maximum: 8
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setHyprField("border_size", Math.round(v)) }
  }

  SettingSlider {
    label: "Window corner rounding"
    value: SettingsService.hyprState.rounding
    minimum: 0
    maximum: 24
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setHyprField("rounding", Math.round(v)) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  PanelSectionHeader {
    text: "OPACITY, BLUR & SHADOWS"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingSlider {
    label: "Active window opacity"
    value: SettingsService.hyprState.active_opacity
    minimum: 0.60
    maximum: 1.00
    step: 0.02
    displayScale: 100
    integer: true
    suffix: "%"
    onMovedValue: function(v) { SettingsService.setHyprField("active_opacity", Number(v.toFixed(2))) }
  }

  SettingSlider {
    label: "Inactive window opacity"
    value: SettingsService.hyprState.inactive_opacity
    minimum: 0.40
    maximum: 1.00
    step: 0.02
    displayScale: 100
    integer: true
    suffix: "%"
    onMovedValue: function(v) { SettingsService.setHyprField("inactive_opacity", Number(v.toFixed(2))) }
  }

  SettingToggle {
    label: "Compositor blur"
    checked: SettingsService.hyprState.blur_enabled === true
    onToggledValue: function(v) { SettingsService.setHyprField("blur_enabled", v) }
  }

  SettingSlider {
    label: "Blur radius"
    value: SettingsService.hyprState.blur_size
    minimum: 1
    maximum: 16
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setHyprField("blur_size", Math.round(v)) }
  }

  SettingSlider {
    label: "Blur passes"
    value: SettingsService.hyprState.blur_passes
    minimum: 1
    maximum: 5
    step: 1
    integer: true
    onMovedValue: function(v) { SettingsService.setHyprField("blur_passes", Math.round(v)) }
  }

  SettingToggle {
    label: "Window shadows"
    checked: SettingsService.hyprState.shadow_enabled === true
    onToggledValue: function(v) { SettingsService.setHyprField("shadow_enabled", v) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  PanelSectionHeader {
    text: "ANIMATIONS, DISPLAY & INPUT"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingToggle {
    label: "Hyprland animations"
    checked: SettingsService.hyprState.animations_enabled === true
    onToggledValue: function(v) { SettingsService.setHyprField("animations_enabled", v) }
  }

  SettingChoices {
    label: "Variable Refresh Rate (VRR)"
    currentValue: SettingsService.hyprState.vrr
    options: [
      { label: "Off", value: 0 },
      { label: "Always", value: 1 },
      { label: "Fullscreen", value: 2 }
    ]
    onSelectedValue: function(v) { SettingsService.setHyprField("vrr", v) }
  }

  SettingChoices {
    label: "Mouse focus policy"
    currentValue: SettingsService.hyprState.follow_mouse
    options: [
      { label: "Cursor", value: 1 },
      { label: "Click", value: 2 },
      { label: "Disabled", value: 0 }
    ]
    onSelectedValue: function(v) { SettingsService.setHyprField("follow_mouse", v) }
  }

  SettingToggle {
    label: "Touchpad natural scroll"
    checked: SettingsService.hyprState.natural_scroll === true
    onToggledValue: function(v) { SettingsService.setHyprField("natural_scroll", v) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  Row {
    anchors.right: parent.right
    Button {
      text: "Reset Hyprland Overrides"
      bordered: true
      foreground: PanelStyle.urgent
      fontFamily: PanelStyle.fontFamily
      fontSize: PanelStyle.captionSize
      onClicked: SettingsService.resetHyprOverrides()
    }
  }
}
