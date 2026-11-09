pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

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

  // A status menu (Wi-Fi, Bluetooth, Battery, Sound; bar/StatusMenu.qml) at the
  // right of the menu bar, e.g. from Control Center.
  function openStatus(kind) {
    const scr = menuScreen || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    menu = kind; menuX = 1e6; menuScreen = scr; open = "status"
  }
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

  // Width of the Memora AI notch in the middle of the menu bar (on the focused
  // screen), so the bar keeps its menus clear of it.
  property real notchWidth: 132
  // App menus that didn't fit before the notch: listed under "»" ([{ id, title }]).
  property var moreMenus: []

  // Do-not-disturb, shared by Control Center and notifications.
  property bool focusMode: false
  // Files being shared with a nearby device: the Share sheet is open (share/ShareSheet.qml).
  property var shareFiles: []
  // Windows in "semi full screen": filling the screen under the menu bar, with
  // the Dock out of the way (address -> true). See Apps.semiFullscreen.
  property var semi: ({})

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
    function onRawEvent(ev) {
      if (ev.name !== "fullscreen") return
      // What the window was before this change, for one never seen here yet.
      const t = Hyprland.activeToplevel
      s.fsHint = t && t.lastIpcObject ? (t.lastIpcObject.fullscreen || 0) : 0
      Hyprland.refreshToplevels()
      if (!s.main) return
      if (fsProbe.running) fsProbe.again = true
      else fsProbe.running = true
    }
  }

  // ---- the battery: warnings when it runs low, Low Power while unplugged --------
  readonly property var battery: UPower.displayDevice && UPower.displayDevice.isLaptopBattery ? UPower.displayDevice : null
  readonly property int batteryPct: battery ? Math.round(battery.percentage * 100) : 100
  readonly property bool discharging: !!battery && UPower.onBattery
  property int warnedAt: 101          // the lowest level already warned about since it was last charging
  onBatteryPctChanged: batteryWarn()
  onDischargingChanged: {
    if (!discharging) warnedAt = 101
    else batteryWarn()
    if (s.main && battery && Prefs.lowPowerOnBattery)
      Quickshell.execDetached(["powerprofilesctl", "set", discharging ? "power-saver" : "balanced"])
  }
  function batteryWarn() {
    if (!s.main || !discharging) return
    const level = [5, 10, 20].find(l => batteryPct <= l && l < warnedAt)
    if (level === undefined) return
    warnedAt = level
    const left = battery.timeToEmpty > 0 ? " · about " + Math.max(1, Math.round(battery.timeToEmpty / 60)) + " min left" : ""
    Quickshell.execDetached(["notify-send", "-a", "Battery", "-i", "battery-caution", "-u", level <= 10 ? "critical" : "normal",
      level <= 5 ? "Battery almost empty" : "Battery low",
      batteryPct + "% remaining" + left + (level <= 5 ? ". Plug it in now, or it will go to sleep." : ".")])
  }

  // Leaving full screen puts a window back as it was. Chromium (the Browser,
  // YouTube's full screen) asks to be maximized right after leaving it, so a
  // window that wasn't maximized came back filling the screen: such a request,
  // within 2 s of leaving full screen, is undone.
  property var fsState: ({})      // address -> 0 normal, 1 maximized, 2 full screen
  property var fsBefore: ({})     // address -> state before going full screen
  property var fsLeft: ({})       // address -> { at, before } when it left full screen
  property int fsHint: 0
  Process {
    id: fsProbe
    property bool again: false
    command: ["hyprctl", "-j", "activewindow"]
    onExited: if (again) { again = false; running = true }
    stdout: StdioCollector {
      onStreamFinished: {
        let w; try { w = JSON.parse(text) } catch (e) { return }
        if (!w || !w.address) return
        const a = w.address, now = w.fullscreen || 0, prev = a in s.fsState ? s.fsState[a] : s.fsHint
        if (now === 2 && prev !== 2) s.fsBefore[a] = prev
        if (prev === 2 && now !== 2) s.fsLeft[a] = { at: Date.now(), before: s.fsBefore[a] || 0 }
        const left = s.fsLeft[a]
        if (now === 1 && left && Date.now() - left.at < 2000 && left.before === 0 && w.fullscreenClient === 1) {
          delete s.fsLeft[a]
          Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })')   // toggles it off again
        }
        // And one that was maximized comes back maximized (Hyprland leaves it normal).
        if (prev === 2 && now === 0 && left && left.before === 1) { fsRemax.addr = a; fsRemax.restart() }
        s.fsState[a] = now
      }
    }
  }
  Timer {
    id: fsRemax
    property string addr: ""
    interval: 500
    onTriggered: fsCheck.running = true
  }
  Process {
    id: fsCheck
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector {
      onStreamFinished: {
        let w; try { w = JSON.parse(text) } catch (e) { return }
        if (w && w.address === fsRemax.addr && (w.fullscreen || 0) === 0)
          Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })')
      }
    }
  }
}
