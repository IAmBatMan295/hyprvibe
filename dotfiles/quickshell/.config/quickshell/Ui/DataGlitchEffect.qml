import QtQuick

// Reusable Data / Typography glitch controller (Effect 4).
// Generates deterministic-per-step scrambled text & Nerd Font icon substitutions
// for a configurable burst duration before snapping back cleanly.
QtObject {
  id: root

  property bool active: false
  property int step: 0
  property int stepIntervalMs: 65
  property int _maxSteps: 5
  property string glyphPool: "#@%&*░▒▓⚡☠?!$"
  property var nerdAlts: ["󰀦", "󰚌", "󰜈", "󱐋", "󰒓", "󰌾", "󰅙", "󰞇"]

  function fire(durationMs) {
    var ms = (durationMs && durationMs > 0) ? durationMs : 420
    _maxSteps = Math.max(2, Math.round(ms / stepIntervalMs))
    step = 1
    active = true
    scrambleTimer.restart()
  }

  function reset() {
    scrambleTimer.stop()
    active = false
    step = 0
  }

  function scrambleText(orig, tickSeed) {
    if (!active) return orig
    var s = String(orig || "")
    var out = ""
    var pool = glyphPool
    var seed = Number(tickSeed || step) * 31
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i)
      if (ch === " " || ch === "/" || ch === "\n") {
        out += ch
      } else {
        var h = ((i * 17 + seed + s.charCodeAt(i)) % 97)
        out += (h < 58) ? pool.charAt(h % pool.length) : ch
      }
    }
    return out
  }

  function scrambleGlyph(orig, tickSeed) {
    if (!active || !orig) return orig
    var s = String(orig)
    var code = s.length > 0 ? s.charCodeAt(0) : 0
    // Nerd Font private-use glyphs live >= 0xE000
    if (code >= 0xE000) {
      var idx = Math.abs(code + Number(tickSeed || step) * 7) % nerdAlts.length
      return nerdAlts[idx]
    }
    return scrambleText(s, tickSeed)
  }

  property Timer _timer: Timer {
    id: scrambleTimer
    interval: root.stepIntervalMs
    repeat: true
    onTriggered: {
      root.step += 1
      if (root.step > root._maxSteps) {
        root.reset()
      }
    }
  }
}
