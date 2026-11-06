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
  readonly property real reach: 150      // how far magnification spreads, in px
  readonly property real gap: 6
  readonly property bool hidden: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen

  anchors { bottom: true; left: true; right: true }
  implicitHeight: 170
  exclusiveZone: hidden ? 0 : base + 22 + gap
  color: "transparent"
  WlrLayershell.namespace: "memora-dock"
  WlrLayershell.layer: WlrLayer.Top
  mask: Region { item: hit }

  property real mouseX: -1000
  readonly property real rowX: row.x
  readonly property real hitX: hit.x
  readonly property bool magnifying: mouseX > -999

  // Everything shown, in order.
  readonly property var running: {
    const seen = {}
    const out = []
    Apps.windows.forEach(w => {
      const c = Apps.classOf(w)
      if (!c || seen[c] || Apps.isMinimized(w)) return
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
    width: row.width + 16
    height: dock.base + 16
    Behavior on anchors.bottomMargin { NumberAnimation { duration: Theme.slow; easing.type: Theme.easing } }

    Glass {
      id: plate
      anchors.fill: parent
      radius: 22
      fill: Theme.glass
      shadowSize: 30
    }

    HoverHandler {
      id: dockHover
      onPointChanged: dock.mouseX = point.position.x
      onHoveredChanged: if (!hovered) dock.mouseX = -1000
    }

    Row {
      id: row
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 8
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 4

      Repeater {
        model: dock.model
        delegate: Loader {
          required property var modelData
          required property int index
          sourceComponent: modelData.kind === "sep" ? sepComp : itemComp
          anchors.bottom: parent ? parent.bottom : undefined
          property var entry: modelData
        }
      }
    }
  }

  Component {
    id: sepComp
    Item {
      width: 13; height: dock.base
      Rectangle { anchors.centerIn: parent; width: 1; height: dock.base * 0.72; color: Theme.separator }
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
      onPicked: item => { dock.menuFor = null; if (item.action) item.action() }
    }
  }
  HyprlandFocusGrab {
    active: ctx.visible
    windows: [ctx, dock]
    onCleared: dock.menuFor = null
  }

  function menuItems(e) {
    if (e.kind === "trash") return [
      { text: "Open", action: () => Apps.run("nautilus --new-window trash:///") },
      { separator: true },
      { text: "Empty Trash", enabled: dock.trashFull, action: () => Apps.run("gio trash --empty") }
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
    }
    if (ws.length) {
      items.push({ text: "Show All Windows", action: () => ws.forEach(w => Apps.isMinimized(w) ? Apps.restore(w) : null) })
      items.push({ separator: true })
      items.push({ text: "Quit", action: () => Apps.quit(e.id) })
    }
    return items
  }
}
