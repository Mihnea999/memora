//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs.core
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

// Memora shell: one process draws the desktop picture, menu bar, Dock, Launchpad,
// Spotlight, Control Center, notifications, the password dialog and the lock screen.
ShellRoot {
  id: root
  Component.onCompleted: Shell.main = true   // this process holds Keep Awake's inhibitor

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
  // Screens change (plugged in or out) or the Dock moves: windows follow, so
  // docked ones dock again and none is left too big or out of reach.
  Timer { id: refitLater; interval: 900; onTriggered: Quickshell.execDetached(["memora-window", "refit"]) }
  Connections {
    target: Hyprland
    function onRawEvent(ev) { if (["monitoraddedv2", "monitorremovedv2", "monitorremoved"].indexOf(ev.name) >= 0) refitLater.restart() }
  }
  Connections {
    target: Prefs
    function onDockPositionChanged() { refitLater.restart() }
    function onDockHidingChanged() { refitLater.restart() }
    function onDockSizeChanged() { refitLater.restart() }
  }
  Variants { model: Quickshell.screens; Wallpaper {} }
  Variants { model: Quickshell.screens; MenuBar {} }
  Variants { model: Quickshell.screens; Dock {} }
  Variants { model: Quickshell.screens; Launchpad {} }
  Variants { model: Quickshell.screens; Spotlight {} }
  Variants { model: Quickshell.screens; ControlCenter {} }
  Variants { model: Quickshell.screens; NotificationCenter {} }
  Variants { model: Quickshell.screens; Banners {} }
  Variants { model: Quickshell.screens; OsdView {} }
  PolkitDialog {}
  Switcher {}
  Lock {}
  Snap {}
  Divider {}
  Genie {}
  Alert {}
  ShareSheet {}
  Notch {}
  Project {}
  Desktops {}

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
    function pin(): void { Apps.dispatch('hl.dsp.window.pin({ action = "toggle" })') }
    // After screens changed (plugged in or out, scale, the Dock moved): windows follow.
    function refit(): void { Quickshell.execDetached(["memora-window", "refit"]) }
    function minimize(): void { if (Hyprland.activeToplevel) Apps.minimize(Hyprland.activeToplevel.address) }
    function showDesktop(): void {
      const shown = Apps.windows.filter(w => !Apps.isMinimized(w) && w.workspace && w.workspace.id === Hyprland.focusedWorkspace.id)
      if (shown.length) shown.forEach(w => Apps.minimize(w.address))
      else Apps.windows.filter(w => Apps.isMinimized(w)).forEach(w => Apps.restore(w))
    }
  }
}
