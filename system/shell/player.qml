//@ pragma UseQApplication
//@ pragma AppId memora-player
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui

// Music: your songs, like Apple Music for the files on this computer. Everything
// in ~/Music (and audio in Downloads) is read by memora-music-scan into albums,
// artists and songs with their covers; Favourites and your playlists live in
// ~/.local/share/memora/music.json. mpv plays (with mpv-mpris, so the media
// keys, the Now Playing widget and Control Center work); this app talks to it
// over its socket. Synced lyrics show when a song has an .lrc file next to it.
ShellRoot {
  id: app
  readonly property string home: Quickshell.env("HOME")
  readonly property string run: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string sock: run + "/memora-music.sock"     // one Music at a time (bin/memora-player)
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/memora/music"

  // ---- the library ---------------------------------------------------------------
  property var tracks: []
  property var byPath: ({})
  property bool loaded: false
  property string scanText: ""
  FileView {
    path: app.cacheDir + "/library.json"
    watchChanges: true; printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const t = JSON.parse(text()).tracks || []
        const m = {}; t.forEach(x => m[x.path] = x)
        app.tracks = t; app.byPath = m
      } catch (e) {}
      app.loaded = true
    }
    onLoadFailed: app.loaded = true
  }
  Process {
    id: scanner
    command: ["memora-music-scan"]
    running: true
    stdout: SplitParser { onRead: line => {
      const m = line.match(/^PROGRESS (\d+)\/(\d+)/)
      app.scanText = m ? "Reading your music… " + m[1] + " of " + m[2] : ""
    } }
    onExited: app.scanText = ""
  }
  Timer { interval: 120000; repeat: true; running: true; onTriggered: if (!scanner.running) scanner.running = true }

  function albumKey(t) { return t.albumArtist + "\u001f" + t.album }
  readonly property var albums: {
    const m = {}, list = []
    tracks.forEach(t => {
      const k = albumKey(t)
      if (!m[k]) { m[k] = { key: k, name: t.album, artist: t.albumArtist, cover: t.cover, year: t.year, genre: t.genre, tracks: [], added: 0 }; list.push(m[k]) }
      const a = m[k]
      a.tracks.push(t)
      a.added = Math.max(a.added, t.added || 0)
      if (!a.cover && t.cover) a.cover = t.cover
      if (!a.year && t.year) a.year = t.year
    })
    list.forEach(a => a.tracks.sort((x, y) => (x.disc - y.disc) || (x.track - y.track) || x.title.localeCompare(y.title)))
    return list.sort((x, y) => x.name.localeCompare(y.name))
  }
  readonly property var albumByKey: { const m = {}; albums.forEach(a => m[a.key] = a); return m }
  readonly property var artists: {
    const m = {}, list = []
    albums.forEach(a => {
      if (!m[a.artist]) { m[a.artist] = { name: a.artist, albums: [], cover: a.cover, count: 0 }; list.push(m[a.artist]) }
      m[a.artist].albums.push(a); m[a.artist].count += a.tracks.length
      if (!m[a.artist].cover) m[a.artist].cover = a.cover
    })
    return list.sort((x, y) => x.name.localeCompare(y.name))
  }
  readonly property var songs: tracks.slice().sort((x, y) => x.title.localeCompare(y.title))
  readonly property var recent: albums.slice().sort((x, y) => y.added - x.added).slice(0, 60)

  // ---- favourites and playlists (~/.local/share/memora/music.json) ---------------
  property var favs: ({})
  property var playlists: []          // [{ name, tracks: [paths] }]
  FileView {
    id: userFile
    path: app.home + "/.local/share/memora/music.json"
    printErrors: false
    onLoaded: { try { const j = JSON.parse(text()); const f = {}; (j.favourites || []).forEach(p => f[p] = true); app.favs = f; app.playlists = j.playlists || [] } catch (e) {} }
  }
  function saveUser() {
    Quickshell.execDetached(["mkdir", "-p", home + "/.local/share/memora"])
    userFile.setText(JSON.stringify({ favourites: Object.keys(favs), playlists: playlists }, null, 1) + "\n")
  }
  function toggleFav(p) { const f = Object.assign({}, favs); if (f[p]) delete f[p]; else f[p] = true; favs = f; saveUser() }
  function newPlaylist(name, paths) {
    const n = (name || "").trim() || "Playlist " + (playlists.length + 1)
    playlists = playlists.concat([{ name: n, tracks: paths || [] }]); saveUser()
    return playlists.length - 1
  }
  function addToPlaylist(i, paths) {
    const pl = playlists.slice(); const cur = pl[i].tracks.slice()
    paths.forEach(p => { if (cur.indexOf(p) < 0) cur.push(p) })
    pl[i] = { name: pl[i].name, tracks: cur }; playlists = pl; saveUser()
  }
  function removeFromPlaylist(i, p) { const pl = playlists.slice(); pl[i] = { name: pl[i].name, tracks: pl[i].tracks.filter(x => x !== p) }; playlists = pl; saveUser() }
  function deletePlaylist(i) { playlists = playlists.filter((_, j) => j !== i); saveUser(); if (view === "playlist:" + i) view = "recent" }
  function renamePlaylist(i, name) { if (!name.trim()) return; const pl = playlists.slice(); pl[i] = { name: name.trim(), tracks: pl[i].tracks }; playlists = pl; saveUser() }

  // ---- mpv -------------------------------------------------------------------------
  property bool paused: true
  property real pos: 0
  property real dur: 0
  property int qpos: -1
  property var queue: []              // paths, as mpv's playlist
  property real volume: 80
  property string repeat: "off"       // off | all | one
  property bool shuffled: false
  readonly property bool playing: !paused && qpos >= 0
  readonly property var current: qpos >= 0 && qpos < queue.length ? (byPath[queue[qpos]] || { path: queue[qpos], title: queue[qpos].split("/").pop(), artist: "", album: "", cover: "" }) : null

  Process {
    id: mpv
    running: true
    // setpriv: mpv ends with the app, even when the app is killed (no music left playing on its own).
    command: ["setpriv", "--pdeathsig", "TERM", "mpv", "--idle=yes", "--no-video", "--no-terminal", "--force-window=no", "--audio-display=no",
              "--input-ipc-server=" + app.sock, "--volume=" + app.volume, "--title=Music", "--gapless-audio=weak"]
  }
  Socket {
    id: ipc
    path: app.sock
    parser: SplitParser { onRead: line => app.event(line) }
    onConnectedChanged: if (connected) app.observe()
  }
  // mpv takes a moment to open its socket.
  Timer { interval: 250; repeat: true; running: mpv.running && !ipc.connected; onTriggered: { ipc.connected = false; ipc.connected = true } }
  function send(cmd) { if (ipc.connected) { ipc.write(JSON.stringify({ command: cmd }) + "\n"); ipc.flush() } }
  function observe() {
    ["pause", "time-pos", "duration", "playlist-pos", "playlist", "volume", "loop-file", "loop-playlist"].forEach((p, i) => send(["observe_property", i + 1, p]))
    if (pendingOpen) { const f = pendingOpen; pendingOpen = ""; openFile(f) }
  }
  function event(line) {
    let e; try { e = JSON.parse(line) } catch (x) { return }
    if (e.event !== "property-change") return
    const d = e.data
    switch (e.name) {
    case "pause": paused = d !== false; break
    case "time-pos": pos = d || 0; break
    case "duration": dur = d || 0; break
    case "playlist-pos": qpos = d === undefined || d === null ? -1 : d; break
    case "playlist": queue = (d || []).map(x => x.filename); break
    case "volume": if (d !== undefined && d !== null) volume = d; break
    case "loop-file": if (d && d !== "no" && d !== false) repeat = "one"; else if (repeat === "one") repeat = "off"; break
    case "loop-playlist": if (d && d !== "no" && d !== false) { if (repeat !== "one") repeat = "all" } else if (repeat === "all") repeat = "off"; break
    }
  }

  // Play a list of songs from one of them (mpv's playlist becomes the queue).
  function playList(paths, index, shuffle) {
    if (!paths.length) return
    let list = paths.slice(), start = Math.max(0, index || 0)
    if (shuffle) {
      const first = list.splice(start, 1)
      for (let i = list.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [list[i], list[j]] = [list[j], list[i]] }
      list = first.concat(list); start = 0
    }
    shuffled = !!shuffle
    const m3u = run + "/memora-music-queue.m3u"
    queueFile.setText(list.join("\n") + "\n")
    Qt.callLater(() => { send(["loadlist", m3u, "replace"]); send(["playlist-play-index", start]); send(["set_property", "pause", false]) })
  }
  FileView { id: queueFile; path: app.run + "/memora-music-queue.m3u"; printErrors: false }
  function playNext(paths) { paths.slice().reverse().forEach(p => send(["loadfile", p, "insert-next"])); if (qpos < 0) send(["playlist-play-index", 0]) }
  function addToQueue(paths) { paths.forEach(p => send(["loadfile", p, "append-play"])) }
  function toggle() { if (qpos < 0 && songs.length) playList(songs.map(t => t.path), 0, false); else send(["cycle", "pause"]) }
  function next() { send(["playlist-next", "force"]) }
  function prev() { if (pos > 3) send(["seek", 0, "absolute"]); else send(["playlist-prev", "force"]) }
  function seek(t) { send(["seek", t, "absolute"]) }
  function setVolume(v) { volume = v; send(["set_property", "volume", v]) }
  function cycleRepeat() {
    const r = repeat === "off" ? "all" : repeat === "all" ? "one" : "off"
    repeat = r
    send(["set_property", "loop-playlist", r === "all" ? "inf" : "no"])
    send(["set_property", "loop-file", r === "one" ? "inf" : "no"])
  }
  function toggleShuffle() {
    shuffled = !shuffled
    if (shuffled) { const cur = qpos; send(["playlist-shuffle"]); Qt.callLater(() => send(["playlist-move", app.qpos, 0])) }
    else send(["playlist-unshuffle"])
  }
  // A file opened from Files: play it with the rest of its album.
  property string pendingOpen: Quickshell.env("MEMORA_PLAYER_FILE") || ""
  function openFile(f) {
    if (!ipc.connected) { pendingOpen = f; return }
    const t = byPath[f]
    if (t) { const a = albumByKey[albumKey(t)]; const ps = a.tracks.map(x => x.path); playList(ps, ps.indexOf(f), false) }
    else playList([f], 0, false)
  }
  IpcHandler {
    target: "player"
    function open(path: string): void { app.openFile(path) }
  }
  function time(s) { s = Math.max(0, Math.floor(s || 0)); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }
  function minutes(list) { const m = Math.round(list.reduce((a, t) => a + (t.dur || 0), 0) / 60); return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min" }

  // ---- synced lyrics (an .lrc next to the song) ---------------------------------
  property var lyrics: []             // [{ t, text }]
  property bool showLyrics: false
  FileView {
    id: lrc
    path: app.current ? app.current.path.replace(/\.[^./]+$/, ".lrc") : ""
    printErrors: false
    onLoaded: {
      const out = []
      text().split("\n").forEach(l => {
        const words = l.replace(/\[[^\]]*\]/g, "").trim()
        const re = /\[(\d+):(\d+(?:\.\d+)?)\]/g
        let m
        while ((m = re.exec(l)) !== null) out.push({ t: parseInt(m[1]) * 60 + parseFloat(m[2]), text: words })
      })
      app.lyrics = out.sort((a, b) => a.t - b.t)
    }
    onLoadFailed: app.lyrics = []
  }
  onCurrentChanged: if (!current) lyrics = []
  onLyricsChanged: if (!lyrics.length) showLyrics = false      // the next song has none
  readonly property int lyricLine: { let i = -1; for (let k = 0; k < lyrics.length; k++) { if (lyrics[k].t <= pos + 0.3) i = k; else break } return i }

  // ---- what the window shows -----------------------------------------------------
  property string view: "recent"      // recent | albums | artists | songs | favs | playlist:N | album:KEY | artist:NAME
  property var back: []
  function go(v) { if (v === view) return; back = back.concat([view]); view = v; query = ""; search.text = "" }
  function goBack() { if (!back.length) return; view = back[back.length - 1]; back = back.slice(0, -1) }
  property string query: ""
  property bool showQueue: false
  property bool full: false           // Now Playing, filling the window

  FloatingWindow {
    id: win
    title: app.current ? app.current.title + " — " + app.current.artist : "Music"
    implicitWidth: 1180
    implicitHeight: 780
    minimumSize: Qt.size(820, 520)
    color: "transparent"
    onVisibleChanged: if (!visible) Qt.quit()
    Rectangle { anchors.fill: parent; color: Theme.window }
    ColorPick { id: tint; src: app.current ? app.current.cover : "" }

    Shortcut { sequence: "Space"; onActivated: app.toggle() }
    Shortcut { sequence: "Ctrl+Right"; onActivated: app.next() }
    Shortcut { sequence: "Ctrl+Left"; onActivated: app.prev() }
    Shortcut { sequence: "Ctrl+Up"; onActivated: app.setVolume(Math.min(100, app.volume + 10)) }
    Shortcut { sequence: "Ctrl+Down"; onActivated: app.setVolume(Math.max(0, app.volume - 10)) }
    Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+W"; onActivated: Qt.quit() }
    Shortcut { sequence: "Escape"; onActivated: app.full ? app.full = false : app.showLyrics ? app.showLyrics = false : app.showQueue ? app.showQueue = false : app.goBack() }

    // Drop songs on the window to play them.
    DropArea {
      anchors.fill: parent
      onDropped: ev => {
        const ps = ev.urls.map(u => decodeURIComponent(u.toString().replace(/^file:\/\//, ""))).filter(p => /\.(mp3|flac|ogg|opus|m4a|aac|wav|wma|aiff?|ape|wv)$/i.test(p))
        if (ps.length) app.playList(ps, 0, false)
      }
    }

    // ==== sidebar ====
    Rectangle {
      id: side
      width: 224
      anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
      color: Theme.sidebar
      Item { anchors { left: parent.left; right: parent.right; top: parent.top } height: 46; DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() } }
      WindowControls { x: 18; y: 15; window: win; onCloseRequested: Qt.quit() }
      Rectangle {
        x: 14; y: 50; width: parent.width - 28; height: 30; radius: 8
        color: Theme.field; border.color: search.activeFocus ? Theme.accent : "transparent"
        Sym { x: 9; anchors.verticalCenter: parent.verticalCenter; name: "search"; width: 13; height: 13; color: Theme.textDim }
        TextInput {
          id: search
          anchors { left: parent.left; leftMargin: 30; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
          color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize; clip: true
          onTextChanged: app.query = text
          Keys.onEscapePressed: { text = ""; focus = false }
          Txt { visible: !search.text; text: "Search"; color: Theme.textFaint }
        }
      }
      Flickable {
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 92; bottom: scanNote.top }
        contentHeight: nav.implicitHeight + 20; clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: nav
          width: parent.width
          spacing: 1
          Head { text: "Library" }
          NavItem { sym: "clock"; label: "Recently Added"; target: "recent" }
          NavItem { sym: "music"; label: "Albums"; target: "albums" }
          NavItem { sym: "user"; label: "Artists"; target: "artists" }
          NavItem { sym: "queue"; label: "Songs"; target: "songs" }
          NavItem { sym: "heart"; label: "Favourites"; target: "favs" }
          Head { text: "Playlists" }
          Repeater {
            model: app.playlists
            delegate: NavItem { required property var modelData; required property int index; sym: "queue"; label: modelData.name; target: "playlist:" + index }
          }
          Item {
            width: nav.width; height: 30
            Sym { x: 20; anchors.verticalCenter: parent.verticalCenter; name: "plus"; width: 13; height: 13; color: Theme.textDim }
            Txt { x: 44; anchors.verticalCenter: parent.verticalCenter; text: "New Playlist"; color: Theme.textDim }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: app.go("playlist:" + app.newPlaylist("", [])) }
          }
        }
      }
      Txt {
        id: scanNote
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
        text: app.scanText || (app.tracks.length ? app.tracks.length + " songs" : "")
        color: Theme.textFaint; font.pixelSize: Theme.small - 0.5; elide: Text.ElideRight
      }
    }
    Rectangle { x: side.width; width: 1; height: parent.height; color: Theme.separator }

    // ==== the player, at the top ====
    Item {
      id: bar
      anchors { left: side.right; right: parent.right; top: parent.top; leftMargin: 1 }
      height: 64
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      Row {
        id: transport
        x: 18; anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        Btn { sym: "shuffle"; size: 15; on: app.shuffled; tip: "Shuffle"; onClicked: app.toggleShuffle() }
        Btn { sym: "prev"; size: 17; tip: "Previous (Ctrl+←)"; onClicked: app.prev() }
        Btn { sym: app.playing ? "pause" : "play"; size: 22; tip: app.playing ? "Pause (Space)" : "Play (Space)"; onClicked: app.toggle() }
        Btn { sym: "next"; size: 17; tip: "Next (Ctrl+→)"; onClicked: app.next() }
        Btn { sym: app.repeat === "one" ? "repeat-one" : "repeat"; size: 15; on: app.repeat !== "off"; tip: ({ off: "Repeat", all: "Repeat: all", one: "Repeat: this song" })[app.repeat]; onClicked: app.cycleRepeat() }
      }
      // Now playing: cover, title, where it is.
      Rectangle {
        id: lcd
        anchors { left: transport.right; leftMargin: 18; right: tools.left; rightMargin: 18; verticalCenter: parent.verticalCenter }
        height: 50; radius: 10
        color: Theme.field
        Cover {
          id: npCover; x: 4; y: 4; width: 42; height: 42; radius: 6; src: app.current ? app.current.cover : ""; small: true
          hover: nph.hovered
          HoverHandler { id: nph; cursorShape: app.current ? Qt.PointingHandCursor : Qt.ArrowCursor }
          TapHandler { onTapped: if (app.current) app.full = true }
        }
        Column {
          anchors { left: npCover.right; leftMargin: 12; right: parent.right; rightMargin: 12; top: parent.top; topMargin: 6 }
          spacing: 1
          Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; font.weight: Font.Bold; text: app.current ? app.current.title : "Music" }
          Txt {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; color: Theme.textDim; font.pixelSize: Theme.small
            text: app.current ? [app.current.artist, app.current.album].filter(x => x).join(" — ") : (app.tracks.length ? "Choose something to play" : "")
          }
        }
        // The position: drag or click to move in the song.
        Item {
          id: seekbar
          anchors { left: npCover.right; leftMargin: 12; right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 6 }
          height: 8
          visible: !!app.current
          readonly property real frac: app.dur > 0 ? Math.min(1, (sd.active ? sd.frac : app.pos) / app.dur) : 0
          Txt { anchors { right: parent.left; rightMargin: -40; verticalCenter: parent.verticalCenter } visible: false; text: "" }
          readonly property real thick: seekHover.hovered || sd.active ? 5 : 3
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: seekbar.thick; radius: height / 2; color: Theme.separator; Behavior on height { NumberAnimation { duration: 120 } } }
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * seekbar.frac; height: seekbar.thick; radius: height / 2; color: seekHover.hovered ? tint.vivid : Theme.textDim; Behavior on height { NumberAnimation { duration: 120 } } }
          Rectangle { visible: seekHover.hovered || sd.active; x: parent.width * seekbar.frac - 6; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: "#ffffff"; border.color: Theme.separator }
          DragHandler {
            id: sd; target: null; xAxis.enabled: true; yAxis.enabled: false
            property real frac: 0
            onCentroidChanged: if (active) frac = Math.max(0, Math.min(1, centroid.position.x / seekbar.width)) * app.dur
            onActiveChanged: if (!active) app.seek(frac)
          }
          TapHandler { onTapped: ev => app.seek(Math.max(0, Math.min(1, ev.position.x / seekbar.width)) * app.dur) }
          HoverHandler { id: seekHover }
        }
        Txt { visible: !!app.current; anchors { left: npCover.right; leftMargin: 12; top: parent.top; topMargin: 7 } text: app.time(app.pos); color: Theme.textFaint; font.pixelSize: Theme.small - 1 }
        Txt { visible: !!app.current; anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 7 } text: "-" + app.time(app.dur - app.pos); color: Theme.textFaint; font.pixelSize: Theme.small - 1 }
      }
      Row {
        id: tools
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 6
        Sym { anchors.verticalCenter: parent.verticalCenter; name: app.volume === 0 ? "sound-off" : "sound"; level: app.volume / 100; width: 15; height: 15; color: Theme.textDim }
        Item {
          id: vol
          anchors.verticalCenter: parent.verticalCenter
          width: 90; height: 16
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 3; radius: 1.5; color: Theme.separator }
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * app.volume / 100; height: 3; radius: 1.5; color: Theme.textDim }
          Rectangle { x: parent.width * app.volume / 100 - 6; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: "#ffffff"; border.color: Theme.separator }
          DragHandler { target: null; xAxis.enabled: true; yAxis.enabled: false; onCentroidChanged: if (active) app.setVolume(Math.round(Math.max(0, Math.min(1, centroid.position.x / vol.width)) * 100)) }
          TapHandler { onTapped: ev => app.setVolume(Math.round(Math.max(0, Math.min(1, ev.position.x / vol.width)) * 100)) }
        }
        Item { width: 6; height: 1 }
        Btn { sym: "lyrics"; size: 15; on: app.showLyrics; enabled: app.lyrics.length > 0; opacity: enabled ? 1 : 0.35; tip: app.lyrics.length ? "Lyrics" : "No lyrics for this song"; onClicked: app.showLyrics = !app.showLyrics }
        Btn { sym: "queue"; size: 15; on: app.showQueue; tip: "Up Next"; onClicked: app.showQueue = !app.showQueue }
      }
    }
    Rectangle { anchors { left: side.right; right: parent.right; top: bar.bottom; leftMargin: 1 } height: 1; color: Theme.separator }

    // ==== content ====
    Item {
      id: content
      // Two fingers to the right: back to where you were.
      SwipeNav { onBack: app.goBack() }
      anchors { left: side.right; right: queuePanel.visible ? queuePanel.left : parent.right; top: bar.bottom; bottom: parent.bottom; leftMargin: 1; topMargin: 1 }
      clip: true

      readonly property bool searching: app.query.trim().length > 0
      readonly property string q: app.query.trim().toLowerCase()
      readonly property var foundSongs: searching ? app.songs.filter(t => (t.title + " " + t.artist + " " + t.album).toLowerCase().indexOf(q) >= 0).slice(0, 300) : []
      readonly property var foundAlbums: searching ? app.albums.filter(a => (a.name + " " + a.artist).toLowerCase().indexOf(q) >= 0).slice(0, 24) : []

      // Nothing yet.
      Column {
        anchors.centerIn: parent
        visible: app.loaded && app.tracks.length === 0 && !content.searching
        spacing: 12
        Sym { anchors.horizontalCenter: parent.horizontalCenter; name: "music"; width: 54; height: 54; color: Theme.textFaint }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: app.scanText || "No music yet"; font.weight: Font.Bold; font.pixelSize: Theme.large + 2 }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Put songs in your Music folder (or drop them on this window)."; color: Theme.textDim }
        Pill { anchors.horizontalCenter: parent.horizontalCenter; text: "Open the Music Folder"; strong: true; onClicked: Quickshell.execDetached(["bash", "-c", "mkdir -p ~/Music && xdg-open ~/Music"]) }
      }

      // Search results, and every list of songs.
      Loader {
        id: page
        anchors.fill: parent
        active: app.tracks.length > 0 && !app.showLyrics
        onLoaded: { item.opacity = 0; pageIn.restart() }
        ParallelAnimation {
          id: pageIn
          NumberAnimation { target: page.item; property: "opacity"; from: 0; to: 1; duration: Prefs.motion(260); easing.type: Easing.OutCubic }
          NumberAnimation { target: page; property: "anchors.topMargin"; from: 14; to: 0; duration: Prefs.motion(320); easing.type: Easing.OutCubic }
        }
        sourceComponent: content.searching ? searchView
          : app.view === "recent" ? recentView
          : app.view === "albums" ? albumsView
          : app.view === "artists" ? artistsView
          : app.view === "songs" ? songsView
          : app.view === "favs" ? favsView
          : app.view.startsWith("playlist:") ? playlistView
          : app.view.startsWith("album:") ? albumView
          : app.view.startsWith("artist:") ? artistView : recentView
      }

      // Lyrics, the line being sung lit up.
      Item {
        anchors.fill: parent
        visible: app.showLyrics
        Cover { anchors.fill: parent; src: app.current ? app.current.cover : ""; radius: 0; blurred: true; opacity: 0.55 }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
        ListView {
          id: lyricList
          anchors { fill: parent; leftMargin: 60; rightMargin: 60 }
          model: app.lyrics
          spacing: 14
          clip: true
          preferredHighlightBegin: height * 0.38; preferredHighlightEnd: height * 0.38 + 40
          highlightRangeMode: ListView.ApplyRange
          highlightMoveDuration: 380
          currentIndex: Math.max(0, app.lyricLine)
          header: Item { height: lyricList.height * 0.38 }
          footer: Item { height: lyricList.height * 0.5 }
          delegate: Txt {
            required property var modelData
            required property int index
            width: lyricList.width; wrapMode: Text.Wrap
            text: modelData.text || "♪"
            font.pixelSize: 26; font.weight: Font.Bold
            color: "#ffffff"
            opacity: index === app.lyricLine ? 1 : 0.38
            Behavior on opacity { NumberAnimation { duration: 240 } }
            TapHandler { onTapped: app.seek(modelData.t) }
          }
        }
      }
    }

    // ==== Up Next ====
    Rectangle {
      id: queuePanel
      visible: app.showQueue
      width: 320
      anchors { right: parent.right; top: bar.bottom; bottom: parent.bottom; topMargin: 1 }
      color: Theme.sidebar
      Rectangle { width: 1; height: parent.height; color: Theme.separator }
      Txt { x: 18; y: 16; text: "Up Next"; font.weight: Font.Bold; font.pixelSize: Theme.large }
      Txt {
        anchors { right: parent.right; rightMargin: 16; top: parent.top; topMargin: 18 }
        text: "Clear"; color: Theme.accent; visible: app.queue.length > app.qpos + 1
        TapHandler { onTapped: { for (let i = app.queue.length - 1; i > app.qpos; i--) app.send(["playlist-remove", i]) } }
      }
      ListView {
        anchors { fill: parent; topMargin: 50 }
        clip: true
        model: app.queue.length
        delegate: SongRow {
          required property int index
          width: ListView.view.width
          t: app.byPath[app.queue[index]] || { path: app.queue[index], title: app.queue[index].split("/").pop(), artist: "", album: "", cover: "", dur: 0 }
          compact: true
          playing: index === app.qpos
          dim: index < app.qpos
          onPlay: app.send(["playlist-play-index", index])
          onContext: (it, x, y) => menu.open(it, x, y, [t.path], { queueIndex: index })
        }
      }
    }

    // ==== Now Playing, filling the window ====
    Item {
      id: np
      anchors.fill: parent
      z: 50
      visible: opacity > 0
      opacity: app.full ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Prefs.motion(320); easing.type: Easing.OutCubic } }
      transform: Translate { y: app.full ? 0 : 60; Behavior on y { NumberAnimation { duration: Prefs.motion(420); easing.type: Easing.OutQuint } } }
      Rectangle { anchors.fill: parent; color: "#0b0b0d" }
      // The cover, huge and blurred, drifting slowly: the room the music fills.
      Cover {
        id: npBg
        anchors.centerIn: parent
        width: Math.max(parent.width, parent.height) * 1.5; height: width
        src: app.current ? app.current.cover : ""; radius: 0; blurred: true
        opacity: 0.85
        RotationAnimation on rotation { running: np.visible && app.playing; from: 0; to: 360; duration: 180000; loops: Animation.Infinite }
      }
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(tint.color.r * 0.4, tint.color.g * 0.4, tint.color.b * 0.4, 0.35) }
          GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) }
        }
      }
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      WindowControls { x: 18; y: 15; window: win; onCloseRequested: Qt.quit() }
      // Down: back to the library.
      Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
        width: 44; height: 24; radius: 12
        color: dh.hovered ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.1)
        Sym { anchors.centerIn: parent; name: "chevron"; rotation: 90; width: 12; height: 12; color: "#ffffff" }
        HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: app.full = false }
      }

      readonly property bool wide: width > 980 && (app.lyrics.length > 0 || app.queue.length > 1)
      Item {
        id: stage
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 50; bottomMargin: 30 }
        width: np.wide ? parent.width * 0.5 : parent.width
        readonly property real coverSize: Math.min(width * 0.62, height - 230)
        // The cover breathes: full size while playing, a little smaller paused.
        Cover {
          id: big
          anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 10 }
          width: stage.coverSize; height: width; radius: 12
          src: app.current ? app.current.cover : ""; shadow: true
          scale: app.playing ? 1 : 0.86
          Behavior on scale { SpringAnimation { spring: 2.6; damping: 0.28; epsilon: 0.002 } }
        }
        Column {
          anchors { top: big.bottom; topMargin: 26; horizontalCenter: parent.horizontalCenter }
          width: stage.coverSize + 40
          spacing: 6
          Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: app.current ? app.current.title : ""; color: "#ffffff"; font.pixelSize: 22; font.weight: Font.Bold }
          Txt {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
            text: app.current ? [app.current.artist, app.current.album].filter(x => x).join(" — ") : ""
            color: Qt.rgba(1, 1, 1, 0.65); font.pixelSize: Theme.large
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: if (app.current && app.current.album) { app.full = false; app.go("album:" + app.albumKey(app.current)) } }
          }
          Item { width: 1; height: 10 }
          // Where the song is.
          Item {
            id: bigSeek
            width: parent.width; height: 14
            readonly property real frac: app.dur > 0 ? Math.min(1, (bsd.active ? bsd.frac : app.pos) / app.dur) : 0
            readonly property real thick: bsh.hovered || bsd.active ? 7 : 5
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: bigSeek.thick; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.22); Behavior on height { NumberAnimation { duration: 120 } } }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * bigSeek.frac; height: bigSeek.thick; radius: height / 2; color: "#ffffff"; Behavior on height { NumberAnimation { duration: 120 } } }
            HoverHandler { id: bsh }
            DragHandler {
              id: bsd; target: null; xAxis.enabled: true; yAxis.enabled: false
              property real frac: 0
              onCentroidChanged: if (active) frac = Math.max(0, Math.min(1, centroid.position.x / bigSeek.width)) * app.dur
              onActiveChanged: if (!active) app.seek(frac)
            }
            TapHandler { onTapped: ev => app.seek(Math.max(0, Math.min(1, ev.position.x / bigSeek.width)) * app.dur) }
          }
          Item {
            width: parent.width; height: 16
            Txt { text: app.time(app.pos); color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: Theme.small - 1 }
            Txt { anchors.right: parent.right; text: "-" + app.time(app.dur - app.pos); color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: Theme.small - 1 }
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 22
            BigBtn { sym: "shuffle"; size: 18; on: app.shuffled; onClicked: app.toggleShuffle() }
            BigBtn { sym: "prev"; size: 26; onClicked: app.prev() }
            // Play: a white disc.
            Rectangle {
              width: 64; height: 64; radius: 32
              anchors.verticalCenter: parent.verticalCenter
              color: "#ffffff"
              scale: pph.pressed ? 0.92 : (pphv.hovered ? 1.05 : 1)
              Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
              Sym { anchors.centerIn: parent; anchors.horizontalCenterOffset: app.playing ? 0 : 2; name: app.playing ? "pause" : "play"; width: 26; height: 26; color: "#111114" }
              HoverHandler { id: pphv; cursorShape: Qt.PointingHandCursor }
              TapHandler { id: pph; onTapped: app.toggle() }
            }
            BigBtn { sym: "next"; size: 26; onClicked: app.next() }
            BigBtn { sym: app.repeat === "one" ? "repeat-one" : "repeat"; size: 18; on: app.repeat !== "off"; onClicked: app.cycleRepeat() }
          }
          Item { width: 1; height: 6 }
          // Volume.
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Sym { anchors.verticalCenter: parent.verticalCenter; name: "sound-off"; width: 13; height: 13; color: Qt.rgba(1, 1, 1, 0.55) }
            Item {
              id: bigVol
              anchors.verticalCenter: parent.verticalCenter
              width: 220; height: 14
              Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.22) }
              Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * app.volume / 100; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.8) }
              DragHandler { target: null; xAxis.enabled: true; yAxis.enabled: false; onCentroidChanged: if (active) app.setVolume(Math.round(Math.max(0, Math.min(1, centroid.position.x / bigVol.width)) * 100)) }
              TapHandler { onTapped: ev => app.setVolume(Math.round(Math.max(0, Math.min(1, ev.position.x / bigVol.width)) * 100)) }
            }
            Sym { anchors.verticalCenter: parent.verticalCenter; name: "sound"; level: 1; width: 15; height: 15; color: Qt.rgba(1, 1, 1, 0.55) }
          }
        }
      }
      // Beside it: the lyrics, or what comes next.
      Item {
        visible: np.wide
        anchors { left: stage.right; right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 60; bottomMargin: 40; rightMargin: 50 }
        ListView {
          id: npLyrics
          anchors.fill: parent
          visible: app.lyrics.length > 0
          model: app.lyrics
          spacing: 16; clip: true
          preferredHighlightBegin: height * 0.35; preferredHighlightEnd: height * 0.35 + 40
          highlightRangeMode: ListView.ApplyRange; highlightMoveDuration: 420
          currentIndex: Math.max(0, app.lyricLine)
          header: Item { height: npLyrics.height * 0.35 }
          footer: Item { height: npLyrics.height * 0.6 }
          delegate: Txt {
            required property var modelData
            required property int index
            width: npLyrics.width; wrapMode: Text.Wrap
            text: modelData.text || "♪"
            font.pixelSize: 28; font.weight: Font.Bold; color: "#ffffff"
            opacity: index === app.lyricLine ? 1 : 0.32
            scale: index === app.lyricLine ? 1 : 0.97
            transformOrigin: Item.Left
            Behavior on opacity { NumberAnimation { duration: 260 } }
            Behavior on scale { NumberAnimation { duration: 260 } }
            TapHandler { onTapped: app.seek(modelData.t) }
          }
        }
        Column {
          visible: app.lyrics.length === 0
          width: parent.width
          spacing: 4
          Txt { text: "Up Next"; color: "#ffffff"; font.weight: Font.Bold; font.pixelSize: Theme.large; bottomPadding: 10 }
          Repeater {
            model: Math.min(8, Math.max(0, app.queue.length - app.qpos - 1))
            delegate: Row {
              required property int index
              readonly property var t: app.byPath[app.queue[app.qpos + 1 + index]] || { title: (app.queue[app.qpos + 1 + index] || "").split("/").pop(), artist: "", cover: "" }
              spacing: 12
              Cover { width: 44; height: 44; radius: 6; src: parent.t.cover || ""; small: true }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                Txt { text: parent.parent.t.title; color: "#ffffff"; width: 320; elide: Text.ElideRight }
                Txt { text: parent.parent.t.artist; color: Qt.rgba(1, 1, 1, 0.55); font.pixelSize: Theme.small; width: 320; elide: Text.ElideRight }
              }
              TapHandler { onTapped: app.send(["playlist-play-index", app.qpos + 1 + index]) }
            }
          }
        }
      }
    }

    // ==== the right-click menu ====
    Item {
      id: menu
      anchors.fill: parent
      visible: false
      z: 100
      property var paths: []
      property var extra: ({})
      property var items: []
      function open(item, x, y, paths, extra) {
        menu.paths = paths; menu.extra = extra || {}
        const t = app.byPath[paths[0]] || {}
        const it = [
          { text: "Play Next", action: () => app.playNext(paths) },
          { text: "Add to Queue", action: () => app.addToQueue(paths) },
          { sep: true },
          { text: paths.every(p => app.favs[p]) ? "Remove from Favourites" : "Add to Favourites", action: () => paths.forEach(p => { if (!!app.favs[p] === paths.every(q => app.favs[q])) app.toggleFav(p) }) },
          { text: "Add to a New Playlist", action: () => app.go("playlist:" + app.newPlaylist("", paths)) }
        ]
        app.playlists.forEach((pl, i) => it.push({ text: "Add to “" + pl.name + "”", action: () => app.addToPlaylist(i, paths) }))
        if (menu.extra.playlist !== undefined) it.push({ text: "Remove from This Playlist", action: () => paths.forEach(p => app.removeFromPlaylist(menu.extra.playlist, p)) })
        if (menu.extra.queueIndex !== undefined) it.push({ text: "Remove from Up Next", action: () => app.send(["playlist-remove", menu.extra.queueIndex]) })
        it.push({ sep: true })
        if (t.album) it.push({ text: "Go to Album", action: () => app.go("album:" + app.albumKey(t)) })
        if (t.albumArtist) it.push({ text: "Go to Artist", action: () => app.go("artist:" + t.albumArtist) })
        it.push({ text: "Show in Files", action: () => Quickshell.execDetached(["memora-files", paths[0].substring(0, paths[0].lastIndexOf("/"))]) })
        menu.items = it
        const p = item.mapToItem(menu, x, y)
        box.x = Math.min(p.x, menu.width - box.width - 8); box.y = Math.min(p.y, menu.height - box.height - 8)
        visible = true
      }
      TapHandler { onTapped: menu.visible = false }
      TapHandler { acceptedButtons: Qt.RightButton; onTapped: menu.visible = false }
      Rectangle {
        id: box
        width: 250; height: mcol.implicitHeight + 10; radius: 10
        color: Theme.dark ? "#2c2c30" : "#fbfbfd"; border.color: Theme.separator
        Column {
          id: mcol
          x: 5; y: 5; width: parent.width - 10
          Repeater {
            model: menu.items
            delegate: Item {
              required property var modelData
              width: mcol.width; height: modelData.sep ? 9 : 28
              Rectangle { visible: !!modelData.sep; anchors.centerIn: parent; width: parent.width - 12; height: 1; color: Theme.separator }
              Rectangle { visible: !modelData.sep; anchors.fill: parent; radius: 6; color: mh.hovered ? Theme.accent : "transparent" }
              Txt { visible: !modelData.sep; x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 20; elide: Text.ElideRight; text: modelData.text || ""; color: mh.hovered ? "#ffffff" : Theme.text }
              HoverHandler { id: mh; enabled: !modelData.sep }
              TapHandler { enabled: !modelData.sep; onTapped: { menu.visible = false; modelData.action() } }
            }
          }
        }
      }
    }
  }

  // ==== views ========================================================================
  Component { id: recentView; AlbumGrid { title: "Recently Added"; model: app.recent } }
  Component { id: albumsView; AlbumGrid { title: "Albums"; model: app.albums } }
  Component {
    id: artistsView
    GridView {
      id: ag
      clip: true; boundsBehavior: Flickable.StopAtBounds
      leftMargin: 28; rightMargin: 28; topMargin: 70
      readonly property int cols: Math.max(2, Math.floor((width - 56) / 190))
      cellWidth: (width - 56) / cols; cellHeight: cellWidth + 34
      model: app.artists
      Txt { parent: ag; x: 28; y: 20; text: "Artists"; font.pixelSize: 26; font.weight: Font.Bold }
      delegate: Item {
        required property var modelData
        width: ag.cellWidth; height: ag.cellHeight
        Cover { x: 10; y: 4; width: parent.width - 20; height: width; radius: width / 2; src: modelData.cover; hover: ah.hovered }
        Txt { y: parent.width - 8; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.name; font.weight: Font.Bold; elide: Text.ElideRight }
        HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: app.go("artist:" + modelData.name) }
      }
    }
  }
  Component { id: songsView; SongTable { title: "Songs"; list: app.songs } }
  Component { id: favsView; SongTable { title: "Favourites"; list: app.tracks.filter(t => app.favs[t.path]); empty: "Songs you love (the heart) gather here." } }
  Component {
    id: playlistView
    SongTable {
      readonly property int idx: parseInt(app.view.slice(9))
      readonly property var pl: app.playlists[idx] || { name: "", tracks: [] }
      title: pl.name; editable: true; playlist: idx
      list: pl.tracks.map(p => app.byPath[p]).filter(t => t)
      empty: "Right-click songs anywhere and choose Add to “" + pl.name + "”."
    }
  }
  Component {
    id: albumView
    Flickable {
      id: af
      readonly property var a: app.albumByKey[app.view.slice(6)] || null
      clip: true; boundsBehavior: Flickable.StopAtBounds
      contentHeight: acol.implicitHeight + 60
      ColorPick { id: albumTint; src: af.a ? af.a.cover : "" }
      Rectangle {
        width: af.width; height: 380; y: -af.contentY * 0.4
        parent: af
        z: -1
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(albumTint.color.r, albumTint.color.g, albumTint.color.b, Theme.dark ? 0.55 : 0.35) }
          GradientStop { position: 1; color: "transparent" }
        }
      }
      Column {
        id: acol
        x: 32; y: 28; width: af.width - 64
        spacing: 22
        Row {
          spacing: 26
          Cover { width: 230; height: 230; radius: 10; src: af.a ? af.a.cover : ""; shadow: true }
          Column {
            width: acol.width - 256
            anchors.bottom: parent.bottom
            spacing: 6
            Txt { width: parent.width; text: af.a ? af.a.name : ""; font.pixelSize: 28; font.weight: Font.Bold; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight }
            Txt { text: af.a ? af.a.artist : ""; color: Theme.accent; font.pixelSize: Theme.large + 2; TapHandler { onTapped: app.go("artist:" + af.a.artist) } HoverHandler { cursorShape: Qt.PointingHandCursor } }
            Txt { text: af.a ? [af.a.genre, af.a.year || ""].filter(x => x).join(" · ") : ""; color: Theme.textDim; font.pixelSize: Theme.small }
            Item { width: 1; height: 8 }
            Row {
              spacing: 10
              Pill { text: "▶  Play"; strong: true; onClicked: app.playList(af.a.tracks.map(t => t.path), 0, false) }
              Pill { text: "Shuffle"; onClicked: app.playList(af.a.tracks.map(t => t.path), Math.floor(Math.random() * af.a.tracks.length), true) }
            }
          }
        }
        Column {
          width: acol.width
          Repeater {
            model: af.a ? af.a.tracks : []
            delegate: SongRow {
              required property var modelData
              required property int index
              width: acol.width
              t: modelData; numbered: true; striped: index % 2 === 1
              playing: app.current && app.current.path === modelData.path
              onPlay: app.playList(af.a.tracks.map(x => x.path), index, false)
              onContext: (it, x, y) => menu.open(it, x, y, [modelData.path])
            }
          }
        }
        Txt { visible: !!af.a; text: af.a ? af.a.tracks.length + (af.a.tracks.length === 1 ? " song, " : " songs, ") + app.minutes(af.a.tracks) : ""; color: Theme.textDim; font.pixelSize: Theme.small }
      }
    }
  }
  Component {
    id: artistView
    Flickable {
      id: rf
      readonly property var r: app.artists.find(x => x.name === app.view.slice(7)) || null
      readonly property var all: r ? [].concat(...r.albums.map(a => a.tracks)) : []
      clip: true; boundsBehavior: Flickable.StopAtBounds
      contentHeight: rcol.implicitHeight + 60
      Column {
        id: rcol
        x: 32; y: 28; width: rf.width - 64
        spacing: 18
        Row {
          spacing: 20
          Cover { width: 120; height: 120; radius: 60; src: rf.r ? rf.r.cover : "" }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Txt { text: rf.r ? rf.r.name : ""; font.pixelSize: 30; font.weight: Font.Bold }
            Row {
              spacing: 10
              Pill { text: "▶  Play"; strong: true; onClicked: app.playList(rf.all.map(t => t.path), 0, false) }
              Pill { text: "Shuffle"; onClicked: app.playList(rf.all.map(t => t.path), Math.floor(Math.random() * rf.all.length), true) }
            }
          }
        }
        Txt { text: "Albums"; font.weight: Font.Bold; font.pixelSize: Theme.large + 2 }
        Flow {
          width: rcol.width; spacing: 22
          Repeater { model: rf.r ? rf.r.albums : []; delegate: AlbumCard { required property var modelData; a: modelData; width: 180 } }
        }
      }
    }
  }
  Component {
    id: searchView
    Flickable {
      id: sf
      clip: true; boundsBehavior: Flickable.StopAtBounds
      contentHeight: scol.implicitHeight + 60
      Column {
        id: scol
        x: 28; y: 20; width: sf.width - 56
        spacing: 16
        Txt { text: "Results for “" + app.query.trim() + "”"; font.pixelSize: 24; font.weight: Font.Bold }
        Txt { visible: !content.foundSongs.length && !content.foundAlbums.length; text: "Nothing matches."; color: Theme.textDim }
        Txt { visible: content.foundAlbums.length > 0; text: "Albums"; font.weight: Font.Bold; font.pixelSize: Theme.large }
        Flow {
          width: scol.width; spacing: 20
          Repeater { model: content.foundAlbums; delegate: AlbumCard { required property var modelData; a: modelData; width: 160 } }
        }
        Txt { visible: content.foundSongs.length > 0; text: "Songs"; font.weight: Font.Bold; font.pixelSize: Theme.large }
        Column {
          width: scol.width
          Repeater {
            model: content.foundSongs
            delegate: SongRow {
              required property var modelData
              required property int index
              width: scol.width; t: modelData; showAlbum: true; striped: index % 2 === 1
              playing: app.current && app.current.path === modelData.path
              onPlay: app.playList(content.foundSongs.map(x => x.path), index, false)
              onContext: (it, x, y) => menu.open(it, x, y, [modelData.path])
            }
          }
        }
      }
    }
  }

  // ==== pieces ========================================================================
  // A cover, or a soft placeholder with a note when the album has none.
  component Cover: Item {
    id: cv
    property string src
    property real radius: 8
    property bool hover: false
    property bool shadow: false
    property bool small: false
    property bool blurred: false
    // The shadow, under it (on its own: padding the picture for it would crop it).
    Rectangle {
      id: shade
      anchors.fill: parent; radius: cv.radius; color: "black"
      visible: false; layer.enabled: true
    }
    MultiEffect {
      anchors.fill: parent
      visible: cv.shadow || cv.hover
      source: shade
      shadowEnabled: true; shadowColor: "black"
      shadowOpacity: cv.hover ? 0.5 : 0.4; shadowBlur: 1.0; shadowVerticalOffset: cv.hover ? 12 : 8
      opacity: 0.9
      scale: cv.hover ? 1.03 : 1
      Behavior on scale { NumberAnimation { duration: Theme.fast } }
    }
    Rectangle {
      id: ph
      anchors.fill: parent; radius: cv.radius
      gradient: Gradient { GradientStop { position: 0; color: Theme.dark ? "#3a3a42" : "#e4e4ea" } GradientStop { position: 1; color: Theme.dark ? "#26262c" : "#d2d2da" } }
      Sym { anchors.centerIn: parent; visible: img.status !== Image.Ready; name: "music"; width: parent.width * 0.32; height: width; color: Theme.textFaint }
    }
    Image {
      id: img
      anchors.fill: parent
      visible: false
      source: cv.src ? "file://" + cv.src : ""
      sourceSize: cv.small ? Qt.size(96, 96) : Qt.size(480, 480)
      fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true
    }
    MultiEffect {
      anchors.fill: parent
      visible: img.status === Image.Ready
      source: img
      maskEnabled: cv.radius > 0
      maskSource: mask
      blurEnabled: cv.blurred; blur: 1.0; blurMax: 64
      autoPaddingEnabled: false
      scale: cv.hover ? 1.03 : 1
      Behavior on scale { NumberAnimation { duration: Theme.fast } }
    }
    Item {
      id: mask
      anchors.fill: parent; layer.enabled: true; visible: false
      Rectangle { anchors.fill: parent; radius: cv.radius; color: "black" }
    }
  }

  component AlbumCard: Item {
    id: ac
    property var a
    height: width + 46
    Cover { width: ac.width; height: ac.width; radius: 8; src: ac.a ? ac.a.cover : ""; hover: ach.hovered }
    // Play straight from the cover.
    Rectangle {
      visible: ach.hovered
      anchors { left: parent.left; top: parent.top; margins: 10; topMargin: ac.width - 44 }
      width: 34; height: 34; radius: 17; color: Qt.rgba(0, 0, 0, 0.55)
      Sym { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; name: "play"; width: 14; height: 14; color: "#ffffff" }
      TapHandler { onTapped: app.playList(ac.a.tracks.map(t => t.path), 0, false) }
    }
    Txt { y: ac.width + 6; width: ac.width; text: ac.a ? ac.a.name : ""; font.weight: Font.Bold; elide: Text.ElideRight }
    Txt { y: ac.width + 24; width: ac.width; text: ac.a ? ac.a.artist : ""; color: Theme.textDim; elide: Text.ElideRight; font.pixelSize: Theme.small }
    HoverHandler { id: ach; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: app.go("album:" + ac.a.key) }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => menu.open(ac, ev.position.x, ev.position.y, ac.a.tracks.map(t => t.path)) }
  }

  component AlbumGrid: GridView {
    id: gv
    property string title
    clip: true; boundsBehavior: Flickable.StopAtBounds
    leftMargin: 28; rightMargin: 28; topMargin: 70; bottomMargin: 20
    readonly property int cols: Math.max(2, Math.floor((width - 56) / 200))
    cellWidth: (width - 56) / cols; cellHeight: cellWidth + 34
    Txt { parent: gv; x: 28; y: 20; text: gv.title; font.pixelSize: 26; font.weight: Font.Bold }
    delegate: Item {
      required property var modelData
      width: gv.cellWidth; height: gv.cellHeight
      AlbumCard { x: 9; width: parent.width - 18; a: modelData }
    }
  }

  // A list of songs with a heading, Play and Shuffle.
  component SongTable: ListView {
    id: st
    property string title
    property var list: []
    property string empty: ""
    property bool editable: false
    property int playlist: -1
    clip: true; boundsBehavior: Flickable.StopAtBounds
    model: list
    leftMargin: 28; rightMargin: 28
    header: Column {
      width: st.width - 56
      spacing: 10
      Item { width: 1; height: 14 }
      Row {
        spacing: 12
        TextInput {
          id: ttl
          text: st.title; readOnly: !st.editable
          color: Theme.text; font.family: Theme.font; font.pixelSize: 26; font.weight: Font.Bold
          selectByMouse: st.editable
          onEditingFinished: if (st.editable) app.renamePlaylist(st.playlist, text)
        }
        Txt { anchors.baseline: ttl.baseline; text: st.list.length ? st.list.length + " songs · " + app.minutes(st.list) : ""; color: Theme.textDim; font.pixelSize: Theme.small }
      }
      Row {
        spacing: 10
        visible: st.list.length > 0 || st.editable
        Pill { visible: st.list.length > 0; text: "▶  Play"; strong: true; onClicked: app.playList(st.list.map(t => t.path), 0, false) }
        Pill { visible: st.list.length > 0; text: "Shuffle"; onClicked: app.playList(st.list.map(t => t.path), Math.floor(Math.random() * st.list.length), true) }
        Pill { visible: st.editable; text: "Delete Playlist"; danger: true; onClicked: app.deletePlaylist(st.playlist) }
      }
      Txt { visible: !st.list.length && st.empty !== ""; text: st.empty; color: Theme.textDim; topPadding: 20 }
      Item { width: 1; height: 6 }
      Row {
        visible: st.list.length > 0
        x: 40
        Txt { width: (st.width - 56 - 40 - 70) * 0.42; text: "Title"; color: Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Bold }
        Txt { width: (st.width - 56 - 40 - 70) * 0.29; text: "Artist"; color: Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Bold }
        Txt { width: (st.width - 56 - 40 - 70) * 0.29; text: "Album"; color: Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Bold }
      }
    }
    delegate: SongRow {
      required property var modelData
      required property int index
      width: st.width - 56
      t: modelData; showAlbum: true; striped: index % 2 === 1; withCover: true
      playing: app.current && app.current.path === modelData.path
      onPlay: app.playList(st.list.map(x => x.path), index, false)
      onContext: (it, x, y) => menu.open(it, x, y, [modelData.path], st.playlist >= 0 ? { playlist: st.playlist } : {})
    }
  }

  // One song: double-click (or click its number) plays; right-click for more.
  component SongRow: Item {
    id: sr
    property var t
    property bool numbered: false
    property bool showAlbum: false
    property bool striped: false
    property bool withCover: false
    property bool compact: false
    property bool playing: false
    property bool dim: false
    signal play()
    signal context(var item, real x, real y)
    height: compact ? 46 : 36
    opacity: dim ? 0.5 : 1
    Rectangle { anchors.fill: parent; radius: 6; color: srh.hovered ? Theme.hover : (sr.striped ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.025) : "transparent") }
    // the number, the playing bars, or a play button on hover
    Item {
      id: lead
      x: sr.compact ? 10 : 6; width: sr.compact ? 36 : 30; height: parent.height
      Txt { anchors.centerIn: parent; visible: sr.numbered && !sr.playing && !srh.hovered; text: sr.t.track || ""; color: Theme.textDim; font.pixelSize: Theme.small }
      Cover { anchors.centerIn: parent; visible: (sr.withCover || sr.compact) && !srh.hovered && !sr.playing; width: sr.compact ? 34 : 26; height: width; radius: 4; src: sr.t.cover || ""; small: true }
      Bars { anchors.centerIn: parent; visible: sr.playing && !srh.hovered }
      Sym { anchors.centerIn: parent; visible: srh.hovered; name: "play"; width: 12; height: 12; color: Theme.text }
      TapHandler { onTapped: sr.play() }
    }
    readonly property real w: width - lead.width - lead.x - 80
    Column {
      visible: sr.compact
      anchors { left: lead.right; leftMargin: 10; right: parent.right; rightMargin: 52; verticalCenter: parent.verticalCenter }
      Txt { width: parent.width; text: sr.t.title; elide: Text.ElideRight; color: sr.playing ? Theme.accent : Theme.text }
      Txt { width: parent.width; text: sr.t.artist; elide: Text.ElideRight; color: Theme.textDim; font.pixelSize: Theme.small }
    }
    Row {
      visible: !sr.compact
      anchors { left: lead.right; leftMargin: 6; verticalCenter: parent.verticalCenter }
      Txt { width: sr.showAlbum ? sr.w * 0.42 : sr.w; rightPadding: 12; text: sr.t.title; elide: Text.ElideRight; color: sr.playing ? Theme.accent : Theme.text; font.weight: sr.playing ? Font.Bold : Font.Normal }
      Txt { visible: sr.showAlbum; width: sr.w * 0.29; rightPadding: 12; text: sr.t.artist; elide: Text.ElideRight; color: Theme.textDim }
      Txt { visible: sr.showAlbum; width: sr.w * 0.29; rightPadding: 12; text: sr.t.album; elide: Text.ElideRight; color: Theme.textDim }
    }
    Sym {
      anchors { right: parent.right; rightMargin: 50; verticalCenter: parent.verticalCenter }
      visible: srh.hovered || !!app.favs[sr.t.path]
      name: "heart"; filled: !!app.favs[sr.t.path]; width: 13; height: 13
      color: app.favs[sr.t.path] ? "#ff4f6d" : Theme.textDim
      TapHandler { onTapped: app.toggleFav(sr.t.path) }
    }
    Txt { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } text: app.time(sr.t.dur); color: Theme.textDim; font.pixelSize: Theme.small }
    HoverHandler { id: srh }
    TapHandler { onDoubleTapped: sr.play() }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: ev => sr.context(sr, ev.position.x, ev.position.y) }
  }

  // Three bars dancing while a song plays.
  component Bars: Row {
    spacing: 2
    Repeater {
      model: 3
      delegate: Rectangle {
        required property int index
        width: 3; radius: 1.5; color: Theme.accent
        anchors.bottom: parent.bottom
        height: 4
        SequentialAnimation on height {
          running: app.playing; loops: Animation.Infinite
          NumberAnimation { to: 6 + (index * 5) % 9; duration: 260 + index * 70 }
          NumberAnimation { to: 3; duration: 300 + index * 50 }
        }
      }
    }
    height: 14
  }

  component NavItem: Item {
    id: ni
    property string sym; property string label; property string target
    readonly property bool here: app.view === target && !app.query
    width: nav.width; height: 30
    Rectangle {
      anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
      radius: 7
      color: ni.here ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.35 : 0.18) : (nh.hovered ? Theme.hover : "transparent")
    }
    Sym { x: 20; anchors.verticalCenter: parent.verticalCenter; name: ni.sym; width: 14; height: 14; color: ni.here ? Theme.text : Theme.accent; filled: ni.sym === "heart" }
    Txt { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 56; elide: Text.ElideRight; text: ni.label }
    HoverHandler { id: nh }
    TapHandler { onTapped: { app.back = []; app.view = ni.target; app.query = ""; search.text = ""; app.showLyrics = false } }
  }
  component Head: Txt { x: 20; height: 30; verticalAlignment: Text.AlignBottom; bottomPadding: 4; color: Theme.textDim; font.pixelSize: Theme.small - 0.5; font.weight: Font.Bold }

  // The colour of a cover: its pixels averaged, the vivid ones counting more.
  component ColorPick: Canvas {
    id: cp
    property string src
    property color color: Theme.dark ? "#3a3a44" : "#c8c8d0"
    readonly property color vivid: Qt.hsla(color.hslHue, Math.max(0.45, color.hslSaturation), Theme.dark ? 0.62 : 0.45, 1)
    width: 12; height: 12; opacity: 0
    readonly property string url: src ? "file://" + src : ""
    onUrlChanged: { if (url) { if (isImageLoaded(url)) requestPaint(); else loadImage(url) } }
    onImageLoaded: requestPaint()
    onPaint: {
      if (!url || !isImageLoaded(url)) return
      const ctx = getContext("2d")
      ctx.clearRect(0, 0, 12, 12)
      ctx.drawImage(url, 0, 0, 12, 12)
      const d = ctx.getImageData(0, 0, 12, 12).data
      let r = 0, g = 0, b = 0, n = 0
      for (let i = 0; i < d.length; i += 4) {
        const mx = Math.max(d[i], d[i + 1], d[i + 2]), mn = Math.min(d[i], d[i + 1], d[i + 2])
        const w = 1 + 6 * (mx - mn) / 255            // saturated pixels weigh more
        r += d[i] * w; g += d[i + 1] * w; b += d[i + 2] * w; n += w
      }
      if (n) cp.color = Qt.rgba(r / n / 255, g / n / 255, b / n / 255, 1)
    }
  }

  component BigBtn: Item {
    id: bb
    property string sym
    property real size: 22
    property bool on: false
    signal clicked()
    width: size + 20; height: size + 20
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    Sym { anchors.centerIn: parent; name: bb.sym; width: bb.size; height: bb.size; color: bb.on ? "#ffffff" : Qt.rgba(1, 1, 1, bbh.hovered ? 1 : 0.8) }
    Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 2.5; anchors.verticalCenterOffset: bb.size / 2 + 8; visible: bb.on; color: "#ffffff" }
    scale: bbp.pressed ? 0.88 : 1
    Behavior on scale { NumberAnimation { duration: 120 } }
    HoverHandler { id: bbh; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: bbp; onTapped: bb.clicked() }
  }

  component Btn: Rectangle {
    id: b
    property string sym
    property real size: 16
    property bool on: false
    property string tip
    signal clicked()
    width: size + 18; height: size + 16; radius: 8
    color: bh.hovered && enabled ? Theme.hover : "transparent"
    Sym { anchors.centerIn: parent; name: b.sym; width: b.size; height: b.size; color: b.on ? Theme.accent : Theme.text }
    HoverHandler { id: bh }
    TapHandler { enabled: b.enabled; onTapped: b.clicked() }
    Tip { text: b.tip }
  }

  component Pill: Rectangle {
    id: pl
    property string text
    property bool strong: false
    property bool danger: false
    signal clicked()
    implicitWidth: pt.implicitWidth + 30; implicitHeight: 32
    width: implicitWidth; height: implicitHeight; radius: 8
    color: strong ? (danger ? Theme.red : Theme.accent) : (ph2.hovered ? Theme.pressed : Theme.field)
    Txt { id: pt; anchors.centerIn: parent; text: pl.text; color: pl.strong ? "#ffffff" : (pl.danger ? Theme.red : Theme.accent); font.weight: Font.Bold }
    HoverHandler { id: ph2; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: pl.clicked() }
  }
}
