pragma Singleton
import QtQuick
import Quickshell.Networking
import HyprVibeLauncher
import "../Models/NetworkModel.js" as Model

// Event-driven NetworkManager + C++ DBus Wi-Fi band & 802.1X EAP backend service.
QtObject {
  id: root

  signal repromptPassphrase(string ssid)

  property int activeConsumers: 0
  readonly property bool panelOpen: activeConsumers > 0

  readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  readonly property var connectedWifiNetwork: findConnectedWifiNetwork()

  property var wifiNetworks: []
  property bool scanning: false
  property bool wifiStationAvailable: false
  readonly property string bandCurrent: SystemCore.wifiBandCurrent || ""
  property string bandSelected: SystemCore.wifiBandSelected || "auto"
  readonly property var bandAvailable: SystemCore.wifiBandAvailable || []
  property string pendingBand: ""

  property string actionSsid: ""
  property string actionKind: ""
  property string failureSsid: ""
  property string failureReason: ""
  property var scannerDevice: null

  readonly property var connectionFailReasons: ({
    NoSecrets: ConnectionFailReason.NoSecrets,
    WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
    WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
    WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
    WifiClientFailed: ConnectionFailReason.WifiClientFailed
  })

  readonly property bool busy: actionKind !== ""
  readonly property var activeNetworkObj: actionSsid !== "" ? networkForSsid(actionSsid) : null
  readonly property string kind: {
    if (wiredDevice && wiredDevice.connected) return "ethernet"
    if (connectedWifiNetwork) return "wifi"
    return "disconnected"
  }
  readonly property int signalStrength: connectedWifiNetwork
    ? Math.round((connectedWifiNetwork.signalStrength || 0) * 100)
    : -1
  readonly property string icon: Model.connectionIcon(kind, signalStrength)

  readonly property bool canDisconnect: !!connectedWifiNetwork
  readonly property bool canShareWifi: kind === "wifi" && canShareNetwork(connectedWifiNetwork)
  readonly property bool canToggleWifi: networkManagerAvailable && wifiStationAvailable
  readonly property bool canScanWifi: networkManagerAvailable && wifiStationAvailable && Networking.wifiEnabled
  readonly property string toggleHint: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
  readonly property string bandEffective: pendingBand !== "" ? pendingBand : bandSelected
  readonly property bool bandPinned: bandEffective !== "auto"
  readonly property bool bandBusy: pendingBand !== ""
  readonly property bool canSelectBand: (kind === "wifi" || bandBusy) && (bandAvailable.length > 1 || bandPinned)
  readonly property bool bandPillsVisible: canSelectBand && bandPinned
  readonly property string bandSectionTitle: Model.bandSectionTitle(bandEffective, bandCurrent)

  readonly property var displayedWifiNetworks: {
    if (!wifiStationAvailable) return []
    return wifiNetworks
  }

  onWifiDeviceChanged: {
    setScannerEnabled(root.panelOpen)
    syncWifiNetworks()
  }
  onWifiNetworkObjectsChanged: if (root.panelOpen || actionKind !== "") syncWifiNetworks()

  function acquireConsumer() {
    activeConsumers += 1
    refresh(true)
  }

  function releaseConsumer() {
    activeConsumers = Math.max(0, activeConsumers - 1)
    if (activeConsumers === 0) {
      scanTimer.stop()
      scanning = false
      setScannerEnabled(false)
    }
  }

  function setScannerEnabled(enabled) {
    var nextDevice = (root.panelOpen && enabled) ? wifiDevice : null
    if (scannerDevice && scannerDevice !== nextDevice)
      scannerDevice.scannerEnabled = false
    scannerDevice = nextDevice
    if (scannerDevice) scannerDevice.scannerEnabled = true
  }

  function toggleNetwork() {
    if (!networkManagerAvailable) return
    Networking.wifiEnabled = !Networking.wifiEnabled
    Qt.callLater(function() { root.refresh(true) })
  }

  function bandLabel(band) { return Model.bandLabel(band) }
  function bandTooltip(band) { return Model.bandTooltip(band) }
  function wifiSectionTitle(index) { return Model.wifiSectionTitle(displayedWifiNetworks, index) }
  function wifiIconFor(strength) { return Model.wifiIconFor(strength) }
  function canForgetNetwork(net) { return Model.canForgetNetwork(net) }
  function requiresCredentials(security) { return Model.requiresCredentials(security, WifiSecurityType.Open, WifiSecurityType.Owe) }
  function networkFailureReason(reason, needsCreds) { return Model.networkFailureReason(reason, needsCreds, connectionFailReasons) }
  function shouldRepromptPassphrase(reason, needsCreds) { return Model.shouldRepromptPassphrase(reason, needsCreds, connectionFailReasons) }

  function canShareNetwork(net) {
    if (!net || !net.connected) return false
    return net.security !== WifiSecurityType.Wpa2Eap && net.security !== WifiSecurityType.WpaEap
  }

  function refresh(scanWifi) {
    SystemCore.refreshWifiBand()
    if (panelOpen && wifiDevice && scanWifi !== false) {
      setScannerEnabled(true)
    }
    syncWifiNetworks()
  }

  function findDevice(type) {
    var devices = networkDevices || []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }

  function findConnectedWifiNetwork() {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected) return networks[i]
    }
    return null
  }

  function syncWifiNetworks() {
    var nets = []
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      var network = networks[i]
      if (!network) continue
      checkActionCompletion(network)
      var row = Model.wifiRow(network)
      if (row) nets.push(row)
    }
    wifiNetworks = Model.sortWifiRows(nets)
    wifiStationAvailable = !!wifiDevice
  }

  function setBand(band) {
    if (!band || root.pendingBand !== "") return
    root.pendingBand = band
    SystemCore.setWifiBand(band)
  }

  function networkForSsid(ssid) {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].name === ssid) return networks[i]
    }
    return null
  }

  function wifiIndexForSsid(ssid) {
    for (var i = 0; i < wifiNetworks.length; i++) {
      if (wifiNetworks[i] && wifiNetworks[i].ssid === ssid) return i
    }
    return -1
  }

  function runNetworkAction(kind, network, callback) {
    if (actionKind !== "" || !network) return
    actionSsid = network.name || ""
    actionKind = kind
    failureSsid = ""
    failureReason = ""
    callback(network)
    actionTimeout.restart()
  }

  function clearNetworkAction() {
    actionTimeout.stop()
    failureSsid = ""
    failureReason = ""
    actionSsid = ""
    actionKind = ""
    SystemCore.refreshWifiBand()
  }

  function failNetworkAction(network, reason) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    actionTimeout.stop()
    failureSsid = actionSsid
    failureReason = networkFailureReason(reason, requiresCredentials(network.security))
    actionSsid = ""
    actionKind = ""
    SystemCore.refreshWifiBand()
  }

  function checkActionCompletion(network) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    if (actionKind === "connect" && network.connected) clearNetworkAction()
    else if (actionKind === "disconnect" && !network.connected && !network.stateChanging) clearNetworkAction()
    else if (actionKind === "forget" && !network.known && !network.stateChanging) clearNetworkAction()
  }

  function connectDirectly(ssid) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connect() })
  }

  function connectWithPassphrase(ssid, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connectWithPsk(passphrase) })
  }

  function connectEnterprise(ssid, identity, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function() {
      SystemCore.connectWifiEnterprise(ssid, identity, passphrase)
    })
  }

  function disconnect(network) {
    runNetworkAction("disconnect", network || connectedWifiNetwork, function(net) { net.disconnect() })
  }

  function disconnectRow(ssid) {
    var network = networkForSsid(ssid)
    if (network) disconnect(network)
  }

  function forget(net) {
    runNetworkAction("forget", net ? networkForSsid(net.ssid) : null, function(network) { network.forget() })
  }

  function scanWifiNetworks() {
    if (!canScanWifi || scanning) return
    scanning = true
    if (wifiDevice) {
      wifiDevice.scannerEnabled = false
      Qt.callLater(function() { if (root.panelOpen && root.wifiDevice) root.wifiDevice.scannerEnabled = true })
    }
    scanTimer.restart()
  }

  property Connections dbusConn: Connections {
    target: SystemCore
    function onWifiBandUpdated() {
      root.bandSelected = SystemCore.wifiBandSelected || "auto"
    }
    function onWifiBandSetFinished(success, error) {
      if (success && root.pendingBand !== "") root.bandSelected = root.pendingBand
      root.pendingBand = ""
      SystemCore.refreshWifiBand()
    }
    function onWifiEnterpriseFinished(ssid, success, error) {
      if (root.actionKind !== "connect" || root.actionSsid !== ssid) return
      if (success) {
        root.clearNetworkAction()
      } else {
        var net = root.networkForSsid(ssid)
        var lower = String(error || "").toLowerCase()
        var reason = (lower.indexOf("secret") !== -1 || lower.indexOf("auth") !== -1 || lower.indexOf("password") !== -1)
          ? ConnectionFailReason.WifiAuthTimeout
          : ConnectionFailReason.WifiClientFailed
        root.failNetworkAction(net, reason)
      }
    }
  }

  property Connections activeNetworkConn: Connections {
    target: root.activeNetworkObj
    function onConnectionFailed(reason) {
      var net = root.activeNetworkObj
      var ssid = root.actionSsid
      var ours = root.actionKind === "connect" && ssid !== ""
      var needsCreds = net ? root.requiresCredentials(net.security) : false
      root.failNetworkAction(net, reason)
      if (ours && root.shouldRepromptPassphrase(reason, needsCreds)) root.repromptPassphrase(ssid)
    }
    function onConnectedChanged() { if (root.activeNetworkObj) root.checkActionCompletion(root.activeNetworkObj) }
    function onKnownChanged() { if (root.activeNetworkObj) root.checkActionCompletion(root.activeNetworkObj) }
    function onStateChangingChanged() { if (root.activeNetworkObj) root.checkActionCompletion(root.activeNetworkObj) }
  }

  property Timer scanTimer: Timer {
    interval: 2500
    repeat: false
    onTriggered: {
      root.scanning = false
      root.syncWifiNetworks()
    }
  }

  property Timer actionTimeout: Timer {
    interval: 30000
    repeat: false
    onTriggered: {
      if (!root.actionKind) return
      var reason
      if (root.actionKind === "connect") reason = "Timed out connecting"
      else if (root.actionKind === "disconnect") reason = "Timed out disconnecting"
      else reason = "Timed out forgetting"
      root.failureSsid = root.actionSsid
      root.failureReason = reason
      root.actionSsid = ""
      root.actionKind = ""
      SystemCore.refreshWifiBand()
    }
  }

  Component.onCompleted: syncWifiNetworks()
  Component.onDestruction: if (scannerDevice) scannerDevice.scannerEnabled = false
}
