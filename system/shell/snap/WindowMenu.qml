import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// The window's own menu: right-click its title bar (the bar Memora draws, or the
// top strip of Memora's apps), long-press it, or Alt+Space. The same actions as
// Window in the menu bar, plus moving it to another desktop.
Scope {
  id: wm
  property bool open: false
  property var win: null
  property point at: Qt.point(0, 0)
  property bool atWindow: false        // Alt+Space: at the window's corner, not the pointer

  IpcHandler {
    target: "windowmenu"
    function show(addr: string): void { wm.begin(addr, false) }
    function keys(addr: string): void { wm.begin(addr, true) }
  }
  function begin(addr, kb) {
    Hyprland.refreshToplevels()
    const a = addr && addr !== "0" ? Apps.addrKey(addr) : (Hyprland.activeToplevel ? Apps.addrKey(Hyprland.activeToplevel.address) : "")
    const w = Apps.windows.find(x => Apps.addrKey(x.address) === a)
    if (!w) return
    Apps.dispatch('hl.dsp.focus({ window = "address:0x' + a + '" })')
    win = w; atWindow = kb
    if (kb) { const o = w.lastIpcObject; at = Qt.point(o.at[0] + 12, o.at[1] + 12); Shell.close(); open = true }
    else cursor.running = true
  }
  Process {
    id: cursor
    command: ["hyprctl", "-j", "cursorpos"]
    stdout: StdioCollector { onStreamFinished: { try { const c = JSON.parse(text); wm.at = Qt.point(c.x, c.y); Shell.close(); wm.open = true } catch (e) {} } }
  }
  Connections { target: Shell; function onOpenChanged() { if (Shell.open !== "") wm.open = false } }

  readonly property var items: {
    if (!open || !win) return []
    const cls = Apps.classOf(win), o = win.lastIpcObject
    const cur = o.workspace ? o.workspace.id : 0
    const desks = []
    for (let i = 1; i <= Math.max(Prefs.desktops, cur); i++)
      if (i !== cur) desks.push({ text: "Move to " + (((Prefs.desktopNames || [])[i - 1]) || "Desktop " + i), action: () => Apps.dispatch('hl.dsp.window.move({ workspace = "' + i + '", follow = false, window = "address:0x' + Apps.addrKey(win.address) + '" })') })
    return [{ text: "Full Screen", keys: "F11", action: () => Apps.dispatch('hl.dsp.window.fullscreen({ mode = "fullscreen" })') }]
      .concat(Menus.items("window", cls, Apps.nameFor(cls), win))
      .concat(desks.length ? [{ separator: true }].concat(desks) : [])
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: wl
      required property var modelData
      screen: modelData
      readonly property bool here: wm.at.x >= modelData.x && wm.at.x < modelData.x + modelData.width && wm.at.y >= modelData.y && wm.at.y < modelData.y + modelData.height
      visible: wm.open && here
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-panel"
      WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      Item {
        anchors.fill: parent
        focus: wl.visible
        Keys.onEscapePressed: wm.open = false
        TapHandler { acceptedButtons: Qt.AllButtons; onTapped: wm.open = false }
      }
      MenuPanel {
        x: Math.min(wm.at.x - wl.modelData.x, wl.width - width - 8)
        y: Math.min(wm.at.y - wl.modelData.y, wl.height - height - 8)
        width: implicitWidth; height: implicitHeight
        items: wm.items
        onPicked: item => { const run = item.action; wm.open = false; if (run) Qt.callLater(run) }
      }
    }
  }
}
