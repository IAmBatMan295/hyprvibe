import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Frontend.Styles
import qs.Frontend.Ui

// Single modular, capability-driven launcher surface ready for global & per-component GUI theming.
// Supports fast keyboard navigation (Ctrl+N/P/J/K/G, Tab complete, Shift+Return custom, Alt+1..9 quick pick),
// dynamic fonts/radii/borders/animations from shell.toml, and zero-fallback-warning icon resolution.
Rectangle {
  id: root

  required property var model
  property var palette: LauncherStyle.palette

  // Global + per-component typography & styling (wired cleanly from shell.toml [font]/[effects]/[launcher])
  property string fontFamily: "JetBrainsMono Nerd Font"
  property int fontBaseSize: 13
  property int borderWidth: 3
  property int borderRadius: 0
  property string animationStyle: "none" // "none" | "fade" | "pop"
  property int animationDurationMs: 110

  // Toggleable layout & behavior capabilities
  property string presetName: "drun"
  property bool showSearch: true
  property bool showNumbers: false
  property bool showIcons: true
  property bool showSubtext: true
  property bool showPrompt: true
  property bool centerText: false
  property bool allowCustomInput: false
  property bool onlyMatch: false
  property bool dynamicHeight: false
  property bool showFooter: true
  property string resultFormat: "s"

  property string promptText: ""
  property string headerIcon: ""
  property string placeholderText: "Type to filter..."
  property int cardWidth: 480
  property int visibleLines: 6
  property int rowHeight: 40
  property int initialRow: 0
  property bool benchAutoAck: false
  property int selectedRow: 0
  property real _hoverAnchorX: -1
  property real _hoverAnchorY: -1
  property bool _hoverMoved: false

  signal accepted(string actionValue, string label, int rowIndex)
  signal cancelled()
  signal clearRequested()
  signal viewReadyForBench()

  readonly property color colBg: palette.background
  readonly property color colDark: palette.dark_background
  readonly property color colLightBg: palette.lighter_background
  readonly property color colAccent: palette.accent
  readonly property color colSelection: palette.selection
  readonly property color colMuted: palette.muted
  readonly property color colFg: palette.foreground
  readonly property color colFgLight: palette.light_foreground
  readonly property color colRed: palette.red
  readonly property color colYellow: palette.yellow

  readonly property int rowSlots: root.dynamicHeight
                                  ? Math.max(1, Math.min(root.visibleLines, Math.max(1, root.model.count)))
                                  : Math.max(1, root.visibleLines)
  readonly property int searchAreaHeight: root.showSearch ? Math.max(40, root.fontBaseSize + 28) : 0
  readonly property int searchSepHeight: root.showSearch ? 14 : 0
  readonly property int headerOnlyHeight: (!root.showSearch && root.showPrompt && root.promptText.length > 0) ? 48 : 0
  readonly property int footerAreaHeight: root.showFooter ? 30 : 0

  width: root.cardWidth
  height: 32 + root.searchAreaHeight + root.searchSepHeight + root.headerOnlyHeight
          + (root.rowSlots * root.rowHeight) + root.footerAreaHeight
  radius: root.borderRadius
  color: root.colBg
  border.width: root.borderWidth
  border.color: root.colAccent
  focus: true
  clip: true
  transformOrigin: Item.Center

  NumberAnimation {
    id: openAnim
    target: root
    duration: Math.max(40, root.animationDurationMs)
    easing.type: Easing.OutCubic
  }

  function playOpenAnimation(): void {
    openAnim.stop()
    if (root.animationStyle === "fade") {
      root.scale = 1.0
      root.opacity = 0.0
      openAnim.property = "opacity"
      openAnim.from = 0.0
      openAnim.to = 1.0
      openAnim.start()
    } else if (root.animationStyle === "pop") {
      root.opacity = 1.0
      root.scale = 0.96
      openAnim.property = "scale"
      openAnim.from = 0.96
      openAnim.to = 1.0
      openAnim.start()
    } else {
      root.opacity = 1.0
      root.scale = 1.0
    }
  }

  function focusDefault(): void {
    if (root.showSearch) {
      searchInput.focus = true
      searchInput.forceActiveFocus()
    } else {
      listView.focus = true
      listView.forceActiveFocus()
    }
  }

  function disarmHover(): void {
    root._hoverMoved = false
    root._hoverAnchorX = listHover.point.scenePosition.x
    root._hoverAnchorY = listHover.point.scenePosition.y
  }

  function moveSelection(delta: int): void {
    root.disarmHover()
    listView._scrollAnimating = false
    const n = root.model.count
    if (n <= 0) return
    let next = root.selectedRow + delta
    if (next < 0) next = 0
    if (next >= n) next = n - 1
    root.selectedRow = next
    listView.positionViewAtIndex(next, ListView.Contain)
    listView._targetScrollY = listView.contentY
  }

  function triggerRow(row: int): void {
    if (row >= 0 && row < root.model.count) {
      const info = root.model.rowAt(row)
      root.model.recordLaunch(info.actionValue)
      const formatted = root.model.formatSelection(row, root.resultFormat)
      root.accepted(formatted, info.label, row)
      return
    }
    if (!root.onlyMatch && root.allowCustomInput && root.showSearch && searchInput.text.length > 0) {
      root.accepted(searchInput.text, searchInput.text, -1)
    }
  }

  function handleKey(event): void {
    const k = event.key
    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    const shift = (event.modifiers & Qt.ShiftModifier) !== 0
    const alt = (event.modifiers & Qt.AltModifier) !== 0

    if (k === Qt.Key_Escape || (ctrl && k === Qt.Key_G)) {
      event.accepted = true
      root.cancelled()
    } else if (ctrl && k === Qt.Key_C && root.presetName === "clipboard") {
      event.accepted = true
      root.clearRequested()
    } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      event.accepted = true
      if (shift && !root.onlyMatch && root.showSearch && searchInput.text.length > 0) {
        root.accepted(searchInput.text, searchInput.text, -1)
      } else {
        root.triggerRow(root.selectedRow)
      }
    } else if (k === Qt.Key_Tab && root.showSearch && root.selectedRow >= 0) {
      event.accepted = true
      const lbl = root.model.labelAt(root.selectedRow)
      if (lbl.length > 0) {
        searchInput.text = lbl
        searchInput.cursorPosition = lbl.length
      }
    } else if (k === Qt.Key_Down || (ctrl && (k === Qt.Key_N || k === Qt.Key_J))) {
      event.accepted = true
      root.moveSelection(1)
    } else if (k === Qt.Key_Up || (ctrl && (k === Qt.Key_P || k === Qt.Key_K))) {
      event.accepted = true
      root.moveSelection(-1)
    } else if (k === Qt.Key_PageDown) {
      event.accepted = true
      root.moveSelection(Math.max(1, root.visibleLines - 1))
    } else if (k === Qt.Key_PageUp) {
      event.accepted = true
      root.moveSelection(-Math.max(1, root.visibleLines - 1))
    } else if (k === Qt.Key_Home && (!root.showSearch || ctrl)) {
      event.accepted = true
      root.moveSelection(-root.model.count)
    } else if (k === Qt.Key_End && (!root.showSearch || ctrl)) {
      event.accepted = true
      root.moveSelection(root.model.count)
    } else if (alt && root.showNumbers && k >= Qt.Key_1 && k <= Qt.Key_9) {
      event.accepted = true
      const idx = k - Qt.Key_1
      if (idx < root.model.count) root.triggerRow(idx)
    }
  }

  function prepareOpen(animate: bool): void {
    const startIdx = Math.max(0, Math.min(root.initialRow, root.model.count - 1))
    root.disarmHover()
    listView._scrollAnimating = false
    root.selectedRow = startIdx
    if (startIdx > 0) listView.positionViewAtIndex(startIdx, ListView.Center)
    else if (startIdx === 0) listView.positionViewAtIndex(0, ListView.Beginning)
    listView._targetScrollY = listView.contentY
    if (root.model.query !== searchInput.text) {
      searchInput.text = root.model.query
    }
    root.focusDefault()
    if (animate) root.playOpenAnimation()
    if (root.benchAutoAck) {
      Qt.callLater(root.viewReadyForBench)
    }
  }

  Component.onCompleted: root.prepareOpen(false)

  Connections {
    target: root.model
    function onModelReset(): void {
      root.disarmHover()
      listView._scrollAnimating = false
      root.selectedRow = root.model.count > 0 ? 0 : -1
      if (root.selectedRow === 0) listView.positionViewAtIndex(0, ListView.Beginning)
      listView._targetScrollY = listView.contentY
    }
    function onCountChanged(): void {
      if (root.model.count <= 0) {
        root.selectedRow = -1
      } else if (root.model.query.length > 0 || root.selectedRow < 0 || root.selectedRow >= root.model.count) {
        root.disarmHover()
        listView._scrollAnimating = false
        root.selectedRow = 0
        listView.positionViewAtIndex(0, ListView.Beginning)
        listView._targetScrollY = listView.contentY
      }
    }
    function onTotalCountChanged(): void {
      if (root.visible && root.model.totalCount > 0) {
        Qt.callLater(() => root.prepareOpen(false))
      }
    }
  }

  Keys.onPressed: event => root.handleKey(event)

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 16
    spacing: 0

    Rectangle {
      visible: root.showSearch
      Layout.fillWidth: true
      Layout.preferredHeight: root.searchAreaHeight
      radius: root.borderRadius > 0 ? Math.max(2, root.borderRadius - 2) : 0
      color: root.colDark
      border.width: 2
      border.color: searchInput.activeFocus ? root.colAccent : root.colSelection

      RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
          visible: root.showPrompt && root.promptText.length > 0
          Layout.preferredHeight: root.searchAreaHeight - 4
          Layout.preferredWidth: Math.max(root.searchAreaHeight - 4, promptLabel.implicitWidth + 16)
          radius: root.borderRadius > 0 ? Math.max(1, root.borderRadius - 3) : 0
          color: root.colSelection

          Text {
            id: promptLabel
            anchors.centerIn: parent
            text: root.promptText
            textFormat: Text.PlainText
            color: root.colAccent
            font.family: root.fontFamily
            font.pixelSize: Math.max(10, root.fontBaseSize)
            font.bold: true
          }

          Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 2
            color: root.colSelection
          }
        }

        TextInput {
          id: searchInput
          Layout.fillWidth: true
          Layout.leftMargin: 12
          Layout.rightMargin: 12
          Layout.alignment: Qt.AlignVCenter
          color: root.colFgLight
          selectionColor: root.colSelection
          selectedTextColor: root.colFgLight
          font.family: root.fontFamily
          font.pixelSize: root.fontBaseSize
          clip: true
          verticalAlignment: TextInput.AlignVCenter

          onTextChanged: root.model.query = text
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: event => root.handleKey(event)

          Text {
            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            text: root.placeholderText
            textFormat: Text.PlainText
            color: root.colMuted
            font: searchInput.font
            visible: searchInput.text.length === 0
            opacity: searchInput.activeFocus ? 0.55 : 0.85
          }
        }
      }
    }

    Item {
      visible: root.showSearch
      Layout.fillWidth: true
      Layout.preferredHeight: root.showSearch ? 14 : 0

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 2
        antialiasing: false
        color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.48)
      }
    }

    Item {
      visible: !root.showSearch && root.showPrompt && root.promptText.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: visible ? 48 : 0

      Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: 10
        radius: root.borderRadius > 0 ? Math.max(2, root.borderRadius - 2) : 0
        color: root.colDark
        border.width: 2
        border.color: root.colSelection

        RowLayout {
          anchors.fill: parent
          spacing: 0

          Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: height
            color: root.colSelection

            Text {
              anchors.centerIn: parent
              text: root.headerIcon.length > 0 ? root.headerIcon : ""
              textFormat: Text.PlainText
              color: root.colAccent
              font.family: root.fontFamily
              font.pixelSize: Math.max(11, root.fontBaseSize + 1)
            }

            Rectangle {
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 2
              color: root.colSelection
            }
          }

          Text {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            horizontalAlignment: root.centerText ? Text.AlignHCenter : Text.AlignLeft
            text: root.promptText
            textFormat: Text.PlainText
            color: root.colFgLight
            font.family: root.fontFamily
            font.pixelSize: root.fontBaseSize
            font.bold: true
            elide: Text.ElideRight
          }
        }
      }
    }

    Item {
      id: listBox
      Layout.fillWidth: true
      Layout.fillHeight: true

      ListView {
        id: listView
        property real _targetScrollY: 0
        property bool _scrollAnimating: false
        readonly property real maxScrollY: Math.max(0, Math.max(contentHeight, root.model.count * root.rowHeight) - height)

        anchors.fill: parent
        clip: true
        focus: !root.showSearch
        interactive: false
        reuseItems: false
        cacheBuffer: root.rowHeight * 6
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: -1
        highlightFollowsCurrentItem: false
        model: root.model
        Keys.onPressed: event => root.handleKey(event)

        ScrollBar.vertical: PanelScrollBar {
          id: launcherScroll
          policy: listView.contentHeight > listView.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          onPressedChanged: if (pressed) listView._scrollAnimating = false
          onPositionChanged: if (pressed) listView._targetScrollY = listView.contentY
        }

        delegate: Item {
          id: rowDelegate
          required property int index
          required property string label
          required property string highlightedLabel
          required property string subtext
          required property string icon
          required property string actionValue
          required property bool isActive
          required property int rowNumber

          readonly property bool isCurrent: rowDelegate.index === root.selectedRow

          width: listView.width - (launcherScroll.visible ? launcherScroll.width + 6 : 0)
          height: root.rowHeight

          Rectangle {
            anchors.fill: parent
            z: -1
            visible: rowDelegate.isCurrent
            radius: root.borderRadius > 0 ? Math.max(2, root.borderRadius - 3) : 0
            color: root.colSelection
            border.width: 2
            border.color: root.colAccent
          }

          RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 10

          Text {
            visible: root.showNumbers
            Layout.preferredWidth: Math.max(22, implicitWidth)
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            text: rowDelegate.rowNumber
            textFormat: Text.PlainText
            color: root.colFg
            font.family: root.fontFamily
            font.pixelSize: Math.max(9, root.fontBaseSize - 2)
            font.bold: true
          }

          Item {
            visible: root.showIcons
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20

            Image {
              id: rowIcon
              anchors.fill: parent
              visible: source.toString().length > 0
              asynchronous: true
              cache: true
              fillMode: Image.PreserveAspectFit
              sourceSize.width: 20
              sourceSize.height: 20
              source: {
                if (!root.showIcons || rowDelegate.icon.length === 0) return ""
                if (rowDelegate.icon.indexOf("/") === 0) return "file://" + rowDelegate.icon
                if (Quickshell.hasThemeIcon(rowDelegate.icon)) return Quickshell.iconPath(rowDelegate.icon)
                return Quickshell.hasThemeIcon("application-x-executable")
                       ? Quickshell.iconPath("application-x-executable")
                       : ""
              }
            }
          }

          Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: root.centerText ? Text.AlignHCenter : Text.AlignLeft
            elide: Text.ElideRight
            text: root.model.query.length > 0 ? rowDelegate.highlightedLabel : rowDelegate.label
            textFormat: root.model.query.length > 0 ? Text.StyledText : Text.PlainText
            color: rowDelegate.isActive ? root.colAccent : (rowDelegate.isCurrent ? root.colFgLight : root.colFg)
            font.family: root.fontFamily
            font.pixelSize: root.fontBaseSize
            font.bold: rowDelegate.isCurrent || rowDelegate.isActive
          }

          Text {
            visible: root.showSubtext && rowDelegate.subtext.length > 0 && !root.centerText
            Layout.maximumWidth: root.cardWidth * 0.34
            Layout.alignment: Qt.AlignVCenter
            elide: Text.ElideRight
            text: rowDelegate.subtext
            textFormat: Text.PlainText
            color: rowDelegate.isCurrent ? root.colFg : root.colMuted
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, root.fontBaseSize - 3)
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.triggerRow(rowDelegate.index)
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.model.count === 0
        text: "No matching items"
        textFormat: Text.PlainText
        color: root.colMuted
        font.family: root.fontFamily
        font.pixelSize: Math.max(10, root.fontBaseSize - 1)
      }
    }

    FrameAnimation {
      id: scrollFrameAnim
      running: listView.visible && listView._scrollAnimating && !launcherScroll.pressed
      onTriggered: {
        const dt = Math.min(0.05, Math.max(0.001, frameTime))
        const maxY = listView.maxScrollY
        const target = Math.max(0, Math.min(maxY, listView._targetScrollY))
        const diff = target - listView.contentY
        if (Math.abs(diff) <= 0.4) {
          listView.contentY = target
          listView._scrollAnimating = false
        } else {
          const k = 1.0 - Math.exp(-22.0 * dt)
          listView.contentY = listView.contentY + diff * k
        }
      }
    }

    WheelHandler {
      id: listWheel
      blocking: true
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      target: null

      onWheel: event => {
        const maxY = listView.maxScrollY
        if (maxY <= 0) {
          event.accepted = true
          return
        }
        let step = 0
        if (Math.abs(event.pixelDelta.y) > 0) {
          step = -event.pixelDelta.y
        } else if (event.angleDelta.y !== 0) {
          step = -(event.angleDelta.y / 120.0) * root.rowHeight
        }
        if (step !== 0) {
          const base = listView._scrollAnimating ? listView._targetScrollY : listView.contentY
          listView._targetScrollY = Math.max(0, Math.min(maxY, base + step))
          listView._scrollAnimating = true
        }
        event.accepted = true
      }
    }

    HoverHandler {
      id: listHover

      onHoveredChanged: {
        root._hoverMoved = false
        if (hovered) {
          root._hoverAnchorX = point.scenePosition.x
          root._hoverAnchorY = point.scenePosition.y
        } else {
          root.selectedRow = root.model.count > 0 ? 0 : -1
        }
      }

      onPointChanged: {
        if (!hovered) return
        const sx = point.scenePosition.x
        const sy = point.scenePosition.y
        if (!root._hoverMoved) {
          if (Math.abs(sx - root._hoverAnchorX) < 3 && Math.abs(sy - root._hoverAnchorY) < 3) {
            return
          }
          root._hoverMoved = true
        }
        if (launcherScroll.visible && point.position.x >= listView.width - launcherScroll.width - 4) {
          return
        }
        const idx = listView.indexAt(point.position.x, point.position.y + listView.contentY)
        if (idx >= 0 && idx < root.model.count) {
          root.selectedRow = idx
        } else {
          root.selectedRow = root.model.count > 0 ? 0 : -1
        }
      }
    }
  }

    Item {
      visible: root.showFooter
      Layout.fillWidth: true
      Layout.preferredHeight: root.showFooter ? 30 : 0

      Item {
        anchors.top: parent.top
        width: parent.width
        height: 12

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: 2
          antialiasing: false
          color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.48)
        }
      }

      RowLayout {
        anchors.fill: parent
        anchors.topMargin: 12
        spacing: 8

        Text {
          text: root.presetName.toUpperCase() + "  " + root.model.count + "/" + root.model.totalCount
          textFormat: Text.PlainText
          color: root.colMuted
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, root.fontBaseSize - 3)
        }
      }
    }
  }
}
