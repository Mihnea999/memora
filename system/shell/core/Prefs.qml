pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shell preferences, shared by the shell and System Settings through
// ~/.config/memora/shell.json (both watch the file).
Singleton {
  id: p
  property int dockSize: 52
  property bool magnify: true
  property int magnifySize: 80
  property bool clock24: true
  property bool showDate: true
  property string wallpaper: ""        // a picture of yours; empty: the set below
  property string wallpaperSet: "ribbon" // ribbon | dune | prism | silk, follows light/dark
  // Motion
  property bool animations: true
  property real animationSpeed: 1.0    // 0.5 slow … 2 fast
  property string windowStyle: "pop"   // pop | slide | fade (Hyprland)
  property bool dockBounce: true
  property bool snapping: true
  // Look
  property real transparency: 1.0      // 0 solid … 1 full glass
  property bool menuBarTransparent: true

  readonly property var keys: ["dockSize", "magnify", "magnifySize", "clock24", "showDate", "wallpaper", "wallpaperSet",
    "animations", "animationSpeed", "windowStyle", "dockBounce", "snapping", "transparency", "menuBarTransparent"]

  // A duration, scaled by the speed setting; 0 when animations are off.
  function motion(ms) { return animations ? Math.round(ms / Math.max(0.25, animationSpeed)) : 0 }

  property FileView file: FileView {
    path: Quickshell.env("HOME") + "/.config/memora/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const j = JSON.parse(text())
        p.keys.forEach(k => { if (j[k] !== undefined) p[k] = j[k] })
      } catch (e) {}
    }
  }

  function set(key, value) {
    p[key] = value
    if (["animations", "animationSpeed", "windowStyle"].indexOf(key) >= 0) writeMotion()
    const j = {}
    keys.forEach(k => j[k] = p[k])
    file.setText(JSON.stringify(j, null, 2) + "\n")
  }

  // Hyprland's own animations follow the same settings (default/hypr/look.lua reads this).
  property FileView motionFile: FileView { path: Quickshell.env("HOME") + "/.config/memora/motion.lua"; printErrors: false }
  property Timer reloadLater: Timer { interval: 250; onTriggered: Quickshell.execDetached(["hyprctl", "reload", "config-only"]) }
  function writeMotion() {
    motionFile.setText("-- Written by System Settings > Animations.\nreturn { enabled = " + animations + ", speed = " + animationSpeed.toFixed(2) + ", style = \"" + windowStyle + "\" }\n")
    reloadLater.restart()
  }
}
