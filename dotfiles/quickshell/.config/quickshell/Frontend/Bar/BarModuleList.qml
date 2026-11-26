import QtQuick

// Horizontal or vertical strip of BarModuleSlots for one region (left / center / right).
Loader {
  id: moduleListRoot

  required property QtObject bar
  property var entries: []
  property string region: ""

  function edgeInsetForEdge(fromEnd) {
    if (!item) return 0
    var children = item.children
    var start = fromEnd ? children.length - 1 : 0
    var step = fromEnd ? -1 : 1
    for (var i = start; fromEnd ? (i >= 0) : (i < children.length); i += step) {
      var slot = children[i]
      if (!slot || slot.moduleName === undefined || !slot.visible || slot.width <= 0) continue
      var active = slot.activeItem
      if (!active || active.visible === false || active.opacity === 0) continue
      return ("barEdgeInset" in active) ? (Number(active.barEdgeInset) || 0) : 0
    }
    return 0
  }

  readonly property real firstVisibleEdgeInset: edgeInsetForEdge(false)
  readonly property real lastVisibleEdgeInset: edgeInsetForEdge(true)

  visible: entries.length > 0
  active: visible && entries.length > 0
  sourceComponent: bar.vertical ? verticalModuleList : horizontalModuleList
  width: item ? item.implicitWidth : 0
  height: item ? item.implicitHeight : 0

  Component {
    id: horizontalModuleList
    Row {
      spacing: 0
      Repeater {
        model: moduleListRoot.entries
        BarModuleSlot { required property var modelData; bar: moduleListRoot.bar; entry: modelData; region: moduleListRoot.region }
      }
    }
  }

  Component {
    id: verticalModuleList
    Column {
      spacing: 0
      Repeater {
        model: moduleListRoot.entries
        BarModuleSlot { required property var modelData; bar: moduleListRoot.bar; entry: modelData; region: moduleListRoot.region }
      }
    }
  }
}
