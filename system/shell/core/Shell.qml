pragma Singleton
import QtQuick
import Quickshell

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

  // Do-not-disturb, shared by Control Center and notifications.
  property bool focusMode: false
}
