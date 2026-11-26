import QtQuick
import QtQuick.Controls
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui

// Compact expandable font family picker with search filter and Inherit Global reset.
Column {
  id: root

  property string label: "Font family"
  property string hint: ""
  property string currentFamily: ""
  property string overrideKey: ""
  property bool allowInherit: false
  property bool expanded: false

  signal pickedFamily(string family)
  signal clearedOverride()

  width: parent ? parent.width : Style.space(520)
  spacing: Style.space(8)

  SettingRow {
    label: root.label
    hint: root.hint

    Row {
      spacing: Style.space(6)

      Button {
        visible: root.allowInherit && root.overrideKey !== ""
          && !!SettingsService.userShellOverrides[root.overrideKey]
        text: "Reset"
        bordered: true
        foreground: PanelStyle.mutedText
        fontFamily: PanelStyle.fontFamily
        fontSize: PanelStyle.captionSize
        horizontalPadding: Style.space(8)
        verticalPadding: Style.space(4)
        onClicked: root.clearedOverride()
      }

      Button {
        text: (root.currentFamily || "System Default") + (root.expanded ? "  ▴" : "  ▾")
        bordered: true
        active: root.expanded
        foreground: PanelStyle.foreground
        fontFamily: PanelStyle.fontFamily
        fontSize: PanelStyle.captionSize
        horizontalPadding: Style.space(10)
        verticalPadding: Style.space(4)
        onClicked: root.expanded = !root.expanded
      }
    }
  }

  BorderSurface {
    visible: root.expanded
    width: parent.width
    height: visible ? Style.space(170) : 0
    color: Style.normalFillFor(PanelStyle.foreground)
    borderSpec: Border.controlSpec("normal", PanelStyle.foreground, PanelStyle.accent)
    radius: PanelStyle.cornerRadius
    padding: Style.space(8)

    Column {
      anchors.fill: parent
      spacing: Style.space(6)

      TextField {
        id: filterField
        width: parent.width
        placeholderText: "Filter installed fonts..."
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.smallSize
        foreground: PanelStyle.foreground
        verticalPadding: Style.space(4)
      }

      ListView {
        id: fontList
        width: parent.width
        height: parent.height - filterField.height - Style.space(6)
        clip: true
        spacing: Style.space(3)
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: PanelScrollBar {}

        model: {
          var q = filterField.text.trim().toLowerCase()
          var all = SettingsService.fontFamilies || []
          if (!q) return all
          var out = []
          for (var i = 0; i < all.length; i++) {
            if (all[i].toLowerCase().indexOf(q) >= 0) out.push(all[i])
          }
          return out
        }

        delegate: Button {
          required property string modelData
          width: fontList.width - Style.space(10)
          leftAlign: true
          text: modelData
          selected: modelData === root.currentFamily
          foreground: selected ? PanelStyle.accent : PanelStyle.foreground
          fontFamily: modelData
          fontSize: PanelStyle.smallSize
          verticalPadding: Style.space(4)
          onClicked: {
            root.pickedFamily(modelData)
            root.expanded = false
          }
        }
      }
    }
  }
}
