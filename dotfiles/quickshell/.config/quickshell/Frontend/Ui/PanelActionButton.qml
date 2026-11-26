import QtQuick
import qs.Backend.Config

// Small (22×22 by default) icon button used at the right edge of panel rows
// for inline actions — forget network, confirm passphrase, unpair device,
// etc. Two visual modes are supported via `hoverColor`:
//   - default: hoverColor === foreground → subtle foreground-tint hover
//   - urgent:  hoverColor === bar.urgent → red-tint hover for destructive
//              actions like forget/unpair
//
// `enabled` gates clicks and dims the icon. The component owns its own
// hover state visuals; mouse hover does NOT update any panel cursor state
// here because action buttons are not cursor targets — the row they live
// in is.
//
// Set `focusable: true` to make the button keyboard-tabbable with the
// shared hover-cursor/focus tokens. Use this
// in form contexts where Tab walks a list
// of controls; leave it false for the right-edge actions on panel rows
// where the row's CursorSurface owns the keyboard cursor.
//
// Set `hasCursor: true` to have the button render the same hover state as
// mouse hover — so a panel's keyboard cursor lands on it identically.
// Use this when a PanelActionButton is itself the cursor target (rather
// than living inside a CursorSurface row). Emits `hovered(bool)` on
// pointer enter/leave so the panel can update its cursor state to match.
BorderSurface {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property color foreground: ThemeStore.foreground
  property color hoverColor: foreground
  property color accent: ThemeStore.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.icon
  property real size: Math.max(Style.space(22), fontSize + Style.spacing.sm * 2)

  property bool focusable: false
  property bool hasCursor: false
  property bool bordered: false
  property bool borderHoverOnly: false

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  implicitWidth: size
  implicitHeight: size
  radius: Style.cornerRadius

  readonly property int _cursorPad: root.borderHoverOnly ? Style.space(3) : 0
  readonly property bool _showFocusRing: focusable && activeFocus
  readonly property bool _hot: (mouse.containsMouse || root.hasCursor) && root.enabled
  readonly property var _borderSpec: root.borderHoverOnly
    ? (_showFocusRing
      ? Border.controlSpec("focus", root.foreground, root.accent)
      : (_hot ? Border.controlSpec("hover-cursor", root.foreground, root.accent) : Border.none()))
    : (_showFocusRing
      ? Border.flat(hoverColor, 1)
      : (_hot
        ? Border.flat(hoverColor, 1)
        : (bordered ? Border.flat(Qt.rgba(hoverColor.r, hoverColor.g, hoverColor.b, 0.28), 1) : Border.none())))

  color: root.borderHoverOnly
    ? "transparent"
    : (mouse.pressed
      ? Qt.rgba(hoverColor.r, hoverColor.g, hoverColor.b, 0.28)
      : (_hot
        ? Qt.rgba(hoverColor.r, hoverColor.g, hoverColor.b, 0.20)
        : (bordered ? Qt.rgba(0, 0, 0, 0.28) : "transparent")))
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: 80 } }

  BorderSurface {
    anchors.fill: parent
    anchors.margins: root._cursorPad
    visible: root.borderHoverOnly
    radius: root.radius
    color: root.bordered ? Qt.rgba(0, 0, 0, 0.28) : "transparent"
    borderSpec: root.bordered ? Border.controlSpec("normal", root.foreground, root.accent) : Border.none()
  }

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    text: GlitchBus.panelGlyph(root.iconText)
    color: root.enabled
      ? ((!root.borderHoverOnly && root._hot) ? root.hoverColor : root.foreground)
      : Qt.darker(root.foreground, 2.0)
    font.family: root.fontFamily
    font.pixelSize: root.borderHoverOnly ? Math.max(10, root.fontSize - 2) : root.fontSize
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.enabled
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: {
      if (root.focusable) root.forceActiveFocus()
      root.clicked()
    }
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }
}
