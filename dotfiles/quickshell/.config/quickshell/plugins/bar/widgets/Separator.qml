import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.separator"

  readonly property int spaceWidth: settings && settings.size !== undefined ? Number(settings.size) : 14
  readonly property string separatorStyle: Style.barWidgetStyle("separator", "line")
  readonly property bool isScanBlip: separatorStyle === "scan-blip"
  readonly property bool isCyberSlash: separatorStyle === "cyber-slash"
  readonly property bool isCustomStyle: isScanBlip || isCyberSlash

  implicitWidth: vertical ? barSize : spaceWidth
  implicitHeight: vertical ? spaceWidth : barSize

  Text {
    id: sepText
    visible: !root.isCustomStyle
    anchors.centerIn: parent
    text: root.vertical ? "—" : "|"
    color: ThemeColor.muted
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    font.bold: false
    renderType: Text.NativeRendering
  }

  Component {
    id: scanBlipComponent

    ScanlineBlipSeparator {
      vertical: root.vertical
      suspended: GlitchBus.suspended || !root.visible
      intervalMs: Style.effects.barBlipIntervalMs
      trackColor: Qt.rgba(ThemeColor.muted.r, ThemeColor.muted.g, ThemeColor.muted.b, 0.28)
      blipColor: ThemeColor.accent
    }
  }

  Component {
    id: cyberSlashComponent

    CyberSlashSeparator {
      vertical: root.vertical
      suspended: GlitchBus.suspended || !root.visible
      accentColor: ThemeColor.accent
    }
  }

  Loader {
    anchors.centerIn: parent
    active: root.isCustomStyle
    sourceComponent: root.isCyberSlash ? cyberSlashComponent : scanBlipComponent
  }
}
