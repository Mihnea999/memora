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

  readonly property real base: Prefs.dockSize
  readonly property real peak: Prefs.magnify ? Math.max(Prefs.magnifySize, base) : base
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
  readonly property bool concealable: Prefs.dockAutohide || fullscreen || semi
  property bool revealed: false
  // Kept out while in use: under the pointer, its menu open, an icon dragged, Launchpad open.
  readonly property bool inUse: dockHover.hovered || menuFor !== null || draggingId !== "" || Shell.open === "launchpad"
  readonly property bool hidden: concealable && !revealed && !inUse
  onInUseChanged: if (!inUse && revealed) leave.restart()
  onConcealableChanged: revealed = false
  Timer { id: arrive; interval: Prefs.dockAutohide && !dock.fullscreen ? 60 : 180; onTriggered: { dock.revealed = true; leave.restart() } }
  Timer { id: leave; interval: 450; onTriggered: if (!dock.inUse && !edgeHover.hovered) dock.revealed = false; else if (!dock.inUse) restart() }

  anchors { bottom: true; left: true; right: true }
  implicitHeight: 170
  exclusiveZone: concealable ? 0 : base + 22 + gap
  color: "transparent"
  WlrLayershell.namespace: "memora-dock"
  // Over full-screen apps it must be above them to show at all.
  WlrLayershell.layer: fullscreen ? WlrLayer.Overlay : WlrLayer.Top
  mask: Region { item: dock.hidden ? edge : hit }

  // The bottom edge of the screen: where the pointer calls a hidden Dock.
  Item {
    id: edge
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    height: 2
    HoverHandler { id: edgeHover; onHoveredChanged: if (hovered && dock.hidden) arrive.restart(); else if (!hovered) arrive.stop() }
  }

  property real mouseX: -1000
  property string draggingId: ""

  // An icon was let go: remove it if pulled out, else move it to where it landed.
  function dropped(item, d) {
    const id = item.appId
    const pinned = Apps.pinned.slice()
    const from = pinned.indexOf(id)
    if (d.y < -item.height * 1.3) { if (from >= 0) { Apps.unpin(id); poof.at(item) } return }
    const x = item.centerX + d.x
    // Slot under the drop point, among the pinned apps.
    let to = 0
    for (let i = 0; i < items.count && i < pinned.length; i++) {
      const slot = row.itemAtIndex(i)
      if (slot && x > slot.x + dock.rowX + slot.width / 2) to = i + 1
    }
    if (from < 0) { pinned.splice(Math.min(to, pinned.length), 0, id); Apps.savePinned(pinned); return }
    pinned.splice(from, 1)
    if (to > from) to--
    pinned.splice(Math.min(to, pinned.length), 0, id)
    Apps.savePinned(pinned)
  }
  readonly property real rowX: row.x - row.contentX
  readonly property real hitX: hit.x
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
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: dock.hidden ? -(dock.base + 40) : dock.gap
    width: row.width + 22
    height: dock.base + 18
    Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.slow; easing.type: Theme.easing } }

    Glass {
      id: plate
      anchors.fill: parent
      radius: 26
      fill: Theme.glass
      shadowSize: 30
    }

    HoverHandler {
      id: dockHover
      onPointChanged: dock.mouseX = point.position.x
      onHoveredChanged: if (!hovered) dock.mouseX = -1000
    }

    // A ListView over a ListModel kept in step with `model`, so icons that
    // arrive grow in, icons that leave shrink away, and the rest slide aside.
    ListView {
      id: row
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 8
      anchors.horizontalCenter: parent.horizontalCenter
      orientation: ListView.Horizontal
      interactive: false
      spacing: 7
      width: contentWidth
      height: dock.base
      model: items
      // Each slot is as tall as the Dock; its icon sits on the bottom and grows upwards.
      delegate: Item {
        id: slot
        required property string key
        required property string kind
        readonly property var entry: dock.entries[key] || null
        width: icon.item ? icon.item.width : 0
        height: dock.base
        Loader {
          id: icon
          anchors.bottom: parent.bottom
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
      displaced: Transition { NumberAnimation { properties: "x"; duration: Theme.slow; easing.type: Theme.easingEmph } }
      addDisplaced: Transition { NumberAnimation { properties: "x"; duration: Theme.slow; easing.type: Theme.easingEmph } }
      removeDisplaced: Transition { NumberAnimation { properties: "x"; duration: Theme.slow; easing.type: Theme.easingEmph } }
    }
  }

  // A small puff where a removed icon was.
  Item {
    id: poof
    width: 60; height: 60
    opacity: 0
    function at(item) {
      const p = item.mapToItem(dock.contentItem, item.width / 2, item.height / 2 + item.drag.y)
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
    const p = hit.mapToItem(null, hit.width - 150, hit.height / 2)
    // The Dock's window sits at the bottom of the screen; p is inside it.
    Apps.dockTarget = Qt.point(dock.modelData.x + p.x, dock.modelData.y + dock.modelData.height - dock.height + p.y)
  }
  Connections { target: hit; function onWidthChanged() { dock.updateTarget() } function onXChanged() { dock.updateTarget() } }

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
      width: 13; height: dock.base
      Rectangle { anchors.centerIn: parent; width: 1; height: dock.base * 0.72; color: Theme.separator }
      // Right-click the divider: the Dock's own options, like on a Mac.
      HoverHandler { cursorShape: Qt.SizeVerCursor }
      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: { const p = sepItem.mapToItem(hit, sepItem.width / 2, 0); dock.menuX = dock.hitX + p.x; dock.menuFor = { kind: "sep", id: "sep" } }
      }
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
    anchor.rect.x: Math.max(8, dock.menuX - ctxPanel.implicitWidth / 2)
    anchor.rect.y: dock.height - dock.base - 30 - ctxPanel.implicitHeight
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
      { text: Prefs.dockAutohide ? "Turn Hiding Off" : "Turn Hiding On", action: () => Prefs.set("dockAutohide", !Prefs.dockAutohide) },
      { text: Prefs.magnify ? "Turn Magnification Off" : "Turn Magnification On", action: () => Prefs.set("magnify", !Prefs.magnify) },
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
      items.push({ text: "Show All Windows", action: () => ws.forEach(w => Apps.isMinimized(w) ? Apps.restore(w) : null) })
      items.push({ separator: true })
      items.push({ text: "Quit", action: () => Apps.quit(e.id) })
    }
    return items
  }
}
