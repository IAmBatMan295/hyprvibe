import QtQuick
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui
import ".."

// Shared stylesheet settings applying uniformly across Audio, Bluetooth, Network, and Power popups.
Column {
  id: root

  width: parent ? parent.width : Style.space(540)
  spacing: Style.space(12)

  PanelSectionHeader {
    text: "SHARED PANELS STYLE"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  Text {
    width: parent.width
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "Changes apply live across Audio, Bluetooth, Network, and Battery popup panels."
    color: PanelStyle.mutedText
    font.family: PanelStyle.fontFamily
    font.pixelSize: PanelStyle.captionSize
  }

  SettingFontPicker {
    label: "Panels font family"
    currentFamily: PanelStyle.fontFamily
    overrideKey: "panels.font-family"
    allowInherit: true
    onPickedFamily: function(f) { SettingsService.setShellOverride("panels.font-family", f) }
    onClearedOverride: SettingsService.setShellOverride("panels.font-family", "")
  }

  SettingSlider {
    label: "Header title size"
    value: PanelStyle.titleSize
    minimum: 11
    maximum: 24
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("panels.title-size", Math.round(v)) }
  }

  SettingSlider {
    label: "Body & row text size"
    value: PanelStyle.bodySize
    minimum: 10
    maximum: 20
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("panels.body-size", Math.round(v)) }
  }

  SettingSlider {
    label: "Background opacity"
    value: SettingsService.effectiveShellReal(["panels.background-alpha", "popups.background-alpha"], 0.85)
    minimum: 0.40
    maximum: 1.0
    step: 0.02
    displayScale: 100
    integer: true
    suffix: "%"
    onMovedValue: function(v) { SettingsService.setShellOverride("panels.background-alpha", Number(v.toFixed(2))) }
  }

  SettingSlider {
    label: "Panel corner radius"
    value: PanelStyle.cornerRadius
    minimum: 0
    maximum: 24
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("panels.border-radius", Math.round(v)) }
  }

  SettingSlider {
    label: "Inner padding"
    value: PanelStyle.padding
    minimum: 6
    maximum: 28
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("panels.padding", Math.round(v)) }
  }

  SettingSlider {
    label: "Max scroll viewport height"
    value: PanelStyle.maxContentHeight
    minimum: 320
    maximum: 820
    step: 20
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("panels.max-height", Math.round(v)) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  Row {
    anchors.right: parent.right
    Button {
      text: "Reset Panels Style"
      bordered: true
      foreground: PanelStyle.urgent
      fontFamily: PanelStyle.fontFamily
      fontSize: PanelStyle.captionSize
      onClicked: SettingsService.resetShellPrefix("panels.")
    }
  }
}
