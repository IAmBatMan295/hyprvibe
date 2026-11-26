import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui

// Launcher-aligned Network / Wi-Fi panel bound to C++ DBus NetworkService & PanelStyle.
PanelShell {
  id: root
  moduleName: "hyprvibe.network"

  readonly property real barEdgeInset: button.barEdgeInset

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string focusSection: "wifi"
  property int headerIndex: 0
  property int bandIndex: 0
  property bool bandAutoFocused: true
  property int selectedIndex: -1
  property bool wifiActionFocused: false
  property bool cursorActive: false
  property string filterQuery: ""

  property string passwordSsid: ""
  property string passwordText: ""
  property string identityText: ""
  property string lastServiceActionKind: ""

  readonly property int refreshHeaderIndex: NetworkService.canScanWifi ? 0 : -1
  readonly property int toggleHeaderIndex: NetworkService.canToggleWifi ? (NetworkService.canScanWifi ? 1 : 0) : -1
  readonly property int headerActionCount: (NetworkService.canScanWifi ? 1 : 0) + (NetworkService.canToggleWifi ? 1 : 0)
  readonly property bool refreshHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === refreshHeaderIndex
  readonly property bool toggleHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === toggleHeaderIndex

  readonly property var filteredWifiNetworks: {
    var nets = NetworkService.displayedWifiNetworks || []
    var q = filterQuery.trim().toLowerCase()
    if (!q) return nets
    var out = []
    for (var i = 0; i < nets.length; i++) {
      var n = nets[i]
      if (n && String(n.ssid || "").toLowerCase().indexOf(q) >= 0) out.push(n)
    }
    return out
  }

  onHeaderActionCountChanged: clampHeaderIndex()
  onFilterQueryChanged: syncCursorAfterNetworks()

  function sectionTitleAt(idx) {
    var nets = filteredWifiNetworks
    if (idx < 0 || idx >= nets.length) return ""
    var net = nets[idx]
    if (!net) return ""
    if (net.known && idx === 0) return "KNOWN NETWORKS"
    if (!net.known && (idx === 0 || (nets[idx - 1] && nets[idx - 1].known))) return "AVAILABLE NETWORKS"
    return ""
  }

  function openPasswordPrompt(ssid) {
    if (passwordSsid !== ssid) {
      passwordText = ""
      identityText = ""
    }
    passwordSsid = ssid
  }

  function cancelPasswordPrompt() {
    passwordSsid = ""
    passwordText = ""
    identityText = ""
  }

  function clampHeaderIndex() {
    var max = Math.max(0, headerActionCount - 1)
    if (headerIndex > max) headerIndex = max
    if (headerIndex < 0) headerIndex = 0
  }

  function selectHeaderByDelta(delta) {
    headerIndex = Math.max(0, Math.min(headerActionCount - 1, headerIndex + delta))
  }

  function activateHeader() {
    if (headerIndex === refreshHeaderIndex) NetworkService.scanWifiNetworks()
    else if (headerIndex === toggleHeaderIndex) NetworkService.toggleNetwork()
  }

  function setHeaderCursor(index) {
    cursorActive = true
    focusSection = "header"
    headerIndex = index
  }

  function selectBandByDelta(delta) {
    bandIndex = Math.max(0, Math.min(NetworkService.bandAvailable.length - 1, bandIndex + delta))
  }

  function activateBand() {
    if (bandAutoFocused) {
      toggleBandAuto()
      return
    }
    if (bandIndex < 0 || bandIndex >= NetworkService.bandAvailable.length) return
    NetworkService.setBand(NetworkService.bandAvailable[bandIndex])
  }

  function toggleBandAuto() {
    if (NetworkService.bandSelected !== "auto") {
      NetworkService.setBand("auto")
      return
    }
    if (NetworkService.bandCurrent === "") return
    NetworkService.setBand(NetworkService.bandCurrent)
  }

  function syncBandIndex() {
    var idx = NetworkService.bandAvailable.indexOf(NetworkService.bandSelected)
    bandIndex = idx >= 0 ? idx : 0
    bandAutoFocused = !NetworkService.bandPillsVisible
  }

  function selectByDelta(delta) {
    var nets = filteredWifiNetworks
    if (nets.length === 0) { selectedIndex = -1; return }
    if (selectedIndex < 0) selectedIndex = delta > 0 ? 0 : nets.length - 1
    else selectedIndex = Math.max(0, Math.min(nets.length - 1, selectedIndex + delta))
    wifiActionFocused = false
  }

  function selectWifiActionByDelta(delta) {
    var nets = filteredWifiNetworks
    if (selectedIndex < 0 || selectedIndex >= nets.length) return
    if (!NetworkService.canForgetNetwork(nets[selectedIndex])) {
      wifiActionFocused = false
      return
    }
    if (delta > 0) wifiActionFocused = true
    else if (delta < 0) wifiActionFocused = false
  }

  function activateSelected() {
    var nets = filteredWifiNetworks
    if (NetworkService.busy || selectedIndex < 0 || selectedIndex >= nets.length) return
    var net = nets[selectedIndex]
    if (!net) return
    if (wifiActionFocused && NetworkService.canForgetNetwork(net)) { NetworkService.forget(net); return }
    if (net.connected) return
    if (NetworkService.requiresCredentials(net.security) && !net.known) { openPasswordPrompt(net.ssid); return }
    NetworkService.connectDirectly(net.ssid)
  }

  function syncCursorAfterNetworks() {
    var nets = filteredWifiNetworks
    if (nets.length === 0) {
      selectedIndex = -1
      wifiActionFocused = false
      if (focusSection === "wifi") focusSection = NetworkService.canSelectBand ? "band" : "header"
    } else if (passwordSsid !== "") {
      var passwordIndex = -1
      for (var i = 0; i < nets.length; i++) {
        if (nets[i] && nets[i].ssid === passwordSsid) { passwordIndex = i; break }
      }
      if (passwordIndex >= 0) {
        selectedIndex = passwordIndex
        focusSection = "wifi"
      }
    } else if (selectedIndex >= nets.length) {
      selectedIndex = nets.length - 1
    } else if (selectedIndex < 0 && opened) {
      selectedIndex = 0
    }
    if (selectedIndex < 0 || selectedIndex >= nets.length || !NetworkService.canForgetNetwork(nets[selectedIndex])) {
      wifiActionFocused = false
    }
  }

  onOpenedChanged: {
    if (opened) {
      NetworkService.acquireConsumer()
      filterQuery = ""
      var nets = filteredWifiNetworks
      selectedIndex = nets.length > 0 ? 0 : -1
      wifiActionFocused = false
      focusSection = nets.length > 0 ? "wifi" : (NetworkService.canSelectBand ? "band" : "header")
      syncBandIndex()
      cursorActive = false
    } else {
      filterQuery = ""
      cancelPasswordPrompt()
      NetworkService.releaseConsumer()
    }
  }

  onPasswordSsidChanged: {
    if (passwordSsid === "" && opened) {
      passwordText = ""
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  Connections {
    target: NetworkService
    function onWifiNetworksChanged() { root.syncCursorAfterNetworks() }
    function onBandAvailableChanged() {
      if (root.bandIndex > NetworkService.bandAvailable.length - 1)
        root.bandIndex = Math.max(0, NetworkService.bandAvailable.length - 1)
    }
    function onCanSelectBandChanged() {
      if (!NetworkService.canSelectBand && root.focusSection === "band") {
        root.focusSection = root.filteredWifiNetworks.length > 0 ? "wifi" : "header"
        root.bandAutoFocused = true
      }
    }
    function onBandPillsVisibleChanged() {
      if (!NetworkService.bandPillsVisible) root.bandAutoFocused = true
    }
    function onRepromptPassphrase(ssid) {
      root.openPasswordPrompt(ssid)
    }
    function onActionKindChanged() {
      if (root.lastServiceActionKind === "connect" && NetworkService.actionKind === "" && NetworkService.failureReason === "") {
        root.cancelPasswordPrompt()
      }
      root.lastServiceActionKind = NetworkService.actionKind
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: NetworkService.icon
    tooltipText: NetworkService.kind === "wifi"
      ? ((NetworkService.connectedWifiNetwork ? NetworkService.connectedWifiNetwork.name : "Wi-Fi")
        + (NetworkService.signalStrength >= 0 ? " (" + NetworkService.signalStrength + "%)" : ""))
      : (NetworkService.kind === "ethernet" ? "Ethernet Connected" : "Disconnected")

    onPressed: function(b) {
      if (b !== Qt.LeftButton) return
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, panel.maxPanelContentHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.passwordSsid !== "" || filterBar.inputActiveFocus

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          if (dy >= 0) return
        }
        if (dy !== 0) {
          if (root.focusSection === "header") {
            if (dy > 0) {
              if (NetworkService.canSelectBand) {
                root.focusSection = "band"
                root.bandAutoFocused = true
              } else if (root.filteredWifiNetworks.length > 0) {
                root.focusSection = "wifi"
                if (root.selectedIndex < 0) root.selectedIndex = 0
              }
            }
          } else if (root.focusSection === "band") {
            if (dy < 0) {
              if (!root.bandAutoFocused) {
                root.bandAutoFocused = true
              } else if (root.headerActionCount > 0) {
                root.focusSection = "header"
                root.headerIndex = 0
              }
            } else if (root.bandAutoFocused && NetworkService.bandPillsVisible) {
              root.bandAutoFocused = false
            } else if (root.filteredWifiNetworks.length > 0) {
              root.focusSection = "wifi"
              if (root.selectedIndex < 0) root.selectedIndex = 0
            }
          } else {
            if (dy < 0 && root.selectedIndex <= 0) {
              if (NetworkService.canSelectBand) {
                root.focusSection = "band"
                root.bandAutoFocused = !NetworkService.bandPillsVisible
              } else if (root.headerActionCount > 0) {
                root.focusSection = "header"
                root.headerIndex = 0
              }
              root.wifiActionFocused = false
            } else {
              root.selectByDelta(dy)
            }
          }
        }
        if (dx !== 0) {
          if (root.focusSection === "header") root.selectHeaderByDelta(dx)
          else if (root.focusSection === "band") { if (!root.bandAutoFocused) root.selectBandByDelta(dx) }
          else if (root.focusSection === "wifi") root.selectWifiActionByDelta(dx)
        }
      }

      onActivateRequested: {
        if (root.cursorActive) {
          if (root.focusSection === "header") root.activateHeader()
          else if (root.focusSection === "band") root.activateBand()
          else root.activateSelected()
        }
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "/") filterBar.focusInput()
        else if (t === "r" || t === "R") NetworkService.scanWifiNetworks()
        else if (t === "w" || t === "W") NetworkService.toggleNetwork()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        PanelHeaderBar {
          id: headerBar
          iconText: NetworkService.icon
          iconDimmed: !NetworkService.networkManagerAvailable
          titleText: {
            if (NetworkService.kind === "wifi") return (NetworkService.connectedWifiNetwork ? NetworkService.connectedWifiNetwork.name : "") || "Wi-Fi"
            if (NetworkService.kind === "ethernet") return "Ethernet"
            return NetworkService.kind === "disconnected" ? "Disconnected" : "No connection"
          }

          PanelActionButton {
            visible: NetworkService.canScanWifi
            enabled: !NetworkService.scanning
            iconText: ""
            tooltipText: "Scan networks (r)"
            hasCursor: root.refreshHeaderHasCursor
            foreground: PanelStyle.foreground
            accent: PanelStyle.accent
            bordered: false
            borderHoverOnly: true
            onHovered: function(on) { if (on) root.setHeaderCursor(root.refreshHeaderIndex) }
            onClicked: NetworkService.scanWifiNetworks()
          }

          ToggleSwitch {
            id: powerSwitch
            visible: NetworkService.canToggleWifi
            checked: Networking.wifiEnabled
            hasCursor: root.toggleHeaderHasCursor
            foreground: PanelStyle.foreground
            trackHeight: Math.round(Style.spacing.controlHeight * 0.48)
            cursorPad: Style.space(3)
            onHovered: function(on) { if (on) root.setHeaderCursor(root.toggleHeaderIndex) }
            onToggled: NetworkService.toggleNetwork()

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: NetworkService.toggleHint
              fontFamily: PanelStyle.fontFamily
            }
          }
        }

        PanelSearchBar {
          id: filterBar
          visible: NetworkService.wifiStationAvailable && Networking.wifiEnabled
          placeholderText: "Filter Wi-Fi networks..."
          onTextChanged: root.filterQuery = text
          onMovePressed: function(dy) {
            root.cursorActive = true
            root.focusSection = "wifi"
            root.selectByDelta(dy)
          }
          onSubmitPressed: {
            root.cursorActive = true
            root.focusSection = "wifi"
            root.activateSelected()
          }
          onEscapePressed: {
            if (text.length > 0) clear()
            else keyCatcher.forceActiveFocus()
          }
        }

        // Compact Band selector container
        Rectangle {
          visible: NetworkService.canSelectBand
          width: parent.width
          implicitHeight: bandCol.implicitHeight + Style.space(12)
          radius: PanelStyle.cornerRadius
          color: PanelStyle.darkBackground
          border.width: 1
          border.color: PanelStyle.subtleBorder

          Column {
            id: bandCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: Math.max(bandHeader.implicitHeight, bandAutoRow.implicitHeight)

              PanelSectionHeader {
                id: bandHeader
                text: NetworkService.bandSectionTitle
                foreground: PanelStyle.foreground
                fontFamily: PanelStyle.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: bandAutoRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)

                PanelSectionHeader {
                  id: bandAutoLabel
                  text: "AUTO"
                  foreground: PanelStyle.foreground
                  fontFamily: PanelStyle.fontFamily
                  anchors.verticalCenter: parent.verticalCenter
                }

                ToggleSwitch {
                  id: bandAutoSwitch
                  trackHeight: Math.round(bandAutoLabel.font.pixelSize * 1.2)
                  cursorPad: Style.space(3)
                  anchors.verticalCenter: bandAutoLabel.verticalCenter
                  anchors.verticalCenterOffset: Math.round(bandAutoLabel.topPadding / 2)
                  checked: !NetworkService.bandPinned
                  busy: NetworkService.bandBusy
                  hasCursor: root.cursorActive && root.focusSection === "band" && root.bandAutoFocused
                  foreground: PanelStyle.foreground
                  onToggled: root.toggleBandAuto()

                  onHovered: function(isHovered) {
                    if (!isHovered) return
                    root.cursorActive = true
                    root.focusSection = "band"
                    root.bandAutoFocused = true
                  }

                  PanelToolTip {
                    visible: bandAutoSwitch.containsMouse
                    text: NetworkService.bandPinned
                      ? "Let Wi-Fi pick the band"
                      : "Stay on " + NetworkService.bandLabel(NetworkService.bandCurrent)
                    fontFamily: PanelStyle.fontFamily
                  }
                }
              }
            }

            Item {
              id: bandPillsClip
              width: parent.width
              clip: true
              visible: height > 0
              height: NetworkService.bandPillsVisible ? bandRow.implicitHeight : 0
              opacity: NetworkService.bandPillsVisible ? 1 : 0

              Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
              Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

              Row {
                id: bandRow
                width: parent.width
                spacing: Style.space(6)

                readonly property int count: Math.max(1, NetworkService.bandAvailable.length)
                readonly property real cellWidth: (width - spacing * (count - 1)) / count

                Repeater {
                  model: NetworkService.bandAvailable

                  delegate: Item {
                    required property var modelData
                    required property int index
                    width: bandRow.cellWidth
                    height: bandPill.implicitHeight

                    BandPill {
                      id: bandPill
                      band: modelData
                      slot: index
                      width: parent.width
                    }
                  }
                }
              }
            }
          }
        }

        ListView {
          id: networkList
          visible: NetworkService.wifiStationAvailable && root.filteredWifiNetworks.length > 0
          width: parent.width
          height: Math.min(contentHeight, panel.maxListViewportHeight(panel.nonScrollChildrenHeight(column, networkList)))
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ScrollBar.vertical: PanelScrollBar {
            id: networkScroll
            policy: networkList.contentHeight > networkList.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          }

          model: root.filteredWifiNetworks
          currentIndex: root.selectedIndex
          onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

          delegate: Item {
            required property var modelData
            required property int index
            readonly property string sectionTitle: root.sectionTitleAt(index)
            width: ListView.view.width - (networkScroll.visible ? networkScroll.width + Style.space(6) : 0)
            height: delegateColumn.implicitHeight

            Column {
              id: delegateColumn
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                visible: sectionTitle !== ""
                text: sectionTitle
                foreground: PanelStyle.foreground
                fontFamily: PanelStyle.fontFamily
              }

              NetworkRow {
                id: row
                width: parent.width
                net: modelData
                index: parent.parent.index
              }
            }
          }
        }

        Text {
          visible: NetworkService.wifiStationAvailable && root.filteredWifiNetworks.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: GlitchBus.panelText(Networking.wifiEnabled
            ? (root.filterQuery.trim() !== "" ? "No matching Wi-Fi networks" : "Scanning for Wi-Fi networks…")
            : "Wi-Fi is disabled")
          color: PanelStyle.mutedText
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.smallSize
        }
      }
    }
  }

  component BandPill: Button {
    id: pill
    required property string band
    required property int slot

    text: NetworkService.bandLabel(band)
    tooltipText: NetworkService.bandTooltip(band)
    fontSize: PanelStyle.smallSize
    foreground: PanelStyle.foreground
    fontFamily: PanelStyle.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true

    active: NetworkService.bandCurrent === band
    selected: NetworkService.bandEffective === band
    hasCursor: root.cursorActive && root.focusSection === "band"
      && !root.bandAutoFocused && root.bandIndex === slot

    onClicked: NetworkService.setBand(band)

    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = "band"
      root.bandIndex = pill.slot
    }
  }

  component NetworkRow: CursorSurface {
    id: row
    required property var net
    required property int index

    readonly property bool isConnected: net && net.connected
    readonly property bool isKnown: !!(net && net.known)
    readonly property bool requiresCredentials: net ? NetworkService.requiresCredentials(net.security) : false
    readonly property bool isEnterprise: net
      ? (net.security === WifiSecurityType.Wpa2Eap || net.security === WifiSecurityType.WpaEap)
      : false
    readonly property bool canForget: NetworkService.canForgetNetwork(net)
    readonly property bool isSelected: root.focusSection === "wifi" && root.selectedIndex === index
    readonly property bool forgetFocused: isSelected && root.wifiActionFocused && canForget

    hasCursor: root.cursorActive && isSelected && !root.wifiActionFocused
    current: isConnected
    pressed: rowMouse.pressed
    foreground: PanelStyle.foreground
    readonly property bool isBusy: NetworkService.actionKind !== "" && NetworkService.actionSsid === (net ? net.ssid : "")
    readonly property bool isFailed: NetworkService.failureReason !== "" && NetworkService.failureSsid === (net ? net.ssid : "")
    readonly property bool isPasswordOpen: root.passwordSsid !== "" && root.passwordSsid === (net ? net.ssid : "")

    function submitCredentials() {
      if (!net || NetworkService.busy || root.passwordText.length === 0) return
      if (!isEnterprise) return NetworkService.connectWithPassphrase(net.ssid, root.passwordText)
      if (root.identityText.length > 0) NetworkService.connectEnterprise(net.ssid, root.identityText, root.passwordText)
    }

    readonly property string statusText: {
      if (!net) return ""
      if (isPasswordOpen) return ""
      if (isBusy && NetworkService.actionKind === "connect") return "Connecting…"
      if (isBusy && NetworkService.actionKind === "disconnect") return "Disconnecting…"
      if (isBusy && NetworkService.actionKind === "forget") return "Forgetting…"
      if (isFailed) return NetworkService.failureReason || "Failed"
      if (isConnected) return "Connected"
      return ""
    }

    readonly property color statusColor: {
      if (isFailed) return root.bar.urgent
      if (row.hasCursor) return ThemeStore.accent
      if (isConnected) return ThemeStore.accent
      if (isBusy) return PanelStyle.lightForeground
      return PanelStyle.mutedText
    }

    implicitHeight: rowBody.implicitHeight + (isPasswordOpen ? passwordPanel.implicitHeight + Style.spacing.md : 0)

    MouseArea {
      id: rowMouse
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: rowBody.implicitHeight
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: row.net && !row.isConnected ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: !NetworkService.busy

      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "wifi"
        root.selectedIndex = row.index
        root.wifiActionFocused = false
      }

      onClicked: {
        if (!row.net) return
        root.cursorActive = true
        root.focusSection = "wifi"
        root.selectedIndex = row.index
        root.wifiActionFocused = false
        if (row.isConnected) return
        if (row.requiresCredentials && !row.isKnown) {
          root.openPasswordPrompt(row.net.ssid)
          return
        }
        NetworkService.connectDirectly(row.net.ssid)
      }
    }

    Item {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      implicitHeight: Math.max(networkIcon.implicitHeight, networkInfo.implicitHeight, rightActions.implicitHeight) + Style.spacing.rowPaddingX

      Text {
        id: networkIcon
        textFormat: Text.PlainText
        text: GlitchBus.panelGlyph(row.net ? NetworkService.wifiIconFor(row.net.signal) : "")
        color: row.statusColor
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.titleSize
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Row {
        id: rightActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          visible: row.requiresCredentials && !row.isKnown && !row.isConnected
          anchors.verticalCenter: parent.verticalCenter
          text: "󰌾"
          color: row.hasCursor ? ThemeStore.accent : PanelStyle.mutedText
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.subtitleSize
        }

        Item {
          id: forgetBtn
          visible: row.canForget && !row.isPasswordOpen
          implicitWidth: forgetText.implicitWidth + Style.space(12)
          implicitHeight: forgetText.implicitHeight + Style.space(6)
          anchors.verticalCenter: parent.verticalCenter

          readonly property bool hot: (forgetMouse.containsMouse || row.forgetFocused) && enabled

          BorderSurface {
            anchors.fill: parent
            visible: forgetBtn.hot
            color: forgetMouse.pressed ? Util.alpha(root.bar.urgent, 0.28) : Util.alpha(root.bar.urgent, 0.16)
            radius: PanelStyle.cornerRadius
            borderSpec: Border.flat(root.bar.urgent, 1)
            Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
          }

          Text {
            id: forgetText
            anchors.centerIn: parent
            text: GlitchBus.panelText("Forget")
            font.family: PanelStyle.fontFamily
            font.pixelSize: PanelStyle.captionSize
            font.bold: true
            color: forgetBtn.hot ? root.bar.urgent : PanelStyle.mutedText
          }

          MouseArea {
            id: forgetMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) {
              root.cursorActive = true
              root.focusSection = "wifi"
              root.selectedIndex = row.index
              root.wifiActionFocused = true
            }
            onClicked: if (row.net) NetworkService.forget(row.net)
          }
        }

        Item {
          id: disconnectBtn
          visible: row.isConnected && !row.isPasswordOpen
          implicitWidth: disconnectText.implicitWidth + Style.space(12)
          implicitHeight: disconnectText.implicitHeight + Style.space(6)
          anchors.verticalCenter: parent.verticalCenter

          readonly property bool hot: disconnectMouse.containsMouse && enabled

          BorderSurface {
            anchors.fill: parent
            visible: disconnectBtn.hot
            color: disconnectMouse.pressed ? Util.alpha(root.bar.urgent, 0.28) : Util.alpha(root.bar.urgent, 0.16)
            radius: PanelStyle.cornerRadius
            borderSpec: Border.flat(root.bar.urgent, 1)
            Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
          }

          Text {
            id: disconnectText
            anchors.centerIn: parent
            text: GlitchBus.panelText("Disconnect")
            font.family: PanelStyle.fontFamily
            font.pixelSize: PanelStyle.captionSize
            font.bold: true
            color: disconnectBtn.hot ? root.bar.urgent : PanelStyle.mutedText
          }

          MouseArea {
            id: disconnectMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: if (row.net) NetworkService.disconnectRow(row.net.ssid)
          }
        }
      }

      Column {
        id: networkInfo
        spacing: Style.space(1)
        anchors.left: networkIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: rightActions.visible ? rightActions.left : parent.right
        anchors.rightMargin: rightActions.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: GlitchBus.panelText(row.net ? (row.net.ssid || "Hidden") : "")
          color: row.hasCursor ? ThemeStore.accent : (row.isConnected ? ThemeStore.accent : PanelStyle.foreground)
          Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.bodySize
          font.bold: row.isConnected || row.hasCursor
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: GlitchBus.panelText(row.statusText)
          visible: row.statusText !== ""
          color: row.statusColor
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.captionSize
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }

    Timer {
      id: failureTimer
      interval: 2000
      running: row.isFailed && row.isPasswordOpen
      onTriggered: {
        NetworkService.failureSsid = ""
        NetworkService.failureReason = ""
        pwField.forceActiveFocus()
      }
    }

    Item {
      id: passwordPanel
      visible: row.isPasswordOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: rowMouse.bottom
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      anchors.topMargin: Style.space(4)
      implicitHeight: (idField.visible ? idField.implicitHeight + Style.space(4) : 0) + pwField.implicitHeight + Style.spacing.rowGap
      height: implicitHeight

      TextField {
        id: idField
        visible: row.isEnterprise && !row.isBusy && !row.isFailed
        anchors.left: parent.left
        anchors.right: connectPwBtn.left
        anchors.top: parent.top
        anchors.rightMargin: Style.space(6)
        placeholderText: "Identity (user@domain)"
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.bodySize
        foreground: PanelStyle.foreground
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: !row.isBusy
        text: row.isPasswordOpen ? root.identityText : ""

        onAccepted: pwField.forceActiveFocus()
        onTextChanged: if (row.isPasswordOpen && text !== root.identityText) root.identityText = text
        Keys.onEscapePressed: root.cancelPasswordPrompt()

        onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
        Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
      }

      TextField {
        id: pwField
        visible: !row.isBusy && !row.isFailed
        anchors.left: parent.left
        anchors.right: connectPwBtn.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.spacing.rowGap / 2
        anchors.rightMargin: Style.space(6)
        password: true
        placeholderText: "Passphrase"
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.bodySize
        foreground: PanelStyle.foreground
        horizontalPadding: Style.spacing.controlGap
        verticalPadding: Style.spacing.controlPaddingY
        enabled: !row.isBusy
        text: row.isPasswordOpen ? root.passwordText : ""

        onAccepted: row.submitCredentials()
        onTextChanged: if (row.isPasswordOpen && text !== root.passwordText) root.passwordText = text
        Keys.onEscapePressed: root.cancelPasswordPrompt()

        onVisibleChanged: if (visible && !row.isEnterprise) Qt.callLater(forceActiveFocus)
        Component.onCompleted: if (visible && !row.isEnterprise) Qt.callLater(forceActiveFocus)
      }

      BorderSurface {
        id: statusMsgWrapper
        visible: row.isBusy || row.isFailed
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.spacing.controlHeight
        color: PanelStyle.darkBackground
        borderSpec: Border.flat(row.isFailed ? root.bar.urgent : PanelStyle.accent, 1)
        radius: PanelStyle.cornerRadius

        Text {
          textFormat: Text.PlainText
          anchors.fill: parent
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: GlitchBus.panelText(row.isFailed ? (NetworkService.failureReason !== "" ? NetworkService.failureReason : "Connection failed") : "Connecting...")
          color: row.isFailed ? root.bar.urgent : PanelStyle.foreground
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.smallSize
        }
      }

      PanelActionButton {
        id: connectPwBtn
        visible: !row.isBusy && !row.isFailed
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        enabled: row.net && pwField.text.length > 0 && (!row.isEnterprise || idField.text.length > 0)
        iconText: "󰄬"
        tooltipText: "Connect"
        bordered: true
        foreground: PanelStyle.foreground
        hoverColor: PanelStyle.accent
        fontFamily: PanelStyle.fontFamily
        onClicked: row.submitCredentials()
      }
    }
  }
}
