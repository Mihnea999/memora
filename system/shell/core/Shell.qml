pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Which shell surface is open. Only one at a time, like a desktop: opening the
// Control Center closes a menu, opening Launchpad closes Spotlight, and so on.
Singleton {
  id: s

  // "", "menu", "control", "calendar", "launchpad", "spotlight", "switcher", "ai"
  property string open: ""
  // For "menu": which menu of the bar is showing, and where it hangs.
  property string menu: ""
  property real menuX: 0
  property var menuScreen: null

  function toggle(name) { open = (open === name) ? "" : name }
  function show(name) { open = name }
  function close() { open = ""; menu = "" }

  function openMenu(id, x, screen) {
    menu = id; menuX = x; menuScreen = screen; open = "menu"
  }

  // A question on screen (alert/Alert.qml): { title, message, action, sym, danger, countdown, onAccept }
  property var alert: null
  function ask(o) { close(); alert = o }
  function power(what) {
    const run = cmd => Quickshell.execDetached(["bash", "-c", cmd])
    if (what === "shutdown") ask({ title: "Shut down your computer now?", message: "If you do nothing, it will shut down in %s seconds.", action: "Shut Down", sym: "power", countdown: true, onAccept: () => run("systemctl poweroff") })
    else if (what === "restart") ask({ title: "Restart your computer now?", message: "If you do nothing, it will restart in %s seconds.", action: "Restart", sym: "restart", countdown: true, onAccept: () => run("systemctl reboot") })
    else if (what.startsWith("restart:")) {
      const o = otherSystems.find(x => x.entry === what.slice(8))
      if (o) ask({ title: "Restart into " + o.name + "?", message: "The computer starts " + o.name + " once; next time it starts Memora again. If you do nothing, it will restart in %s seconds.", action: "Restart", sym: "restart", countdown: true, onAccept: () => run("systemctl reboot --boot-loader-entry=" + o.entry) })
    }
    else if (what === "logout") ask({ title: "Log out of Memora?", message: "Open apps will be closed. If you do nothing, you will be logged out in %s seconds.", action: "Log Out", sym: "logout", countdown: true, onAccept: () => run("uwsm stop || hyprctl dispatch exit") })
    else if (what === "trash") ask({ title: "Empty the Trash?", message: "Everything in the Trash will be deleted. You can't undo this action.", action: "Empty Trash", sym: "close", danger: true, onAccept: () => run("gio trash --empty && memora-sound trash") })
  }

  // Other systems on this computer (memora-bootsync): [{ name, entry }], for
  // "Restart into Windows…".
  property var otherSystems: []
  FileView {
    path: "/etc/memora/other-systems"; printErrors: false
    onLoaded: s.otherSystems = text().split("\n").filter(l => l.indexOf("|") > 0)
      .map(l => ({ name: l.split("|")[0], entry: l.split("|")[1] }))
  }

  // Do-not-disturb, shared by Control Center and notifications.
  property bool focusMode: false

  // ---- Keep Awake ------------------------------------------------------------
  // The screen stays on, doesn't lock and the computer doesn't sleep: while Keep
  // Awake is on (for a while or until turned off), or while an app is full screen
  // on a screen (a film, a game, a presentation). A systemd "idle" inhibitor
  // does it (hypridle obeys it); Sleep from the menu still works. With "lid"
  // on, closing the lid doesn't put the computer to sleep either.
  property real now: Date.now()
  Timer { interval: 15000; repeat: true; running: Prefs.awakeUntil > 0; triggeredOnStart: true
    onTriggered: { s.now = Date.now(); if (Prefs.awakeUntil > 0 && s.now >= Prefs.awakeUntil) Prefs.set("awakeUntil", 0) } }
  readonly property bool keepAwake: Prefs.awakeUntil === -1 || (Prefs.awakeUntil > 0 && Prefs.awakeUntil > now)
  // minutes: 0 off, -1 until turned off.
  property real awakeSetAt: 0      // when a timed Keep Awake was started (which chip is lit)
  function setAwake(minutes) {
    now = Date.now(); awakeSetAt = now
    Prefs.set("awakeUntil", minutes === 0 ? 0 : (minutes < 0 ? -1 : now + minutes * 60000))
  }
  // "On", "Until 15:30"
  readonly property string awakeLabel: !keepAwake ? "Off" : (Prefs.awakeUntil === -1 ? "On"
    : "Until " + Qt.formatTime(new Date(Prefs.awakeUntil), Prefs.clock24 ? "HH:mm" : "h:mm AP"))

  // An app is full screen (not just maximized) on a desktop that is showing.
  readonly property bool fullscreenApp: {
    const shown = Hyprland.monitors.values.map(m => m.activeWorkspace ? m.activeWorkspace.id : -1)
    return Hyprland.toplevels.values.some(w => {
      const o = w.lastIpcObject
      return o && o.fullscreen === 2 && o.workspace && shown.indexOf(o.workspace.id) >= 0
    })
  }
  readonly property bool inhibiting: keepAwake || (Prefs.awakeFullscreen && fullscreenApp)
  property bool main: false        // set by the desktop shell (shell.qml); apps only read this singleton
  Process {
    running: s.main && s.inhibiting
    command: ["systemd-inhibit", "--who=Memora", "--mode=block",
      "--what=" + (s.keepAwake && Prefs.awakeLid ? "idle:handle-lid-switch" : "idle"),
      "--why=" + (s.keepAwake ? "Keep Awake is on" : "An app is full screen"), "sleep", "infinity"]
  }
  Connections {
    target: Hyprland
    function onRawEvent(ev) { if (ev.name === "fullscreen") Hyprland.refreshToplevels() }
  }
}
