//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.core
import qs.ui
import qs.bar
import qs.dock
import qs.wallpaper
import qs.launchpad
import qs.spotlight
import qs.control
import qs.notify
import qs.osd
import qs.polkit
import qs.switcher
import qs.lock
import qs.snap
import qs.alert
import qs.notch
import qs.display
import qs.desktops
import qs.share
import qs.corners
import qs.reminders

// Memora shell: one process draws the desktop picture, menu bar, Dock, Launchpad,
// Spotlight, Control Center, notifications, the password dialog and the lock screen.
ShellRoot {
  id: root
  Component.onCompleted: Shell.main = true   // this process holds Keep Awake's inhibitor
  // Window memory (frames, home screens, reopening after login) runs here.
  readonly property bool remembering: Frames.on

  // A chime when a charger is plugged in (laptops), like a Mac.
  Connections {
    target: UPower
    function onOnBatteryChanged() {
      // Only a real change from battery to charger on a laptop, not UPower
      // reporting its state while the desktop starts.
      const was = root.onBattery
      root.onBattery = UPower.onBattery
      const laptop = UPower.displayDevice && UPower.displayDevice.isLaptopBattery
      if (was && !UPower.onBattery && laptop && Date.now() - root.started > 5000)
        Quickshell.execDetached(["memora-sound", "power"])
    }
  }
  property bool onBattery: UPower.onBattery
  readonly property real started: Date.now()
  // The login screen shows your desktop picture and light or dark: a copy goes
  // where it can read it whenever either changes (memora-theme login-sync).
  readonly property string loginLook: Theme.mode + "|" + Theme.wallpaper
  onLoginLookChanged: loginSync.restart()
  Timer { id: loginSync; interval: 2000; running: true; onTriggered: Quickshell.execDetached(["memora-theme", "login-sync", Theme.wallpaper]) }
  // Screens change (plugged in or out) or the Dock moves: windows follow, so
  // docked ones dock again and none is left too big or out of reach.
  Timer { id: refitLater; interval: 900; onTriggered: Quickshell.execDetached(["memora-window", "refit"]) }
  Connections {
    target: Hyprland
    function onRawEvent(ev) { if (["monitoraddedv2", "monitorremovedv2", "monitorremoved"].indexOf(ev.name) >= 0) refitLater.restart() }
  }
  // The on-screen keyboard pops up for a tapped text field only while a finger
  // is used, never while typing with the mouse at hand.
  Connections {
    target: Input
    function onTouchChanged() { if (Host.hasTouchscreen) Quickshell.execDetached(["memora-touch", "keyboard", "auto", Input.touch ? "on" : "off"]) }
  }
  // Touch-screen gestures, recognised by the Memora plugin (plugin/touch.cpp).
  readonly property var gestures: ({
    "edge-bottom-short": () => Shell.dockPeek(),
    "edge-bottom-long": () => Shell.toggle("overview"),
    "edge-top-left": () => { Shell.menuScreen = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""; Shell.toggle("calendar") },
    "edge-top-right": () => { Shell.menuScreen = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""; Shell.toggle("control") },
    "edge-left": () => Quickshell.execDetached(["memora-shell", "desktop", "prev"]),
    "edge-right": () => Quickshell.execDetached(["memora-shell", "desktop", "next"]),
    "three-up": () => Shell.show("overview"),
    "three-down": () => { if (Shell.open !== "") Shell.close(); else Quickshell.execDetached(["memora-shell", "desktop", "expose", ""]) },
    "three-left": () => Quickshell.execDetached(["memora-shell", "desktop", "next"]),
    "three-right": () => Quickshell.execDetached(["memora-shell", "desktop", "prev"]),
    "pinch-in": () => Shell.toggle("launchpad"),
    "pinch-out": () => Quickshell.execDetached(["memora-shell", "show-desktop"])
  })
  Connections {
    target: Hyprland
    function onRawEvent(ev) { if (ev.name === "memoragesture" && root.gestures[ev.data]) root.gestures[ev.data]() }
  }
  Connections {
    target: Prefs
    function onDockPositionChanged() { refitLater.restart() }
    function onDockHidingChanged() { refitLater.restart() }
    function onDockSizeChanged() { refitLater.restart() }
  }
  Variants { model: Quickshell.screens; Wallpaper {} }
  Variants { model: Quickshell.screens; MenuBar {} }
  // The Dock is built again when it moves to another edge: a layer that changes
  // its anchors in place kept the size of the old edge (a tall, half-empty Dock).
  property string dockAt: Prefs.dockPosition
  property bool dockUp: true
  onDockAtChanged: dockDown.restart()   // not from inside the Dock's own menu
  Timer { id: dockDown; interval: 1; onTriggered: { root.dockUp = false; dockBack.restart() } }
  Timer { id: dockBack; interval: 60; onTriggered: root.dockUp = true }
  Variants { model: root.dockUp ? Quickshell.screens : []; Dock {} }
  // Overlays deferred slightly so wallpaper, menu bar and dock render instantly on login.
  // Activated immediately if any overlay or menu is opened before the timer triggers.
  property bool overlaysReady: false
  Timer {
    id: deferOverlays
    interval: 350
    running: true
    onTriggered: root.overlaysReady = true
  }
  Connections {
    target: Shell
    function onOpenChanged() { if (Shell.open !== "") root.overlaysReady = true }
  }

  Variants { model: root.overlaysReady ? Quickshell.screens : []; Launchpad {} }
  Variants { model: root.overlaysReady ? Quickshell.screens : []; Spotlight {} }
  Variants { model: root.overlaysReady ? Quickshell.screens : []; ControlCenter {} }
  Variants { model: root.overlaysReady ? Quickshell.screens : []; NotificationCenter {} }
  Variants { model: root.overlaysReady ? Quickshell.screens : []; Banners {} }
  Variants { model: root.overlaysReady ? Quickshell.screens : []; OsdView {} }
  PolkitDialog {}
  Switcher {}
  ShortcutSheet {}
  Lock {}
  Snap {}
  Divider {}
  WindowMenu {}
  Layouts {}
  Genie {}
  Alert {}
  ShareSheet {}
  AddAppDialog {}
  Notch {}
  Reminders {}
  Project {}
  Desktops {}
  HotCorners {}
  ShowDesktop { id: deskAside }

  IpcHandler {
    target: "osd"
    function volume(dir: string): void { Osd.volume(dir) }
    function brightness(dir: string): void { Osd.brightness(dir) }
  }

  // memora-shell toggle launchpad|spotlight|control|switcher, memora-shell close
  IpcHandler {
    target: "shell"
    function toggle(name: string): void { Shell.toggle(name) }
    function show(name: string): void { Shell.show(name) }
    function close(): void { Shell.close() }
    function power(what: string): void { Shell.power(what) }
    function restore(addr: string): void { const a = addr.replace(/^0x/, ""); const w = Hyprland.toplevels.values.find(t => String(t.address).replace(/^0x/, "") === a); if (w) Apps.restore(w) }
    function quitApp(): void { if (Shell.switcherApp) { Shell.switcherAction = "quit"; return } const w = Hyprland.activeToplevel; if (w) Apps.quit(Apps.classOf(Apps.windows.find(x => x.address === w.address) || w)) }
    function hideApp(): void {
      if (Shell.switcherApp) { Shell.switcherAction = "hide"; return }
      const w = Hyprland.activeToplevel; if (!w) return
      const c = Apps.classOf(Apps.windows.find(x => x.address === w.address) || w)
      Apps.windowsOf(c).filter(x => !Apps.isMinimized(x)).forEach(x => Apps.minimize(x.address))
    }
    function setFocusMode(on: string): void { Shell.focusMode = on === "on" || on === "true" }
    function toggleDockHiding(): void { Prefs.set("dockHiding", (Prefs.dockHiding || (Prefs.dockAutohide ? "always" : "auto")) === "always" ? "auto" : "always") }
    function semiFullscreen(): void { Apps.semiFullscreen() }
    // Nearby Share for these files (one path per line).
    function share(paths: string): void { Shell.close(); Shell.shareFiles = paths.split("\n").filter(p => p !== "") }
    // Add Game / Application modal sheet
    function addApp(path: string): void { Shell.close(); Shell.addApp(path || "") }
    // Three fingers down: leave what is open, or show the app's windows.
    function swipeDown(): void { if (Shell.open !== "") Shell.close(); else Quickshell.execDetached(["memora-shell", "desktop", "expose", ""]) }
    function pin(): void { Apps.dispatch('hl.dsp.window.pin({ action = "toggle" })') }
    // After screens changed (plugged in or out, scale, the Dock moved): windows follow.
    function refit(): void { Quickshell.execDetached(["memora-window", "refit"]) }
    function minimize(): void { if (Hyprland.activeToplevel) Apps.minimize(Hyprland.activeToplevel.address) }
    // The windows glide aside to the edges, and back (desktops/ShowDesktop.qml).
    function showDesktop(): void { deskAside.toggle() }
  }
}
