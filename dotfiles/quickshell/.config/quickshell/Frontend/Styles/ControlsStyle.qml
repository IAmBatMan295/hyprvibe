pragma Singleton
import QtQuick
import qs.Backend.Config

// Shared interactive control chrome stylesheet for buttons, toggles, sliders, and cursor rows.
QtObject {
  id: root

  readonly property color normalFill: Style.normalFill
  readonly property color hoverFill: Style.hoverFill
  readonly property color selectedFill: Style.selectedFill
  readonly property color pressedFill: Style.pressedFill
  readonly property color focusFillColor: Style.focusFillColor
  readonly property color selectionFill: Style.selectionFill

  readonly property int normalBorderWidth: Style.normalBorderWidth
  readonly property int hoverBorderWidth: Style.hoverBorderWidth
  readonly property int selectedBorderWidth: Style.selectedBorderWidth
  readonly property int focusBorderWidth: Style.focusBorderWidth

  function controlFill(focused, hot, fg, accent) { return Style.controlFill(focused, hot, fg, accent) }
  function controlBorder(focused, hot, fg, accent) { return Style.controlBorder(focused, hot, fg, accent) }
  function controlBorderWidth(focused, hot) { return Style.controlBorderWidth(focused, hot) }
}
