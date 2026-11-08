pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Bluetooth
import qs.core

// Sound, display brightness, Bluetooth and media, for Control Center and the OSD.
Singleton {
  id: sys

  // ---- sound
  readonly property var sink: Pipewire.defaultAudioSink
  property PwObjectTracker tracker: PwObjectTracker { objects: sys.sink ? [sys.sink] : [] }
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  function setVolume(v) { if (sink && sink.audio) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, v)) } }
  function toggleMute() { if (sink && sink.audio) sink.audio.muted = !sink.audio.muted }
  // Changed by hand (keys, sliders, scrolling): like a Mac, a short pop at the
  // new level once it stops changing, so holding a key or dragging plays it once.
  function changeVolume(v) { setVolume(v); popLater.restart() }
  property Timer popLater: Timer {
    interval: 180
    onTriggered: if (!sys.muted && sys.volume > 0) Quickshell.execDetached(["memora-sound", "volume"])
  }

  // ---- brightness (brightnessctl; absent on desktops and VMs)
  property bool hasBacklight: false
  property real brightness: 1
  property Process brRead: Process {
    command: ["brightnessctl", "-m", "-c", "backlight"]
    stdout: StdioCollector {
      onStreamFinished: {
        const f = text.trim().split(",")
        sys.hasBacklight = f.length >= 4
        if (sys.hasBacklight) sys.brightness = parseInt(f[3]) / 100
      }
    }
  }
  property Process brWrite: Process {}
  function setBrightness(v) {
    brightness = Math.max(0.02, Math.min(1, v))
    brWrite.command = ["brightnessctl", "-q", "-c", "backlight", "set", Math.round(brightness * 100) + "%"]
    brWrite.running = true
  }
  Component.onCompleted: brRead.running = true

  // ---- bluetooth
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property bool btAvailable: !!adapter
  readonly property bool btOn: adapter ? adapter.enabled : false
  function toggleBt() { if (adapter) adapter.enabled = !adapter.enabled }
  readonly property var btConnected: adapter ? adapter.devices.values.filter(d => d.connected) : []

  // ---- wi-fi
  property Process wifiProc: Process {}
  function setWifi(on) {
    wifiProc.command = ["nmcli", "radio", "wifi", on ? "on" : "off"]
    wifiProc.running = true
    Net.wifiEnabled = on
  }

  // ---- media
  readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
}
