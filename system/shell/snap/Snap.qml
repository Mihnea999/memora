import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Window docking: drag a window against an edge of the screen and a glass
// outline shows where it will go; let go and it settles there.
//   left / right edge          half of the screen
//   corners                    a quarter
//   top edge (the menu bar)    the whole free area
// Hyprland tells the shell when the left button goes down and up (binds.lua);
// in between the shell follows the pointer.
Scope {
  id: snap
  property bool held: false
  property bool moving: false
  property string zone: ""
  property string addr: ""
  property var startAt: null
  property real cx: 0
  property real cy: 0
  property var mon: null          // { x, y, w, h, l, t, r, b } logical
  readonly property int edge: 6
  readonly property int corner: 120

  IpcHandler {
    target: "snap"
    function begin(): void { if (!Prefs.snapping) return; snap.held = true; snap.moving = false; snap.zone = ""; snap.startAt = null; snap.addr = ""; poll.running = true }
    function end(): void {
      const z = snap.zone, a = snap.addr, m = snap.moving
      snap.held = false; snap.zone = ""; snap.moving = false
      if (z && m && a) Quickshell.execDetached(["memora-window", z, a])
    }
  }

  // One look at the pointer, the focused window and its monitor.
  Process {
    id: probe
    command: ["bash", "-c", "hyprctl -j cursorpos; echo '\x1e'; hyprctl -j activewindow; echo '\x1e'; hyprctl -j monitors"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.split("\x1e\n")
        let c, w, ms
        try { c = JSON.parse(parts[0]); w = JSON.parse(parts[1]); ms = JSON.parse(parts[2]) } catch (e) { return }
        if (!snap.held) return
        snap.cx = c.x; snap.cy = c.y
        if (!w || !w.address || !w.floating || w.fullscreen) { snap.zone = ""; return }
        if (snap.startAt === null || snap.addr !== w.address) { snap.addr = w.address; snap.startAt = w.at; return }
        if (!snap.moving && (Math.abs(w.at[0] - snap.startAt[0]) > 4 || Math.abs(w.at[1] - snap.startAt[1]) > 4)) snap.moving = true
        const m = ms.find(x => c.x >= x.x && c.x < x.x + x.width / x.scale && c.y >= x.y && c.y < x.y + x.height / x.scale) || ms[0]
        snap.mon = { name: m.name, x: m.x, y: m.y, w: m.width / m.scale, h: m.height / m.scale, l: m.reserved[0], t: m.reserved[1], r: m.reserved[2], b: m.reserved[3] }
        snap.zone = snap.moving ? snap.zoneAt(c.x - m.x, c.y - m.y, snap.mon) : ""
      }
    }
  }
  Timer { id: poll; interval: 40; repeat: true; running: false; onTriggered: { if (!snap.held) { stop(); return } if (!probe.running) probe.running = true } }

  function zoneAt(x, y, m) {
    const left = x <= edge, right = x >= m.w - edge - 1
    const top = y <= m.t + edge, bottom = y >= m.h - edge - 1
    if (left && y < m.t + corner) return "top-left"
    if (left && y > m.h - m.b - corner) return "bottom-left"
    if (right && y < m.t + corner) return "top-right"
    if (right && y > m.h - m.b - corner) return "bottom-right"
    if (left) return "left"
    if (right) return "right"
    if (top) return "fill"
    if (bottom && x < corner) return "bottom-left"
    if (bottom && x > m.w - corner) return "bottom-right"
    return ""
  }

  // The rectangle a zone covers, relative to the monitor.
  function rectFor(z, m) {
    const g = 10
    const ax = m.l + g, ay = m.t + g, aw = m.w - m.l - m.r - 2 * g, ah = m.h - m.t - m.b - 2 * g
    const hw = (aw - g) / 2, hh = (ah - g) / 2
    switch (z) {
    case "left": return Qt.rect(ax, ay, hw, ah)
    case "right": return Qt.rect(ax + hw + g, ay, hw, ah)
    case "fill": return Qt.rect(ax, ay, aw, ah)
    case "top-left": return Qt.rect(ax, ay, hw, hh)
    case "top-right": return Qt.rect(ax + hw + g, ay, hw, hh)
    case "bottom-left": return Qt.rect(ax, ay + hh + g, hw, hh)
    case "bottom-right": return Qt.rect(ax + hw + g, ay + hh + g, hw, hh)
    }
    return Qt.rect(snap.cx - m.x - 20, snap.cy - m.y - 20, 40, 40)
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      readonly property bool here: !!snap.mon && snap.mon.name === modelData.name
      visible: snap.held && snap.moving && here
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.namespace: "memora-snap"
      mask: Region {}

      readonly property rect target: snap.mon ? snap.rectFor(snap.zone, snap.mon) : Qt.rect(0, 0, 0, 0)
      Glass {
        id: ghost
        x: win.target.x; y: win.target.y; width: win.target.width; height: win.target.height
        radius: 16
        fill: Qt.rgba(1, 1, 1, Theme.dark ? 0.10 : 0.22)
        shadowSize: 30
        opacity: snap.zone !== "" ? 1 : 0
        scale: snap.zone !== "" ? 1 : 0.92
        Behavior on x { NumberAnimation { duration: Prefs.motion(240); easing.type: Easing.OutQuint } }
        Behavior on y { NumberAnimation { duration: Prefs.motion(240); easing.type: Easing.OutQuint } }
        Behavior on width { NumberAnimation { duration: Prefs.motion(240); easing.type: Easing.OutQuint } }
        Behavior on height { NumberAnimation { duration: Prefs.motion(240); easing.type: Easing.OutQuint } }
        Behavior on opacity { NumberAnimation { duration: Prefs.motion(160) } }
        Behavior on scale { NumberAnimation { duration: Prefs.motion(240); easing.type: Easing.OutBack } }
      }
    }
  }
}
