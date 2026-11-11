import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import QtQuick.Effects
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.core
import qs.ui
import "../core/cal.js" as Cal

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
  // The desktop picture, frosted (wallpaper/Wallpaper.qml): what the widgets' glass shows.
  property Item backdrop: null

  // ---- layout ----------------------------------------------------------------
  readonly property real unit: 168            // a small widget; medium is two wide
  readonly property real gap: 16
  readonly property var kinds: [
    { type: "clock", name: "Clock", sizes: ["small"] },
    { type: "worldclock", name: "World Clock", sizes: ["medium", "large"] },
    { type: "weather", name: "Weather", sizes: ["small", "medium", "large"] },
    { type: "calendar", name: "Calendar", sizes: ["small", "medium", "large"] },
    { type: "upnext", name: "Up Next", sizes: ["small", "medium"] },
    { type: "reminders", name: "Reminders", sizes: ["small", "medium", "large"] },
    { type: "batteries", name: "Batteries", sizes: ["small", "medium", "large"] },
    { type: "photos", name: "Photos", sizes: ["small", "medium", "large"] },
    { type: "stocks", name: "Stocks", sizes: ["small", "medium", "large"] },
    { type: "music", name: "Now Playing", sizes: ["small", "medium"] },
    { type: "notes", name: "Notes", sizes: ["small", "medium", "large"] },
    { type: "system", name: "System", sizes: ["small", "medium"] }
  ]
  readonly property var sizeNames: ({ small: "S", medium: "M", large: "L" })
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
  function spanOf(o) { return o.size === "medium" || o.size === "large" ? 2 : 1 }
  function rowSpanOf(o) { return o.size === "large" ? 2 : 1 }
  function cellOf(o) { return { c: Math.round((o.x - ox) / step), r: Math.round((o.y - oy) / step) } }
  function free(c, r, span, skip, rspan) {
    rspan = rspan || 1
    if (c < 0 || r < 0 || c + span > cols || r + rspan > rows) return false
    return !layout.some((o, j) => {
      if (j === skip) return false
      const k = cellOf(o), sp = spanOf(o), rp = rowSpanOf(o)
      return r < k.r + rp && r + rspan > k.r && c < k.c + sp && c + span > k.c
    })
  }
  // The nearest free spot to where a widget was dropped.
  function nearest(c, r, span, skip, rspan) {
    let best = null, bd = 1e9
    for (let rr = 0; rr < rows; rr++) for (let cc = 0; cc + span <= cols; cc++) {
      if (!free(cc, rr, span, skip, rspan)) continue
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
      const k = nearest(c, r, spanOf(o), i, rowSpanOf(o))
      if (k) { l[i] = Object.assign({}, o, { x: ox + k.c * step, y: oy + k.r * step }); changed = true }
    }
    if (changed) save(l)
  }
  property var ghost: null       // { c, r, span } while dragging
  function dropCell(i, x, y) {
    const span = spanOf(layout[i])
    return nearest(Math.round((x - ox) / step), Math.round((y - oy) / step), span, i, rowSpanOf(layout[i]))
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
      const k = nearest(0, 0, spanOf(o), -1, rowSpanOf(o))
      if (!k) return
      l = l.concat([Object.assign({}, o, { x: ox + k.c * step, y: oy + k.r * step })])
      layout = l
    })
    save(l)
  }
  function add(type, size) {
    const span = size === "medium" || size === "large" ? 2 : 1
    const k = nearest(0, 0, span, -1, size === "large" ? 2 : 1)
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
    command: ["bash", "-c", "loc=$(memora-location) || exit 1; lat=$(jq -r .latitude <<<\"$loc\"); lon=$(jq -r .longitude <<<\"$loc\"); city=$(jq -r .city <<<\"$loc\"); f=$(curl -sf --max-time 8 \"https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset&timezone=auto&forecast_days=6\") || exit 1; jq -c --arg c \"$city\" '. as $f | ($f.hourly.time | map(.[0:13]) | indices($f.current.time[0:13])[0] // 0) as $h | {temp: .current.temperature_2m, code: .current.weather_code, hi: .daily.temperature_2m_max[0], lo: .daily.temperature_2m_min[0], sunrise: .daily.sunrise[0], sunset: .daily.sunset[0], place: $c, days: [range(0;6) as $i | {day: .daily.time[$i], code: .daily.weather_code[$i], hi: .daily.temperature_2m_max[$i], lo: .daily.temperature_2m_min[$i]}], hours: [range($h; $h + 6) as $i | {t: $f.hourly.time[$i], temp: $f.hourly.temperature_2m[$i], code: $f.hourly.weather_code[$i]}]}' <<<\"$f\""]
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

  // The latest notes from Notes, and their open checklist items (☐), which
  // the Reminders widget lists.
  property var notes: []
  property var todos: []          // [{ text, note }]
  FileView {
    path: Quickshell.env("HOME") + "/.local/share/memora/notes.json"
    printErrors: false; watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        const j = JSON.parse(text()); const list = (j.notes || j).filter(n => !n.deleted)
        list.sort((a, b) => (b.pinned - a.pinned) || (b.modified - a.modified))
        root.notes = list.slice(0, 7)
        const t = []
        list.forEach(n => {
          const lines = (n.text || "").split("\n")
          lines.forEach(l => { const s = l.trim(); if (s.startsWith("☐")) t.push({ text: s.slice(1).trim() || "Untitled", note: (lines[0] || "").replace(/^[☐☑•]\s*/, "").trim() }) })
        })
        root.todos = t
      } catch (e) {}
    }
  }

  // Calendar events coming up (from Calendar's file), refreshed each minute.
  property var calEvents: []
  property var calColors: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/share/memora/calendar.json"
    printErrors: false; watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        const j = JSON.parse(text()); const cols = {}
        const cals = j.calendars && j.calendars.length ? j.calendars : [{ id: "personal", color: "#3d8bff" }, { id: "work", color: "#ff9f0a" }, { id: "family", color: "#30d158" }]
        const on = cals.filter(c => c.on !== false).map(c => c.id)
        cals.forEach(c => cols[c.id] = c.color)
        root.calColors = cols
        root.calEvents = (j.events || []).filter(e => on.indexOf(e.cal) >= 0)
      } catch (e) {}
    }
  }
  property real minute: Date.now()
  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.minute = Date.now() }
  // The next events: still going or yet to start, within a week.
  readonly property var upcoming: Cal.occurrences(calEvents, minute, minute + 7 * Cal.DAY)
    .filter(o => o.ev.allDay ? Cal.startOfDay(o.start) + Cal.DAY > minute : o.end > minute)
    .sort((a, b) => a.start - b.start).slice(0, 8)
  function whenText(o) {
    const day = Cal.sameDay(o.start, minute) ? "Today" : Cal.sameDay(o.start, Cal.addDays(minute, 1)) ? "Tomorrow" : Qt.formatDate(new Date(o.start), "dddd")
    return o.ev.allDay ? day + " · All day" : day + " · " + Qt.formatTime(new Date(o.start), "HH:mm") + "–" + Qt.formatTime(new Date(o.end), "HH:mm")
  }

  // World Clock: each city's offset from UTC (asked every hour, for summer time).
  readonly property var cities: ["America/New_York", "Europe/London", "Asia/Tokyo", "Australia/Sydney", "Europe/Paris", "Asia/Dubai", "America/Los_Angeles", "Asia/Singapore"]
  property string localZone: ""
  property var zones: ({})        // "Europe/London" -> minutes east of UTC
  Process {
    id: tzq
    command: ["bash", "-c", "z=$(timedatectl show -p Timezone --value 2>/dev/null || readlink /etc/localtime | sed 's|.*/zoneinfo/||'); echo \"local $z\"; for c in \"$@\"; do echo \"$c $(TZ=$c date +%z)\"; done", "_"].concat(root.cities)
    stdout: StdioCollector {
      onStreamFinished: {
        const z = {}
        text.trim().split("\n").forEach(l => {
          const p = l.split(" ")
          if (p[0] === "local") root.localZone = p[1] || ""
          else if (/^[+-]\d{4}$/.test(p[1])) z[p[0]] = (p[1][0] === "-" ? -1 : 1) * (parseInt(p[1].slice(1, 3)) * 60 + parseInt(p[1].slice(3)))
        })
        root.zones = z
      }
    }
  }
  Timer { interval: 3600000; running: root.layout.some(o => o.type === "worldclock"); repeat: true; triggeredOnStart: true; onTriggered: tzq.running = true }
  function cityName(zone) { return (zone.split("/").pop() || zone).replace(/_/g, " ") }
  // The cities shown: yours first, then the others (not yours twice).
  function cityList(n) {
    const local = { zone: localZone, local: true }
    return [local].concat(cities.filter(c => c !== localZone && zones[c] !== undefined).map(c => ({ zone: c }))).slice(0, n)
  }
  function cityTime(c) {
    if (c.local) return root.now
    return new Date(root.now.getTime() + (zones[c.zone] + root.now.getTimezoneOffset()) * 60000)
  }
  function cityDiff(c) {
    if (c.local) return "Today"
    const t = cityTime(c), h = Math.round((zones[c.zone] + root.now.getTimezoneOffset()) / 60)
    const d = Cal.startOfDay(t) - Cal.startOfDay(root.now)
    return (d > 0 ? "Tomorrow" : d < 0 ? "Yesterday" : "Today") + ", " + (h >= 0 ? "+" : "") + h + "H"
  }

  // Batteries: the computer's and those of the mice, keyboards, headphones…
  readonly property var batteries: (UPower.devices ? UPower.devices.values : []).filter(d => d && d.isPresent !== false
    && d.type !== UPowerDeviceType.LinePower && d.type !== UPowerDeviceType.Unknown && (d.isLaptopBattery || d.percentage > 0))
    .sort((a, b) => b.isLaptopBattery - a.isLaptopBattery)
  function batteryName(d) {
    if (d.isLaptopBattery) return "This Computer"
    return d.model || UPowerDeviceType.toString(d.type)
  }
  function batterySym(d) {
    const t = d.type
    if (d.isLaptopBattery) return "laptop"
    if (t === UPowerDeviceType.Mouse || t === UPowerDeviceType.Touchpad) return "mouse"
    if (t === UPowerDeviceType.Keyboard) return "keyboard"
    if (t === UPowerDeviceType.Phone || t === UPowerDeviceType.Tablet) return "phone"
    if (t === UPowerDeviceType.GamingInput) return "gamepad"
    if (t === UPowerDeviceType.Headset || t === UPowerDeviceType.Headphones || t === UPowerDeviceType.Speakers || t === UPowerDeviceType.OtherAudio) return "sound"
    return "battery"
  }
  function charging(d) { return d.state === UPowerDeviceState.Charging || d.state === UPowerDeviceState.FullyCharged }

  // Photos: a few pictures from Pictures, a new choice every hour (Featured Photo).
  property var photos: []
  Process {
    id: photoq
    command: ["bash", "-c", "cd \"$HOME\" && find Pictures -name '.*' -prune -o -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -printf \"$HOME/%p\\n\" 2>/dev/null | shuf -n 12"]
    stdout: StdioCollector { onStreamFinished: root.photos = text.trim() ? text.trim().split("\n") : [] }
  }
  Timer { interval: 3600000; running: root.layout.some(o => o.type === "photos"); repeat: true; triggeredOnStart: true; onTriggered: photoq.running = true }

  // Stocks from Yahoo Finance (no account): the market indices and a few names.
  readonly property var symbols: ["^GSPC", "^IXIC", "^DJI", "AAPL", "MSFT", "GOOGL"]
  readonly property var symbolNames: ({ "^GSPC": "S&P 500", "^IXIC": "NASDAQ", "^DJI": "DOW" })
  property var quotes: []         // [{ sym, name, price, prev, closes }]
  property bool quotesFailed: false
  Process {
    id: stq
    command: ["bash", "-c", "for s in \"$@\"; do curl -sf --max-time 10 -H 'User-Agent: Mozilla/5.0' \"https://query1.finance.yahoo.com/v8/finance/chart/${s//^/%5E}?range=1d&interval=15m\" | jq -c '.chart.result[0] | {sym: .meta.symbol, name: (.meta.shortName // .meta.symbol), price: .meta.regularMarketPrice, prev: (.meta.chartPreviousClose // .meta.previousClose), closes: [.indicators.quote[0].close[] | select(. != null)]}'; done", "_"].concat(root.symbols)
    stdout: StdioCollector {
      onStreamFinished: {
        const q = []
        text.trim().split("\n").forEach(l => { try { const o = JSON.parse(l); if (o && o.price) q.push(o) } catch (e) {} })
        if (q.length) root.quotes = q
        root.quotesFailed = !q.length && !root.quotes.length
      }
    }
  }
  Timer { interval: 5 * 60000; running: root.layout.some(o => o.type === "stocks"); repeat: true; triggeredOnStart: true; onTriggered: stq.running = true }
  function stockName(q) { return root.symbolNames[q.sym] || q.sym }
  function stockChange(q) { return q.prev ? (q.price - q.prev) / q.prev * 100 : 0 }
  function money(v) { return v >= 1000 ? Number(v).toLocaleString(Qt.locale("en_US"), "f", 0) : Number(v).toFixed(2) }

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
    height: root.ghost ? (root.ghost.rspan || 1) * root.unit + ((root.ghost.rspan || 1) - 1) * root.gap : 0; radius: 24
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
      readonly property bool medium: modelData.size === "medium" || modelData.size === "large"
      readonly property bool tall: modelData.size === "large"
      x: modelData.x; y: modelData.y
      width: medium ? 2 * root.unit + root.gap : root.unit
      height: tall ? 2 * root.unit + root.gap : root.unit
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
        // Clear glass like the Dock's when the picture behind is there to bend, else a thicker sheet.
        fill: root.backdrop ? (Theme.tinted ? (Theme.dark ? Qt.rgba(0.08, 0.08, 0.10, Theme.see(0.26)) : Qt.rgba(1, 1, 1, Theme.see(0.24))) : Theme.glass)
          : (Theme.dark ? Qt.rgba(0.09, 0.09, 0.11, 0.55) : Qt.rgba(1, 1, 1, 0.55))
        backdrop: root.backdrop
        backdropRect: Qt.rect(w.x, w.y, w.width, w.height)
        scale: drag.active ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
        Loader {
          // (a photo fills the whole card)
          anchors { fill: parent; margins: w.modelData.type === "photos" ? 0 : 16 }
          sourceComponent: ({ clock: clockC, worldclock: worldC, weather: weatherC, calendar: calendarC, upnext: upnextC, reminders: remindersC,
                              batteries: batteriesC, photos: photosC, stocks: stocksC, system: systemC, music: musicC, notes: notesC, custom: customC })[w.modelData.type] || null
          property int slot: w.index
          property bool medium: w.medium
          property bool tall: w.tall
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
        onTranslationChanged: if (active) { const k = root.dropCell(w.index, w.x, w.y); root.ghost = k ? { c: k.c, r: k.r, span: root.spanOf(w.modelData), rspan: root.rowSpanOf(w.modelData) } : null }
      }
      z: drag.active ? 10 : 0
      TapHandler {
        enabled: !root.editing
        onTapped: {
          const open = ({ calendar: "memora-shell toggle calendar", upnext: "memora-shell toggle calendar", system: "memora-app activity", notes: "memora-app notes",
                          reminders: "memora-app notes", photos: "memora-photos", stocks: "xdg-open https://finance.yahoo.com/markets/" })[w.modelData.type]
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
      readonly property bool tall: parent ? parent.tall : false
      readonly property string path: Quickshell.env("HOME") + "/.config/memora/widgets/" + file + ".qml"
      // Loaded from a copy with a new name each time it changes: QML keeps
      // what it loaded once per name (and a "?v=" on the name spoils its errors).
      property int ver: 0
      property string loadPath: ""
      readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/memora/widgets"
      // The file often changes twice in a row (written, then written again). One copy
      // runs at a time; a change that comes meanwhile is copied right after, so the
      // name loaded is always one that exists.
      property bool again: false
      function refresh() {
        if (!file) return
        if (copier.running) { again = true; return }
        ver++
        // A new folder for every copy: QML remembers a folder's file list once, so a
        // file created later in a folder it already looked at is "not found"
        // (shown as "File name case mismatch") and only the first widget would load.
        copier.dest = cacheDir + "/" + file + "-" + ver + "/widget.qml"
        // (old copies go after a while, not now: the one showing may still be read)
        copier.command = ["bash", "-c", "mkdir -p \"$3\" && find \"$3\" -mindepth 1 -maxdepth 1 -name \"$4-*\" -mmin +10 -exec rm -rf {} +; mkdir -p \"$(dirname \"$2\")\" && cp -- \"$1\" \"$2\"", "_", path, copier.dest, cacheDir, file]
        copier.running = true
      }
      Process { id: copier; property string dest; onExited: code => { if (code === 0) cw.loadPath = dest; if (cw.again) { cw.again = false; cw.refresh() } } }
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
          font: Theme.font, small: Theme.small, large: Theme.large, medium: cw.medium, tall: cw.tall, width: ld.width, height: ld.height }))
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

  // An analog clock face: dark at night (or in dark mode), white by day.
  // Small faces get ticks instead of numbers.
  component Face: Canvas {
    property date t: root.now
    property bool night: Theme.dark
    onTChanged: requestPaint()
    onNightChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
      const c = getContext("2d"); c.reset()
      const r = width / 2, h = t.getHours() % 12, m = t.getMinutes(), s = t.getSeconds()
      c.translate(r, r)
      c.fillStyle = night ? "#1c1c1f" : "#ffffff"
      c.beginPath(); c.arc(0, 0, r - 1, 0, Math.PI * 2); c.fill()
      c.fillStyle = night ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(0, 0, 0, 0.75)
      c.strokeStyle = c.fillStyle
      if (width >= 90) {
        c.font = "bold " + Math.round(r * 0.17) + "px '" + Theme.font + "'"
        c.textAlign = "center"; c.textBaseline = "middle"
        for (let i = 1; i <= 12; i++) { const a = i * Math.PI / 6; c.fillText(String(i), Math.sin(a) * r * 0.76, -Math.cos(a) * r * 0.76) }
      } else {
        c.lineWidth = Math.max(1, r * 0.04); c.lineCap = "round"
        for (let i = 0; i < 12; i++) { const a = i * Math.PI / 6, l = i % 3 ? 0.86 : 0.78; c.beginPath(); c.moveTo(Math.sin(a) * r * l, -Math.cos(a) * r * l); c.lineTo(Math.sin(a) * r * 0.92, -Math.cos(a) * r * 0.92); c.stroke() }
      }
      const hand = (a, len, w, col) => { c.save(); c.rotate(a); c.strokeStyle = col; c.lineWidth = w; c.lineCap = "round"; c.beginPath(); c.moveTo(0, len * 0.12); c.lineTo(0, -len); c.stroke(); c.restore() }
      const ink = night ? "#f5f5f7" : "#1c1c1e"
      hand((h + m / 60) * Math.PI / 6, r * 0.48, r * 0.07, ink)
      hand((m + s / 60) * Math.PI / 30, r * 0.7, r * 0.05, ink)
      hand(s * Math.PI / 30, r * 0.78, Math.max(1, r * 0.02), "#ff9f0a")
      c.fillStyle = "#ff9f0a"; c.beginPath(); c.arc(0, 0, Math.max(1.5, r * 0.045), 0, Math.PI * 2); c.fill()
    }
  }

  // A ring that fills up (battery, CPU).
  component Ring: Canvas {
    property real v: 0
    property color col: "#30d158"
    property real thick: 6
    onVChanged: requestPaint()
    onColChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
      const c = getContext("2d"); c.reset(); const r = width / 2 - thick / 2 - 1
      c.lineWidth = thick; c.lineCap = "round"
      c.strokeStyle = Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.09)
      c.beginPath(); c.arc(width / 2, height / 2, r, 0, Math.PI * 2); c.stroke()
      c.strokeStyle = col
      c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.01, Math.min(1, v))); c.stroke()
    }
  }

  // A day's prices as a line, green when up, red when down, over a dotted line
  // at the day before's close.
  component Spark: Canvas {
    property var values: []
    property real base: 0
    readonly property bool up: values.length ? values[values.length - 1] >= base : true
    onValuesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      const c = getContext("2d"); c.reset()
      if (values.length < 2) return
      const lo = Math.min(base || values[0], Math.min.apply(null, values)), hi = Math.max(base || values[0], Math.max.apply(null, values))
      const span = hi - lo || 1, y = v => 2 + (height - 4) * (1 - (v - lo) / span), x = i => i / (values.length - 1) * width
      if (base) {
        c.strokeStyle = Theme.dark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.25); c.lineWidth = 1
        for (let px = 0; px < width; px += 5) { c.beginPath(); c.moveTo(px, y(base)); c.lineTo(px + 2, y(base)); c.stroke() }
      }
      c.strokeStyle = up ? "#30d158" : "#ff453a"; c.lineWidth = 1.6; c.lineJoin = "round"
      c.beginPath(); values.forEach((v, i) => i ? c.lineTo(x(i), y(v)) : c.moveTo(x(i), y(v))); c.stroke()
    }
  }

  // A picture with the card's rounded corners.
  component RoundImage: Item {
    id: ri
    property string src: ""
    property real radius: 24
    Image {
      id: rimg
      anchors.fill: parent; visible: false
      source: ri.src
      sourceSize: Qt.size(720, 720)
      fillMode: Image.PreserveAspectCrop; asynchronous: true
    }
    MultiEffect {
      anchors.fill: parent
      visible: rimg.status === Image.Ready
      source: rimg
      maskEnabled: true; maskSource: rmask
      autoPaddingEnabled: false
    }
    Item {
      id: rmask
      anchors.fill: parent; layer.enabled: true; visible: false
      Rectangle { anchors.fill: parent; radius: ri.radius; color: "black" }
    }
  }

  Component {
    id: clockC
    Item {
      Face { anchors.centerIn: parent; width: Math.min(parent.width, parent.height); height: width }
    }
  }

  // World Clock: four cities side by side (medium) or a list of eight (large).
  Component {
    id: worldC
    Item {
      id: wc
      readonly property bool tall: parent ? parent.tall : false
      readonly property var list: root.cityList(tall ? 6 : 4)
      Row {
        visible: !wc.tall
        anchors.centerIn: parent
        spacing: 8
        Repeater {
          model: wc.tall ? [] : wc.list
          delegate: Column {
            required property var modelData
            readonly property date t: root.cityTime(modelData)
            width: (wc.width - 24) / 4; spacing: 6
            Face { anchors.horizontalCenter: parent.horizontalCenter; width: Math.min(parent.width, 70); height: width; t: parent.t; night: t.getHours() < 6 || t.getHours() >= 18 }
            Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.local ? root.cityName(root.localZone || "Local") : root.cityName(modelData.zone); font.pixelSize: Theme.small; font.weight: Font.Bold }
            Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: root.cityDiff(modelData).replace("Today, ", "").replace("Today", "Here").replace("Tomorrow, ", "").replace("Yesterday, ", ""); font.pixelSize: Theme.small - 1; color: root.dim }
          }
        }
      }
      Column {
        visible: wc.tall
        anchors.fill: parent
        Repeater {
          model: wc.tall ? wc.list : []
          delegate: Item {
            required property var modelData
            required property int index
            readonly property date t: root.cityTime(modelData)
            width: parent.width; height: wc.height / 6
            Face { id: wf; anchors.verticalCenter: parent.verticalCenter; width: 38; height: 38; t: parent.t; night: t.getHours() < 6 || t.getHours() >= 18 }
            Column {
              anchors { left: wf.right; leftMargin: 12; right: wt.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
              Txt { width: parent.width; text: modelData.local ? root.cityName(root.localZone || "Local") : root.cityName(modelData.zone); font.weight: Font.Bold }
              Txt { width: parent.width; text: root.cityDiff(modelData); color: root.dim; font.pixelSize: Theme.small }
            }
            Txt { id: wt; anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: Qt.formatTime(parent.t, "HH:mm"); font.pixelSize: 26; font.weight: Font.Light }
            Rectangle { visible: index > 0; width: parent.width; height: 1; color: Theme.separator }
          }
        }
      }
    }
  }

  // Up Next: the next events from Calendar.
  Component {
    id: upnextC
    Item {
      id: un
      readonly property bool medium: parent ? parent.medium : false
      Column {
        id: unh
        width: un.medium ? un.width * 0.36 : un.width
        Txt { text: Qt.formatDate(root.now, "dddd").toUpperCase(); color: "#ff453a"; font.pixelSize: Theme.small; font.weight: Font.Bold }
        Txt { text: Qt.formatDate(root.now, "d"); font.pixelSize: un.medium ? 48 : 30; font.weight: Font.Light; topPadding: -2 }
      }
      Column {
        anchors { left: un.medium ? unh.right : un.left; right: un.right; top: un.medium ? un.top : unh.bottom; topMargin: un.medium ? 0 : 6 }
        spacing: 6
        Repeater {
          model: root.upcoming.slice(0, un.medium ? 3 : 2)
          delegate: Row {
            required property var modelData
            width: parent.width; spacing: 7
            Rectangle { width: 3; height: 32; radius: 1.5; color: root.calColors[modelData.ev.cal] || Theme.accent }
            Column {
              width: parent.width - 10
              Txt { width: parent.width; text: modelData.ev.title || "Event"; font.weight: Font.Bold; font.pixelSize: Theme.small + 0.5 }
              Txt { width: parent.width; text: root.whenText(modelData); color: root.dim; font.pixelSize: Theme.small - 1 }
            }
          }
        }
        Txt { visible: root.upcoming.length === 0; width: parent.width; wrapMode: Text.Wrap; text: "No events this week"; color: root.dim; font.pixelSize: Theme.small }
      }
    }
  }

  // Reminders: the open checklist items (☐) from Notes.
  Component {
    id: remindersC
    Item {
      id: rw
      readonly property bool medium: parent ? parent.medium : false
      readonly property bool tall: parent ? parent.tall : false
      Item {
        id: rh
        width: rw.medium && !rw.tall ? rw.width * 0.34 : rw.width
        height: rw.medium && !rw.tall ? rw.height : 56
        Rectangle { id: rdot; width: 28; height: 28; radius: 14; color: "#ff9f0a"; Sym { anchors.centerIn: parent; name: "check"; width: 14; height: 14; color: "#ffffff" } }
        Txt { anchors { right: rw.medium && !rw.tall ? undefined : parent.right; left: rw.medium && !rw.tall ? parent.left : undefined; top: rw.medium && !rw.tall ? rdot.bottom : parent.top; topMargin: rw.medium && !rw.tall ? 4 : -6 }
              text: root.todos.length; font.pixelSize: 32; font.weight: Font.Bold }
        Txt { anchors { left: parent.left; bottom: parent.bottom } text: "Reminders"; color: "#ff9f0a"; font.weight: Font.Bold }
      }
      Column {
        anchors { left: rw.medium && !rw.tall ? rh.right : rw.left; leftMargin: rw.medium && !rw.tall ? 12 : 0; right: rw.right
                  top: rw.medium && !rw.tall ? rw.top : rh.bottom; topMargin: rw.medium && !rw.tall ? 2 : 8 }
        spacing: 7
        Repeater {
          model: root.todos.slice(0, rw.tall ? 10 : rw.medium ? 5 : 2)
          delegate: Row {
            required property var modelData
            width: parent.width; spacing: 7
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 13; height: 13; radius: 6.5; color: "transparent"; border.width: 1.5; border.color: root.dim }
            Txt { width: parent.width - 20; text: modelData.text; font.pixelSize: Theme.small + 0.5 }
          }
        }
        Txt { visible: root.todos.length === 0; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 3; text: "Checklist items from Notes show here"; color: root.dim; font.pixelSize: Theme.small }
      }
    }
  }

  // Batteries: this computer and what is connected to it.
  Component {
    id: batteriesC
    Item {
      id: bw
      readonly property bool medium: parent ? parent.medium : false
      readonly property bool tall: parent ? parent.tall : false
      readonly property var list: root.batteries
      Column {
        visible: bw.list.length === 0
        anchors.centerIn: parent; spacing: 6
        Sym { anchors.horizontalCenter: parent.horizontalCenter; name: "battery"; width: 28; height: 28; color: root.dim }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "No batteries"; color: root.dim; font.pixelSize: Theme.small }
      }
      // Rings: one big, a square of four (small) or a row of four (medium).
      Grid {
        visible: !bw.tall && bw.list.length > 0
        anchors.centerIn: parent
        readonly property bool one: !bw.medium && bw.list.length === 1
        columns: bw.medium ? 4 : 2
        columnSpacing: bw.medium ? 14 : 10; rowSpacing: 8
        Repeater {
          model: bw.tall ? [] : bw.list.slice(0, 4)
          delegate: Column {
            required property var modelData
            readonly property real size: parent.one ? 96 : bw.medium ? 62 : 54
            spacing: 4
            Ring {
              width: parent.size; height: width; thick: parent.size > 80 ? 9 : 6
              v: modelData.percentage
              col: modelData.percentage <= 0.2 && !root.charging(modelData) ? "#ff453a" : "#30d158"
              Sym { anchors.centerIn: parent; name: root.batterySym(modelData); width: parent.width * 0.36; height: width; color: root.ink }
              Txt { visible: root.charging(modelData); anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.thick + 2 } text: "⚡"; font.pixelSize: 9; color: "#30d158" }
            }
            Txt { visible: bw.medium || parent.parent.one; anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.percentage * 100) + "%"; font.pixelSize: Theme.small; font.weight: Font.Bold }
          }
        }
      }
      // A list: name, charge and a bar.
      Column {
        visible: bw.tall
        anchors.fill: parent
        spacing: 12
        Repeater {
          model: bw.tall ? bw.list.slice(0, 6) : []
          delegate: Item {
            required property var modelData
            width: parent.width; height: 40
            Sym { id: bs; name: root.batterySym(modelData); width: 22; height: 22; color: root.ink; anchors.verticalCenter: parent.verticalCenter }
            Txt { anchors { left: bs.right; leftMargin: 10; right: bp.left; rightMargin: 8; top: parent.top } text: root.batteryName(modelData); font.weight: Font.Bold }
            Txt { id: bp; anchors { right: parent.right; top: parent.top } text: (root.charging(modelData) ? "⚡ " : "") + Math.round(modelData.percentage * 100) + "%"; font.weight: Font.Bold }
            Rectangle {
              anchors { left: bs.right; leftMargin: 10; right: parent.right; bottom: parent.bottom; bottomMargin: 4 }
              height: 6; radius: 3; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.09)
              Rectangle { width: parent.width * Math.max(0.02, modelData.percentage); height: parent.height; radius: 3; color: modelData.percentage <= 0.2 && !root.charging(modelData) ? "#ff453a" : "#30d158" }
            }
          }
        }
      }
    }
  }

  // Photos: a picture from Pictures, full card.
  Component {
    id: photosC
    Item {
      id: pw
      readonly property int slot: parent ? parent.slot : 0
      readonly property string src: root.photos.length ? root.photos[pw.slot % root.photos.length] : ""
      RoundImage { anchors.fill: parent; src: pw.src ? "file://" + pw.src : "" }
      Column {
        visible: !pw.src
        anchors.centerIn: parent; width: parent.width - 32; spacing: 6
        Sym { anchors.horizontalCenter: parent.horizontalCenter; name: "photo"; width: 28; height: 28; color: root.dim }
        Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: "Photos in Pictures show here"; color: root.dim; font.pixelSize: Theme.small }
      }
    }
  }

  // Stocks: one symbol (small) or a watchlist.
  Component {
    id: stocksC
    Item {
      id: sw
      readonly property bool medium: parent ? parent.medium : false
      readonly property bool tall: parent ? parent.tall : false
      readonly property var q0: root.quotes.length ? root.quotes[0] : null
      Txt { visible: !root.quotes.length; anchors.centerIn: parent; text: root.quotesFailed ? "Stocks unavailable" : "Stocks…"; color: root.dim }
      // Small: the first symbol, big.
      ColumnLayout {
        visible: !sw.medium && !!sw.q0
        anchors.fill: parent; spacing: 0
        Txt { Layout.fillWidth: true; text: sw.q0 ? root.stockName(sw.q0) : ""; font.weight: Font.Bold }
        Txt { Layout.fillWidth: true; text: sw.q0 ? (root.stockChange(sw.q0) >= 0 ? "▲ " : "▼ ") + Math.abs(root.stockChange(sw.q0)).toFixed(2) + "%" : ""; font.pixelSize: Theme.small; color: sw.q0 && root.stockChange(sw.q0) >= 0 ? "#30d158" : "#ff453a" }
        Spark { Layout.fillWidth: true; Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 4; values: sw.q0 ? sw.q0.closes : []; base: sw.q0 ? sw.q0.prev : 0 }
        Txt { Layout.fillWidth: true; text: sw.q0 ? root.money(sw.q0.price) : ""; font.pixelSize: 24; font.weight: Font.Medium; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 14 }
      }
      // Medium and large: rows.
      Column {
        visible: sw.medium && root.quotes.length > 0
        anchors.fill: parent
        Repeater {
          model: sw.medium ? root.quotes.slice(0, sw.tall ? 6 : 3) : []
          delegate: Item {
            required property var modelData
            required property int index
            readonly property real ch: root.stockChange(modelData)
            width: parent.width; height: sw.height / (sw.tall ? 6 : 3)
            Rectangle { visible: index > 0; width: parent.width; height: 1; color: Theme.separator }
            Column {
              anchors { left: parent.left; verticalCenter: parent.verticalCenter }
              width: parent.width * 0.34
              Txt { width: parent.width; text: root.stockName(modelData); font.weight: Font.Bold }
              Txt { width: parent.width; text: modelData.sym.startsWith("^") ? "Index" : modelData.name; color: root.dim; font.pixelSize: Theme.small - 1 }
            }
            Spark { anchors { left: parent.left; leftMargin: parent.width * 0.37; verticalCenter: parent.verticalCenter } width: parent.width * 0.27; height: parent.height * 0.6; values: modelData.closes; base: modelData.prev }
            Column {
              anchors { right: parent.right; verticalCenter: parent.verticalCenter }
              Txt { anchors.right: parent.right; text: root.money(modelData.price); font.weight: Font.Medium }
              Rectangle {
                anchors.right: parent.right
                width: chg.implicitWidth + 10; height: 17; radius: 5
                color: ch >= 0 ? "#30d158" : "#ff453a"
                Txt { id: chg; anchors.centerIn: parent; text: (ch >= 0 ? "+" : "") + ch.toFixed(2) + "%"; color: "#ffffff"; font.pixelSize: Theme.small - 1; font.weight: Font.Bold }
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: weatherC
    Item {
      id: wxw
      readonly property bool medium: parent ? parent.medium : false
      readonly property bool tall: parent ? parent.tall : false
      readonly property var wd: root.weather
      Txt { visible: !parent.wd; anchors.centerIn: parent; text: "Weather…"; color: root.dim }
      // Large: now, the next hours and the next five days.
      Item {
        visible: wxw.tall && !!wxw.wd
        anchors.fill: parent
        Column {
          id: wxl
          Txt { text: wxw.wd ? wxw.wd.place : ""; font.weight: Font.Bold; width: wxw.width * 0.55 }
          Txt { text: wxw.wd ? Math.round(wxw.wd.temp) + "°" : ""; font.pixelSize: 40; font.weight: Font.Light }
        }
        Column {
          anchors { right: parent.right; top: parent.top }
          spacing: 2
          Sym { anchors.right: parent.right; name: wxw.wd ? root.wxSym(wxw.wd.code) : "sun"; width: 20; height: 20; color: root.ink }
          Txt { anchors.right: parent.right; text: wxw.wd ? root.wxName(wxw.wd.code) : ""; font.pixelSize: Theme.small }
          Txt { anchors.right: parent.right; text: wxw.wd ? "H:" + Math.round(wxw.wd.hi) + "°  L:" + Math.round(wxw.wd.lo) + "°" : ""; font.pixelSize: Theme.small; color: root.dim }
        }
        Row {
          id: wxh
          anchors { top: wxl.bottom; topMargin: 8; left: parent.left; right: parent.right }
          Repeater {
            model: wxw.tall && wxw.wd && wxw.wd.hours ? wxw.wd.hours : []
            delegate: Column {
              required property var modelData
              required property int index
              width: wxh.width / 6; spacing: 4
              Txt { anchors.horizontalCenter: parent.horizontalCenter; text: index === 0 ? "Now" : modelData.t.slice(11, 13); color: root.dim; font.pixelSize: Theme.small }
              Sym { anchors.horizontalCenter: parent.horizontalCenter; name: root.wxSym(modelData.code); width: 18; height: 18; color: root.ink }
              Txt { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.temp) + "°"; font.pixelSize: Theme.small; font.weight: Font.Bold }
            }
          }
        }
        Rectangle { id: wxs; anchors { top: wxh.bottom; topMargin: 8; left: parent.left; right: parent.right } height: 1; color: Theme.separator }
        Column {
          anchors { top: wxs.bottom; topMargin: 4; left: parent.left; right: parent.right; bottom: parent.bottom }
          Repeater {
            id: wxd
            model: wxw.tall && wxw.wd ? wxw.wd.days.slice(1, 6) : []
            // The week's lowest and highest, so the bars line up.
            readonly property real lo: wxw.wd ? Math.min.apply(null, wxw.wd.days.map(d => d.lo)) : 0
            readonly property real hi: wxw.wd ? Math.max.apply(null, wxw.wd.days.map(d => d.hi)) : 1
            delegate: Item {
              required property var modelData
              width: parent.width; height: parent.height / 5
              Txt { id: wdn; anchors.verticalCenter: parent.verticalCenter; width: 46; text: Qt.formatDate(new Date(modelData.day + "T12:00"), "ddd"); font.weight: Font.Bold }
              Sym { id: wds; anchors { left: wdn.right; verticalCenter: parent.verticalCenter } name: root.wxSym(modelData.code); width: 18; height: 18; color: root.ink }
              Txt { id: wdl; anchors { left: wds.right; leftMargin: 10; verticalCenter: parent.verticalCenter } width: 32; horizontalAlignment: Text.AlignRight; text: Math.round(modelData.lo) + "°"; color: root.dim; font.pixelSize: Theme.small }
              Rectangle {
                id: wdb
                anchors { left: wdl.right; leftMargin: 8; right: wdh.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                height: 5; radius: 2.5; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.09)
                readonly property real span: Math.max(1, wxd.hi - wxd.lo)
                Rectangle {
                  x: parent.width * (modelData.lo - wxd.lo) / parent.span
                  width: Math.max(5, parent.width * (modelData.hi - modelData.lo) / parent.span); height: parent.height; radius: 2.5
                  gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "#64d2ff" } GradientStop { position: 1; color: "#ff9f0a" } }
                }
              }
              Txt { id: wdh; anchors { right: parent.right; verticalCenter: parent.verticalCenter } width: 30; horizontalAlignment: Text.AlignRight; text: Math.round(modelData.hi) + "°"; font.pixelSize: Theme.small; font.weight: Font.Bold }
            }
          }
        }
      }
      ColumnLayout {
        visible: !!parent.wd && !wxw.tall
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
        visible: medium && !wxw.tall && !!parent.wd
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
      id: cw2
      readonly property bool medium: parent ? parent.medium : false
      readonly property bool tall: parent ? parent.tall : false
      readonly property date d: root.now
      // Large: the month, then what comes next.
      Item {
        visible: cw2.tall
        anchors.fill: parent
        Txt { id: clm; text: Qt.formatDate(cw2.d, "MMMM").toUpperCase(); color: "#ff453a"; font.pixelSize: Theme.small; font.weight: Font.Bold }
        Grid {
          id: clg
          anchors { top: clm.bottom; topMargin: 4; horizontalCenter: parent.horizontalCenter }
          columns: 7; columnSpacing: 0; rowSpacing: 0
          readonly property real cell: cw2.width / 7
          readonly property date first: new Date(cw2.d.getFullYear(), cw2.d.getMonth(), 1)
          readonly property int lead: (first.getDay() + 6) % 7
          readonly property int days: new Date(cw2.d.getFullYear(), cw2.d.getMonth() + 1, 0).getDate()
          Repeater { model: cw2.tall ? ["M", "T", "W", "T", "F", "S", "S"] : []; delegate: Txt { required property string modelData; width: clg.cell; height: 18; horizontalAlignment: Text.AlignHCenter; text: modelData; color: root.dim; font.pixelSize: Theme.small - 1; font.weight: Font.Bold } }
          Repeater {
            model: cw2.tall ? clg.lead + clg.days : 0
            delegate: Item {
              required property int index
              readonly property int day: index - clg.lead + 1
              width: clg.cell; height: 22
              Rectangle { anchors.centerIn: parent; width: 22; height: 20; radius: 10; color: "#ff453a"; visible: parent.day === root.now.getDate() }
              Txt { anchors.centerIn: parent; visible: parent.day > 0; text: parent.day; font.pixelSize: Theme.small; color: parent.day === root.now.getDate() ? "#ffffff" : root.ink }
            }
          }
        }
        Rectangle { id: cls; anchors { top: clg.bottom; topMargin: 6; left: parent.left; right: parent.right } height: 1; color: Theme.separator }
        Column {
          anchors { top: cls.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: parent.bottom }
          spacing: 6
          clip: true
          Repeater {
            model: cw2.tall ? root.upcoming.slice(0, 3) : []
            delegate: Row {
              required property var modelData
              width: parent.width; spacing: 7
              Rectangle { width: 3; height: 30; radius: 1.5; color: root.calColors[modelData.ev.cal] || Theme.accent }
              Column {
                width: parent.width - 10
                Txt { width: parent.width; text: modelData.ev.title || "Event"; font.weight: Font.Bold; font.pixelSize: Theme.small + 0.5 }
                Txt { width: parent.width; text: root.whenText(modelData); color: root.dim; font.pixelSize: Theme.small - 1 }
              }
            }
          }
          Txt { visible: root.upcoming.length === 0; text: "No events this week"; color: root.dim; font.pixelSize: Theme.small }
        }
      }
      // Small: the day; medium: day and the month.
      Column {
        visible: !cw2.tall
        anchors { left: parent.left; top: parent.top }
        width: medium ? parent.width * 0.38 : parent.width
        Txt { text: Qt.formatDate(d, "dddd").toUpperCase(); color: "#ff453a"; font.pixelSize: Theme.small; font.weight: Font.Bold }
        Txt { text: Qt.formatDate(d, "d"); font.pixelSize: 54; font.weight: Font.Light; topPadding: -4 }
        Txt { text: Qt.formatDate(d, "MMMM yyyy"); color: root.dim; font.pixelSize: Theme.small }
      }
      Grid {
        visible: medium && !cw2.tall
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
      // Small: the cover, the song and play/pause.
      Item {
        visible: !medium
        anchors.fill: parent
        Rectangle {
          id: sart
          width: 64; height: 64; radius: 12
          color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
          RoundImage { anchors.fill: parent; radius: 12; src: p ? (p.trackArtUrl || "") : "" }
          Sym { anchors.centerIn: parent; name: "music"; width: 26; height: 26; color: root.dim; visible: !p || !p.trackArtUrl }
        }
        Item {
          anchors { right: parent.right; top: parent.top }
          width: 30; height: 30
          visible: !!p
          Sym { anchors.centerIn: parent; name: root.player && root.player.isPlaying ? "pause" : "play"; width: 20; height: 20; color: root.ink }
          TapHandler { onTapped: if (root.player) root.player.togglePlaying() }
        }
        Column {
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          Txt { width: parent.width; text: p ? (p.trackTitle || "Not Playing") : "Not Playing"; font.weight: Font.Bold }
          Txt { width: parent.width; text: p ? (p.trackArtist || Sys.playerName(p)) : "Music"; color: root.dim; font.pixelSize: Theme.small }
        }
      }
      Rectangle {
        id: art
        visible: medium
        width: parent.height; height: parent.height; radius: 14
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
        clip: true
        Image { anchors.fill: parent; source: p ? (p.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop; visible: status === Image.Ready; asynchronous: true }
        Sym { anchors.centerIn: parent; name: "play"; width: 30; height: 30; color: root.dim; visible: !p || !p.trackArtUrl }
      }
      Column {
        visible: medium
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
      readonly property bool tall: parent ? parent.tall : false
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
          model: root.notes.slice(0, parent.parent.tall ? 7 : medium ? 3 : 2)
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
    width: Math.min(root.width - 48, grow.implicitWidth + done.width + 73); height: 150
    radius: 26
    fill: Theme.glassStrong
    backdrop: root.backdrop
    backdropRect: Qt.rect(gallery.x, gallery.y, gallery.width, gallery.height)
    // The kinds scroll sideways when they don't all fit.
    Flickable {
      id: gf
      anchors { left: parent.left; leftMargin: 20; right: gsep.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
      height: grow.implicitHeight
      contentWidth: grow.implicitWidth
      flickableDirection: Flickable.HorizontalFlick
      boundsBehavior: Flickable.StopAtBounds
      clip: true
      WheelHandler {
        onWheel: event => {
          const d = event.angleDelta.y || event.angleDelta.x
          gf.contentX = Math.max(0, Math.min(gf.contentWidth - gf.width, gf.contentX - d))
        }
      }
      Row {
        id: grow
        spacing: 12
        Repeater {
          model: root.kinds
          delegate: Column {
            id: kind
            required property var modelData
            spacing: 5
            Rectangle {
              width: 92; height: 64; radius: 14
              color: gh.hovered ? Theme.pressed : Theme.hover
              border.color: Theme.separator
              Sym {
                visible: kind.modelData.type !== "stocks"
                anchors.centerIn: parent; width: 24; height: 24; color: Theme.text
                name: ({ clock: "clock", worldclock: "globe", weather: "suncloud", calendar: "display", upnext: "bell", reminders: "check",
                         batteries: "battery", photos: "photo", system: "gear", music: "music", notes: "file" })[kind.modelData.type] || "star"
              }
              // Stocks: a little rising line.
              Canvas {
                visible: kind.modelData.type === "stocks"
                anchors.centerIn: parent; width: 26; height: 18
                onPaint: {
                  const c = getContext("2d"); c.reset(); c.strokeStyle = Theme.text; c.lineWidth = 1.8; c.lineJoin = "round"; c.lineCap = "round"
                  c.beginPath(); c.moveTo(1, 16); c.lineTo(8, 9); c.lineTo(13, 12); c.lineTo(25, 2); c.stroke()
                }
              }
              Txt { anchors { right: parent.right; bottom: parent.bottom; margins: 6 } text: "+"; font.weight: Font.Bold; color: Theme.accent }
              HoverHandler { id: gh; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.add(kind.modelData.type, kind.modelData.sizes[0]) }
            }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: kind.modelData.name; font.pixelSize: Theme.small }
            // The sizes it comes in: click one to add that size.
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 4
              Repeater {
                model: kind.modelData.sizes
                delegate: Rectangle {
                  required property string modelData
                  width: 24; height: 18; radius: 9
                  color: sh.hovered ? Theme.accent : Theme.hover
                  Txt { anchors.centerIn: parent; text: root.sizeNames[modelData]; font.pixelSize: 10; font.weight: Font.Bold; color: sh.hovered ? "#ffffff" : Theme.text }
                  HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: root.add(kind.modelData.type, modelData) }
                }
              }
            }
          }
        }
      }
    }
    Rectangle { id: gsep; anchors { right: done.left; rightMargin: 16; verticalCenter: parent.verticalCenter } width: 1; height: 80; color: Theme.separator }
    Rectangle {
      id: done
      anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
      width: dn.implicitWidth + 30; height: 34; radius: 17
      color: Theme.accent
      Txt { id: dn; anchors.centerIn: parent; text: "Done"; color: "#ffffff"; font.weight: Font.Bold }
      TapHandler { onTapped: root.editing = false }
    }
  }
  Txt {
    visible: root.editing
    anchors { horizontalCenter: gallery.horizontalCenter; bottom: gallery.top; bottomMargin: 10 }
    text: "Drag widgets to move them. Click a widget to add it, or S, M, L for its size."
    color: "#ffffff"; style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.4)
    font.pixelSize: Theme.small
  }
}
