import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Show Desktop (Super+D, F3 with Super, a hot corner, four fingers spread):
// the windows glide aside to the nearest edges of their screens, leaving a thin
// strip of each, and glide back the same way. While they are aside the real
// windows wait in a hidden desktop (special:desktop), not in the Dock.
// They come back with the same shortcut, a click on a strip, a click on an app
// in the Dock, switching desktops or a new window opening.
Scope {
  id: sd
  property var items: []           // [{ addr, win, rect: {x,y,w,h}, ws, mon }]
  property real t: 0               // 0 in place, 1 aside
  readonly property bool shown: Shell.desktopShown
  readonly property int strip: 26  // how much of each window stays in sight

  function toggle() { shown ? back() : aside() }
  function aside() {
    if (shown || anim.running) return
    const showing = Hyprland.monitors.values.map(m => m.activeWorkspace ? m.activeWorkspace.id : -1)
    const ws = Apps.windows.filter(w => {
      const o = w.lastIpcObject
      return o && o.at && !Apps.isMinimized(w) && !o.pinned && o.workspace && showing.indexOf(o.workspace.id) >= 0
    })
    if (!ws.length) return
    // Oldest first, so putting them back in this order leaves the newest on top.
    ws.sort((a, b) => (b.lastIpcObject.focusHistoryID ?? 99) - (a.lastIpcObject.focusHistoryID ?? 99))
    items = ws.map(w => {
      const o = w.lastIpcObject
      const m = Hyprland.monitors.values.find(x => x.id === o.monitor)
      return { addr: "0x" + Apps.addrKey(w.address), win: w, rect: { x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1] }, ws: o.workspace.id, mon: m ? m.name : "" }
    })
    Shell.desktopShown = true
    hideLater.restart()          // once the pictures are taken
    anim.from = 0; anim.to = 1; anim.restart()
  }
  Timer {
    id: hideLater
    interval: 70
    onTriggered: sd.items.forEach(i => Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:desktop", follow = false, window = "address:' + i.addr + '" })'))
  }
  function back() {
    if (!shown) return
    anim.from = t; anim.to = 0; anim.restart()
  }
  function done() {
    if (anim.to > 0) return
    const list = items
    list.forEach(i => Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + i.ws + '", follow = false, window = "address:' + i.addr + '" })'))
    list.forEach(i => Hyprland.dispatch('hl.dsp.window.alter_zorder({ mode = "top", window = "address:' + i.addr + '" })'))
    if (list.length) Hyprland.dispatch('hl.dsp.focus({ window = "address:' + list[list.length - 1].addr + '" })')
    items = []
    Shell.desktopShown = false
  }
  NumberAnimation { id: anim; target: sd; property: "t"; duration: Prefs.motion(anim.to > 0 ? 420 : 360); easing.type: Easing.OutCubic; onFinished: sd.done() }

  // Anything else that brings windows back.
  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      if (!sd.shown || anim.running && anim.to === 0) return
      if (ev.name === "openwindow" || ev.name === "workspacev2" || ev.name === "activespecial") sd.back()
    }
  }
  Connections { target: Shell; function onRequestBackChanged() { if (Shell.requestBack) { Shell.requestBack = false; sd.back() } } }

  // Where a window goes: to the nearest edge of its screen, leaving a strip.
  function target(i, m) {
    const r = i.rect
    const cx = r.x + r.w / 2 - m.x, cy = r.y + r.h / 2 - m.y
    const dl = cx, dr = m.width - cx, dt = cy, db = m.height - cy
    const near = Math.min(dl, dr, dt, db)
    if (near === dl) return Qt.point(m.x - r.w + strip, r.y)
    if (near === dr) return Qt.point(m.x + m.width - strip, r.y)
    if (near === dt) return Qt.point(r.x, m.y - r.h + strip + 30)
    return Qt.point(r.x, m.y + m.height - strip)
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: layer
      required property var modelData
      screen: modelData
      readonly property var mine: sd.items.filter(i => i.mon === modelData.name)
      visible: mine.length > 0
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      // Above the desktop picture and widgets, under the menu bar and the Dock.
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.namespace: "memora-genie"
      mask: Region { regions: pics.children.filter(c => c.region).map(c => c.region) }
      Item {
        id: pics
        anchors.fill: parent
        Repeater {
          model: layer.mine
          delegate: Item {
            id: pic
            required property var modelData
            readonly property point to: sd.target(modelData, layer.modelData)
            readonly property real fx: modelData.rect.x - layer.modelData.x
            readonly property real fy: modelData.rect.y - layer.modelData.y
            x: fx + (to.x - layer.modelData.x - fx) * sd.t
            y: fy + (to.y - layer.modelData.y - fy) * sd.t
            width: modelData.rect.w; height: modelData.rect.h
            opacity: 1 - 0.25 * sd.t
            property Region region: Region { item: pic }
            ScreencopyView {
              anchors.fill: parent
              live: false
              captureSource: pic.modelData.win && pic.modelData.win.wayland ? pic.modelData.win.wayland : null
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sd.back() }
          }
        }
      }
    }
  }
}
