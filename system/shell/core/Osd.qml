pragma Singleton
import QtQuick
import Quickshell
import qs.core

// What the OSD shows, and the volume/brightness steps behind the hardware keys.
Singleton {
  id: o
  property string kind: "volume"
  property real value: 0
  property bool muted: false
  property bool visible: false
  property Timer hideTimer: Timer { interval: 1400; onTriggered: o.visible = false }

  function show(k, v, m) { kind = k; value = v; muted = !!m; visible = true; hideTimer.restart() }

  function volume(dir) {
    if (dir === "mute") Sys.toggleMute()
    else Sys.changeVolume(Sys.volume + (dir === "up" ? 0.05 : -0.05), true)
    show("volume", Sys.volume, Sys.muted)
  }
  function brightness(dir) {
    if (!Sys.hasBacklight) { Sys.refreshBrightness(); return }
    Sys.setBrightness(Sys.brightness + (dir === "up" ? 0.05 : -0.05))
    show("brightness", Sys.brightness, false)
  }
}
