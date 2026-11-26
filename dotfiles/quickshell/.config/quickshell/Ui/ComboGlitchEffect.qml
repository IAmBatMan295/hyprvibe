import QtQuick
import qs.Commons

// Reusable combined glitch + CRT container (Effects 1 + 4 + 5).
// Driven declaratively by Style tokens (`componentId` -> shell.toml [effects])
// so global user settings / GUI toggles can swap effect modes live.
//
// Supported glitchMode: "none" | "spatial" | "data" | "crt" | "combo"
// Supported crtMode:    "off" | "burst" | "fulltime"
Item {
  id: root

  default property alias content: stage.data

  property string componentId: ""
  property var sharedDataEffect: null
  property bool useSyncedClock: true
  property bool suspended: false
  property string glitchMode: Style.componentGlitchMode(componentId)
  property string crtMode: Style.componentCrtMode(componentId)
  property int intervalMs: Style.effects.glitchIntervalMs
  property int burstMs: Style.effects.glitchBurstMs
  property real scanlineAlpha: Style.effects.crtScanlineAlpha

  readonly property bool _useSpatial: glitchMode === "spatial" || glitchMode === "combo"
  readonly property bool _useData: glitchMode === "data" || glitchMode === "combo"
  readonly property bool _useCrtBurst: glitchMode === "crt" || glitchMode === "combo"
  readonly property var dataEffect: sharedDataEffect ? sharedDataEffect : dataFx
  readonly property bool bursting: !suspended && (spatialFx.active || dataEffect.active || _crtBurstIntensity > 0.02)

  property real _crtBurstIntensity: 0.0

  function reset() {
    spatialFx.reset()
    dataEffect.reset()
    crtDecay.stop()
    _crtBurstIntensity = 0.0
  }

  function fireBurst() {
    if (!Style.effects.enabled || root.suspended) return
    if (_useSpatial) spatialFx.fire(burstMs)
    if (_useData) dataEffect.fire(burstMs)
    if (crtMode !== "off" && _useCrtBurst) {
      _crtBurstIntensity = 1.0
      crtDecay.restart()
    }
  }

  onSuspendedChanged: if (suspended) reset()

  DataGlitchEffect {
    id: dataFx
  }

  Connections {
    target: GlitchBus
    enabled: root.useSyncedClock
    function onBurstTriggered() {
      if (root.visible && !root.suspended && Style.effects.enabled && Style.effects.animations && root.glitchMode !== "none") {
        root.fireBurst()
      }
    }
  }

  Timer {
    interval: Math.max(500, root.intervalMs)
    repeat: true
    running: !root.useSyncedClock && !root.suspended && root.visible && Style.effects.enabled && Style.effects.animations && root.glitchMode !== "none"
    onTriggered: root.fireBurst()
  }

  NumberAnimation {
    id: crtDecay
    target: root
    property: "_crtBurstIntensity"
    from: 1.0
    to: 0.0
    duration: Math.max(150, root.burstMs)
    easing.type: Easing.OutQuad
  }

  CrtShaderEffect {
    anchors.fill: parent
    suspended: root.suspended
    active: !root.suspended && Style.effects.enabled && (
      root.crtMode === "fulltime" ||
      (root.crtMode === "burst" && root._crtBurstIntensity > 0.005)
    )
    burstIntensity: root._crtBurstIntensity
    scanlineAlpha: root.scanlineAlpha

    Item {
      id: stage
      x: root._useSpatial ? spatialFx.jitterX : 0
      y: root._useSpatial ? spatialFx.jitterY : 0
      width: parent.width
      height: parent.height
      transform: Scale {
        origin.x: stage.width / 2
        origin.y: stage.height / 2
        xScale: root._useSpatial ? spatialFx.squashX : 1.0
        yScale: root._useSpatial ? spatialFx.squashY : 1.0
      }
    }

    SpatialGlitchEffect {
      id: spatialFx
      targetItem: stage
      sliceEnabled: root._useSpatial
    }
  }
}
