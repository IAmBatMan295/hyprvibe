import QtQuick
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui
import ".."

// Bar layout, position, transparency, autohide, typography, widget styles, and ordering.
Column {
  id: root

  width: parent ? parent.width : Style.space(540)
  spacing: Style.space(12)

  PanelSectionHeader {
    text: "BAR BEHAVIOR & POSITION"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingChoices {
    label: "Bar screen edge"
    currentValue: ShellConfig.barConfig.position || "top"
    options: [
      { label: "Top", value: "top" },
      { label: "Bottom", value: "bottom" },
      { label: "Left", value: "left" },
      { label: "Right", value: "right" }
    ]
    onSelectedValue: function(v) { SettingsService.setBarField("position", v) }
  }

  SettingToggle {
    label: "Autohide bar"
    hint: "Reveal on edge hover or SUPER+W"
    checked: ShellConfig.barConfig.autohide === true
    onToggledValue: function(v) { SettingsService.setBarField("autohide", v) }
  }

  SettingToggle {
    label: "Transparent bar surface"
    hint: "Blend bar into wallpaper instead of opaque fill"
    checked: ShellConfig.barConfig.transparent === true
    onToggledValue: function(v) { SettingsService.setBarField("transparent", v) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  PanelSectionHeader {
    text: "BAR STYLE & SIZING"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingFontPicker {
    label: "Bar font family"
    currentFamily: BarStyle.fontFamily
    overrideKey: "bar.font-family"
    allowInherit: true
    onPickedFamily: function(f) { SettingsService.setShellOverride("bar.font-family", f) }
    onClearedOverride: SettingsService.setShellOverride("bar.font-family", "")
  }

  SettingSlider {
    label: "Bar text size"
    value: SettingsService.effectiveShellInt(["bar.font-size"], Style.font.body)
    minimum: 9
    maximum: 20
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("bar.font-size", Math.round(v)) }
  }

  SettingSlider {
    label: "Horizontal bar height"
    value: SettingsService.effectiveShellInt(["bar.size-horizontal"], 26)
    minimum: 20
    maximum: 44
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("bar.size-horizontal", Math.round(v)) }
  }

  SettingSlider {
    label: "Bar icon size"
    value: SettingsService.effectiveShellInt(["bar.icon-font"], 13)
    minimum: 10
    maximum: 22
    step: 1
    integer: true
    suffix: "px"
    onMovedValue: function(v) { SettingsService.setShellOverride("bar.icon-font", Math.round(v)) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  PanelSectionHeader {
    text: "WIDGET STYLES"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  SettingChoices {
    label: "CPU indicator"
    hint: "Requires Visual effects engine enabled"
    currentValue: SettingsService.effectiveShellStr(["effects.bar-cpu-style"], "text")
    options: [
      { label: "Text", value: "text" },
      { label: "Arc Reactor", value: "arc-reactor" }
    ]
    onSelectedValue: function(v) { SettingsService.setShellOverride("effects.bar-cpu-style", v) }
  }

  SettingChoices {
    label: "RAM indicator"
    hint: "Requires Visual effects engine enabled"
    currentValue: SettingsService.effectiveShellStr(["effects.bar-ram-style"], "text")
    options: [
      { label: "Text", value: "text" },
      { label: "Silicon Die", value: "silicon-die" }
    ]
    onSelectedValue: function(v) { SettingsService.setShellOverride("effects.bar-ram-style", v) }
  }

  SettingChoices {
    label: "Clock format preset"
    currentValue: SettingsService.currentClockFormat()
    options: [
      { label: "Compact", value: "ddd d MMM h:mm AP" },
      { label: "Full Date", value: "dddd  h:mm AP  d MMMM" },
      { label: "24h Time", value: "HH:mm" }
    ]
    onSelectedValue: function(v) { SettingsService.setClockFormat(v) }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  PanelSectionHeader {
    text: "BAR WIDGETS (ENABLE / DISABLE)"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  Repeater {
    model: SettingsService.builtInWidgets

    delegate: SettingToggle {
      required property var modelData
      label: modelData.label
      hint: modelData.region.toUpperCase() + " section  (" + modelData.id + ")"
      checked: SettingsService.hasBarWidget(modelData.region, modelData.id)
      onToggledValue: function(v) { SettingsService.toggleBarWidget(modelData.region, modelData.id, v) }
    }
  }

  PanelSeparator { foreground: PanelStyle.foreground }

  PanelSectionHeader {
    text: "RIGHT SECTION ORDER"
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
  }

  Repeater {
    model: (ShellConfig.barConfig.layout && ShellConfig.barConfig.layout.right) ? ShellConfig.barConfig.layout.right : []

    delegate: Item {
      required property var modelData
      required property int index
      readonly property var arr: (ShellConfig.barConfig.layout && ShellConfig.barConfig.layout.right) ? ShellConfig.barConfig.layout.right : []

      width: root.width
      implicitHeight: Style.space(28)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String((modelData && modelData.id) ? modelData.id : modelData)
        color: PanelStyle.foreground
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.smallSize
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Button {
          text: "↑"
          bordered: true
          enabled: index > 0
          foreground: enabled ? PanelStyle.foreground : PanelStyle.mutedText
          fontFamily: PanelStyle.fontFamily
          fontSize: PanelStyle.captionSize
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(2)
          onClicked: SettingsService.moveBarWidget("right", index, index - 1)
        }

        Button {
          text: "↓"
          bordered: true
          enabled: index < arr.length - 1
          foreground: enabled ? PanelStyle.foreground : PanelStyle.mutedText
          fontFamily: PanelStyle.fontFamily
          fontSize: PanelStyle.captionSize
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(2)
          onClicked: SettingsService.moveBarWidget("right", index, index + 1)
        }
      }
    }
  }
}
