import QtQuick
import qs.Commons

Item {
  id: root

  property var bar: null
  property string text: ""
  property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property real fontSize: Style.font.body
  property bool fontBold: false
  property color foreground: bar ? bar.barForeground : ThemeColor.foreground
  property color activeColor: bar ? bar.urgent : ThemeColor.urgent
  property color hoverColor: ThemeColor.accent
  property bool highlightOnHover: true
  property bool active: false
  property real horizontalMargin: 8.5
  property real verticalPadding: 6
  property real fixedWidth: -1
  property real fixedHeight: -1
  property real textRotation: 0
  property bool keepSpace: false
  property bool dimmed: false
  property bool concealed: false
  property bool interactive: true
  property bool pressable: true
  property bool useActiveColor: true
  property bool maintainIndicatorReveal: false
  property bool labelVisible: true
  property Component leadingComponent: null
  property real leadingSpacing: Style.space(6)
  property Component trailingComponent: null
  property real trailingSpacing: Style.space(5)
  property bool hasVisualContent: text !== ""
  property var revealHost: bar
  property string tooltipText: ""
  property var registeredBar: null

  readonly property color effectiveColor: {
    if (root.active && root.useActiveColor) return root.activeColor
    if (root.hovered && root.highlightOnHover) return root.hoverColor
    return root.foreground
  }

  signal pressed(int button)
  signal wheelMoved(int delta)

  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button)
  }

  function hideOwnTooltip() {
    if (root.bar) root.bar.hideTooltip(root)
  }

  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }

  onBarChanged: syncClickRegistration()
  onVisibleChanged: if (!visible) hideOwnTooltip()
  onInteractiveChanged: if (!interactive) hideOwnTooltip()
  onConcealedChanged: if (concealed) hideOwnTooltip()
  onTooltipTextChanged: {
    if (mouseArea.containsMouse && root.bar) {
      root.bar.showTooltip(root, root.tooltipText)
    }
  }
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property real scaledHorizontalMargin: Style.spaceReal(horizontalMargin)
  readonly property real scaledVerticalPadding: Style.spaceReal(verticalPadding)
  readonly property bool tooltipHovered: visible && interactive && !concealed && mouseArea.containsMouse
  readonly property bool hovered: visible && interactive && !concealed && mouseArea.containsMouse
  // Width of the painted label, for bar chrome that wants to line up with the
  // text rather than with the slot it sits in. Zero on icon-only buttons.
  readonly property real labelWidth: label.visible ? label.implicitWidth : 0
  // Painted content width inside this button; subclasses like BarIconButton
  // bind their optical glyph/canvas width so barEdgeInset measures true inner
  // padding from widget edge to painted content for Bar.qml edge alignment.
  property real contentVisualWidth: labelVisible ? contentRow.implicitWidth : 0
  readonly property real barEdgeInset: Math.max(0, (width - contentVisualWidth) / 2)

  visible: hasVisualContent || keepSpace
  opacity: !hasVisualContent || concealed ? 0 : (dimmed ? 0.45 : 1)
  implicitWidth: fixedWidth > 0 ? fixedWidth : (vertical ? barSize : Math.max(12, contentRow.implicitWidth + scaledHorizontalMargin * 2))
  implicitHeight: fixedHeight > 0 ? fixedHeight : (vertical ? Math.max(12, contentRow.implicitHeight + scaledVerticalPadding * 2) : barSize)

  Behavior on opacity {
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  Row {
    id: contentRow
    anchors.centerIn: parent
    spacing: 0

    Loader {
      id: leadingLoader
      anchors.verticalCenter: parent.verticalCenter
      active: root.labelVisible && root.leadingComponent !== null
      visible: active && status === Loader.Ready
      sourceComponent: root.leadingComponent
    }

    Item {
      width: root.leadingSpacing
      height: 1
      visible: leadingLoader.visible
    }

    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      visible: root.labelVisible
      text: (root.bar && root.bar.dataEffect && root.bar.dataEffect.active)
        ? root.bar.dataEffect.scrambleText(root.text)
        : root.text
      color: root.effectiveColor
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.fontBold
      renderType: Text.NativeRendering
      rotation: root.textRotation
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter

      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      width: root.trailingSpacing
      height: 1
      visible: trailingLoader.visible
    }

    Loader {
      id: trailingLoader
      anchors.verticalCenter: parent.verticalCenter
      active: root.labelVisible && root.trailingComponent !== null
      visible: active && status === Loader.Ready
      sourceComponent: root.trailingComponent
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: root.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: {
      if (root.bar) {
        root.bar.showTooltip(root, root.tooltipText)
      }
      if (root.maintainIndicatorReveal && root.revealHost && root.revealHost.setIndicatorItemHovered)
        root.revealHost.setIndicatorItemHovered(true)
    }
    onExited: {
      if (root.bar) {
        root.bar.hideTooltip(root)
      }
      if (root.maintainIndicatorReveal && root.revealHost && root.revealHost.setIndicatorItemHovered)
        root.revealHost.setIndicatorItemHovered(false)
    }
    onClicked: function(mouse) { if (root.pressable) root.triggerPress(mouse.button) }
    onWheel: function(wheel) { root.wheelMoved(wheel.angleDelta.y) }
  }
}
