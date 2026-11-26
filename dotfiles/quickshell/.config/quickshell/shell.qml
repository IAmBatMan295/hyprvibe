//@ pragma Env MALLOC_ARENA_MAX = 2
import QtQuick
import Quickshell
import Quickshell.Io

import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Bar
import "Launcher"

// Thin composition root wiring Backend singletons, Frontend Bar/Widgets/Panels,
// single-process LauncherHost, and centralized monitor-safe IPC targets.
ShellRoot {
  id: shell

  readonly property alias bar: mainBar
  property bool settingsOpen: false
  property string settingsTab: "theme"

  WidgetRegistry {
    id: widgetRegistry
  }

  Bar {
    id: mainBar
    widgetRegistry: widgetRegistry
  }

  LauncherHost {
    id: launcher
  }

  Loader {
    id: settingsLoader
    active: shell.settingsOpen
    source: "Frontend/Settings/SettingsWindow.qml"
    onLoaded: {
      if (item) {
        item.open = Qt.binding(function() { return shell.settingsOpen })
        item.activeTab = shell.settingsTab
        item.closeRequested.connect(function() { shell.settingsOpen = false })
      }
    }
  }

  function invokeModuleMethod(id, method, arg) {
    var list = mainBar.moduleWidgets(id)
    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (item && typeof item[method] === "function") {
        var result = arg !== undefined && arg !== "" ? item[method](arg) : item[method]()
        return result !== undefined ? String(result) : "ok"
      }
    }
    return "unknown"
  }

  IpcHandler {
    target: "hyprvibe.bar"

    function syncHidden(): void { ShellConfig.syncBarHidden() }
    function show(): void { mainBar.ipcShow() }
    function hide(): void { mainBar.ipcHide() }
    function toggle(): void { mainBar.ipcToggle() }
    function setTransparency(value: string): string {
      mainBar.setRequestedTransparency(String(value || "").trim().toLowerCase() === "true")
      return mainBar.requestedTransparent ? "true" : "false"
    }
    function toggleTransparency(): string {
      mainBar.toggleTransparency()
      return mainBar.requestedTransparent ? "true" : "false"
    }
  }

  IpcHandler {
    target: "hyprvibe.powerprofile"

    function setProfile(p: string): void { TelemetryService.setPowerProfileName(p) }
    function refresh(): void { TelemetryService.refreshPowerProfile() }
  }

  IpcHandler {
    target: "hyprvibe.audio"

    function open(): void { mainBar.summonBarWidget("hyprvibe.audio") }
    function close(): void { mainBar.hideBarWidget("hyprvibe.audio") }
    function show(): void { mainBar.summonBarWidget("hyprvibe.audio") }
    function hide(): void { mainBar.hideBarWidget("hyprvibe.audio") }
    function toggle(): void { mainBar.toggleBarWidget("hyprvibe.audio") }
    function toggleMute(): void { AudioService.toggleOutputMute() }
    function toggleAllMuted(): void { AudioService.toggleAllMuted() }
  }

  IpcHandler {
    target: "hyprvibe.bluetooth"

    function open(): void { mainBar.summonBarWidget("hyprvibe.bluetooth") }
    function close(): void { mainBar.hideBarWidget("hyprvibe.bluetooth") }
    function show(): void { mainBar.summonBarWidget("hyprvibe.bluetooth") }
    function hide(): void { mainBar.hideBarWidget("hyprvibe.bluetooth") }
    function toggle(): void { mainBar.toggleBarWidget("hyprvibe.bluetooth") }
    function toggleBluetooth(): void { BluetoothService.toggleBluetooth() }
  }

  IpcHandler {
    target: "hyprvibe.network"

    function open(): void { mainBar.summonBarWidget("hyprvibe.network") }
    function close(): void { mainBar.hideBarWidget("hyprvibe.network") }
    function show(): void { mainBar.summonBarWidget("hyprvibe.network") }
    function hide(): void { mainBar.hideBarWidget("hyprvibe.network") }
    function toggle(): void { mainBar.toggleBarWidget("hyprvibe.network") }
    function toggleNetwork(): void { NetworkService.toggleNetwork() }
  }

  IpcHandler {
    target: "hyprvibe.power"

    function open(): void { mainBar.summonBarWidget("hyprvibe.power") }
    function close(): void { mainBar.hideBarWidget("hyprvibe.power") }
    function show(): void { mainBar.summonBarWidget("hyprvibe.power") }
    function hide(): void { mainBar.hideBarWidget("hyprvibe.power") }
    function toggle(): void { mainBar.toggleBarWidget("hyprvibe.power") }
  }

  IpcHandler {
    target: "hyprvibe.clock"

    function refresh(): void { shell.invokeModuleMethod("hyprvibe.clock", "refresh", "") }
  }

  IpcHandler {
    target: "hyprvibe.settings"

    function open(): void { shell.settingsOpen = true }
    function close(): void { shell.settingsOpen = false }
    function show(): void { shell.settingsOpen = true }
    function hide(): void { shell.settingsOpen = false }
    function toggle(): void { shell.settingsOpen = !shell.settingsOpen }
    function openTab(tab: string): void {
      if (tab) shell.settingsTab = tab
      if (settingsLoader.item && tab) settingsLoader.item.activeTab = tab
      shell.settingsOpen = true
    }
  }

  IpcHandler {
    target: "shell"

    function ping(): string { return "ok" }

    function applyTheme(colorsB64: string, shellB64: string): string {
      ThemeStore.loadColors(Util.decodeBase64(colorsB64))
      ThemeStore.loadShell(Util.decodeBase64(shellB64))
      Style.scheduleRefresh()
      return "ok"
    }

    function reloadConfig(): string {
      ShellConfig.reloadConfig()
      return "ok"
    }

    function toggleBarTransparency(): string {
      mainBar.toggleTransparency()
      return "ok"
    }

    function listShellConfig(): string {
      return JSON.stringify(ShellConfig.shellConfig || {})
    }

    function debugBarGeometry(): string {
      return JSON.stringify(mainBar.debugBarGeometry())
    }

    function summon(id: string, payloadJson: string): string {
      return mainBar.summonBarWidget(id) ? "ok" : "unknown"
    }

    function hide(id: string): void { mainBar.hideBarWidget(id) }
    function toggle(id: string, payloadJson: string): void { mainBar.toggleBarWidget(id) }

    function togglePanelAt(section: string, index: string): string {
      var id = mainBar.panelWidgetIdAt(section, index)
      if (!id) return "unknown"
      mainBar.toggleBarWidget(id)
      return id
    }

    function call(id: string, method: string, arg: string): string {
      return shell.invokeModuleMethod(id, method, arg)
    }
  }
}
