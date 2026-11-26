pragma Singleton
import QtQuick
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import HyprVibeLauncher
import "../Models/BluetoothModel.js" as Model

// Event-driven BlueZ + C++ Agent1 + rfkill + reactive PipeWire sink auto-switch service.
QtObject {
  id: root

  signal listsUpdated()

  property int activeConsumers: 0
  readonly property bool panelOpen: activeConsumers > 0

  property var pendingActions: ({})
  property bool owesDiscoveryStop: false
  property bool scanning: false
  property var pendingAudioOutputDevice: null
  property string pairPromptAddress: ""
  property string pairPromptType: ""
  property string pairPromptPasskey: ""
  property string pairPinText: ""

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []

  readonly property var deviceGroups: Model.deviceLists(devices)
  readonly property var connectedDevices: deviceGroups.connected || []
  readonly property var knownDevices: deviceGroups.known || []
  readonly property var discoveredDevices: deviceGroups.discovered || []

  readonly property bool canToggleBluetooth: !!root.adapter
  readonly property bool canScanBluetooth: !!root.adapter && root.adapter.enabled
  readonly property string toggleHint: root.adapter && root.adapter.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"

  readonly property string icon: {
    if (!adapter) return ""
    if (!adapter.enabled) return "󰂲"
    if (connectedDevices.length > 0) return "󰂱"
    return "󰂯"
  }

  readonly property var connectedRows: {
    var rows = []
    for (var i = 0; i < connectedDevices.length; i++)
      rows.push(Model.deviceRow(connectedDevices[i]))
    return rows
  }

  readonly property var scrollRows: {
    var rows = []
    for (var k = 0; k < knownDevices.length; k++)
      rows.push({ dev: Model.deviceRow(knownDevices[k]), section: "known", indexInSection: k })
    if (sectionVisible("discovered"))
      for (var d = 0; d < discoveredDevices.length; d++)
        rows.push({ dev: Model.deviceRow(discoveredDevices[d]), section: "discovered", indexInSection: d })
    return rows
  }

  onConnectedDevicesChanged: { syncPendingActions(); listsUpdated() }
  onKnownDevicesChanged: { syncPendingActions(); listsUpdated() }
  onDiscoveredDevicesChanged: { syncPendingActions(); listsUpdated() }
  onPipewireNodesChanged: if (pendingAudioOutputDevice) switchPendingAudioOutput()

  function ensureDiscoveryActive() {
    if (!panelOpen || !adapter || !adapter.enabled) return
    if (!adapter.discovering) {
      owesDiscoveryStop = true
      adapter.discovering = true
    }
  }

  function acquireConsumer() {
    activeConsumers += 1
    if (adapter !== null && adapter.discovering) owesDiscoveryStop = true
    ensureDiscoveryActive()
  }

  function releaseConsumer() {
    activeConsumers = Math.max(0, activeConsumers - 1)
    if (activeConsumers === 0) {
      SystemCore.cancelBluetoothPair()
      if (pairPromptAddress !== "") setPendingAction(pairPromptAddress, "")
      clearPairState()
      if (owesDiscoveryStop && adapter && adapter.discovering) {
        adapter.discovering = false
        owesDiscoveryStop = false
      }
    }
  }

  function clearPairState() {
    pairPromptAddress = ""
    pairPromptType = ""
    pairPromptPasskey = ""
    pairPinText = ""
  }

  function deviceLabel(device) { return Model.deviceLabel(device) }
  function isUuidLike(value) { return Model.isUuidLike(value) }
  function isAddressLike(value) { return Model.isAddressLike(value) }
  function hasHumanName(device) { return Model.hasHumanName(device) }

  function sectionCount(section) {
    if (section === "connected") return connectedDevices.length
    if (section === "known") return knownDevices.length
    if (section === "discovered") return discoveredDevices.length
    return 0
  }

  function sectionVisible(section) {
    if (section === "connected") return connectedDevices.length > 0
    if (section === "known") return knownDevices.length > 0
    if (section === "discovered") return !!(adapter && adapter.enabled && (adapter.discovering || discoveredDevices.length > 0)) && discoveredDevices.length > 0
    return false
  }

  readonly property var visibleSections: Model.visibleSections(deviceGroups, !!(adapter && adapter.enabled && discoveredDevices.length > 0))

  function devicesForSection(section) { return Model.sectionDevices(deviceGroups, section) }
  function deviceAt(section, index) {
    var list = devicesForSection(section)
    return index >= 0 && index < list.length ? list[index] : null
  }

  function deviceFor(row) {
    if (!row || !row.dev) return null
    var addr = row.dev.address || ""
    var devs = devices || []
    for (var i = 0; i < devs.length; i++) {
      if ((devs[i].address || "") === addr) return devs[i]
    }
    return null
  }

  function scrollSectionTitle(index) {
    var rows = scrollRows
    if (index < 0 || index >= rows.length) return ""
    if (index > 0 && rows[index - 1].section === rows[index].section) return ""
    return rows[index].section === "known" ? "PAIRED" : "AVAILABLE"
  }

  function audioSinks() {
    var sinks = []
    for (var i = 0; i < pipewireNodes.length; i++) {
      var node = pipewireNodes[i]
      if (node && node.isSink && !node.isStream) sinks.push(node)
    }
    return sinks
  }

  function bluetoothAudioSink(device) {
    var sinks = audioSinks()
    for (var i = 0; i < sinks.length; i++) {
      if (Model.bluetoothSinkMatchesDevice(sinks[i], device)) return sinks[i]
    }
    return null
  }

  function setDefaultAudioSink(sink) {
    if (!sink) return
    Pipewire.preferredDefaultAudioSink = sink
    if (sink.name) SystemCore.setDefaultAudioSink(String(sink.name))
  }

  function scheduleAudioOutputSwitch(device) {
    pendingAudioOutputDevice = {
      address: device && device.address ? device.address : "",
      name: device && device.name ? device.name : "",
      deviceName: device && device.deviceName ? device.deviceName : ""
    }
    audioSwitchExpiry.restart()
    switchPendingAudioOutput()
  }

  function switchPendingAudioOutput() {
    if (!pendingAudioOutputDevice) return
    var sink = bluetoothAudioSink(pendingAudioOutputDevice)
    if (sink) {
      setDefaultAudioSink(sink)
      pendingAudioOutputDevice = null
      audioSwitchExpiry.stop()
    }
  }

  function pendingAction(address) { return Model.pendingAction(pendingActions, address) }
  function setPendingAction(address, action) {
    if (!address) return
    pendingActions = Model.withPendingAction(pendingActions, address, action)
    if (action) pendingTimeout.restart()
  }

  function connectDevice(device) {
    if (!device || device.connected) return
    if (device.bonded && (device.paired || device.trusted)) {
      setPendingAction(device.address, "connecting")
      if (device.connect) device.connect()
    } else {
      startPairing(device)
    }
  }

  function disconnectDevice(device) {
    if (!device || !device.address || !device.connected) return
    setPendingAction(device.address, "disconnecting")
    if (device.disconnect) device.disconnect()
  }

  function forgetDevice(device) {
    if (!device || !device.address) return
    setPendingAction(device.address, "forgetting")
    if (device.forget) device.forget()
    SystemCore.forgetBluetoothDevice(device.address)
  }

  function syncPendingActions() {
    var next = Model.cloneMap(pendingActions)
    var changed = false
    for (var address in next) {
      var action = next[address]
      var found = null
      for (var i = 0; i < devices.length; i++) {
        var d = devices[i]
        if (d && d.address === address) { found = d; break }
      }
      var finishedConnecting = action === "connecting" && found && found.connected
      if (finishedConnecting
          || (action === "disconnecting" && found && !found.connected)
          || (action === "forgetting" && (!found || (!found.paired && !found.bonded && !found.trusted)))) {
        if (finishedConnecting) scheduleAudioOutputSwitch(found)
        delete next[address]
        changed = true
      }
    }
    if (changed) pendingActions = next
  }

  function startPairing(device) {
    if (!device || !device.address) return
    setPendingAction(device.address, "connecting")
    clearPairState()
    pairPromptAddress = device.address
    SystemCore.pairBluetoothDevice(device.address)
  }

  function confirmPairPrompt(val) {
    var response = (val !== undefined && val !== "" ? val : (pairPinText !== "" ? pairPinText : "yes"))
    SystemCore.confirmBluetoothPair(response)
    clearPairState()
  }

  function cancelPairPrompt() {
    SystemCore.cancelBluetoothPair()
    clearPairState()
  }

  function scanBluetoothDevices() {
    if (!canScanBluetooth || scanning) return
    scanning = true
    if (adapter) {
      owesDiscoveryStop = true
      adapter.discovering = true
    }
    scanTimer.restart()
  }

  function toggleBluetooth() {
    if (!adapter) return
    SystemCore.setBluetoothEnabled(!adapter.enabled)
  }

  property Connections dbusConn: Connections {
    target: SystemCore
    function onBluetoothPairPrompt(address, promptType, passkey) {
      if (promptType === "canceled") {
        root.clearPairState()
        return
      }
      if (!root.pairPromptAddress || root.pairPromptAddress.toUpperCase() === String(address).toUpperCase()) {
        root.pairPromptType = promptType || "confirmation"
        root.pairPromptPasskey = passkey || ""
      }
    }
    function onBluetoothPairFinished(address, success, error) {
      if (address) root.setPendingAction(address, "")
      root.clearPairState()
      root.syncPendingActions()
    }
  }

  property Connections adapterConn: Connections {
    target: root.adapter
    function onEnabledChanged() {
      if (root.panelOpen && root.adapter && root.adapter.enabled) root.ensureDiscoveryActive()
    }
    function onDiscoveringChanged() {
      if (!root.adapter.discovering) root.owesDiscoveryStop = false
    }
  }

  property Timer scanTimer: Timer {
    interval: 2500
    repeat: false
    onTriggered: root.scanning = false
  }

  property Timer pendingTimeout: Timer {
    interval: 20000
    repeat: false
    onTriggered: root.pendingActions = ({})
  }

  property Timer audioSwitchExpiry: Timer {
    interval: 4000
    repeat: false
    onTriggered: root.pendingAudioOutputDevice = null
  }

  Component.onDestruction: {
    SystemCore.cancelBluetoothPair()
    if (owesDiscoveryStop && adapter !== null && adapter.discovering) adapter.discovering = false
  }
}
