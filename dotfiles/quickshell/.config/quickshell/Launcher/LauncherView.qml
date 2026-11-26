import QtQuick
import QtQuick.Layouts
import Quickshell

// Single modular, capability-driven launcher surface ready for global & per-component GUI theming.
// Supports fast keyboard navigation (Ctrl+N/P/J/K/G, Tab complete, Shift+Return custom, Alt+1..9 quick pick),
// dynamic fonts/radii/borders/animations from shell.toml, and zero-fallback-warning icon resolution.
Rectangle {
  id: root

  required property var model
  required property var palette

  // Global + per-component typography & styling (wired cleanly from shell.toml [font]/[effects]/[launcher])
  property string fontFamily: "JetBrainsMono Nerd Font"
  property int fontBaseSize: 13
  property int borderWidth: 2
  property int borderRadius: 8
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
  property bool dynamicHeight: true
  property bool showFooter: true
  property string resultFormat: "s"

  property string promptText: ""
  property string placeholderText: "Type to filter..."
  property int cardWidth: 480
  property int visibleLines: 6
  property int rowHeight: 40
  property int initialRow: 0
  property bool benchAutoAck: false

  signal accepted(string actionValue, string label, int rowIndex)
  signal cancelled()
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
  readonly property int searchAreaHeight: root.showSearch ? Math.max(38, root.fontBaseSize + 30) : 0
  readonly property int searchSepHeight: root.showSearch ? 11 : 0
  readonly property int headerOnlyHeight: (!root.showSearch && root.showPrompt && root.promptText.length > 0) ? 32 : 0
  readonly property int footerAreaHeight: root.showFooter ? 24 : 0

  width: root.cardWidth
  height: 24 + root.searchAreaHeight + root.searchSepHeight + root.headerOnlyHeight
          + (root.rowSlots * root.rowHeight) + root.footerAreaHeight
  radius: root.borderRadius
  color: root.colBg
  border.width: root.borderWidth
  border.color: root.colAccent
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
      searchInput.forceActiveFocus()
    } else {
      listView.forceActiveFocus()
    }
  }

  function moveSelection(delta: int): void {
    const n = root.model.count
    if (n <= 0) return
    let next = listView.currentIndex + delta
    if (next < 0) next = 0
    if (next >= n) next = n - 1
    listView.currentIndex = next
    listView.positionViewAtIndex(next, ListView.Contain)
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
    } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      event.accepted = true
      if (shift && !root.onlyMatch && root.showSearch && searchInput.text.length > 0) {
        root.accepted(searchInput.text, searchInput.text, -1)
      } else {
        root.triggerRow(listView.currentIndex)
      }
    } else if (k === Qt.Key_Tab && root.showSearch && listView.currentIndex >= 0) {
      event.accepted = true
      const lbl = root.model.labelAt(listView.currentIndex)
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
    listView.currentIndex = startIdx
    if (startIdx > 0) listView.positionViewAtIndex(startIdx, ListView.Center)
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
    function onCountChanged(): void {
      if (root.model.count <= 0) {
        listView.currentIndex = -1
      } else if (listView.currentIndex < 0 || listView.currentIndex >= root.model.count) {
        listView.currentIndex = 0
        listView.positionViewAtIndex(0, ListView.Beginning)
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
    anchors.margins: 12
    spacing: 0

    Rectangle {
      visible: root.showSearch
      Layout.fillWidth: true
      Layout.preferredHeight: root.searchAreaHeight
      radius: Math.max(2, root.borderRadius - 2)
      color: root.colDark
      border.width: 1
      border.color: searchInput.activeFocus ? root.colAccent : root.colSelection

      RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 8

        Rectangle {
          visible: root.showPrompt && root.promptText.length > 0
          Layout.preferredHeight: 24
          Layout.preferredWidth: promptLabel.implicitWidth + 14
          radius: 4
          color: root.colSelection
          border.width: 1
          border.color: root.colAccent

          Text {
            id: promptLabel
            anchors.centerIn: parent
            text: root.promptText
            textFormat: Text.PlainText
            color: root.colFgLight
            font.family: root.fontFamily
            font.pixelSize: Math.max(9, root.fontBaseSize - 1)
            font.bold: true
          }
        }

        TextInput {
          id: searchInput
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignVCenter
          color: root.colFgLight
          selectionColor: root.colSelection
          selectedTextColor: root.colFgLight
          font.family: root.fontFamily
          font.pixelSize: root.fontBaseSize
          clip: true
          verticalAlignment: TextInput.AlignVCenter

          onTextChanged: root.model.query = text
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
      Layout.preferredHeight: root.showSearch ? 11 : 0

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 1
        color: root.colSelection
      }
    }

    Item {
      visible: !root.showSearch && root.showPrompt && root.promptText.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: visible ? 32 : 0

      Text {
        anchors.left: root.centerText ? undefined : parent.left
        anchors.horizontalCenter: root.centerText ? parent.horizontalCenter : undefined
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 6
        text: root.promptText
        textFormat: Text.PlainText
        color: root.colMuted
        font.family: root.fontFamily
        font.pixelSize: Math.max(9, root.fontBaseSize - 2)
        font.bold: true
      }

      Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        width: parent.width
        height: 1
        color: root.colSelection
      }
    }

    ListView {
      id: listView
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      focus: !root.showSearch
      reuseItems: true
      boundsBehavior: Flickable.StopAtBounds
      highlightMoveDuration: 0
      highlightResizeDuration: 0
      model: root.model
      Keys.onPressed: event => root.handleKey(event)

      highlight: Rectangle {
        radius: Math.max(2, root.borderRadius - 3)
        color: root.colSelection
        border.width: 1
        border.color: root.colAccent
      }

      delegate: Item {
        id: rowDelegate
        required property int index
        required property string label
        required property string subtext
        required property string icon
        required property string actionValue
        required property bool isActive
        required property int rowNumber

        readonly property bool isCurrent: ListView.isCurrentItem

        width: listView.width
        height: root.rowHeight

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          spacing: 8

          Rectangle {
            visible: root.showNumbers
            Layout.preferredWidth: Math.max(24, numTxt.implicitWidth + 8)
            Layout.preferredHeight: 20
            radius: 3
            color: rowDelegate.isCurrent ? root.colAccent : root.colDark
            border.width: 1
            border.color: rowDelegate.isCurrent ? root.colAccent : root.colSelection

            Text {
              id: numTxt
              anchors.centerIn: parent
              text: rowDelegate.rowNumber
              textFormat: Text.PlainText
              color: rowDelegate.isCurrent ? root.colBg : root.colMuted
              font.family: root.fontFamily
              font.pixelSize: Math.max(8, root.fontBaseSize - 3)
              font.bold: true
            }
          }

          Image {
            id: rowIcon
            visible: root.showIcons && source.toString().length > 0
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            asynchronous: true
            cache: false
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

          Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: root.centerText ? Text.AlignHCenter : Text.AlignLeft
            elide: Text.ElideRight
            text: rowDelegate.label
            textFormat: Text.PlainText
            color: rowDelegate.isCurrent || rowDelegate.isActive ? root.colFgLight : root.colFg
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

          Rectangle {
            visible: rowDelegate.isActive
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            color: root.colAccent
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: listView.currentIndex = rowDelegate.index
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

    Item {
      visible: root.showFooter
      Layout.fillWidth: true
      Layout.preferredHeight: root.showFooter ? 24 : 0

      Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 3
        width: parent.width
        height: 1
        color: root.colSelection
      }

      RowLayout {
        anchors.fill: parent
        anchors.topMargin: 5
        spacing: 8

        Text {
          text: root.presetName.toUpperCase() + "  " + root.model.count + "/" + root.model.totalCount
                + "  [" + root.model.matchingMode + (root.model.caseSensitive ? " CS" : "") + "]"
          textFormat: Text.PlainText
          color: root.colMuted
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, root.fontBaseSize - 3)
        }

        Item { Layout.fillWidth: true }

        Text {
          text: "C++: " + root.model.lastFilterUs + " us"
          textFormat: Text.PlainText
          color: root.colYellow
          font.family: root.fontFamily
          font.pixelSize: Math.max(8, root.fontBaseSize - 3)
          font.bold: true
        }
      }
    }
  }
}
