import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui

// Launcher-aligned Bluetooth panel & device pairing prompt bound to C++ DBus/rfkill BluetoothService.
PanelShell {
  id: root
  moduleName: "hyprvibe.bluetooth"

  readonly property real barEdgeInset: button.barEdgeInset

  visible: BluetoothService.adapter !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string focusSection: "connected"
  property int selectedIndex: 0
  property bool actionFocused: false
  property bool cursorActive: false
  property string focusedDeviceAddress: ""
  property int headerIndex: 0

  readonly property int refreshHeaderIndex: BluetoothService.canScanBluetooth ? 0 : -1
  readonly property int toggleHeaderIndex: BluetoothService.canToggleBluetooth ? (BluetoothService.canScanBluetooth ? 1 : 0) : -1
  readonly property int headerActionCount: (BluetoothService.canScanBluetooth ? 1 : 0) + (BluetoothService.canToggleBluetooth ? 1 : 0)
  readonly property bool refreshHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === refreshHeaderIndex
  readonly property bool toggleHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === toggleHeaderIndex

  function scrollSectionTitle(index) {
    var rows = BluetoothService.scrollRows
    if (index < 0 || index >= rows.length) return ""
    if (index > 0 && rows[index - 1].section === rows[index].section) return ""
    return rows[index].section === "known" ? "PAIRED" : "AVAILABLE"
  }

  function rowsForSection(section) {
    if (section === "connected") return BluetoothService.connectedRows
    var all = BluetoothService.scrollRows
    var out = []
    for (var i = 0; i < all.length; i++) {
      if (all[i].section === section) out.push(all[i])
    }
    return out
  }

  readonly property var visibleSections: {
    var s = []
    if (BluetoothService.connectedRows.length > 0) s.push("connected")
    if (rowsForSection("known").length > 0) s.push("known")
    if (rowsForSection("discovered").length > 0) s.push("discovered")
    return s
  }

  readonly property int scrollRowIndex: {
    if (focusSection !== "known" && focusSection !== "discovered") return -1
    var rows = BluetoothService.scrollRows
    var sectionPos = 0
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].section === focusSection) {
        if (sectionPos === selectedIndex) return i
        sectionPos++
      }
    }
    return -1
  }

  function targetDeviceAt(section, index) {
    var list = rowsForSection(section)
    if (index < 0 || index >= list.length) return null
    var entry = section === "connected" ? { dev: list[index] } : list[index]
    return BluetoothService.deviceFor(entry)
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (focusSection === "header") {
      if (delta > 0 && sections && sections.length > 0) {
        focusSection = sections[0]; selectedIndex = 0; actionFocused = false
      }
      return
    }
    if (!sections || sections.length === 0) { focusSection = "header"; actionFocused = false; return }
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = 0; actionFocused = false; return }

    var idx = selectedIndex
    var max = rowsForSection(focusSection).length - 1

    if (delta > 0) {
      if (idx < max) { selectedIndex = idx + 1; actionFocused = false; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = 0
        actionFocused = false
      }
    } else {
      if (idx > 0) { selectedIndex = idx - 1; actionFocused = false; return }
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        selectedIndex = Math.max(0, rowsForSection(focusSection).length - 1)
        actionFocused = false
      } else {
        focusSection = "header"; actionFocused = false
      }
    }
  }

  function setHeaderCursor(index) {
    cursorActive = true
    focusSection = "header"
    actionFocused = false
    headerIndex = (index !== undefined) ? index : toggleHeaderIndex
  }

  function moveCursorH(delta) {
    if (!cursorActive) { cursorActive = true; return }
    if (focusSection === "header") {
      headerIndex = Math.max(0, Math.min(headerActionCount - 1, headerIndex + delta))
      return
    }
    if (focusSection !== "known" && focusSection !== "connected") return
    var dev = targetDeviceAt(focusSection, selectedIndex)
    if (!dev || !dev.address) return
    if (delta > 0) actionFocused = true
    else if (delta < 0) actionFocused = false
  }

  function activateCursor() {
    if (focusSection === "header") {
      if (headerIndex === refreshHeaderIndex) BluetoothService.scanBluetoothDevices()
      else BluetoothService.toggleBluetooth()
      return
    }
    if (actionFocused) {
      deleteSelected()
      return
    }
    var dev = targetDeviceAt(focusSection, selectedIndex)
    if (!dev) return
    if (!dev.connected) BluetoothService.connectDevice(dev)
  }

  function deleteSelected() {
    if (focusSection !== "known" && focusSection !== "connected") return
    var dev = targetDeviceAt(focusSection, selectedIndex)
    if (dev) BluetoothService.forgetDevice(dev)
  }

  function updateFocusedAddress() {
    var d = targetDeviceAt(focusSection, selectedIndex)
    focusedDeviceAddress = d ? (d.address || "") : ""
  }

  function reselectFocusedDevice() {
    if (focusedDeviceAddress === "") { clampCursor(); return }
    var sections = visibleSections
    for (var s = 0; s < sections.length; s++) {
      var section = sections[s]
      var list = rowsForSection(section)
      for (var i = 0; i < list.length; i++) {
        var devObj = section === "connected" ? list[i] : list[i].dev
        if (devObj && devObj.address === focusedDeviceAddress) {
          focusSection = section
          selectedIndex = i
          clampCursor()
          return
        }
      }
    }
    clampCursor()
  }

  function clampCursor() {
    var sections = visibleSections
    if (focusSection === "header") return
    if (!sections || !sections.length) {
      selectedIndex = 0
      return
    }
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = 0
      return
    }
    var count = rowsForSection(focusSection).length
    if (count === 0) {
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = Math.max(0, rowsForSection(focusSection).length - 1)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  onSelectedIndexChanged: updateFocusedAddress()
  onFocusSectionChanged: updateFocusedAddress()

  onOpenedChanged: {
    if (opened) {
      BluetoothService.acquireConsumer()
      var sections = visibleSections
      if (sections.length > 0) { focusSection = sections[0]; selectedIndex = 0 }
      else { focusSection = "header" }
      actionFocused = false
      cursorActive = false
    } else {
      BluetoothService.releaseConsumer()
    }
  }

  Connections {
    target: BluetoothService
    function onListsUpdated() { root.reselectFocusedDevice() }
    function onVisibleSectionsChanged() { root.clampCursor() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: BluetoothService.icon
    tooltipText: BluetoothService.adapter && !BluetoothService.adapter.enabled
      ? "Bluetooth: Disabled"
      : (BluetoothService.connectedDevices.length > 0
        ? ("Bluetooth: " + BluetoothService.connectedDevices.length + " connected")
        : "Bluetooth: No devices connected")
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
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
      blocked: BluetoothService.pairPromptAddress !== ""
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onDeleteRequested: if (root.cursorActive) root.deleteSelected()
      onTextKey: function(t) {
        if (t === "b" || t === "B") BluetoothService.toggleBluetooth()
        else if (t === "r" || t === "R") BluetoothService.scanBluetoothDevices()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        PanelHeaderBar {
          id: headerBar
          iconText: BluetoothService.icon
          iconDimmed: !(BluetoothService.adapter && BluetoothService.adapter.enabled)
          titleText: "Bluetooth"

          PanelActionButton {
            visible: BluetoothService.canScanBluetooth
            enabled: !BluetoothService.scanning
            iconText: ""
            tooltipText: "Scan for devices (r)"
            hasCursor: root.refreshHeaderHasCursor
            foreground: PanelStyle.foreground
            accent: PanelStyle.accent
            bordered: false
            borderHoverOnly: true
            onHovered: function(on) { if (on) root.setHeaderCursor(root.refreshHeaderIndex) }
            onClicked: BluetoothService.scanBluetoothDevices()
          }

          ToggleSwitch {
            id: powerSwitch
            visible: BluetoothService.canToggleBluetooth
            checked: !!BluetoothService.adapter && BluetoothService.adapter.enabled
            hasCursor: root.toggleHeaderHasCursor
            foreground: PanelStyle.foreground
            trackHeight: Math.round(Style.spacing.controlHeight * 0.48)
            cursorPad: Style.space(3)
            onHovered: function(on) { if (on) root.setHeaderCursor(root.toggleHeaderIndex) }
            onToggled: BluetoothService.toggleBluetooth()

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: BluetoothService.toggleHint
              fontFamily: PanelStyle.fontFamily
            }
          }
        }

        Column {
          id: connectedList
          visible: BluetoothService.connectedRows.length > 0
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "CONNECTED"
            foreground: PanelStyle.foreground
            fontFamily: PanelStyle.fontFamily
          }

          Repeater {
            model: BluetoothService.connectedRows
            DeviceRow {
              required property var modelData
              required property int index
              width: connectedList.width
              dev: modelData
              rowIndex: index
              sectionName: "connected"
              isDiscovered: false
            }
          }
        }

        PanelSeparator {
          visible: BluetoothService.connectedRows.length > 0 && BluetoothService.scrollRows.length > 0
          foreground: PanelStyle.foreground
        }

        ListView {
          id: deviceListView
          visible: BluetoothService.scrollRows.length > 0
          width: parent.width
          height: Math.min(contentHeight, panel.maxListViewportHeight(panel.nonScrollChildrenHeight(column, deviceListView)))
          spacing: Style.space(6)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ScrollBar.vertical: PanelScrollBar {
            id: deviceScroll
            policy: deviceListView.contentHeight > deviceListView.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          }

          model: BluetoothService.scrollRows
          currentIndex: root.scrollRowIndex
          onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(keepCurrentVisible)
          function keepCurrentVisible() {
            if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
          }

          delegate: Item {
            required property var modelData
            required property int index
            readonly property string sectionTitle: root.scrollSectionTitle(index)
            readonly property int sectionRowIdx: {
              var sec = modelData.section
              var count = 0
              for (var i = 0; i < index; i++) {
                if (BluetoothService.scrollRows[i].section === sec) count++
              }
              return count
            }

            width: ListView.view.width - (deviceScroll.visible ? deviceScroll.width + Style.space(6) : 0)
            height: delegateColumn.implicitHeight

            Column {
              id: delegateColumn
              width: parent.width
              spacing: Style.space(6)

              PanelSeparator {
                visible: index > 0 && sectionTitle !== ""
                height: visible ? implicitHeight : 0
                foreground: PanelStyle.foreground
              }

              PanelSectionHeader {
                visible: sectionTitle !== ""
                height: visible ? implicitHeight : 0
                text: sectionTitle
                foreground: PanelStyle.foreground
                fontFamily: PanelStyle.fontFamily
              }

              DeviceRow {
                width: parent.width
                dev: modelData.dev
                rowIndex: sectionRowIdx
                sectionName: modelData.section
                isDiscovered: modelData.section === "discovered"
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: BluetoothService.connectedRows.length === 0 && BluetoothService.scrollRows.length === 0
          text: GlitchBus.panelText(!BluetoothService.adapter
            ? "No Bluetooth adapter"
            : !BluetoothService.adapter.enabled
              ? "Turn Bluetooth on to scan"
              : "Scanning for devices…")
          color: PanelStyle.mutedText
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.smallSize
          wrapMode: Text.WordWrap
          width: parent.width
        }
      }
    }
  }

  component DeviceRow: CursorSurface {
    id: row
    required property var dev
    required property int rowIndex
    required property string sectionName
    required property bool isDiscovered

    readonly property bool isPromptOpen: BluetoothService.pairPromptAddress !== ""
      && BluetoothService.pairPromptAddress.toUpperCase() === String(dev ? dev.address : "").toUpperCase()
    readonly property bool isConnected: dev && dev.connected
    readonly property int devState: dev && dev.state !== undefined ? dev.state : -1
    readonly property string action: BluetoothService.pendingAction(dev ? dev.address : "")
    readonly property string actionTooltip: {
      if (!dev) return ""
      if (isConnected) return "Disconnect"
      if (isDiscovered) return "Pair"
      return "Connect"
    }

    readonly property bool rowSelected: root.cursorActive && root.focusSection === sectionName && root.selectedIndex === rowIndex
    readonly property bool forgetAvailable: (sectionName === "known" || sectionName === "connected") && !isDiscovered

    hasCursor: rowSelected && !root.actionFocused && !row.isPromptOpen
    current: isConnected
    pressed: rowMouse.pressed
    foreground: PanelStyle.foreground

    readonly property string statusText: {
      if (!dev) return ""
      if (row.isPromptOpen) return "Pairing…"
      if (action === "forgetting") return "Forgetting…"
      if (action === "disconnecting" || devState === 2) return "Disconnecting…"
      if (isConnected) {
        if (dev.batteryAvailable) return Math.round(dev.battery * 100) + "%"
        return "Connected"
      }
      if (action === "connecting" || devState === 3 || dev.pairing === true) return "Connecting…"
      return ""
    }

    readonly property color statusColor: {
      if (row.hasCursor) return ThemeStore.accent
      if (isConnected) return ThemeStore.accent
      if (action !== "" || devState === 3 || dev.pairing === true || row.isPromptOpen) return PanelStyle.foreground
      return PanelStyle.mutedText
    }

    implicitHeight: (rowContent.implicitHeight + Style.spacing.rowPaddingX)
      + (row.isPromptOpen ? (promptPanel.implicitHeight + Style.space(8)) : 0)

    MouseArea {
      id: rowMouse
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: rowContent.implicitHeight + Style.spacing.rowPaddingX
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: row.dev && !row.isConnected ? Qt.PointingHandCursor : Qt.ArrowCursor

      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = row.sectionName
        root.selectedIndex = row.rowIndex
        root.actionFocused = false
      }

      onClicked: {
        if (row.isPromptOpen) return
        var d = BluetoothService.deviceFor({ dev: row.dev })
        if (!d || row.isConnected) return
        BluetoothService.connectDevice(d)
      }
    }

    PanelToolTip {
      visible: !row.isConnected && row.actionTooltip !== "" && rowMouse.containsMouse && !root.actionFocused && !row.isPromptOpen
      text: row.actionTooltip
      fontFamily: PanelStyle.fontFamily
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.rowPaddingX / 2
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      implicitHeight: Math.max(deviceIcon.implicitHeight, info.implicitHeight, rightActions.implicitHeight)

      Text {
        id: deviceIcon
        textFormat: Text.PlainText
        text: GlitchBus.panelGlyph(row.isConnected ? "󰂱" : "󰂯")
        color: row.statusColor
        font.family: PanelStyle.fontFamily
        font.pixelSize: Style.font.heading
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: info
        spacing: Style.space(1)
        anchors.left: deviceIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: rightActions.visible ? rightActions.left : parent.right
        anchors.rightMargin: rightActions.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: GlitchBus.panelText(BluetoothService.deviceLabel(row.dev) || "Device")
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
          visible: row.statusText !== ""
          text: GlitchBus.panelText(row.statusText)
          color: row.statusColor
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.captionSize
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Row {
        id: rightActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Item {
          id: unpairBtn
          visible: row.forgetAvailable && !row.isPromptOpen
          implicitWidth: unpairText.implicitWidth + Style.space(12)
          implicitHeight: unpairText.implicitHeight + Style.space(6)
          anchors.verticalCenter: parent.verticalCenter

          readonly property bool hot: (unpairMouse.containsMouse || (row.rowSelected && root.actionFocused)) && enabled

          BorderSurface {
            anchors.fill: parent
            visible: unpairBtn.hot
            color: unpairMouse.pressed ? Util.alpha(root.bar.urgent, 0.28) : Util.alpha(root.bar.urgent, 0.16)
            radius: PanelStyle.cornerRadius
            borderSpec: Border.flat(root.bar.urgent, 1)
            Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
          }

          Text {
            id: unpairText
            anchors.centerIn: parent
            text: GlitchBus.panelText("Unpair")
            font.family: PanelStyle.fontFamily
            font.pixelSize: PanelStyle.captionSize
            font.bold: true
            color: unpairBtn.hot ? root.bar.urgent : PanelStyle.mutedText
          }

          MouseArea {
            id: unpairMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) {
              root.cursorActive = true
              root.focusSection = row.sectionName
              root.selectedIndex = row.rowIndex
              root.actionFocused = true
            }
            onClicked: {
              var d = BluetoothService.deviceFor({ dev: row.dev })
              if (d) BluetoothService.forgetDevice(d)
            }
          }
        }

        Item {
          id: disconnectBtn
          visible: row.isConnected && !row.isPromptOpen
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
            onClicked: {
              var d = BluetoothService.deviceFor({ dev: row.dev })
              if (d) BluetoothService.disconnectDevice(d)
            }
          }
        }
      }
    }

    Item {
      id: promptPanel
      visible: row.isPromptOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: rowContent.bottom
      anchors.topMargin: Style.space(4)
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      implicitHeight: promptRow.implicitHeight
      height: implicitHeight

      RowLayout {
        id: promptRow
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(6)

        TextField {
          id: pinField
          visible: BluetoothService.pairPromptType === "pin" || BluetoothService.pairPromptType === "passkey"
          Layout.fillWidth: true
          placeholderText: BluetoothService.pairPromptType === "pin" ? "Enter PIN" : "Enter Passkey"
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.smallSize
          foreground: PanelStyle.foreground
          horizontalPadding: Style.spacing.controlGap
          verticalPadding: Style.spacing.controlPaddingY
          text: BluetoothService.pairPinText
          onTextChanged: if (row.isPromptOpen && text !== BluetoothService.pairPinText) BluetoothService.pairPinText = text
          onAccepted: BluetoothService.confirmPairPrompt(text)
          Keys.onEscapePressed: BluetoothService.cancelPairPrompt()
          Component.onCompleted: Qt.callLater(forceActiveFocus)
        }

        Text {
          id: promptLabel
          visible: !(BluetoothService.pairPromptType === "pin" || BluetoothService.pairPromptType === "passkey")
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: {
            if (BluetoothService.pairPromptType === "confirmation") {
              return BluetoothService.pairPromptPasskey !== ""
                ? ("Pair code: " + BluetoothService.pairPromptPasskey)
                : "Confirm pairing?"
            }
            if (BluetoothService.pairPromptType === "display" || BluetoothService.pairPromptType === "display_pin") {
              return "Code on device: " + BluetoothService.pairPromptPasskey
            }
            if (BluetoothService.pairPromptType === "authorize") {
              return "Authorize connection?"
            }
            return "Initiating pairing…"
          }
          color: PanelStyle.foreground
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.smallSize
          font.bold: true
          elide: Text.ElideRight
        }

        Button {
          text: "Cancel"
          iconText: "󰅙"
          bordered: true
          foreground: PanelStyle.foreground
          fontSize: PanelStyle.captionSize
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(3)
          onClicked: BluetoothService.cancelPairPrompt()
        }

        Button {
          visible: BluetoothService.pairPromptType !== "display" && BluetoothService.pairPromptType !== "display_pin"
          text: "Pair"
          iconText: "󰄬"
          bordered: true
          foreground: PanelStyle.foreground
          fontSize: PanelStyle.captionSize
          horizontalPadding: Style.space(8)
          verticalPadding: Style.space(3)
          enabled: (BluetoothService.pairPromptType !== "pin" && BluetoothService.pairPromptType !== "passkey")
            || pinField.text.length > 0
          onClicked: BluetoothService.confirmPairPrompt(pinField.text)
        }
      }
    }
  }
}
