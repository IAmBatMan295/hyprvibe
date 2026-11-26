import QtQuick
import qs.Backend.Config

// Micro Arc Reactor circular gauge for CPU speed & load.
// Optimization: the outer HUD reticle paints ONCE onto Canvas and rotates pure
// GPU via transform rotation (zero per-frame Canvas redraws); the inner load
// arc only repaints during short ratio/color transitions after polling.
Item {
  id: root

  property real ratio: 0.0
  property real speedRatio: 0.0
  property bool suspended: false
  property bool animate: Style.effects.animations
  property int size: Math.max(14, Style.space(18))

  property color normalColor: ThemeStore.bar.text
  property color urgentColor: ThemeStore.bar.active
  property color reticleColor: ThemeStore.muted
  property color trackColor: Qt.rgba(ThemeStore.muted.r, ThemeStore.muted.g, ThemeStore.muted.b, 0.18)

  readonly property real clampedRatio: Math.max(0, Math.min(1, ratio))
  readonly property color activeColor: Style.loadStateColor(clampedRatio, normalColor, urgentColor)
  // Quantize speedRatio into 5 gears so noisy 0.1GHz fluctuations don't restart rotation mid-cycle
  readonly property int _speedGear: Math.max(0, Math.min(4, Math.round(Math.max(0, Math.min(1, speedRatio)) * 4)))
  readonly property int spinDurationMs: 6400 - _speedGear * 900
  readonly property bool spinActive: visible && animate && !suspended

  property real animatedRatio: clampedRatio

  Behavior on animatedRatio {
    enabled: root.animate && !root.suspended && root.visible
    NumberAnimation {
      duration: 280
      easing.type: Easing.OutCubic
    }
  }

  implicitWidth: size
  implicitHeight: size

  Canvas {
    id: reticleCanvas
    anchors.fill: parent
    property color strokeColor: root.reticleColor

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onStrokeColorChanged: requestPaint()
    Component.onCompleted: requestPaint()

    NumberAnimation on rotation {
      running: root.spinActive
      from: 0
      to: 360
      duration: root.spinDurationMs
      loops: Animation.Infinite
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2
      var cy = height / 2
      var r = Math.max(2, Math.min(cx, cy) - 1.5)
      ctx.strokeStyle = strokeColor
      ctx.lineWidth = Math.max(1.1, width * 0.068)
      ctx.lineCap = "round"
      ctx.beginPath()
      ctx.arc(cx, cy, r, -0.4, Math.PI * 0.65)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(cx, cy, r, Math.PI - 0.3, Math.PI * 1.6)
      ctx.stroke()
    }
  }

  Canvas {
    id: arcCanvas
    anchors.fill: parent
    property real sweepRatio: root.animatedRatio
    property color fgColor: root.activeColor
    property color bgTrackColor: root.trackColor

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onSweepRatioChanged: requestPaint()
    onFgColorChanged: requestPaint()
    onBgTrackColorChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2
      var cy = height / 2
      var r = Math.max(2, Math.min(cx, cy) * 0.56)
      var lw = Math.max(1.8, width * 0.13)

      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.strokeStyle = bgTrackColor
      ctx.lineWidth = lw
      ctx.stroke()

      if (sweepRatio > 0.005) {
        ctx.beginPath()
        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * sweepRatio)
        ctx.strokeStyle = fgColor
        ctx.lineWidth = lw
        ctx.lineCap = "round"
        ctx.stroke()
      }
    }
  }
}
