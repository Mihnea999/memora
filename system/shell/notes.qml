//@ pragma UseQApplication
//@ pragma AppId memora-notes
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui

// Notes: folders, a list of notes, and the note itself. Everything is saved as
// you type, in ~/.local/share/memora/notes.json (a copy is kept next to it).
ShellRoot {
  id: app
  readonly property string store: Quickshell.env("HOME") + "/.local/share/memora/notes.json"
  property var notes: []          // { id, folder, html, text, created, modified, pinned, deleted }
  property var folders: ["Notes"]
  property string folder: "*"      // "*" all, "~" recently deleted, or a folder name
  property string current: ""
  property string query: ""
  property bool showFolders: true
  property real textSize: 15
  property bool loaded: false

  // ---- storage
  FileView {
    id: file
    path: app.store
    printErrors: false
    onLoaded: {
      try { const j = JSON.parse(text()); app.notes = j.notes || []; app.folders = j.folders && j.folders.length ? j.folders : ["Notes"] } catch (e) {}
      app.loaded = true
      if (!app.notes.length) app.welcome()
      app.pickFirst()
    }
    onLoadFailed: { app.loaded = true; app.welcome(); app.pickFirst() }
  }
  FileView { id: backup; path: app.store + ".bak"; printErrors: false }
  Timer { id: saveLater; interval: 600; onTriggered: app.saveNow() }
  function saveNow() {
    const t = JSON.stringify({ version: 1, folders: folders, notes: notes })
    file.setText(t); backup.setText(t)
  }
  function changed() { notes = notes.slice(); saveLater.restart() }
  Component.onDestruction: saveNow()

  function welcome() {
    notes = [{ id: "n" + Date.now(), folder: "Notes", pinned: true, deleted: false, created: Date.now(), modified: Date.now(),
      text: "Welcome to Notes\nEverything you write is saved as you type.\n☐ Make a checklist with the button above\n☑ Pin a note to keep it on top",
      html: "<h1>Welcome to Notes</h1><p>Everything you write is saved as you type.</p><p>☐ Make a checklist with the button above</p><p>☑ Pin a note to keep it on top</p><p><b>Bold</b>, <i>italic</i> and <s>strikethrough</s> are in the Format menu.</p>" }]
    saveLater.restart()
  }

  // ---- what is shown
  readonly property var visibleNotes: {
    const q = query.toLowerCase()
    const list = notes.filter(n => folder === "~" ? n.deleted : (!n.deleted && (folder === "*" || n.folder === folder)))
      .filter(n => !q || n.text.toLowerCase().indexOf(q) >= 0)
    list.sort((a, b) => (b.pinned - a.pinned) || (b.modified - a.modified))
    return list
  }
  readonly property var note: notes.find(n => n.id === current) || null
  function pickFirst() { current = visibleNotes.length ? visibleNotes[0].id : "" }
  onFolderChanged: pickFirst()
  function countIn(f) { return notes.filter(n => f === "~" ? n.deleted : (!n.deleted && (f === "*" || n.folder === f))).length }

  function group(n) {
    if (n.pinned && !n.deleted) return "Pinned"
    const d = new Date(n.modified), now = new Date()
    if (d.toDateString() === now.toDateString()) return "Today"
    const days = (now - d) / 86400000
    if (days < 7) return "Previous 7 Days"
    if (days < 30) return "Previous 30 Days"
    return Qt.formatDate(d, "MMMM yyyy")
  }
  function when(n) {
    const d = new Date(n.modified), now = new Date()
    if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm")
    if ((now - d) / 86400000 < 7) return Qt.formatDate(d, "dddd")
    return Qt.formatDate(d, "dd.MM.yyyy")
  }

  // ---- actions
  function newNote() {
    const f = folder === "*" || folder === "~" ? (folders[0] || "Notes") : folder
    if (folder === "~") folder = "*"
    const n = { id: "n" + Date.now(), folder: f, html: "", text: "", created: Date.now(), modified: Date.now(), pinned: false, deleted: false }
    notes = [n].concat(notes); current = n.id; query = ""
    saveLater.restart()
    Qt.callLater(() => editor.forceActiveFocus())
  }
  function deleteNote() {
    const n = note; if (!n) return
    const list = visibleNotes, i = list.indexOf(n)
    if (n.deleted) notes = notes.filter(x => x !== n)
    else { n.deleted = true; n.modified = Date.now(); changed() }
    const rest = visibleNotes
    current = rest.length ? rest[Math.min(i, rest.length - 1)].id : ""
    saveLater.restart()
  }
  function restoreNote() { if (note) { note.deleted = false; changed(); pickFirst() } }
  function togglePin() { if (note) { note.pinned = !note.pinned; changed() } }
  function newFolder() {
    let name = "New Folder", i = 2
    while (folders.indexOf(name) >= 0) name = "New Folder " + i++
    folders = folders.concat([name]); folder = name; renamingFolder = name
    saveLater.restart()
  }
  property string renamingFolder: ""
  function renameFolder(from, to) {
    renamingFolder = ""
    to = to.trim()
    if (!to || to === from || folders.indexOf(to) >= 0) return
    folders = folders.map(f => f === from ? to : f)
    notes.forEach(n => { if (n.folder === from) n.folder = to })
    if (folder === from) folder = to
    changed()
  }
  function deleteFolder(f) {
    if (folders.length < 2) return
    notes.forEach(n => { if (n.folder === f) { n.deleted = true; n.folder = folders.find(x => x !== f) } })
    folders = folders.filter(x => x !== f)
    if (folder === f) folder = "*"
    changed()
  }
  function exportNote() {
    if (!note) return
    const name = (note.text.split("\n")[0] || "Note").replace(/[\/\\:*?"<>|]/g, "").slice(0, 60).trim() || "Note"
    exporter.command = ["bash", "-c", "mkdir -p ~/Documents && printf '%s' \"$1\" > ~/Documents/\"$2\".txt && notify-send -a Notes 'Exported' \"Documents/$2.txt\"", "_", note.text, name]
    exporter.running = true
  }
  Process { id: exporter }

  // The editor writes back here.
  function editorChanged() {
    const n = note
    if (!n || app.loadingNote) return
    if (pendingStyle && !applying) {
      applying = true
      const t = plain(), s0 = lineStart(t, editor.cursorPosition), e0 = lineEnd(t, editor.cursorPosition)
      styleRange(s0, e0, pendingStyle)
      applying = false
    }
    const html = editor.text, text = app.plain()
    if (html === n.html) return
    n.html = html; n.text = text; n.modified = Date.now()
    changed()
  }
  property bool loadingNote: false
  property bool applying: false
  // Rich text separates paragraphs with U+2029; notes use plain newlines.
  function plain() { return editor.getText(0, editor.length).replace(/[\u2029\u2028]/g, "\n") }
  function lineStart(t, pos) { return Math.max(t.lastIndexOf("\n", pos - 1), -1) + 1 }
  function lineEnd(t, pos) { const e = t.indexOf("\n", pos); return e < 0 ? t.length : e }
  onCurrentChanged: loadNote()
  function loadNote() {
    if (typeof editor === "undefined" || !editor) return
    const n = notes.find(x => x.id === current)
    loadingNote = true
    editor.text = n ? n.html : ""
    loadingNote = false
    noteIn.restart()
  }

  // ---- formatting (on the selection, or the current line)
  property string pendingStyle: ""      // a line style chosen before typing the line
  function fontFor(kind, f) {
    if (kind === "title") { f.pixelSize = app.textSize * 1.75; f.bold = true }
    else if (kind === "heading") { f.pixelSize = app.textSize * 1.3; f.bold = true }
    else { f.pixelSize = app.textSize; f.bold = false; f.italic = false; f.strikeout = false }
    return f
  }
  function styleRange(a, b, kind) {
    if (b <= a) return
    const pos = editor.cursorPosition
    editor.select(a, b)
    editor.cursorSelection.font = fontFor(kind, editor.cursorSelection.font)
    editor.cursorPosition = pos
  }
  function bodyAtCursor() { editor.cursorSelection.font = fontFor("body", editor.cursorSelection.font) }
  function style(kind) {
    if (!note || note.deleted) return
    const sel = editor.cursorSelection
    if (editor.selectionStart === editor.selectionEnd && (kind === "title" || kind === "heading" || kind === "body")) {
      // No selection: the whole line the cursor is on (or the line about to be typed).
      const t = app.plain()
      const s = app.lineStart(t, editor.cursorPosition), e = app.lineEnd(t, editor.cursorPosition)
      if (e > s) styleRange(s, e, kind)
      else { pendingStyle = kind; sel.font = fontFor(kind, sel.font) }
      editorChanged()
      return
    }
    const f = sel.font
    if (kind === "bold") f.bold = !f.bold
    else if (kind === "italic") f.italic = !f.italic
    else if (kind === "strike") f.strikeout = !f.strikeout
    else if (kind === "title") { f.pixelSize = app.textSize * 1.75; f.bold = true }
    else if (kind === "heading") { f.pixelSize = app.textSize * 1.3; f.bold = true }
    else if (kind === "body") { f.pixelSize = app.textSize; f.bold = false; f.italic = false; f.strikeout = false }
    sel.font = f
    editorChanged()
  }
  function linePrefix(mark) {
    if (!note || note.deleted) return
    const t = app.plain()
    const s = app.lineStart(t, editor.cursorPosition)
    const cur = t.substr(s, 2)
    if (cur === "☐ " || cur === "☑ " || cur === "• ") { editor.remove(s, s + 2); if (cur.charAt(0) === mark.charAt(0) || (mark === "☐ " && cur === "☑ ")) { editorChanged(); return } }
    editor.insert(s, mark)
    editorChanged()
  }

  // ================================================================ window
  FloatingWindow {
    id: win
    title: "Notes"
    implicitWidth: 1080
    implicitHeight: 680
    minimumSize: Qt.size(720, 420)
    color: "transparent"
    Rectangle { anchors.fill: parent; color: Theme.dark ? Qt.rgba(0.11, 0.11, 0.13, 0.97) : Qt.rgba(0.99, 0.99, 1, 0.98) }

    readonly property color tint: "#f5b72e"     // Notes' own highlight
    // ---- shortcuts (the menu bar sends the same keys)
    Shortcut { sequence: "Ctrl+N"; onActivated: app.newNote() }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: app.newFolder() }
    Shortcut { sequence: "Ctrl+Backspace"; onActivated: app.deleteNote() }
    Shortcut { sequence: "Ctrl+E"; onActivated: app.exportNote() }
    Shortcut { sequence: "Ctrl+F"; onActivated: searchField.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+1"; onActivated: app.style("title") }
    Shortcut { sequence: "Ctrl+2"; onActivated: app.style("heading") }
    Shortcut { sequence: "Ctrl+0"; onActivated: app.style("body") }
    Shortcut { sequence: "Ctrl+B"; onActivated: app.style("bold") }
    Shortcut { sequence: "Ctrl+I"; onActivated: app.style("italic") }
    Shortcut { sequence: "Ctrl+Shift+X"; onActivated: app.style("strike") }
    Shortcut { sequence: "Ctrl+Shift+L"; onActivated: app.linePrefix("☐ ") }
    Shortcut { sequence: "Ctrl+Shift+8"; onActivated: app.linePrefix("• ") }
    Shortcut { sequence: "Ctrl+Alt+S"; onActivated: app.showFolders = !app.showFolders }
    Shortcut { sequence: "Ctrl+="; onActivated: app.textSize = Math.min(26, app.textSize + 1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: app.textSize = Math.max(11, app.textSize - 1) }
    Shortcut { sequence: "Ctrl+W"; onActivated: { app.saveNow(); Qt.quit() } }


    // ---- folders
    Rectangle {
      id: side
      width: app.showFolders ? 200 : 0
      visible: width > 1
      clip: true
      Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
      anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 8 }
      radius: 12
      color: Theme.dark ? Qt.rgba(1, 1, 1, 0.045) : Qt.rgba(0, 0, 0, 0.035)
      border.color: Theme.separator
      WindowControls { x: 14; y: 14; window: win; onCloseRequested: { app.saveNow(); Qt.quit() } }
      Item { anchors { left: parent.left; right: parent.right; top: parent.top } height: 40; DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() } }
      Column {
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 48 }
        spacing: 1
        FolderRow { label: "All Notes"; key: "*" }
        Text { x: 16; height: 28; verticalAlignment: Text.AlignBottom; bottomPadding: 4; text: "Folders"; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.small - 0.5; font.weight: Font.Bold }
        Repeater { model: app.folders; delegate: FolderRow { required property string modelData; label: modelData; key: modelData; removable: true } }
        Item { width: 1; height: 8 }
        FolderRow { label: "Recently Deleted"; key: "~" }
      }
      Rectangle {
        anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
        width: nf.implicitWidth + 34; height: 28; radius: 8
        color: nfh.hovered ? Theme.hover : "transparent"
        Sym { x: 8; anchors.verticalCenter: parent.verticalCenter; name: "plus"; width: 12; height: 12; color: Theme.textDim }
        Txt { id: nf; x: 26; anchors.verticalCenter: parent.verticalCenter; text: "New Folder"; color: Theme.textDim; font.pixelSize: Theme.small }
        HoverHandler { id: nfh }
        TapHandler { onTapped: app.newFolder() }
      }
    }

    // ---- list of notes
    Item {
      id: middle
      anchors { left: side.right; top: parent.top; bottom: parent.bottom; leftMargin: 6 }
      width: 290
      Item {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 52
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        WindowControls { visible: !app.showFolders; x: 10; y: 19; window: win; onCloseRequested: { app.saveNow(); Qt.quit() } }
        Row {
          anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
          spacing: 2
          Tool { sym: "dock"; tip: "Folders"; onClicked: app.showFolders = !app.showFolders }
          Tool { sym: "plus"; tip: "New Note"; onClicked: app.newNote() }
        }
      }
      Rectangle {
        id: searchBox
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 52; leftMargin: 10; rightMargin: 10 }
        height: 30; radius: 8
        color: Theme.field; border.color: searchField.activeFocus ? win.tint : Theme.separator
        Sym { name: "search"; width: 12; height: 12; color: Theme.textDim; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
        TextInput {
          id: searchField
          anchors { left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 8; verticalCenter: parent.verticalCenter }
          color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
          clip: true
          onTextChanged: app.query = text
          Keys.onEscapePressed: text = ""
          Txt { visible: !searchField.text; text: "Search"; color: Theme.textFaint; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
        }
      }
      ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: searchBox.bottom; bottom: parent.bottom; topMargin: 8; leftMargin: 8; rightMargin: 8 }
        clip: true
        model: app.visibleNotes
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
          id: slot
          required property var modelData
          required property int index
          // A heading (Pinned, Today, …) above the first note of each group.
          readonly property string group: app.group(modelData)
          readonly property bool first: index === 0 || app.group(app.visibleNotes[index - 1]) !== group
          width: list.width; height: row.height + (first ? 30 : 0)
          Text { visible: slot.first; width: list.width; height: 30; leftPadding: 8; verticalAlignment: Text.AlignBottom; bottomPadding: 6; text: slot.group; color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.small; font.weight: Font.Bold }
        Rectangle {
          id: row
          readonly property var modelData: slot.modelData
          y: slot.first ? 30 : 0
          readonly property bool sel: modelData.id === app.current
          width: list.width; height: 62; radius: 9
          color: sel ? Qt.rgba(0.96, 0.72, 0.18, Theme.dark ? 0.32 : 0.28) : (rh.hovered ? Theme.hover : "transparent")
          Behavior on color { ColorAnimation { duration: Theme.fast } }
          Column {
            anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 3
            Txt { width: parent.width; text: (row.modelData.text.split("\n")[0] || "New Note").trim() || "New Note"; font.weight: Font.Bold }
            Row {
              width: parent.width; spacing: 8
              Txt { text: app.when(row.modelData); color: Theme.text; opacity: 0.8; font.pixelSize: Theme.small }
              Txt { width: parent.width - x; text: row.modelData.text.split("\n").slice(1).join(" ").trim() || "No additional text"; color: Theme.textDim; font.pixelSize: Theme.small }
            }
            Txt { visible: app.folder === "*" || app.folder === "~"; text: row.modelData.folder; color: Theme.textFaint; font.pixelSize: Theme.small - 1 }
          }
          HoverHandler { id: rh }
          TapHandler { onTapped: app.current = row.modelData.id }
          TapHandler { acceptedButtons: Qt.RightButton; onTapped: { app.current = row.modelData.id; app.togglePin() } }
        }
        }
        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal } NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Theme.normal; easing.type: Easing.OutBack } }
        remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast } }
        displaced: Transition { NumberAnimation { properties: "y"; duration: Theme.normal; easing.type: Easing.OutQuint } }
        Txt { visible: list.count === 0; anchors.centerIn: parent; text: app.query ? "No matches" : (app.folder === "~" ? "Nothing deleted" : "No notes"); color: Theme.textDim }
      }
      Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.separator }
    }

    // ---- the note
    Item {
      id: page
      anchors { left: middle.right; right: parent.right; top: parent.top; bottom: parent.bottom }

      // Toolbar
      Item {
        id: bar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 52
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        Row {
          anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
          spacing: 2
          visible: !!app.note && !app.note.deleted
          Tool { label: "Aa"; tip: "Format"; onClicked: formatMenu.open = !formatMenu.open; active: formatMenu.open }
          Tool { sym: "check"; tip: "Checklist"; onClicked: app.linePrefix("☐ ") }
          Tool { label: "B"; bold: true; tip: "Bold"; onClicked: app.style("bold") }
          Tool { label: "I"; italic: true; tip: "Italic"; onClicked: app.style("italic") }
          Tool { label: "S"; strike: true; tip: "Strikethrough"; onClicked: app.style("strike") }
        }
        Row {
          anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
          spacing: 2
          Tool { visible: !!app.note && app.note.deleted; label: "Recover"; tip: "Put back"; onClicked: app.restoreNote() }
          Tool { visible: !!app.note && !app.note.deleted; label: app.note && app.note.pinned ? "Unpin" : "Pin"; tip: "Keep on top"; onClicked: app.togglePin() }
          Tool { visible: !!app.note; sym: "close"; tip: app.note && app.note.deleted ? "Delete forever" : "Delete"; onClicked: app.deleteNote() }
        }
      }

      // Format menu
      Glass {
        id: formatMenu
        property bool open: false
        z: 10
        x: 12; y: 48
        width: 190; height: fcol.implicitHeight + 12
        radius: 12; fill: Theme.glassStrong; shadowSize: 22
        visible: opacity > 0
        opacity: open ? 1 : 0
        scale: open ? 1 : 0.9
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
        Column {
          id: fcol
          x: 6; y: 6; width: parent.width - 12
          Repeater {
            model: [["Title", "title", 22, true], ["Heading", "heading", 17, true], ["Body", "body", 14, false], ["Checklist", "check", 14, false], ["Bulleted List", "bullet", 14, false]]
            delegate: Rectangle {
              required property var modelData
              width: fcol.width; height: 32; radius: 7
              color: fh.hovered ? win.tint : "transparent"
              Txt { x: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData[0]; font.pixelSize: modelData[2]; font.weight: modelData[3] ? Font.Bold : Font.Normal; color: fh.hovered ? "#1c1c1e" : Theme.text }
              HoverHandler { id: fh }
              TapHandler {
                onTapped: {
                  formatMenu.open = false
                  if (modelData[1] === "check") app.linePrefix("☐ ")
                  else if (modelData[1] === "bullet") app.linePrefix("• ")
                  else app.style(modelData[1])
                }
              }
            }
          }
        }
      }

      Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom }
        contentHeight: editor.contentHeight + 120
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        opacity: 1
        transform: Translate { id: noteShift }
        SequentialAnimation {
          id: noteIn
          PropertyAction { target: flick; property: "opacity"; value: 0 }
          PropertyAction { target: noteShift; property: "y"; value: 8 }
          ParallelAnimation {
            NumberAnimation { target: flick; property: "opacity"; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
            NumberAnimation { target: noteShift; property: "y"; to: 0; duration: Theme.slow; easing.type: Easing.OutQuint }
          }
        }

        Txt {
          id: dateLine
          visible: !!app.note
          anchors.horizontalCenter: parent.horizontalCenter
          y: 4
          text: app.note ? Qt.formatDateTime(new Date(app.note.modified), "d MMMM yyyy 'at' HH:mm") : ""
          color: Theme.textDim; font.pixelSize: Theme.small
        }
        TextEdit {
          id: editor
          x: Math.max(32, (flick.width - 760) / 2)
          y: 34
          width: Math.min(760, flick.width - 64)
          textFormat: TextEdit.RichText
          wrapMode: TextEdit.Wrap
          color: Theme.text
          font.family: Theme.font
          font.pixelSize: app.textSize
          selectionColor: Qt.rgba(0.96, 0.72, 0.18, 0.45)
          selectedTextColor: Theme.text
          selectByMouse: true
          persistentSelection: true
          readOnly: !app.note || app.note.deleted
          visible: !!app.note
          onTextChanged: app.editorChanged()
          onCursorRectangleChanged: {
            const r = cursorRectangle
            if (r.y + y + 40 > flick.contentY + flick.height) flick.contentY = r.y + y + 40 - flick.height
            else if (r.y + y < flick.contentY) flick.contentY = Math.max(0, r.y + y - 10)
          }
          // Enter: the first line becomes the title; a checklist or bullet line
          // continues the list, an empty one ends it; text after a heading is body.
          Keys.onReturnPressed: ev => {
            const t = app.plain()
            const s = app.lineStart(t, cursorPosition)
            const pre = t.substr(s, 2)
            const listy = pre === "☐ " || pre === "☑ " || pre === "• "
            if (listy && app.lineEnd(t, s) - s <= 2) { remove(s, app.lineEnd(t, s)); ev.accepted = true; return }
            const firstLine = s === 0
            app.pendingStyle = ""
            ev.accepted = false
            Qt.callLater(() => {
              if (firstLine) app.styleRange(0, app.lineEnd(app.plain(), 0), "title")
              app.bodyAtCursor()
              if (listy) insert(cursorPosition, pre === "• " ? "• " : "☐ ")
              app.editorChanged()
            })
          }
          // A click on a box ticks it.
          TapHandler {
            onTapped: ev => {
              const pos = editor.positionAt(ev.position.x, ev.position.y)
              for (const p of [pos, pos - 1]) {
                const ch = editor.getText(p, p + 1)
                if (ch === "☐" || ch === "☑") { editor.remove(p, p + 1); editor.insert(p, ch === "☐" ? "☑" : "☐"); app.editorChanged(); return }
              }
            }
          }
          Txt { visible: !editor.length && !editor.activeFocus; text: "Start writing"; color: Theme.textFaint; font.pixelSize: app.textSize }
          Component.onCompleted: app.loadNote()
        }
        TapHandler { onTapped: { formatMenu.open = false; editor.forceActiveFocus() } }
      }

      Column {
        visible: !app.note
        anchors.centerIn: parent
        spacing: 12
        Image { anchors.horizontalCenter: parent.horizontalCenter; source: Quickshell.iconPath("memora-notes"); width: 72; height: 72; sourceSize: Qt.size(144, 144); opacity: 0.8 }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "No note selected"; color: Theme.textDim }
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: nn.implicitWidth + 28; height: 30; radius: 9; color: win.tint
          Txt { id: nn; anchors.centerIn: parent; text: "New Note"; color: "#1c1c1e"; font.weight: Font.Bold }
          TapHandler { onTapped: app.newNote() }
        }
      }
    }

    // ---- pieces
    component FolderRow: Item {
      id: fr
      property string label; property string key; property bool removable: false
      readonly property bool here: app.folder === key
      width: side.width; height: 30
      Rectangle {
        anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
        radius: 7
        color: fr.here ? Qt.rgba(0.96, 0.72, 0.18, Theme.dark ? 0.32 : 0.28) : (frh.hovered ? Theme.hover : "transparent")
        Behavior on color { ColorAnimation { duration: Theme.fast } }
      }
      Image { id: fi; x: 16; anchors.verticalCenter: parent.verticalCenter; width: 17; height: 17; sourceSize: Qt.size(34, 34); source: Quickshell.iconPath(fr.key === "~" ? "user-trash" : "folder") }
      Txt { visible: app.renamingFolder !== fr.key; anchors { left: fi.right; leftMargin: 9; right: cnt.left; rightMargin: 6; verticalCenter: parent.verticalCenter } text: fr.label }
      TextInput {
        id: rn
        visible: app.renamingFolder === fr.key
        anchors { left: fi.right; leftMargin: 9; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize
        onVisibleChanged: if (visible) { text = fr.label; forceActiveFocus(); selectAll() }
        Keys.onReturnPressed: app.renameFolder(fr.key, text)
        Keys.onEscapePressed: app.renamingFolder = ""
        onActiveFocusChanged: if (!activeFocus && visible) app.renameFolder(fr.key, text)
      }
      Txt { id: cnt; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: app.countIn(fr.key); color: Theme.textDim; font.pixelSize: Theme.small }
      HoverHandler { id: frh }
      TapHandler { onTapped: app.folder = fr.key; onDoubleTapped: if (fr.removable) app.renamingFolder = fr.key }
      TapHandler { acceptedButtons: Qt.RightButton; onTapped: if (fr.removable) app.deleteFolder(fr.key) }
    }

    component Tool: Rectangle {
      id: tl
      property string sym: ""
      property string label: ""
      property string tip: ""
      property bool bold: false
      property bool italic: false
      property bool strike: false
      property bool active: false
      signal clicked()
      width: sym ? 32 : Math.max(32, lt.implicitWidth + 18); height: 30; radius: 8
      color: active ? Theme.pressed : (th.hovered ? Theme.hover : "transparent")
      scale: tt.pressed ? 0.92 : 1
      Behavior on scale { NumberAnimation { duration: Theme.fast } }
      Sym { visible: tl.sym !== ""; anchors.centerIn: parent; name: tl.sym; width: 14; height: 14; color: Theme.textDim }
      Txt { id: lt; visible: tl.label !== ""; anchors.centerIn: parent; text: tl.label; color: Theme.textDim; font.weight: tl.bold ? Font.Bold : Font.Medium; font.italic: tl.italic; font.strikeout: tl.strike }
      HoverHandler { id: th }
      TapHandler { id: tt; onTapped: tl.clicked() }
    }
  }
}
