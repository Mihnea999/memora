pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shell preferences, shared by the shell and System Settings through
// ~/.config/memora/shell.json (both watch the file).
Singleton {
  id: p
  property int dockSize: 58
  property bool magnify: true
  property int magnifySize: 86
  property bool clock24: true
  property bool showDate: true
  property string wallpaper: ""        // a picture of yours; empty: the set below
  property string wallpaperSet: "candy"   // candy | ember | tide | horizon | dunes | silk | sorbet | lagoon | petal | bubbles, follows light/dark
  property var wallpaperRecent: []     // your pictures used lately, newest first
  property bool batteryPercent: true   // the percentage next to the battery in the menu bar
  property bool lowPowerOnBattery: false   // Low Power mode while unplugged
  // Motion
  property bool animations: true
  property real animationSpeed: 1.0    // 0.5 slow … 2 fast
  property string windowStyle: "pop"   // pop | slide | fade (Hyprland)
  property bool dockBounce: true
  property bool dockAutohide: false    // old switch; dockHiding replaces it ("always" when it was on)
  property string dockHiding: ""       // auto | never | smart (when a window needs the room) | always; "" = from dockAutohide
  property string dockPosition: "bottom"   // bottom | left | right
  property bool dockDots: true         // a dot under apps that are open
  property string iconStyle: "color"   // color | mono (black and white) | tinted (the accent colour)
  property bool snapping: true
  // Look
  property real transparency: 1.0      // 0 solid … 1 full glass
  property bool menuBarTransparent: true
  // Liquid glass (System Settings > Appearance)
  property string glassStyle: "clear"  // clear | tinted
  property real blur: 0.0              // how much the glass frosts what is behind (0 … 1)
  property real shine: 1             // light on the glass edges (0 … 1), as ybouane/liquidglass at 1
  property real vibrancy: 0.7          // colour carried through the glass (0 … 1)
  property bool reduceTransparency: false
  property string accent: "blue"       // blue | purple | pink | red | orange | green | graphite
  // Privacy & Security
  property int lockAfter: 5            // minutes of inactivity before the screen locks; 0 never
  property int sleepAfter: 30          // minutes before the computer sleeps; 0 never
  // Battery & Energy
  property int displayOffAfter: 10     // minutes before the screen turns off; 0 never
  property bool sleepOnPower: true     // also sleep when idle while plugged in
  property real awakeUntil: 0          // Keep Awake: 0 off, -1 until turned off, else a time (ms since 1970)
  property bool awakeFullscreen: true  // stay awake while an app (a film, a game) is full screen
  property bool awakeLid: false        // with Keep Awake on, closing the lid doesn't put it to sleep
  // Sound
  property string alertSound: "glint"  // glint | drop | chime | bell | pebble | bubble | breeze | pluck (system/sounds)
  property real alertVolume: 0.7       // alert and sound-effect volume, relative to the output volume
  property bool startupSound: true     // a chord when the desktop starts
  property bool uiSounds: true         // screenshot, emptying the Trash, plugging in a charger
  property bool volumeFeedback: true   // a pop after changing the volume with the keys
  property bool updateCheck: true      // look for updates in the background and say when there are some
  // Desktops and windows
  property int desktops: 2             // how many desktops there are (more appear when needed)
  property bool snapAssist: true       // after docking a window, offer others for the rest of the screen
  property string font: "Inter"        // the system typeface (System Settings > Appearance)
  property bool snapLayouts: true      // drag a window to the top middle for a choice of layouts
  property var desktopNames: []
  property var hotCorners: ({})
  property bool reopenWindows: true    // reopen the apps that were open, after shutting down or logging out        // { tl, tr, bl, br }: overview | expose | desktop | launchpad | notifications | control | ai | lock | display        // names given in Mission Control ("" = Desktop N)

  readonly property var keys: ["dockSize", "magnify", "magnifySize", "clock24", "showDate", "wallpaper", "wallpaperSet", "wallpaperRecent", "batteryPercent", "lowPowerOnBattery",
    "animations", "animationSpeed", "windowStyle", "dockBounce", "dockAutohide", "dockHiding", "dockPosition", "dockDots", "iconStyle", "snapping", "transparency", "menuBarTransparent",
    "glassStyle", "blur", "shine", "vibrancy", "reduceTransparency", "accent", "font",
    "lockAfter", "sleepAfter", "displayOffAfter", "sleepOnPower", "awakeUntil", "awakeFullscreen", "awakeLid", "alertSound", "alertVolume", "startupSound", "uiSounds", "volumeFeedback", "updateCheck", "desktops", "snapAssist", "snapLayouts", "desktopNames", "hotCorners", "reopenWindows"]

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
    if (key === "wallpaper" && value) p.wallpaperRecent = [value].concat((p.wallpaperRecent || []).filter(f => f !== value)).slice(0, 6)
    if (["animations", "animationSpeed", "windowStyle"].indexOf(key) >= 0) writeMotion()
    if (["blur", "vibrancy", "reduceTransparency"].indexOf(key) >= 0) writeGlass()
    // Other apps (GTK, title bars Memora draws) take the typeface from memora-theme.
    if (key === "font") Quickshell.execDetached(["memora-theme", "font", String(value)])
    if (["lockAfter", "sleepAfter", "displayOffAfter", "sleepOnPower"].indexOf(key) >= 0) writeIdle()
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

  // Hyprland's blur follows the glass settings (default/hypr/look.lua reads this).
  property FileView glassFile: FileView { path: Quickshell.env("HOME") + "/.config/memora/glass.lua"; printErrors: false }
  function writeGlass() {
    glassFile.setText("-- Written by System Settings > Appearance.\nreturn { blur = " + blur.toFixed(2) + ", vibrancy = " + vibrancy.toFixed(2) + ", reduce = " + reduceTransparency + " }\n")
    reloadLater.restart()
  }

  // Locking, turning the screen off and sleeping when idle (hypridle). Keep
  // Awake and full-screen apps hold a systemd "idle" inhibitor (core/Shell.qml),
  // which hypridle obeys, so none of these fire while they are on.
  property FileView idleFile: FileView { path: Quickshell.env("HOME") + "/.config/hypr/hypridle.conf"; printErrors: false }
  function writeIdle() {
    let t = "# Written by System Settings (Lock Screen, Battery & Energy).\n"
    t += "general {\n  lock_cmd = memora-lock\n  before_sleep_cmd = memora-lock\n  after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'\n  ignore_systemd_inhibit = false\n  ignore_dbus_inhibit = false\n}\n"
    if (lockAfter > 0) t += "\nlistener {\n  timeout = " + lockAfter * 60 + "\n  on-timeout = memora-lock\n}\n"
    if (displayOffAfter > 0) {
      // Just after locking when both are the same, so the lock screen is what wakes up.
      const off = displayOffAfter * 60 + (displayOffAfter === lockAfter ? 30 : 0)
      t += "\nlistener {\n  timeout = " + off + "\n  on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'\n  on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'\n}\n"
    }
    if (sleepAfter > 0) t += "\nlistener {\n  timeout = " + sleepAfter * 60 + "\n  on-timeout = " + (sleepOnPower ? "systemctl suspend" : "memora-power idle-sleep") + "\n}\n"
    idleFile.setText(t)
    restartIdle.restart()
  }
  property Timer restartIdle: Timer { interval: 300; onTriggered: Quickshell.execDetached(["bash", "-c", "pkill -x hypridle; sleep 0.3; setsid uwsm app -- hypridle >/dev/null 2>&1 &"]) }
}
