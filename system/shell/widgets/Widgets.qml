import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.core
import qs.ui

// Desktop widgets: small glass cards on the desktop picture, under the
// windows. Right-click the desktop and choose Edit Widgets to move them
// (drag), remove them (−) or add new ones from the gallery. The layout is
// kept in ~/.config/memora/widgets.json.
// Widgets of your own (Memora AI makes them): type "custom", file NAME, which
// is ~/.config/memora/widgets/NAME.qml. Entries without x/y get a free spot.
Item {
  id: root
  anchors.fill: parent
  property bool editing: false
  readonly property bool primary: true

  // ---- layout ----------------------------------------------------------------
  readonly property real unit: 168            // a small widget; medium is two wide
  readonly property real gap: 16
  readonly property var kinds: [
    { type: "clock", name: "Clock", sizes: ["small"] },
    { type: "weather", name: "Weather", sizes: ["small", "medium"] },
    { type: "calendar", name: "Calendar", sizes: ["small", "medium"] },
    { type: "system", name: "System", sizes: ["small", "medium"] },
    { type: "music", name: "Now Playing", sizes: ["medium"] },
    { type: "notes", name: "Notes", sizes: ["small", "medium"] }
  ]
  readonly property var defaults: [
    { type: "weather", size: "medium", x: 24, y: 48 },
    { type: "clock", size: "small", x: 24, y: 48 + 168 + 16 },
    { type: "calendar", size: "small", x: 24 + 168 + 16, y: 48 + 168 + 16 },
    { type: "music", size: "medium", x: 24, y: 48 + 2 * (168 + 16) }
  ]
  property var layout: []
  FileView {
    id: store
    path: Quickshell.env("HOME") + "/.config/memora/widgets.json"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { root.layout = JSON.parse(text()); Qt.callLater(root.placeNew); Qt.callLater(root.snapAll) } catch (e) { root.layout = root.defaults } }
    onLoadFailed: root.layout = root.defaults
  }
  function save(l) { layout = l; store.setText(JSON.stringify(l, null, 1) + "\n") }
  // The grid: cells of one small widget; medium ones take two side by side.
  readonly property real ox: 24
  readonly property real oy: 48
  readonly property real step: unit + gap
  readonly property int cols: Math.max(2, Math.floor((width - ox) / step))
  readonly property int rows: Math.max(2, Math.floor((height - oy - 110) / step))
  function spanOf(o) { return o.size === "medium" ? 2 : 1 }
  function cellOf(o) { return { c: Math.round((o.x - ox) / step), r: Math.round((o.y - oy) / step) } }
  function free(c, r, span, skip) {
    if (c < 0 || r < 0 || c + span > cols || r >= rows) return false
    return !layout.some((o, j) => {
      if (j === skip) return false
      const k = cellOf(o), sp = spanOf(o)
      return k.r === r && c < k.c + sp && c + span > k.c
    })
  }
  // The nearest free spot to where a widget was dropped.
  function nearest(c, r, span, skip) {
    let best = null, bd = 1e9
    for (let rr = 0; rr < rows; rr++) for (let cc = 0; cc + span <= cols; cc++) {
      if (!free(cc, rr, span, skip)) continue
      const d = (cc - c) * (cc - c) + (rr - r) * (rr - r)
      if (d < bd) { bd = d; best = { c: cc, r: rr } }
    }
    return best
  }
  // Layouts saved before the grid: put each widget in its nearest cell.
  function snapAll() {
    if (width <= 0) return
    const l = layout.slice(); let changed = false
    for (let i = 0; i < l.length; i++) {
      const o = l[i], c = Math.round((o.x - ox) / step), r = Math.round((o.y - oy) / step)
      if (o.x === ox + c * step && o.y === oy + r * step) continue
      layout = l
      const k = nearest(c, r, spanOf(o), i)
      if (k) { l[i] = Object.assign({}, o, { x: ox + k.c * step, y: oy + k.r * step }); changed = true }
    }
    if (changed) save(l)
  }
  property var ghost: null       // { c, r, span } while dragging
  function dropCell(i, x, y) {
    const span = spanOf(layout[i])
    return nearest(Math.round((x - ox) / step), Math.round((y - oy) / step), span, i)
  }
  function move(i, x, y) {
    const k = dropCell(i, x, y)
    const l = layout.slice()
    if (k) l[i] = Object.assign({}, l[i], { x: ox + k.c * step, y: oy + k.r * step })
    ghost = null
    save(l)
  }
  function remove(i) { const l = layout.slice(); l.splice(i, 1); save(l) }
  // New entries (written by Memora AI) have no place yet: give each a free one.
  function placeNew() {
    if (width <= 0 || !layout.some(o => typeof o.x !== "number")) return
    let l = layout.filter(o => typeof o.x === "number")
    const fresh = layout.filter(o => typeof o.x !== "number")
    layout = l
    fresh.forEach(o => {
      const k = nearest(0, 0, o.size === "medium" ? 2 : 1, -1)
      if (!k) return
      l = l.concat([Object.assign({}, o, { x: ox + k.c * step, y: oy + k.r * step })])
      layout = l
    })
    save(l)
  }
  function add(type, size) {
    const span = size === "medium" ? 2 : 1
    const k = nearest(0, 0, span, -1)
    if (!k) return
    save(layout.concat([{ type: type, size: size, x: ox + k.c * step, y: oy + k.r * step }]))
  }

  // ---- shared data ------------------------------------------------------------
  // Time, refreshed each second.
  property date now: new Date()
  Timer { interval: 1000; running: true; repeat: true; onTriggered: root.now = new Date() }

  // Weather from Open-Meteo (no account needed), for where you are.
  property var weather: null      // { temp, code, hi, lo, place, days: [{ day, code, hi, lo }] }
  Process {
    id: wx
    command: ["bash", "-c", "loc=$(memora-location) || exit 1; lat=$(jq -r .latitude <<<\"$loc\"); lon=$(jq -r .longitude <<<\"$loc\"); city=$(jq -r .city <<<\"$loc\"); f=$(curl -sf --max-time 8 \"https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,weather_code&timezone=auto&forecast_days=5\") || exit 1; jq -c --arg c \"$city\" '{temp: .current.temperature_2m, code: .current.weather_code, hi: .daily.temperature_2m_max[0], lo: .daily.temperature_2m_min[0], place: $c, days: [range(0;5) as $i | {day: .daily.time[$i], code: .daily.weather_code[$i], hi: .daily.temperature_2m_max[$i], lo: .daily.temperature_2m_min[$i]}]}' <<<\"$f\""]
    stdout: StdioCollector { onStreamFinished: { try { root.weather = JSON.parse(text); wxCache.setText(text) } catch (e) { wxRetry.start() } } }
    onExited: code => { if (code !== 0) wxRetry.start() }
  }
  // No answer (offline, or a service busy): again in two minutes, not in half an hour;
  // meanwhile the last weather known.
  Timer { id: wxRetry; interval: 120000; onTriggered: wx.running = true }
  FileView {
    id: wxCache
    path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/memora/weather.json"
    printErrors: false
    onLoaded: if (!root.weather) { try { root.weather = JSON.parse(text()) } catch (e) {} }
  }
  Timer { interval: 30 * 60 * 1000; running: root.layout.some(o => o.type === "weather"); repeat: true; triggeredOnStart: true; onTriggered: wx.running = true }
  function wxSym(code) {
    if (code === 0 || code === 1) return "sun"
    if (code === 2) return "suncloud"
    if (code === 3) return "cloud"
    if (code === 45 || code === 48) return "fog"
    if (code >= 71 && code <= 77 || code === 85 || code === 86) return "snow"
    if (code >= 95) return "storm"
    return "rain"
  }
  function wxName(code) {
    return ({ 0: "Clear", 1: "Mostly Clear", 2: "Partly Cloudy", 3: "Cloudy", 45: "Fog", 48: "Fog" })[code]
      || (code >= 51 && code <= 57 ? "Drizzle" : code >= 61 && code <= 67 ? "Rain" : code >= 71 && code <= 77 ? "Snow"
      : code >= 80 && code <= 82 ? "Showers" : code >= 85 && code <= 86 ? "Snow Showers" : code >= 95 ? "Thunderstorm" : "")
  }

  // CPU, memory and disk.
  property real cpu: 0
  property real mem: 0
  property real disk: 0
  property var prev: null
  Process {
    id: sysq
    command: ["bash", "-c", "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; df --output=pcent / | tail -1"]
    stdout: StdioCollector {
      onStreamFinished: {
        const l = text.trim().split("\n")
        const c = l[0].split(/\s+/).slice(1).map(Number)
        if (root.prev) { const idle = c[3] + c[4] - root.prev[3] - root.prev[4]; const tot = c.reduce((a, b) => a + b) - root.prev.reduce((a, b) => a + b); root.cpu = tot > 0 ? 1 - idle / tot : 0 }
        root.prev = c
        const mt = parseInt(l[1].split(/\s+/)[1]), ma = parseInt(l[2].split(/\s+/)[1])
        root.mem = 1 - ma / mt
        root.disk = parseInt(l[3]) / 100
      }
    }
  }
  Timer { interval: 3000; running: root.layout.some(o => o.type === "system"); repeat: true; triggeredOnStart: true; onTriggered: sysq.running = true }

  // The latest notes from Notes.
  property var notes: []
  FileView {
    path: Quickshell.env("HOME") + "/.local/share/memora/notes.json"
    printErrors: false; watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { const j = JSON.parse(text()); const list = (j.notes || j).filter(n => !n.deleted); list.sort((a, b) => (b.pinned - a.pinned) || (b.modified - a.modified)); root.notes = list.slice(0, 4) } catch (e) {} }
  }

  readonly property var player: Sys.player

  // ---- the grid, while editing -------------------------------------------------
  Repeater {
    model: root.editing ? root.cols * root.rows : 0
    delegate: Rectangle {
      required property int index
      x: root.ox + (index % root.cols) * root.step; y: root.oy + Math.floor(index / root.cols) * root.step
      width: root.unit; height: root.unit; radius: 24
      color: "transparent"
      border.width: 1.5; border.color: Qt.rgba(1, 1, 1, 0.16)
      opacity: 0
      Component.onCompleted: opacity = 1
      Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    }
  }
  Rectangle {
    visible: !!root.ghost
    x: root.ghost ? root.ox + root.ghost.c * root.step : 0
    y: root.ghost ? root.oy + root.ghost.r * root.step : 0
    width: root.ghost ? root.ghost.span * root.unit + (root.ghost.span - 1) * root.gap : 0
    height: root.unit; radius: 24
    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
    border.width: 2; border.color: Theme.accent
    Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Theme.easing } }
    Behavior on y { NumberAnimation { duration: Theme.fast; easing.type: Theme.easing } }
  }

  // ---- the widgets -------------------------------------------------------------
  Repeater {
    model: root.layout
    delegate: Item {
      id: w
      required property var modelData
      required property int index
      readonly property bool medium: modelData.size === "medium"
      x: modelData.x; y: modelData.y
      width: medium ? 2 * root.unit + root.gap : root.unit
      height: root.unit
      // Appear softly, one after another.
      opacity: 0; scale: 0.94
      Component.onCompleted: appear.start()
      ParallelAnimation {
        id: appear
        SequentialAnimation { PauseAnimation { duration: Prefs.motion(w.index * 70) } NumberAnimation { target: w; property: "opacity"; to: 1; duration: Prefs.motion(420); easing.type: Easing.OutCubic } }
        SequentialAnimation { PauseAnimation { duration: Prefs.motion(w.index * 70) } NumberAnimation { target: w; property: "scale"; to: 1; duration: Prefs.motion(520); easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
      }
      Behavior on x { enabled: !drag.active; NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
      Behavior on y { enabled: !drag.active; NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }

      // A gentle wiggle while editing.
      rotation: root.editing ? (w.index % 2 ? 0.6 : -0.6) * wig.v : 0
      QtObject { id: wig; property real v: 0 }
      SequentialAnimation {
        running: root.editing && Prefs.animations; loops: Animation.Infinite
        NumberAnimation { target: wig; property: "v"; from: -1; to: 1; duration: 260 + w.index * 13; easing.type: Easing.InOutSine }
        NumberAnimation { target: wig; property: "v"; from: 1; to: -1; duration: 260 + w.index * 13; easing.type: Easing.InOutSine }
      }

      Glass {
        id: card
        anchors.fill: parent
        radius: 24
        fill: Theme.dark ? Qt.rgba(0.09, 0.09, 0.11, 0.55) : Qt.rgba(1, 1, 1, 0.55)
        shadowSize: 24
        scale: drag.active ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
        Loader {
          anchors { fill: parent; margins: 16 }
          sourceComponent: ({ clock: clockC, weather: weatherC, calendar: calendarC, system: systemC, music: musicC, notes: notesC, custom: customC })[w.modelData.type] || null
          property bool medium: w.medium
          property string file: w.modelData.file || ""
        }
      }
      // Remove, while editing.
      Rectangle {
        visible: root.editing
        x: -8; y: -8; width: 24; height: 24; radius: 12
        color: Theme.dark ? "#3a3a3e" : "#e5e5ea"
        border.color: Qt.rgba(0, 0, 0, 0.2)
        Rectangle { anchors.centerIn: parent; width: 10; height: 2; radius: 1; color: Theme.text }
        TapHandler { onTapped: root.remove(w.index) }
      }
      DragHandler {
        id: drag
        enabled: root.editing
        onActiveChanged: if (!active) root.move(w.index, w.x, w.y)
        onTranslationChanged: if (active) { const k = root.dropCell(w.index, w.x, w.y); root.ghost = k ? { c: k.c, r: k.r, span: root.spanOf(w.modelData) } : null }
      }
      z: drag.active ? 10 : 0
      TapHandler {
        enabled: !root.editing
        onTapped: {
          const open = ({ calendar: "memora-shell toggle calendar", system: "memora-app activity", notes: "memora-app notes", music: "", weather: "", clock: "" })[w.modelData.type]
          if (open) Apps.run(open)
        }
      }
    }
  }

  // ---- widget faces ------------------------------------------------------------
  // A widget of your own: ~/.config/memora/widgets/NAME.qml, reloaded when the
  // file changes. Its root may declare `property var memora`, which gets
  // { dark, text, dim, accent, font, small, large, medium }. Whether it loaded
  // is written next to it in NAME.status ("ok" or the error), for Memora AI.
  Component {
    id: customC
    Item {
      id: cw
      readonly property string file: parent ? parent.file : ""
      readonly property bool medium: parent ? parent.medium : false
      readonly property string path: Quickshell.env("HOME") + "/.config/memora/widgets/" + file + ".qml"
      // Loaded from a copy with a new name each time it changes: QML keeps
      // what it loaded once per name (and a "?v=" on the name spoils its errors).
      property int ver: 0
      property string loadPath: ""
      readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/memora/widgets"
      function refresh() {
        if (!file) return
        ver++
        copier.dest = cacheDir + "/" + file + "-" + ver + ".qml"
        // (old copies go after a while, not now: the one showing may still be read)
        copier.command = ["bash", "-c", "mkdir -p \"$3\" && find \"$3\" -name \"$4-*.qml\" -mmin +10 -delete; cp -- \"$1\" \"$2\"", "_", path, copier.dest, cacheDir, file]
        copier.running = true
      }
      Process { id: copier; property string dest; onExited: code => { if (code === 0) cw.loadPath = dest } }
      FileView { path: cw.file ? cw.path : ""; watchChanges: true; printErrors: false; onFileChanged: cw.refresh() }
      Component.onCompleted: refresh()
      FileView { id: statusFile; path: cw.file ? cw.path.replace(/\.qml$/, ".status") : ""; printErrors: false }
      Loader {
        id: ld
        anchors.fill: parent
        source: cw.loadPath ? "file://" + cw.loadPath : ""
        // Reported for every new copy (an error again after a fix is not a "change").
        onStatusChanged: report()
        onSourceChanged: Qt.callLater(report)
        property string reported: ""
        function report() {
          if (status !== Loader.Error && status !== Loader.Ready) return
          const key = source + status
          if (key === reported) return
          reported = key
          if (status === Loader.Error) {
            const c = Qt.createComponent(source)
            // (the copy's number makes each report differ, so it is written every time)
            statusFile.setText("error " + cw.ver + "\n" + (c.errorString() || "The widget could not be loaded.").split(cw.loadPath).join(cw.path) + "\n")
          } else
            statusFile.setText("ok " + cw.ver + "\n")
        }
        onLoaded: if (item && "memora" in item) item.memora = Qt.binding(() => ({
          dark: Theme.dark, text: Theme.text, dim: Theme.textDim, accent: Theme.accent,
          font: Theme.font, small: Theme.small, large: Theme.large, medium: cw.medium }))
      }
      Column {
        visible: ld.status === Loader.Error
        anchors.centerIn: parent
        width: parent.width
        spacing: 4
        Sym { anchors.horizontalCenter: parent.horizontalCenter; name: "info"; width: 20; height: 20; color: root.dim }
        Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: "This widget has a problem. Ask Memora AI to fix it."; color: root.dim; font.pixelSize: Theme.small }
      }
    }
  }

  readonly property color ink: Theme.text
  readonly property color dim: Theme.textDim

  Component {
    id: clockC
    Item {
      readonly property bool medium: parent ? parent.medium : false
      // An analog clock face.
      Canvas {
        id: face
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height); height: width
        property date t: root.now
        onTChanged: requestPaint()
        onPaint: {
          const c = getContext("2d"); c.reset()
          const r = width / 2, h = t.getHours() % 12, m = t.getMinutes(), s = t.getSeconds()
          c.translate(r, r)
          c.fillStyle = Theme.dark ? "#1c1c1f" : "#ffffff"
          c.beginPath(); c.arc(0, 0, r - 1, 0, Math.PI * 2); c.fill()
          c.fillStyle = Theme.dark ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.75)
          c.font = "bold " + Math.round(r * 0.17) + "px '" + Theme.font + "'"
          c.textAlign = "center"; c.textBaseline = "middle"
          for (let i = 1; i <= 12; i++) { const a = i * Math.PI / 6; c.fillText(String(i), Math.sin(a) * r * 0.76, -Math.cos(a) * r * 0.76) }
          const hand = (a, len, w, col) => { c.save(); c.rotate(a); c.strokeStyle = col; c.lineWidth = w; c.lineCap = "round"; c.beginPath(); c.moveTo(0, len * 0.12); c.lineTo(0, -len); c.stroke(); c.restore() }
          const ink = Theme.dark ? "#f5f5f7" : "#1c1c1e"
          hand((h + m / 60) * Math.PI / 6, r * 0.48, r * 0.07, ink)
          hand((m + s / 60) * Math.PI / 30, r * 0.7, r * 0.05, ink)
          hand(s * Math.PI / 30, r * 0.78, r * 0.02, "#ff9f0a")
          c.fillStyle = "#ff9f0a"; c.beginPath(); c.arc(0, 0, r * 0.045, 0, Math.PI * 2); c.fill()
        }
      }
    }
  }

  Component {
    id: weatherC
    Item {
      readonly property bool medium: parent ? parent.medium : false
      readonly property var wd: root.weather
      Txt { visible: !parent.wd; anchors.centerIn: parent; text: "Weather…"; color: root.dim }
      ColumnLayout {
        visible: !!parent.wd
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: medium ? parent.width * 0.42 : parent.width
        spacing: 0
        Txt { text: wd ? wd.place : ""; font.weight: Font.Bold; elide: Text.ElideRight; Layout.fillWidth: true }
        Txt { text: wd ? Math.round(wd.temp) + "°" : ""; font.pixelSize: 40; font.weight: Font.Light }
        Item { Layout.fillHeight: true }
        Sym { name: wd ? root.wxSym(wd.code) : "sun"; width: 20; height: 20; color: root.ink }
        Txt { text: wd ? root.wxName(wd.code) : ""; font.pixelSize: Theme.small; Layout.fillWidth: true; elide: Text.ElideRight }
        Txt { text: wd ? "H:" + Math.round(wd.hi) + "°  L:" + Math.round(wd.lo) + "°" : ""; font.pixelSize: Theme.small; color: root.dim }
      }
      Row {
        visible: medium && !!parent.wd
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 6
        Repeater {
          model: wd ? wd.days.slice(1, 5) : []
          delegate: Column {
            required property var modelData
            width: 38; spacing: 6
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(new Date(modelData.day + "T12:00"), "ddd"); color: root.dim; font.pixelSize: Theme.small }
            Sym { anchors.horizontalCenter: parent.horizontalCenter; name: root.wxSym(modelData.code); width: 18; height: 18; color: root.ink }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.hi) + "°"; font.pixelSize: Theme.small }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.lo) + "°"; color: root.dim; font.pixelSize: Theme.small }
          }
        }
      }
    }
  }

  Component {
    id: calendarC
    Item {
      readonly property bool medium: parent ? parent.medium : false
      readonly property date d: root.now
      // Small: the day; medium: day and the month.
      Column {
        anchors { left: parent.left; top: parent.top }
        width: medium ? parent.width * 0.38 : parent.width
        Txt { text: Qt.formatDate(d, "dddd").toUpperCase(); color: "#ff453a"; font.pixelSize: Theme.small; font.weight: Font.Bold }
        Txt { text: Qt.formatDate(d, "d"); font.pixelSize: 54; font.weight: Font.Light; topPadding: -4 }
        Txt { text: Qt.formatDate(d, "MMMM yyyy"); color: root.dim; font.pixelSize: Theme.small }
      }
      Grid {
        visible: medium
        anchors { right: parent.right; top: parent.top }
        columns: 7; columnSpacing: 2; rowSpacing: 1
        readonly property date first: new Date(parent.d.getFullYear(), parent.d.getMonth(), 1)
        readonly property int lead: (first.getDay() + 6) % 7
        readonly property int days: new Date(parent.d.getFullYear(), parent.d.getMonth() + 1, 0).getDate()
        Repeater { model: ["M", "T", "W", "T", "F", "S", "S"]; delegate: Txt { required property string modelData; width: 24; horizontalAlignment: Text.AlignHCenter; text: modelData; color: root.dim; font.pixelSize: Theme.small - 1; font.weight: Font.Bold } }
        Repeater {
          model: parent.lead + parent.days
          delegate: Item {
            required property int index
            readonly property int day: index - parent.lead + 1
            width: 24; height: 18
            Rectangle { anchors.centerIn: parent; width: 20; height: 18; radius: 9; color: "#ff453a"; visible: parent.day === root.now.getDate() }
            Txt { anchors.centerIn: parent; visible: parent.day > 0; text: parent.day; font.pixelSize: Theme.small - 1; color: parent.day === root.now.getDate() ? "#ffffff" : root.ink }
          }
        }
      }
    }
  }

  Component {
    id: systemC
    Item {
      readonly property bool medium: parent ? parent.medium : false
      Txt { id: st; text: "System"; font.weight: Font.Bold }
      Row {
        anchors { top: st.bottom; topMargin: 12; horizontalCenter: medium ? undefined : parent.horizontalCenter; left: medium ? parent.left : undefined }
        spacing: medium ? 26 : 10
        Repeater {
          model: medium ? [["CPU", root.cpu, "#30d158"], ["Memory", root.mem, "#0a84ff"], ["Disk", root.disk, "#ff9f0a"]] : [["CPU", root.cpu, "#30d158"], ["Memory", root.mem, "#0a84ff"]]
          delegate: Column {
            required property var modelData
            spacing: 6
            Canvas {
              width: medium ? 82 : 58; height: width
              property real v: modelData[1]
              Behavior on v { NumberAnimation { duration: Theme.slow; easing.type: Theme.easing } }
              onVChanged: requestPaint()
              onPaint: {
                const c = getContext("2d"); c.reset(); const r = width / 2 - 5
                c.lineWidth = 8; c.lineCap = "round"
                c.strokeStyle = Theme.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)
                c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke()
                c.strokeStyle = modelData[2]
                c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.01, v)); c.stroke()
              }
              Txt { anchors.centerIn: parent; text: Math.round(parent.v * 100) + "%"; font.pixelSize: Theme.small; font.weight: Font.Bold }
            }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[0]; color: root.dim; font.pixelSize: Theme.small }
          }
        }
      }
    }
  }

  Component {
    id: musicC
    Item {
      readonly property bool medium: parent ? parent.medium : false
      readonly property var p: root.player
      Rectangle {
        id: art
        width: parent.height; height: parent.height; radius: 14
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
        clip: true
        Image { anchors.fill: parent; source: p ? (p.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready; asynchronous: true }
        Sym { anchors.centerIn: parent; name: "play"; width: 30; height: 30; color: root.dim; visible: !p || !p.trackArtUrl }
      }
      Column {
        anchors { left: art.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 3
        Txt { width: parent.width; text: p ? (p.trackTitle || "Not Playing") : "Not Playing"; font.weight: Font.Bold; elide: Text.ElideRight }
        Txt { width: parent.width; text: p ? (p.trackArtist || Sys.playerName(p)) : "Play something to see it here"; color: root.dim; font.pixelSize: Theme.small; elide: Text.ElideRight }
        Item { width: 1; height: 10 }
        Row {
          spacing: 18
          visible: !!p
          Repeater {
            model: [["prev", "next"], [root.player && root.player.isPlaying ? "pause" : "play", "toggle"], ["next", "next2"]]
            delegate: Item {
              required property var modelData
              width: 24; height: 24
              Sym { anchors.centerIn: parent; name: modelData[0] === "prev" ? "next" : modelData[0]; rotation: modelData[0] === "prev" ? 180 : 0; width: modelData[1] === "toggle" ? 22 : 16; height: width; color: root.ink }
              TapHandler {
                onTapped: {
                  const pl = root.player; if (!pl) return
                  if (modelData[1] === "toggle") pl.togglePlaying(); else if (modelData[1] === "next") pl.previous(); else pl.next()
                }
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: notesC
    Item {
      readonly property bool medium: parent ? parent.medium : false
      Row {
        id: nh
        spacing: 7
        Rectangle { width: 18; height: 18; radius: 5; color: "#f5b72e"; Sym { anchors.centerIn: parent; name: "check"; width: 10; height: 10; color: "#ffffff" } }
        Txt { text: "Notes"; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
      }
      Column {
        anchors { left: parent.left; right: parent.right; top: nh.bottom; topMargin: 10 }
        spacing: 8
        Repeater {
          model: root.notes.slice(0, medium ? 3 : 2)
          delegate: Column {
            required property var modelData
            width: parent.width
            Txt { width: parent.width; text: (modelData.text || "").split("\n")[0] || "New Note"; font.weight: Font.Medium; elide: Text.ElideRight }
            Txt { width: parent.width; text: ((modelData.text || "").split("\n").slice(1).join(" ").trim()) || "No additional text"; color: root.dim; font.pixelSize: Theme.small; elide: Text.ElideRight }
          }
        }
        Txt { visible: root.notes.length === 0; text: "No notes yet"; color: root.dim; font.pixelSize: Theme.small }
      }
    }
  }

  // ---- editing: the gallery ------------------------------------------------------
  Glass {
    id: gallery
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.editing ? parent.height - height - 112 : parent.height + 20
    opacity: root.editing ? 1 : 0
    visible: opacity > 0
    Behavior on y { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
    Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    width: grow.implicitWidth + 40; height: 132
    radius: 26
    fill: Theme.glassStrong
    shadowSize: 40
    RowLayout {
      id: grow
      anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
      spacing: 12
      Repeater {
        model: root.kinds
        delegate: Column {
          required property var modelData
          spacing: 6
          Rectangle {
            width: 92; height: 64; radius: 14
            color: gh.hovered ? Theme.pressed : Theme.hover
            border.color: Theme.separator
            Sym {
              anchors.centerIn: parent; width: 24; height: 24; color: Theme.text
              name: ({ clock: "clock", weather: "suncloud", calendar: "display", system: "gear", music: "play", notes: "check" })[modelData.type]
            }
            Txt { anchors { right: parent.right; bottom: parent.bottom; margins: 6 } text: "+"; font.weight: Font.Bold; color: Theme.accent }
            HoverHandler { id: gh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.add(modelData.type, modelData.sizes[0]) }
            // Right-click: the larger size, when there is one.
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.add(modelData.type, modelData.sizes[modelData.sizes.length - 1]) }
          }
          Txt { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; font.pixelSize: Theme.small }
        }
      }
      Rectangle { width: 1; height: 70; color: Theme.separator }
      Rectangle {
        width: dn.implicitWidth + 30; height: 34; radius: 17
        color: Theme.accent
        Txt { id: dn; anchors.centerIn: parent; text: "Done"; color: "#ffffff"; font.weight: Font.Bold }
        TapHandler { onTapped: root.editing = false }
      }
    }
  }
  Txt {
    visible: root.editing
    anchors { horizontalCenter: gallery.horizontalCenter; bottom: gallery.top; bottomMargin: 10 }
    text: "Drag widgets to move them. Click to add; right-click for the larger size."
    color: "#ffffff"; style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.4)
    font.pixelSize: Theme.small
  }
}
