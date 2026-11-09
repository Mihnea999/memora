import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Window docking with the mouse.
//   Drag to the left or right edge      half of the screen
//   Drag to a corner                    a quarter
//   Drag to the top edge                the whole free area
//   Drag to the middle of the top edge  a bar of layouts opens; drop on any
//                                       part of one (halves, thirds, 2/3 + 1/3,
//                                       quarters) to put the window there
//   Drag a docked window away           it goes back to its own size
// After docking to one side, Snap Assist offers the other windows for the rest
// of the screen. Hyprland tells the shell when the left button goes down and
// up (binds.lua); in between the shell follows the pointer.
Scope {
  id: snap
  property bool held: false
  property bool moving: false
  property string zone: ""
  property string addr: ""
  property var startAt: null
  property real cx: 0
  property real cy: 0
  property var mon: null          // { name, x, y, w, h, l, t, r, b } logical
  property bool layoutsOpen: false
  property bool unsnapped: false
  readonly property int edge: 6
  readonly property int corner: 120

  // ---- zones and layouts, shared with memora-window (default/zones.json)
  property var zoneData: ({ zones: {}, layouts: {} })
  FileView {
    path: Theme.share + "/default/zones.json"
    printErrors: false
    onLoaded: { try { snap.zoneData = JSON.parse(text()) } catch (e) {} }
  }
  // The shape of a screen's free area: compact, wide, portrait or regular.
  function kindOf(m) {
    if (!m) return "regular"
    const aw = m.w - m.l - m.r, ah = m.h - m.t - m.b
    return ah > aw ? "portrait" : (aw / Math.max(1, ah) >= 2.1 ? "wide" : (aw < 1400 ? "compact" : "regular"))
  }
  // The layouts bar for the screen under the pointer: [[zone, fx, fy, fw, fh], …] per layout.
  readonly property var layouts: ((zoneData.layouts || {})[kindOf(mon)] || []).map(l => l.map(z => [z].concat(zoneData.zones[z] || [0, 0, 1, 1])))
  // The dragged window's smallest size (Memora plugin): zones smaller are not offered.
  property size minSize: Qt.size(1, 1)
  property var sizeMap: ({})          // address -> [minW, minH], every window
  function minOf(a) { const e = sizeMap["0x" + String(a).replace(/^0x/, "")]; return e || [1, 1] }
  Process {
    id: sizes
    property string want: ""
    command: ["hyprctl", "memora-sizes"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const all = JSON.parse(text), map = {}
          all.forEach(x => map[x.address] = x.min)
          snap.sizeMap = map
          const e = all.find(x => x.address === sizes.want)
          if (e) snap.minSize = Qt.size(e.min[0], e.min[1])
        } catch (err) {}
      }
    }
  }
  function fits(z, m) {
    if (!z || !m) return false
    const r = rectFor(z, m)
    return r.width + 2 >= minSize.width && r.height + 2 >= minSize.height
  }
  readonly property int cellW: 104
  readonly property int cellH: 66
  readonly property int cellGap: 12
  readonly property int barPad: 14
  function barRect(m) {
    const w = layouts.length * cellW + (layouts.length - 1) * cellGap + 2 * barPad
    return Qt.rect((m.w - w) / 2, m.t + 10, w, cellH + 2 * barPad + 18)
  }
  // The zone under a point of the bar, or "" between layouts.
  function barZone(x, y, m) {
    const b = barRect(m)
    const lx = x - b.x - barPad, ly = y - b.y - barPad
    if (ly < -4 || ly > cellH + 4) return ""
    const i = Math.floor(lx / (cellW + cellGap))
    if (i < 0 || i >= layouts.length) return ""
    const fx = (lx - i * (cellW + cellGap)) / cellW, fy = Math.max(0, Math.min(0.999, ly / cellH))
    if (fx < 0 || fx > 1) return ""
    const seg = layouts[i].find(s => fx >= s[1] && fx < s[1] + s[3] + 0.001 && fy >= s[2] && fy < s[2] + s[4] + 0.001)
    return seg && fits(seg[0], m) ? seg[0] : ""
  }

  IpcHandler {
    target: "snap"
    function begin(): void { if (!Prefs.snapping) return; snap.held = true; snap.moving = false; snap.zone = ""; snap.startAt = null; snap.addr = ""; snap.layoutsOpen = false; snap.unsnapped = false; snap.minSize = Qt.size(1, 1); poll.running = true }
    function end(): void {
      const z = snap.zone, a = snap.addr, m = snap.moving, mon = snap.mon
      snap.held = false; snap.zone = ""; snap.moving = false; snap.layoutsOpen = false
      if (z && m && a) {
        Quickshell.execDetached(["memora-window", z, a])
        if (Prefs.snapAssist && snap.complement[z]) assist.offer(snap.complement[z], a, mon)
      } else if (m || !Prefs.snapping) Quickshell.execDetached(["memora-window", "inside"])   // dragged: not left under the menu bar
    }
  }

  // One look at the pointer, the focused window and its monitor.
  Process {
    id: probe
    command: ["bash", "-c", "hyprctl -j cursorpos; echo '\x1e'; hyprctl -j clients; echo '\x1e'; hyprctl -j monitors"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.split("\x1e\n")
        let c, cl, ms
        try { c = JSON.parse(parts[0]); cl = JSON.parse(parts[1]); ms = JSON.parse(parts[2]) } catch (e) { return }
        if (!snap.held) return
        snap.cx = c.x; snap.cy = c.y
        // The window being dragged: the one that moved since the button went
        // down (with click to focus it need not be the focused one).
        if (snap.startAt === null) { const m0 = {}; cl.forEach(x => m0[x.address] = x.at); snap.startAt = m0; return }
        let w = snap.addr ? cl.find(x => x.address === snap.addr) : null
        if (!w) w = cl.find(x => snap.startAt[x.address] && (Math.abs(x.at[0] - snap.startAt[x.address][0]) > 4 || Math.abs(x.at[1] - snap.startAt[x.address][1]) > 4)) || null
        if (!w || !w.floating || w.fullscreen) { snap.zone = ""; return }
        if (snap.addr !== w.address) { snap.addr = w.address; sizes.want = w.address; sizes.running = true }
        const st = snap.startAt[w.address] || w.at
        if (!snap.moving && (Math.abs(w.at[0] - st[0]) > 4 || Math.abs(w.at[1] - st[1]) > 4)) {
          snap.moving = true
          // A docked window being dragged away takes back its own size.
          if (!snap.unsnapped) { snap.unsnapped = true; Quickshell.execDetached(["memora-window", "unsnap", w.address, String(c.x), String(c.y)]) }
        }
        const m = ms.find(x => c.x >= x.x && c.x < x.x + x.width / x.scale && c.y >= x.y && c.y < x.y + x.height / x.scale) || ms[0]
        snap.mon = { name: m.name, x: m.x, y: m.y, w: m.width / m.scale, h: m.height / m.scale, l: m.reserved[0], t: m.reserved[1], r: m.reserved[2], b: m.reserved[3] }
        const z = snap.moving ? snap.zoneAt(c.x - m.x, c.y - m.y, snap.mon) : ""
        snap.zone = snap.fits(z, snap.mon) ? z : ""
      }
    }
  }
  Timer { id: poll; interval: 40; repeat: true; running: false; onTriggered: { if (!snap.held) { stop(); return } if (!probe.running) probe.running = true } }

  function zoneAt(x, y, m) {
    // The layouts bar: opens at the middle of the top edge, stays while the
    // pointer is over it.
    if (Prefs.snapLayouts) {
      const b = barRect(m)
      const inBar = x >= b.x - 20 && x <= b.x + b.width + 20 && y <= b.y + b.height + 20
      if (y <= m.t + edge + 2 && x > m.w * 0.3 && x < m.w * 0.7) layoutsOpen = true
      else if (!inBar) layoutsOpen = false
      if (layoutsOpen) return barZone(x, y, m)
    }
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
    const f = (zoneData.zones || {})[z]
    if (!f) return Qt.rect(snap.cx - m.x - 20, snap.cy - m.y - 20, 40, 40)
    const x0 = ax + f[0] * (aw + g), y0 = ay + f[1] * (ah + g)
    return Qt.rect(x0, y0, ax + (f[0] + f[2]) * (aw + g) - g - x0, ay + (f[1] + f[3]) * (ah + g) - g - y0)
  }
  // What is left of the screen after docking to a side.
  readonly property var complement: ({
    "left": "right", "right": "left", "left-third": "right-two-thirds", "right-third": "left-two-thirds",
    "left-two-thirds": "right-third", "right-two-thirds": "left-third",
    "top": "bottom", "bottom": "top", "top-third": "bottom-two-thirds", "bottom-third": "top-two-thirds",
    "top-two-thirds": "bottom-third", "bottom-two-thirds": "top-third"
  })

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
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-snap"
      mask: Region {}

      readonly property rect target: snap.mon ? snap.rectFor(snap.zone, snap.mon) : Qt.rect(0, 0, 0, 0)
      Glass {
        id: ghost
        x: win.target.x; y: win.target.y; width: win.target.width; height: win.target.height
        radius: 16
        fill: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.16 : 0.2)
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

      // The layouts bar.
      Glass {
        id: bar
        readonly property rect r: snap.mon ? snap.barRect(snap.mon) : Qt.rect(0, 0, 0, 0)
        x: r.x; y: r.y + (snap.layoutsOpen ? 0 : -16); width: r.width; height: r.height
        radius: 20
        fill: Theme.glassStrong
        shadowSize: 30
        opacity: snap.layoutsOpen ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Prefs.motion(160) } }
        Behavior on y { NumberAnimation { duration: Prefs.motion(240); easing.type: Easing.OutQuint } }
        Row {
          x: snap.barPad; y: snap.barPad
          spacing: snap.cellGap
          Repeater {
            model: snap.layouts
            delegate: Item {
              required property var modelData
              width: snap.cellW; height: snap.cellH
              Repeater {
                model: modelData
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool on: snap.zone === modelData[0]
                  readonly property bool can: snap.fits(modelData[0], snap.mon)
                  opacity: can ? 1 : 0.3
                  x: modelData[1] * snap.cellW + 2; y: modelData[2] * snap.cellH + 2
                  width: modelData[3] * snap.cellW - 4; height: modelData[4] * snap.cellH - 4
                  radius: 6
                  color: on ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.1))
                  border.width: 1; border.color: on ? Qt.lighter(Theme.accent, 1.3) : Theme.separator
                  Behavior on color { ColorAnimation { duration: Theme.fast } }
                }
              }
            }
          }
        }
        Txt {
          anchors { bottom: parent.bottom; bottomMargin: 8; horizontalCenter: parent.horizontalCenter }
          text: "Drop the window on a part of a layout"; color: Theme.textDim; font.pixelSize: Theme.small - 0.5
        }
      }
    }
  }

  // ---- Snap Assist ---------------------------------------------------------------
  QtObject {
    id: assist
    property string zone: ""
    property string placed: ""
    property var mon: null
    function offer(z, a, m) {
      const others = Apps.windows.filter(w => String(w.address).replace(/^0x/, "") !== String(a).replace(/^0x/, "")
        && w.workspace && Hyprland.focusedWorkspace && w.workspace.id === Hyprland.focusedWorkspace.id && !Apps.isMinimized(w))
      const r = m ? snap.rectFor(z, m) : null
      if (!others.some(w => !r || (snap.minOf(w.address)[0] <= r.width + 2 && snap.minOf(w.address)[1] <= r.height + 2))) return
      Hyprland.refreshToplevels()
      mon = m; placed = a; zone = z
    }
    function pick(w) {
      const z = zone; zone = ""
      Quickshell.execDetached(["memora-window", z, "0x" + String(w.address).replace(/^0x/, "")])
      Qt.callLater(() => Apps.focus(w))
    }
    function dismiss() { zone = "" }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: aw
      required property var modelData
      screen: modelData
      readonly property bool here: !!assist.mon && assist.mon.name === modelData.name
      visible: here && (assist.zone !== "" || afade.running)
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.namespace: "memora-overview"
      WlrLayershell.keyboardFocus: assist.zone !== "" && here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      property real shown: assist.zone !== "" ? 1 : 0
      Behavior on shown { NumberAnimation { id: afade; duration: Theme.normal; easing.type: Theme.easing } }
      // Only the free part is covered; the docked window stays clickable-free.
      readonly property rect area: assist.mon && assist.zone ? snap.rectFor(assist.zone, assist.mon) : Qt.rect(0, 0, 0, 0)
      mask: Region { item: aw.shown > 0 ? catcher : null }
      Item {
        id: catcher
        anchors.fill: parent
        focus: assist.zone !== ""
        Keys.onEscapePressed: assist.dismiss()
        TapHandler { onTapped: assist.dismiss() }
      }
      Glass {
        x: aw.area.x; y: aw.area.y; width: aw.area.width; height: aw.area.height
        radius: 16
        fill: Theme.glassStrong
        shadowSize: 30
        opacity: aw.shown
        scale: 0.96 + 0.04 * aw.shown
        TapHandler {}
        Txt { x: 20; y: 16; text: "Choose a window for this side"; font.weight: Font.Bold; color: Theme.textDim; font.pixelSize: Theme.small }
        Flow {
          id: flow
          anchors { fill: parent; margins: 20; topMargin: 44 }
          spacing: 16
          // Only windows that can shrink to the free part.
          readonly property var wins: assist.zone ? Apps.windows.filter(w => String(w.address).replace(/^0x/, "") !== String(assist.placed).replace(/^0x/, "")
            && w.workspace && Hyprland.focusedWorkspace && w.workspace.id === Hyprland.focusedWorkspace.id && !Apps.isMinimized(w)
            && snap.minOf(w.address)[0] <= aw.area.width + 2 && snap.minOf(w.address)[1] <= aw.area.height + 2) : []
          readonly property real cw: Math.min(300, (width - 16) / Math.max(1, Math.min(2, wins.length)) - 16)
          Repeater {
            model: flow.wins
            delegate: Item {
              id: c
              required property var modelData
              required property int index
              readonly property var o: modelData.lastIpcObject
              width: flow.cw; height: flow.cw * Math.min(0.75, o.size[1] / Math.max(1, o.size[0])) + 30
              opacity: 0
              Component.onCompleted: appear.start()
              NumberAnimation { id: appear; target: c; property: "opacity"; to: 1; duration: Theme.normal; easing.type: Theme.easing }
              Rectangle {
                id: frame
                width: parent.width; height: parent.height - 30
                radius: 10; clip: true
                color: Theme.field
                border.width: ch.hovered ? 3 : 1; border.color: ch.hovered ? Theme.accent : Theme.separator
                ScreencopyView { anchors.fill: parent; anchors.margins: 2; captureSource: assist.zone && c.modelData.wayland ? c.modelData.wayland : null; live: false }
              }
              Row {
                anchors { top: frame.bottom; topMargin: 7; horizontalCenter: parent.horizontalCenter }
                spacing: 6
                AppIcon { appId: Apps.classOf(c.modelData); width: 18; height: 18 }
                Txt { text: Apps.nameFor(Apps.classOf(c.modelData)); font.pixelSize: Theme.small; anchors.verticalCenter: parent.verticalCenter }
              }
              scale: ch.hovered ? 1.03 : 1
              Behavior on scale { NumberAnimation { duration: Theme.fast } }
              HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: assist.pick(c.modelData) }
            }
          }
        }
      }
    }
  }
}
