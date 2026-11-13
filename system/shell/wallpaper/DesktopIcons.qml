import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.ui

// What is in ~/Desktop, on the desktop picture as on a Mac: icons on a grid
// from the top right, where you put them (~/.config/memora/desktop.json).
// Click to select (Ctrl adds one, Shift a run, a drag on empty space a band),
// double-click to open, drag to move them, onto a folder to put them in it, or
// over a window to drop them into the app. Folders show their own colour and
// symbol (core/Folders.qml); right-click > Colour & Symbol… picks them.
Item {
  id: d
  anchors.fill: parent
  // Set by the wallpaper: the screen, the widgets (icons keep out of their way)
  // and the frosted picture for the glass.
  property var screen: null
  property Item widgets: null
  property Item backdrop: null

  readonly property string dir: Folders.home + "/Desktop"
  readonly property real cellW: 100
  readonly property real cellH: 108
  readonly property real icon: 64
  readonly property real padTop: 40          // under the menu bar
  readonly property real padRight: 12
  readonly property real padBottom: 96       // above the Dock
  readonly property int cols: Math.max(1, Math.floor((width - padRight - 12) / cellW))
  readonly property int rows: Math.max(1, Math.floor((height - padTop - padBottom) / cellH))
  function cellX(c) { return width - padRight - (c + 1) * cellW }
  function cellY(r) { return padTop + r * cellH }

  // name -> [c, r]: c counts columns from the right.
  property var places: ({})
  property var selected: ({})             // name -> true
  property string renaming: ""
  property string styling: ""             // the folder whose colour & symbol is being picked
  readonly property var selection: Object.keys(selected)
  readonly property bool typing: renaming !== "" || styling !== ""

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", dir])

  FolderListModel {
    id: desk
    folder: "file://" + d.dir
    showDirsFirst: false
    showHidden: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
    sortCaseSensitive: false
    onCountChanged: settle.restart()
    onStatusChanged: settle.restart()
  }
  // The entries, as { name, path, dir } (rows from another folder count as none).
  property var items: []
  Timer {
    id: settle
    interval: 60
    onTriggered: {
      const l = []
      for (let i = 0; i < desk.count; i++) {
        const p = desk.get(i, "filePath") || ""
        if (p.substring(0, p.lastIndexOf("/")) !== d.dir) continue
        l.push({ name: desk.get(i, "fileName"), path: p, dir: !!desk.get(i, "fileIsDir") })
      }
      d.items = l
      d.arrange()
    }
  }
  Connections { target: desk; function onDataChanged() { settle.restart() } function onRowsInserted() { settle.restart() } function onRowsRemoved() { settle.restart() } function onModelReset() { settle.restart() } }
  Connections {
    target: d.widgets
    function onLayoutChanged() { d.evacuateBlocked() }
    function onPreviewChanged() { if (d.widgets && d.widgets.preview) d.evacuateBlocked() }
  }
  onWidgetsChanged: if (widgets) d.evacuateBlocked()
  onColsChanged: settle.restart()
  onRowsChanged: settle.restart()

  // ---- places ------------------------------------------------------------------
  FileView {
    id: store
    path: Folders.home + "/.config/memora/desktop.json"
    printErrors: false
    onLoaded: { try { const j = JSON.parse(text()); d.places = j.places || {} } catch (e) {} settle.restart() }
    onLoadFailed: settle.restart()
  }
  function save(p) { places = p; store.setText(JSON.stringify({ places: p }, null, 1) + "\n") }

  // Cells the widgets cover (or hover over while dragging in preview).
  function blocked(c, r) {
    if (!widgets || !widgets.layout) return false
    const x = cellX(c) + 4, y = cellY(r) + 4, w = cellW - 8, h = cellH - 8
    const l = (widgets.editing && widgets.preview) ? widgets.preview : widgets.layout
    return l.some(o => {
      const ww = widgets.spanOf(o) * widgets.unit + (widgets.spanOf(o) - 1) * widgets.gap
      const wh = widgets.rowSpanOf(o) * widgets.unit + (widgets.rowSpanOf(o) - 1) * widgets.gap
      return x < o.x + ww && x + w > o.x && y < o.y + wh && y + h > o.y
    })
  }
  function key(c, r) { return c + ":" + r }
  function taken(p, skip) {
    const t = {}
    Object.keys(p).forEach(n => { if (!skip || !skip[n]) t[key(p[n][0], p[n][1])] = n })
    return t
  }
  // The free cell nearest to (c, r).
  function nearestFree(c, r, used) {
    let best = null, bd = 1e9
    for (let cc = 0; cc < cols; cc++) for (let rr = 0; rr < rows; rr++) {
      if (used[key(cc, rr)] || blocked(cc, rr)) continue
      const dd = (cc - c) * (cc - c) * 1.2 + (rr - r) * (rr - r)
      if (dd < bd) { bd = dd; best = [cc, rr] }
    }
    return best
  }
  // The first free cell, down each column from the right, as a Mac fills it.
  function firstFree(used) {
    for (let c = 0; c < cols; c++) for (let r = 0; r < rows; r++) if (!used[key(c, r)] && !blocked(c, r)) return [c, r]
    return [0, 0]
  }
  // Each entry gets a cell: its own if it has one on this screen and is unblocked, else the next free one.
  function arrange() {
    const names = {}
    items.forEach(i => names[i.name] = true)
    const p = {}
    let changed = false
    Object.keys(places).forEach(n => {
      const v = places[n]
      if (names[n] && v[0] < cols && v[1] < rows && !blocked(v[0], v[1])) p[n] = v
      else if (names[n] || desk.status === FolderListModel.Ready) changed = true
    })
    const used = taken(p)
    items.forEach(i => {
      if (!p[i.name]) {
        const spot = nearestFree(0, 0, used) || firstFree(used)
        p[i.name] = spot
        used[key(spot[0], spot[1])] = i.name
        changed = true
      }
    })
    if (changed) save(p)
    else places = p
  }
  // Ensure icons that are covered by widgets move out of the way to nearest free cells (macOS approach)
  function evacuateBlocked() {
    if (!widgets || !widgets.layout || !items.length) return
    const p = Object.assign({}, places)
    let changed = false
    const used = {}
    // First preserve all unblocked icon positions
    items.forEach(i => {
      const v = p[i.name]
      if (v && v[0] < cols && v[1] < rows && !blocked(v[0], v[1])) used[key(v[0], v[1])] = i.name
    })
    // Push any blocked or out-of-bounds icon to the nearest free cell
    items.forEach(i => {
      const v = p[i.name]
      if (!v || v[0] >= cols || v[1] >= rows || blocked(v[0], v[1])) {
        const startC = v ? v[0] : 0
        const startR = v ? v[1] : 0
        const f = nearestFree(startC, startR, used) || firstFree(used)
        if (f) {
          p[i.name] = f
          used[key(f[0], f[1])] = i.name
          changed = true
        }
      }
    })
    if (changed) save(p)
  }
  // Clean Up: by name, down the columns from the right.
  function cleanUp() {
    const p = {}, used = {}
    items.forEach(i => { p[i.name] = firstFree(used); used[key(p[i.name][0], p[i.name][1])] = i.name })
    save(p)
  }
  function itemAt(x, y) {
    for (let i = 0; i < items.length; i++) {
      const v = places[items[i].name]
      if (!v) continue
      const ix = cellX(v[0]), iy = cellY(v[1])
      // The picture and the name under it, not the whole cell.
      if (x >= ix + (cellW - icon) / 2 - 4 && x <= ix + (cellW + icon) / 2 + 4 && y >= iy + 2 && y <= iy + icon + 10) return items[i]
      if (x >= ix + 4 && x <= ix + cellW - 4 && y > iy + icon + 10 && y <= iy + cellH - 6) return items[i]
    }
    return null
  }
  function byName(n) { return items.find(i => i.name === n) || null }

  // ---- what you do with them -----------------------------------------------------
  function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  function sh(cmd, then) { const p = runner.createObject(d, { cmd: cmd }); if (then) p.done.connect(then) }
  Component { id: runner; Process {
    property string cmd
    signal done()
    command: ["bash", "-c", cmd]
    running: true
    onExited: { done(); destroy() }
  } }
  property string lastClicked: ""
  function select(name, mods) {
    const toggle = !!(mods & (Qt.ControlModifier | Qt.MetaModifier))
    const range = !!(mods & Qt.ShiftModifier)
    if (range && lastClicked && places[lastClicked] && places[name]) {
      // Everything in the rectangle between the two, as on a Mac.
      const a = places[lastClicked], b = places[name], s = Object.assign({}, selected)
      const cMin = Math.min(a[0], b[0]), cMax = Math.max(a[0], b[0])
      const rMin = Math.min(a[1], b[1]), rMax = Math.max(a[1], b[1])
      items.forEach(i => {
        const v = places[i.name]
        if (v && v[0] >= cMin && v[0] <= cMax && v[1] >= rMin && v[1] <= rMax) s[i.name] = true
      })
      selected = s
      return
    }
    const s = toggle ? Object.assign({}, selected) : {}
    if (toggle && s[name]) delete s[name]; else s[name] = true
    selected = s
    lastClicked = name
  }
  function clear() { selected = ({}); lastClicked = "" }
  function selectAll() { const s = {}; items.forEach(i => s[i.name] = true); selected = s }
  function open(it) {
    if (!it) return
    if (it.dir) Quickshell.execDetached(["memora-files", it.path])
    else Quickshell.execDetached(["gio", "open", it.path])
  }
  function openSelection(targets) {
    const list = (targets && targets.length) ? targets : selection
    list.forEach(n => open(byName(n)))
  }
  function trash(targets) {
    const list = (targets && targets.length) ? targets : selection
    const l = list.map(n => dir + "/" + n)
    if (!l.length) return
    const cmd = "mkdir -p \"$HOME/.local/share/Trash/files\" \"$HOME/.local/share/Trash/info\" 2>/dev/null; " +
      "gio trash -- " + l.map(q).join(" ") + " 2>/dev/null || " +
      "mv -f -- " + l.map(q).join(" ") + " \"$HOME/.local/share/Trash/files/\" 2>/dev/null || " +
      "rm -rf -- " + l.map(q).join(" ") + "; " +
      "setsid -f memora-sound trash >/dev/null 2>&1 || true"
    sh(cmd)
    clear()
  }
  function newFolder(at) {
    const names = {}; items.forEach(i => names[i.name] = true)
    let n = "untitled folder", i = 2
    while (names[n]) n = "untitled folder " + i++
    const p = Object.assign({}, places)
    const spot = at ? nearestFree(at[0], at[1], taken(places)) || firstFree(taken(places)) : firstFree(taken(places))
    p[n] = spot
    save(p)
    // Add immediately to items so delegate is instantiated right now without waiting for inotify settle
    const newItem = { name: n, path: dir + "/" + n, dir: true }
    items = items.concat([newItem])
    selected = ({ [n]: true })
    lastClicked = n
    renaming = n
    sh("mkdir -p -- " + q(dir + "/" + n))
  }
  function rename(from, to) {
    renaming = ""
    to = String(to).trim()
    if (!to || to === from || to.indexOf("/") >= 0 || to === "." || to === "..") return
    if (byName(to)) return
    const p = Object.assign({}, places)
    p[to] = p[from]; delete p[from]
    save(p)
    sh("mv -n -- " + q(dir + "/" + from) + " " + q(dir + "/" + to), () => { Folders.moved(dir + "/" + from, dir + "/" + to); selected = ({ [to]: true }) })
  }
  // Selected entries into a folder on the desktop.
  function moveInto(target, names) {
    const l = names.filter(n => n !== target.name)
    if (!l.length) return
    sh("mv -n -- " + l.map(n => q(dir + "/" + n)).join(" ") + " " + q(target.path + "/"),
      () => l.forEach(n => Folders.moved(dir + "/" + n, target.path + "/" + n)))
    clear()
  }
  // Files dropped from elsewhere (Files, an app): moved onto the desktop where they fell.
  function takeIn(paths, x, y) {
    const target = itemAt(x, y)
    if (target && target.dir) {
      const l = paths.filter(p => p !== target.path)
      if (l.length) sh("mv -n -- " + l.map(q).join(" ") + " " + q(target.path + "/"), () => l.forEach(p => Folders.moved(p, target.path + "/" + p.split("/").pop())))
      return
    }
    const outside = paths.filter(p => p.substring(0, p.lastIndexOf("/")) !== dir)
    if (!outside.length) return
    const c = Math.max(0, Math.min(cols - 1, Math.floor((width - padRight - x) / cellW))), r = Math.max(0, Math.min(rows - 1, Math.floor((y - padTop) / cellH)))
    const p = Object.assign({}, places), used = taken(places)
    outside.forEach(f => { const n = f.split("/").pop(); const v = nearestFree(c, r, used) || firstFree(used); p[n] = v; used[key(v[0], v[1])] = n })
    save(p)
    sh("mv -n -- " + outside.map(q).join(" ") + " " + q(dir + "/"), () => outside.forEach(f => Folders.moved(f, dir + "/" + f.split("/").pop())))
  }

  // ---- the right-click menu (the wallpaper shows it) ---------------------------
  // Items for a right-click at (x, y): an icon's own, or the desktop's (empty: none).
  function menuAt(x, y) {
    const it = itemAt(x, y)
    if (!it) { if (selection.length) clear(); return null }
    if (!selected[it.name]) { selected = ({ [it.name]: true }); lastClicked = it.name }
    const targets = selection.indexOf(it.name) >= 0 ? selection.slice() : [it.name]
    const one = targets.length === 1
    return [
      { text: "Open", action: () => openSelection(targets) },
      { separator: true },
      { text: "Rename", enabled: one, action: () => renaming = it.name },
      it.dir && one ? { text: "Colour & Symbol…", action: () => styling = it.name } : null,
      { text: "Show in Files", action: () => Quickshell.execDetached(["memora-files", dir]) },
      { text: "Share…", enabled: !targets.some(n => (byName(n) || {}).dir), action: () => Quickshell.execDetached(["memora-shell", "share"].concat(targets.map(n => dir + "/" + n))) },
      { separator: true },
      { text: "Move to Trash", action: () => trash(targets) }
    ].filter(i => i)
  }
  function deskItems(x, y) {
    const c = Math.max(0, Math.min(cols - 1, Math.floor((width - padRight - x) / cellW))), r = Math.max(0, Math.min(rows - 1, Math.floor((y - padTop) / cellH)))
    return [
      { text: "New Folder", action: () => newFolder([c, r]) },
      { text: "Clean Up", enabled: items.length > 0, action: () => cleanUp() },
      { separator: true }
    ]
  }

  // Whether a point is inside any widget's bounds
  function overWidget(x, y) {
    if (!widgets || !widgets.layout) return false
    return widgets.layout.some(o => {
      const ww = widgets.spanOf(o) * widgets.unit + (widgets.spanOf(o) - 1) * widgets.gap
      const wh = widgets.rowSpanOf(o) * widgets.unit + (widgets.rowSpanOf(o) - 1) * widgets.gap
      return x >= o.x && x <= o.x + ww && y >= o.y && y <= o.y + wh
    })
  }

  // ---- pointer -------------------------------------------------------------------
  // Clicks (the wallpaper's handlers pass them on).
  property bool justBanded: false
  Timer { id: bandTimer; interval: 120; onTriggered: d.justBanded = false }

  function tapped(x, y, mods, count) {
    if (justBanded) { justBanded = false; return }
    if (overWidget(x, y)) return
    if (renaming) { commitRename(); return }
    const it = itemAt(x, y)
    if (!it) { clear(); return }
    if (count >= 2) { open(it); return }
    if (!(mods & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier)) && selected[it.name] && selection.length > 1) {
      selected = ({ [it.name]: true })
      lastClicked = it.name
      return
    }
    select(it.name, mods)
  }
  // Dragging: icons (mode "move") or a selection band (mode "band").
  property string mode: ""
  property point from: Qt.point(0, 0)
  property point at: Qt.point(0, 0)
  property string lead: ""                // the icon the pointer holds
  property var moving: []
  property var bandBase: ({})
  readonly property real dx: mode === "move" ? at.x - from.x : 0
  readonly property real dy: mode === "move" ? at.y - from.y : 0
  readonly property var dropTarget: mode === "move" ? (() => { const t = itemAt(at.x, at.y); return t && t.dir && !selected[t.name] ? t : null })() : null

  DragHandler {
    id: dragger
    target: null
    enabled: !(d.widgets && d.widgets.editing) && !d.typing
    dragThreshold: 5
    onActiveChanged: {
      if (active) {
        const p = centroid.pressPosition
        if (d.overWidget(p.x, p.y)) return
        d.from = p; d.at = p
        const it = d.itemAt(p.x, p.y)
        if (it) {
          if (!d.selected[it.name]) {
            if (!(dragger.keyboardModifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier))) {
              d.selected = ({ [it.name]: true })
            } else {
              const s = Object.assign({}, d.selected)
              s[it.name] = true
              d.selected = s
            }
            d.lastClicked = it.name
          }
          d.lead = it.name; d.moving = d.selection.slice(); d.mode = "move"
        } else {
          d.bandBase = (dragger.keyboardModifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier)) ? Object.assign({}, d.selected) : {}
          d.mode = "band"
        }
      } else if (d.mode !== "") {
        if (d.mode === "move" && !outDrag.Drag.active) d.drop()
        if (d.mode === "band") {
          d.justBanded = true
          bandTimer.restart()
        }
        if (!outDrag.Drag.active) d.mode = ""
      }
    }
    onCentroidChanged: if (active) {
      d.at = centroid.position
      if (d.mode === "band") d.band()
      else if (d.mode === "move" && d.overWindow(d.at)) outDrag.start()
    }
  }
  function band() {
    const x1 = Math.min(from.x, at.x), x2 = Math.max(from.x, at.x), y1 = Math.min(from.y, at.y), y2 = Math.max(from.y, at.y)
    const s = Object.assign({}, bandBase)
    items.forEach(i => {
      const v = places[i.name]; if (!v) return
      const ix = cellX(v[0]), iy = cellY(v[1])
      if (ix < x2 && ix + cellW > x1 && iy < y2 && iy + cellH > y1) s[i.name] = true
    })
    selected = s
  }
  function drop() {
    const target = dropTarget
    if (target) { moveInto(target, moving); return }
    const v = places[lead]
    if (!v) return
    // The lead icon goes to the cell under it; the others keep their places around it.
    const lc = Math.round((width - padRight - cellW - (cellX(v[0]) + dx)) / cellW), lr = Math.round((cellY(v[1]) + dy - padTop) / cellH)
    const dc = lc - v[0], dr = lr - v[1]
    if (!dc && !dr) return
    const skip = {}; moving.forEach(n => skip[n] = true)
    const p = Object.assign({}, places), used = taken(places, skip)
    const order = moving.slice().sort((a, b) => a === lead ? -1 : b === lead ? 1 : 0)
    order.forEach(n => {
      const o = places[n]; if (!o) return
      let c = Math.max(0, Math.min(cols - 1, o[0] + dc)), r = Math.max(0, Math.min(rows - 1, o[1] + dr))
      if (used[key(c, r)] || blocked(c, r)) { const f = nearestFree(c, r, used); if (f) { c = f[0]; r = f[1] } }
      p[n] = [c, r]; used[key(c, r)] = n
    })
    save(p)
  }
  // Over a window of this screen's desktop: the icons leave as files for the app.
  function overWindow(pt) {
    const mon = d.screen ? Hyprland.monitorFor(d.screen) : null
    if (!mon) return false
    const ws = mon.activeWorkspace
    return Apps.windows.some(w => {
      if (!w.workspace || w.workspace !== ws || Apps.isMinimized(w)) return false
      const r = Apps.rectOf(w)
      const x = pt.x + mon.x, y = pt.y + mon.y
      return r.width > 0 && x >= r.x && x <= r.x + r.width && y >= r.y && y <= r.y + r.height
    })
  }
  Item {
    id: outDrag
    visible: false
    width: d.icon; height: d.icon
    x: d.at.x - width / 2; y: d.at.y - height / 2
    property var paths: []
    function start() {
      if (Drag.active) return
      paths = d.moving.map(n => d.dir + "/" + n)
      if (!paths.length) return
      const it = d.byName(d.lead)
      dragPic.source = it ? (Folders.kindOf(it.name, it.dir) === "image" ? "file://" + it.path : Folders.iconFor(it.path, it.name, it.dir)) : ""
      dragPic.grabToImage(r => { outDrag.Drag.imageSource = r.url; outDrag.Drag.active = true }, Qt.size(d.icon, d.icon))
    }
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.mimeData: ({ "text/uri-list": paths.map(p => "file://" + encodeURI(p)).join("\r\n") + "\r\n" })
    Drag.hotSpot: Qt.point(d.icon / 2, d.icon / 2)
    Drag.onDragFinished: { Drag.active = false; d.mode = ""; d.moving = [] }
  }
  Image { id: dragPic; x: -1000; width: d.icon; height: d.icon; sourceSize: Qt.size(d.icon * 2, d.icon * 2); fillMode: Image.PreserveAspectFit }

  // Files dragged in from Files or an app.
  DropArea {
    anchors.fill: parent
    keys: ["text/uri-list"]
    onDropped: ev => {
      if (!ev.hasUrls) return
      const paths = ev.urls.map(u => String(u)).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.substring(7)))
      if (!paths.length) return
      ev.accept(Qt.CopyAction)
      d.takeIn(paths, ev.x, ev.y)
    }
  }

  // ---- keys (while the desktop has them) ---------------------------------------
  Item {
    id: keys
    focus: d.selection.length > 0 && !d.typing
    Keys.onPressed: ev => {
      const ctrl = ev.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
      if (ev.key === Qt.Key_Delete || (ctrl && ev.key === Qt.Key_Backspace)) { d.trash(); ev.accepted = true }
      else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_F2) { if (d.selection.length === 1) d.renaming = d.selection[0]; ev.accepted = true }
      else if (ctrl && (ev.key === Qt.Key_O || ev.key === Qt.Key_Down)) { d.openSelection(); ev.accepted = true }
      else if (ctrl && ev.key === Qt.Key_A) { d.selectAll(); ev.accepted = true }
      else if (ev.key === Qt.Key_Escape) { d.clear(); ev.accepted = true }
    }
  }

  // ---- the icons ---------------------------------------------------------------
  Repeater {
    model: d.items
    delegate: Item {
      id: ic
      required property var modelData
      readonly property var cell: d.places[modelData.name] || null
      readonly property bool on: !!d.selected[modelData.name]
      readonly property bool carried: d.mode === "move" && d.moving.indexOf(modelData.name) >= 0 && !outDrag.Drag.active
      readonly property bool target: d.dropTarget !== null && d.dropTarget.name === modelData.name
      visible: cell !== null
      width: d.cellW; height: d.cellH
      x: (cell ? d.cellX(cell[0]) : 0) + (carried ? d.dx : 0)
      y: (cell ? d.cellY(cell[1]) : 0) + (carried ? d.dy : 0)
      z: carried ? 5 : 0
      opacity: carried ? 0.8 : 1
      Behavior on x { enabled: !ic.carried; NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
      Behavior on y { enabled: !ic.carried; NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }

      // Selected: a soft plate behind the picture, the name on the accent.
      Rectangle {
        x: (parent.width - d.icon) / 2 - 5; y: 0
        width: d.icon + 10; height: d.icon + 6; radius: 8
        color: Qt.rgba(0, 0, 0, 0.22)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
        visible: ic.on || ic.target
      }
      Image {
        id: pic
        x: (parent.width - d.icon) / 2; y: 3
        width: d.icon; height: d.icon
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        sourceSize: Qt.size(d.icon * 2, d.icon * 2)
        readonly property bool photo: !ic.modelData.dir && Folders.kindOf(ic.modelData.name, false) === "image"
        source: photo ? "file://" + ic.modelData.path : Folders.iconFor(ic.modelData.path, ic.modelData.name, ic.modelData.dir)
        scale: ic.target ? 1.08 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
      }
      Rectangle {
        id: plate
        visible: ic.on && d.renaming !== ic.modelData.name
        anchors.horizontalCenter: label.horizontalCenter
        y: label.y - 1
        width: Math.min(d.cellW - 4, label.contentWidth + 10); height: label.contentHeight + 2
        radius: 5
        color: Theme.accent
      }
      Text {
        id: label
        visible: d.renaming !== ic.modelData.name
        x: 4; y: d.icon + 9
        width: d.cellW - 8
        text: ic.modelData.name
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        maximumLineCount: ic.on ? 4 : 2
        elide: Text.ElideMiddle
        font.family: Theme.font
        font.pixelSize: 12
        font.weight: Font.Medium
        color: "#ffffff"
        style: ic.on ? Text.Normal : Text.Raised
        styleColor: Qt.rgba(0, 0, 0, 0.55)
      }
      // Renaming, in place.
      Rectangle {
        id: renameBox
        visible: d.renaming === ic.modelData.name
        x: 2; y: d.icon + 6
        width: d.cellW - 4
        implicitHeight: Math.max(26, edit.contentHeight + 8)
        height: implicitHeight
        radius: 6
        color: Theme.dark ? "#1c1d22" : "#ffffff"
        border.color: Theme.accent
        border.width: 2

        function startRename() {
          edit.text = ic.modelData.name
          focusTimer.restart()
        }

        Timer {
          id: focusTimer
          interval: 25
          repeat: false
          onTriggered: {
            edit.forceActiveFocus()
            const dot = ic.modelData.dir ? -1 : edit.text.lastIndexOf(".")
            edit.select(0, dot > 0 ? dot : edit.text.length)
          }
        }

        Component.onCompleted: if (d.renaming === ic.modelData.name) startRename()
        onVisibleChanged: if (visible) startRename()

        Connections {
          target: d
          function onRenamingChanged() {
            if (d.renaming === ic.modelData.name) renameBox.startRename()
          }
        }

        TextInput {
          id: edit
          anchors { fill: parent; margins: 3 }
          horizontalAlignment: TextInput.AlignHCenter
          verticalAlignment: TextInput.AlignVCenter
          wrapMode: TextInput.Wrap
          color: Theme.dark ? "#ffffff" : "#111111"
          font.family: Theme.font
          font.pixelSize: 12
          font.weight: Font.Medium
          selectByMouse: true
          selectionColor: Theme.accent
          selectedTextColor: "#ffffff"
          Keys.onReturnPressed: d.rename(ic.modelData.name, text)
          Keys.onEnterPressed: d.rename(ic.modelData.name, text)
          Keys.onEscapePressed: d.renaming = ""
          onActiveFocusChanged: if (!activeFocus && d.renaming === ic.modelData.name) d.rename(ic.modelData.name, text)
        }
      }
    }
  }
  function commitRename() {
    if (!renaming) return
    // The field's own focus-out renames it.
    keys.forceActiveFocus()
    renaming = ""
  }

  // The selection band.
  Rectangle {
    visible: d.mode === "band"
    x: Math.min(d.from.x, d.at.x); y: Math.min(d.from.y, d.at.y)
    width: Math.abs(d.at.x - d.from.x); height: Math.abs(d.at.y - d.from.y)
    color: Qt.rgba(0, 0.48, 1, 0.20)
    border.width: 1.5; border.color: Qt.rgba(0, 0.48, 1, 0.75)
    radius: 3
    z: 10
  }

  // Colour & Symbol, next to the folder.
  FolderStyler {
    id: styler
    visible: d.styling !== ""
    path: d.styling ? d.dir + "/" + d.styling : ""
    solid: false
    backdrop: d.backdrop
    backdropRect: Qt.rect(x, y, width, height)
    readonly property var cell: d.styling ? d.places[d.styling] : null
    x: cell ? Math.max(12, d.cellX(cell[0]) - width - 8) : 0
    y: cell ? Math.max(d.padTop, Math.min(d.cellY(cell[1]), d.height - height - d.padBottom)) : 0
    onDone: d.styling = ""
    onVisibleChanged: if (visible) focusSearch()
    // Taps on the card stay on it.
    TapHandler {}
    DragHandler { target: null }
  }
}
