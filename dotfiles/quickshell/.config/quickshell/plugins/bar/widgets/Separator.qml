import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.separator"

  readonly property int spaceWidth: settings && settings.size !== undefined ? Number(settings.size) : 14

  implicitWidth: vertical ? barSize : spaceWidth
  implicitHeight: vertical ? spaceWidth : barSize

  Text {
    id: sepText
    anchors.centerIn: parent
    text: root.vertical ? "—" : "|"
    color: ThemeColor.muted
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    font.bold: false
    renderType: Text.NativeRendering
  }
}
