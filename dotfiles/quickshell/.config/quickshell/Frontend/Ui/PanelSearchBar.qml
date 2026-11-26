import QtQuick
import QtQuick.Layouts
import qs.Backend.Config
import qs.Frontend.Styles

// Dark inset search/filter bar matching LauncherView's header design language cleanly.
// Arrow Up/Down and Return propagate upward via signals so PanelKeyCatcher keeps cursor sync.
Rectangle {
  id: root

  property alias text: input.text
  property string placeholderText: "Filter..."
  property string promptIcon: ""
  readonly property alias inputActiveFocus: input.activeFocus

  signal movePressed(int dy)
  signal submitPressed()
  signal escapePressed()

  function focusInput() {
    input.forceActiveFocus()
  }

  function clear() {
    input.text = ""
  }

  width: parent ? parent.width : implicitWidth
  implicitWidth: Style.space(340)
  implicitHeight: Math.max(Style.space(32), input.implicitHeight + Style.space(12))
  height: implicitHeight
  radius: PanelStyle.cornerRadius
  color: PanelStyle.darkBackground
  border.width: 1
  border.color: input.activeFocus ? PanelStyle.accent : PanelStyle.subtleBorder

  RowLayout {
    anchors.fill: parent
    spacing: 0

    Rectangle {
      Layout.preferredWidth: Math.max(Style.space(30), root.implicitHeight - 2)
      Layout.fillHeight: true
      radius: root.radius
      color: input.activeFocus ? PanelStyle.selectionFill : PanelStyle.activeFill

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.promptIcon
        color: input.activeFocus ? PanelStyle.accent : PanelStyle.mutedText
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.smallSize
      }

      Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: PanelStyle.subtleBorder
      }
    }

    TextInput {
      id: input
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(10)
      Layout.rightMargin: clearBtn.visible ? Style.space(4) : Style.space(10)
      Layout.alignment: Qt.AlignVCenter
      color: PanelStyle.lightForeground
      selectionColor: PanelStyle.selectionFill
      selectedTextColor: PanelStyle.lightForeground
      font.family: PanelStyle.fontFamily
      font.pixelSize: PanelStyle.smallSize
      clip: true
      verticalAlignment: TextInput.AlignVCenter

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Down) {
          root.movePressed(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.movePressed(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.submitPressed()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.escapePressed()
          event.accepted = true
        }
      }

      Text {
        anchors.fill: parent
        verticalAlignment: TextInput.AlignVCenter
        text: root.placeholderText
        textFormat: Text.PlainText
        color: PanelStyle.mutedText
        font: input.font
        visible: input.text.length === 0
        opacity: input.activeFocus ? 0.55 : 0.8
        elide: Text.ElideRight
      }
    }

    Item {
      id: clearBtn
      visible: input.text.length > 0
      Layout.preferredWidth: Style.space(24)
      Layout.fillHeight: true

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "󰅖"
        color: clearMouse.containsMouse ? PanelStyle.accent : PanelStyle.mutedText
        font.family: PanelStyle.fontFamily
        font.pixelSize: PanelStyle.smallSize
      }

      MouseArea {
        id: clearMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          input.text = ""
          root.escapePressed()
        }
      }
    }
  }
}
