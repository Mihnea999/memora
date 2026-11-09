import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.core
import qs.ui

// The Dock: pinned and running apps, then minimized windows, Downloads and Trash.
// Icons magnify under the pointer, running apps carry a dot, launching bounces.
PanelWindow {
  id: dock
  required property var modelData
  screen: modelData

  // Where it sits: bottom (default), left or right of the screen.
  readonly property string pos: ["left", "right"].indexOf(Prefs.dockPosition) >= 0 ? Prefs.dockPosition : "bottom"
  readonly property bool vertical: pos !== "bottom"
  // It always fits: with many apps on a small screen the icons get smaller
  // (magnification shrinks in step), as on a Mac.
  readonly property int count: Math.max(1, model.length - 1)
  readonly property real along: vertical ? modelData.height : modelData.width
  readonly property real fit: Math.max(30, Math.floor((along * 0.92 - 22 - 13 - 7 * (count - 1)) / count))
  readonly property real base: Math.min(Prefs.dockSize, fit)
  readonly property real peak: Prefs.magnify ? Math.max(Prefs.magnifySize * base / Math.max(1, Prefs.dockSize), base) : base
  readonly property real reach: 200      // how far magnification spreads, in px
  readonly property real gap: 6

  // Like a Mac: the Dock stays put and windows (zoomed ones too) end above it.
  // It steps aside for an app in full screen, or always with "Automatically hide
  // and show the Dock"; then pushing the pointer against the bottom edge brings
  // it back, and it leaves again once the pointer moves away.
  readonly property var monitor: Hyprland.monitors.values.find(m => m.name === modelData.name) || null
  readonly property bool fullscreen: {
    const ws = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    return Apps.windows.some(w => w.lastIpcObject.fullscreen === 2 && w.lastIpcObject.workspace && w.lastIpcObject.workspace.id === ws)
  }
  // A window in semi full screen here (Shift+F11): the Dock steps aside too.
  readonly property bool semi: {
    const ws = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    return Apps.windows.some(w => Shell.semi[Apps.addrKey(w.address)] && w.lastIpcObject.fullscreen === 1 && w.lastIpcObject.workspace && w.lastIpcObject.workspace.id === ws)
  }
  // Hiding: never, always, or "when needed": it stays until a window would
  // cover it. Automatic is "when needed" on small screens and "never" on big ones.
  readonly property string hideMode: {
    const h = Prefs.dockHiding || (Prefs.dockAutohide ? "always" : "auto")
    if (h !== "auto") return h
    return (vertical ? modelData.width < 1400 : modelData.height < 900) ? "smart" : "never"
  }
  // A window on this screen's desktop over the Dock's place.
  readonly property bool overlapped: {
    if (hideMode !== "smart" || !monitor) return false
    const ws = monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    const sx = modelData.x, sy = modelData.y
    const thick = base + 18 + gap + 4
    const len = (vertical ? row.height : row.width) + 22
    const r = pos === "bottom" ? Qt.rect(sx + (modelData.width - len) / 2, sy + modelData.height - thick, len, thick)
      : pos === "left" ? Qt.rect(sx, sy + (modelData.height - len) / 2, thick, len)
      : Qt.rect(sx + modelData.width - thick, sy + (modelData.height - len) / 2, thick, len)
    return Apps.windows.some(w => {
      const o = w.lastIpcObject
      if (!o || !o.at || !o.workspace || o.workspace.id !== ws || Apps.isMinimized(w)) return false
      return o.at[0] < r.x + r.width && o.at[0] + o.size[0] > r.x && o.at[1] < r.y + r.height && o.at[1] + o.size[1] > r.y
    })
  }
  // Window sizes change without an event: look again now and then.
  Timer { interval: 900; repeat: true; running: dock.hideMode === "smart"; onTriggered: Hyprland.refreshToplevels() }
  readonly property bool concealable: hideMode === "always" || (hideMode === "smart" && overlapped) || fullscreen || semi
  property bool revealed: false
  // Kept out while in use: under the pointer, its menu open, an icon dragged, Launchpad open.
  readonly property bool inUse: dockHover.hovered || menuFor !== null || draggingId !== "" || Shell.open === "launchpad"
  readonly property bool hidden: concealable && !revealed && !inUse
  onInUseChanged: if (!inUse && revealed) leave.restart()
  onConcealableChanged: revealed = false
  Timer { id: arrive; interval: dock.hideMode === "always" && !dock.fullscreen ? 60 : 180; onTriggered: { dock.revealed = true; leave.restart() } }
  Timer { id: leave; interval: 450; onTriggered: if (!dock.inUse && !edgeHover.hovered) dock.revealed = false; else if (!dock.inUse) restart() }

  anchors { bottom: true; top: vertical; left: pos !== "right"; right: pos !== "left" }
  implicitHeight: 170
  implicitWidth: 170
  exclusiveZone: hideMode === "never" && !fullscreen && !semi ? base + 22 + gap : 0
  color: "transparent"
  WlrLayershell.namespace: "memora-dock"
  // Over full-screen apps it must be above them to show at all.
  WlrLayershell.layer: fullscreen ? WlrLayer.Overlay : WlrLayer.Top
  mask: Region { item: dock.hidden ? edge : hit }

  // The edge of the screen: where the pointer calls a hidden Dock.
  Item {
    id: edge
    anchors {
      left: dock.pos !== "right" ? parent.left : undefined; right: dock.pos !== "left" ? parent.right : undefined
      top: dock.vertical ? parent.top : undefined; bottom: parent.bottom
    }
    height: dock.vertical ? parent.height : 2
    width: dock.vertical ? 2 : parent.width
    HoverHandler { id: edgeHover; onHoveredChanged: if (hovered && dock.hidden) arrive.restart(); else if (!hovered) arrive.stop() }
  }

  property real mouseX: -1000
  property string draggingId: ""

  // How far a drag went away from the screen edge (into the screen).
  function outward(d) { return pos === "bottom" ? -d.y : (pos === "left" ? d.x : -d.x) }
  function alongOf(d) { return vertical ? d.y : d.x }
  // An icon was let go: remove it if pulled out, else move it to where it landed.
  function dropped(item, d) {
    const id = item.appId
    const pinned = Apps.pinned.slice()
    const from = pinned.indexOf(id)
    if (outward(d) > item.height * 1.3) { if (from >= 0) { Apps.unpin(id); poof.at(item) } return }
    const x = item.centerX + alongOf(d)
    // Slot under the drop point, among the pinned apps.
    let to = 0
    for (let i = 0; i < items.count && i < pinned.length; i++) {
      const slot = row.itemAtIndex(i)
      if (slot && x > (vertical ? slot.y + slot.height / 2 : slot.x + slot.width / 2) + dock.rowX) to = i + 1
    }
    if (from < 0) { pinned.splice(Math.min(to, pinned.length), 0, id); Apps.savePinned(pinned); return }
    pinned.splice(from, 1)
    if (to > from) to--
    pinned.splice(Math.min(to, pinned.length), 0, id)
    Apps.savePinned(pinned)
  }
  // Positions along the Dock (x at the bottom, y at a side).
  readonly property real rowX: vertical ? row.y - row.contentY : row.x - row.contentX
  readonly property real hitX: vertical ? hit.y : hit.x
  readonly property bool magnifying: mouseX > -999

  // Everything shown, in order.
  readonly property var running: {
    const seen = {}
    const out = []
    Apps.windows.forEach(w => {
      const c = Apps.classOf(w)
      if (!c || seen[c] || Apps.isMinimized(w) || Apps.helperClasses.indexOf(c) >= 0) return
      seen[c] = true
      if (!Apps.pinned.some(p => Apps.sameApp(c, p))) out.push(c)
    })
    return out
  }
  readonly property var minimized: Apps.windows.filter(w => Apps.isMinimized(w))
  readonly property var model: {
    let m = Apps.pinned.map(id => ({ kind: "app", id: id }))
    m = m.concat(running.map(id => ({ kind: "app", id: id })))
    m.push({ kind: "sep" })
    m = m.concat(minimized.map(w => ({ kind: "window", id: Apps.classOf(w), win: w })))
    m.push({ kind: "folder", id: "downloads" })
    m.push({ kind: "trash", id: "trash" })
    return m
  }

  // Trash state, for the full/empty icon.
  property bool trashFull: false
  Process {
    id: trashProc
    command: ["bash", "-c", "[ -n \"$(ls -A ~/.local/share/Trash/files 2>/dev/null)\" ] && echo full || echo empty"]
    stdout: StdioCollector { onStreamFinished: dock.trashFull = text.trim() === "full" }
  }
  Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: trashProc.running = true }

  // ------------------------------------------------------------------ the bar
  Item {
    id: hit
    property real off: dock.hidden ? -(dock.base + 40) : dock.gap
    anchors.horizontalCenter: dock.vertical ? undefined : parent.horizontalCenter
    anchors.verticalCenter: dock.vertical ? parent.verticalCenter : undefined
    anchors.bottom: dock.vertical ? undefined : parent.bottom
    anchors.left: dock.pos === "left" ? parent.left : undefined
    anchors.right: dock.pos === "right" ? parent.right : undefined
    anchors.bottomMargin: off
    anchors.leftMargin: off
    anchors.rightMargin: off
    width: dock.vertical ? dock.base + 18 : row.width + 22
    height: dock.vertical ? row.height + 22 : dock.base + 18
    Behavior on off { NumberAnimation { duration: Theme.slow; easing.type: Theme.easing } }

    Glass {
      id: plate
      anchors.fill: parent
      radius: 26
      fill: Theme.glass
      shadowSize: 30
    }

    HoverHandler {
      id: dockHover
      onPointChanged: dock.mouseX = dock.vertical ? point.position.y : point.position.x
      onHoveredChanged: if (!hovered) dock.mouseX = -1000
    }

    // A ListView over a ListModel kept in step with `model`, so icons that
    // arrive grow in, icons that leave shrink away, and the rest slide aside.
    ListView {
      id: row
      anchors.bottom: dock.vertical ? undefined : parent.bottom
      anchors.bottomMargin: 8
      anchors.horizontalCenter: dock.vertical ? undefined : parent.horizontalCenter
      anchors.verticalCenter: dock.vertical ? parent.verticalCenter : undefined
      anchors.left: dock.pos === "left" ? parent.left : undefined
      anchors.right: dock.pos === "right" ? parent.right : undefined
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      orientation: dock.vertical ? ListView.Vertical : ListView.Horizontal
      interactive: false
      spacing: 7
      width: dock.vertical ? dock.base : contentWidth
      height: dock.vertical ? contentHeight : dock.base
      model: items
      // Each slot is as tall as the Dock; its icon sits on the bottom and grows upwards.
      delegate: Item {
        id: slot
        required property string key
        required property string kind
        readonly property var entry: dock.entries[key] || null
        width: dock.vertical ? dock.base : (icon.item ? icon.item.width : 0)
        height: dock.vertical ? (icon.item ? icon.item.height : 0) : dock.base
        // The icon sits against the screen edge and grows into the screen.
        Loader {
          id: icon
          anchors.bottom: dock.vertical ? undefined : parent.bottom
          anchors.left: dock.pos === "left" ? parent.left : undefined
          anchors.right: dock.pos === "right" ? parent.right : undefined
          sourceComponent: slot.kind === "sep" ? sepComp : itemComp
          property var entry: slot.entry
        }
      }
      add: Transition {
        NumberAnimation { property: "scale"; from: 0.1; to: 1; duration: Theme.slow; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal }
      }
      remove: Transition {
        NumberAnimation { property: "scale"; to: 0.1; duration: Theme.normal; easing.type: Easing.InCubic }
        NumberAnimation { property: "opacity"; to: 0; duration: Theme.normal }
      }
      displaced: Transition { NumberAnimation { properties: "x,y"; duration: Theme.slow; easing.type: Theme.easingEmph } }
      addDisplaced: Transition { NumberAnimation { properties: "x,y"; duration: Theme.slow; easing.type: Theme.easingEmph } }
      removeDisplaced: Transition { NumberAnimation { properties: "x,y"; duration: Theme.slow; easing.type: Theme.easingEmph } }
    }
  }

  // A small puff where a removed icon was.
  Item {
    id: poof
    width: 60; height: 60
    opacity: 0
    function at(item) {
      const p = item.mapToItem(dock.contentItem, item.width / 2 + item.drag.x, item.height / 2 + item.drag.y)
      x = p.x - 30; y = p.y - 30
      puff.restart()
    }
    Repeater {
      model: 6
      delegate: Rectangle {
        required property int index
        readonly property real ang: index / 6 * Math.PI * 2
        width: 12; height: 12; radius: 6
        color: Theme.text
        opacity: 0.6
        x: 24 + Math.cos(ang) * 22 * poof.spread; y: 24 + Math.sin(ang) * 22 * poof.spread
      }
    }
    property real spread: 0
    ParallelAnimation {
      id: puff
      NumberAnimation { target: poof; property: "spread"; from: 0.2; to: 1.4; duration: 380; easing.type: Easing.OutCubic }
      SequentialAnimation {
        NumberAnimation { target: poof; property: "opacity"; from: 0; to: 1; duration: 60 }
        NumberAnimation { target: poof; property: "opacity"; to: 0; duration: 320 }
      }
    }
  }

  // Minimized windows fly to the end of the Dock, before Downloads and Trash.
  function updateTarget() {
    const p = vertical ? hit.mapToItem(null, hit.width / 2, hit.height - 150) : hit.mapToItem(null, hit.width - 150, hit.height / 2)
    // The Dock's window sits against its edge of the screen; p is inside it.
    const wx = pos === "right" ? dock.modelData.width - dock.width : 0
    const wy = pos === "bottom" ? dock.modelData.height - dock.height : 0
    Apps.dockTarget = Qt.point(dock.modelData.x + wx + p.x, dock.modelData.y + wy + p.y)
  }
  Connections { target: hit; function onWidthChanged() { dock.updateTarget() } function onXChanged() { dock.updateTarget() } function onHeightChanged() { dock.updateTarget() } function onYChanged() { dock.updateTarget() } }
  onPosChanged: Qt.callLater(updateTarget)

  ListModel { id: items }
  property var entries: ({})
  function keyOf(e) { return e.kind === "window" ? "w:" + e.win.address : e.kind + ":" + e.id }
  function sync() {
    const want = dock.model
    const map = {}
    want.forEach(e => map[keyOf(e)] = e)
    entries = map
    // Drop what is gone, then insert or move the rest into place.
    for (let i = items.count - 1; i >= 0; i--) if (!map[items.get(i).key]) items.remove(i)
    want.forEach((e, i) => {
      const k = keyOf(e)
      let at = -1
      for (let j = i; j < items.count; j++) if (items.get(j).key === k) { at = j; break }
      if (at === -1) items.insert(i, { key: k, kind: e.kind })
      else if (at !== i) items.move(at, i, 1)
    })
  }
  onModelChanged: sync()
  Component.onCompleted: { sync(); updateTarget() }

  Component {
    id: sepComp
    Item {
      id: sepItem
      width: dock.vertical ? dock.base : 13; height: dock.vertical ? 13 : dock.base
      Rectangle { anchors.centerIn: parent; width: dock.vertical ? dock.base * 0.72 : 1; height: dock.vertical ? 1 : dock.base * 0.72; color: Theme.separator }
      // Right-click (or long-press) the divider: the Dock's own options, like on a Mac.
      HoverHandler { cursorShape: dock.vertical ? Qt.SizeHorCursor : Qt.SizeVerCursor }
      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: sepItem.openMenu()
      }
      TapHandler { onLongPressed: sepItem.openMenu() }
      function openMenu() { const p = sepItem.mapToItem(hit, sepItem.width / 2, sepItem.height / 2); dock.menuX = dock.hitX + (dock.vertical ? p.y : p.x); dock.menuFor = { kind: "sep", id: "sep" } }
    }
  }

  Component {
    id: itemComp
    DockItem {
      dockRoot: dock
      entry: parent ? parent.entry : null
    }
  }

  // Context menu for a dock icon.
  property var menuFor: null
  property real menuX: 0
  PopupWindow {
    id: ctx
    visible: dock.menuFor !== null
    anchor.window: dock
    anchor.rect.x: dock.pos === "bottom" ? Math.max(8, dock.menuX - ctxPanel.implicitWidth / 2)
      : (dock.pos === "left" ? dock.base + 34 : dock.width - dock.base - 64 - ctxPanel.implicitWidth)
    anchor.rect.y: dock.pos === "bottom" ? dock.height - dock.base - 30 - ctxPanel.implicitHeight
      : Math.max(8, Math.min(dock.height - ctxPanel.implicitHeight - 38, dock.menuX - ctxPanel.implicitHeight / 2))
    implicitWidth: ctxPanel.implicitWidth + 30
    implicitHeight: ctxPanel.implicitHeight + 30
    color: "transparent"
    MenuPanel {
      id: ctxPanel
      width: implicitWidth; height: implicitHeight
      items: dock.menuFor ? dock.menuItems(dock.menuFor) : []
      onPicked: item => { const run = item.action; dock.menuFor = null; if (run) Qt.callLater(run) }
    }
  }
  OutsideClick {
    when: ctx.visible
    windows: [ctx, dock]
    onOutside: dock.menuFor = null
  }

  function menuItems(e) {
    if (e.kind === "trash") return [
      { text: "Open", action: () => Apps.run("nautilus --new-window trash:///") },
      { separator: true },
      { text: "Empty Trash", enabled: dock.trashFull, action: () => Shell.power("trash") }
    ]
    if (e.kind === "sep") return [
      { text: dock.hideMode === "always" ? "Turn Hiding Off" : "Turn Hiding On", action: () => Prefs.set("dockHiding", dock.hideMode === "always" ? "auto" : "always") },
      { text: Prefs.magnify ? "Turn Magnification Off" : "Turn Magnification On", action: () => Prefs.set("magnify", !Prefs.magnify) },
      { separator: true },
      { text: "Position on Screen: Left", checked: dock.pos === "left", action: () => Prefs.set("dockPosition", "left") },
      { text: "Position on Screen: Bottom", checked: dock.pos === "bottom", action: () => Prefs.set("dockPosition", "bottom") },
      { text: "Position on Screen: Right", checked: dock.pos === "right", action: () => Prefs.set("dockPosition", "right") },
      { separator: true },
      { text: "Dock Settings…", action: () => Apps.run("memora-settings dock") }
    ]
    if (e.kind === "folder") return [
      { text: "Open Downloads", action: () => Apps.run("nautilus --new-window ~/Downloads") }
    ]
    const ws = Apps.windowsOf(e.id)
    const pinned = Apps.pinned.indexOf(e.id) >= 0
    let items = ws.map(w => ({ text: (w.title || Apps.nameFor(e.id)).slice(0, 48), checked: w.activated, action: () => Apps.focus(w) }))
    if (items.length) items.push({ separator: true })
    if (e.id !== "memora-launchpad") {
      items.push({ text: ws.length ? "New Window" : "Open", action: () => Apps.launch(e.id) })
      items.push({ separator: true })
      items.push(pinned ? { text: "Remove from Dock", action: () => Apps.unpin(e.id) } : { text: "Keep in Dock", action: () => Apps.pin(e.id) })
      if (Apps.removable(e.id)) items.push({ text: "Uninstall…", action: () => Apps.uninstall(e.id) })
    }
    if (ws.length) {
      items.push({ text: "Show All Windows", action: () => Apps.run("memora-shell desktop expose '" + e.id.replace(/'/g, "") + "'") })
      items.push({ separator: true })
      items.push({ text: "Quit", action: () => Apps.quit(e.id) })
    }
    return items
  }
}
