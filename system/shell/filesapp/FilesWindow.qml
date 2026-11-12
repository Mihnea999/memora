import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui

// One Files window.
FloatingWindow {
  required property var app
  id: win
  property string startPath
  onVisibleChanged: if (!visible) closeMe()
  signal closeMe()
  title: "Files"
  implicitWidth: 1040
  implicitHeight: 660
  minimumSize: Qt.size(460, 360)
  // Narrow (docked beside another app on a small screen): the sidebar tucks
  // away and slides in over the files when wanted.
  readonly property bool compact: width < 700
  property bool sideOpen: false
  onCompactChanged: sideOpen = false
  color: "transparent"

  // ---- where we are
  property string path: startPath
  property var back: []
  property var fwd: []
  property string view: "icons"                 // icons | list
  property bool hidden: false
  property real iconSize: 72
  property string query: ""
  property var found: []
  property var selected: ({})                   // path -> true
  property string renaming: ""
  property string lastClicked: ""
  readonly property bool inTrash: path === trashDir
  readonly property string trashDir: app.home + "/.local/share/Trash/files"
  readonly property string title2: path === app.home ? "Home" : (inTrash ? "Trash" : (path === "/" ? "Computer" : path.split("/").pop()))
  readonly property var selection: Object.keys(selected)

  function go(p, keepHistory) {
    if (!p || p === path) return
    if (!keepHistory) { back = back.concat([path]); fwd = [] }
    path = p; selected = ({}); lastClicked = ""; renaming = ""; search.text = ""; query = ""
    appear.restart()
  }
  function goBack() { if (!back.length) return; fwd = [path].concat(fwd); const p = back[back.length - 1]; back = back.slice(0, -1); go(p, true) }
  function goForward() { if (!fwd.length) return; back = back.concat([path]); const p = fwd[0]; fwd = fwd.slice(1); go(p, true) }
  function up() { if (path !== "/") go(path.substring(0, path.lastIndexOf("/")) || "/") }

  function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  function sh(cmd, then) { const p = runner.createObject(win, { cmd: cmd }); if (then) p.done.connect(then) }
  function openItem(p, isDir) {
    if (isDir) return go(p)
    Quickshell.execDetached(["gio", "open", p])
  }
  // The path of row i in what is shown (the folder, or search results).
  function pathAt(i) { return content.searching ? found[i] : folder.get(i, "filePath") }
  function isDir(p) { const i = folder.indexOf("file://" + p); return i >= 0 && !!folder.get(i, "fileIsDir") }
  // As in Finder: a click selects one; Ctrl (or Super) adds or removes one;
  // Shift adds everything from the last clicked one to this one.
  // `mods` comes from the handler's point (a TapHandler's tapped eventPoint
  // carries no modifiers).
  function select(p, mods) {
    const toggle = mods & (Qt.ControlModifier | Qt.MetaModifier), range = mods & Qt.ShiftModifier
    const s = toggle || range ? Object.assign({}, selected) : {}
    const a = range && lastClicked ? (() => { for (let i = 0; i < content.n; i++) if (pathAt(i) === lastClicked) return i; return -1 })() : -1
    if (a >= 0) {
      let b = -1
      for (let i = 0; i < content.n; i++) if (pathAt(i) === p) { b = i; break }
      if (b < 0) s[p] = true
      else for (let i = Math.min(a, b); i <= Math.max(a, b); i++) s[pathAt(i)] = true
    } else if (toggle) { if (s[p]) delete s[p]; else s[p] = true }
    else s[p] = true
    selected = s
    if (a < 0) lastClicked = p
  }
  function selectAll() { const s = {}; for (let i = 0; i < content.n; i++) s[pathAt(i)] = true; selected = s }
  // A drag of the selection starts: the icons it shows.
  function iconSrc(p) {
    const name = p.split("/").pop(), dir = isDir(p)
    return !dir && kindOf(name, false) === "image" ? "file://" + p : iconFor(p, name, dir)
  }
  function startDrag() {
    dragging = selection.slice()
    ghost.icons = dragging.slice(0, 3).map(iconSrc)
    ghost.count = dragging.length
  }
  function newFolder() {
    let n = "untitled folder", i = 2
    const names = {}; for (let j = 0; j < win.entries; j++) names[folder.get(j, "fileName")] = true
    while (names[n]) n = "untitled folder " + i++
    sh("mkdir -p " + q(path + "/" + n), () => { selected = ({ [path + "/" + n]: true }); renaming = path + "/" + n })
  }
  function trash() {
    if (!selection.length) return
    const items = selection.slice()
    if (inTrash) {
      confirm.ask({
        title: items.length === 1 ? "Delete “" + items[0].split("/").pop() + "” immediately?" : "Delete " + items.length + " items immediately?",
        message: "You can't undo this action.", action: "Delete",
        onAccept: () => { sh("rm -rf -- " + items.map(q).join(" ") + " && setsid -f memora-sound trash >/dev/null 2>&1"); selected = ({}) }
      })
      return
    }
    sh("gio trash -- " + items.map(q).join(" ") + " && setsid -f memora-sound trash >/dev/null 2>&1")
    selected = ({})
  }
  // ---- drives (memora-drives): SSDs, partitions and USB sticks to open -----------
  property var drives: []
  Process {
    id: driveList
    command: ["memora-drives", "list"]
    stdout: StdioCollector { onStreamFinished: { try { win.drives = JSON.parse(text) } catch (e) {} } }
  }
  Timer { interval: 3000; repeat: true; triggeredOnStart: true; running: win.visible; onTriggered: if (!driveList.running) driveList.running = true }
  property string driveError: ""
  Timer { id: driveErrorTimer; interval: 5000; onTriggered: win.driveError = "" }
  Component {
    id: driveCmd
    Process {
      id: dp
      property var then: null
      property string out: ""
      property bool outDone: false
      property int code: -1
      running: true
      stdout: StdioCollector { onStreamFinished: { dp.out = text.trim(); dp.outDone = true; dp.finish() } }
      stderr: StdioCollector { id: derr }
      onExited: c => { code = c; finish() }
      // Both the output and the exit are in (they come in either order).
      function finish() {
        if (code < 0 || !outDone) return
        driveList.running = true
        if (code !== 0) { win.driveError = derr.text.trim() || "Couldn't do that."; driveErrorTimer.restart() }
        else if (then) then(out)
        destroy()
      }
    }
  }
  function driveRun(args, then, input) {
    const p = driveCmd.createObject(win, { command: ["memora-drives"].concat(args), then: then || null, stdinEnabled: input !== undefined })
    if (input !== undefined) { p.write(input + "\n"); p.stdinEnabled = false }
  }
  function openDrive(d) {
    if (d.locked) return unlockSheet.ask(d)
    if (d.mounted) return go(d.mounted)
    driveRun(["mount", d.id], where => { if (where) go(where) })
  }
  function ejectDrive(d) {
    if (d.mounted && (path === d.mounted || path.startsWith(d.mounted + "/"))) go(app.home)
    driveRun([d.removable ? "eject" : "unmount", d.id])
  }

  function emptyTrash() {
    confirm.ask({
      title: "Empty the Trash?", message: "Everything in the Trash will be deleted. You can't undo this action.", action: "Empty Trash",
      onAccept: () => sh("[ -z \"$(ls -A ~/.local/share/Trash/files 2>/dev/null)\" ] || { gio trash --empty && setsid -f memora-sound trash >/dev/null 2>&1; }")
    })
  }
  function copy(cut) { app.clip = selection.slice(); app.clipCut = cut }
  function paste() {
    if (!app.clip.length) return
    // A name already taken in this folder: the pasted item becomes "name copy".
    sh(freeName + "for f in " + app.clip.map(q).join(" ") + "; do [ -e \"$f\" ] || continue; " +
      (app.clipCut ? "[ \"$(dirname -- \"$f\")\" = " + q(path) + " ] && continue; " : "") +
      "t=$(free " + q(path) + " \"$(basename -- \"$f\")\"); " + (app.clipCut ? "mv -n" : "cp -a") + " -- \"$f\" \"$t\" || bad=1; done; [ -z \"$bad\" ]")
    if (app.clipCut) app.clip = []
  }
  // free DIR NAME: NAME's path in DIR, or "NAME copy", "NAME copy 2"… when taken.
  readonly property string freeName: "free() { local d=\"$1\" b=\"$2\" n e c i=2; [ -e \"$d/$b\" ] || { printf %s \"$d/$b\"; return; }; " +
    "if [[ $b == ?*.* && ! -d \"$d/$b\" ]]; then n=\"${b%.*}\"; e=\".${b##*.}\"; else n=\"$b\"; e=\"\"; fi; " +
    "c=\"$d/$n copy$e\"; while [ -e \"$c\" ]; do c=\"$d/$n copy $i$e\"; i=$((i+1)); done; printf %s \"$c\"; }; "
  function rename(p, name) {
    renaming = ""
    if (!name || name === p.split("/").pop() || name.indexOf("/") >= 0) return
    const to = p.substring(0, p.lastIndexOf("/") + 1) + name
    sh("mv -n -- " + q(p) + " " + q(to), () => { selected = ({ [to]: true }); Folders.moved(p, to) })
  }
  function moveInto(dir) {
    if (!dragging.length || dragging.indexOf(dir) >= 0) return
    const moving = dragging.slice()
    sh((dir === trashDir ? "gio trash -- " : "mv -n -- ") + moving.map(q).join(" ") + (dir === trashDir ? " && setsid -f memora-sound trash >/dev/null 2>&1" : " " + q(dir + "/")),
      () => { if (dir !== trashDir) moving.forEach(m => Folders.moved(m, dir + "/" + m.split("/").pop())) })
  }
  property var dragging: []
  property string styling: ""                  // the folder whose colour & symbol is being picked

  Component { id: runner; Process {
    property string cmd
    signal done()
    command: ["bash", "-c", cmd]
    running: true
    stderr: StdioCollector { id: runErr }
    // What went wrong (no permission, disk full…) is said, not swallowed.
    onExited: code => {
      if (code !== 0) {
        const line = runErr.text.trim().split("\n").pop() || ""
        win.driveError = line ? line.replace(/^[a-z]+: /, "").replace(/^.*: (?=[^:]+$)/, "") : "Couldn't do that."
        driveErrorTimer.restart()
      }
      done(); destroy()
    }
  } }

  // How many entries the folder really has. Qt's FolderListModel keeps the
  // previous folder's rows when the new one is empty, so rows from another
  // folder count as none (else an empty Screenshots showed Pictures' items,
  // "Screenshots" among them, which then wouldn't open).
  readonly property int entries: {
    const c = folder.count
    if (!c) return 0
    const fp = folder.get(0, "filePath") || ""
    return (fp.substring(0, fp.lastIndexOf("/")) || "/") === path ? c : 0
  }
  FolderListModel {
    id: folder
    folder: "file://" + win.path
    showDirsFirst: true
    showHidden: win.hidden
    showDotAndDotDot: false
    sortField: FolderListModel.Name
    sortCaseSensitive: false
  }

  // Search: names under this folder, a few levels deep.
  Process {
    id: finder
    stdout: StdioCollector { onStreamFinished: win.found = text.split("\n").filter(l => l).slice(0, 300) }
  }
  Timer { id: findLater; interval: 200; onTriggered: { if (win.query.length < 2) { win.found = []; return } finder.running = false; finder.command = ["bash", "-c", "find \"$1\" -maxdepth 5 -not -path '*/.*' -iname \"*$2*\" 2>/dev/null | head -300", "_", win.path, win.query]; finder.running = true } }

  // Free space for the status bar.
  property string free: ""
  Process { id: df; command: ["bash", "-c", "df -h --output=avail \"$1\" | tail -1", "_", win.path]; stdout: StdioCollector { onStreamFinished: win.free = text.trim() } }
  onPathChanged: { sideOpen = false; df.running = true }

  // ---- icons for files (shared with the desktop; a folder's own colour and symbol too)
  function kindOf(name, isDir) { return Folders.kindOf(name, isDir) }
  function iconFor(p, name, isDir) { return Folders.iconFor(p, name, isDir) }
  function sizeText(b) {
    if (b < 1000) return b + " bytes"
    if (b < 1e6) return (b / 1e3).toFixed(0) + " KB"
    if (b < 1e9) return (b / 1e6).toFixed(1) + " MB"
    return (b / 1e9).toFixed(2) + " GB"
  }
  function dateText(d) {
    const now = new Date()
    if (d.toDateString() === now.toDateString()) return "Today at " + Qt.formatTime(d, "HH:mm")
    const y = new Date(now); y.setDate(now.getDate() - 1)
    if (d.toDateString() === y.toDateString()) return "Yesterday at " + Qt.formatTime(d, "HH:mm")
    return Qt.formatDateTime(d, "d MMM yyyy, HH:mm")
  }

  // ================================================================ layout
  Rectangle { anchors.fill: parent; color: Theme.window }

  // ---- sidebar
  Rectangle {
    id: side
    width: 210
    z: win.compact ? 10 : 0
    anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 8 }
    anchors.leftMargin: win.compact && !win.sideOpen ? -width - 24 : 8
    Behavior on anchors.leftMargin { NumberAnimation { duration: Theme.normal; easing.type: Theme.easingEmph } }
    radius: 12
    color: win.compact ? Theme.glassSolid : Theme.sidebar
    border.color: Theme.separator
    WindowControls { x: 14; y: 14; window: win; onCloseRequested: win.closeMe() }
    Item { anchors { left: parent.left; right: parent.right; top: parent.top } height: 40; DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) } }

    Flickable {
      anchors { fill: parent; topMargin: 44; bottomMargin: 8 }
      contentHeight: places.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: places
        width: parent.width
        spacing: 1
        Header { text: "Favorites" }
        Repeater {
          model: [["Home", app.home, "user-home"], ["Desktop", app.home + "/Desktop", "user-desktop"], ["Documents", app.home + "/Documents", "folder-documents"],
                  ["Downloads", app.home + "/Downloads", "folder-download"], ["Pictures", app.home + "/Pictures", "folder-pictures"],
                  ["Music", app.home + "/Music", "folder-music"], ["Videos", app.home + "/Videos", "folder-videos"], ["Projects", app.home + "/Projects", "folder-projects"]]
          delegate: Place { required property var modelData; label: modelData[0]; target: modelData[1]; icon: modelData[2] }
        }
        Header { text: "Locations" }
        Place { label: "Computer"; target: "/"; icon: "folder" }
        Place { label: "Trash"; target: win.trashDir; icon: "user-trash" }
        Header { visible: win.drives.length > 0; text: "Drives" }
        Repeater { model: win.drives; delegate: DriveItem { required property var modelData; d: modelData } }
        Txt { visible: win.driveError !== ""; x: 16; width: places.width - 28; text: win.driveError; color: Theme.red; font.pixelSize: Theme.small - 0.5; wrapMode: Text.Wrap }
      }
    }
  }

  // A drive: click opens it (mounting, or asking an encrypted one's passphrase),
  // ⏏ puts it away, right click for "Open at Login".
  component DriveItem: Item {
    id: dr
    property var d
    readonly property bool here: !!d.mounted && (win.path === d.mounted || win.path.startsWith(d.mounted + "/"))
    width: places.width; height: 30
    Rectangle {
      anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
      radius: 7
      color: dr.here ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.35 : 0.18) : (dh.hovered ? Theme.hover : "transparent")
    }
    Image { id: di; x: 16; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; sourceSize: Qt.size(36, 36); source: Quickshell.iconPath(dr.d.removable ? "drive-removable-media" : "drive-harddisk", "drive-harddisk") }
    Txt {
      anchors { left: di.right; leftMargin: 9; right: tail.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
      text: dr.d.name; elide: Text.ElideRight
      opacity: dr.d.mounted ? 1 : 0.75
    }
    Row {
      id: tail
      anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
      spacing: 4
      Sym { visible: dr.d.locked; name: "lock"; width: 11; height: 11; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
      Txt { visible: !dr.d.mounted && !dr.d.locked && dh.hovered; text: dr.d.size; color: Theme.textDim; font.pixelSize: Theme.small - 1; anchors.verticalCenter: parent.verticalCenter }
      Rectangle {
        visible: !!dr.d.mounted
        width: 20; height: 20; radius: 10
        color: eh.hovered ? Theme.pressed : "transparent"
        Txt { anchors.centerIn: parent; text: "⏏"; color: Theme.textDim; font.pixelSize: 13 }
        HoverHandler { id: eh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: win.ejectDrive(dr.d) }
        Tip { text: dr.d.removable ? "Eject" : "Unmount" }
      }
    }
    HoverHandler { id: dh }
    TapHandler { onTapped: win.openDrive(dr.d) }
    TapHandler {
      acceptedButtons: Qt.RightButton
      onTapped: ev => menu.showItems(dr, ev.position.x, ev.position.y, [
        { text: dr.d.mounted ? "Open" : "Open", action: () => win.openDrive(dr.d) },
        { text: "Open in New Window", enabled: !!dr.d.mounted, action: () => app.openWindow(dr.d.mounted) },
        { separator: true },
        { text: (dr.d.pinned ? "✓  " : "") + "Open at Login", action: () => {
            if (dr.d.locked && !dr.d.pinned) unlockSheet.ask(dr.d, true)
            else win.driveRun(["pin", dr.d.id, dr.d.pinned ? "off" : "on"]) } },
        { separator: true },
        { text: dr.d.removable ? "Eject" : "Unmount", enabled: !!dr.d.mounted, action: () => win.ejectDrive(dr.d) }
      ])
    }
  }

  component Header: Text {
    x: 16; height: 30; verticalAlignment: Text.AlignBottom; bottomPadding: 4
    color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.small - 0.5; font.weight: Font.Bold
  }
  component Place: Item {
    id: pl
    property string label; property string target; property string icon
    readonly property bool here: win.path === target
    width: places.width; height: 30
    Rectangle {
      anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
      radius: 7
      color: pl.here ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.35 : 0.18) : (drop.containsDrag ? Theme.pressed : (ph.hovered ? Theme.hover : "transparent"))
      Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    Image { id: pi; x: 16; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; sourceSize: Qt.size(36, 36); source: Quickshell.iconPath(pl.icon) }
    Txt { anchors { left: pi.right; leftMargin: 9; verticalCenter: parent.verticalCenter } text: pl.label }
    HoverHandler { id: ph }
    TapHandler { onTapped: win.go(pl.target) }
    DropArea { id: drop; anchors.fill: parent; onDropped: win.moveInto(pl.target) }
  }

  CompactBar {
    x: 14; y: 16; z: 5
    visible: win.compact
    window: win; sideOpen: win.sideOpen
    onToggled: win.sideOpen = !win.sideOpen
    onCloseRequested: win.closeMe()
  }
  MouseArea { anchors.fill: parent; z: 9; visible: win.compact && win.sideOpen; onClicked: win.sideOpen = false }

  // ---- toolbar
  Item {
    id: tools
    anchors { left: win.compact ? parent.left : side.right; right: parent.right; top: parent.top; leftMargin: win.compact ? 128 : 0 }
    height: 52
    DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) }
    Row {
      x: 14; anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      ToolBtn { sym: "chevron"; flip: true; tip: "Back"; enabled: win.back.length > 0; onClicked: win.goBack() }
      ToolBtn { sym: "chevron"; tip: "Forward"; enabled: win.fwd.length > 0; onClicked: win.goForward() }
      Item { width: 10; height: 1 }
      Txt { anchors.verticalCenter: parent.verticalCenter; text: win.query ? "Searching “" + win.query + "”" : win.title2; font.weight: Font.Bold; font.pixelSize: Theme.fontSize + 1 }
    }
    Row {
      anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
      spacing: 8
      Kbd {
        visible: win.inTrash
        text: "Empty Trash"
        onClicked: win.emptyTrash()
      }
      // View choice
      Rectangle {
        width: 64; height: 28; radius: 8; color: Theme.field; border.color: Theme.separator
        Rectangle {
          x: win.view === "icons" ? 2 : 32; y: 2; width: 30; height: 24; radius: 6
          color: Theme.dark ? Qt.rgba(1, 1, 1, 0.18) : "#ffffff"
          Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
        }
        Row {
          anchors.fill: parent; anchors.margins: 2
          Item { width: 30; height: 24; GridGlyph { anchors.centerIn: parent } TapHandler { onTapped: win.view = "icons" } Tip { text: "Icons" } }
          Item { width: 30; height: 24; ListGlyph { anchors.centerIn: parent } TapHandler { onTapped: win.view = "list" } Tip { text: "List" } }
        }
      }
      Rectangle {
        width: 200; height: 28; radius: 8
        color: Theme.field; border.color: search.activeFocus ? Theme.accent : Theme.separator
        Sym { name: "search"; width: 12; height: 12; color: Theme.textDim; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
        TextInput {
          id: search
          anchors { left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 8; verticalCenter: parent.verticalCenter }
          color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
          clip: true
          onTextChanged: { win.query = text; findLater.restart() }
          Keys.onEscapePressed: { text = ""; content.forceActiveFocus() }
          Txt { visible: !search.text; text: "Search"; color: Theme.textFaint; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
        }
      }
    }
  }

  // ---- contents
  Item {
    id: content
    // Two fingers sideways: back and forward through the folders you visited.
    SwipeNav { onBack: win.goBack(); onForward: win.goForward() }
    anchors { left: win.compact ? parent.left : side.right; right: parent.right; top: tools.bottom; bottom: status.top; leftMargin: 6 }
    focus: true
    // Not clipped, so a dragged file stays visible over the sidebar.
    clip: false

    // The current list: the folder, or search results.
    readonly property bool searching: win.query.length >= 2
    readonly property int n: searching ? win.found.length : win.entries
    function at(i) {
      if (!searching) return { name: folder.get(i, "fileName"), path: folder.get(i, "filePath"), dir: folder.get(i, "fileIsDir"), size: folder.get(i, "fileSize"), mod: folder.get(i, "fileModified") }
      const p = win.found[i]; return { name: p.split("/").pop(), path: p, dir: false, size: 0, mod: new Date(), search: true }
    }

    // New folder contents arrive with a short fade and rise.
    opacity: 1
    SequentialAnimation {
      id: appear
      PropertyAction { target: content; property: "opacity"; value: 0 }
      PropertyAction { target: shift; property: "y"; value: 10 }
      ParallelAnimation {
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
        NumberAnimation { target: shift; property: "y"; to: 0; duration: Theme.slow; easing.type: Easing.OutQuint }
      }
    }
    transform: Translate { id: shift }

    Keys.onPressed: ev => {
      const c = ev.modifiers & Qt.ControlModifier, a = ev.modifiers & Qt.AltModifier, s = ev.modifiers & Qt.ShiftModifier
      if (win.renaming) return
      if (ev.key === Qt.Key_Delete) win.trash()
      else if (ev.key === Qt.Key_F2 && win.selection.length === 1) win.renaming = win.selection[0]
      else if (ev.key === Qt.Key_Return && win.selection.length) { win.selection.forEach(p => win.openItem(p, win.isDir(p))) }
      else if (c && s && ev.key === Qt.Key_N) win.newFolder()
      else if (c && ev.key === Qt.Key_N) app.openWindow(win.path)
      else if (c && ev.key === Qt.Key_W) win.closeMe()
      else if (c && ev.key === Qt.Key_A) win.selectAll()
      else if (c && ev.key === Qt.Key_I && win.selection.length) info.show(win.selection[0])
      else if (c && ev.key === Qt.Key_C) win.copy(false)
      else if (c && ev.key === Qt.Key_X) win.copy(true)
      else if (c && ev.key === Qt.Key_V) win.paste()
      else if (c && ev.key === Qt.Key_F) search.forceActiveFocus()
      else if (c && ev.key === Qt.Key_L) { goBox.visible = true; goField.text = win.path + "/"; goField.forceActiveFocus() }
      else if (c && ev.key === Qt.Key_H) win.hidden = !win.hidden
      else if (c && ev.key === Qt.Key_1) win.view = "icons"
      else if (c && ev.key === Qt.Key_2) win.view = "list"
      else if (c && (ev.key === Qt.Key_Equal || ev.key === Qt.Key_Plus)) win.iconSize = Math.min(128, win.iconSize + 16)
      else if (c && ev.key === Qt.Key_Minus) win.iconSize = Math.max(40, win.iconSize - 16)
      else if (a && ev.key === Qt.Key_Left) win.goBack()
      else if (a && ev.key === Qt.Key_Right) win.goForward()
      else if (a && ev.key === Qt.Key_Up) win.up()
      else if (a && ev.key === Qt.Key_Home) win.go(app.home)
      else if (ev.key === Qt.Key_Backspace) win.up()
      else return
      ev.accepted = true
    }

    // Click on empty space: clear the selection; right-click: folder menu.
    // In the icon view only the icon and its name count, not the rest of the cell.
    function hitAt(x, y) {
      if (win.view !== "icons") return list.itemAt(x - list.x + list.contentX, y - list.parent.y - list.y + list.contentY)
      const c = grid.itemAt(x - grid.x + grid.contentX, y - grid.y + grid.contentY)
      if (!c || !c.hitBox) return c
      return c.hitBox.contains(c.hitBox.mapFromItem(content, x, y)) ? c : null
    }
    // (not while a menu is open: a click on its buttons passes through to here)
    TapHandler {
      id: bgTap
      enabled: !menu.visible
      onTapped: ev => {
        if (!content.hitAt(ev.position.x, ev.position.y) && !(bgTap.point.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier))) win.selected = ({})
        content.forceActiveFocus()
      }
    }

    // A drag on empty space draws a box; what it touches is selected
    // (added to the selection with Ctrl, Super or Shift held).
    readonly property real scrollY: win.view === "icons" ? grid.contentY : list.contentY
    DragHandler {
      id: band
      target: null
      enabled: !menu.visible && !win.renaming
      property bool on: false
      property real ax; property real ay           // where it started (ay scrolls with the files)
      property real bx; property real by           // where the pointer is
      property var base: ({})
      onActiveChanged: {
        if (!active) { on = false; return }
        const pp = centroid.pressPosition
        if (content.hitAt(pp.x, pp.y)) return
        base = centroid.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.ShiftModifier) ? Object.assign({}, win.selected) : ({})
        ax = pp.x; ay = pp.y + content.scrollY
        bx = centroid.position.x; by = centroid.position.y
        on = true
        content.forceActiveFocus()
        content.bandSelect()
      }
      onCentroidChanged: if (on) { bx = centroid.position.x; by = centroid.position.y; content.bandSelect() }
    }
    onScrollYChanged: if (band.on) bandSelect()
    function bandSelect() {
      const sy = scrollY
      const x1 = Math.min(band.ax, band.bx), x2 = Math.max(band.ax, band.bx)
      const y1 = Math.min(band.ay, band.by + sy), y2 = Math.max(band.ay, band.by + sy)
      const s = Object.assign({}, band.base)
      if (win.view === "icons") {
        const cw = grid.cellWidth, ch = grid.cellHeight, cols = Math.max(1, Math.floor(grid.width / cw))
        const bw = win.iconSize + 12, bh = win.iconSize + 44
        for (let i = 0; i < n; i++) {
          const ix = grid.x + (i % cols) * cw + (cw - bw) / 2, iy = grid.y + Math.floor(i / cols) * ch + 4
          if (ix < x2 && ix + bw > x1 && iy < y2 && iy + bh > y1) s[win.pathAt(i)] = true
        }
      } else {
        const top = list.parent.y + list.y
        if (x1 < list.width - 6 && x2 > 6)
          for (let i = 0; i < n; i++) { const ry = top + i * 30; if (ry < y2 && ry + 30 > y1) s[win.pathAt(i)] = true }
      }
      win.selected = s
    }
    // Near the top or bottom edge, the files scroll under the box.
    Timer {
      interval: 16; repeat: true; running: band.on
      onTriggered: {
        const v = win.view === "icons" ? grid : list
        const top = v.mapToItem(content, 0, 0).y, bot = top + v.height
        const d = band.by < top + 10 ? -14 : (band.by > bot - 10 ? 14 : 0)
        if (d) v.contentY = Math.max(0, Math.min(Math.max(0, v.contentHeight - v.height), v.contentY + d))
      }
    }
    Rectangle {
      visible: band.on
      z: 20
      x: Math.max(0, Math.min(band.ax, band.bx)); y: Math.max(0, Math.min(band.ay - content.scrollY, band.by))
      width: Math.max(0, Math.min(content.width, Math.max(band.ax, band.bx)) - x)
      height: Math.max(0, Math.min(content.height, Math.max(band.ay - content.scrollY, band.by)) - y)
      radius: 3
      color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
      border.width: 1; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
    }
    // Only on empty space: a file under the pointer opens its own menu.
    TapHandler {
      acceptedButtons: Qt.RightButton
      onTapped: ev => {
        if (!content.hitAt(ev.position.x, ev.position.y)) menu.show(ev.position.x, ev.position.y, null)
      }
    }

    Txt {
      visible: content.n === 0
      anchors.centerIn: parent
      text: content.searching ? "No results" : (win.inTrash ? "Trash is empty" : "This folder is empty")
      color: Theme.textDim
    }

    // Icons
    GridView {
      id: grid
      visible: win.view === "icons"
      anchors.fill: parent
      anchors.margins: 10
      clip: true
      cellWidth: win.iconSize + 48
      cellHeight: win.iconSize + 52
      model: content.n
      boundsBehavior: Flickable.StopAtBounds
      // Scroll with the wheel; a drag always moves files.
      interactive: false
      WheelHandler { onWheel: ev => grid.contentY = Math.max(0, Math.min(grid.contentHeight - grid.height, grid.contentY - ev.angleDelta.y)) }
      delegate: Item {
        id: cell
        required property int index
        readonly property var f: content.at(index)
        readonly property bool sel: !!win.selected[f.path]
        width: grid.cellWidth; height: grid.cellHeight
        opacity: win.dragging.indexOf(f.path) >= 0 ? 0.4 : 1
        Rectangle {
          id: ib
          anchors.horizontalCenter: parent.horizontalCenter
          y: 4; width: win.iconSize + 12; height: win.iconSize + 10; radius: 8
          color: cell.sel ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)) : (fdrop.containsDrag ? Theme.pressed : "transparent")
        }
        Image {
          id: thumb
          readonly property bool pic: win.kindOf(cell.f.name, cell.f.dir) === "image"
          anchors.centerIn: ib
          width: win.iconSize; height: win.iconSize
          source: pic ? "file://" + cell.f.path : win.iconFor(cell.f.path, cell.f.name, cell.f.dir)
          sourceSize: Qt.size(win.iconSize * 2, win.iconSize * 2)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true; mipmap: true
          scale: tap.pressed ? 0.94 : 1
          Behavior on scale { NumberAnimation { duration: Theme.fast } }
        }
        Rectangle {
          id: nameBg
          anchors { horizontalCenter: parent.horizontalCenter; top: ib.bottom; topMargin: 3 }
          width: Math.min(nameText.implicitWidth + 10, cell.width - 6); height: nameText.height + 2; radius: 5
          color: cell.sel ? Theme.accent : "transparent"
          visible: win.renaming !== cell.f.path
        }
        Text {
          id: nameText
          visible: win.renaming !== cell.f.path
          anchors { horizontalCenter: parent.horizontalCenter; top: ib.bottom; topMargin: 4 }
          width: cell.width - 14
          horizontalAlignment: Text.AlignHCenter
          text: cell.f.name
          textFormat: Text.PlainText
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 2
          elide: Text.ElideMiddle
          color: cell.sel ? "#ffffff" : Theme.text
          font.family: Theme.font; font.pixelSize: Theme.small
        }
        RenameField { visible: win.renaming === cell.f.path; anchors { horizontalCenter: parent.horizontalCenter; top: ib.bottom; topMargin: 2 } width: cell.width - 8; target: cell.f.path }

        // The icon and its name take clicks and drags; the rest of the cell is
        // empty space, where a drag draws a selection box.
        property alias hitBox: hitBox
        Item {
          id: hitBox
          anchors.horizontalCenter: parent.horizontalCenter
          y: ib.y
          width: Math.max(ib.width, nameBg.width)
          height: nameBg.y + nameBg.height + 2 - ib.y
          TapHandler { id: tap; enabled: !menu.visible; onTapped: { win.select(cell.f.path, tap.point.modifiers); content.forceActiveFocus() }
                       onDoubleTapped: win.openItem(cell.f.path, cell.f.dir) }
          TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => { if (!cell.sel) win.select(cell.f.path, 0); const p = hitBox.mapToItem(content, ev.position.x, ev.position.y); menu.show(p.x, p.y, cell.f) } }
          DragHandler {
            id: dh
            enabled: !menu.visible
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
            onActiveChanged: {
              if (active) { if (!cell.sel) win.select(cell.f.path, 0); win.startDrag() }
              else ghost.release()
            }
            onCentroidChanged: if (active) { const p = hitBox.mapToItem(content, centroid.position.x, centroid.position.y); ghost.x = p.x - ghost.width / 2; ghost.y = p.y - ghost.height / 2; ghost.track(p) }
          }
        }
        // Folders accept a drop.
        property bool hot: false
        function dropHere() { if (cell.f.dir) win.moveInto(cell.f.path) }
        Item { id: fdrop; property bool containsDrag: cell.hot && cell.f.dir }
      }
      add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal } }
    }

    // List
    Item {
      visible: win.view === "list"
      anchors.fill: parent
      Row {
        id: listHead
        x: 14; height: 28
        readonly property real w: parent.width - 28
        Repeater {
          model: [["Name", 0.5, FolderListModel.Name], ["Date Modified", 0.25, FolderListModel.Time], ["Size", 0.12, FolderListModel.Size], ["Kind", 0.13, FolderListModel.Type]]
          delegate: Item {
            required property var modelData
            width: listHead.w * modelData[1]; height: 28
            Txt {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData[0] + (folder.sortField === modelData[2] ? (folder.sortReversed ? "  ↓" : "  ↑") : "")
              color: Theme.textDim; font.pixelSize: Theme.small
              font.weight: folder.sortField === modelData[2] ? Font.Bold : Font.Normal
            }
            TapHandler { onTapped: { if (folder.sortField === modelData[2]) folder.sortReversed = !folder.sortReversed; else { folder.sortField = modelData[2]; folder.sortReversed = false } } }
          }
        }
      }
      Rectangle { anchors { left: parent.left; right: parent.right; top: listHead.bottom } height: 1; color: Theme.separator }
      ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: listHead.bottom; bottom: parent.bottom; topMargin: 2 }
        clip: true
        model: content.n
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        WheelHandler { onWheel: ev => list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY - ev.angleDelta.y)) }
        delegate: Rectangle {
          id: lrow
          required property int index
          readonly property var f: content.at(index)
          readonly property bool sel: !!win.selected[f.path]
          width: list.width - 12; x: 6; height: 30; radius: 6
          color: sel ? Theme.accent : (index % 2 ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.025) : Qt.rgba(0, 0, 0, 0.025)) : "transparent")
          readonly property color ink: sel ? "#ffffff" : Theme.text
          Row {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            Item {
              width: listHead.w * 0.5; height: 22
              Image { id: li; width: 20; height: 20; anchors.verticalCenter: parent.verticalCenter; sourceSize: Qt.size(40, 40); source: win.iconFor(lrow.f.path, lrow.f.name, lrow.f.dir) }
              Txt { visible: win.renaming !== lrow.f.path; anchors { left: li.right; leftMargin: 8; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: content.searching ? lrow.f.path.replace(app.home, "~") : lrow.f.name; color: lrow.ink }
              RenameField { visible: win.renaming === lrow.f.path; anchors { left: li.right; leftMargin: 6; verticalCenter: parent.verticalCenter } width: parent.width - 40; target: lrow.f.path }
            }
            Txt { width: listHead.w * 0.25; text: content.searching ? "" : win.dateText(lrow.f.mod); color: lrow.sel ? Qt.rgba(1, 1, 1, 0.85) : Theme.textDim; font.pixelSize: Theme.small }
            Txt { width: listHead.w * 0.12; text: lrow.f.dir ? "--" : win.sizeText(lrow.f.size); color: lrow.sel ? Qt.rgba(1, 1, 1, 0.85) : Theme.textDim; font.pixelSize: Theme.small }
            Txt { width: listHead.w * 0.13; text: lrow.f.dir ? "Folder" : win.kindOf(lrow.f.name, false).replace(/^./, c => c.toUpperCase()); color: lrow.sel ? Qt.rgba(1, 1, 1, 0.85) : Theme.textDim; font.pixelSize: Theme.small }
          }
          TapHandler { id: ltap; enabled: !menu.visible; onTapped: { win.select(lrow.f.path, ltap.point.modifiers); content.forceActiveFocus() } onDoubleTapped: win.openItem(lrow.f.path, lrow.f.dir) }
          property bool hot: false
          function dropHere() { if (lrow.f.dir) win.moveInto(lrow.f.path) }
          border.color: hot && f.dir ? Theme.accent : "transparent"
          border.width: 2
          DragHandler {
            enabled: !menu.visible
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
            onActiveChanged: {
              if (active) { if (!lrow.sel) win.select(lrow.f.path, 0); win.startDrag() }
              else ghost.release()
            }
            onCentroidChanged: if (active) { const p = lrow.mapToItem(content, centroid.position.x, centroid.position.y); ghost.x = p.x - ghost.width / 2; ghost.y = p.y - ghost.height / 2; ghost.track(p) }
          }
          TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => { if (!lrow.sel) win.select(lrow.f.path, 0); const p = lrow.mapToItem(content, ev.position.x, ev.position.y); menu.show(p.x, p.y, lrow.f) } }
        }
      }
    }

    // What you are dragging.
    DragStack {
      id: ghost
      visible: win.dragging.length > 0
      z: 30
      property var over: null
      // Let go: into the folder under the pointer, or onto a sidebar place.
      function release() {
        if (ghost.over) ghost.over.dropHere()
        else ghost.Drag.drop()
        if (ghost.over) ghost.over.hot = false
        win.dragging = []; ghost.over = null
      }
      function track(p) {
        // Out of the window: hand it to the system, so it can be dropped in
        // other apps (the AI, a browser, a chat…) as files.
        if (p.x < -8 || p.y < -8 || p.x > content.width + 8 || p.y > content.height + 8) { outDrag.start(); return }
        // Highlight the folder under the pointer (icons or list).
        const c = win.view === "icons" ? grid.itemAt(p.x - grid.x + grid.contentX, p.y - grid.y + grid.contentY)
                                       : list.itemAt(p.x - list.x + list.contentX, p.y - list.parent.y - list.y + list.contentY)
        if (over && over !== c) over.hot = false
        over = c && c.f && c.f.dir && win.dragging.indexOf(c.f.path) < 0 ? c : null
        if (over) over.hot = true
      }
      opacity: 0.9
      Drag.active: visible
      Drag.hotSpot: Qt.point(width / 2, height / 2)
    }
    // The same files, dragged out to other apps (a system drag-and-drop).
    // Its picture is the same small stack, grabbed at its own size: given an
    // image file's path (or nothing), the drag showed the whole picture at
    // full size, or the whole window.
    Item {
      id: outDrag
      property string uris: ""
      property var shot: null          // keeps the grabbed picture alive during the drag
      property bool starting: false
      function start() {
        if (!win.dragging.length || Drag.active || starting) return
        uris = win.dragging.map(f => "file://" + encodeURI(f)).join("\r\n") + "\r\n"
        if (ghost.over) ghost.over.hot = false
        ghost.over = null
        win.dragging = []
        starting = true
        const ok = dragPic.grabToImage(r => {
          shot = r
          Drag.imageSource = r.url
          starting = false
          Drag.active = true
        }, Qt.size(dragPic.width, dragPic.height))
        if (!ok) { starting = false; Drag.active = true }
      }
      Drag.dragType: Drag.Automatic
      Drag.supportedActions: Qt.CopyAction
      Drag.mimeData: ({ "text/uri-list": uris })
      Drag.hotSpot: Qt.point(dragPic.width / 2, dragPic.height / 2)
      Drag.imageSourceSize: Qt.size(dragPic.width, dragPic.height)
      Drag.onDragFinished: { Drag.active = false; shot = null }
    }
  }

  // ---- path and status
  Item {
    id: status
    anchors { left: win.compact ? parent.left : side.right; right: parent.right; bottom: parent.bottom; leftMargin: 6 }
    height: 30
    Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.separator }
    Row {
      x: 12; anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      Repeater {
        model: {
          // Inside the home folder the path starts at Home; elsewhere at Computer.
          if (win.inTrash) return [{ name: "Trash", path: win.trashDir }]
          const inHome = win.path === app.home || win.path.startsWith(app.home + "/")
          const rel = inHome ? win.path.slice(app.home.length) : win.path
          const parts = rel.split("/").filter(x => x)
          const base = inHome ? app.home : ""
          return [{ name: inHome ? "Home" : "Computer", path: inHome ? app.home : "/" }]
            .concat(parts.map((p, i) => ({ name: p, path: base + "/" + parts.slice(0, i + 1).join("/") })))
        }
        delegate: Row {
          required property var modelData
          required property int index
          spacing: 2
          Sym { visible: index > 0; name: "chevron"; width: 9; height: 9; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
          Txt { text: modelData.name; color: Theme.textDim; font.pixelSize: Theme.small; TapHandler { onTapped: win.go(modelData.path) } }
        }
      }
    }
    Txt {
      anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
      text: (win.selection.length ? win.selection.length + " of " : "") + content.n + (content.n === 1 ? " item" : " items") + (win.free ? ", " + win.free + " available" : "")
      color: Theme.textDim; font.pixelSize: Theme.small
    }
  }

  // ---- Get Info
  Glass {
    id: info
    property string path: ""
    property var d: ({})
    readonly property bool isDir: !!d.mode && d.mode.startsWith("d")
    visible: opacity > 0
    opacity: path !== "" ? 1 : 0
    scale: path !== "" ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
    z: 40
    anchors.centerIn: parent
    width: 380; height: icol.implicitHeight + 40
    radius: 18; fill: Theme.popover
    function show(p) {
      path = p; d = ({})
      infoProc.command = ["bash", "-c",
        "p=\"$1\"; stat -c '%s|%W|%Y|%A|%U' -- \"$p\"; echo '@@'; " +
        "if [ -d \"$p\" ]; then du -sb -- \"$p\" 2>/dev/null | cut -f1; else echo; fi; echo '@@'; " +
        "if [ -d \"$p\" ]; then find \"$p\" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l; else echo; fi; echo '@@'; " +
        "t=$(gio info -a standard::content-type -- \"$p\" 2>/dev/null | awk '/content-type/ {print $2}'); echo \"$t\"; echo '@@'; " +
        "a=$(xdg-mime query default \"$t\" 2>/dev/null); echo \"${a%.desktop}\"", "_", p]
      infoProc.running = true
    }
    Process {
      id: infoProc
      stdout: StdioCollector {
        onStreamFinished: {
          const f = text.split("@@\n").map(x => x.trim())
          const st = (f[0] || "").split("|")
          info.d = { size: parseInt(st[0]) || 0, created: parseInt(st[1]) || 0, modified: parseInt(st[2]) || 0, mode: st[3] || "", owner: st[4] || "",
                     total: parseInt(f[1]) || 0, items: parseInt(f[2]) || 0, type: f[3] || "", app: f[4] || "" }
        }
      }
    }
    TapHandler {}
    ColumnLayout {
      id: icol
      x: 20; y: 20; width: parent.width - 40
      spacing: 12
      RowLayout {
        spacing: 14
        Image {
          Layout.preferredWidth: 64; Layout.preferredHeight: 64; sourceSize: Qt.size(128, 128); fillMode: Image.PreserveAspectFit
          readonly property string nm: info.path.split("/").pop()
          source: !info.path ? "" : (!info.isDir && win.kindOf(nm, false) === "image" ? "file://" + info.path : win.iconFor(info.path, nm, info.isDir))
        }
        ColumnLayout {
          spacing: 2
          Layout.fillWidth: true
          Txt { Layout.fillWidth: true; text: info.path.split("/").pop(); font.weight: Font.Bold; font.pixelSize: Theme.fontSize + 2; elide: Text.ElideMiddle }
          Txt { text: info.isDir ? win.sizeText(info.d.total || 0) + ", " + (info.d.items || 0) + ((info.d.items || 0) === 1 ? " item" : " items") : win.sizeText(info.d.size || 0); color: Theme.textDim; font.pixelSize: Theme.small }
        }
      }
      Rectangle { Layout.fillWidth: true; height: 1; color: Theme.separator }
      GridLayout {
        columns: 2; columnSpacing: 14; rowSpacing: 7
        Layout.fillWidth: true
        InfoKey { text: "Kind" }
        InfoVal { text: info.isDir ? "Folder" : (info.d.type || "File") }
        InfoKey { text: "Where" }
        InfoVal { text: info.path.substring(0, info.path.lastIndexOf("/")).replace(app.home, "~") || "/" }
        InfoKey { text: "Created" }
        InfoVal { text: info.d.created ? win.dateText(new Date(info.d.created * 1000)) : "Unknown" }
        InfoKey { text: "Modified" }
        InfoVal { text: info.d.modified ? win.dateText(new Date(info.d.modified * 1000)) : "" }
        InfoKey { text: "Opens with"; visible: !!info.d.app }
        InfoVal { text: Apps.nameFor(info.d.app || ""); visible: !!info.d.app }
        InfoKey { text: "Owner" }
        InfoVal { text: info.d.owner || "" }
        InfoKey { text: "Permissions" }
        InfoVal { text: info.d.mode || "" }
      }
      RowLayout {
        Layout.topMargin: 4
        Item { Layout.fillWidth: true }
        Rectangle {
          implicitWidth: dt.implicitWidth + 28; implicitHeight: 28; radius: 8; color: Theme.accent
          Txt { id: dt; anchors.centerIn: parent; text: "Done"; color: "#ffffff"; font.weight: Font.Bold }
          TapHandler { onTapped: { info.path = ""; content.forceActiveFocus() } }
        }
      }
    }
  }
  component InfoKey: Txt { color: Theme.textDim; font.pixelSize: Theme.small + 0.5; Layout.alignment: Qt.AlignTop }
  component InfoVal: Txt { Layout.fillWidth: true; font.pixelSize: Theme.small + 0.5 }

  // ---- go to folder
  Glass {
    id: goBox
    visible: false
    anchors.centerIn: parent
    width: 460; height: 92
    radius: 16; fill: Theme.popover
    Txt { x: 16; y: 12; text: "Go to Folder"; font.weight: Font.Bold }
    Rectangle {
      x: 16; y: 40; width: parent.width - 32; height: 32; radius: 8; color: Theme.field; border.color: Theme.accent
      TextInput {
        id: goField
        clip: true   // long text scrolls inside the field, never spills out
        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize
        Keys.onEscapePressed: { goBox.visible = false; content.forceActiveFocus() }
        Keys.onReturnPressed: { const p = text.replace(/^~/, app.home).replace(/\/+$/, "") || "/"; goBox.visible = false; win.go(p); content.forceActiveFocus() }
      }
    }
  }

  // ---- menus (right click)
  Item {
    id: menu
    anchors.fill: parent
    visible: false
    z: 50
    property var target: null
    property var items: []
    property bool chooser: false
    property point at: Qt.point(0, 0)   // where it opens, in the window
    // A click outside the menu closes it; clicks inside belong to the menu.
    // Closed a moment later, so the handlers under it (that see the same click) still find it open.
    property int stamp: 0
    function close() { const t = ++stamp; Qt.callLater(() => { if (t === stamp) visible = false }) }
    function outside(ev) { const p = panel.mapFromItem(menu, ev.position.x, ev.position.y); return !panel.contains(p) }
    TapHandler { onTapped: ev => { if (menu.outside(ev)) menu.close() } }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => { if (menu.outside(ev)) menu.close() } }
    function show(x, y, f) {
      stamp++
      target = f
      chooser = false
      const p = content.mapToItem(menu, x, y)
      at = Qt.point(p.x, p.y)
      items = (f ? itemMenu(f) : folderMenu()).filter(i => i)
      visible = true
      if (f && !f.dir) openWith.load(f.path)
    }
    function showItems(item, x, y, list) {
      stamp++
      target = null
      chooser = false
      const p = item.mapToItem(menu, x, y)
      at = Qt.point(p.x, p.y)
      items = list
      visible = true
    }
    function folderMenu() {
      return [
        { text: "New Folder", keys: "Ctrl Shift N", action: () => win.newFolder() },
        { text: "New Text File", action: () => win.sh(win.freeName + "t=$(free " + win.q(win.path) + " Untitled.txt); : >> \"$t\"") },
        { separator: true },
        { text: "Paste", keys: "Ctrl V", enabled: app.clip.length > 0, action: () => win.paste() },
        { text: "Select All", keys: "Ctrl A", action: () => win.selectAll() },
        { separator: true },
        { text: win.view === "icons" ? "View as List" : "View as Icons", action: () => win.view = win.view === "icons" ? "list" : "icons" },
        { text: win.hidden ? "Hide Hidden Files" : "Show Hidden Files", keys: "Ctrl H", action: () => win.hidden = !win.hidden },
        { separator: true },
        { text: "Open in Terminal", action: () => Quickshell.execDetached(["ghostty", "--working-directory=" + win.path]) }
      ]
    }
    function itemMenu(f) {
      const many = win.selection.length > 1
      if (win.inTrash) return [
        { text: "Put Back", action: () => win.sh("for f in " + win.selection.map(win.q).join(" ") + "; do gio trash --restore \"trash:///$(basename \"$f\")\"; done") },
        { text: "Delete Immediately", action: () => win.trash() }
      ]
      return [
        { text: "Open", action: () => win.selection.forEach(p => win.openItem(p, p === f.path ? f.dir : win.isDir(p))) },
        f.dir ? { text: "Open in New Window", action: () => app.openWindow(f.path) } : { text: "Open With…", submenu: true },
        { text: "Share…", enabled: !win.selection.some(p => p === f.path && f.dir), action: () => Quickshell.execDetached(["memora-shell", "share"].concat(win.selection)) },
        { separator: true },
        { text: "Get Info", keys: "Ctrl I", action: () => info.show(f.path) },
        f.dir && !many ? { text: "Colour & Symbol…", action: () => win.styling = f.path } : null,
        { separator: true },
        { text: "Rename", keys: "F2", enabled: !many, action: () => win.renaming = f.path },
        { text: "Copy", keys: "Ctrl C", action: () => win.copy(false) },
        { text: "Cut", keys: "Ctrl X", action: () => win.copy(true) },
        { text: "Duplicate", action: () => win.sh(win.freeName + "for f in " + win.selection.map(win.q).join(" ") + "; do cp -a -- \"$f\" \"$(free \"$(dirname -- \"$f\")\" \"$(basename -- \"$f\")\")\"; done") },
        // Archives (memora-archive) does the work: a zip at once, or the choices (7z, RAR, a password, parts).
        { text: "Compress", action: () => Quickshell.execDetached([Theme.share + "/bin/memora-archive-tool", "create", win.path + "/" + (many ? "Archive" : f.name) + ".zip", "zip", "5"].concat(win.selection)) },
        { text: "Compress…", action: () => Quickshell.execDetached(["memora-archive", "--compress"].concat(win.selection)) },
        win.selection.every(p => win.kindOf(p.split("/").pop(), false) === "archive" && !win.isDir(p))
          ? { text: "Extract Here", action: () => win.selection.forEach(p => Quickshell.execDetached([Theme.share + "/bin/memora-archive-tool", "extract", p, win.path])) } : null,
        { separator: true },
        { text: "Copy Path", action: () => Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" | wl-copy", "_", win.selection.join("\n")]) },
        { text: "Ask Memora AI About This", action: () => Quickshell.execDetached(["memora-ai", "window", "Look at " + f.path + " and tell me briefly what it is."]) },
        { separator: true },
        { text: "Move to Trash", keys: "Delete", action: () => win.trash() }
      ]
    }

    // The menu is a little window of its own above Files, as on a Mac: the
    // compositor frosts what is under it (Files itself included), which it
    // can't do for anything drawn inside the window. It also keeps it on screen.
    PopupWindow {
      id: menuPop
      visible: menu.visible
      anchor.window: win
      anchor.rect.x: menu.at.x; anchor.rect.y: menu.at.y
      anchor.adjustment: PopupAdjustment.All
      implicitWidth: panel.width; implicitHeight: panel.height
      color: "transparent"

    Glass {
      id: panel
      width: menu.chooser ? 280 : 250
      height: (menu.chooser ? chooserCol.implicitHeight : itemsCol.implicitHeight) + 12
      radius: 12
      fill: Theme.menuGlass
      scale: menu.visible ? 1 : 0.92
      opacity: menu.visible ? 1 : 0
      transformOrigin: Item.TopLeft
      Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: Theme.fast } }
      TapHandler {}

      Column {
        id: itemsCol
        visible: !menu.chooser
        x: 6; y: 6; width: parent.width - 12
        Repeater {
          model: menu.items
          delegate: Item {
            required property var modelData
            width: itemsCol.width; height: modelData.separator ? 11 : 26
            readonly property bool on: modelData.enabled !== false
            Rectangle { visible: !!parent.modelData.separator; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.separator }
            Rectangle { visible: !parent.modelData.separator; anchors.fill: parent; radius: 6; color: mh.hovered && parent.on ? Theme.accent : "transparent" }
            Txt { visible: !parent.modelData.separator; x: 10; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.text || ""; color: mh.hovered && parent.on ? "#fff" : (parent.on ? Theme.text : Theme.textFaint) }
            Txt { visible: !!parent.modelData.keys; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: parent.modelData.keys || ""; color: mh.hovered ? Qt.rgba(1, 1, 1, 0.8) : Theme.textDim; font.pixelSize: Theme.small }
            Sym { visible: !!parent.modelData.submenu; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } name: "chevron"; width: 10; height: 10; color: mh.hovered ? "#fff" : Theme.textDim }
            HoverHandler { id: mh }
            TapHandler {
              enabled: !parent.modelData.separator && parent.on
              onTapped: {
                if (parent.modelData.submenu) { menu.chooser = true; return }
                const run = parent.modelData.action; menu.close(); if (run) Qt.callLater(run)
              }
            }
          }
        }
      }

      // Open With: the apps that can open this kind of file, the default first.
      // One click opens it; the switch makes that app the default.
      Column {
        id: chooserCol
        visible: menu.chooser
        x: 6; y: 6; width: parent.width - 12
        spacing: 2
        Item {
          width: parent.width; height: 28
          Sym { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "chevron"; rotation: 180; width: 10; height: 10; color: Theme.textDim; TapHandler { onTapped: menu.chooser = false } }
          Txt { x: 24; anchors.verticalCenter: parent.verticalCenter; text: "Open With"; font.weight: Font.Bold }
        }
        Repeater {
          model: openWith.apps
          delegate: Rectangle {
            required property var modelData
            width: chooserCol.width; height: 36; radius: 8
            color: ah.hovered ? Theme.accent : "transparent"
            AppIcon { id: oi; x: 8; anchors.verticalCenter: parent.verticalCenter; width: 24; height: 24; appId: modelData.id }
            Txt { anchors { left: oi.right; leftMargin: 10; verticalCenter: parent.verticalCenter; right: dflt.left; rightMargin: 6 } text: modelData.name; color: ah.hovered ? "#fff" : Theme.text }
            Txt { id: dflt; visible: modelData.isDefault; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: "Default"; color: ah.hovered ? Qt.rgba(1, 1, 1, 0.8) : Theme.textDim; font.pixelSize: Theme.small - 1 }
            HoverHandler { id: ah }
            TapHandler { onTapped: { menu.close(); Quickshell.execDetached(["gio", "launch", modelData.file, menu.target.path]); if (openWith.always) Quickshell.execDetached(["gio", "mime", openWith.mime, modelData.id + ".desktop"]) } }
          }
        }
        Txt { visible: openWith.apps.length === 0; x: 10; height: 30; verticalAlignment: Text.AlignVCenter; text: "No app opens this kind of file"; color: Theme.textDim }
        Rectangle { width: parent.width - 16; x: 8; height: 1; color: Theme.separator }
        Item {
          width: parent.width; height: 32
          Txt { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "Always open this kind of file here"; font.pixelSize: Theme.small }
          Rectangle {
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            width: 32; height: 18; radius: 9
            color: openWith.always ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
            Rectangle { width: 14; height: 14; radius: 7; y: 2; x: openWith.always ? 16 : 2; color: "#fff"; Behavior on x { NumberAnimation { duration: Theme.fast } } }
            TapHandler { onTapped: openWith.always = !openWith.always }
          }
        }
      }
    }
    }

    QtObject {
      id: openWith
      property var apps: []
      property string mime: ""
      property bool always: false
      property Process proc: Process {
        stdout: StdioCollector {
          onStreamFinished: {
            const lines = text.split("\n")
            openWith.mime = (lines[0] || "").trim()
            const dflt = (lines[1] || "").trim()
            const ids = lines.slice(2).map(l => l.trim()).filter(l => l.endsWith(".desktop"))
            const seen = {}
            openWith.apps = [dflt].concat(ids).filter(i => i && !seen[i] && (seen[i] = true)).map(f => {
              const id = f.replace(/\.desktop$/, "")
              const e = Apps.entry(id)
              return { id: id, file: f, entry: e, name: Apps.names[id] !== undefined ? Apps.names[id] : (e ? e.name : id), isDefault: f === dflt }
            }).filter(a => a.entry && !a.entry.noDisplay)
          }
        }
      }
      function load(p) {
        always = false; apps = []
        proc.command = ["bash", "-c", "t=$(gio info -a standard::content-type \"$1\" 2>/dev/null | awk '/content-type/ {print $2}'); [ -n \"$t\" ] || t=$(file -b --mime-type \"$1\"); echo \"$t\"; xdg-mime query default \"$t\"; gio mime \"$t\" 2>/dev/null | sed -n '/Registered applications:/,/Recommended/p' | grep '\\.desktop'", "_", p]
        proc.running = true
      }
    }
  }

  // ---- small pieces
  // What a drag of files looks like: the icon (or the picture, small), up to
  // three stacked, with how many there are.
  component DragStack: Item {
    id: ds
    property var icons: []
    property int count: 0
    width: 84; height: 84
    Repeater {
      model: ds.icons.slice(0, 3).reverse()        // the first one on top
      delegate: Image {
        required property var modelData
        required property int index
        readonly property int depth: Math.min(ds.icons.length, 3) - 1 - index
        x: 10 + depth * 4; y: 10 - depth * 3
        width: 64; height: 64
        rotation: depth === 1 ? -7 : (depth === 2 ? 7 : 0)
        source: modelData
        sourceSize: Qt.size(128, 128)
        fillMode: Image.PreserveAspectFit
        smooth: true; mipmap: true
      }
    }
    Rectangle {
      visible: ds.count > 1
      anchors { right: parent.right; top: parent.top; rightMargin: 2; topMargin: 2 }
      width: Math.max(22, badge.implicitWidth + 12); height: 22; radius: 11; color: Theme.red
      Txt { id: badge; anchors.centerIn: parent; text: ds.count; color: "#ffffff"; font.pixelSize: Theme.small - 1; font.weight: Font.Bold }
    }
  }
  // The same, out of sight, for the system drag's picture (grabToImage).
  DragStack { id: dragPic; x: -1000; y: -1000; icons: ghost.icons; count: ghost.count }

  component ToolBtn: Rectangle {
    id: tb
    property string sym
    property bool flip: false
    property string tip
    signal clicked()
    width: 30; height: 28; radius: 7
    color: tbh.hovered && enabled ? Theme.hover : "transparent"
    opacity: enabled ? 1 : 0.35
    Sym { anchors.centerIn: parent; name: tb.sym; rotation: tb.flip ? 180 : 0; width: 13; height: 13 }
    HoverHandler { id: tbh }
    TapHandler { onTapped: if (tb.enabled) tb.clicked() }
    Tip { text: tb.tip }
  }
  component Kbd: Rectangle {
    id: kb
    property string text
    signal clicked()
    width: kt.implicitWidth + 22; height: 28; radius: 8
    color: kh.hovered ? Theme.pressed : Theme.hover
    border.color: Theme.separator
    Txt { id: kt; anchors.centerIn: parent; text: kb.text; font.pixelSize: Theme.small + 0.5 }
    HoverHandler { id: kh }
    TapHandler { onTapped: kb.clicked() }
  }
  component GridGlyph: Grid { columns: 2; spacing: 2; Repeater { model: 4; Rectangle { width: 5; height: 5; radius: 1.5; color: win.view === "icons" ? Theme.text : Theme.textDim } } }
  component ListGlyph: Column { spacing: 2; Repeater { model: 3; Rectangle { width: 12; height: 2.4; radius: 1.2; color: win.view === "list" ? Theme.text : Theme.textDim } } }
  component RenameField: Rectangle {
    id: rf
    property string target
    height: 22; radius: 5
    color: Theme.dark ? "#2a2a2e" : "#ffffff"
    border.color: Theme.accent
    onVisibleChanged: if (visible) { ri.text = target.split("/").pop(); ri.forceActiveFocus(); const dot = ri.text.lastIndexOf("."); ri.select(0, dot > 0 ? dot : ri.text.length) }
    TextInput {
      id: ri
      anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
      verticalAlignment: TextInput.AlignVCenter
      horizontalAlignment: TextInput.AlignHCenter
      color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small
      clip: true
      selectByMouse: true
      Keys.onReturnPressed: { win.rename(rf.target, text); content.forceActiveFocus() }
      Keys.onEscapePressed: { win.renaming = ""; content.forceActiveFocus() }
      onActiveFocusChanged: if (!activeFocus && win.renaming === rf.target) win.rename(rf.target, text)
    }
  }
  ConfirmSheet { id: confirm }

  // Colour & Symbol for a folder, over the window.
  Rectangle {
    anchors.fill: parent
    visible: win.styling !== ""
    color: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.18)
    z: 50
    TapHandler { onTapped: win.styling = "" }
    FolderStyler {
      anchors.centerIn: parent
      path: win.styling
      onDone: win.styling = ""
      TapHandler {}   // taps on the card stay on it
    }
    onVisibleChanged: if (visible) forceActiveFocus()
    Keys.onEscapePressed: win.styling = ""
  }

  // An encrypted drive's passphrase, asked once; "Remember" keeps it in the
  // Keyring and opens the drive at every login.
  Item {
    id: unlockSheet
    anchors.fill: parent
    visible: false
    z: 60
    property var d: ({})
    property bool remember: true
    property string error: ""
    function ask(drive, pin) { d = drive; error = ""; remember = true; pass.text = ""; visible = true; pass.forceActiveFocus() }
    function submit() {
      if (!pass.text) return
      error = ""
      const pw = pass.text
      win.driveRun(["unlock", d.id].concat(remember ? ["--remember"] : []), where => { unlockSheet.visible = false; if (where) win.go(where) }, pw)
      pass.text = ""
    }
    Connections { target: win; function onDriveErrorChanged() { if (unlockSheet.visible && win.driveError) { unlockSheet.error = win.driveError; win.driveError = "" } } }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35); TapHandler { onTapped: unlockSheet.visible = false } }
    Rectangle {
      anchors.centerIn: parent
      width: 380; height: col.implicitHeight + 40; radius: 16
      color: Theme.dark ? "#2a2a2e" : "#f6f6f8"; border.color: Theme.separator
      Column {
        id: col
        x: 20; y: 20; width: parent.width - 40
        spacing: 12
        Txt { text: "Unlock “" + (unlockSheet.d.name || "") + "”"; font.weight: Font.Bold; font.pixelSize: Theme.large }
        Txt { width: parent.width; text: "This drive is encrypted. Type its passphrase to open it."; color: Theme.textDim; wrapMode: Text.Wrap; font.pixelSize: Theme.small }
        Rectangle {
          width: parent.width; height: 32; radius: 8; color: Theme.field
          border.color: pass.activeFocus ? Theme.accent : Theme.separator; border.width: pass.activeFocus ? 2 : 1
          TextInput {
            id: pass
            clip: true   // long text scrolls inside the field, never spills out
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password; passwordCharacter: "•"
            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize
            Keys.onReturnPressed: unlockSheet.submit()
            Keys.onEscapePressed: unlockSheet.visible = false
          }
        }
        Row {
          spacing: 8
          Rectangle {
            width: 18; height: 18; radius: 5; anchors.verticalCenter: parent.verticalCenter
            color: unlockSheet.remember ? Theme.accent : "transparent"; border.color: unlockSheet.remember ? Theme.accent : Theme.separator; border.width: 1.5
            Sym { visible: unlockSheet.remember; anchors.centerIn: parent; name: "check"; width: 11; height: 11; color: "#ffffff" }
          }
          Txt { text: "Remember and open at login"; anchors.verticalCenter: parent.verticalCenter }
          TapHandler { onTapped: unlockSheet.remember = !unlockSheet.remember }
        }
        Txt { visible: unlockSheet.error !== ""; text: unlockSheet.error; color: Theme.red; font.pixelSize: Theme.small }
        Row {
          anchors.right: parent.right
          spacing: 8
          Rectangle {
            width: ct.implicitWidth + 28; height: 30; radius: 8; color: ch.hovered ? Theme.pressed : Theme.hover
            Txt { id: ct; anchors.centerIn: parent; text: "Cancel" }
            HoverHandler { id: ch } TapHandler { onTapped: unlockSheet.visible = false }
          }
          Rectangle {
            width: ut.implicitWidth + 28; height: 30; radius: 8; color: Theme.accent; opacity: pass.text ? 1 : 0.5
            Txt { id: ut; anchors.centerIn: parent; text: "Unlock"; color: "#ffffff"; font.weight: Font.Bold }
            TapHandler { onTapped: unlockSheet.submit() }
          }
        }
      }
    }
  }
}
