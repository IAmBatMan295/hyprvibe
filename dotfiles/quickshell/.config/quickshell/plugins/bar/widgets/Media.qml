import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.media"

  readonly property string playbackState: Telemetry.playbackState
  readonly property string songTitle: Telemetry.songTitle
  readonly property string songArtist: Telemetry.songArtist
  readonly property string songFile: Telemetry.songFile
  readonly property bool isPlaying: playbackState === "Play"
  readonly property string currentTooltip: {
    if (songTitle !== "") {
      return songArtist !== "" ? (songTitle + " — " + songArtist) : songTitle
    }
    if (songFile !== "") return songFile
    if (playbackState === "Stop") return "MPD Stopped"
    return "MPD"
  }

  implicitWidth: row.implicitWidth
  implicitHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal

  RowLayout {
    id: row
    anchors.fill: parent
    spacing: 0

    WidgetButton {
      id: prevBtn
      bar: root.bar
      text: "󰒮"
      foreground: ThemeColor.muted
      tooltipText: root.currentTooltip
      fontSize: Style.font.body
      horizontalMargin: 4
      verticalPadding: 2
      fixedHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal
      onPressed: function() { Telemetry.triggerMediaAction("prev") }
    }

    WidgetButton {
      id: toggleBtn
      bar: root.bar
      text: root.isPlaying ? "󰏤" : "󰐊"
      foreground: ThemeColor.muted
      tooltipText: root.currentTooltip
      fontSize: Style.font.body
      horizontalMargin: 4
      verticalPadding: 2
      fixedHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal
      onPressed: function() { Telemetry.triggerMediaAction("toggle") }
    }

    WidgetButton {
      id: nextBtn
      bar: root.bar
      text: "󰒭"
      foreground: ThemeColor.muted
      tooltipText: root.currentTooltip
      fontSize: Style.font.body
      horizontalMargin: 4
      verticalPadding: 2
      fixedHeight: root.bar ? root.bar.barSize : Style.bar.sizeHorizontal
      onPressed: function() { Telemetry.triggerMediaAction("next") }
    }

    Text {
      id: sep
      text: "|"
      color: ThemeColor.muted
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      Layout.alignment: Qt.AlignVCenter
      Layout.leftMargin: 6
      Layout.rightMargin: 6
    }
  }
}
