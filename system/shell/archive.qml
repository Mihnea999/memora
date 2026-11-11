//@ pragma UseQApplication
//@ pragma AppId memora-archive
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui

// Archives: open zip, rar, 7z, tar, iso and dozens more, look inside as in Files,
// extract all of it or only some, open a file straight from it or drag it out;
// make new archives (zip, 7z, RAR, tar.gz/xz/zst) with a password and in parts,
// add to them and take out of them. The work is done by bin/memora-archive-tool
// (7-Zip, unrar, RARLAB's rar, bsdtar).
// Run as `memora-archive [ARCHIVE]` or `memora-archive --compress FILE…`.
ShellRoot {
  id: app
  readonly property string tool: Theme.share + "/bin/memora-archive-tool"
  readonly property string home: Quickshell.env("HOME")
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/memora/archives"

  // ---- the open archive
  property string archive: ""
  property var info: null
  property var entries: []
  property string cwd: ""              // the folder inside the archive being looked at
  property var sel: ({})               // path inside → true
  property string lastClicked: ""
  property string sortKey: "name"      // name | kind | size | packed | date
  property bool asc: true
  property string query: ""
  property string password: ""
  property bool loading: false
  property bool draggingOut: false

  // ---- what is on screen over it
  property string sheet: ""            // extract | password | create | info | getrar
  property var job: null               // { kind, title, pct, file } while the tool works
  property var toast: null             // { text, path, error }
  property var caps: ({ rar: false })
  property var recents: []

  // Extract
  property string destDir: ""
  property var extractItems: []        // empty: everything
  property bool showWhenDone: true
  // Password
  property var afterPassword: null
  property bool passWrong: false
  // New archive
  property var createFiles: []
  property string cName: "Archive"
  property string cFormat: "zip"
  property int cLevel: 5
  property string cPass: ""
  property bool cHide: false
  property real cSplit: 0
  property string cDest: ""

  readonly property bool hasArchive: archive !== "" && info !== null
  readonly property var selected: Object.keys(sel).filter(p => sel[p])
  readonly property var shown: {
    const q = query.trim().toLowerCase()
    const list = q ? entries.filter(e => e.n.toLowerCase().indexOf(q) >= 0) : entries.filter(e => e.d === cwd)
    const k = sortKey, dir = asc ? 1 : -1
    list.sort((a, b) => {
      if (a.dir !== b.dir) return a.dir ? -1 : 1
      let r = 0
      if (k === "size") r = a.s - b.s
      else if (k === "packed") r = a.k - b.k
      else if (k === "date") r = a.m < b.m ? -1 : (a.m > b.m ? 1 : 0)
      else if (k === "kind") r = kindName(a).localeCompare(kindName(b))
      if (!r) r = a.n.localeCompare(b.n, undefined, { numeric: true, sensitivity: "base" })
      return r * dir
    })
    return list
  }
  readonly property var crumbs: cwd ? cwd.split("/") : []

  // ================================================================ helpers
  function baseName(p) { return p.split("/").pop() }
  function dirName(p) { return p.substring(0, p.lastIndexOf("/")) || "/" }
  function pretty(p) { return p.startsWith(home + "/") ? "~" + p.slice(home.length) : (p === home ? "~" : p) }
  function human(b) {
    if (b < 1000) return b + (b === 1 ? " byte" : " bytes")
    if (b < 1e6) return (b / 1e3).toFixed(b < 1e4 ? 1 : 0) + " KB"
    if (b < 1e9) return (b / 1e6).toFixed(1) + " MB"
    if (b < 1e12) return (b / 1e9).toFixed(2) + " GB"
    return (b / 1e12).toFixed(2) + " TB"
  }
  function ext(n) { const i = n.lastIndexOf("."); return i > 0 ? n.slice(i + 1).toLowerCase() : "" }
  readonly property var archiveExt: /\.(zip|zipx|7z|rar|tar|gz|tgz|bz2|tbz2?|xz|txz|zst|tzst|lz|lz4|lzma|tlz|z|taz|cab|arj|lzh|lha|cpio|iso|dmg|wim|xar|rpm|deb|jar|apk|001|r00|ace)$/i
  function isArchive(p) { return archiveExt.test(p) }
  readonly property var kinds: ({
    png: "image", jpg: "image", jpeg: "image", webp: "image", gif: "image", bmp: "image", svg: "image", heic: "image", avif: "image", tif: "image", tiff: "image", ico: "image", psd: "image",
    mp4: "video", mkv: "video", webm: "video", mov: "video", avi: "video", m4v: "video", wmv: "video",
    mp3: "audio", flac: "audio", ogg: "audio", wav: "audio", m4a: "audio", opus: "audio", aac: "audio",
    pdf: "pdf", txt: "text", md: "text", log: "text", rtf: "text", nfo: "text", csv: "sheet", ini: "text", cfg: "text",
    json: "code", js: "code", ts: "code", py: "code", sh: "code", rs: "code", go: "code", c: "code", cpp: "code", h: "code", java: "code", qml: "code", lua: "code", html: "code", css: "code", xml: "code", yml: "code", yaml: "code",
    zip: "archive", "7z": "archive", rar: "archive", tar: "archive", gz: "archive", xz: "archive", zst: "archive", bz2: "archive", tgz: "archive",
    iso: "disc", img: "disc", dmg: "disc", exe: "app", msi: "app", appimage: "app", deb: "package", rpm: "package", apk: "package",
    doc: "document", docx: "document", odt: "document", xls: "sheet", xlsx: "sheet", ods: "sheet", ppt: "slides", pptx: "slides", odp: "slides",
    ttf: "font", otf: "font", woff: "font", woff2: "font"
  })
  function kindOf(e) { return e.dir ? "folder" : (kinds[ext(e.n)] || "file") }
  function kindName(e) {
    if (e.dir) return "Folder"
    const k = kindOf(e), x = ext(e.n).toUpperCase()
    const names = { image: x + " image", video: x + " video", audio: x + " audio", pdf: "PDF document", text: "Text", code: x + " source",
      archive: x + " archive", disc: "Disk image", app: "Windows app", package: "Package", document: "Document", sheet: "Spreadsheet",
      slides: "Presentation", font: "Font" }
    return names[k] || (x ? x + " file" : "File")
  }
  function iconFor(e) {
    const map = { folder: "folder", image: "image-x-generic", video: "video-x-generic", audio: "audio-x-generic", pdf: "application-pdf",
      text: "text-x-generic", code: "text-x-script", archive: "package-x-generic", disc: "media-optical", app: "application-x-executable",
      package: "package-x-generic", document: "x-office-document", sheet: "x-office-spreadsheet", slides: "x-office-presentation",
      font: "font-x-generic", file: "text-x-generic" }
    return Quickshell.iconPath(map[kindOf(e)] || "text-x-generic", "text-x-generic")
  }
  function typeLabel(t) {
    const m = { "zip": "ZIP", "7z": "7-Zip", "Rar": "RAR", "Rar5": "RAR 5", "tar": "TAR", "Iso": "Disk image (ISO)", "Udf": "Disk image (UDF)",
      "Dmg": "Disk image (DMG)", "Cab": "Cabinet", "Compound": "Windows Installer", "Ar": "Debian package", "Rpm": "RPM package",
      "wim": "Windows image", "gzip": "GZip", "bzip2": "BZip2", "xz": "XZ", "zstd": "Zstandard", "Split": "Split archive" }
    return m[t] || String(t || "").toUpperCase()
  }
  function dateText(m) {
    if (!m) return "—"
    const d = new Date(m.replace(" ", "T"))
    if (isNaN(d.getTime())) return m
    const now = new Date()
    if (d.toDateString() === now.toDateString()) return "Today, " + Qt.formatTime(d, "HH:mm")
    const y = new Date(now); y.setDate(now.getDate() - 1)
    if (d.toDateString() === y.toDateString()) return "Yesterday, " + Qt.formatTime(d, "HH:mm")
    return Qt.formatDateTime(d, d.getFullYear() === now.getFullYear() ? "d MMM, HH:mm" : "d MMM yyyy")
  }
  readonly property real ratio: info && info.size > 0 ? Math.max(0, 1 - info.disk / info.size) : 0

  // ================================================================ reading
  Process {
    id: lister
    stdout: StdioCollector { onStreamFinished: app.listed(text) }
  }
  function openArchive(path) {
    if (!path) return
    password = ""
    sheet = ""
    load(path, false)
  }
  function load(path, keepPlace) {
    if (!keepPlace) { cwd = ""; sel = ({}); query = ""; info = null; entries = [] }
    archive = path
    loading = true
    lister.running = false
    lister.environment = ({ MEMORA_ARCHIVE_PASSWORD: password })
    lister.command = [tool, "list", path]
    lister.running = true
  }
  function listed(text) {
    loading = false
    const t = text.trim()
    if (t.startsWith("ERR ") || !t) {
      const e = t.slice(4)
      if (e === "needpass" || e === "badpass") { askPassword(e === "badpass", () => load(archive, true)); return }
      showError(e || "This archive couldn't be read.")
      if (!info) archive = ""
      return
    }
    try {
      const r = JSON.parse(t)
      info = r.info
      entries = r.entries
      if (cwd && !entries.some(e => e.p === cwd && e.dir)) cwd = ""
      remember(archive)
      // Something wrapped in one folder: go straight into it.
      const top = entries.filter(e => e.d === "")
      if (cwd === "" && top.length === 1 && top[0].dir && !win.seenInside) cwd = top[0].p
      win.seenInside = true
    } catch (err) {
      showError("This archive couldn't be read.")
      if (!info) archive = ""
    }
  }

  // ---- recent archives (~/.config/memora/archives-recent)
  FileView {
    id: recentFile
    path: app.home + "/.config/memora/archives-recent"
    printErrors: false
    // Only the ones still there.
    onLoaded: {
      probeRecent.command = ["bash", "-c", "for f; do [[ -e $f ]] && printf '%s\\n' \"$f\"; done; true", "_"].concat(text().split("\n").filter(l => l.trim()))
      probeRecent.running = true
    }
  }
  function remember(p) {
    recents = [p].concat(recents.filter(r => r !== p)).slice(0, 8)
    Quickshell.execDetached(["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"${@:2}\" > \"$1\"", "_", recentFile.path].concat(recents))
  }
  Process { id: probeRecent; stdout: StdioCollector { onStreamFinished: app.recents = text.split("\n").filter(l => l.trim()) } }

  // ---- what this computer can make
  Process {
    id: capsProc
    command: [app.tool, "caps"]
    stdout: StdioCollector { onStreamFinished: { try { app.caps = JSON.parse(text) } catch (e) {} } }
  }

  // ================================================================ working
  property bool cancelled: false
  Process {
    id: worker
    property var onDone: null
    property var retry: null
    property var outs: []
    property string err: ""
    stdout: SplitParser { onRead: line => app.jobLine(line) }
    onExited: code => app.jobEnded(code)
  }
  function start(kind, title, args, env, done) {
    if (worker.running) return
    worker.outs = []
    worker.err = ""
    worker.onDone = done
    worker.retry = () => app.start(kind, title, args, env, done)
    worker.environment = Object.assign({ MEMORA_ARCHIVE_PASSWORD: password, MEMORA_ARCHIVE_HIDE: "0", MEMORA_ARCHIVE_SPLIT: "0" }, env || {})
    worker.command = [tool].concat(args)
    cancelled = false
    job = { kind: kind, title: title, pct: 0, file: "" }
    worker.running = true
  }
  function jobLine(l) {
    if (!job) return
    if (l.startsWith("P ")) { const p = parseFloat(l.slice(2)); if (p !== job.pct) job = Object.assign({}, job, { pct: p }) }
    else if (l.startsWith("F ")) job = Object.assign({}, job, { file: l.slice(2) })
    else if (l.startsWith("OUT ")) worker.outs.push(l.slice(4))
    else if (l.startsWith("ERR ")) worker.err = l.slice(4)
  }
  function jobEnded(code) {
    const done = worker.onDone, outs = worker.outs, err = worker.err
    job = null
    if (cancelled) { cancelled = false; return }
    if (err === "needpass" || err === "badpass") { askPassword(err === "badpass", worker.retry); return }
    if (code !== 0 || err) { showError(err || "It didn't work."); return }
    if (done) done(outs)
  }
  function cancel() {
    cancelled = true
    worker.running = false
  }

  function askPassword(wrong, then) {
    passWrong = wrong
    afterPassword = then
    sheet = "password"
  }
  function showError(t) { toast = { text: t, error: true, path: "" }; toastTimer.restart() }
  function showDone(t, p) { toast = { text: t, error: false, path: p || "" }; toastTimer.restart() }
  Timer { id: toastTimer; interval: 7000; onTriggered: app.toast = null }

  // ---- what you can do
  function enter(e) {
    if (e.dir) { cwd = e.p; query = ""; sel = ({}); return }
    openItems([e.p])
  }
  function up() { if (query) { query = ""; return } if (cwd) { const was = cwd; cwd = cwd.indexOf("/") > 0 ? cwd.substring(0, cwd.lastIndexOf("/")) : ""; sel = {}; sel[was] = true; sel = sel } }
  function needsPasswordFirst(then) {
    if (info && info.encrypted && !password) { askPassword(false, then); return true }
    return false
  }
  // A file from the archive in the app it belongs to (a copy in the cache).
  function openItems(items) {
    if (needsPasswordFirst(() => openItems(items))) return
    const dir = cacheDir + "/open-" + Date.now()
    start("open", items.length === 1 ? "Opening “" + baseName(items[0]) + "”" : "Opening " + items.length + " items", ["open", archive, dir].concat(items), {},
      outs => outs.forEach(o => Quickshell.execDetached(["gio", "open", o])))
  }
  function askExtract(items) {
    extractItems = items || []
    if (!destDir) destDir = dirName(archive)
    sheet = "extract"
  }
  function extractNow() {
    sheet = ""
    if (needsPasswordFirst(() => extractNow())) return
    const items = extractItems
    const dest = destDir || dirName(archive)
    start("extract", items.length ? "Extracting " + (items.length === 1 ? "“" + baseName(items[0]) + "”" : items.length + " items") : "Extracting “" + baseName(archive) + "”",
      ["extract", archive, dest].concat(items), {}, outs => {
        showDone(outs.length === 1 ? "Extracted “" + baseName(outs[0]) + "” to " + pretty(dest) : "Extracted " + outs.length + " items to " + pretty(dest), outs[0])
        if (showWhenDone && outs.length) Quickshell.execDetached(["memora-files", outs.length === 1 && !app.isFile(outs[0]) ? outs[0] : dest])
      })
  }
  // Only a guess (a dot near the end): Files opens folders, and the folder of a file.
  // Is a point (in `from`) on the item? Taps reach every handler under them, card or not.
  function inside(item, from, pos) {
    const p = item.mapFromItem(from, pos.x, pos.y)
    return p.x >= 0 && p.y >= 0 && p.x <= item.width && p.y <= item.height
  }
  function isFile(p) { return /\.[A-Za-z0-9]{1,5}$/.test(baseName(p)) }
  function extractHere(items) { destDir = dirName(archive); extractItems = items || []; extractNow() }
  function test() {
    start("test", "Checking “" + baseName(archive) + "”", ["test", archive], {}, () => showDone("Every file in “" + baseName(archive) + "” is intact.", ""))
  }
  function addFiles(files) {
    if (!files.length) return
    if (!info || !info.writable) { newArchive(files); return }
    start("add", "Adding " + (files.length === 1 ? "“" + baseName(files[0]) + "”" : files.length + " items"), ["add", archive, cwd].concat(files),
      { MEMORA_ARCHIVE_HIDE: info.type === "7z" && info.encrypted && password ? "1" : "0" }, () => {
        showDone(files.length === 1 ? "Added “" + baseName(files[0]) + "”." : "Added " + files.length + " items.", "")
        load(archive, true)
      })
  }
  function removeSelected() {
    const items = selected
    if (!items.length || !info || !info.writable) return
    confirm.ask({
      title: items.length === 1 ? "Delete “" + baseName(items[0]) + "” from the archive?" : "Delete " + items.length + " items from the archive?",
      message: "They are taken out of “" + baseName(archive) + "”. This can't be undone.",
      action: "Delete",
      onAccept: () => start("delete", "Deleting", ["delete", archive].concat(items), {}, () => { sel = ({}); load(archive, true) })
    })
  }
  function newArchive(files) {
    createFiles = files
    const first = files[0] || ""
    cName = files.length === 1 ? baseName(first).replace(/\.[^.]{1,5}$/, "") || baseName(first) : "Archive"
    cDest = first ? dirName(first) : home
    cPass = ""; cHide = false; cSplit = 0
    if (cFormat === "rar" && !caps.rar) cFormat = "zip"
    capsProc.running = true
    sheet = "create"
  }
  readonly property var formats: [
    ["zip", "ZIP", ".zip"], ["7z", "7Z", ".7z"], ["rar", "RAR", ".rar"],
    ["tar.gz", "TAR.GZ", ".tar.gz"], ["tar.xz", "TAR.XZ", ".tar.xz"], ["tar.zst", "TAR.ZST", ".tar.zst"]
  ]
  readonly property string cExt: (formats.find(f => f[0] === cFormat) || ["", "", ".zip"])[2]
  readonly property bool cCanLock: cFormat === "zip" || cFormat === "7z" || cFormat === "rar"
  function createNow() {
    if (cFormat === "rar" && !caps.rar) { sheet = "getrar"; return }
    sheet = ""
    const out = cDest + "/" + (cName.trim() || "Archive") + cExt
    const pw = cCanLock ? cPass : ""
    start("create", "Compressing " + (createFiles.length === 1 ? "“" + baseName(createFiles[0]) + "”" : createFiles.length + " items"),
      ["create", out, cFormat, String(cLevel)].concat(createFiles),
      { MEMORA_ARCHIVE_PASSWORD: pw, MEMORA_ARCHIVE_HIDE: cHide && pw && cFormat !== "zip" ? "1" : "0", MEMORA_ARCHIVE_SPLIT: String(Math.round(cSplit)) },
      outs => {
        const made = outs[0] || out
        showDone("Made “" + baseName(made) + "”.", made)
        password = pw
        load(made, false)
      })
  }
  function getRar() {
    sheet = ""
    start("getrar", "Getting RAR from rarlab.com", ["get-rar"], {}, () => {
      capsProc.running = true
      caps = Object.assign({}, caps, { rar: true })
      showDone("RAR is ready: you can make RAR archives now.", "")
      cFormat = "rar"
      if (createFiles.length) sheet = "create"
    })
  }

  // ---- selection (as in Files)
  function select(p, mods) {
    const toggle = mods & (Qt.ControlModifier | Qt.MetaModifier), range = mods & Qt.ShiftModifier
    const s = toggle || range ? Object.assign({}, sel) : {}
    if (range && lastClicked) {
      const list = shown.map(e => e.p)
      const a = list.indexOf(lastClicked), b = list.indexOf(p)
      if (a >= 0 && b >= 0) for (let i = Math.min(a, b); i <= Math.max(a, b); i++) s[list[i]] = true
      else s[p] = true
    } else if (toggle) s[p] = !s[p]
    else s[p] = true
    sel = s
    if (!range) lastClicked = p
  }
  function selectAll() { const s = {}; shown.forEach(e => s[e.p] = true); sel = s }
  function moveSel(d) {
    const list = shown
    if (!list.length) return
    let i = list.findIndex(e => e.p === lastClicked)
    i = Math.max(0, Math.min(list.length - 1, i < 0 ? 0 : i + d))
    select(list[i].p, 0)
    table.positionViewAtIndex(i, ListView.Contain)
  }

  // ---- drag out of the window: the items come out into the cache while you drag
  Process { id: dragger }
  function dragOut(items) {
    if (needsPasswordFirst(() => {})) return
    const dir = cacheDir + "/drag-" + Date.now()
    dout.uris = items.map(p => "file://" + encodeURI(dir + "/" + p))
    dragger.environment = ({ MEMORA_ARCHIVE_PASSWORD: password })
    dragger.command = [tool, "open", archive, dir].concat(items)
    dragger.running = true
    draggingOut = true
    dout.Drag.active = true
  }

  // ---- started with files, or told by memora-archive while open
  function take(mode, list) {
    const files = String(list || "").split("\n").filter(f => f)
    if (!files.length) return
    if (mode === "compress" || !files.every(isArchive)) newArchive(files)
    else openArchive(files[0])
  }
  IpcHandler {
    target: "archive"
    function open(list: string): void { app.take("open", list) }
    function compress(list: string): void { app.take("compress", list) }
  }
  Component.onCompleted: {
    capsProc.running = true
    take(Quickshell.env("MEMORA_ARCHIVE_MODE") || "open", Quickshell.env("MEMORA_ARCHIVE_FILES"))
    Quickshell.execDetached(["bash", "-c", "find \"$1\" -mindepth 1 -maxdepth 1 -mmin +720 -exec rm -rf {} + 2>/dev/null", "_", cacheDir])
  }

  // ---- pickers
  FileDialog {
    id: openDialog
    title: "Open an Archive"
    currentFolder: "file://" + app.home + "/Downloads"
    nameFilters: ["Archives (*.zip *.7z *.rar *.tar *.gz *.tgz *.bz2 *.xz *.txz *.zst *.tzst *.iso *.dmg *.cab *.lzh *.arj *.cpio *.wim *.001 *.jar *.apk *.deb *.rpm)", "All files (*)"]
    onAccepted: app.openArchive(decodeURIComponent(String(selectedFile).replace(/^file:\/\//, "")))
  }
  FileDialog {
    id: filesDialog
    property bool forAdd: false
    title: forAdd ? "Add to the Archive" : "Choose What to Compress"
    fileMode: FileDialog.OpenFiles
    currentFolder: "file://" + app.home
    onAccepted: {
      const files = selectedFiles.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, "")))
      if (forAdd) app.addFiles(files); else app.newArchive(files)
    }
  }
  FolderDialog {
    id: folderDialog
    property string target: "extract"
    title: target === "extract" ? "Extract To" : "Save the Archive In"
    currentFolder: "file://" + (target === "extract" ? app.destDir : app.cDest)
    // The sheet it was opened from stays (or comes back) with the folder chosen.
    onAccepted: {
      const p = decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, ""))
      if (target === "extract") app.destDir = p; else app.cDest = p
      app.sheet = target
    }
    onRejected: app.sheet = target
    onVisibleChanged: if (!visible) pickGrace.restart()
  }
  // A dialog drawn inside the window, or its last click landing on the window
  // as it closes, must not count as a click beside the sheet.
  Timer { id: pickGrace; interval: 500 }
  readonly property bool picking: folderDialog.visible || openDialog.visible || filesDialog.visible || pickGrace.running

  // ================================================================ window
  FloatingWindow {
    id: win
    property bool seenInside: false
    onVisibleChanged: if (!visible) Qt.quit()
    title: app.hasArchive ? app.baseName(app.archive) : "Archives"
    implicitWidth: 940
    implicitHeight: 620
    minimumSize: Qt.size(620, 420)
    color: "transparent"
    readonly property bool narrow: width < 800

    Shortcut { sequence: "Ctrl+O"; onActivated: openDialog.open() }
    Shortcut { sequence: "Ctrl+N"; onActivated: { filesDialog.forAdd = false; filesDialog.open() } }
    Shortcut { sequence: "Ctrl+E"; enabled: app.hasArchive && !app.job; onActivated: app.askExtract(app.selected) }
    Shortcut { sequence: "Ctrl+Shift+E"; enabled: app.hasArchive && !app.job; onActivated: app.extractHere(app.selected) }
    Shortcut { sequence: "Ctrl+F"; enabled: app.hasArchive; onActivated: sf.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+A"; enabled: app.hasArchive && !sf.activeFocus; onActivated: app.selectAll() }
    Shortcut { sequence: "Ctrl+I"; enabled: app.hasArchive; onActivated: app.sheet = app.sheet === "info" ? "" : "info" }
    Shortcut { sequence: "Ctrl+T"; enabled: app.hasArchive && !app.job; onActivated: app.test() }
    Shortcut { sequence: "Ctrl+W"; onActivated: Qt.quit() }
    Shortcut { sequence: "Ctrl+Q"; onActivated: Qt.quit() }
    Shortcut { sequence: "Delete"; enabled: app.hasArchive && app.sheet === "" && !sf.activeFocus; onActivated: app.removeSelected() }
    Shortcut { sequence: "Alt+Up"; enabled: app.hasArchive; onActivated: app.up() }
    Shortcut { sequence: "Backspace"; enabled: app.hasArchive && !sf.activeFocus && app.sheet === ""; onActivated: app.up() }
    Shortcut { sequence: "Up"; enabled: app.hasArchive && app.sheet === ""; onActivated: app.moveSel(-1) }
    Shortcut { sequence: "Down"; enabled: app.hasArchive && app.sheet === ""; onActivated: app.moveSel(1) }
    Shortcut {
      sequence: "Return"; enabled: app.hasArchive && app.sheet === "" && !sf.activeFocus && app.selected.length > 0
      onActivated: { const e = app.entries.find(x => x.p === app.selected[0]); if (app.selected.length === 1 && e) app.enter(e); else app.openItems(app.selected.filter(p => !(app.entries.find(x => x.p === p) || {}).dir)) }
    }
    Shortcut {
      sequence: "Escape"
      onActivated: {
        if (menu.open) menu.open = false
        else if (app.sheet && !app.picking) app.sheet = ""
        else if (sf.text) sf.text = ""
        else app.sel = ({})
      }
    }

    Rectangle { anchors.fill: parent; color: Theme.window }

    // ------------------------------------------------------------ toolbar
    Item {
      id: bar
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: 54
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) }
      WindowControls { id: lights; x: 16; anchors.verticalCenter: parent.verticalCenter; window: win; onCloseRequested: Qt.quit() }

      // Back to the folder above.
      Tool {
        id: backBtn
        x: lights.x + lights.width + 14; anchors.verticalCenter: parent.verticalCenter
        visible: app.hasArchive
        sym: "chevron"; flip: true; on: app.cwd !== "" || app.query !== ""
        tip: "Back"
        onClicked: app.up()
      }
      Column {
        anchors { left: app.hasArchive ? backBtn.right : lights.right; leftMargin: app.hasArchive ? 8 : 18; right: tools.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        Txt { width: parent.width; text: app.hasArchive ? app.baseName(app.archive) : "Archives"; font.weight: Font.Bold }
        Txt {
          width: parent.width
          visible: text !== ""
          color: Theme.textDim; font.pixelSize: Theme.small - 0.5
          text: !app.hasArchive ? "" : app.typeLabel(app.info.type) + " · " + app.info.files + (app.info.files === 1 ? " file" : " files") + " · " + app.human(app.info.size)
                + (app.ratio > 0.01 ? " · " + Math.round(app.ratio * 100) + "% smaller" : "")
        }
      }

      Row {
        id: tools
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 6
        // Before anything is open: open one, or make one.
        Pill { visible: !app.hasArchive; text: "New Archive"; sym: "plus"; onClicked: { filesDialog.forAdd = false; filesDialog.open() } }
        Pill { visible: !app.hasArchive; text: "Open…"; primary: true; onClicked: openDialog.open() }

        Tool { visible: app.hasArchive; sym: "plus"; on: !!app.info && !app.job; tip: app.info && app.info.writable ? "Add files (or drop them here)" : "Make a new archive with more files"; onClicked: { filesDialog.forAdd = true; filesDialog.open() } }
        Tool { visible: app.hasArchive; sym: "trash"; on: !!app.info && app.info.writable && app.selected.length > 0 && !app.job; tip: app.info && !app.info.writable ? "This kind of archive can't be changed" : "Delete from the archive"; onClicked: app.removeSelected() }
        Tool { visible: app.hasArchive; sym: "shield"; on: !app.job; tip: "Check for damage (Ctrl+T)"; onClicked: app.test() }
        Tool { visible: app.hasArchive; sym: "info"; on: true; tip: "About this archive (Ctrl+I)"; onClicked: app.sheet = app.sheet === "info" ? "" : "info" }
        Item { visible: app.hasArchive; width: 4; height: 1 }
        // Search
        Rectangle {
          visible: app.hasArchive
          width: win.narrow ? 140 : 190; height: 28; radius: 8
          color: Theme.field; border.color: sf.activeFocus ? Theme.accent : Theme.separator
          Sym { name: "search"; width: 12; height: 12; color: Theme.textDim; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
          TextInput {
            id: sf
            clip: true
            anchors { left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 8; verticalCenter: parent.verticalCenter }
            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
            selectByMouse: true
            onTextChanged: { app.query = text; app.sel = ({}) }
            Keys.onEscapePressed: { text = ""; focus = false }
            Keys.onDownPressed: { focus = false; app.moveSel(1) }
            Txt { visible: !sf.text; text: "Search"; color: Theme.textFaint; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
          }
        }
        Pill {
          visible: app.hasArchive
          primary: true
          sym: "download"
          text: app.selected.length ? "Extract " + app.selected.length : "Extract"
          on: !app.job
          onClicked: app.askExtract(app.selected)
        }
      }
      Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.separator }
    }

    // ------------------------------------------------------------ inside the archive
    Item {
      id: browser
      anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: status.top }
      visible: app.hasArchive

      // Where you are: the archive, then its folders.
      Item {
        id: path
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 34
        Flickable {
          anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
          contentWidth: crumbRow.width
          clip: true
          interactive: contentWidth > width
          Row {
            id: crumbRow
            height: parent.height
            spacing: 2
            Crumb {
              label: app.baseName(app.archive)
              icon: Quickshell.iconPath("package-x-generic", "folder")
              current: app.cwd === "" && !app.query
              onClicked: { app.cwd = ""; sf.text = ""; app.sel = ({}) }
            }
            Repeater {
              model: app.query ? [] : app.crumbs
              delegate: Row {
                required property var modelData
                required property int index
                height: crumbRow.height
                spacing: 2
                Sym { name: "chevron"; width: 10; height: 10; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
                Crumb {
                  label: modelData
                  icon: Quickshell.iconPath("folder")
                  current: index === app.crumbs.length - 1
                  onClicked: { app.cwd = app.crumbs.slice(0, index + 1).join("/"); app.sel = ({}) }
                }
              }
            }
            Row {
              visible: app.query !== ""
              height: crumbRow.height
              spacing: 6
              Sym { name: "chevron"; width: 10; height: 10; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
              Txt { anchors.verticalCenter: parent.verticalCenter; text: app.shown.length + (app.shown.length === 1 ? " found for “" : " found for “") + app.query + "”"; color: Theme.textDim; font.pixelSize: Theme.small + 0.5 }
            }
          }
        }
      }

      // Column titles: a click sorts by it, again turns the order round.
      Item {
        id: head
        anchors { left: parent.left; right: parent.right; top: path.bottom }
        height: 26
        readonly property real cKind: win.narrow ? 0 : 140
        readonly property real cSize: 88
        readonly property real cPacked: win.narrow ? 0 : 88
        readonly property real cDate: 132
        readonly property real cName: width - 20 - cKind - cSize - cPacked - cDate - 16
        Row {
          x: 20; height: parent.height
          Head { width: head.cName; key: "name"; label: "Name" }
          Head { width: head.cKind; key: "kind"; label: "Kind"; visible: width > 0 }
          Head { width: head.cSize; key: "size"; label: "Size"; alignRight: true }
          Head { width: head.cPacked; key: "packed"; label: "Packed"; alignRight: true; visible: width > 0 }
          Head { width: head.cDate; key: "date"; label: "Modified"; alignRight: true }
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.separator }
      }

      ListView {
        id: table
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom }
        clip: true
        model: app.shown
        boundsBehavior: Flickable.StopAtBounds
        topMargin: 4; bottomMargin: 4; leftMargin: 8; rightMargin: 8
        // A click on nothing clears the selection; right-click: the archive's menu.
        TapHandler { onTapped: app.sel = ({}) }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => menu.show(table, ev.position, null) }

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index
          readonly property bool chosen: !!app.sel[modelData.p]
          readonly property color ink: chosen ? "#ffffff" : Theme.text
          width: table.width - 16; height: 30; radius: 7
          color: chosen ? Theme.accent : (rh.hovered ? Theme.hover : (index % 2 ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.025) : Qt.rgba(0, 0, 0, 0.022)) : "transparent"))
          HoverHandler { id: rh }
          TapHandler {
            id: rowTap
            onTapped: app.select(row.modelData.p, rowTap.point.modifiers)
            onDoubleTapped: app.enter(row.modelData)
          }
          TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: ev => {
              if (!row.chosen) app.select(row.modelData.p, 0)
              menu.show(row, ev.position, row.modelData)
            }
          }
          DragHandler {
            target: null
            dragThreshold: 8
            onActiveChanged: if (active && !app.job) {
              if (!row.chosen) app.select(row.modelData.p, 0)
              app.dragOut(app.selected)
            }
          }
          Row {
            x: 12; height: parent.height
            Item {
              width: head.cName; height: parent.height
              Image {
                id: ic
                width: 18; height: 18; sourceSize: Qt.size(36, 36)
                anchors.verticalCenter: parent.verticalCenter
                source: app.iconFor(row.modelData)
                asynchronous: true
              }
              Txt {
                anchors { left: ic.right; leftMargin: 8; right: lock.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                text: row.modelData.n
                color: row.ink
              }
              Sym {
                id: lock
                visible: row.modelData.e
                width: visible ? 11 : 0; height: 11
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                name: "lock"; color: row.chosen ? "#ffffff" : Theme.textDim
              }
            }
            Txt { width: head.cKind; visible: width > 0; text: app.kindName(row.modelData); color: row.chosen ? Qt.rgba(1, 1, 1, 0.85) : Theme.textDim; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
            Txt { width: head.cSize; horizontalAlignment: Text.AlignRight; text: row.modelData.dir && row.modelData.s === 0 ? "—" : app.human(row.modelData.s); color: row.ink; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
            Txt { width: head.cPacked; visible: width > 0; horizontalAlignment: Text.AlignRight; text: row.modelData.k > 0 ? app.human(row.modelData.k) : "—"; color: row.chosen ? Qt.rgba(1, 1, 1, 0.85) : Theme.textDim; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
            Txt { width: head.cDate; horizontalAlignment: Text.AlignRight; text: app.dateText(row.modelData.m); color: row.chosen ? Qt.rgba(1, 1, 1, 0.85) : Theme.textDim; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
          }
        }

        Txt {
          anchors.centerIn: parent
          visible: table.count === 0 && !app.loading
          text: app.query ? "Nothing called “" + app.query + "” in this archive." : "This folder is empty."
          color: Theme.textFaint
        }
      }
    }

    // ------------------------------------------------------------ nothing open yet
    Item {
      id: welcome
      anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: parent.bottom }
      visible: !app.hasArchive && !app.loading

      ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 520)
        spacing: 0

        Image {
          Layout.alignment: Qt.AlignHCenter
          width: 112; height: 112
          Layout.preferredWidth: 112; Layout.preferredHeight: 112
          sourceSize: Qt.size(224, 224)
          source: Quickshell.iconPath("memora-archive", "package-x-generic")
        }
        Txt { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 14; text: "Archives"; font.pixelSize: 24; font.weight: Font.Bold }
        Txt {
          Layout.fillWidth: true; Layout.topMargin: 6
          horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; elide: Text.ElideNone
          text: "Open zip, rar, 7z, tar, iso and dozens more. Drop an archive here to look inside, or drop files and folders to make one."
          color: Theme.textDim
        }

        // The drop zone.
        Rectangle {
          Layout.fillWidth: true; Layout.topMargin: 22
          Layout.preferredHeight: 128
          radius: 18
          color: drop.containsDrag ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : Theme.field
          border.width: 1.5
          border.color: drop.containsDrag ? Theme.accent : Theme.separator
          Behavior on color { ColorAnimation { duration: Theme.fast } }
          Column {
            anchors.centerIn: parent
            spacing: 8
            Sym { anchors.horizontalCenter: parent.horizontalCenter; name: "download"; width: 26; height: 26; color: drop.containsDrag ? Theme.accent : Theme.textDim }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: drop.containsDrag ? "Let go to " + (drop.allArchives ? "open it" : "compress") : "Drop here"; color: drop.containsDrag ? Theme.accent : Theme.textDim; font.weight: Font.Medium }
          }
          TapHandler { onTapped: openDialog.open() }
        }

        // Recently opened archives that are still there.
        Txt { visible: recentList.count > 0; Layout.topMargin: 22; text: "Recent"; color: Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.DemiBold }
        Column {
          Layout.fillWidth: true; Layout.topMargin: 6
          Repeater {
            id: recentList
            model: app.recents.slice(0, 5)
            delegate: Rectangle {
              required property var modelData
              width: parent.width; height: 34; radius: 8
              color: recH.hovered ? Theme.hover : "transparent"
              Image { id: ri; x: 10; width: 20; height: 20; sourceSize: Qt.size(40, 40); anchors.verticalCenter: parent.verticalCenter; source: Quickshell.iconPath("package-x-generic") }
              Txt { anchors { left: ri.right; leftMargin: 10; right: rp.left; rightMargin: 10; verticalCenter: parent.verticalCenter } text: app.baseName(modelData) }
              Txt { id: rp; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } width: Math.min(implicitWidth, parent.width * 0.5); text: app.pretty(app.dirName(modelData)); color: Theme.textFaint; font.pixelSize: Theme.small; elide: Text.ElideMiddle }
              HoverHandler { id: recH }
              TapHandler { onTapped: app.openArchive(modelData) }
            }
          }
        }
      }
    }

    // Opening (a big archive takes a moment to read).
    Column {
      anchors.centerIn: parent
      visible: app.loading && !app.hasArchive
      spacing: 12
      Spinner { anchors.horizontalCenter: parent.horizontalCenter }
      Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Opening “" + app.baseName(app.archive) + "”…"; color: Theme.textDim }
    }

    // ------------------------------------------------------------ status bar
    Rectangle {
      id: status
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: app.hasArchive ? 30 : 0
      visible: app.hasArchive
      color: Theme.dark ? Qt.rgba(1, 1, 1, 0.025) : Qt.rgba(0, 0, 0, 0.02)
      Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.separator }
      Txt {
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter; right: badges.left; rightMargin: 12 }
        color: Theme.textDim; font.pixelSize: Theme.small
        text: {
          if (!app.hasArchive) return ""
          const n = app.selected.length
          if (n) {
            const chosen = app.entries.filter(e => app.sel[e.p])
            return n + " of " + app.shown.length + " selected · " + app.human(chosen.reduce((a, e) => a + e.s, 0))
          }
          return app.shown.length + (app.shown.length === 1 ? " item" : " items") + (app.loading ? " · reading…" : "")
        }
      }
      Row {
        id: badges
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 6
        Badge { visible: !!app.info && app.info.encrypted; text: "Encrypted"; sym: "lock" }
        Badge { visible: !!app.info && app.info.multi; text: "In parts" }
        Badge { visible: !!app.info && app.info.solid; text: "Solid" }
        Badge { visible: !!app.info && !app.info.writable; text: "Read-only" }
        Badge { visible: !!app.info; text: app.info ? app.typeLabel(app.info.type) : "" }
      }
    }

    // ------------------------------------------------------------ dropping in
    DropArea {
      id: drop
      anchors.fill: parent
      keys: ["text/uri-list"]
      enabled: !app.draggingOut && !app.job
      property bool allArchives: false
      onEntered: ev => {
        if (!ev.hasUrls || app.draggingOut) { ev.accepted = false; return }
        allArchives = ev.urls.length > 0 && ev.urls.every(u => app.isArchive(String(u)))
      }
      onDropped: ev => {
        const files = ev.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))).filter(f => f.startsWith("/"))
        if (!files.length) return
        ev.accept(Qt.CopyAction)
        if (!app.hasArchive) {
          if (files.length === 1 && app.isArchive(files[0])) app.openArchive(files[0])
          else app.newArchive(files)
        } else if (app.info.writable) app.addFiles(files)
        else if (files.length === 1 && app.isArchive(files[0])) app.openArchive(files[0])
        else app.newArchive(files)
      }
    }
    // Over the open archive: what a drop will do.
    Rectangle {
      anchors { fill: browser; margins: 6 }
      visible: drop.containsDrag && app.hasArchive
      radius: 14
      color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
      border.width: 2; border.color: Theme.accent
      Glass {
        anchors.centerIn: parent
        width: dropLabel.implicitWidth + 36; height: 38; radius: 19
        fill: Theme.popover
        Txt {
          id: dropLabel
          anchors.centerIn: parent
          font.weight: Font.Medium
          text: app.info && app.info.writable ? "Add to " + (app.cwd ? "“" + app.baseName(app.cwd) + "”" : "“" + app.baseName(app.archive) + "”")
              : (drop.allArchives ? "Open this archive" : "Make a new archive")
        }
      }
    }

    // The thing dragged out: its files come out of the archive meanwhile.
    Item {
      id: dout
      width: 1; height: 1
      property var uris: []
      Drag.dragType: Drag.Automatic
      Drag.supportedActions: Qt.CopyAction
      Drag.mimeData: ({ "text/uri-list": uris.join("\r\n") + "\r\n" })
      Drag.onDragFinished: { Drag.active = false; app.draggingOut = false }
    }

    // ------------------------------------------------------------ right-click menu
    Item {
      anchors.fill: parent
      visible: menu.open
      z: 40
      TapHandler { acceptedButtons: Qt.AllButtons; onTapped: ev => { if (!app.inside(menu, win.contentItem, ev.position)) menu.open = false } }
    }
    MenuPanel {
      id: menu
      property bool open: false
      z: 41
      visible: open
      opacity: open ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.fast } }
      function show(item, pos, entry) {
        const p = item.mapToItem(win.contentItem, pos.x, pos.y)
        const files = app.selected
        const writable = app.info && app.info.writable
        items = entry ? [
          { text: entry.dir && files.length === 1 ? "Open Folder" : "Open", action: () => { if (entry.dir && files.length === 1) app.enter(entry); else app.openItems(files.filter(f => !(app.entries.find(e => e.p === f) || {}).dir)) } },
          { separator: true },
          { text: "Extract To…", keys: "Ctrl E", action: () => app.askExtract(files) },
          { text: "Extract Next to the Archive", keys: "Ctrl Shift E", action: () => app.extractHere(files) },
          { separator: true },
          { text: "Copy Name", action: () => Quickshell.execDetached(["wl-copy", "--", files.map(app.baseName).join("\n")]) },
          { text: "Delete from Archive", keys: "Delete", enabled: !!writable, action: () => app.removeSelected() }
        ] : [
          { text: "Extract All To…", keys: "Ctrl E", action: () => app.askExtract([]) },
          { text: "Extract All Next to the Archive", action: () => app.extractHere([]) },
          { separator: true },
          { text: writable ? "Add Files…" : "New Archive with More Files…", action: () => { filesDialog.forAdd = true; filesDialog.open() } },
          { text: "Check for Damage", keys: "Ctrl T", action: () => app.test() },
          { text: "Get Info", keys: "Ctrl I", action: () => app.sheet = "info" },
          { separator: true },
          { text: "Show in Files", action: () => Quickshell.execDetached(["memora-files", app.dirName(app.archive)]) }
        ]
        x = Math.min(p.x, win.width - implicitWidth - 8)
        y = Math.min(p.y, win.height - implicitHeight - 8)
        width = implicitWidth; height = implicitHeight
        open = true
      }
      onPicked: item => { open = false; if (item.action) item.action() }
    }

    // ------------------------------------------------------------ sheets
    // Extract: where to.
    Sheet {
      name: "extract"
      title: app.extractItems.length ? "Extract " + (app.extractItems.length === 1 ? "“" + app.baseName(app.extractItems[0]) + "”" : app.extractItems.length + " items") : "Extract “" + app.baseName(app.archive) + "”"
      Txt { text: "Extract to"; color: Theme.textDim; font.pixelSize: Theme.small }
      Place { Layout.fillWidth: true; path: app.destDir; onChange: { folderDialog.target = "extract"; folderDialog.open() } }
      Row {
        spacing: 6
        Repeater {
          model: [["Next to the archive", app.dirName(app.archive)], ["Downloads", app.home + "/Downloads"], ["Desktop", app.home + "/Desktop"]]
          delegate: Pill {
            required property var modelData
            small: true
            text: modelData[0]
            selected: app.destDir === modelData[1]
            onClicked: app.destDir = modelData[1]
          }
        }
      }
      Check { Layout.topMargin: 4; text: "Show in Files when done"; checked: app.showWhenDone; onToggled: app.showWhenDone = !app.showWhenDone }
      Buttons {
        Pill { text: "Cancel"; onClicked: app.sheet = "" }
        Pill { text: "Extract"; primary: true; onClicked: app.extractNow() }
      }
    }

    // A password, asked when it's needed.
    Sheet {
      id: passSheet
      name: "password"
      cardWidth: 380
      title: app.passWrong ? "That password isn't right" : "“" + app.baseName(app.archive) + "” is locked"
      subtitle: app.passWrong ? "Check it and type it again: capitals count." : "Type the password it was made with."
      onShownChanged: if (shown) { passField.text = ""; passField.grab() }
      Field {
        id: passField
        Layout.fillWidth: true
        secret: true
        placeholder: "Password"
        bad: app.passWrong
        onAccepted: passOk.clicked()
      }
      Buttons {
        Pill { text: "Cancel"; onClicked: { app.sheet = ""; if (!app.info) app.archive = "" } }
        Pill {
          id: passOk
          text: "Unlock"; primary: true; on: passField.text !== ""
          onClicked: {
            if (!passField.text) return
            app.password = passField.text
            app.sheet = ""
            const then = app.afterPassword
            app.afterPassword = null
            if (then) then()
          }
        }
      }
    }

    // A new archive: name, kind, how small, a password, in parts.
    Sheet {
      name: "create"
      cardWidth: 500
      title: "New Archive"
      subtitle: app.createFiles.length === 1 ? "With “" + app.baseName(app.createFiles[0]) + "”" : "With " + app.createFiles.length + " items"
      onShownChanged: if (shown) nameField.grab()
      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Field { id: nameField; Layout.fillWidth: true; text: app.cName; onTextChanged: app.cName = text; onAccepted: app.createNow() }
        Txt { text: app.cExt; color: Theme.textDim }
      }
      Label { text: "Format" }
      Seg {
        Layout.fillWidth: true
        stretch: true
        options: app.formats.map(f => [f[0], f[1]])
        value: app.cFormat
        onPicked: v => { if (v === "rar" && !app.caps.rar) { app.sheet = "getrar"; return } app.cFormat = v }
      }
      Txt {
        Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone
        color: Theme.textFaint; font.pixelSize: Theme.small
        text: ({ "zip": "Opens everywhere: Windows, Mac, phones.", "7z": "Smallest files. Opens with 7-Zip, WinRAR and here.",
          "rar": app.caps.rar ? "WinRAR's own format, made with RARLAB's rar." : "WinRAR's own format. Needs RAR from rarlab.com (one click).",
          "tar.gz": "Linux and Mac classic. No password.", "tar.xz": "Small, slower to make. No password.",
          "tar.zst": "Fast and small (Zstandard). No password." })[app.cFormat] || ""
      }
      Label { text: "Compression" }
      Seg {
        Layout.fillWidth: true
        stretch: true
        options: [[0, "Store"], [1, "Fast"], [5, "Normal"], [7, "Best"], [9, "Ultra"]]
        value: app.cLevel
        onPicked: v => app.cLevel = v
      }
      Label { text: "Password" }
      RowLayout {
        Layout.fillWidth: true
        spacing: 12
        opacity: app.cCanLock ? 1 : 0.4
        Field { id: cpw; Layout.fillWidth: true; secret: true; placeholder: app.cCanLock ? "None" : "Not for tar"; enabled: app.cCanLock; text: app.cPass; onTextChanged: app.cPass = text }
        Check { text: "Hide file names"; enabled: app.cCanLock && app.cFormat !== "zip" && app.cPass !== ""; checked: app.cHide && enabled; onToggled: app.cHide = !app.cHide }
      }
      Label { text: "Split into parts" }
      Seg {
        Layout.fillWidth: true
        stretch: true
        options: [[0, "Off"], [25e6, "25 MB"], [100e6, "100 MB"], [700e6, "700 MB"], [4e9, "4 GB"]]
        value: app.cSplit
        onPicked: v => app.cSplit = v
      }
      Label { text: "Save in" }
      Place { Layout.fillWidth: true; path: app.cDest; onChange: { folderDialog.target = "create"; folderDialog.open() } }
      Buttons {
        Pill { text: "Cancel"; onClicked: app.sheet = "" }
        Pill { text: "Create"; primary: true; on: app.cName.trim() !== ""; onClicked: app.createNow() }
      }
    }

    // RAR, from RARLAB.
    Sheet {
      name: "getrar"
      cardWidth: 420
      title: "Get RAR"
      subtitle: "Making RAR archives needs rar, WinRAR's own tool for Linux, from RARLAB (rarlab.com). Archives downloads it for you; opening RAR archives works without it."
      Buttons {
        Pill { text: "Not Now"; onClicked: app.sheet = app.createFiles.length ? "create" : "" }
        Pill { text: "Get RAR"; primary: true; sym: "download"; onClicked: app.getRar() }
      }
    }

    // About the archive.
    Sheet {
      name: "info"
      cardWidth: 420
      title: app.hasArchive ? app.baseName(app.archive) : ""
      subtitle: app.hasArchive ? app.pretty(app.dirName(app.archive)) : ""
      GridLayout {
        Layout.fillWidth: true
        columns: 2; columnSpacing: 16; rowSpacing: 7
        InfoRow { label: "Kind"; value: app.info ? app.typeLabel(app.info.type) + (app.info.method ? " · " + app.info.method : "") : "" }
        InfoRow { label: "Contains"; value: app.info ? app.info.files + (app.info.files === 1 ? " file" : " files") + (app.info.folders ? ", " + app.info.folders + (app.info.folders === 1 ? " folder" : " folders") : "") : "" }
        InfoRow { label: "Unpacked"; value: app.info ? app.human(app.info.size) : "" }
        InfoRow { label: "On disk"; value: app.info ? app.human(app.info.disk) + (app.info.volumes > 1 ? " in " + app.info.volumes + " parts" : "") : "" }
        InfoRow { label: "Encrypted"; value: app.info && app.info.encrypted ? "Yes" : "No" }
        InfoRow { label: "Solid"; value: app.info && app.info.solid ? "Yes" : "No" }
        InfoRow { label: "Can change"; value: app.info && app.info.writable ? "Yes: add and delete files" : "No (read-only)" }
      }
      // How much smaller it is.
      Rectangle {
        Layout.fillWidth: true; Layout.topMargin: 6
        height: 8; radius: 4
        color: Theme.field
        Rectangle {
          width: parent.width * Math.max(0.02, Math.min(1, app.info && app.info.size ? app.info.disk / app.info.size : 1)); height: parent.height; radius: 4
          color: Theme.accent
        }
      }
      Txt { text: app.ratio > 0.005 ? Math.round(app.ratio * 100) + "% smaller than its files" : "About as big as its files"; color: Theme.textDim; font.pixelSize: Theme.small }
      Txt { visible: !!app.info && app.info.comment !== ""; Layout.fillWidth: true; Layout.topMargin: 4; text: app.info ? app.info.comment : ""; wrapMode: Text.Wrap; elide: Text.ElideNone; color: Theme.textDim; font.family: Theme.mono; font.pixelSize: Theme.small }
      Buttons { Pill { text: "Done"; primary: true; onClicked: app.sheet = "" } }
    }

    // ------------------------------------------------------------ working on it
    Item {
      anchors.fill: parent
      visible: !!app.job
      z: 60
      Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.3 : 0.14) }
      TapHandler {}
      Glass {
        anchors.centerIn: parent
        width: 420; height: pcol.implicitHeight + 40
        radius: 20
        fill: Theme.popover
        ColumnLayout {
          id: pcol
          x: 20; y: 20; width: parent.width - 40
          spacing: 10
          Txt { Layout.fillWidth: true; text: app.job ? app.job.title : ""; font.weight: Font.Bold }
          Rectangle {
            Layout.fillWidth: true; height: 6; radius: 3
            color: Theme.field
            clip: true
            Rectangle {
              visible: !!app.job && app.job.pct > 0
              width: parent.width * (app.job ? Math.min(1, app.job.pct / 100) : 0); height: parent.height; radius: 3
              color: Theme.accent
              Behavior on width { NumberAnimation { duration: 200 } }
            }
            // Before the first number comes: a light that runs along.
            Rectangle {
              id: runner
              visible: !!app.job && app.job.pct <= 0
              width: parent.width * 0.3; height: parent.height; radius: 3
              color: Theme.accent; opacity: 0.7
              SequentialAnimation on x {
                running: !!app.job && app.job.pct <= 0; loops: Animation.Infinite
                NumberAnimation { from: -runner.width; to: pcol.width; duration: 1100; easing.type: Easing.InOutSine }
              }
            }
          }
          RowLayout {
            Layout.fillWidth: true
            Txt { Layout.fillWidth: true; text: app.job && app.job.file ? app.job.file : " "; color: Theme.textFaint; font.pixelSize: Theme.small; elide: Text.ElideMiddle }
            Txt { text: app.job && app.job.pct > 0 ? Math.floor(app.job.pct) + "%" : ""; color: Theme.textDim; font.pixelSize: Theme.small; font.features: { "tnum": 1 } }
          }
          Buttons { Pill { text: "Stop"; onClicked: app.cancel() } }
        }
      }
    }

    // ------------------------------------------------------------ done / went wrong
    Glass {
      id: toastCard
      anchors.horizontalCenter: parent.horizontalCenter
      y: app.toast ? parent.height - height - (app.hasArchive ? 44 : 20) : parent.height + 10
      Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Theme.easingEmph } }
      z: 70
      visible: y < parent.height
      width: Math.min(parent.width - 40, trow.implicitWidth + 28); height: 40; radius: 20
      fill: Theme.popover
      RowLayout {
        id: trow
        anchors { fill: parent; leftMargin: 14; rightMargin: 8 }
        spacing: 10
        Rectangle {
          width: 18; height: 18; radius: 9
          color: app.toast && app.toast.error ? Theme.red : Theme.green
          Sym { anchors.centerIn: parent; width: 10; height: 10; name: app.toast && app.toast.error ? "close" : "check"; color: "#ffffff"; stroke: 2.2 }
        }
        Txt { Layout.fillWidth: true; Layout.maximumWidth: 560; text: app.toast ? app.toast.text : "" }
        Pill { visible: !!app.toast && app.toast.path !== ""; small: true; text: "Show"; onClicked: { Quickshell.execDetached(["memora-files", app.dirName(app.toast.path)]); app.toast = null } }
        Tool { sym: "close"; on: true; onClicked: app.toast = null }
      }
    }

    ConfirmSheet { id: confirm }
  }

  // ================================================================ pieces
  // A toolbar symbol button.
  component Tool: Rectangle {
    id: tb
    property string sym
    property string tip: ""
    property bool on: true
    property bool flip: false
    signal clicked()
    width: 30; height: 28; radius: 8
    color: th.hovered && on ? Theme.hover : "transparent"
    opacity: on ? 1 : 0.35
    Sym { anchors.centerIn: parent; name: tb.sym; width: 15; height: 15; rotation: tb.flip ? 180 : 0 }
    HoverHandler { id: th }
    TapHandler { onTapped: if (tb.on) tb.clicked() }
    Tip { text: tb.tip }
  }
  // A text button; primary in the accent.
  component Pill: Rectangle {
    id: pb
    property string text
    property string sym: ""
    property bool primary: false
    property bool selected: false
    property bool small: false
    property bool on: true
    signal clicked()
    width: pr.implicitWidth + (small ? 18 : 26); height: small ? 24 : 28; radius: small ? 12 : 8
    opacity: on ? 1 : 0.45
    color: primary ? (ph.hovered && on ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
         : selected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
         : (ph.hovered && on ? Theme.pressed : Theme.hover)
    border.color: selected ? Theme.accent : "transparent"
    Row {
      id: pr
      anchors.centerIn: parent
      spacing: 6
      Sym { visible: pb.sym !== ""; name: pb.sym; width: 13; height: 13; color: pb.primary ? "#ffffff" : Theme.text; anchors.verticalCenter: parent.verticalCenter }
      Txt { text: pb.text; color: pb.primary ? "#ffffff" : (pb.selected ? Theme.accent : Theme.text); font.weight: pb.primary ? Font.DemiBold : Font.Normal; font.pixelSize: pb.small ? Theme.small + 0.5 : Theme.fontSize; anchors.verticalCenter: parent.verticalCenter }
    }
    HoverHandler { id: ph }
    TapHandler { onTapped: if (pb.on) pb.clicked() }
  }
  component Crumb: Rectangle {
    id: cb
    property string label
    property string icon
    property bool current: false
    signal clicked()
    height: 24; anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: cr.implicitWidth + 14; radius: 6
    color: ch.hovered && !current ? Theme.hover : "transparent"
    Row {
      id: cr
      anchors.centerIn: parent
      spacing: 6
      Image { width: 15; height: 15; sourceSize: Qt.size(30, 30); source: cb.icon; anchors.verticalCenter: parent.verticalCenter }
      Txt { text: cb.label; font.pixelSize: Theme.small + 0.5; font.weight: cb.current ? Font.DemiBold : Font.Normal; color: cb.current ? Theme.text : Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
    }
    HoverHandler { id: ch }
    TapHandler { onTapped: cb.clicked() }
  }
  component Head: Item {
    id: hd
    property string key
    property string label
    property bool alignRight: false
    height: parent ? parent.height : 26
    Row {
      anchors { verticalCenter: parent.verticalCenter; right: hd.alignRight ? parent.right : undefined; left: hd.alignRight ? undefined : parent.left; rightMargin: 0 }
      spacing: 4
      layoutDirection: hd.alignRight ? Qt.RightToLeft : Qt.LeftToRight
      Txt { text: hd.label; color: app.sortKey === hd.key ? Theme.text : Theme.textDim; font.pixelSize: Theme.small; font.weight: app.sortKey === hd.key ? Font.DemiBold : Font.Normal }
      Sym { visible: app.sortKey === hd.key; name: "chevron"; width: 9; height: 9; rotation: app.asc ? 90 : -90; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
    }
    TapHandler { onTapped: { if (app.sortKey === hd.key) app.asc = !app.asc; else { app.sortKey = hd.key; app.asc = hd.key === "name" || hd.key === "kind" } } }
  }
  component Badge: Rectangle {
    id: bd
    property string text
    property string sym: ""
    height: 18; radius: 9
    width: br.implicitWidth + 14
    color: Theme.field
    Row {
      id: br
      anchors.centerIn: parent
      spacing: 4
      Sym { visible: bd.sym !== ""; name: bd.sym; width: 9; height: 9; color: Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
      Txt { text: bd.text; color: Theme.textDim; font.pixelSize: Theme.small - 1; font.weight: Font.Medium }
    }
  }
  // A sheet over the window: a title, what it asks, its buttons.
  component Sheet: Item {
    id: sh
    property string name
    property string title
    property string subtitle
    property real cardWidth: 440
    readonly property bool shown: app.sheet === name
    default property alias body: col.data
    anchors.fill: parent
    z: 50
    visible: shown || fadeOut.running
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.18)
      opacity: sh.shown ? 1 : 0
      Behavior on opacity { NumberAnimation { id: fadeOut; duration: Theme.fast } }
      // Handlers don't stop at the card above: only a tap beside the card closes the sheet.
      TapHandler { enabled: !app.picking; onTapped: ev => { if (!app.inside(card, sh, ev.position)) app.sheet = "" } }
    }
    Glass {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      y: sh.shown ? Math.max(20, (parent.height - height) * 0.38) : Math.max(20, (parent.height - height) * 0.38) - 16
      opacity: sh.shown ? 1 : 0
      scale: sh.shown ? 1 : 0.97
      Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Theme.easingEmph } }
      Behavior on opacity { NumberAnimation { duration: Theme.fast } }
      Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Theme.easingEmph } }
      width: Math.min(sh.cardWidth, sh.width - 32); height: col.implicitHeight + 44
      radius: 22
      fill: Theme.popover
      TapHandler {}
      ColumnLayout {
        id: col
        x: 22; y: 22; width: parent.width - 44
        spacing: 10
        Txt { Layout.fillWidth: true; text: sh.title; font.pixelSize: Theme.large; font.weight: Font.Bold }
        Txt { Layout.fillWidth: true; Layout.topMargin: -4; visible: sh.subtitle !== ""; text: sh.subtitle; color: Theme.textDim; wrapMode: Text.Wrap; elide: Text.ElideNone; font.pixelSize: Theme.small + 0.5 }
      }
    }
  }
  component Buttons: RowLayout {
    Layout.fillWidth: true
    Layout.topMargin: 8
    spacing: 8
    Item { Layout.fillWidth: true }
  }
  component Label: Txt { Layout.topMargin: 4; color: Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Medium }
  component Field: Rectangle {
    id: fd
    property alias text: ti.text
    property string placeholder: ""
    property bool secret: false
    property bool bad: false
    signal accepted()
    function grab() { ti.forceActiveFocus(); ti.selectAll() }
    implicitHeight: 30; radius: 8
    color: Theme.field
    border.color: bad ? Theme.red : (ti.activeFocus ? Theme.accent : Theme.separator)
    TextInput {
      id: ti
      anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize
      echoMode: fd.secret ? TextInput.Password : TextInput.Normal
      passwordCharacter: "•"
      selectByMouse: true
      enabled: fd.enabled
      onAccepted: fd.accepted()
      Txt { visible: !ti.text; text: fd.placeholder; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
    }
  }
  // Segmented choice: options [[value, label], …].
  component Seg: Rectangle {
    id: sg
    property var options: []
    property var value
    property bool stretch: false
    signal picked(var v)
    implicitHeight: 30
    implicitWidth: sgRow.implicitWidth + 4
    radius: 8
    color: Theme.field
    border.color: Theme.separator
    Row {
      id: sgRow
      anchors.centerIn: parent
      Repeater {
        model: sg.options
        delegate: Rectangle {
          required property var modelData
          readonly property bool on: sg.value === modelData[0]
          width: sg.stretch ? (sg.width - 4) / sg.options.length : Math.max(54, sgt.implicitWidth + 22)
          height: 26; radius: 6
          color: on ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.18) : "#ffffff") : (sgh.hovered ? Theme.hover : "transparent")
          Behavior on color { ColorAnimation { duration: Theme.fast } }
          Txt { id: sgt; anchors.centerIn: parent; text: modelData[1]; font.pixelSize: Theme.small + 0.5; font.weight: parent.on ? Font.DemiBold : Font.Normal }
          HoverHandler { id: sgh }
          TapHandler { onTapped: sg.picked(modelData[0]) }
        }
      }
    }
  }
  component Check: Row {
    id: ck
    property bool checked: false
    property string text
    signal toggled()
    spacing: 8
    opacity: enabled ? 1 : 0.4
    Rectangle {
      width: 16; height: 16; radius: 5
      anchors.verticalCenter: parent.verticalCenter
      color: ck.checked ? Theme.accent : Theme.field
      border.color: ck.checked ? Theme.accent : Theme.separator
      Sym { anchors.centerIn: parent; name: "check"; width: 10; height: 10; color: "#ffffff"; stroke: 2.2; visible: ck.checked }
    }
    Txt { text: ck.text; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.small + 0.5 }
    TapHandler { enabled: ck.enabled; onTapped: ck.toggled() }
  }
  // A folder, and Change… to pick another.
  component Place: Rectangle {
    id: pl
    property string path
    signal change()
    implicitHeight: 36; radius: 9
    color: Theme.field
    border.color: Theme.separator
    Image { id: pli; x: 10; width: 18; height: 18; sourceSize: Qt.size(36, 36); anchors.verticalCenter: parent.verticalCenter; source: Quickshell.iconPath("folder") }
    Txt { anchors { left: pli.right; leftMargin: 8; right: plb.left; rightMargin: 8; verticalCenter: parent.verticalCenter } text: app.pretty(pl.path); elide: Text.ElideMiddle }
    Pill { id: plb; small: true; text: "Change…"; anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter } onClicked: pl.change() }
  }
  component InfoRow: Item {
    property string label
    property string value
    Layout.columnSpan: 2
    Layout.fillWidth: true
    implicitHeight: 18
    Txt { width: 96; text: parent.label; color: Theme.textDim; font.pixelSize: Theme.small + 0.5; horizontalAlignment: Text.AlignRight }
    Txt { x: 108; width: parent.width - 108; text: parent.value; font.pixelSize: Theme.small + 0.5 }
  }
  component Spinner: Canvas {
    width: 28; height: 28
    property real a: 0
    NumberAnimation on a { from: 0; to: Math.PI * 2; duration: 900; loops: Animation.Infinite; running: true }
    onAChanged: requestPaint()
    onPaint: {
      const ctx = getContext("2d"); ctx.reset()
      ctx.lineWidth = 3; ctx.lineCap = "round"
      ctx.strokeStyle = Theme.separator
      ctx.beginPath(); ctx.arc(14, 14, 11, 0, Math.PI * 2); ctx.stroke()
      ctx.strokeStyle = Theme.accent
      ctx.beginPath(); ctx.arc(14, 14, 11, a, a + 1.6); ctx.stroke()
    }
  }
}
