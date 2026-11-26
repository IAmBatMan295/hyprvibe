import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Backend.Config
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui
import "Sections"

// Lazy-loaded Settings modal overlay GUI. Shares PanelStyle tokens & Ui controls,
// blocks input leakage under overlay without casting a dim shadow across desktop.
Item {
  id: root

  property bool open: false
  property string activeTab: "theme"

  signal closeRequested()

  readonly property var activeScreen: {
    var focused = Hyprland.focusedMonitor
    var list = Quickshell.screens || []
    if (focused && focused.name) {
      for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].name === focused.name) return list[i]
      }
    }
    return list.length > 0 ? list[0] : null
  }

  readonly property var sections: [
    { id: "theme", label: "Theme & Global", icon: "" },
    { id: "bar", label: "Bar & Widgets", icon: "󰕮" },
    { id: "panels", label: "Panels", icon: "󰍜" },
    { id: "launcher", label: "Launcher", icon: "" },
    { id: "hyprland", label: "Hyprland", icon: "" }
  ]

  function focusOverlay() {
    if (!root.open) return
    keyRoot.forceActiveFocus()
    Qt.callLater(function() {
      if (root.open) keyRoot.forceActiveFocus()
    })
  }

  function stepTab(delta) {
    var idx = 0
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].id === root.activeTab) { idx = i; break }
    }
    var next = (idx + delta + sections.length) % sections.length
    root.activeTab = sections[next].id
    scrollArea.contentItem.contentY = 0
  }

  onOpenChanged: {
    if (open) {
      SettingsService.refreshEnvironment()
      focusOverlay()
    }
  }

  PanelWindow {
    id: overlayWin

    screen: root.activeScreen
    visible: root.open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hyprvibe-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    onVisibleChanged: if (visible) root.focusOverlay()
    onBackingWindowVisibleChanged: if (backingWindowVisible && root.open) root.focusOverlay()

    // Transparent outside-click & hover catcher prevents follow_mouse focus leak
    // onto windows underneath without casting a dim shadow backdrop.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      hoverEnabled: true
      onPressed: root.closeRequested()
    }

    FocusScope {
      id: keyRoot
      focus: true
      anchors.centerIn: parent
      width: Math.max(Style.space(480), Math.min(overlayWin.width - Style.space(48), Style.space(800)))
      height: Math.max(Style.space(360), Math.min(overlayWin.height - Style.space(48), Style.space(560)))

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          event.accepted = true
          root.closeRequested()
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Tab) {
          event.accepted = true
          root.stepTab(1)
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Backtab) {
          event.accepted = true
          root.stepTab(-1)
        }
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: function(mouse) {
          mouse.accepted = true
          keyRoot.forceActiveFocus()
        }
      }

      BorderSurface {
        anchors.fill: parent
        color: PanelStyle.background
        borderSpec: Border.panelsOrPopupSpec(PanelStyle.border, ThemeStore.popups.border, Math.max(1, Style.space(2)))
        radius: PanelStyle.cornerRadius
        padding: PanelStyle.padding

        RowLayout {
          anchors.fill: parent
          spacing: Style.space(14)

          // Left navigation sidebar
          ColumnLayout {
            Layout.preferredWidth: Style.space(184)
            Layout.fillHeight: true
            spacing: Style.space(6)

            PanelHeaderBar {
              Layout.fillWidth: true
              iconText: ""
              titleText: "Settings"
            }

            Item { Layout.preferredHeight: Style.space(4) }

            Repeater {
              model: root.sections

              delegate: Button {
                required property var modelData
                readonly property bool isCurrent: root.activeTab === modelData.id

                Layout.fillWidth: true
                leftAlign: true
                text: modelData.label
                iconText: modelData.icon
                bordered: true
                active: isCurrent
                selected: isCurrent
                foreground: isCurrent ? PanelStyle.accent : PanelStyle.foreground
                fontFamily: PanelStyle.fontFamily
                fontSize: PanelStyle.bodySize
                verticalPadding: Style.space(7)
                onClicked: {
                  root.activeTab = modelData.id
                  scrollArea.contentItem.contentY = 0
                }
              }
            }

            Item { Layout.fillHeight: true }

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: "SUPER+, toggle • Esc close"
              color: PanelStyle.mutedText
              font.family: PanelStyle.fontFamily
              font.pixelSize: PanelStyle.captionSize
            }
          }

          Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: PanelStyle.trackFill
          }

          // Right content pane
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.space(10)

            RowLayout {
              Layout.fillWidth: true

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: {
                  for (var i = 0; i < root.sections.length; i++) {
                    if (root.sections[i].id === root.activeTab) return root.sections[i].label
                  }
                  return "Settings"
                }
                color: PanelStyle.foreground
                font.family: PanelStyle.fontFamily
                font.pixelSize: PanelStyle.titleSize
                font.bold: true
              }

              PanelActionButton {
                iconText: "󰅖"
                tooltipText: "Close (Esc)"
                foreground: PanelStyle.foreground
                fontFamily: PanelStyle.fontFamily
                onClicked: root.closeRequested()
              }
            }

            PanelSeparator { foreground: PanelStyle.foreground }

            ScrollView {
              id: scrollArea
              Layout.fillWidth: true
              Layout.fillHeight: true
              padding: 0
              clip: true
              ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
              ScrollBar.vertical: PanelScrollBar {
                id: settingsScroll
                parent: scrollArea
                policy: sectionHost.implicitHeight > scrollArea.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
              }
              Binding {
                target: scrollArea.contentItem
                property: "interactive"
                value: sectionHost.implicitHeight > scrollArea.height
              }

              Item {
                id: sectionHost
                width: scrollArea.width - (settingsScroll.visible ? settingsScroll.width + Style.space(8) : 0)
                implicitHeight: currentLoader.item ? currentLoader.item.implicitHeight : 0

                Loader {
                  id: currentLoader
                  width: parent.width
                  source: {
                    switch (root.activeTab) {
                      case "bar": return "Sections/BarSection.qml"
                      case "panels": return "Sections/PanelsSection.qml"
                      case "launcher": return "Sections/LauncherSection.qml"
                      case "hyprland": return "Sections/HyprlandSection.qml"
                      default: return "Sections/ThemeSection.qml"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: root.open && !!overlayWin.screen && modelData.name !== overlayWin.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "hyprvibe-settings-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors { top: true; bottom: true; left: true; right: true }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.closeRequested()
        }
      }
    }
  }
}
