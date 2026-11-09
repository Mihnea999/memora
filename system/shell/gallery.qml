//@ pragma UseQApplication
//@ pragma AppId memora-photos
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui

// Gallery: your photos and videos, like the gallery on a phone. Library shows
// everything newest first under the month it was taken; Albums groups them by
// folder (Screenshots among them), plus Videos and Favourites. A tap opens one full size:
// pictures zoom (scroll, pinch, double-click), videos play right there; the
// arrow keys go to the next and previous. Run as `memora-photos [FILE]`.
ShellRoot {
  id: app
  readonly property string home: Quickshell.env("HOME")
  readonly property var imageExt: ["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg", "tif", "tiff", "avif", "heic", "jxl"]
  readonly property var videoExt: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "mpg", "mpeg", "3gp"]
  function isVideo(p) { return videoExt.indexOf(String(p).split(".").pop().toLowerCase()) >= 0 }

  // ---- the library ----------------------------------------------------------------
  // Every picture and video in Pictures and Videos (and their folders) and in
  // Downloads, newest first: [{ path, video, time, album }]
  property var all: []
  property bool loaded: false
  property var favs: ({})            // path -> true
  property var thumbs: ({})          // video path -> { img, dur }
  property string tab: "library"     // library | albums
  property string album: ""          // "" everything, else an album id
  property var shown: []             // what the grid and the viewer go through
  property int open: -1              // index in `shown` of the one open full size, -1 none

  readonly property var albums: {
    const m = {}, order = []
    const add = (id, name, it) => { if (!m[id]) { m[id] = { id: id, name: name, cover: it, count: 0 }; order.push(id) } m[id].count++ }
    all.forEach(it => {
      // (videos straight in ~/Videos are the Videos album already; Screenshots
      // is the folder of that name)
      if (!(it.album === "Videos" && it.video)) add(it.album, it.album, it)
      if (it.video) add("@videos", "Videos", it)
      if (favs[it.path]) add("@favs", "Favourites", it)
    })
    const special = ["@favs", "@videos"].filter(k => m[k]).map(k => m[k])
    return special.concat(order.filter(k => !k.startsWith("@")).map(k => m[k]))
  }
  function inAlbum(it, a) {
    if (!a) return true
    if (a === "@videos") return it.video
    if (a === "@favs") return !!favs[it.path]
    return it.album === a
  }
  function refreshShown() {
    const keep = open >= 0 && shown[open] ? shown[open].path : ""
    shown = all.filter(it => inAlbum(it, album))
    if (keep) { const i = shown.findIndex(it => it.path === keep); open = i }
  }
  onAllChanged: refreshShown()
  onAlbumChanged: refreshShown()
  onFavsChanged: if (album === "@favs") refreshShown()

  Process {
    id: scan
    command: ["bash", "-c",
      "cd ~ || exit 0; exts='" + app.imageExt.concat(app.videoExt).join("|") + "'; " +
      "{ find Pictures Videos -mindepth 1 -name '.*' -prune -o -type f -printf '%T@\\t%p\\n' 2>/dev/null; " +
      "  find Downloads -maxdepth 1 -type f -printf '%T@\\t%p\\n' 2>/dev/null; } " +
      "| grep -iE \"\\.($exts)$\" | sort -rn | head -20000"]
    stdout: StdioCollector {
      onStreamFinished: {
        const list = text.split("\n").filter(l => l).map(l => {
          const tab = l.indexOf("\t"), rel = l.slice(tab + 1)
          const parts = rel.split("/")
          const album = parts.length > 2 ? parts[1] : parts[0]   // Pictures/Trip/x.jpg -> Trip
          const path = app.home + "/" + rel
          return { path: path, video: app.isVideo(path), time: parseFloat(l.slice(0, tab)) * 1000, album: album }
        })
        // Only when something changed, so the grid doesn't jump.
        const same = list.length === app.all.length && list.every((it, i) => it.path === app.all[i].path)
        if (!same) app.all = list
        app.loaded = true
        app.makeThumbs()
        if (app.pendingFile) app.openFile(app.pendingFile)
      }
    }
  }
  function rescan() { if (!scan.running) scan.running = true }
  Component.onCompleted: rescan()
  // New pictures and videos (a screenshot, a download) appear while it's open.
  Timer { interval: 5000; repeat: true; running: win.visible && app.open < 0; onTriggered: app.rescan() }

  // Video thumbnails and lengths, made once with ffmpeg and kept in ~/.cache.
  Process {
    id: thumber
    property var queue: []
    stdout: SplitParser {
      onRead: line => {
        const f = line.split("\t")
        if (f.length < 3) return
        const t = Object.assign({}, app.thumbs); t[f[0]] = { img: f[1], dur: parseFloat(f[2]) || 0 }; app.thumbs = t
      }
    }
    onExited: if (queue.length) app.makeThumbs()
  }
  function makeThumbs() {
    if (thumber.running) return
    const todo = all.filter(it => it.video && !thumbs[it.path]).slice(0, 40).map(it => it.path)
    if (!todo.length) return
    thumber.command = ["bash", "-c",
      "d=~/.cache/memora/gallery; mkdir -p \"$d\"; for f in \"$@\"; do " +
      "h=$(printf '%s' \"$f$(stat -c %Y \"$f\" 2>/dev/null)\" | md5sum | cut -c1-24); t=\"$d/$h.jpg\"; " +
      "[ -s \"$t\" ] || ffmpeg -loglevel error -y -ss 1 -i \"$f\" -frames:v 1 -vf 'scale=480:-2' \"$t\" </dev/null 2>/dev/null || " +
      "ffmpeg -loglevel error -y -i \"$f\" -frames:v 1 -vf 'scale=480:-2' \"$t\" </dev/null 2>/dev/null; " +
      "dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 \"$f\" 2>/dev/null); " +
      "printf '%s\\t%s\\t%s\\n' \"$f\" \"$t\" \"${dur:-0}\"; done", "_"].concat(todo)
    thumber.queue = all.filter(it => it.video && !thumbs[it.path]).slice(40)
    thumber.running = true
  }
  function duration(s) { s = Math.round(s); const m = Math.floor(s / 60); return m + ":" + String(s % 60).padStart(2, "0") }

  // Favourites, kept in ~/.local/share/memora/gallery.json.
  FileView {
    id: favFile
    path: app.home + "/.local/share/memora/gallery.json"
    printErrors: false
    onLoaded: { try { const j = JSON.parse(text()); const f = {}; (j.favourites || []).forEach(p => f[p] = true); app.favs = f } catch (e) {} }
  }
  function toggleFav(p) {
    const f = Object.assign({}, favs)
    if (f[p]) delete f[p]; else f[p] = true
    favs = f
    Quickshell.execDetached(["mkdir", "-p", home + "/.local/share/memora"])
    favFile.setText(JSON.stringify({ favourites: Object.keys(f) }, null, 1) + "\n")
  }

  // ---- opening ---------------------------------------------------------------------
  property string pendingFile: Quickshell.env("MEMORA_PHOTOS_FILE") || ""
  function openFile(p) {
    pendingFile = ""
    let i = shown.findIndex(it => it.path === p)
    if (i < 0) {
      // Not in the library (a file from elsewhere): show it with its folder.
      album = ""
      i = all.findIndex(it => it.path === p)
      if (i < 0) { siblings.target = p; siblings.running = true; return }
      shown = all
    }
    show(i)
  }
  Process {
    id: siblings
    property string target
    command: ["bash", "-c", "d=$(dirname \"$1\"); find \"$d\" -maxdepth 1 -type f -printf '%T@\\t%p\\n' | sort -rn", "_", target]
    stdout: StdioCollector {
      onStreamFinished: {
        const exts = app.imageExt.concat(app.videoExt)
        const list = text.split("\n").filter(l => l).map(l => l.slice(l.indexOf("\t") + 1))
          .filter(p => exts.indexOf(p.split(".").pop().toLowerCase()) >= 0)
          .map(p => ({ path: p, video: app.isVideo(p), time: 0, album: "" }))
        app.shown = list.length ? list : [{ path: siblings.target, video: app.isVideo(siblings.target), time: 0, album: "" }]
        app.show(Math.max(0, app.shown.findIndex(it => it.path === siblings.target)))
      }
    }
  }
  property int dir: 1
  function show(i) {
    if (!shown.length) { open = -1; return }
    const n = (i + shown.length) % shown.length
    dir = n >= open ? 1 : -1
    open = n
    viewer.reset()
  }
  readonly property var current: open >= 0 && open < shown.length ? shown[open] : null
  function close() { open = -1; video.stop(); info = false; rescan() }
  property bool info: false
  property bool chrome: true
  Timer { id: hideChrome; interval: 2600; onTriggered: if (app.current && app.current.video && video.playbackState === MediaPlayer.PlayingState) app.chrome = false }

  Process { id: runner }
  function trash() {
    if (!current) return
    const p = current.path, was = open
    runner.command = ["gio", "trash", "--", p]; runner.running = true
    all = all.filter(it => it.path !== p)
    shown = shown.filter(it => it.path !== p)
    Quickshell.execDetached(["memora-sound", "trash"])
    if (!shown.length) close(); else show(Math.min(was, shown.length - 1))
  }

  IpcHandler {
    target: "photos"
    function open(path: string): void { if (app.loaded) app.openFile(path); else app.pendingFile = path }
  }

  // ---- meta for Info -------------------------------------------------------------------
  property var meta: ({})
  Process {
    id: metaProc
    command: ["bash", "-c", "f=\"$1\"; stat -c '%s|%y' \"$f\"; identify -format '%w|%h\\n' \"$f[0]\" 2>/dev/null | head -1 || ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s='|' \"$f\"", "_", app.current ? app.current.path : ""]
    stdout: StdioCollector { onStreamFinished: { const l = text.trim().split("\n"); const a = (l[0] || "").split("|"), b = (l[1] || "").split("|"); app.meta = { size: Number(a[0]), date: a[1] || "", w: b[0] || "", h: b[1] || "" } } }
  }
  onCurrentChanged: { meta = ({}); if (current && info) metaProc.running = true }
  onInfoChanged: if (info && current) metaProc.running = true
  function human(b) { return b > 1e9 ? (b / 1e9).toFixed(1) + " GB" : b > 1e6 ? (b / 1e6).toFixed(1) + " MB" : Math.round(b / 1e3) + " KB" }
  function monthOf(t) {
    const d = new Date(t), now = new Date()
    const days = Math.floor((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(d.getFullYear(), d.getMonth(), d.getDate())) / 86400000)
    if (days === 0) return "Today"
    if (days === 1) return "Yesterday"
    if (days < 7) return Qt.formatDate(d, "dddd")
    return Qt.formatDate(d, d.getFullYear() === now.getFullYear() ? "MMMM" : "MMMM yyyy")
  }

  MediaPlayer {
    id: video
    source: app.current && app.current.video ? "file://" + app.current.path : ""
    audioOutput: AudioOutput { id: audio; volume: 1 }
    videoOutput: videoOut
    onSourceChanged: if (source != "") play()
  }

  // ---- the window ----------------------------------------------------------------------
  FloatingWindow {
    id: win
    onVisibleChanged: if (!visible) Qt.quit()
    title: app.current ? app.current.path.split("/").pop() : "Gallery"
    implicitWidth: 1180
    implicitHeight: 800
    minimumSize: Qt.size(560, 440)
    color: "transparent"
    Rectangle { anchors.fill: parent; color: app.current ? "#000000" : Theme.window }

    Shortcut { sequence: "Right"; enabled: !!app.current; onActivated: app.show(app.open + 1) }
    Shortcut { sequence: "Left"; enabled: !!app.current; onActivated: app.show(app.open - 1) }
    Shortcut { sequence: "Space"; enabled: !!app.current && app.current.video; onActivated: video.playbackState === MediaPlayer.PlayingState ? video.pause() : video.play() }
    Shortcut { sequence: "Escape"; onActivated: win.visibility === Window.FullScreen ? win.showNormal() : (app.current ? app.close() : (app.album ? app.album = "" : Qt.quit())) }
    Shortcut { sequence: "F"; onActivated: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen() }
    Shortcut { sequence: "I"; enabled: !!app.current; onActivated: app.info = !app.info }
    Shortcut { sequence: "Delete"; enabled: !!app.current; onActivated: app.trash() }
    Shortcut { sequence: "Ctrl+W"; onActivated: Qt.quit() }

    // ==== Library / Albums ====
    Item {
      id: browse
      anchors.fill: parent
      visible: !app.current

      // Header: window buttons, Library | Albums, the count.
      Item {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        WindowControls { x: 18; anchors.verticalCenter: parent.verticalCenter; window: win; onCloseRequested: Qt.quit() }
        Row {
          x: 104; anchors.verticalCenter: parent.verticalCenter
          visible: app.album !== ""
          spacing: 4
          Sym { anchors.verticalCenter: parent.verticalCenter; name: "chevron"; rotation: 180; width: 12; height: 12; color: Theme.accent }
          Txt { text: "Albums"; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
          TapHandler { onTapped: { app.album = ""; app.tab = "albums" } }
          HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
        // The segmented switch, as on a phone.
        Rectangle {
          visible: app.album === ""
          anchors.centerIn: parent
          width: seg.width + 6; height: 32; radius: 16
          color: Theme.field
          Row {
            id: seg; x: 3; anchors.verticalCenter: parent.verticalCenter
            Repeater {
              model: [["library", "Library"], ["albums", "Albums"]]
              delegate: Rectangle {
                required property var modelData
                width: segt.implicitWidth + 36; height: 26; radius: 13
                color: app.tab === modelData[0] ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : "#ffffff") : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Txt { id: segt; anchors.centerIn: parent; text: modelData[1]; font.weight: app.tab === modelData[0] ? Font.Bold : Font.Normal }
                TapHandler { onTapped: app.tab = modelData[0] }
              }
            }
          }
        }
        Txt {
          visible: app.album !== ""
          anchors.centerIn: parent
          text: (app.albums.find(a => a.id === app.album) || {}).name || ""
          font.weight: Font.Bold; font.pixelSize: Theme.large
        }
        Txt {
          anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
          text: app.shown.length ? app.shown.length + (app.shown.length === 1 ? " item" : " items") : ""
          color: Theme.textDim; font.pixelSize: Theme.small
        }
      }

      // ---- Library: a grid under month headings (rows, so it stays quick with thousands)
      ListView {
        id: grid
        visible: app.tab === "library" || app.album !== ""
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; leftMargin: 14; rightMargin: 14 }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        readonly property int cols: Math.max(3, Math.floor(width / 170))
        readonly property real cell: (width - (cols - 1) * 3) / cols
        model: {
          const rows = []
          let label = "", row = null
          app.shown.forEach((it, i) => {
            const l = app.album === "" ? app.monthOf(it.time) : ""
            if (l !== label || !row || row.items.length === grid.cols) {
              if (l !== label) { rows.push({ header: l, items: [] }); label = l }
              row = { header: "", items: [] }; rows.push(row)
            }
            row.items.push(i)
          })
          return rows.filter(r => r.header || r.items.length)
        }
        delegate: Item {
          required property var modelData
          width: grid.width
          height: modelData.header ? 44 : grid.cell + 3
          Txt {
            visible: !!modelData.header
            anchors { left: parent.left; leftMargin: 4; bottom: parent.bottom; bottomMargin: 10 }
            text: modelData.header || ""
            font.pixelSize: Theme.large; font.weight: Font.Bold
          }
          Row {
            visible: !modelData.header
            spacing: 3
            Repeater {
              model: modelData.items || []
              delegate: Tile { required property int modelData; index: modelData; width: grid.cell; height: grid.cell }
            }
          }
        }
        Column {
          anchors.centerIn: parent
          visible: app.loaded && app.shown.length === 0
          spacing: 10
          Sym { anchors.horizontalCenter: parent.horizontalCenter; name: "photo"; width: 48; height: 48; color: Theme.textFaint }
          Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "No photos or videos yet"; font.weight: Font.Bold; font.pixelSize: Theme.large }
          Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Pictures and videos in Pictures, Videos and Downloads show up here."; color: Theme.textDim }
        }
      }

      // ---- Albums
      GridView {
        id: albumGrid
        visible: app.tab === "albums" && app.album === ""
        anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom; leftMargin: 20; rightMargin: 20 }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        readonly property int cols: Math.max(2, Math.floor(width / 210))
        cellWidth: width / cols; cellHeight: cellWidth + 46
        model: app.albums
        delegate: Item {
          required property var modelData
          width: albumGrid.cellWidth; height: albumGrid.cellHeight
          Rectangle {
            id: cover
            x: 6; y: 6; width: parent.width - 12; height: width
            radius: 14; clip: true; color: Theme.field
            scale: ah.hovered ? 1.02 : 1
            Behavior on scale { NumberAnimation { duration: Theme.fast } }
            Image {
              anchors.fill: parent
              fillMode: Image.PreserveAspectCrop; asynchronous: true
              sourceSize: Qt.size(420, 420)
              source: modelData.cover.video ? (app.thumbs[modelData.cover.path] ? "file://" + app.thumbs[modelData.cover.path].img : "") : "file://" + modelData.cover.path
            }
            Sym {
              visible: modelData.id === "@favs" || modelData.id === "@videos"
              anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
              name: modelData.id === "@favs" ? "heart" : "play"; width: 18; height: 18; color: "#ffffff"
            }
          }
          Txt { x: 8; anchors.top: cover.bottom; anchors.topMargin: 6; width: parent.width - 16; text: modelData.name; font.weight: Font.Bold; elide: Text.ElideRight }
          Txt { x: 8; anchors.top: cover.bottom; anchors.topMargin: 24; text: modelData.count; color: Theme.textDim; font.pixelSize: Theme.small }
          HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: app.album = modelData.id }
        }
      }
    }

    // ==== One photo or video, full size ====
    Item {
      id: viewer
      anchors.fill: parent
      visible: !!app.current
      clip: true
      property real zoom: 1
      property real px: 0
      property real py: 0
      function reset() { zoom = 1; px = 0; py = 0 }
      function zoomBy(f) { zoom = Math.max(1, Math.min(12, zoom * f)); if (zoom === 1) { px = 0; py = 0 } }
      Behavior on zoom { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
      HoverHandler { onPointChanged: { app.chrome = true; hideChrome.restart() } }

      AnimatedImage {
        id: img
        visible: !!app.current && !app.current.video
        readonly property real fit: Math.min(viewer.width / Math.max(1, sourceSize.width), viewer.height / Math.max(1, sourceSize.height), 1)
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: viewer.px
        anchors.verticalCenterOffset: viewer.py
        width: sourceSize.width * fit * viewer.zoom
        height: sourceSize.height * fit * viewer.zoom
        source: app.current && !app.current.video ? "file://" + app.current.path : ""
        asynchronous: true; cache: false; smooth: true; mipmap: true
        opacity: 0
        onSourceChanged: { fade.restart(); slide.restart() }
        NumberAnimation { id: fade; target: img; property: "opacity"; from: 0; to: 1; duration: Theme.normal }
        transform: Translate { id: shift }
        NumberAnimation { id: slide; target: shift; property: "x"; from: app.dir * 40; to: 0; duration: Theme.slow; easing.type: Easing.OutCubic }
      }
      Txt { anchors.centerIn: parent; visible: img.visible && img.status === Image.Error; text: "Can't open this picture"; color: "#aaaaaa" }

      VideoOutput {
        id: videoOut
        anchors.fill: parent
        visible: !!app.current && app.current.video
        fillMode: VideoOutput.PreserveAspectFit
        TapHandler { onTapped: video.playbackState === MediaPlayer.PlayingState ? video.pause() : video.play() }
      }
      // A big play button while a video is paused.
      Rectangle {
        visible: videoOut.visible && video.playbackState !== MediaPlayer.PlayingState
        anchors.centerIn: parent
        width: 78; height: 78; radius: 39
        color: Qt.rgba(0, 0, 0, 0.45)
        Sym { anchors.centerIn: parent; anchors.horizontalCenterOffset: 3; name: "play"; width: 30; height: 30; color: "#ffffff" }
        TapHandler { onTapped: video.play() }
      }

      DragHandler {
        target: null; enabled: viewer.zoom > 1 && img.visible
        property real sx; property real sy
        onActiveChanged: if (active) { sx = viewer.px; sy = viewer.py }
        onTranslationChanged: { viewer.px = sx + translation.x; viewer.py = sy + translation.y }
      }
      // Swipe left/right (trackpad or a drag) for the next and previous one.
      DragHandler {
        target: null; enabled: viewer.zoom === 1
        xAxis.enabled: true; yAxis.enabled: false
        onActiveChanged: if (!active && Math.abs(translation.x) > 80) app.show(app.open + (translation.x < 0 ? 1 : -1))
      }
      WheelHandler { enabled: img.visible; onWheel: ev => viewer.zoomBy(ev.angleDelta.y > 0 ? 1.15 : 1 / 1.15) }
      PinchHandler { enabled: img.visible; target: null; onScaleChanged: delta => viewer.zoomBy(delta) }
      TapHandler { enabled: img.visible; onDoubleTapped: viewer.zoom > 1 ? viewer.reset() : viewer.zoomBy(2.5) }

      // Previous / next arrows at the sides.
      Repeater {
        model: [-1, 1]
        delegate: Rectangle {
          required property int modelData
          visible: app.shown.length > 1
          opacity: app.chrome ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Theme.normal } }
          anchors.verticalCenter: parent.verticalCenter
          x: modelData < 0 ? 16 : parent.width - width - 16
          width: 40; height: 40; radius: 20
          color: nh.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.35)
          Sym { anchors.centerIn: parent; name: "chevron"; rotation: modelData < 0 ? 180 : 0; width: 14; height: 14; color: "#ffffff" }
          HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: app.show(app.open + modelData) }
        }
      }

      // Top: back, the date, favourite, info, delete.
      Item {
        id: vtop
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56
        opacity: app.chrome ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.6) }
            GradientStop { position: 1; color: "transparent" }
          }
        }
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        WindowControls { x: 18; anchors.verticalCenter: parent.verticalCenter; window: win; onCloseRequested: Qt.quit() }
        Row {
          x: 104; anchors.verticalCenter: parent.verticalCenter
          spacing: 4
          Sym { anchors.verticalCenter: parent.verticalCenter; name: "chevron"; rotation: 180; width: 12; height: 12; color: "#ffffff" }
          Txt { text: app.album ? ((app.albums.find(a => a.id === app.album) || {}).name || "Back") : "Library"; color: "#ffffff" }
          TapHandler { onTapped: app.close() }
          HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
        Column {
          anchors.centerIn: parent
          Txt { anchors.horizontalCenter: parent.horizontalCenter; color: "#ffffff"; font.weight: Font.Bold
            text: app.current && app.current.time ? Qt.formatDateTime(new Date(app.current.time), "d MMMM yyyy") : (app.current ? app.current.path.split("/").pop() : "") }
          Txt { anchors.horizontalCenter: parent.horizontalCenter; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: Theme.small - 1
            text: app.current && app.current.time ? Qt.formatDateTime(new Date(app.current.time), "HH:mm") + "  ·  " + (app.open + 1) + " of " + app.shown.length : "" }
        }
        Row {
          anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
          spacing: 4
          Tool { sym: "share"; tip: "Share with a device nearby"; onClicked: Quickshell.execDetached(["memora-shell", "share", app.current.path]) }
          Tool { sym: "heart"; on: !!app.current && !!app.favs[app.current.path]; tip: "Favourite"; onClicked: app.toggleFav(app.current.path) }
          Tool { sym: "photo"; visible: !!app.current && !app.current.video; tip: "Use as Wallpaper"; onClicked: { Prefs.set("wallpaper", app.current.path); Quickshell.execDetached(["notify-send", "-a", "Gallery", "-h", "boolean:suppress-sound:true", "-i", app.current.path, "Wallpaper changed", app.current.path.split("/").pop()]) } }
          Tool { sym: "info"; on: app.info; tip: "Info (I)"; onClicked: app.info = !app.info }
          Tool { sym: "trash"; tip: "Move to Trash (Delete)"; onClicked: app.trash() }
        }
      }

      // Video controls at the bottom.
      Rectangle {
        visible: videoOut.visible
        opacity: app.chrome || video.playbackState !== MediaPlayer.PlayingState ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 22 }
        width: Math.min(parent.width - 60, 640); height: 52; radius: 26
        color: Qt.rgba(0.08, 0.08, 0.09, 0.82)
        RowLayout {
          anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
          spacing: 12
          Sym {
            name: video.playbackState === MediaPlayer.PlayingState ? "pause" : "play"; width: 18; height: 18; color: "#ffffff"
            TapHandler { onTapped: video.playbackState === MediaPlayer.PlayingState ? video.pause() : video.play() }
          }
          Txt { text: app.duration(video.position / 1000); color: "#ffffff"; font.pixelSize: Theme.small }
          Item {
            Layout.fillWidth: true; height: 20
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.25) }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * (video.duration ? video.position / video.duration : 0); height: 4; radius: 2; color: "#ffffff" }
            TapHandler { onTapped: ev => video.position = video.duration * ev.position.x / parent.width }
            DragHandler { target: null; onCentroidChanged: if (active) video.position = video.duration * Math.max(0, Math.min(1, centroid.position.x / parent.width)) }
          }
          Txt { text: app.duration(video.duration / 1000); color: "#ffffff"; font.pixelSize: Theme.small }
          Sym {
            name: audio.muted ? "sound-off" : "sound"; width: 16; height: 16; color: "#ffffff"
            TapHandler { onTapped: audio.muted = !audio.muted }
          }
        }
      }

      // Info.
      Glass {
        anchors { right: parent.right; top: vtop.bottom; margins: 12 }
        width: 260; height: infoCol.implicitHeight + 28
        radius: 16
        fill: Theme.glassStrong
        opacity: app.info ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }
        ColumnLayout {
          id: infoCol
          x: 14; y: 14; width: parent.width - 28
          spacing: 8
          Txt { text: app.current ? app.current.path.split("/").pop() : ""; font.weight: Font.Bold; Layout.fillWidth: true; elide: Text.ElideMiddle }
          Repeater {
            model: app.current ? [["Dimensions", app.meta.w ? app.meta.w + " × " + app.meta.h : "…"], ["Size", app.meta.size ? app.human(app.meta.size) : "…"],
                    ["Date", app.meta.date ? app.meta.date.slice(0, 16) : "…"], ["Where", app.current.path.substring(0, app.current.path.lastIndexOf("/")).replace(app.home, "~")]] : []
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              Txt { text: modelData[0]; color: Theme.textDim; font.pixelSize: Theme.small; Layout.preferredWidth: 78 }
              Txt { text: modelData[1]; font.pixelSize: Theme.small; Layout.fillWidth: true; elide: Text.ElideMiddle }
            }
          }
          Txt {
            text: "Show in Files"; color: Theme.accent; font.pixelSize: Theme.small
            TapHandler { onTapped: Quickshell.execDetached(["memora-files", app.current.path.substring(0, app.current.path.lastIndexOf("/"))]) }
          }
        }
      }
    }
  }

  // A square in the grid: the picture (or the video's first frame, with its length).
  component Tile: Item {
    id: tile
    property int index
    readonly property var it: app.shown[index] || ({})
    Rectangle { anchors.fill: parent; color: Theme.field }
    Image {
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      asynchronous: true; cache: true
      sourceSize: Qt.size(360, 360)
      source: tile.it.video ? (app.thumbs[tile.it.path] ? "file://" + app.thumbs[tile.it.path].img : "") : (tile.it.path ? "file://" + tile.it.path : "")
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    }
    Rectangle {
      visible: !!tile.it.video
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: 30
      gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.55) } }
      Sym { x: 7; anchors.verticalCenter: parent.verticalCenter; name: "play"; width: 11; height: 11; color: "#ffffff" }
      Txt {
        anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
        text: app.thumbs[tile.it.path] && app.thumbs[tile.it.path].dur ? app.duration(app.thumbs[tile.it.path].dur) : ""
        color: "#ffffff"; font.pixelSize: Theme.small - 1; font.weight: Font.Bold
      }
    }
    Sym { visible: !!app.favs[tile.it.path]; anchors { left: parent.left; top: parent.top; margins: 7 } name: "heart"; width: 13; height: 13; color: "#ffffff" }
    Rectangle { anchors.fill: parent; color: "#ffffff"; opacity: th.hovered ? 0.08 : 0 }
    HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: app.show(tile.index) }
  }

  component Tool: Rectangle {
    id: tl
    property string sym
    property string tip
    property bool on: false
    signal clicked()
    width: 34; height: 32; radius: 9
    color: th2.hovered ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
    Sym { anchors.centerIn: parent; name: tl.sym; width: 16; height: 16; color: tl.on ? (tl.sym === "heart" ? "#ff4f6d" : Theme.accent) : "#ffffff"; filled: tl.on && tl.sym === "heart" }
    HoverHandler { id: th2 }
    TapHandler { onTapped: tl.clicked() }
    Tip { text: tl.tip }
  }
}
