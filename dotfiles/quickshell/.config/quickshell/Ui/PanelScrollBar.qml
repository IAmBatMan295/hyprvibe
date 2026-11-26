import QtQuick
import QtQuick.Templates as T
import qs.Commons

// Thin accent-themed vertical scrollbar extending QtQuick.Templates.ScrollBar
// so the thumb stays pinned to the right edge and visible whenever scrollable.
T.ScrollBar {
  id: root

  policy: size < 1.0 ? T.ScrollBar.AlwaysOn : T.ScrollBar.AlwaysOff
  visible: size < 1.0 && policy !== T.ScrollBar.AlwaysOff
  padding: 0
  implicitWidth: Math.max(4, Style.space(5))
  implicitHeight: Style.space(48)

  x: parent ? (parent.width - width) : 0
  y: (parent && "topPadding" in parent) ? parent.topPadding : 0
  height: (parent && "availableHeight" in parent)
    ? parent.availableHeight
    : (parent ? parent.height : implicitHeight)

  readonly property color accentColor: ThemeColor.accent
  readonly property bool interacting: pressed || hovered || active

  background: Rectangle {
    implicitWidth: root.implicitWidth
    radius: Math.min(width / 2, Style.cornerRadius)
    color: root.interacting
      ? Util.alpha(ThemeColor.foreground, 0.10)
      : Util.alpha(ThemeColor.foreground, 0.05)

    Behavior on color { ColorAnimation { duration: 120 } }
  }

  contentItem: Rectangle {
    implicitWidth: root.implicitWidth
    radius: Math.min(width / 2, Style.cornerRadius)
    color: root.pressed
      ? root.accentColor
      : (root.hovered
        ? Util.alpha(root.accentColor, 0.95)
        : Util.alpha(root.accentColor, root.active ? 0.85 : 0.65))

    Behavior on color { ColorAnimation { duration: 120 } }
  }
}
