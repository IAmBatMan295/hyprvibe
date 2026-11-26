import QtQuick
import QtQuick.Controls
import Quickshell.Services.Pipewire
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui

// Launcher-aligned Audio mixer widget & popup (Output / Input / Streams).
PanelShell {
  id: root
  moduleName: "hyprvibe.audio"

  readonly property real barEdgeInset: button.barEdgeInset

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string focusSection: "output"
  property int selectedIndex: -1
  property bool cursorActive: false
  property real wheelAccumulator: 0

  readonly property bool headerHasCursor: cursorActive && focusSection === "header"

  readonly property var visibleSections: {
    var list = []
    if (sectionVisible("output")) list.push("output")
    if (sectionVisible("input")) list.push("input")
    if (sectionVisible("streams")) list.push("streams")
    return list
  }

  function sectionCount(section) {
    if (section === "output") return AudioService.displayAudioSinks.length
    if (section === "input") return AudioService.displayAudioSources.length
    if (section === "streams") return AudioService.displayAudioStreams.length
    return 0
  }

  function sectionVisible(section) {
    if (section === "output") return true
    if (section === "input") return AudioService.displayAudioSources.length > 0 || !!AudioService.source
    if (section === "streams") return AudioService.displayAudioStreams.length > 0
    return false
  }

  function sectionHasSlider(section) {
    if (section === "output") return true
    if (section === "input") return !!AudioService.source
    return false
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (sections.length === 0) return
    if (focusSection === "header") {
      if (delta > 0) { focusSection = sections[0]; selectedIndex = sectionHasSlider(sections[0]) ? -1 : 0 }
      return
    }
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = sectionHasSlider(focusSection) ? -1 : 0; return }

    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0

    if (delta > 0) {
      if (idx < max) { selectedIndex = idx + 1; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      }
    } else {
      if (idx > floor) { selectedIndex = idx - 1; return }
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        var prevMax = sectionCount(focusSection) - 1
        selectedIndex = prevMax >= 0 ? prevMax : (sectionHasSlider(focusSection) ? -1 : 0)
      } else {
        focusSection = "header"
      }
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    selectedIndex = -1
  }

  function adjustVolume(delta) {
    if (focusSection === "output" && selectedIndex === -1) {
      AudioService.setOutputVolume(AudioService.outputVolume + delta)
      return
    }
    if (focusSection === "input" && selectedIndex === -1) {
      AudioService.setInputVolume(AudioService.inputVolume + delta)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0 && selectedIndex < AudioService.displayAudioStreams.length) {
      var s = AudioService.displayAudioStreams[selectedIndex]
      if (s && s.audio) s.audio.volume = Math.max(0, Math.min(1.5, s.audio.volume + delta))
    }
  }

  function activateCursor() {
    if (focusSection === "header") { AudioService.toggleAllMuted(); return }
    if (focusSection === "output") {
      if (selectedIndex === -1) { AudioService.toggleOutputMute(); return }
      var sink = AudioService.displayAudioSinks[selectedIndex]
      if (sink) AudioService.setDefaultSink(sink)
      return
    }
    if (focusSection === "input") {
      if (selectedIndex === -1) { AudioService.toggleInputMute(); return }
      var src = AudioService.displayAudioSources[selectedIndex]
      if (src) AudioService.setDefaultSource(src)
      return
    }
    if (focusSection === "streams" && selectedIndex >= 0) {
      var st = AudioService.displayAudioStreams[selectedIndex]
      if (st && st.audio) st.audio.muted = !st.audio.muted
    }
  }

  function resetScroll() {
    if (!scrollArea) return
    var flick = scrollArea.contentItem
    if (flick && flick.contentY !== undefined) flick.contentY = 0
  }

  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var margin = 6
    var maxY = Math.max(0, (flick.contentHeight || 0) - flick.height)
    if (maxY <= Style.space(24) || (root.focusSection === "output" && root.selectedIndex === -1)) {
      flick.contentY = 0
      return
    }
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    if (top < viewTop + margin) flick.contentY = Math.max(0, Math.min(maxY, top - margin))
    else if (bottom > viewBottom - margin)
      flick.contentY = Math.max(0, Math.min(maxY, bottom + margin - flick.height))
  }

  function clampCursor() {
    var sections = visibleSections
    if (!sections || !sections.length) return
    if (focusSection === "header") return
    if (sections.indexOf(focusSection) < 0) {
      focusSection = visibleSections[0]
      selectedIndex = sectionHasSlider(focusSection) ? -1 : 0
      return
    }
    var count = sectionCount(focusSection)
    var hasSlider = sectionHasSlider(focusSection)
    var floor = hasSlider ? -1 : 0
    if (selectedIndex > count - 1) selectedIndex = Math.max(floor, count - 1)
    if (selectedIndex < floor) selectedIndex = floor
  }

  onOpenedChanged: {
    if (opened) {
      AudioService.acquireConsumer()
      focusSection = "output"
      selectedIndex = -1
      cursorActive = false
      Qt.callLater(resetScroll)
    } else {
      AudioService.releaseConsumer()
    }
  }

  Connections {
    target: AudioService
    function onModelsRefreshed() { root.clampCursor() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: AudioService.outputIcon()
    tooltipText: !AudioService.anyAudible
      ? "Audio: Muted"
      : ("Playing at " + Math.round(AudioService.outputVolume * 100) + "%")
    onPressed: function(b) {
      if (b === Qt.RightButton) AudioService.toggleAllMuted()
      else if (b === Qt.LeftButton) root.toggle()
    }
    onWheelMoved: function(delta) {
      if (!AudioService.hasOutput) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      AudioService.setOutputVolume(AudioService.outputVolume + wheel.steps * 0.05)
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
    contentHeight: panel.fittedContentHeight(outerColumn.implicitHeight, panel.maxPanelContentHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.adjustVolume(dx * 0.05)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "m" || t === "M") {
          if (!root.cursorActive) return
          if (root.focusSection === "streams" && root.selectedIndex >= 0 && root.selectedIndex < AudioService.displayAudioStreams.length) {
            var s = AudioService.displayAudioStreams[root.selectedIndex]
            if (s && s.audio) s.audio.muted = !s.audio.muted
          } else if (root.focusSection === "input") {
            AudioService.toggleInputMute()
          } else {
            AudioService.toggleOutputMute()
          }
        }
      }

      Column {
        id: outerColumn
        anchors.fill: parent
        spacing: Style.space(10)

        PanelHeaderBar {
          id: headerBar
          iconText: AudioService.outputIcon()
          iconDimmed: AudioService.outputMuted
          titleText: "Audio"

          ToggleSwitch {
            id: powerSwitch
            checked: AudioService.anyAudible
            hasCursor: root.headerHasCursor
            foreground: PanelStyle.foreground
            trackHeight: Math.round(Style.spacing.controlHeight * 0.48)
            cursorPad: Style.space(3)
            onHovered: function(on) { if (on) root.setHeaderCursor() }
            onToggled: AudioService.toggleAllMuted()

            PanelToolTip {
              visible: powerSwitch.containsMouse
              text: AudioService.toggleHint
              fontFamily: PanelStyle.fontFamily
            }
          }
        }

        ScrollView {
          id: scrollArea
          readonly property real viewportHeight: Math.min(
            panelColumn.implicitHeight,
            panel.maxListViewportHeight(panel.nonScrollChildrenHeight(outerColumn, scrollArea))
          )
          width: parent.width
          implicitHeight: viewportHeight
          height: viewportHeight
          padding: 0
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
          ScrollBar.vertical: PanelScrollBar {
            id: audioScroll
            parent: scrollArea
            policy: panelColumn.implicitHeight > scrollArea.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          }
          Binding {
            target: scrollArea.contentItem
            property: "interactive"
            value: panelColumn.implicitHeight > scrollArea.height
          }

          Column {
            id: panelColumn
            width: scrollArea.width - (audioScroll.visible ? audioScroll.width + Style.space(6) : 0)
            spacing: Style.space(10)

            // ---- Output ----
            Column {
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                implicitHeight: Math.max(outputHeader.implicitHeight, outputPercent.implicitHeight)

                PanelSectionHeader {
                  id: outputHeader
                  text: "OUTPUT"
                  foreground: PanelStyle.foreground
                  fontFamily: PanelStyle.fontFamily
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: outputPercent
                  textFormat: Text.PlainText
                  text: GlitchBus.panelText(Math.round((outputSlider.dragging ? outputSlider.liveValue : AudioService.outputVolume) * 100) + "%")
                  color: PanelStyle.accent
                  font.family: PanelStyle.fontFamily
                  font.pixelSize: PanelStyle.captionSize
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: AudioService.outputMuted ? 0.5 : 1.0
                }
              }

              CursorSurface {
                id: outputSliderRow
                width: parent.width
                height: outputSlider.implicitHeight + Style.spacing.controlGap
                hasCursor: root.cursorActive && root.focusSection === "output" && root.selectedIndex === -1
                onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(outputSliderRow)
                foreground: PanelStyle.foreground
                bordered: true

                PanelSlider {
                  id: outputSlider
                  bar: root.bar
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: AudioService.outputVolume
                  fillColor: PanelStyle.accent
                  knobColor: PanelStyle.lightForeground
                  opacity: AudioService.outputMuted ? 0.5 : 1.0
                  enabled: !!AudioService.sink

                  onMoved: function(v) { AudioService.setOutputVolume(v) }
                  onRightClicked: AudioService.toggleOutputMute()
                }

                HoverHandler {
                  onHoveredChanged: if (hovered) {
                    root.cursorActive = true
                    root.focusSection = "output"
                    root.selectedIndex = -1
                  }
                }
              }

              Repeater {
                model: AudioService.displayAudioSinks

                SinkRow {
                  required property var modelData
                  required property int index
                  width: panelColumn.width
                  node: modelData
                  rowIndex: index
                }
              }
            }

            // ---- Input ----
            PanelSeparator {
              visible: !!AudioService.source || AudioService.displayAudioSources.length > 0
              foreground: PanelStyle.foreground
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: !!AudioService.source || AudioService.displayAudioSources.length > 0

              Item {
                width: parent.width
                implicitHeight: Math.max(microphoneHeader.implicitHeight, microphonePercent.implicitHeight)

                PanelSectionHeader {
                  id: microphoneHeader
                  text: "INPUT"
                  foreground: PanelStyle.foreground
                  fontFamily: PanelStyle.fontFamily
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: microphonePercent
                  textFormat: Text.PlainText
                  text: GlitchBus.panelText(Math.round((inputSlider.dragging ? inputSlider.liveValue : AudioService.inputVolume) * 100) + "%")
                  color: PanelStyle.accent
                  font.family: PanelStyle.fontFamily
                  font.pixelSize: PanelStyle.captionSize
                  font.bold: true
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: AudioService.inputMuted ? 0.5 : 1.0
                }
              }

              CursorSurface {
                id: inputSliderRow
                visible: !!AudioService.source
                width: parent.width
                height: inputSlider.implicitHeight + Style.spacing.controlGap
                hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === -1
                onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(inputSliderRow)
                foreground: PanelStyle.foreground
                bordered: true

                PanelSlider {
                  id: inputSlider
                  bar: root.bar
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  value: AudioService.inputVolume
                  fillColor: PanelStyle.accent
                  knobColor: PanelStyle.lightForeground
                  opacity: AudioService.inputMuted ? 0.5 : 1.0
                  enabled: !!AudioService.source

                  onMoved: function(v) { AudioService.setInputVolume(v) }
                  onRightClicked: AudioService.toggleInputMute()
                }

                HoverHandler {
                  onHoveredChanged: if (hovered) {
                    root.cursorActive = true
                    root.focusSection = "input"
                    root.selectedIndex = -1
                  }
                }
              }

              Repeater {
                model: AudioService.displayAudioSources

                SourceRow {
                  required property var modelData
                  required property int index
                  width: panelColumn.width
                  node: modelData
                  rowIndex: index
                }
              }
            }

            // ---- App Streams ----
            PanelSeparator {
              visible: AudioService.displayAudioStreams.length > 0
              foreground: PanelStyle.foreground
            }

            Column {
              width: parent.width
              spacing: Style.space(8)
              visible: AudioService.displayAudioStreams.length > 0

              PanelSectionHeader {
                text: "APP STREAMS"
                foreground: PanelStyle.foreground
                fontFamily: PanelStyle.fontFamily
              }

              Repeater {
                model: AudioService.displayAudioStreams

                StreamRow {
                  required property var modelData
                  required property int index
                  width: panelColumn.width
                  node: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component SinkRow: CursorSurface {
    id: sinkRow
    required property var node
    required property int rowIndex

    readonly property bool isActive: (Pipewire.preferredDefaultAudioSink && node && Pipewire.preferredDefaultAudioSink.id === node.id)
      || (AudioService.sink && node && AudioService.sink.id === node.id)
    hasCursor: root.cursorActive && root.focusSection === "output" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sinkRow)
    current: isActive
    pressed: sinkMouse.pressed
    foreground: PanelStyle.foreground
    implicitHeight: sinkInner.implicitHeight + Style.spacing.xl

    Row {
      id: sinkInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: GlitchBus.panelGlyph(AudioService.sinkGlyph(sinkRow.node))
        color: sinkRow.hasCursor ? ThemeStore.accent : (sinkRow.isActive ? ThemeStore.accent : PanelStyle.foreground)
        Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.titleSize
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: GlitchBus.panelText(AudioService.nodeLabel(sinkRow.node))
        color: sinkRow.hasCursor ? ThemeStore.accent : (sinkRow.isActive ? ThemeStore.accent : PanelStyle.foreground)
        Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.bodySize
        font.bold: sinkRow.isActive || sinkRow.hasCursor
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: sinkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "output"
        root.selectedIndex = sinkRow.rowIndex
      }
      onClicked: AudioService.setDefaultSink(sinkRow.node)
    }
  }

  component SourceRow: CursorSurface {
    id: sourceRow
    required property var node
    required property int rowIndex

    readonly property bool isActive: (Pipewire.preferredDefaultAudioSource && node && Pipewire.preferredDefaultAudioSource.id === node.id)
      || (AudioService.source && node && AudioService.source.id === node.id)
    hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(sourceRow)
    current: isActive
    pressed: sourceMouse.pressed
    foreground: PanelStyle.foreground
    implicitHeight: sourceInner.implicitHeight + Style.spacing.xl

    Row {
      id: sourceInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: GlitchBus.panelGlyph(AudioService.sourceGlyph(sourceRow.node))
        color: sourceRow.hasCursor ? ThemeStore.accent : (sourceRow.isActive ? ThemeStore.accent : PanelStyle.foreground)
        Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.titleSize
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: GlitchBus.panelText(AudioService.nodeLabel(sourceRow.node))
        color: sourceRow.hasCursor ? ThemeStore.accent : (sourceRow.isActive ? ThemeStore.accent : PanelStyle.foreground)
        Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.bodySize
        font.bold: sourceRow.isActive || sourceRow.hasCursor
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: sourceMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "input"
        root.selectedIndex = sourceRow.rowIndex
      }
      onClicked: AudioService.setDefaultSource(sourceRow.node)
    }
  }

  component StreamRow: CursorSurface {
    id: streamRow
    required property var node
    required property int rowIndex

    readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
    readonly property bool streamMuted: node && node.audio ? node.audio.muted : false
    readonly property bool isActive: false

    hasCursor: root.cursorActive && root.focusSection === "streams" && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(streamRow)
    current: isActive
    bordered: true
    pressed: false
    foreground: PanelStyle.foreground
    implicitHeight: streamColumn.implicitHeight + Style.spacing.xl

    Column {
      id: streamColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: streamMuteIcon
          textFormat: Text.PlainText
          text: GlitchBus.panelGlyph(streamRow.streamMuted ? "󰝟" : "󰕾")
          color: streamRow.hasCursor ? ThemeStore.accent : PanelStyle.foreground
          Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.titleSize
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (streamRow.node && streamRow.node.audio)
                streamRow.node.audio.muted = !streamRow.node.audio.muted
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: GlitchBus.panelText(AudioService.streamLabel(streamRow.node))
          color: streamRow.hasCursor ? ThemeStore.accent : PanelStyle.foreground
          Behavior on color { ColorAnimation { duration: PanelStyle.hoverColorAnimMs } }
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.bodySize
          font.bold: streamRow.hasCursor
          elide: Text.ElideRight
          width: parent.width - streamMuteIcon.width - streamPct.width - Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: streamPct
          textFormat: Text.PlainText
          text: GlitchBus.panelText(Math.round(streamRow.streamVolume * 100) + "%")
          color: PanelStyle.accent
          font.family: PanelStyle.fontFamily
          font.pixelSize: PanelStyle.captionSize
          font.bold: true
          width: Style.space(36)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
          opacity: streamRow.streamMuted ? 0.5 : 1.0
        }
      }

      PanelSlider {
        bar: root.bar
        width: parent.width
        minimum: 0
        maximum: 1.5
        step: 0.05
        value: streamRow.streamVolume
        fillColor: PanelStyle.accent
        knobColor: PanelStyle.lightForeground
        opacity: streamRow.streamMuted ? 0.5 : 1.0

        onMoved: function(v) {
          if (streamRow.node && streamRow.node.audio) streamRow.node.audio.volume = v
        }
        onRightClicked: {
          if (streamRow.node && streamRow.node.audio)
            streamRow.node.audio.muted = !streamRow.node.audio.muted
        }
      }
    }

    MouseArea {
      id: streamMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      propagateComposedEvents: true
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = "streams"
        root.selectedIndex = streamRow.rowIndex
      }
    }
  }
}
