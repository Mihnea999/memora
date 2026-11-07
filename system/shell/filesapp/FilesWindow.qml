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
  minimumSize: Qt.size(640, 400)
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
    path = p; selected = ({}); renaming = ""; search.text = ""; query = ""
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
  function select(p, mods) {
    const s = Object.assign({}, selected)
    if (mods & Qt.ControlModifier) { if (s[p]) delete s[p]; else s[p] = true }
    else if (mods & Qt.ShiftModifier && lastClicked) {
      const names = [], m = folder
      for (let i = 0; i < m.count; i++) names.push(m.get(i, "filePath"))
      const a = names.indexOf(lastClicked), b = names.indexOf(p)
      if (a >= 0 && b >= 0) for (let i = Math.min(a, b); i <= Math.max(a, b); i++) s[names[i]] = true
    } else { for (const k in s) delete s[k]; s[p] = true }
    selected = s; lastClicked = p
  }
  function selectAll() { const s = {}; for (let i = 0; i < folder.count; i++) s[folder.get(i, "filePath")] = true; selected = s }
  function newFolder() {
    let n = "untitled folder", i = 2
    const names = {}; for (let j = 0; j < folder.count; j++) names[folder.get(j, "fileName")] = true
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
        onAccept: () => { sh("rm -rf -- " + items.map(q).join(" ")); selected = ({}) }
      })
      return
    }
    sh("gio trash -- " + items.map(q).join(" "))
    selected = ({})
  }
  function emptyTrash() {
    confirm.ask({
      title: "Empty the Trash?", message: "Everything in the Trash will be deleted. You can't undo this action.", action: "Empty Trash",
      onAccept: () => sh("gio trash --empty")
    })
  }
  function copy(cut) { app.clip = selection.slice(); app.clipCut = cut }
  function paste() {
    if (!app.clip.length) return
    sh((app.clipCut ? "mv -n -- " : "cp -an -- ") + app.clip.map(q).join(" ") + " " + q(path + "/"))
    if (app.clipCut) app.clip = []
  }
  function rename(p, name) {
    renaming = ""
    if (!name || name === p.split("/").pop() || name.indexOf("/") >= 0) return
    const to = p.substring(0, p.lastIndexOf("/") + 1) + name
    sh("mv -n -- " + q(p) + " " + q(to), () => selected = ({ [to]: true }))
  }
  function moveInto(dir) {
    if (!dragging.length || dragging.indexOf(dir) >= 0) return
    sh((dir === trashDir ? "gio trash -- " : "mv -n -- ") + dragging.map(q).join(" ") + (dir === trashDir ? "" : " " + q(dir + "/")))
  }
  property var dragging: []

  Component { id: runner; Process {
    property string cmd
    signal done()
    command: ["bash", "-c", cmd]
    running: true
    onExited: { done(); destroy() }
  } }

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
  onPathChanged: df.running = true

  // ---- icons for files
  readonly property var kinds: ({
    png: "image", jpg: "image", jpeg: "image", webp: "image", gif: "image", bmp: "image", svg: "image", heic: "image",
    mp4: "video", mkv: "video", webm: "video", mov: "video", avi: "video",
    mp3: "audio", flac: "audio", ogg: "audio", wav: "audio", m4a: "audio", opus: "audio",
    pdf: "pdf", txt: "text", md: "text", log: "text", json: "code", js: "code", ts: "code", py: "code", sh: "code", rs: "code", go: "code", c: "code", cpp: "code", h: "code", qml: "code", lua: "code", html: "code", css: "code",
    zip: "archive", tar: "archive", gz: "archive", xz: "archive", zst: "archive", "7z": "archive", rar: "archive",
    iso: "disc", img: "disc", deb: "package", AppImage: "package", doc: "document", docx: "document", odt: "document",
    xls: "sheet", xlsx: "sheet", ods: "sheet", ppt: "slides", pptx: "slides", odp: "slides"
  })
  function kindOf(name, isDir) {
    if (isDir) return "folder"
    const ext = name.indexOf(".") > 0 ? name.split(".").pop() : ""
    return kinds[ext] || kinds[ext.toLowerCase()] || "file"
  }
  function iconFor(p, name, isDir) {
    if (isDir) {
      const special = { Desktop: "user-desktop", Documents: "folder-documents", Downloads: "folder-download", Music: "folder-music",
        Pictures: "folder-pictures", Videos: "folder-videos", Projects: "folder-projects", Public: "folder-publicshare", Templates: "folder-templates" }
      const parent = p.substring(0, p.lastIndexOf("/"))
      return Quickshell.iconPath(parent === app.home && special[name] ? special[name] : "folder")
    }
    const k = kindOf(name, false)
    const map = { video: "video-x-generic", audio: "audio-x-generic", pdf: "application-pdf", text: "text-x-generic", code: "text-x-script",
      archive: "package-x-generic", disc: "media-optical", package: "package-x-generic", document: "x-office-document", sheet: "x-office-spreadsheet",
      slides: "x-office-presentation", file: "text-x-generic" }
    return Quickshell.iconPath(map[k] || "text-x-generic", "text-x-generic")
  }
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
    anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 8 }
    radius: 12
    color: Theme.sidebar
    border.color: Theme.separator
    WindowControls { x: 14; y: 14; window: win; onCloseRequested: win.closeMe() }
    Item { anchors { left: parent.left; right: parent.right; top: parent.top } height: 40; DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() } }

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
      }
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

  // ---- toolbar
  Item {
    id: tools
    anchors { left: side.right; right: parent.right; top: parent.top }
    height: 52
    DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
    Row {
      x: 14; anchors.verticalCenter: parent.verticalCenter
      spacing: 2
      ToolBtn { sym: "chevron"; flip: true; enabled: win.back.length > 0; onClicked: win.goBack() }
      ToolBtn { sym: "chevron"; enabled: win.fwd.length > 0; onClicked: win.goForward() }
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
          Item { width: 30; height: 24; GridGlyph { anchors.centerIn: parent } TapHandler { onTapped: win.view = "icons" } }
          Item { width: 30; height: 24; ListGlyph { anchors.centerIn: parent } TapHandler { onTapped: win.view = "list" } }
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
    anchors { left: side.right; right: parent.right; top: tools.bottom; bottom: status.top; leftMargin: 6 }
    focus: true
    // Not clipped, so a dragged file stays visible over the sidebar.
    clip: false

    // The current list: the folder, or search results.
    readonly property bool searching: win.query.length >= 2
    readonly property int n: searching ? win.found.length : folder.count
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
      else if (ev.key === Qt.Key_Return && win.selection.length) { win.selection.forEach(p => { const i = folder.indexOf("file://" + p); win.openItem(p, i >= 0 && folder.get(i, "fileIsDir")) }) }
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
    function hitAt(x, y) {
      return win.view === "icons" ? grid.itemAt(x - grid.x + grid.contentX, y - grid.y + grid.contentY)
                                  : list.itemAt(x - list.x + list.contentX, y - list.parent.y - list.y + list.contentY)
    }
    TapHandler { onTapped: ev => { if (!content.hitAt(ev.position.x, ev.position.y)) win.selected = ({}); content.forceActiveFocus() } }
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
          wrapMode: Text.WrapAnywhere
          maximumLineCount: 2
          elide: Text.ElideMiddle
          color: cell.sel ? "#ffffff" : Theme.text
          font.family: Theme.font; font.pixelSize: Theme.small
        }
        RenameField { visible: win.renaming === cell.f.path; anchors { horizontalCenter: parent.horizontalCenter; top: ib.bottom; topMargin: 2 } width: cell.width - 8; target: cell.f.path }

        TapHandler { id: tap; onTapped: ev => { win.select(cell.f.path, ev.modifiers); content.forceActiveFocus() }
                     onDoubleTapped: win.openItem(cell.f.path, cell.f.dir) }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => { if (!cell.sel) win.select(cell.f.path, 0); const p = cell.mapToItem(content, ev.position.x, ev.position.y); menu.show(p.x, p.y, cell.f) } }
        DragHandler {
          id: dh
          target: null
          grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
          onActiveChanged: {
            if (active) { if (!cell.sel) win.select(cell.f.path, 0); win.dragging = win.selection.slice(); ghost.icon = thumb.source; ghost.count = win.dragging.length }
            else ghost.release()
          }
          onCentroidChanged: if (active) { const p = cell.mapToItem(content, centroid.position.x, centroid.position.y); ghost.x = p.x - 32; ghost.y = p.y - 32; ghost.track(p) }
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
          TapHandler { onTapped: ev => { win.select(lrow.f.path, ev.modifiers); content.forceActiveFocus() } onDoubleTapped: win.openItem(lrow.f.path, lrow.f.dir) }
          property bool hot: false
          function dropHere() { if (lrow.f.dir) win.moveInto(lrow.f.path) }
          border.color: hot && f.dir ? Theme.accent : "transparent"
          border.width: 2
          DragHandler {
            target: null
            grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
            onActiveChanged: {
              if (active) { if (!lrow.sel) win.select(lrow.f.path, 0); win.dragging = win.selection.slice(); ghost.icon = win.iconFor(lrow.f.path, lrow.f.name, lrow.f.dir); ghost.count = win.dragging.length }
              else ghost.release()
            }
            onCentroidChanged: if (active) { const p = lrow.mapToItem(content, centroid.position.x, centroid.position.y); ghost.x = p.x - 32; ghost.y = p.y - 32; ghost.track(p) }
          }
          TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => { if (!lrow.sel) win.select(lrow.f.path, 0); const p = lrow.mapToItem(content, ev.position.x, ev.position.y); menu.show(p.x, p.y, lrow.f) } }
        }
      }
    }

    // What you are dragging.
    Item {
      id: ghost
      visible: win.dragging.length > 0
      width: 64; height: 64
      property url icon
      property int count: 0
      property var over: null
      // Let go: into the folder under the pointer, or onto a sidebar place.
      function release() {
        if (ghost.over) ghost.over.dropHere()
        else ghost.Drag.drop()
        if (ghost.over) ghost.over.hot = false
        win.dragging = []; ghost.over = null
      }
      function track(p) {
        // Highlight the folder under the pointer (icons or list).
        const c = win.view === "icons" ? grid.itemAt(p.x - grid.x + grid.contentX, p.y - grid.y + grid.contentY)
                                       : list.itemAt(p.x - list.x + list.contentX, p.y - list.parent.y - list.y + list.contentY)
        if (over && over !== c) over.hot = false
        over = c && c.f && c.f.dir && win.dragging.indexOf(c.f.path) < 0 ? c : null
        if (over) over.hot = true
      }
      Image { anchors.fill: parent; source: ghost.icon; sourceSize: Qt.size(128, 128); opacity: 0.85 }
      Rectangle {
        visible: ghost.count > 1
        anchors { right: parent.right; top: parent.top }
        width: 22; height: 22; radius: 11; color: Theme.red
        Txt { anchors.centerIn: parent; text: ghost.count; color: "#ffffff"; font.pixelSize: Theme.small - 1; font.weight: Font.Bold }
      }
      Drag.active: visible
      Drag.hotSpot: Qt.point(32, 32)
    }
  }

  // ---- path and status
  Item {
    id: status
    anchors { left: side.right; right: parent.right; bottom: parent.bottom; leftMargin: 6 }
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
    radius: 18; fill: Theme.glassStrong; shadowSize: 40
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
    radius: 16; fill: Theme.glassStrong
    Txt { x: 16; y: 12; text: "Go to Folder"; font.weight: Font.Bold }
    Rectangle {
      x: 16; y: 40; width: parent.width - 32; height: 32; radius: 8; color: Theme.field; border.color: Theme.accent
      TextInput {
        id: goField
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
    // A click outside the menu closes it; clicks inside belong to the menu.
    function outside(ev) { const p = panel.mapFromItem(menu, ev.position.x, ev.position.y); return !panel.contains(p) }
    TapHandler { onTapped: ev => { if (menu.outside(ev)) menu.visible = false } }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => { if (menu.outside(ev)) menu.visible = false } }
    function show(x, y, f) {
      target = f
      chooser = false
      const p = content.mapToItem(menu, x, y)
      panel.x = Math.min(p.x, menu.width - panel.width - 10)
      panel.y = Math.min(p.y, menu.height - 300)
      items = f ? itemMenu(f) : folderMenu()
      visible = true
      if (f && !f.dir) openWith.load(f.path)
    }
    function folderMenu() {
      return [
        { text: "New Folder", keys: "Ctrl Shift N", action: () => win.newFolder() },
        { text: "New Text File", action: () => win.sh("touch " + win.q(win.path + "/Untitled.txt")) },
        { separator: true },
        { text: "Paste", keys: "Ctrl V", enabled: app.clip.length > 0, action: () => win.paste() },
        { text: "Select All", keys: "Ctrl A", action: () => win.selectAll() },
        { separator: true },
        { text: win.view === "icons" ? "View as List" : "View as Icons", action: () => win.view = win.view === "icons" ? "list" : "icons" },
        { text: win.hidden ? "Hide Hidden Files" : "Show Hidden Files", keys: "Ctrl H", action: () => win.hidden = !win.hidden },
        { separator: true },
        { text: "Open in Terminal", action: () => Quickshell.execDetached(["ptyxis", "--new-window", "-d", win.path]) }
      ]
    }
    function itemMenu(f) {
      const many = win.selection.length > 1
      if (win.inTrash) return [
        { text: "Put Back", action: () => win.sh("for f in " + win.selection.map(win.q).join(" ") + "; do gio trash --restore \"trash:///$(basename \"$f\")\"; done") },
        { text: "Delete Immediately", action: () => win.trash() }
      ]
      return [
        { text: "Open", action: () => win.selection.forEach(p => win.openItem(p, f.dir && p === f.path)) },
        f.dir ? { text: "Open in New Window", action: () => app.openWindow(f.path) } : { text: "Open With…", submenu: true },
        { separator: true },
        { text: "Get Info", keys: "Ctrl I", action: () => info.show(f.path) },
        { separator: true },
        { text: "Rename", keys: "F2", enabled: !many, action: () => win.renaming = f.path },
        { text: "Copy", keys: "Ctrl C", action: () => win.copy(false) },
        { text: "Cut", keys: "Ctrl X", action: () => win.copy(true) },
        { text: "Duplicate", action: () => win.sh(win.selection.map(p => "cp -an " + win.q(p) + " " + win.q(p.replace(/(\.[^./]+)?$/, " copy$1"))).join("; ")) },
        { text: "Compress", action: () => win.sh("cd " + win.q(win.path) + " && zip -rq " + win.q((many ? "Archive" : f.name) + ".zip") + " " + win.selection.map(p => win.q(p.split("/").pop())).join(" ")) },
        { separator: true },
        { text: "Copy Path", action: () => Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" | wl-copy", "_", win.selection.join("\n")]) },
        { text: "Ask Memora AI About This", action: () => Quickshell.execDetached(["memora-ai", "window", "Look at " + f.path + " and tell me briefly what it is."]) },
        { separator: true },
        { text: "Move to Trash", keys: "Delete", action: () => win.trash() }
      ]
    }

    Glass {
      id: panel
      width: menu.chooser ? 280 : 250
      height: (menu.chooser ? chooserCol.implicitHeight : itemsCol.implicitHeight) + 12
      radius: 12
      fill: Theme.glassStrong
      shadowSize: 24
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
                const run = parent.modelData.action; menu.visible = false; if (run) Qt.callLater(run)
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
            TapHandler { onTapped: { menu.visible = false; Quickshell.execDetached(["gio", "launch", modelData.file, menu.target.path]); if (openWith.always) Quickshell.execDetached(["gio", "mime", openWith.mime, modelData.id + ".desktop"]) } }
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
  component ToolBtn: Rectangle {
    id: tb
    property string sym
    property bool flip: false
    signal clicked()
    width: 30; height: 28; radius: 7
    color: tbh.hovered && enabled ? Theme.hover : "transparent"
    opacity: enabled ? 1 : 0.35
    Sym { anchors.centerIn: parent; name: tb.sym; rotation: tb.flip ? 180 : 0; width: 13; height: 13 }
    HoverHandler { id: tbh }
    TapHandler { onTapped: if (tb.enabled) tb.clicked() }
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
}
