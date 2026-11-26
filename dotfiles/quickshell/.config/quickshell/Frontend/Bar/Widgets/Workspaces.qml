import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Backend.Config
import qs.Frontend.Styles
import qs.Frontend.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = []
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
    }
    if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0 && ids.indexOf(Hyprland.focusedWorkspace.id) === -1) {
      ids.push(Hyprland.focusedWorkspace.id)
    }
    ids.sort(function(left, right) { return left - right })
    if (ids.length === 0) ids = [1]
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(2)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: modelData === 10 ? "0" : String(modelData)
        fontBold: focused
        foreground: focused ? BarStyle.background : BarStyle.muted
        highlightOnHover: !focused
        opacity: focused ? 1.0 : (occupied ? 0.8 : 0.5)
        horizontalMargin: 6
        verticalPadding: 2
        fontSize: BarStyle.fontSize
        fixedWidth: root.vertical ? root.barSize : -1
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        Rectangle {
          z: -1
          visible: focused
          anchors.fill: parent
          anchors.topMargin: 2
          anchors.bottomMargin: 2
          color: BarStyle.accent
          radius: 0
        }
      }
    }
  }
}
