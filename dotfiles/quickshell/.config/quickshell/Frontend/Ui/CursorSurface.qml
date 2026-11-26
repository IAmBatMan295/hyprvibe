import QtQuick
import qs.Backend.Config
import qs.Frontend.Styles

// Shared Launcher-matched visual chrome for keyboard-and-mouse-navigable items inside panels.
// Uses accent selection tint + 1px accent outline on cursor/hover, subtle tint on current row.
BorderSurface {
  id: root

  property bool hasCursor: false
  property bool current: false
  property bool pressed: false
  property bool outline: false
  property bool bordered: false

  property color foreground: ThemeStore.foreground
  property color accent: ThemeStore.accent
  property color fill: "transparent"
  property color currentFill: "transparent"

  radius: PanelStyle.cornerRadius

  color: root.pressed
    ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.32)
    : (root.hasCursor
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
      : (root.current
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.11)
        : (root.bordered ? PanelStyle.darkBackground : "transparent")))

  borderSpec: root.hasCursor
    ? Border.flat(root.accent, 1)
    : ((root.current || root.bordered || root.outline)
      ? Border.flat(Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.current ? 0.42 : 0.24), 1)
      : Border.none())

  Behavior on color {
    ColorAnimation { duration: 80 }
  }
}
