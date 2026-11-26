import QtQuick
import QtQuick.Window
import qs.Commons

// Reusable high-DPI CRT ShaderEffect wrapper.
// Wraps child visuals in an FBO only while `active` is true, so disabled
// themes/components pay zero GPU memory or pass cost.
Item {
  id: root

  default property alias content: host.data

  property bool active: true
  property bool suspended: false
  property real burstIntensity: 0.0
  property real scanlineAlpha: Style.effects.crtScanlineAlpha
  property color accentColor: ThemeColor.accent
  property bool animateAmbient: true
  property real _time: 0.0

  readonly property real _dpr: (Window.window && Window.window.screen && Window.window.screen.devicePixelRatio > 0)
    ? Window.window.screen.devicePixelRatio
    : 1.0

  NumberAnimation {
    target: root
    property: "_time"
    from: 0.0
    to: 600.0
    duration: 300000
    loops: Animation.Infinite
    running: root.visible && root.active && !root.suspended && (root.animateAmbient || root.burstIntensity > 0.001)
  }

  Item {
    id: host
    anchors.fill: parent
    layer.enabled: root.active && !root.suspended
    layer.samplerName: "source"
    layer.smooth: false
    layer.effect: ShaderEffect {
      property real u_time: root._time
      property real u_intensity: root.burstIntensity
      property real u_width: Math.max(1.0, host.width * root._dpr)
      property real u_height: Math.max(1.0, host.height * root._dpr)
      property real u_scanlineAlpha: root.scanlineAlpha
      property color u_accent: root.accentColor
      fragmentShader: Qt.resolvedUrl("shaders/crt_effect.frag.qsb")
    }
  }
}
