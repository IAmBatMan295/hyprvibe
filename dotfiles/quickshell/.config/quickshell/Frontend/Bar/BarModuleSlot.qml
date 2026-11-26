import QtQuick

// Instantiates a registered built-in BarWidget/PanelShell or CustomCommandWidget for one slot.
Item {
  id: slot

  required property QtObject bar
  required property var entry
  property string region: ""

  readonly property string moduleName: bar.entryId(entry)
  readonly property var moduleSettings: bar.entrySettings(entry)
  readonly property Component registeredComp: bar.widgetRegistry ? bar.widgetRegistry.componentFor(moduleName) : null
  readonly property string customType: registeredComp ? "" : bar.customModuleType(entry)
  readonly property var activeItem: registeredComp ? widgetLoader.item : customLoader.item

  implicitWidth: activeItem && activeItem.visible ? (bar.vertical ? bar.barSize : activeItem.implicitWidth) : 0
  implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
  width: implicitWidth
  height: implicitHeight

  Component.onCompleted: bar.registerModuleSlot(slot)
  Component.onDestruction: bar.unregisterModuleSlot(slot)

  Loader {
    id: widgetLoader
    active: slot.registeredComp !== null
    sourceComponent: slot.registeredComp
    anchors.fill: parent
    onLoaded: { slot.injectProps(); Qt.callLater(slot.injectProps) }
  }

  Loader {
    id: customLoader
    active: slot.customType === "command"
    sourceComponent: customCommandComponent
    anchors.fill: parent
    onLoaded: { slot.injectProps(); Qt.callLater(slot.injectProps) }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    enabled: slot.visible && slot.width > 0 && slot.height > 0
    propagateComposedEvents: true
    cursorShape: slot.bar.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) {
      if (!slot.bar.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
    }
  }

  onActiveItemChanged: Qt.callLater(injectProps)
  onModuleSettingsChanged: injectProps()

  function injectProps() {
    var target = activeItem
    if (!target) return
    if ("bar" in target) target.bar = slot.bar
    if ("moduleName" in target) target.moduleName = moduleName
    if ("settings" in target) target.settings = moduleSettings
  }

  Component {
    id: customCommandComponent
    CustomCommandWidget { bar: slot.bar; entry: slot.entry }
  }
}
