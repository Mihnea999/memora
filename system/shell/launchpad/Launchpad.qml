import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Apps: a glass library that rises out of the Dock. Search at the top, the apps
// you use most just below it, everything else sorted into calm groups on the
// left. Arrow keys move, Return opens, Escape closes. Drag an app onto the Dock
// to keep it there.
PanelWindow {
  id: lp
  required property var modelData
  screen: modelData
  readonly property bool open: Shell.open === "launchpad"
  // Shown on the screen you are working on.
  readonly property bool main: Hyprland.focusedMonitor ? modelData.name === Hyprland.focusedMonitor.name : modelData === Quickshell.screens[0]

  visible: (open || anim.running) && main
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "memora-launchpad"
  WlrLayershell.keyboardFocus: open && main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  color: "transparent"

  property real shown: open ? 1 : 0
  Behavior on shown { NumberAnimation { id: anim; duration: Prefs.motion(open ? 420 : 220); easing.type: open ? Easing.OutQuint : Easing.InCubic } }

  // ---- what is shown ---------------------------------------------------------
  readonly property var groups: [
    { id: "all", name: "All Apps", sym: "dock" },
    { id: "productivity", name: "Productivity", sym: "check", cats: ["Office", "TextEditor", "WordProcessor", "Spreadsheet", "Presentation", "Calendar", "ContactManagement", "ProjectManagement", "Finance"] },
    { id: "internet", name: "Internet", sym: "globe", cats: ["Network", "WebBrowser", "Email", "Chat", "InstantMessaging", "IRCClient", "FileTransfer", "P2P"] },
    { id: "creativity", name: "Creativity", sym: "palette", cats: ["Graphics", "2DGraphics", "3DGraphics", "VectorGraphics", "RasterGraphics", "Photography", "AudioVideoEditing", "Publishing"] },
    { id: "development", name: "Development", sym: "keyboard", cats: ["Development", "IDE", "Debugger", "RevisionControl", "WebDevelopment", "Building"] },
    { id: "media", name: "Media", sym: "play", cats: ["AudioVideo", "Audio", "Video", "Player", "Music", "Recorder", "TV"] },
    { id: "games", name: "Games", sym: "gamepad", cats: ["Game"] },
    { id: "utilities", name: "Utilities", sym: "gear", cats: ["Utility", "Accessories", "System", "Settings", "Monitor", "FileManager", "Archiving", "Calculator", "TerminalEmulator", "Security"] }
  ]
  function groupOf(e) {
    const c = e.categories || []
    for (let i = 1; i < groups.length; i++) if (c.some(x => groups[i].cats.indexOf(x) >= 0)) return groups[i].id
    return "utilities"
  }
  property string group: "all"
  property string query: ""
  readonly property var library: Apps.all.filter(e => e.id !== "memora-launchpad")
  readonly property var shownApps: {
    const q = query.toLowerCase().trim()
    if (q) {
      const score = e => {
        const n = Apps.displayName(e).toLowerCase() + " " + e.name.toLowerCase()
        if (n.startsWith(q)) return 0
        if (n.split(/\s+/).some(w => w.startsWith(q))) return 1
        if (n.indexOf(q) >= 0) return 2
        if ((e.genericName || "").toLowerCase().indexOf(q) >= 0 || (e.keywords || []).some(k => k.toLowerCase().startsWith(q))) return 3
        return 9
      }
      return library.map(e => ({ e: e, s: score(e) })).filter(x => x.s < 9).sort((a, b) => a.s - b.s || Apps.displayName(a.e).localeCompare(Apps.displayName(b.e))).map(x => x.e)
    }
    if (group === "all") return library
    return library.filter(e => groupOf(e) === group)
  }
  function countIn(g) { return g === "all" ? library.length : library.filter(e => groupOf(e) === g).length }

  // The apps you open most (kept in ~/.local/state/memora/launches.json).
  property var launches: ({})
  FileView {
    id: launchFile
    path: Quickshell.env("HOME") + "/.local/state/memora/launches.json"
    printErrors: false
    onLoaded: { try { lp.launches = JSON.parse(text()) } catch (e) {} }
  }
  readonly property var favourites: library.filter(e => (launches[e.id] || 0) > 0)
    .sort((a, b) => (launches[b.id] || 0) - (launches[a.id] || 0)).slice(0, 6)
  function open_(id) {
    const l = Object.assign({}, launches); l[id] = (l[id] || 0) + 1; launches = l
    launchFile.setText(JSON.stringify(l))
    Apps.launch(id); Shell.close()
  }

  // Keyboard selection in the grid.
  property int sel: 0
  readonly property int cols: Math.max(1, Math.floor(grid.width / 116))
  onShownAppsChanged: sel = 0
  // The selected app stays in view while the arrow keys move through the grid.
  onSelChanged: {
    const top = grid.y + Math.floor(sel / cols) * 122
    if (sel < cols) flick.contentY = 0
    else if (top < flick.contentY) flick.contentY = top
    else if (top + 122 > flick.contentY + flick.height) flick.contentY = Math.min(top + 122 - flick.height, Math.max(0, flick.contentHeight - flick.height))
  }
  onOpenChanged: if (open) { query = ""; search.text = ""; group = "all"; sel = 0; menuApp = ""; launchFile.reload(); search.forceActiveFocus() }

  property string dragApp: ""
  property point dragPos: Qt.point(0, 0)
  readonly property bool overDock: dragApp !== "" && dragPos.y > height - 110
  property bool pinnedFlash: false
  Timer { id: flashOff; interval: 900; onTriggered: lp.pinnedFlash = false }
  property string menuApp: ""
  // The app's menu; each action keeps the app it was made for (the menu closes first).
  function menuItems(id) {
    return [
      { text: "Open", action: () => lp.open_(id) },
      { separator: true },
      Apps.pinned.indexOf(id) >= 0
        ? { text: "Remove from Dock", action: () => Apps.unpin(id) }
        : { text: "Keep in Dock", action: () => Apps.pin(id) }
    ].concat(Apps.removable(id) ? [{ separator: true }, { text: "Uninstall…", action: () => Apps.uninstall(id) }] : [])
  }
  property point menuPos: Qt.point(0, 0)

  // A soft veil over the desktop; click it to close.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, Theme.dark ? 0.36 : 0.18)
    opacity: lp.shown
  }
  TapHandler {
    onTapped: ev => {
      if (lp.menuApp !== "") { lp.menuApp = ""; return }
      const p = panel.mapFromItem(lp.contentItem, ev.position.x, ev.position.y)
      if (p.x < 0 || p.y < 0 || p.x > panel.width || p.y > panel.height) Shell.close()
    }
  }

  // ---- the library ----------------------------------------------------------
  Glass {
    id: panel
    width: Math.min(lp.width - 80, 940)
    height: Math.min(lp.height - 170, 640)
    anchors.horizontalCenter: parent.horizontalCenter
    // Rises from just above the Dock.
    y: lp.height - height - Shell.bottomInset + (1 - lp.shown) * 60
    opacity: lp.shown
    scale: 0.94 + 0.06 * lp.shown
    transformOrigin: Item.Bottom
    radius: 28
    // Thicker glass than the menus: it opens over windows full of text, and
    // names and icons must read clearly over them (frosted or not).
    fill: Theme.dark ? Qt.rgba(0.10, 0.10, 0.12, Theme.see(0.74)) : Qt.rgba(0.98, 0.98, 0.99, Theme.see(0.78))
    TapHandler { onTapped: lp.menuApp = "" }   // taps inside don't close

    // Search
    Rectangle {
      id: searchBox
      anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
      height: 42; radius: 13
      color: Theme.field
      border.color: search.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : Theme.separator
      Sym { name: "search"; width: 16; height: 16; color: Theme.textDim; anchors { left: parent.left; leftMargin: 15; verticalCenter: parent.verticalCenter } }
      TextInput {
        id: search
        clip: true   // long text scrolls inside the field, never spills out
        anchors { left: parent.left; right: parent.right; leftMargin: 42; rightMargin: 14; verticalCenter: parent.verticalCenter }
        color: Theme.text
        font.family: Theme.font; font.pixelSize: Theme.large
        selectionColor: Theme.accent
        onTextChanged: lp.query = text
        Keys.onEscapePressed: text ? text = "" : Shell.close()
        Keys.onReturnPressed: if (lp.shownApps.length) lp.open_(lp.shownApps[Math.min(lp.sel, lp.shownApps.length - 1)].id)
        Keys.onRightPressed: lp.sel = Math.min(lp.shownApps.length - 1, lp.sel + 1)
        Keys.onLeftPressed: lp.sel = Math.max(0, lp.sel - 1)
        Keys.onDownPressed: lp.sel = Math.min(lp.shownApps.length - 1, lp.sel + lp.cols)
        Keys.onUpPressed: lp.sel = Math.max(0, lp.sel - lp.cols)
        Keys.onTabPressed: { const i = lp.groups.findIndex(g => g.id === lp.group); lp.group = lp.groups[(i + 1) % lp.groups.length].id }
        Txt { visible: !search.text; text: "Search apps"; color: Theme.textFaint; font.pixelSize: Theme.large; anchors.verticalCenter: parent.verticalCenter }
      }
    }

    // Groups
    Column {
      id: side
      anchors { top: searchBox.bottom; topMargin: 16; left: parent.left; leftMargin: 12 }
      width: 190
      spacing: 2
      opacity: lp.query ? 0.35 : 1
      Behavior on opacity { NumberAnimation { duration: Theme.fast } }
      Repeater {
        model: lp.groups
        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property bool here: lp.group === modelData.id && !lp.query
          readonly property int n: lp.countIn(modelData.id)
          visible: n > 0
          width: side.width; height: visible ? 34 : 0; radius: 9
          color: here ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.32 : 0.16) : (gh.hovered ? Theme.hover : "transparent")
          Behavior on color { ColorAnimation { duration: Theme.fast } }
          Sym { x: 12; anchors.verticalCenter: parent.verticalCenter; name: modelData.sym; width: 14; height: 14; color: parent.here ? Theme.accent : Theme.textDim }
          Txt { x: 36; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; font.weight: parent.here ? Font.Bold : Font.Normal }
          Txt { anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: parent.n; color: Theme.textFaint; font.pixelSize: Theme.small }
          HoverHandler { id: gh }
          TapHandler { onTapped: { search.text = ""; lp.group = modelData.id; search.forceActiveFocus() } }
        }
      }
    }
    Rectangle { anchors { top: searchBox.bottom; topMargin: 16; bottom: parent.bottom; bottomMargin: 18; left: side.right; leftMargin: 10 } width: 1; color: Theme.separator }

    // Most used, then the grid.
    Flickable {
      id: flick
      anchors { top: searchBox.bottom; topMargin: 12; bottom: parent.bottom; bottomMargin: 10; left: side.right; leftMargin: 22; right: parent.right; rightMargin: 14 }
      clip: true
      contentHeight: body.implicitHeight + 10
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: body
        width: flick.width
        spacing: 6
        Txt {
          visible: favRow.visible
          text: "Most Used"; color: Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Bold
          topPadding: 4
        }
        Row {
          id: favRow
          visible: !lp.query && lp.group === "all" && lp.favourites.length > 0
          spacing: 0
          Repeater { model: favRow.visible ? lp.favourites : []; delegate: Tile { required property var modelData; required property int index; entry: modelData; order: index; selected: false } }
        }
        Rectangle { visible: favRow.visible; width: body.width; height: 1; color: Theme.separator }
        Txt {
          text: lp.query ? (lp.shownApps.length ? "Results" : "No apps match “" + lp.query + "”") : lp.groups.find(g => g.id === lp.group).name
          color: Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Bold
          topPadding: 6
        }
        Grid {
          id: grid
          width: body.width
          columns: lp.cols
          Repeater {
            model: lp.shownApps
            delegate: Tile { required property var modelData; required property int index; entry: modelData; order: index + 6; selected: index === lp.sel && (lp.query !== "" || keyNav.used) }
          }
        }
      }
    }
    // Arrow keys show the selection only once they are used.
    QtObject { id: keyNav; property bool used: false }
    Connections { target: lp; function onSelChanged() { if (lp.sel > 0) keyNav.used = true } function onOpenChanged() { keyNav.used = false } }
  }

  // ---- one app ---------------------------------------------------------------
  component Tile: Item {
    id: t
    property var entry
    property int order: 0
    property bool selected: false
    width: Math.floor(grid.width / lp.cols); height: 122
    // Icons drift up into place one after another as the library opens.
    property real enter: lp.open ? 1 : 0
    Behavior on enter { SequentialAnimation {
      PauseAnimation { duration: lp.open ? Prefs.motion(Math.min(t.order, 30) * 12) : 0 }
      NumberAnimation { duration: Prefs.motion(lp.open ? 380 : 120); easing.type: lp.open ? Easing.OutCubic : Easing.InCubic }
    } }
    opacity: (lp.dragApp === entry.id ? 0.35 : 1) * enter
    transform: Translate { y: (1 - t.enter) * 14 }
    Rectangle {
      anchors { fill: parent; margins: 4 }
      radius: 14
      color: t.selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : (th.hovered ? Theme.hover : "transparent")
      Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    AppIcon {
      id: ic
      appId: t.entry.id
      width: 60; height: 60
      anchors.horizontalCenter: parent.horizontalCenter
      y: 12
      scale: tp.pressed ? 0.9 : (th.hovered ? 1.06 : 1)
      Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
    }
    Txt {
      anchors { top: ic.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
      width: parent.width - 10
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      lineHeight: 0.95
      text: Apps.displayName(t.entry)
      font.pixelSize: Theme.small + 0.5
    }
    HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tp; onTapped: lp.open_(t.entry.id) }
    TapHandler {
      acceptedButtons: Qt.RightButton
      onTapped: ev => { lp.menuApp = t.entry.id; lp.menuPos = t.mapToItem(lp.contentItem, ev.position.x, ev.position.y) }
    }
    DragHandler {
      target: null
      onActiveChanged: {
        if (active) { lp.dragApp = t.entry.id; return }
        if (lp.overDock) { Apps.pin(t.entry.id); lp.pinnedFlash = true; flashOff.restart() }
        lp.dragApp = ""
      }
      onCentroidChanged: if (active) lp.dragPos = t.mapToItem(lp.contentItem, centroid.position.x, centroid.position.y)
    }
  }

  // ---- dragging to the Dock, and the menu ------------------------------------
  Glass {
    visible: opacity > 0
    opacity: lp.dragApp !== "" || lp.pinnedFlash ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
    width: 460; height: 80
    radius: 24
    fill: lp.overDock || lp.pinnedFlash ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.glassStrong
    Behavior on fill { ColorAnimation { duration: Theme.fast } }
    Txt { anchors.centerIn: parent; text: lp.pinnedFlash ? "Added to the Dock" : (lp.overDock ? "Release to keep in the Dock" : "Drag here to keep in the Dock"); font.weight: Font.Medium }
  }
  AppIcon {
    visible: lp.dragApp !== ""
    appId: lp.dragApp
    width: 72; height: 72
    x: lp.dragPos.x - 36; y: lp.dragPos.y - 36
    scale: lp.overDock ? 0.8 : 1.05
    Behavior on scale { NumberAnimation { duration: Theme.fast } }
  }
  MenuPanel {
    visible: lp.menuApp !== ""
    x: Math.min(lp.menuPos.x, lp.width - width - 10); y: Math.min(lp.menuPos.y, lp.height - height - 10)
    width: implicitWidth; height: implicitHeight
    items: lp.menuApp === "" ? [] : lp.menuItems(lp.menuApp)
    onPicked: item => { const run = item.action; Qt.callLater(() => { run(); lp.menuApp = "" }) }
  }
}
