pragma Singleton
import QtQuick
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import HyprVibeLauncher
import "../Models/AudioModel.js" as Model

// Event-driven PipeWire + MPRIS + C++ libpulse audio service (zero shell/pactl subprocesses).
QtObject {
  id: root

  signal modelsRefreshed()

  property int activeConsumers: 0
  readonly property bool panelOpen: activeConsumers > 0

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []

  readonly property var candidateSinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }

  readonly property var candidateSources: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && !n.isSink && !n.isStream && isAudioSource(n)) {
        if ((n.name || "") === "quickshell") continue
        list.push(n)
      }
    }
    return list
  }

  readonly property var candidateStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !isPlaybackStream(n)) continue
      if (String(n.name || "").indexOf("hyprvibe_speaker_tuning") === 0) continue
      list.push(n)
    }
    return list
  }

  readonly property var sinkAvailability: SystemCore.audioSinkAvailability || ({})
  readonly property bool sinkAvailabilityLoaded: Object.keys(sinkAvailability).length > 0
  readonly property string volumeSinkName: SystemCore.audioVolumeSink || ""

  property var cachedAudioSinks: []
  property var cachedAudioSources: []

  readonly property var rawAudioSinks: {
    var list = []
    for (var i = 0; i < candidateSinks.length; i++)
      if (sinkAvailable(candidateSinks[i])) list.push(candidateSinks[i])
    if (sink && list.indexOf(sink) < 0) list.unshift(sink)
    return list
  }

  readonly property var rawAudioSources: {
    var list = candidateSources.slice()
    if (source && list.indexOf(source) < 0) list.unshift(source)
    return list
  }

  readonly property var audioSinks: rawAudioSinks.length > 0 ? rawAudioSinks : cachedAudioSinks
  readonly property var audioSources: rawAudioSources.length > 0 ? rawAudioSources : cachedAudioSources

  readonly property var audioStreams: {
    var list = []
    for (var i = 0; i < candidateStreams.length; i++)
      if (candidateStreams[i].audio) list.push(candidateStreams[i])
    return list
  }

  property var displayAudioSinks: []
  property var displayAudioSources: []
  property var displayAudioStreams: []

  readonly property var volumeSink: {
    if (volumeSinkName === "" || !sink) return sink
    if (volumeSinkName === String(sink.name)) return sink
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && String(n.name) === volumeSinkName && n.audio)
        return n
    }
    return sink
  }

  onSinkChanged: SystemCore.refreshAudioState()
  onRawAudioSinksChanged: if (rawAudioSinks.length > 0) cachedAudioSinks = rawAudioSinks
  onRawAudioSourcesChanged: if (rawAudioSources.length > 0) cachedAudioSources = rawAudioSources
  onAudioSinksChanged: scheduleDisplayAudioModelRefresh()
  onAudioSourcesChanged: scheduleDisplayAudioModelRefresh()
  onAudioStreamsChanged: scheduleDisplayAudioModelRefresh()

  readonly property real outputVolume: volumeSink && volumeSink.audio ? volumeSink.audio.volume : 0
  readonly property bool outputMuted: volumeSink && volumeSink.audio ? volumeSink.audio.muted : false
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  readonly property bool hasOutput: !!(volumeSink && volumeSink.audio)
  readonly property bool hasInput: !!(source && source.audio)
  readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)
  readonly property string toggleHint: anyAudible ? "Mute" : "Unmute"

  function acquireConsumer() {
    activeConsumers += 1
    SystemCore.refreshAudioState()
    refreshDisplayAudioModels()
  }

  function releaseConsumer() {
    activeConsumers = Math.max(0, activeConsumers - 1)
    if (activeConsumers === 0) clearDisplayAudioModels()
  }

  function refreshDisplayAudioModels() {
    if (!panelOpen) return
    displayAudioSinks = Model.listSnapshot(audioSinks)
    displayAudioSources = Model.listSnapshot(audioSources)
    displayAudioStreams = Model.listSnapshot(audioStreams)
    modelsRefreshed()
  }

  function scheduleDisplayAudioModelRefresh() {
    if (!panelOpen) return
    audioModelRefreshTimer.restart()
  }

  function clearDisplayAudioModels() {
    audioModelRefreshTimer.stop()
    displayAudioSinks = []
    displayAudioSources = []
    displayAudioStreams = []
  }

  function isPlaybackStream(node) { return Model.isPlaybackStream(node) }
  function isAudioSource(node) { return Model.isAudioSource(node) }
  function outputVolumeName(volume, muted) { return Model.outputVolumeName(volume, muted) }
  function friendlyDeviceLabel(text) { return Model.friendlyDeviceLabel(text) }
  function nodeLabel(node) { return Model.nodeLabel(node) }
  function nodeProps(node) { return Model.nodeProps(node) }
  function isHeadphones(node) { return Model.isHeadphones(node) }
  function sinkGlyph(node) { return Model.sinkGlyph(node) }
  function sourceGlyph(node) { return Model.sourceGlyph(node) }
  function streamLabel(node) { return Model.streamLabel(node, mprisPlayers, displayAudioStreams) }
  function streamRepresentsPlayer(node, player) { return Model.streamRepresentsPlayer(node, player, mprisPlayers, displayAudioStreams) }

  function outputIcon(volume) {
    if (!sink || !sink.audio) return ""
    if (isHeadphones(sink)) return "󰋋"
    if (outputMuted) return ""
    var v = volume === undefined ? outputVolume : volume
    if (v >= 0.67) return ""
    if (v >= 0.34) return ""
    if (v > 0) return ""
    return ""
  }

  function inputIcon() {
    if (!source || !source.audio) return "󰍭"
    return inputMuted ? "󰍭" : "󰍬"
  }

  function setOutputVolume(v) {
    if (!volumeSink || !volumeSink.audio) return outputVolume
    var volume = Math.max(0, Math.min(1, v))
    volumeSink.audio.volume = volume
    return volume
  }

  function setInputVolume(v) {
    if (!source || !source.audio) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() {
    if (volumeSink && volumeSink.audio) volumeSink.audio.muted = !volumeSink.audio.muted
  }

  function toggleInputMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  function toggleAllMuted() {
    var mute = anyAudible
    if (hasOutput) volumeSink.audio.muted = mute
    if (hasInput) source.audio.muted = mute
  }

  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.name) SystemCore.setDefaultAudioSink(String(node.name))
  }

  function setDefaultSource(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSource = node
    if (node.name) SystemCore.setDefaultAudioSource(String(node.name))
  }

  function sinkAvailable(node) {
    if (!node || !node.name || !sinkAvailabilityLoaded) return true
    return sinkAvailability[String(node.name)] !== false
  }

  property PwObjectTracker sinkTracker: PwObjectTracker { objects: root.candidateSinks }
  property PwObjectTracker sourceTracker: PwObjectTracker { objects: root.candidateSources }
  property PwObjectTracker streamTracker: PwObjectTracker { objects: root.audioStreams }

  property Timer audioModelRefreshTimer: Timer {
    id: audioModelRefreshTimer
    interval: 75
    repeat: false
    onTriggered: root.refreshDisplayAudioModels()
  }
}
