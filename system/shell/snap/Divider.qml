import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Windows docked side by side share the line between them: rest the pointer
// on the gap and a handle appears; drag it and both windows resize together.
// Double-click it to split the screen evenly again.
Scope {
  id: dv
  // Keep window positions fresh (Hyprland has no event for resizing).
  Timer { interval: 1200; repeat: true; running: Prefs.snapping; onTriggered: if (!dv.dragging) Hyprland.refreshToplevels() }
  property bool dragging: false

  // Pairs of windows on the current desktop that touch along a vertical seam.
  readonly property var pairs: {
    const ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    const list = Apps.windows.filter(w => w.lastIpcObject.workspace && w.lastIpcObject.workspace.id === ws
      && w.lastIpcObject.floating && !w.lastIpcObject.fullscreen && !Apps.isMinimized(w))
    const out = []
    for (const a of list) for (const b of list) {
      if (a === b) continue
      const A = a.lastIpcObject, B = b.lastIpcObject
      const gap = B.at[0] - (A.at[0] + A.size[0])
      const sameRow = Math.abs(A.at[1] - B.at[1]) <= 8 && Math.abs(A.size[1] - B.size[1]) <= 8
      if (!(gap >= 0 && gap <= 24 && sameRow)) continue
      // Not while another window lies over the line between them.
      const sx = A.at[0] + A.size[0], covered = list.some(c => {
        if (c === a || c === b) return false
        const C = c.lastIpcObject
        return C.at[0] < sx + gap + 8 && C.at[0] + C.size[0] > sx - 8 && C.at[1] < A.at[1] + A.size[1] && C.at[1] + C.size[1] > A.at[1]
      })
      if (!covered) out.push({ a: a, b: b, x: sx, gap: gap, y: A.at[1], h: A.size[1], mon: A.monitor })
    }
    return out
  }

  function sel(w) { return 'window = "address:0x' + String(w.address).replace(/^0x/, "") + '"' }
  // Put the seam at screen x (logical), keeping both windows at least 280 wide.
  function moveSeam(p, x) {
    const A = p.a.lastIpcObject, B = p.b.lastIpcObject
    const left = A.at[0], right = B.at[0] + B.size[0]
    x = Math.max(left + 280, Math.min(right - 280 - p.gap, x))
    const aw = Math.round(x - left), bx = Math.round(x + p.gap), bw = Math.round(right - bx)
    // Hyprland resizes around the middle, so each window is put back in place
    // after it is resized (again a moment later, once the app has redrawn).
    const place = () => {
      Hyprland.dispatch('hl.dsp.window.move({ x = ' + left + ', y = ' + A.at[1] + ', ' + sel(p.a) + ' })')
      Hyprland.dispatch('hl.dsp.window.move({ x = ' + bx + ', y = ' + B.at[1] + ', ' + sel(p.b) + ' })')
    }
    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + aw + ', y = ' + A.size[1] + ', ' + sel(p.a) + ' })')
    Hyprland.dispatch('hl.dsp.window.resize({ x = ' + bw + ', y = ' + B.size[1] + ', ' + sel(p.b) + ' })')
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
      readonly property var mine: dv.pairs.filter(p => {
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
      mask: Region { regions: handles.children.map(h => h.region) }

      Item {
        id: handles
        anchors.fill: parent
        Repeater {
          model: win.mine
          delegate: Item {
            id: h
            required property var modelData
            readonly property var p: modelData
            property real dragX: 0
            x: p.x - win.modelData.x + p.gap / 2 - width / 2 + (sd.active ? dragX : 0)
            y: p.y - win.modelData.y
            width: Math.max(12, p.gap + 6); height: p.h
            property Region region: Region { item: h }
            // The handle itself: a small glass pill in the middle of the seam.
            Rectangle {
              anchors.centerIn: parent
              width: 6; height: Math.min(80, parent.height * 0.25); radius: 3
              color: sd.active ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.45))
              opacity: hov.hovered || sd.active ? 1 : 0
              scale: hov.hovered || sd.active ? 1 : 0.6
              Behavior on opacity { NumberAnimation { duration: Theme.fast } }
              Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
            }
            HoverHandler { id: hov; cursorShape: Qt.SplitHCursor }
            DragHandler {
              id: sd
              target: null
              xAxis.enabled: true; yAxis.enabled: false
              onActiveChanged: { dv.dragging = active; if (!active) { h.dragX = 0; Qt.callLater(() => Hyprland.refreshToplevels()) } }
              onTranslationChanged: if (active) { h.dragX = translation.x; throttle.restart() }
            }
            Timer { id: throttle; interval: 30; onTriggered: dv.moveSeam(h.p, h.p.x + h.dragX) }
            TapHandler {
              onDoubleTapped: {
                const A = h.p.a.lastIpcObject, B = h.p.b.lastIpcObject
                dv.moveSeam(h.p, (A.at[0] + B.at[0] + B.size[0] - h.p.gap) / 2)
                Qt.callLater(() => Hyprland.refreshToplevels())
              }
            }
            Tip { text: "Drag to resize both · double-click to split evenly"; delay: 900 }
          }
        }
      }
    }
  }
}
