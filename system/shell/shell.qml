//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
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

// Memora shell: one process draws the desktop picture, menu bar, Dock, Launchpad,
// Spotlight, Control Center, notifications, the password dialog and the lock screen.
ShellRoot {
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
  Genie {}
  Alert {}

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
    function minimize(): void { if (Hyprland.activeToplevel) Apps.minimize(Hyprland.activeToplevel.address) }
    function showDesktop(): void {
      const shown = Apps.windows.filter(w => !Apps.isMinimized(w) && w.workspace && w.workspace.id === Hyprland.focusedWorkspace.id)
      if (shown.length) shown.forEach(w => Apps.minimize(w.address))
      else Apps.windows.filter(w => Apps.isMinimized(w)).forEach(w => Apps.restore(w))
    }
  }
}
