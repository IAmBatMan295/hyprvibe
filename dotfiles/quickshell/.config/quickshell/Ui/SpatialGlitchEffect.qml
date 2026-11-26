import QtQuick

// Reusable Spatial / Slice glitch controller (Effect 1).
// Applies brief x/y micro-jitter, squash/stretch transform, and optional live
// horizontal ShaderEffectSource slice bands over a target Item during bursts.
Item {
  id: root

  property Item targetItem: null
  property bool sliceEnabled: true
  property bool active: false
  property real jitterX: 0
  property real jitterY: 0
  property real squashX: 1.0
  property real squashY: 1.0
  property real band1Offset: 0
  property real band2Offset: 0
  property real band1FracY: 0.20
  property real band2FracY: 0.66
  property real band1SegStart: 0.15
  property real band1SegSpan: 0.34
  property real band2SegStart: 0.52
  property real band2SegSpan: 0.30
  property int stepIntervalMs: 58
  property int _step: 0
  property int _maxSteps: 7

  function fire(durationMs) {
    var ms = (durationMs && durationMs > 0) ? durationMs : 420
    _maxSteps = Math.max(3, Math.round(ms / stepIntervalMs))
    _step = 0
    active = true
    burstTimer.restart()
  }

  function reset() {
    burstTimer.stop()
    active = false
    jitterX = 0
    jitterY = 0
    squashX = 1.0
    squashY = 1.0
    band1Offset = 0
    band2Offset = 0
  }

  anchors.fill: parent
  visible: active
  clip: true

  Timer {
    id: burstTimer
    interval: root.stepIntervalMs
    repeat: true
    onTriggered: {
      root._step += 1
      if (root._step > root._maxSteps) {
        root.reset()
        return
      }
      root.jitterX = (Math.random() - 0.5) * 5.0
      root.jitterY = (Math.random() - 0.5) * 2.0
      root.squashX = 1.0 + (Math.random() - 0.5) * 0.08
      root.squashY = 1.0 - (root.squashX - 1.0) * 0.6
      root.band1Offset = (Math.random() - 0.5) * 14.0
      root.band2Offset = (Math.random() - 0.5) * 18.0
      root.band1SegStart = Math.random() * 0.65
      root.band2SegStart = Math.random() * 0.65
    }
  }

  // Live horizontal slice bands clipped directly from targetItem texture during bursts
  ShaderEffectSource {
    id: sliceSrc
    live: root.active && root.sliceEnabled && root.targetItem !== null
    sourceItem: root.active && root.sliceEnabled ? root.targetItem : null
    hideSource: false
    visible: false
  }

  Item {
    visible: root.active && root.sliceEnabled && root.targetItem !== null
    x: Math.round(root.width * root.band1SegStart)
    y: Math.round(root.height * root.band1FracY)
    width: Math.max(48, Math.round(root.width * root.band1SegSpan))
    height: Math.max(2, Math.round(root.height * 0.13))
    clip: true

    ShaderEffect {
      x: -Math.round(root.width * root.band1SegStart) + root.band1Offset
      y: -Math.round(root.height * root.band1FracY)
      width: root.width
      height: root.height
      property var source: sliceSrc
    }
  }

  Item {
    visible: root.active && root.sliceEnabled && root.targetItem !== null
    x: Math.round(root.width * root.band2SegStart)
    y: Math.round(root.height * root.band2FracY)
    width: Math.max(48, Math.round(root.width * root.band2SegSpan))
    height: Math.max(2, Math.round(root.height * 0.11))
    clip: true

    ShaderEffect {
      x: -Math.round(root.width * root.band2SegStart) + root.band2Offset
      y: -Math.round(root.height * root.band2FracY)
      width: root.width
      height: root.height
      property var source: sliceSrc
    }
  }
}
