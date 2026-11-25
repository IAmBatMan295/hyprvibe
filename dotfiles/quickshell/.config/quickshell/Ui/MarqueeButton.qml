import QtQuick
import qs.Commons

// Fixed-width bar button with Waybar-style wrapping marquee text and optional
// single-click vs left/right-half double-click zone disambiguation.
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
  property bool useActiveColor: true
  property real fixedWidth: 180
  property real fixedHeight: -1
  property real horizontalMargin: 8
  property real verticalPadding: 2
  property real marqueeGap: 36
  property real marqueeSpeed: 42
  property bool pauseOnHover: false
  property bool dimmed: false
  property bool concealed: false
  property bool interactive: true
  property bool pressable: true
  property bool splitDoubleClick: false
  property int doubleClickWindowMs: 240
  property bool hasVisualContent: text !== ""
  property string tooltipText: ""
  property var registeredBar: null

  property real _pendingClickX: 0

  signal pressed(int button)
  signal singleClicked()
  signal doubleClickedLeft()
  signal doubleClickedRight()

  function triggerPress(button) {
    triggerPressAt(button, root.width / 2, root.height / 2)
  }

  function triggerPressAt(button, localX, localY) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button)
    if (!root.splitDoubleClick || button !== Qt.LeftButton) return

    var clickX = (localX !== undefined && localX !== null) ? localX : (root.width / 2)
    if (clickTimer.running) {
      clickTimer.stop()
      if (clickX < root.width / 2) {
        root.doubleClickedLeft()
      } else {
        root.doubleClickedRight()
      }
    } else {
      root._pendingClickX = clickX
      clickTimer.restart()
    }
  }

  function hideOwnTooltip() {
    if (root.bar) root.bar.hideTooltip(root)
  }

  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(root)
  }

  function resetMarquee() {
    marqueeTrack.x = 0
    if (root.visible && root.needsScroll) {
      marqueeAnim.restart()
    }
  }

  onBarChanged: syncClickRegistration()
  onVisibleChanged: {
    if (!visible) hideOwnTooltip()
    resetMarquee()
  }
  onInteractiveChanged: if (!interactive) hideOwnTooltip()
  onConcealedChanged: if (concealed) hideOwnTooltip()
  onTextChanged: resetMarquee()
  onNeedsScrollChanged: resetMarquee()
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
  readonly property real scaledMarqueeGap: Style.spaceReal(marqueeGap)
  readonly property real scaledFixedWidth: fixedWidth > 0 ? Style.spaceReal(fixedWidth) : -1
  readonly property bool tooltipHovered: visible && interactive && !concealed && mouseArea.containsMouse
  readonly property bool hovered: visible && interactive && !concealed && mouseArea.containsMouse
  readonly property color resolvedColor: {
    if (root.active && root.useActiveColor) return root.activeColor
    if (root.hovered && root.highlightOnHover) return root.hoverColor
    return root.foreground
  }
  readonly property real viewportWidth: Math.max(0, width - scaledHorizontalMargin * 2)
  readonly property real textWidth: Math.ceil(Math.max(metrics.advanceWidth, metrics.boundingRect.width))
  readonly property bool needsScroll: text !== "" && viewportWidth > 0 && textWidth > viewportWidth
  // Distance from widget outer edge to the clipped marquee wrap viewport;
  // Bar.qml subtracts this from Style.gapsOut to keep widget margins symmetric
  // while aligning the wrap edge to Hyprland's window border.
  readonly property real barEdgeInset: scaledHorizontalMargin

  visible: hasVisualContent
  opacity: !hasVisualContent || concealed ? 0 : (dimmed ? 0.45 : 1)
  implicitWidth: scaledFixedWidth > 0 ? scaledFixedWidth : Math.max(12, textWidth + scaledHorizontalMargin * 2)
  implicitHeight: fixedHeight > 0 ? fixedHeight : barSize

  Behavior on opacity {
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  TextMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.fontBold
    text: root.text
  }

  Timer {
    id: clickTimer
    interval: root.doubleClickWindowMs
    repeat: false
    onTriggered: root.singleClicked()
  }

  Item {
    id: viewport
    anchors.fill: parent
    anchors.leftMargin: root.scaledHorizontalMargin
    anchors.rightMargin: root.scaledHorizontalMargin
    clip: true

    Text {
      id: staticLabel
      visible: !root.needsScroll
      anchors.centerIn: parent
      text: root.text
      textFormat: Text.PlainText
      color: root.resolvedColor
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.fontBold
      renderType: Text.NativeRendering
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter

      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }
    }

    Item {
      id: marqueeTrack
      visible: root.needsScroll
      y: 0
      height: viewport.height
      width: root.textWidth * 2 + root.scaledMarqueeGap

      Text {
        id: copyA
        x: 0
        height: parent.height
        text: root.text
        textFormat: Text.PlainText
        color: root.resolvedColor
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: root.fontBold
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      Text {
        id: copyB
        x: root.textWidth + root.scaledMarqueeGap
        height: parent.height
        text: root.text
        textFormat: Text.PlainText
        color: root.resolvedColor
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        font.bold: root.fontBold
        renderType: Text.NativeRendering
        verticalAlignment: Text.AlignVCenter

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }

    NumberAnimation {
      id: marqueeAnim
      target: marqueeTrack
      property: "x"
      from: 0
      to: -(root.textWidth + root.scaledMarqueeGap)
      duration: Math.max(500, Math.round(((root.textWidth + root.scaledMarqueeGap) / Math.max(10, root.marqueeSpeed)) * 1000))
      easing.type: Easing.Linear
      loops: Animation.Infinite
      running: root.visible && root.needsScroll
      paused: root.pauseOnHover && root.hovered
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.RightButton | Qt.MiddleButton
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: root.pressable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: {
      if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    }
    onExited: {
      if (root.bar) root.bar.hideTooltip(root)
    }
    onClicked: function(mouse) {
      if (root.pressable) root.triggerPressAt(mouse.button, mouse.x, mouse.y)
    }
  }
}
