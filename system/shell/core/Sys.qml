pragma Singleton
import QtQuick
import QtMultimedia
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
  // new level. A key press pops at once; while a key is held or a slider is
  // dragged, the changes that follow pop once, when they stop.
  // The pop is decoded and held here (SoundEffect), not started as a program
  // each time (memora-sound: bash, jq, pw-play), which was about 90 ms late.
  function changeVolume(v, now) {
    setVolume(v)
    popLevel = Math.max(0, Math.min(1, v))   // the sink reports its new level a moment later
    if (now && !popLater.running && Date.now() - lastPop > 250) pop()
    else popLater.restart()
  }
  property real lastPop: 0
  property real popLevel: 0
  function pop() {
    lastPop = Date.now()
    if (sys.popLevel <= 0 || !Prefs.volumeFeedback) return
    if (popFx.status === SoundEffect.Ready) { popFx.stop(); popFx.play() }
    else Quickshell.execDetached(["memora-sound", "volume"])
  }
  property Timer popLater: Timer { interval: 60; onTriggered: sys.pop() }
  // The shell's own process: its streams (the pop below) are system sounds, kept
  // out of the mixer, which would list them as "Quickshell".
  property int shellPid: 0
  property Process pidRead: Process {
    running: true
    command: ["sh", "-c", "echo $PPID"]
    stdout: StdioCollector { onStreamFinished: sys.shellPid = parseInt(text) || 0 }
  }
  property MediaDevices devices: MediaDevices {}
  property SoundEffect popFx: SoundEffect {
    source: "file://" + Theme.share + "/sounds/volume.wav"
    audioDevice: sys.devices.defaultAudioOutput   // follows a change of speakers
  }

  // ---- brightness: the built-in screen's backlight (brightnessctl, which asks
  // logind, so no root needed), else an external monitor over DDC/CI (ddcutil;
  // the first one). Desktops without either, and VMs, show no slider.
  property bool hasBacklight: false     // a screen whose brightness Memora can set
  property string brKind: ""            // "backlight" | "ddc"
  property string brDevice: ""          // the backlight, e.g. intel_backlight
  property int brMax: 100               // the monitor's top DDC value
  property real brightness: 1
  // Looked for again when Control Center opens or a brightness key is pressed:
  // a backlight driver can come up after the desktop, a monitor can be plugged in.
  function refreshBrightness() { if (!brRead.running && !brWrite.running) brRead.running = true }
  property Process brRead: Process {
    // A firmware backlight first, then platform, then raw (like systemd): on
    // laptops with two, the raw one may do nothing.
    command: ["bash", "-c", `
      for t in firmware platform raw; do
        for d in /sys/class/backlight/*; do
          [ "$(cat "$d/type" 2>/dev/null)" = "$t" ] || continue
          m=$(cat "$d/max_brightness" 2>/dev/null); b=$(cat "$d/brightness" 2>/dev/null)
          [ "$m" -gt 0 ] 2>/dev/null && { echo "backlight $(( b * 100 / m )) $m $(basename "$d")"; exit; }
        done
      done
      command -v ddcutil >/dev/null || exit 0
      set -- $(timeout 6 ddcutil getvcp 10 --brief 2>/dev/null)   # VCP 10 C <now> <max>
      [ "$1" = VCP ] && [ "$5" -gt 0 ] 2>/dev/null && echo "ddc $(( $4 * 100 / $5 )) $5"`]
    stdout: StdioCollector {
      onStreamFinished: {
        const f = text.trim().split(" ")
        sys.hasBacklight = f.length >= 3 && (f[0] === "backlight" || f[0] === "ddc")
        if (!sys.hasBacklight) return
        sys.brKind = f[0]
        sys.brMax = parseInt(f[2]) || 100
        sys.brDevice = f[3] || ""
        sys.brightness = Math.max(0, Math.min(1, parseInt(f[1]) / 100))
      }
    }
  }
  // One write at a time: values that come while one runs (a slider dragged,
  // a key held) wait, and only the last is written.
  property bool brPending: false
  property Process brWrite: Process { onExited: if (sys.brPending) sys.writeBrightness() }
  function writeBrightness() {
    brPending = false
    brWrite.command = brKind === "ddc"
      ? ["ddcutil", "setvcp", "10", String(Math.round(brightness * brMax)), "--noverify"]
      : ["brightnessctl", "-q", "-d", brDevice, "set", Math.round(brightness * 100) + "%"]
    brWrite.running = true
  }
  function setBrightness(v) {
    if (!hasBacklight) return
    brightness = Math.max(brKind === "ddc" ? 0 : 0.02, Math.min(1, v))   // a backlight at 0 is a black screen
    if (brWrite.running) brPending = true
    else writeBrightness()
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
  // The app behind a player, by name: Memora's Music plays through mpv, which calls itself "mpv".
  function playerName(p) { return !p ? "" : (/^mpv/i.test(p.identity || "") ? "Music" : (p.identity || "")) }
}
