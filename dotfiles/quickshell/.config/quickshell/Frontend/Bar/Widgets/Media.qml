import QtQuick
import qs.Backend.Services
import qs.Frontend.Styles
import qs.Frontend.Ui

BarWidget {
  id: root
  moduleName: "hyprvibe.media"

  readonly property string playbackState: TelemetryService.playbackState
  readonly property string songTitle: TelemetryService.songTitle
  readonly property string songArtist: TelemetryService.songArtist
  readonly property string songFile: TelemetryService.songFile
  readonly property bool isPlaying: playbackState === "Play"
  readonly property string currentTooltip: {
    if (songTitle !== "") {
      return songArtist !== "" ? (songTitle + " — " + songArtist) : songTitle
    }
    if (songFile !== "") return songFile
    if (playbackState === "Stop") return "MPD Stopped"
    return "MPD"
  }

  readonly property real barEdgeInset: marquee.barEdgeInset

  implicitWidth: marquee.implicitWidth
  implicitHeight: root.bar ? root.bar.barSize : BarStyle.sizeHorizontal

  MarqueeButton {
    id: marquee
    anchors.fill: parent
    bar: root.bar
    text: root.currentTooltip
    tooltipText: root.currentTooltip
    fontSize: BarStyle.fontSize
    fixedWidth: root.setting("width", 140)
    fixedHeight: root.bar ? root.bar.barSize : BarStyle.sizeHorizontal
    horizontalMargin: 8
    dimmed: !root.isPlaying
    splitDoubleClick: true
    onSingleClicked: TelemetryService.triggerMediaAction("toggle")
    onDoubleClickedLeft: TelemetryService.triggerMediaAction("prev")
    onDoubleClickedRight: TelemetryService.triggerMediaAction("next")
  }
}
