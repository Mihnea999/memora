pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

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
    else if (what === "trash") ask({ title: "Empty the Trash?", message: "Everything in the Trash will be deleted. You can't undo this action.", action: "Empty Trash", sym: "close", danger: true, onAccept: () => run("gio trash --empty") })
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
}
