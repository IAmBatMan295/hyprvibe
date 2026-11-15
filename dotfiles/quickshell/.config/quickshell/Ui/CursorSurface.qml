import QtQuick
import qs.Commons

// Shared visual chrome for keyboard-and-mouse-navigable items inside a panel.
// Visuals derive from `hasCursor` / `current` / `pressed`.
// No background change on hover or active/current state.
// Active/connected items show a 2px accent border.
// Hovered items show a 1px muted border.
// On press/click: 80ms instant subtle micro-flash.
BorderSurface {
  id: root

  property bool hasCursor: false
  property bool current: false
  property bool pressed: false
  property bool outline: false
  property bool bordered: false

  property color foreground: ThemeColor.foreground
  property color accent: ThemeColor.accent
  property color fill: "transparent"
  property color currentFill: "transparent"

  radius: Style.cornerRadius

  color: pressed ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : "transparent"
  borderSpec: root.current
    ? Border.flat(root.accent, 2)
    : (root.hasCursor
      ? Border.flat(ThemeColor.muted, 1)
      : (root.bordered
        ? Border.flat(Qt.darker(ThemeColor.muted, 1.4), 1)
        : Border.none()))

  Behavior on color {
    ColorAnimation { duration: 80 }
  }
}
