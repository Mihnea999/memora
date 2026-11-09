import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Windows docked next to each other share the line between them: rest the
// pointer on the gap and a handle appears; drag it and every window along the
// line resizes together (halves, thirds, a half beside two quarters, quarters,
// windows above and below each other). Double-click it to split evenly again.
Scope {
  id: dv
  // Keep window positions fresh (Hyprland has no event for resizing).
  Timer { interval: 1200; repeat: true; running: Prefs.snapping; onTriggered: if (!dv.dragging) Hyprland.refreshToplevels() }
  property bool dragging: false

  function geo(w) { const o = w.lastIpcObject; return { w: w, x: o.at[0], y: o.at[1], r: o.at[0] + o.size[0], b: o.at[1] + o.size[1], mon: o.monitor } }

  // Seams on the current desktop: { vertical, at (the line), gap, from, to, before: [g], after: [g], mon }.
  readonly property var seams: {
    const ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    const list = Apps.windows.filter(w => w.lastIpcObject && w.lastIpcObject.at && w.lastIpcObject.workspace && w.lastIpcObject.workspace.id === ws
      && w.lastIpcObject.floating && !w.lastIpcObject.fullscreen && !w.lastIpcObject.pinned && !Apps.isMinimized(w)).map(geo)
    const out = [], seen = {}
    for (const vertical of [true, false]) {
      const lo = g => vertical ? g.x : g.y, hi = g => vertical ? g.r : g.b
      const s0 = g => vertical ? g.y : g.x, s1 = g => vertical ? g.b : g.r
      for (const a of list) {
        const line = hi(a)
        const key = (vertical ? "v" : "h") + Math.round(line / 6) + ":" + a.mon
        if (seen[key]) continue
        const before = list.filter(g => Math.abs(hi(g) - line) <= 4)
        const after = list.filter(g => lo(g) - line >= 0 && lo(g) - line <= 24 && before.some(b => s0(b) < s1(g) - 8 && s0(g) < s1(b) - 8))
        if (!after.length) continue
        const near = before.filter(b => after.some(g => s0(b) < s1(g) - 8 && s0(g) < s1(b) - 8))
        // Both sides span the same stretch of the line.
        const from = Math.min(...near.map(s0)), to = Math.max(...near.map(s1))
        const from2 = Math.min(...after.map(s0)), to2 = Math.max(...after.map(s1))
        if (Math.abs(from - from2) > 10 || Math.abs(to - to2) > 10) continue
        const gap = Math.min(...after.map(lo)) - line
        // Not while another window lies over the line.
        const covered = list.some(c => near.indexOf(c) < 0 && after.indexOf(c) < 0
          && lo(c) < line + gap + 8 && hi(c) > line - 8 && s0(c) < to && s1(c) > from)
        if (covered) continue
        seen[key] = true
        out.push({ vertical: vertical, at: line, gap: gap, from: from, to: to, before: near, after: after, mon: a.mon })
      }
    }
    return out
  }

  function sel(g) { return 'window = "address:0x' + String(g.w.address).replace(/^0x/, "") + '"' }
  // Put the seam at `pos` (screen pixels along its axis), keeping every window at least 240 wide/tall.
  function moveSeam(s, pos) {
    const lo = g => s.vertical ? g.x : g.y, hi = g => s.vertical ? g.r : g.b
    const minPos = Math.max(...s.before.map(g => lo(g) + 240)), maxPos = Math.min(...s.after.map(g => hi(g) - 240)) - s.gap
    pos = Math.round(Math.max(minPos, Math.min(maxPos, pos)))
    const place = () => {
      s.before.forEach(g => Hyprland.dispatch('hl.dsp.window.move({ x = ' + g.x + ', y = ' + g.y + ', ' + sel(g) + ' })'))
      s.after.forEach(g => Hyprland.dispatch('hl.dsp.window.move({ x = ' + (s.vertical ? pos + s.gap : g.x) + ', y = ' + (s.vertical ? g.y : pos + s.gap) + ', ' + sel(g) + ' })'))
    }
    // Hyprland resizes around the middle, so each window is put back in place
    // after it is resized (again a moment later, once the app has redrawn).
    s.before.forEach(g => Hyprland.dispatch('hl.dsp.window.resize({ x = ' + (s.vertical ? pos - g.x : g.r - g.x) + ', y = ' + (s.vertical ? g.b - g.y : pos - g.y) + ', ' + sel(g) + ' })'))
    s.after.forEach(g => Hyprland.dispatch('hl.dsp.window.resize({ x = ' + (s.vertical ? g.r - pos - s.gap : g.r - g.x) + ', y = ' + (s.vertical ? g.b - g.y : g.b - pos - s.gap) + ', ' + sel(g) + ' })'))
    place()
    settle.fn = place; settle.restart()
  }
  Timer { id: settle; property var fn: null; interval: 120; onTriggered: if (fn) fn() }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      readonly property var mine: dv.seams.filter(p => {
        const m = Hyprland.monitors.values.find(x => x.name === modelData.name)
        return m && p.mon === m.id
      })
      visible: Prefs.snapping && mine.length > 0
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.namespace: "memora-snap"
      // Only the seams take the pointer.
      mask: Region { regions: handles.children.filter(h => h.region).map(h => h.region) }

      Item {
        id: handles
        anchors.fill: parent
        Repeater {
          model: win.mine
          delegate: Item {
            id: h
            required property var modelData
            readonly property var s: modelData
            property real drag: 0
            readonly property real thick: Math.max(12, s.gap + 6)
            x: s.vertical ? s.at - win.modelData.x + s.gap / 2 - thick / 2 + (sd.active ? drag : 0) : s.from - win.modelData.x
            y: s.vertical ? s.from - win.modelData.y : s.at - win.modelData.y + s.gap / 2 - thick / 2 + (sd.active ? drag : 0)
            width: s.vertical ? thick : s.to - s.from
            height: s.vertical ? s.to - s.from : thick
            property Region region: Region { item: h }
            // The handle itself: a small pill in the middle of the seam.
            Rectangle {
              anchors.centerIn: parent
              width: h.s.vertical ? 6 : Math.min(80, parent.width * 0.25); height: h.s.vertical ? Math.min(80, parent.height * 0.25) : 6; radius: 3
              color: sd.active ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.45))
              opacity: hov.hovered || sd.active ? 1 : 0
              scale: hov.hovered || sd.active ? 1 : 0.6
              Behavior on opacity { NumberAnimation { duration: Theme.fast } }
              Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
            }
            HoverHandler { id: hov; cursorShape: h.s.vertical ? Qt.SplitHCursor : Qt.SplitVCursor }
            DragHandler {
              id: sd
              target: null
              xAxis.enabled: h.s.vertical; yAxis.enabled: !h.s.vertical
              onActiveChanged: { dv.dragging = active; if (!active) { h.drag = 0; Qt.callLater(() => Hyprland.refreshToplevels()) } }
              onTranslationChanged: if (active) { h.drag = h.s.vertical ? translation.x : translation.y; throttle.restart() }
            }
            Timer { id: throttle; interval: 30; onTriggered: dv.moveSeam(h.s, h.s.at + h.drag) }
            TapHandler {
              onDoubleTapped: {
                // Evenly: the line halfway between the two outer edges.
                const lo = Math.min(...h.s.before.map(g => h.s.vertical ? g.x : g.y))
                const hi = Math.max(...h.s.after.map(g => h.s.vertical ? g.r : g.b))
                dv.moveSeam(h.s, (lo + hi - h.s.gap) / 2)
                Qt.callLater(() => Hyprland.refreshToplevels())
              }
            }
            Tip { text: "Drag to resize the windows on both sides · double-click to split evenly"; delay: 900 }
          }
        }
      }
    }
  }
}
