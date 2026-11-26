pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import HyprVibeLauncher
import "."

// Single owner for shell.json defaults, deep-merged user-shell.json overrides,
// atomic persistence (for Settings GUI / bar mutations), and the external
// `~/.local/state/hyprvibe/toggles/bar-off` hidden flag.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string shellPath: Quickshell.shellDir || (home + "/.config/quickshell")
  readonly property string defaultsPath: shellPath + "/shell.json"
  readonly property string userConfigPath: home + "/.config/quickshell/user-shell.json"

  readonly property var builtinShellConfig: ({
    version: 1,
    bar: {
      position: "top",
      transparent: false,
      autohide: false,
      centerAnchor: "hyprvibe.clock",
      layout: {
        left: [
          { id: "hyprvibe.media" },
          { id: "hyprvibe.workspaces" }
        ],
        center: [
          { id: "hyprvibe.clock", format: "ddd d MMM h:mm AP" }
        ],
        right: [
          { id: "hyprvibe.cpu" },
          { id: "hyprvibe.memory" },
          { id: "hyprvibe.audio" },
          { id: "hyprvibe.bluetooth" },
          { id: "hyprvibe.network" },
          { id: "hyprvibe.backlight" },
          { id: "hyprvibe.powerprofile" },
          { id: "hyprvibe.power" }
        ]
      }
    }
  })

  property var defaultsConfig: builtinShellConfig
  property var shellConfig: builtinShellConfig
  readonly property var barConfig: shellConfig && Util.isPlainObject(shellConfig.bar)
                                   ? shellConfig.bar
                                   : builtinShellConfig.bar

  property bool barHidden: false

  function deepMerge(base, override) {
    if (!Util.isPlainObject(base)) return Util.cloneJson(override)
    if (!Util.isPlainObject(override)) return Util.cloneJson(base)
    var out = {}
    for (var bk in base) out[bk] = Util.cloneJson(base[bk])
    for (var ok in override) {
      if (Util.isPlainObject(override[ok]) && Util.isPlainObject(out[ok])) {
        out[ok] = deepMerge(out[ok], override[ok])
      } else {
        out[ok] = Util.cloneJson(override[ok])
      }
    }
    return out
  }

  function applyShellConfig() {
    var base = Util.isPlainObject(defaultsConfig) ? defaultsConfig : builtinShellConfig
    var user = null
    var userText = userConfigFile.text() || ""
    if (userText.trim()) {
      try {
        var parsed = JSON.parse(userText)
        if (Util.isPlainObject(parsed) && parsed.version === 1) user = parsed
        else if (Util.isPlainObject(parsed)) console.warn("user-shell.json missing version: 1, using defaults")
      } catch (e) {
        console.warn("user-shell.json parse failed, using defaults:", e)
      }
    }
    shellConfig = user ? deepMerge(base, user) : base
  }

  function loadDefaults(raw) {
    var text = String(raw || "").trim()
    if (!text) {
      defaultsConfig = builtinShellConfig
      applyShellConfig()
      return
    }
    try {
      var parsed = JSON.parse(text)
      defaultsConfig = (Util.isPlainObject(parsed) && parsed.version === 1) ? parsed : builtinShellConfig
    } catch (e) {
      console.warn("default shell.json parse failed, using builtin:", e)
      defaultsConfig = builtinShellConfig
    }
    applyShellConfig()
  }

  function persistShellConfig(nextConfig) {
    var payload = Util.cloneJson(nextConfig || {})
    payload.version = 1
    shellConfig = payload
    userConfigFile.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function mutateShellConfig(mutator) {
    if (typeof mutator !== "function") return
    var next = Util.cloneJson(shellConfig || builtinShellConfig)
    mutator(next)
    persistShellConfig(next)
  }

  function reloadConfig() {
    defaultsFile.reload()
    userConfigFile.reload()
  }

  function syncBarHidden() {
    root.barHidden = SystemCore.pathExists(root.home + "/.local/state/hyprvibe/toggles/bar-off")
  }

  property FileView defaultsFile: FileView {
    id: defaultsFile
    path: root.defaultsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadDefaults(text())
    onLoadFailed: root.loadDefaults("")
    onFileChanged: reload()
  }

  property FileView userConfigFile: FileView {
    id: userConfigFile
    path: root.userConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyShellConfig()
    onLoadFailed: root.applyShellConfig()
    onFileChanged: reload()
  }

  property FileView togglesDirWatch: FileView {
    path: root.home + "/.local/state/hyprvibe/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: root.syncBarHidden()
  }

  Component.onCompleted: {
    SystemCore.ensureDir(root.home + "/.local/state/hyprvibe/toggles")
    root.syncBarHidden()
  }
}
