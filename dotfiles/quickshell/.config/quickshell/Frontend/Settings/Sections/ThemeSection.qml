import QtQuick
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui
import ".."

// Theme selection, global font, spacing, corner override, and shader/animation effects.
Column {
  id: root

  width: parent ? parent.width : Style.space(540)
  spacing: Style.space(12)

  PanelSectionHeader {
    text: "ACTIVE THEME"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  Flow {
    width: parent.width
    spacing: Style.space(8)

    Repeater {
      model: SettingsService.themes

      delegate: Button {
        required property string modelData
        readonly property bool isActive: modelData === SettingsService.currentTheme

        text: modelData
        bordered: true
        active: isActive
        selected: isActive
        foreground: isActive ? PanelStyle.accent : PanelStyle.foreground
        fontFamily: PanelStyle.fontFamily
        fontSize: PanelStyle.smallSize
        horizontalPadding: Style.space(12)
        verticalPadding: Style.space(6)
        onClicked: SettingsService.setTheme(modelData)
      }
    }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  PanelSectionHeader {
    text: "GLOBAL TYPOGRAPHY & GEOMETRY"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingFontPicker {
    label: "Global font family"
    hint: "Shared across bar, panels, and launcher unless overridden"
    currentFamily: Style.font.family
    overrideKey: "font.family"
    allowInherit: true
    onPickedFamily: function(f) { SettingsService.setShellOverride("font.family", f) }
    onClearedOverride: SettingsService.setShellOverride("font.family", "")
  }

  SettingSlider {
    label: "Global font size"
    hint: "Scales typography and spacing proportionally"
    value: Style.fontBaseSize
    minimum: 10
    maximum: 20
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("font.base-size", Math.round(v)) }
  }

  SettingSlider {
    label: "Global spacing scale"
    hint: "Multiplier applied to layout gaps and padding"
    value: SettingsService.effectiveShellReal(["spacing.scale"], 1.0)
    minimum: 0.75
    maximum: 1.40
    step: 0.05
    decimals: 2
    suffix: "x"
    onMovedValue: function(v) { SettingsService.setShellOverride("spacing.scale", Number(v.toFixed(2))) }
  }

  SettingSlider {
    label: "Corner radius"
    hint: "-1 follows Hyprland rounding; 0+ overrides all shell surfaces"
    value: SettingsService.effectiveShellInt(["corner.radius"], -1)
    minimum: -1
    maximum: 20
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) {
      var iv = Math.round(v)
      SettingsService.setShellOverride("corner.radius", iv < 0 ? "" : iv)
    }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  PanelSectionHeader {
    text: "EFFECTS & ANIMATIONS"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingToggle {
    label: "UI animations"
    hint: "Smooth bar slide, panel fade, and launcher open transitions"
    checked: Style.effects.animations
    onToggledValue: function(v) { SettingsService.setShellOverride("effects.animations", v) }
  }

  SettingToggle {
    label: "Visual effects engine"
    hint: "Enables styled bar indicators, glitch/blip accents, and CRT scanlines"
    checked: Style.effects.enabled
    onToggledValue: function(v) { SettingsService.setShellOverride("effects.enabled", v) }
  }

  SettingSlider {
    label: "CRT scanline opacity"
    value: Style.effects.crtScanlineAlpha
    minimum: 0.0
    maximum: 0.45
    step: 0.02
    displayScale: 100
    integer: true
    suffix: "%"
    onMovedValue: function(v) { SettingsService.setShellOverride("effects.crt-scanline-alpha", Number(v.toFixed(2))) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  Row {
    anchors.right: parent.right
    spacing: Style.space(8)

    Button {
      text: "Reset Appearance Overrides"
      bordered: true
      foreground: PanelStyle.urgent
      fontFamily: PanelStyle.fontFamily
      fontSize: PanelStyle.captionSize
      onClicked: {
        SettingsService.resetShellPrefix("font.")
        SettingsService.resetShellPrefix("spacing.")
        SettingsService.resetShellPrefix("corner.")
        SettingsService.resetShellPrefix("effects.")
      }
    }
  }
}
