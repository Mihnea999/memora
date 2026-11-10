//@ pragma UseQApplication
//@ pragma AppId memora-calendar
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui
import "core/cal.js" as Cal

// Calendar: your events by day, week, month or year, in calendars of their own
// colour, with the public holidays of your country. Type an event the way you'd
// say it ("Lunch with Ana tomorrow at 13"), drag it to another day or time, and
// the desktop reminds you before it starts (reminders/Reminders.qml). Everything lives
// in ~/.local/share/memora/calendar.json (a copy is kept next to it), which
// Memora AI can read and add to.
ShellRoot {
  id: app
  readonly property string store: Quickshell.env("HOME") + "/.local/share/memora/calendar.json"
  readonly property color tint: "#ff3b30"          // Calendar's own red: today, the current time
  readonly property var palette: ["#3d8bff", "#ff9f0a", "#30d158", "#bf5af2", "#ff375f", "#64d2ff", "#ffd60a", "#ac8e68"]

  property var calendars: [{ id: "personal", name: "Personal", color: "#3d8bff", on: true },
                           { id: "work", name: "Work", color: "#ff9f0a", on: true },
                           { id: "family", name: "Family", color: "#30d158", on: true }]
  property var events: []
  property string country: ""           // two letters; "" = from the time zone
  property bool showHolidays: true
  property bool loaded: false

  // What is shown.
  property string view: "month"          // day | week | month | year
  property real cursor: Cal.startOfDay(Date.now())  // the day in focus
  property real selDay: cursor
  property string selId: ""              // the event open in the card
  property rect selRect                  // where it was clicked (the card opens beside it)
  property real selOcc: 0                // which occurrence, for a repeating one
  property real now: Date.now()
  Timer { interval: 30000; running: true; repeat: true; onTriggered: app.now = Date.now() }
  property int dir: 0                    // which way the last move went, for the slide

  // ---- storage
  FileView {
    id: file
    path: app.store
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      if (app.loaded && text() === app.lastSaved) return
      try {
        // A damaged file (the power went mid-save): the copy from the save before.
        let j
        try { j = JSON.parse(text()); app.lastSaved = text() } catch (e) { j = JSON.parse(backup.text()) }
        if (j.calendars && j.calendars.length) app.calendars = j.calendars
        app.events = j.events || []
        if (j.country !== undefined) app.country = j.country
        if (j.showHolidays !== undefined) app.showHolidays = j.showHolidays
      } catch (e) {}
      app.loaded = true
    }
    onLoadFailed: app.loaded = true
  }
  // The backup holds the save before the last one, so one bad write never takes both.
  FileView { id: backup; path: app.store + ".bak"; printErrors: false; blockLoading: true }
  property string lastSaved: ""
  Timer { id: saveLater; interval: 500; onTriggered: app.saveNow() }
  function saveNow() {
    if (!loaded) return
    const t = JSON.stringify({ version: 1, calendars: calendars, events: events, country: country, showHolidays: showHolidays }, null, 1)
    if (t === lastSaved) return
    Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/share/memora"])
    if (lastSaved) backup.setText(lastSaved)
    lastSaved = t
    file.setText(t)
  }
  function changed() { events = events.slice(); saveLater.restart() }
  Component.onDestruction: saveNow()

  // ---- holidays: from date.nager.at (cached a month), or built in when offline
  property string autoCountry: ""
  readonly property string cc: (country || autoCountry || "US").toUpperCase()
  property var holidayYears: ({})        // "RO-2026" -> [{ date, name }]
  property var asked: ({})
  Process {
    running: true
    // The country of the time zone (zone1970.tab lists the countries of each zone).
    command: ["bash", "-c", "tz=$(timedatectl show -p Timezone --value 2>/dev/null || readlink /etc/localtime | sed 's|.*/zoneinfo/||'); awk -v tz=\"$tz\" '$3 == tz { split($1, c, \",\"); print c[1]; exit }' /usr/share/zoneinfo/zone1970.tab 2>/dev/null | grep . || { l=\"${LC_TIME:-${LANG:-}}\"; l=${l%%.*}; [ \"${l#*_}\" != \"$l\" ] && echo \"${l#*_}\"; }"]
    // The time zone's country, or else the language's (ro_RO → RO); US when neither says.
    stdout: StdioCollector { onStreamFinished: { app.autoCountry = (text.trim().split("\n")[0] || "US").slice(0, 2).toUpperCase(); app.loadYears() } }
  }
  function wantYear(y) {
    const key = cc + "-" + y
    if (asked[key] || !autoCountry && !country) return
    asked[key] = true
    const p = holidayProc.createObject(app, { key: key, year: y, code: cc })
    p.running = true
  }
  Component {
    id: holidayProc
    Process {
      property string key
      property int year
      property string code
      command: ["bash", "-c", "d=\"${XDG_CACHE_HOME:-$HOME/.cache}/memora/holidays\"; f=\"$d/$1-$2.json\"; mkdir -p \"$d\"; " +
        "if [ ! -s \"$f\" ] || [ -n \"$(find \"$f\" -mtime +30 2>/dev/null)\" ]; then curl -sf --max-time 10 \"https://date.nager.at/api/v3/PublicHolidays/$2/$1\" -o \"$f.new\" && [ -s \"$f.new\" ] && mv \"$f.new\" \"$f\"; rm -f \"$f.new\"; fi; cat \"$f\" 2>/dev/null",
        "_", code, String(year)]
      stdout: StdioCollector {
        onStreamFinished: {
          let list = []
          try { list = Cal.parseNager(text) } catch (e) { list = [] }
          if (!list.length) list = Cal.builtinHolidays(code, year)
          const h = Object.assign({}, app.holidayYears); h[key] = list; app.holidayYears = h
        }
      }
    }
  }
  onCcChanged: { asked = ({}); holidayYears = ({}); loadYears() }
  onCursorChanged: loadYears()
  function loadYears() { const y = new Date(cursor).getFullYear(); [y - 1, y, y + 1].forEach(wantYear) }
  readonly property var holidayEvents: {
    if (!showHolidays) return []
    const out = []
    Object.keys(holidayYears).forEach(k => {
      if (k.indexOf(cc + "-") !== 0) return
      holidayYears[k].forEach((h, i) => out.push({ id: "holiday-" + k + "-" + i, title: h.name, cal: "holidays", start: h.date, end: h.date, allDay: true, holiday: true }))
    })
    return out
  }
  readonly property var holidayCal: ({ id: "holidays", name: "Holidays", color: tint, on: showHolidays })

  // ---- events
  function calOf(id) { return id === "holidays" ? holidayCal : (calendars.find(c => c.id === id) || calendars[0]) }
  function colorOf(ev) { return calOf(ev.cal).color }
  readonly property var shownEvents: events.filter(e => { const c = calendars.find(x => x.id === e.cal); return !c || c.on }).concat(holidayEvents)
  function occ(from, to) { return Cal.occurrences(shownEvents, from, to) }
  function dayOcc(day) { return Cal.onDay(shownEvents, day) }
  readonly property var sel: events.find(e => e.id === selId) || holidayEvents.find(e => e.id === selId) || null

  // Opens the card for an event, next to the thing clicked (or on the right).
  function select(id, item, occStart) {
    selRect = item ? item.mapToItem(floats, 0, 0, item.width, item.height) : Qt.rect(0, 0, 0, 0)
    selOcc = occStart || 0
    selId = id
  }
  function newEvent(o, item) {
    const c = calendars.find(x => x.on) || calendars[0]
    const ev = Object.assign({ id: "e" + Date.now() + Math.floor(Math.random() * 1000), title: "New Event", cal: c.id,
      start: selDay + 9 * 3600000, end: selDay + 10 * 3600000, allDay: false, location: "", notes: "", repeat: "none", until: 0, alert: 10, skip: [] }, o || {})
    if (ev.allDay) ev.alert = -1
    events = events.concat([ev])
    selDay = Cal.startOfDay(ev.start)
    select(ev.id, item || null, ev.start)
    changed()
    Qt.callLater(() => card.focusTitle())
    return ev
  }
  function quickAdd(text) {
    if (!text.trim()) return
    const q = Cal.quick(text, Date.now())
    if (view === "year") view = "month"
    goTo(q.start)
    newEvent({ title: q.title, start: q.start, end: q.end, allDay: q.allDay })
  }
  function update(ev, k, v) {
    if (!ev || ev.holiday) return
    ev[k] = v
    if (k === "start" && ev.end < ev.start) ev.end = ev.allDay ? ev.start : ev.start + 3600000
    if (k === "end" && ev.end < ev.start) ev.end = ev.start
    changed()
  }
  function removeEvent(ev, onlyThis, occStart) {
    if (!ev || ev.holiday) return
    if (onlyThis && ev.repeat && ev.repeat !== "none") { ev.skip = (ev.skip || []).concat([occStart]); changed() }
    else { events = events.filter(e => e !== ev); saveLater.restart() }
    selId = ""
  }
  // Dragged to another day (the time of day stays) and, in a day or week, to
  // another time, in quarters of an hour.
  function shift(ev, days, minutes) {
    if (!ev || ev.holiday || (!days && !minutes)) return
    const m = (minutes || 0) * 60000
    ev.start = Cal.addDays(ev.start, days || 0) + m; ev.end = Cal.addDays(ev.end, days || 0) + m
    changed()
  }
  // Its end dragged down or up.
  function stretch(ev, minutes) {
    if (!ev || ev.holiday || !minutes) return
    ev.end = Math.max(ev.start + 15 * 60000, ev.end + minutes * 60000)
    changed()
  }

  // A week (or a day) as rows of bars: an event that lasts several days is one
  // bar across them. Each gets the first row free on all its days.
  // -> [{ o, a, b (first and last day, 0-based), lane, contL, contR }]
  function layoutWeek(list, from, n) {
    const to = Cal.addDays(from, n)
    const idx = t => Math.round((Cal.startOfDay(t) - from) / Cal.DAY)
    const items = []
    list.forEach(o => {
      const endT = o.ev.allDay ? Cal.addDays(Cal.startOfDay(o.end), 1) : Math.max(o.end, o.start + 1)
      if (o.start >= to || endT <= from) return
      const a = Math.max(0, idx(o.start))
      const last = o.ev.allDay ? idx(o.end) : a
      items.push({ o: o, a: a, b: Math.min(n - 1, Math.max(a, last)), lane: 0, contL: Cal.startOfDay(o.start) < from, contR: last > n - 1, span: o.ev.allDay ? 1 : 0 })
    })
    items.sort((x, y) => (y.span - x.span) || (x.a - y.a) || ((y.b - y.a) - (x.b - x.a)) || (x.o.start - y.o.start))
    const used = []
    items.forEach(x => {
      let l = 0
      for (;; l++) {
        if (!used[l]) used[l] = []
        let free = true
        for (let i = x.a; i <= x.b; i++) if (used[l][i]) { free = false; break }
        if (free) break
      }
      for (let i = x.a; i <= x.b; i++) used[l][i] = true
      x.lane = l
    })
    return items
  }

  // Search: what you typed in the title, place or notes; coming ones first.
  function search(q) {
    q = q.trim().toLowerCase()
    if (!q) return []
    const hit = e => [e.title, e.location, e.notes].some(s => (s || "").toLowerCase().indexOf(q) >= 0)
    const d0 = Cal.startOfDay(now)
    const list = events.filter(hit).concat(holidayEvents.filter(hit)).map(e => {
      // A repeating one: its next time.
      let t = e.start
      if (e.repeat && e.repeat !== "none" && e.end < d0) { const nx = Cal.occurrences([e], d0, Cal.addDays(d0, 400)); if (nx.length) t = nx[0].start }
      return { ev: e, start: t }
    })
    list.sort((a, b) => { const fa = a.start >= d0, fb = b.start >= d0; return fa !== fb ? (fa ? -1 : 1) : (fa ? a.start - b.start : b.start - a.start) })
    return list.slice(0, 14)
  }

  // ---- moving around
  function goTo(t) { const d = Cal.startOfDay(t); dir = d > cursor ? 1 : (d < cursor ? -1 : 0); cursor = d; selDay = d }
  function stepView(n) {
    dir = n
    if (view === "day") { cursor = Cal.addDays(cursor, n); selDay = cursor }
    else if (view === "week") cursor = Cal.addDays(cursor, 7 * n)
    else if (view === "month") { const d = new Date(cursor); cursor = new Date(d.getFullYear(), d.getMonth() + n, 1).getTime() }
    else { const d = new Date(cursor); cursor = new Date(d.getFullYear() + n, d.getMonth(), 1).getTime() }
  }
  function time(t) { return Qt.formatTime(new Date(t), Prefs.clock24 ? "HH:mm" : "h:mm AP") }
  function span(o) {
    if (o.ev.allDay) return Cal.sameDay(o.start, o.end) ? "All day" : Qt.formatDate(new Date(o.start), "d MMM") + " – " + Qt.formatDate(new Date(o.end), "d MMM")
    return time(o.start) + " – " + time(o.end)
  }
  // The heading: "November" and, lighter, "2026".
  // What the New Event box will make of what you typed.
  function quickPreview(text) {
    const q = Cal.quick(text, Date.now())
    const when = Cal.sameDay(q.start, now) ? "Today" : (Cal.sameDay(q.start, Cal.addDays(now, 1)) ? "Tomorrow" : Qt.formatDate(new Date(q.start), "dddd d MMMM"))
    return "“" + q.title + "” · " + when + (q.allDay ? ", all day" : " at " + time(q.start))
  }
  readonly property string titleMain: {
    const d = new Date(cursor)
    if (view === "year") return String(d.getFullYear())
    if (view === "day") return Qt.formatDate(d, "d MMMM")
    if (view === "week") {
      const a = new Date(Cal.weekStart(cursor)), b = new Date(Cal.addDays(Cal.weekStart(cursor), 6))
      return a.getMonth() === b.getMonth() ? Qt.formatDate(a, "MMMM") : Qt.formatDate(a, "MMM") + " – " + Qt.formatDate(b, "MMM")
    }
    return Qt.formatDate(d, "MMMM")
  }
  readonly property string titleYear: {
    if (view === "year") return ""
    if (view === "week") return String(new Date(Cal.addDays(Cal.weekStart(cursor), 6)).getFullYear())
    return String(new Date(cursor).getFullYear())
  }
  // The next things coming, for the sidebar.
  readonly property var upNext: {
    const n = Cal.startOfDay(now)
    return occ(now, Cal.addDays(n, 15)).filter(o => !o.ev.holiday || o.start >= n).filter(o => o.ev.allDay ? Cal.startOfDay(o.start) >= n : o.end > now).slice(0, 6)
  }

  IpcHandler {
    target: "calendar"
    // "2026-11-12": that day (a local date, not UTC midnight).
    function show(day: string): void {
      const m = day.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/)
      const t = m ? new Date(+m[1], +m[2] - 1, +m[3]).getTime() : Date.parse(day)
      if (!isNaN(t)) app.goTo(t)
    }
  }

  // ================================================================ window
  FloatingWindow {
    id: win
    onVisibleChanged: if (!visible) { app.saveNow(); Qt.quit() }
    title: "Calendar"
    implicitWidth: 1240
    implicitHeight: 800
    minimumSize: Qt.size(600, 460)
    color: "transparent"
    Rectangle { anchors.fill: parent; color: Theme.window }

    readonly property bool narrow: width < 900
    property bool sideHere: false        // narrow: the sidebar slid in over the calendar
    property bool sideWide: true         // wide: the sidebar shown (the Sidebar button hides it)
    onNarrowChanged: sideHere = false
    readonly property bool docked: !narrow && sideWide
    readonly property bool sideOpen: narrow ? sideHere : sideWide
    function toggleSide() { if (narrow) sideHere = !sideHere; else sideWide = !sideWide }

    Shortcut { sequence: "Ctrl+N"; onActivated: quickBox.show() }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: app.newEvent() }
    Shortcut { sequence: "Ctrl+T"; onActivated: app.goTo(Date.now()) }
    Shortcut { sequence: "Ctrl+1"; onActivated: app.view = "day" }
    Shortcut { sequence: "Ctrl+2"; onActivated: app.view = "week" }
    Shortcut { sequence: "Ctrl+3"; onActivated: app.view = "month" }
    Shortcut { sequence: "Ctrl+4"; onActivated: app.view = "year" }
    Shortcut { sequence: "Ctrl+Right"; onActivated: app.stepView(1) }
    Shortcut { sequence: "Ctrl+Left"; onActivated: app.stepView(-1) }
    Shortcut { sequence: "Ctrl+F"; onActivated: searchIn.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+Alt+S"; onActivated: win.toggleSide() }
    Shortcut {
      sequence: "Escape"
      onActivated: {
        if (pop.open) pop.close()
        else if (quickBox.open) quickBox.hide()
        else if (searchIn.activeFocus || searchIn.text) { searchIn.text = ""; searchIn.focus = false }
        else if (app.selId) app.selId = ""
      }
    }
    Shortcut { sequence: "Delete"; enabled: !!app.sel && !app.sel.holiday && !card.typing && !searchIn.activeFocus && !quickIn.activeFocus; onActivated: card.askDelete() }
    Shortcut { sequence: "Ctrl+W"; onActivated: { app.saveNow(); Qt.quit() } }

    // ---- sidebar: the calendars, what's next, a month to jump with
    Rectangle {
      id: side
      width: 240
      x: win.sideOpen ? (win.narrow ? 8 : 0) : -width - 20
      Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
      z: win.narrow ? 20 : 1
      anchors { top: parent.top; bottom: parent.bottom; topMargin: win.narrow ? 8 : 0; bottomMargin: win.narrow ? 8 : 0 }
      radius: win.narrow ? 14 : 0
      color: win.narrow ? Theme.glassSolid : Theme.sidebar
      border.color: win.narrow ? Theme.separator : "transparent"
      Rectangle { visible: !win.narrow; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.separator }
      Item {
        anchors { left: parent.left; right: parent.right; top: parent.top } height: 52
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) }
      }
      CompactBar { x: 18; y: 15; window: win; sideOpen: true; onToggled: win.toggleSide(); onCloseRequested: { app.saveNow(); Qt.quit() } }

      Flickable {
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 52; bottom: miniBox.top }
        contentHeight: sideCol.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: sideCol
          x: 10; width: side.width - 20
          spacing: 14

          Column {
            width: parent.width
            spacing: 1
            Head { text: "Calendars" }
            Repeater {
              model: app.calendars
              delegate: CalRow {
                required property var modelData
                width: sideCol.width
                cal: modelData
                onToggled: { modelData.on = !modelData.on; app.calendars = app.calendars.slice(); saveLater.restart() }
                onRenamed: name => { modelData.name = name; app.calendars = app.calendars.slice(); saveLater.restart() }
                onRecolor: { modelData.color = app.palette[(app.palette.indexOf(modelData.color) + 1) % app.palette.length]; app.calendars = app.calendars.slice(); saveLater.restart() }
                onRemove: if (app.calendars.length > 1) confirm.ask({ title: "Delete the calendar “" + modelData.name + "”?", message: "Its events are deleted too. You can't undo this.", action: "Delete",
                  onAccept: () => { app.events = app.events.filter(e => e.cal !== modelData.id); app.calendars = app.calendars.filter(c => c !== modelData); saveLater.restart() } })
              }
            }
            CalRow {
              width: sideCol.width
              cal: app.holidayCal
              fixed: true
              detail: app.cc
              onToggled: { app.showHolidays = !app.showHolidays; saveLater.restart() }
              onPickCountry: item => pop.choose(item, ["Automatic (" + (app.autoCountry || "US") + ")"].concat(app.countries.map(c => c[1] + " (" + c[0] + ")")),
                v => { app.country = v.startsWith("Automatic") ? "" : v.slice(-3, -1); saveLater.restart() })
            }
            Rectangle {
              width: sideCol.width; height: 28; radius: 6
              color: nch.hovered ? Theme.hover : "transparent"
              Sym { x: 9; anchors.verticalCenter: parent.verticalCenter; name: "plus"; width: 12; height: 12; color: Theme.textDim }
              Txt { x: 31; anchors.verticalCenter: parent.verticalCenter; text: "New Calendar"; color: Theme.textDim }
              HoverHandler { id: nch; cursorShape: Qt.PointingHandCursor }
              TapHandler {
                onTapped: {
                  const used = app.calendars.map(c => c.color)
                  const col = app.palette.find(p => used.indexOf(p) < 0) || app.palette[app.calendars.length % app.palette.length]
                  app.calendars = app.calendars.concat([{ id: "c" + Date.now(), name: "Calendar " + (app.calendars.length + 1), color: col, on: true, fresh: true }])
                  saveLater.restart()
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: 1
            Head { text: "Up Next" }
            Txt { visible: app.upNext.length === 0; x: 9; text: "Nothing in the next two weeks."; color: Theme.textFaint; font.pixelSize: Theme.small; width: parent.width - 18; wrapMode: Text.Wrap }
            Repeater {
              model: app.upNext
              delegate: Rectangle {
                required property var modelData
                readonly property bool on: app.selId === modelData.ev.id
                width: sideCol.width; height: 44; radius: 7
                color: on ? Theme.pressed : (uh.hovered ? Theme.hover : "transparent")
                Rectangle { x: 10; y: 11; width: 8; height: 8; radius: 4; color: app.colorOf(modelData.ev) }
                Column {
                  x: 26; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 34; spacing: 1
                  Txt { width: parent.width; text: modelData.ev.title; font.weight: Font.Medium }
                  Txt {
                    width: parent.width; color: Theme.textDim; font.pixelSize: Theme.small
                    text: (Cal.sameDay(modelData.start, app.now) ? "Today" : (Cal.sameDay(modelData.start, Cal.addDays(app.now, 1)) ? "Tomorrow" : Qt.formatDate(new Date(modelData.start), "ddd d MMM")))
                      + (modelData.ev.allDay ? "" : " · " + app.time(modelData.start))
                  }
                }
                HoverHandler { id: uh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { app.goTo(modelData.start); app.select(modelData.ev.id, null, modelData.start); if (win.narrow) win.sideHere = false } }
              }
            }
          }
        }
      }
      // The month, at the bottom, to jump to any day.
      Item {
        id: miniBox
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: mini.implicitHeight + 26
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 } height: 1; color: Theme.separator }
        MiniMonth {
          id: mini
          x: 12; y: 14; width: side.width - 24
          marks: true
          property real shown: app.cursor
          month: new Date(shown).getMonth(); year: new Date(shown).getFullYear()
          selected: app.selDay
          onPicked: d => { if (app.view === "year") app.view = "day"; app.goTo(d); if (win.narrow) win.sideHere = false }
          onStepped: n => shown = new Date(year, month + n, 1).getTime()
          Connections { target: app; function onCursorChanged() { mini.shown = app.cursor } }
        }
      }
    }
    MouseArea { anchors.fill: parent; z: 19; visible: win.narrow && win.sideHere; onClicked: win.sideHere = false }

    // ---- toolbar: the window buttons (when the sidebar is away), the views, new, search
    Item {
      id: bar
      anchors { left: win.docked ? side.right : parent.left; right: parent.right; top: parent.top }
      height: 52
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) }
      CompactBar { id: cbar; visible: !win.docked; x: 18; anchors.verticalCenter: parent.verticalCenter; window: win; sideOpen: win.sideOpen; onToggled: win.toggleSide(); onCloseRequested: { app.saveNow(); Qt.quit() } }
      Seg {
        id: seg
        anchors.verticalCenter: parent.verticalCenter
        readonly property real lo: win.docked ? 18 : cbar.x + cbar.width + 18
        x: Math.max(lo, Math.min((bar.width - width) / 2, tools.x - width - 14))
        options: [["day", "Day"], ["week", "Week"], ["month", "Month"], ["year", "Year"]]
        value: app.view
        onPicked: v => { app.dir = 0; app.view = v }
      }
      Row {
        id: tools
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 8
        Tool { id: addBtn; anchors.verticalCenter: parent.verticalCenter; sym: "plus"; on: quickBox.open; tip: "New Event (Ctrl+N)"; onClicked: quickBox.toggle() }
        // Search the titles, places and notes.
        Rectangle {
          id: searchBox
          anchors.verticalCenter: parent.verticalCenter
          readonly property bool wide: bar.width > 780 || searchIn.activeFocus || searchIn.text !== ""
          width: wide ? 200 : 30; height: 28; radius: 8
          Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
          color: wide ? Theme.field : (sbh.hovered ? Theme.hover : "transparent")
          border.width: searchIn.activeFocus ? 1.5 : 0
          border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
          Sym { x: searchBox.wide ? 9 : 8; anchors.verticalCenter: parent.verticalCenter; name: "search"; width: 13; height: 13; color: Theme.textDim }
          TextInput {
            id: searchIn
            visible: searchBox.wide
            anchors { left: parent.left; leftMargin: 29; right: clr.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize; clip: true
            selectByMouse: true
            onTextEdited: results.open = text.trim() !== ""
            onActiveFocusChanged: if (activeFocus && text.trim()) results.open = true
            Keys.onReturnPressed: if (results.list.length) results.pick(results.list[0])
            Keys.onDownPressed: if (results.list.length) { results.open = true; resList.forceActiveFocus() }
            Txt { visible: !searchIn.text; anchors.verticalCenter: parent.verticalCenter; text: "Search"; color: Theme.textFaint }
          }
          Rectangle {
            id: clr
            visible: searchIn.text !== ""
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            width: visible ? 16 : 0; height: 16; radius: 8; color: Theme.textFaint
            Sym { anchors.centerIn: parent; name: "close"; width: 8; height: 8; color: Theme.window; stroke: 2 }
            TapHandler { onTapped: { searchIn.text = ""; results.open = false } }
          }
          HoverHandler { id: sbh; cursorShape: Qt.IBeamCursor }
          TapHandler { onTapped: searchIn.forceActiveFocus() }
          Tip { text: searchBox.wide ? "" : "Search (Ctrl+F)" }
        }
      }
    }

    // ---- heading: "November 2026", and back, today, forward
    Item {
      id: head
      anchors { left: bar.left; right: parent.right; top: bar.bottom }
      height: 46
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      Row {
        x: 22; anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Txt { text: app.titleMain; font.pixelSize: 26; font.weight: Font.Bold; font.letterSpacing: -0.4 }
        Txt { visible: text !== ""; text: app.titleYear; font.pixelSize: 26; font.weight: Font.Normal; font.letterSpacing: -0.4; color: Theme.textDim }
      }
      Rectangle {
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        width: nav.width; height: 28; radius: 8
        color: Theme.field
        Row {
          id: nav
          Tool { sym: "chevron"; flip: true; height: 28; width: 30; tip: "Previous (Ctrl+←)"; onClicked: app.stepView(-1) }
          Rectangle { width: 1; height: 14; anchors.verticalCenter: parent.verticalCenter; color: Theme.separator }
          Tool { label: "Today"; height: 28; tip: "Go to today (Ctrl+T)"; onClicked: { app.dir = 0; app.goTo(Date.now()) } }
          Rectangle { width: 1; height: 14; anchors.verticalCenter: parent.verticalCenter; color: Theme.separator }
          Tool { sym: "chevron"; height: 28; width: 30; tip: "Next (Ctrl+→)"; onClicked: app.stepView(1) }
        }
      }
    }

    // ---- the calendar itself
    Item {
      id: body
      anchors { left: bar.left; right: parent.right; top: head.bottom; bottom: parent.bottom }
      clip: true
      SwipeNav { onBack: app.stepView(-1); onForward: app.stepView(1) }

      // A short slide when moving to the next or previous day, week, month or year.
      Item {
        id: slide
        width: body.width; height: body.height
        transform: [Translate { id: slideT }, Scale { id: slideS; origin.x: slide.width / 2; origin.y: slide.height / 3 }]
        Connections {
          target: app
          function onCursorChanged() { if (app.dir !== 0) slideAnim.restart() }
          function onViewChanged() { viewAnim.restart() }
        }
        ParallelAnimation {
          id: slideAnim
          NumberAnimation { target: slideT; property: "x"; from: app.dir * 40; to: 0; duration: Theme.slow; easing.type: Easing.OutQuint }
          NumberAnimation { target: slide; property: "opacity"; from: 0.2; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
          id: viewAnim
          NumberAnimation { target: slide; property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
          NumberAnimation { target: slideS; properties: "xScale,yScale"; from: 0.985; to: 1; duration: Theme.slow; easing.type: Easing.OutQuint }
        }

        Loader { anchors.fill: parent; active: app.view === "month"; sourceComponent: Component { MonthView {} } }
        Loader { anchors.fill: parent; active: app.view === "week"; sourceComponent: Component { WeekView { days: 7 } } }
        Loader { anchors.fill: parent; active: app.view === "day"; sourceComponent: Component { WeekView { days: 1 } } }
        Loader { anchors.fill: parent; active: app.view === "year"; sourceComponent: Component { YearView {} } }
      }
    }

    // ---- what floats over the calendar: the event's card, New Event, search results
    Item {
      id: floats
      anchors.fill: parent
      z: 800
      // A click anywhere else closes them (and still does what it was for).
      MouseArea {
        anchors.fill: parent
        enabled: card.shown || quickBox.open || results.open
        onPressed: m => {
          if (quickBox.open && !quickBox.contains(mapToItem(quickBox, m.x, m.y))) quickBox.hide()
          if (results.open && !searchBox.contains(mapToItem(searchBox, m.x, m.y))) results.open = false
          if (card.shown) app.selId = ""
          m.accepted = false
        }
      }

      EventCard { id: card }

      // New Event: type it the way you'd say it.
      Rectangle {
        id: quickBox
        property bool open: false
        property real closedAt: 0
        function show() { app.selId = ""; place(); open = true; quickIn.text = ""; quickIn.forceActiveFocus(); popIn.restart() }
        function hide() { open = false; closedAt = Date.now(); quickIn.focus = false }
        function toggle() { if (open) hide(); else if (Date.now() - closedAt > 250) show() }
        function place() { const p = addBtn.mapToItem(floats, addBtn.width, addBtn.height); x = Math.max(10, Math.min(floats.width - width - 10, p.x - width + 8)); y = p.y + 8 }
        visible: open
        width: 340; height: qcol.implicitHeight + 28
        radius: 14
        color: Theme.popover
        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
        transformOrigin: Item.TopRight
        ParallelAnimation {
          id: popIn
          NumberAnimation { target: quickBox; property: "opacity"; from: 0; to: 1; duration: Theme.fast; easing.type: Easing.OutCubic }
          NumberAnimation { target: quickBox; property: "scale"; from: 0.95; to: 1; duration: Theme.normal; easing.type: Easing.OutQuint }
        }
        MouseArea { anchors.fill: parent }
        Column {
          id: qcol
          x: 14; y: 14; width: parent.width - 28
          spacing: 8
          Txt { text: "New Event"; font.weight: Font.DemiBold }
          Rectangle {
            width: parent.width; height: 34; radius: 8
            color: Theme.field
            border.width: 1.5; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
            TextInput {
              id: quickIn
              anchors { left: parent.left; leftMargin: 11; right: parent.right; rightMargin: 11; verticalCenter: parent.verticalCenter }
              color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize + 0.5; clip: true
              selectByMouse: true
              Keys.onReturnPressed: { const t = text; quickBox.hide(); if (t.trim()) app.quickAdd(t); else app.newEvent() }
              Keys.onEnterPressed: { const t = text; quickBox.hide(); if (t.trim()) app.quickAdd(t); else app.newEvent() }
              Txt { visible: !quickIn.text; anchors.verticalCenter: parent.verticalCenter; width: parent.width; text: "Lunch with Ana tomorrow at 13"; color: Theme.textFaint; font.pixelSize: Theme.fontSize + 0.5 }
            }
          }
          Txt {
            width: parent.width; wrapMode: Text.Wrap; elide: Text.ElideNone
            text: quickIn.text.trim() ? app.quickPreview(quickIn.text) : "Say what, when and at what time. Return adds it; Return on an empty line, a blank event."
            color: Theme.textDim; font.pixelSize: Theme.small
          }
        }
      }

      // Search results, under the field.
      Rectangle {
        id: results
        property bool open: false
        readonly property var list: open ? app.search(searchIn.text) : []
        function pick(r) {
          open = false; searchIn.focus = false
          if (app.view === "year") app.view = "day"
          app.goTo(r.start)
          app.select(r.ev.id, null, r.start)
        }
        visible: open
        readonly property point at: open ? searchBox.mapToItem(floats, searchBox.width, searchBox.height) : Qt.point(0, 0)
        width: 320
        x: Math.max(10, Math.min(floats.width - width - 10, at.x - width))
        y: at.y + 8
        height: Math.min(floats.height - y - 12, resList.contentHeight + 12)
        radius: 14
        color: Theme.popover
        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
        MouseArea { anchors.fill: parent }
        Txt { visible: results.list.length === 0; anchors.centerIn: parent; text: "No events match."; color: Theme.textDim }
        ListView {
          id: resList
          anchors { fill: parent; margins: 6 }
          clip: true
          model: results.list
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: -1
          Keys.onReturnPressed: if (currentIndex >= 0) results.pick(results.list[currentIndex])
          Keys.onUpPressed: { if (currentIndex <= 0) searchIn.forceActiveFocus(); else decrementCurrentIndex() }
          Keys.onDownPressed: incrementCurrentIndex()
          onActiveFocusChanged: if (activeFocus && currentIndex < 0) currentIndex = 0
          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool lit: rh.hovered || (resList.activeFocus && resList.currentIndex === index)
            width: resList.width; height: 46; radius: 8
            color: lit ? Theme.accent : "transparent"
            Rectangle { x: 10; y: 12; width: 8; height: 8; radius: 4; color: lit ? "#ffffff" : app.colorOf(modelData.ev) }
            Column {
              x: 26; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 36; spacing: 1
              Txt { width: parent.width; text: modelData.ev.title; font.weight: Font.Medium; color: lit ? "#ffffff" : Theme.text }
              Txt {
                width: parent.width; font.pixelSize: Theme.small; color: lit ? Qt.rgba(1, 1, 1, 0.8) : Theme.textDim
                text: Qt.formatDate(new Date(modelData.start), "ddd d MMM yyyy") + (modelData.ev.allDay ? "" : " · " + app.time(modelData.start))
                  + (modelData.ev.location ? " · " + modelData.ev.location : "")
              }
            }
            HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: results.pick(modelData) }
          }
        }
      }
    }

    // ---- a list to choose from, or a date, by the thing clicked
    Pop { id: pop }
    ConfirmSheet { id: confirm }

    // ============================================================ pieces
    component Head: Txt {
      height: 28; verticalAlignment: Text.AlignBottom; bottomPadding: 6; leftPadding: 9
      color: Theme.textDim; font.pixelSize: Theme.small - 0.5; font.weight: Font.DemiBold
    }

    component Tool: Rectangle {
      id: tl
      property string sym: ""
      property string label: ""
      property string tip: ""
      property bool flip: false
      property bool on: false
      signal clicked()
      width: sym ? 30 : lt.implicitWidth + 22; height: 28; radius: 7
      color: on || tt.pressed ? Theme.pressed : (th.hovered ? Theme.hover : "transparent")
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      Sym { visible: tl.sym !== ""; anchors.centerIn: parent; name: tl.sym || "plus"; rotation: tl.flip ? 180 : 0; width: 13; height: 13; color: Theme.text }
      Txt { id: lt; visible: tl.label !== ""; anchors.centerIn: parent; text: tl.label; font.weight: Font.Medium }
      HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
      TapHandler { id: tt; onTapped: tl.clicked() }
      Tip { text: tl.tip }
    }

    // Day | Week | Month | Year, with a raised thumb that slides to the one chosen.
    component Seg: Rectangle {
      id: sg
      property var options: []
      property string value
      signal picked(string v)
      width: sr.implicitWidth + 4; height: 28; radius: 8
      color: Theme.field
      Rectangle {
        id: thumb
        readonly property Item at: { segRep.count; return segRep.itemAt(sg.options.findIndex(o => o[0] === sg.value)) }
        x: at ? sr.x + at.x : 2; y: 2; width: at ? at.width : 0; height: 24; radius: 6
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.2) : "#ffffff"
        border.color: Theme.dark ? "transparent" : Qt.rgba(0, 0, 0, 0.08)
        Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
      }
      Row {
        id: sr
        x: 2; y: 2
        Repeater {
          id: segRep
          model: sg.options
          delegate: Item {
            required property var modelData
            required property int index
            readonly property bool on: sg.value === modelData[0]
            width: Math.max(58, st.implicitWidth + 26); height: 24
            Rectangle {
              visible: index > 0 && !parent.on && sg.options[index - 1][0] !== sg.value
              anchors.verticalCenter: parent.verticalCenter; width: 1; height: 12; color: Theme.separator
            }
            Txt { id: st; anchors.centerIn: parent; text: modelData[1]; font.weight: parent.on ? Font.DemiBold : Font.Normal; color: parent.on || sh.hovered ? Theme.text : Theme.textDim }
            HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sg.picked(modelData[0]) }
            Tip { text: "Ctrl+" + (index + 1) }
          }
        }
      }
    }

    // A calendar in the sidebar: its colour (a click shows or hides it), its name
    // (double-click to rename), right-click for colour and delete.
    component CalRow: Rectangle {
      id: cr
      property var cal
      property bool fixed: false
      property string detail: ""
      signal toggled()
      signal renamed(string name)
      signal recolor()
      signal remove()
      signal pickCountry(var item)
      height: 28; radius: 6
      color: crh.hovered ? Theme.hover : "transparent"
      property bool renaming: !!cal && !!cal.fresh
      Rectangle {
        id: dot
        x: 9; anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 14; radius: 4
        color: cr.cal && cr.cal.on ? cr.cal.color : "transparent"
        border.width: cr.cal && cr.cal.on ? 0 : 1.5; border.color: cr.cal ? cr.cal.color : Theme.textDim
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Sym { anchors.centerIn: parent; visible: cr.cal && cr.cal.on; name: "check"; width: 9; height: 9; color: "#ffffff"; stroke: 2.2 }
        TapHandler { onTapped: cr.toggled() }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
      }
      Txt { visible: !cr.renaming; anchors { left: dot.right; leftMargin: 9; right: tag.left; rightMargin: 6; verticalCenter: parent.verticalCenter } text: cr.cal ? cr.cal.name : "" }
      TextInput {
        visible: cr.renaming
        anchors { left: dot.right; leftMargin: 9; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize; clip: true
        selectByMouse: true
        onVisibleChanged: if (visible) { text = cr.cal.name; forceActiveFocus(); selectAll() }
        Component.onCompleted: if (visible) { text = cr.cal.name; forceActiveFocus(); selectAll() }
        Keys.onReturnPressed: focus = false
        Keys.onEscapePressed: focus = false
        onActiveFocusChanged: if (!activeFocus && cr.renaming) { if (cr.cal.fresh) delete cr.cal.fresh; cr.renaming = false; if (text.trim()) cr.renamed(text.trim()) }
      }
      Rectangle {
        id: tag
        visible: cr.detail !== ""
        anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
        width: visible ? tt2.implicitWidth + 14 : 0; height: 20; radius: 5
        color: tgh.hovered ? Theme.pressed : Theme.field
        Txt { id: tt2; anchors.centerIn: parent; text: cr.detail; color: Theme.textDim; font.pixelSize: Theme.small - 1; font.weight: Font.DemiBold }
        HoverHandler { id: tgh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: cr.pickCountry(tag) }
        Tip { text: "Whose public holidays" }
      }
      HoverHandler { id: crh }
      TapHandler { onDoubleTapped: if (!cr.fixed) cr.renaming = true }
      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: if (!cr.fixed) pop.choose(cr, ["Rename", "Change Colour", "Delete Calendar"], v => {
          if (v === "Rename") cr.renaming = true
          else if (v === "Change Colour") cr.recolor()
          else cr.remove()
        })
      }
    }

    // A month: weekday letters and its days. In the sidebar a dot marks the busy
    // days; in the year they are shaded by how busy they are.
    component MiniMonth: Column {
      id: mm
      property int month
      property int year
      property real selected: 0
      property bool compact: false         // in the year: no arrows, no other months' days
      property bool header: true
      property bool marks: false
      signal picked(real day)
      signal stepped(int n)
      signal titleClicked()
      spacing: 2
      readonly property real cell: width / 7
      readonly property real first: Cal.monthGridStart(year, month)
      readonly property bool thisMonth: month === new Date(app.now).getMonth() && year === new Date(app.now).getFullYear()
      readonly property var busy: {
        if (!marks) return []
        const c = []
        for (let i = 0; i < 42; i++) c.push(0)
        app.layoutWeek(app.occ(first, Cal.addDays(first, 42)), first, 42).forEach(x => { for (let i = x.a; i <= x.b; i++) c[i]++ })
        return c
      }
      Item {
        visible: mm.header
        width: parent.width; height: mm.compact ? 30 : 28
        Txt {
          anchors.verticalCenter: parent.verticalCenter; x: mm.compact ? 4 : 6
          text: Qt.formatDate(new Date(mm.year, mm.month, 1), mm.compact ? "MMMM" : "MMMM yyyy")
          font.pixelSize: mm.compact ? Theme.large + 1 : Theme.fontSize
          font.weight: mm.compact ? Font.DemiBold : Font.DemiBold
          color: mm.compact && mm.thisMonth ? app.tint : Theme.text
          TapHandler { onTapped: mm.titleClicked() }
          HoverHandler { cursorShape: mm.compact ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Row {
          visible: !mm.compact
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          Tool { sym: "chevron"; flip: true; width: 24; height: 24; onClicked: mm.stepped(-1) }
          Tool { sym: "chevron"; width: 24; height: 24; onClicked: mm.stepped(1) }
        }
      }
      Row {
        Repeater {
          model: ["M", "T", "W", "T", "F", "S", "S"]
          delegate: Txt { required property string modelData; width: mm.cell; height: 18; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.textFaint; font.pixelSize: Theme.small - 1.5; font.weight: Font.DemiBold }
        }
      }
      Grid {
        columns: 7
        Repeater {
          model: mm.compact ? Math.ceil(Math.round((new Date(mm.year, mm.month + 1, 1).getTime() - mm.first) / Cal.DAY) / 7) * 7 : 42
          delegate: Item {
            required property int index
            readonly property real day: Cal.addDays(mm.first, index)
            readonly property bool inMonth: new Date(day).getMonth() === mm.month
            readonly property bool today: Cal.sameDay(day, app.now)
            readonly property bool chosen: !mm.compact && Cal.sameDay(day, mm.selected)
            readonly property int n: mm.marks && inMonth ? (mm.busy[index] || 0) : 0
            width: mm.cell; height: Math.min(mm.cell, mm.compact ? 26 : 28)
            Rectangle {
              anchors.centerIn: parent
              visible: parent.inMonth || !mm.compact
              width: Math.min(parent.width, parent.height) - 3; height: width; radius: width / 2
              color: parent.today ? app.tint
                : parent.chosen ? Theme.pressed
                : mh.hovered ? Theme.hover
                : mm.compact && parent.n > 0 ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, (Theme.dark ? 0.06 : 0.05) * Math.min(4, parent.n) + 0.02)
                : "transparent"
            }
            Txt {
              anchors.centerIn: parent
              text: new Date(parent.day).getDate()
              font.pixelSize: mm.compact ? Theme.small - 0.5 : Theme.small
              font.weight: parent.today || parent.chosen ? Font.DemiBold : Font.Normal
              font.features: { "tnum": 1 }
              color: parent.today ? "#ffffff" : (parent.inMonth ? Theme.text : Theme.textFaint)
              opacity: parent.inMonth || !mm.compact ? 1 : 0
            }
            Rectangle {
              visible: parent.n > 0 && !parent.today && !mm.compact
              anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
              width: 3.5; height: 3.5; radius: 1.75; color: Theme.textDim
            }
            HoverHandler { id: mh; enabled: parent.inMonth || !mm.compact; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: parent.inMonth || !mm.compact; onTapped: mm.picked(parent.day) }
          }
        }
      }
    }

    // ---- Month: weeks of seven days; what lasts several days is one bar across them.
    component MonthView: Item {
      id: mv
      readonly property int y0: new Date(app.cursor).getFullYear()
      readonly property int m0: new Date(app.cursor).getMonth()
      readonly property real first: Cal.monthGridStart(y0, m0)
      readonly property int rows: Math.ceil(Math.round((new Date(y0, m0 + 1, 1).getTime() - first) / Cal.DAY) / 7)
      readonly property real cw: width / 7
      readonly property real headH: 26
      readonly property real rh: (height - headH) / rows
      readonly property var all: app.occ(first, Cal.addDays(first, rows * 7))
      // Dragging an event to another day.
      property var drag: null            // { o, grab (the cell it was picked up from) }
      property point dragAt
      property int over: -1
      function cellAt(p) {
        const c = Math.floor(p.x / cw), r = Math.floor((p.y - headH) / rh)
        return c >= 0 && c < 7 && r >= 0 && r < rows ? r * 7 + c : -1
      }

      Row {
        height: mv.headH
        Repeater {
          model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
          delegate: Txt { required property string modelData; required property int index; width: mv.cw; height: mv.headH; horizontalAlignment: Text.AlignRight; rightPadding: 12; text: modelData; color: index >= 5 ? Theme.textFaint : Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Medium }
        }
      }
      Repeater {
        model: mv.rows
        delegate: WeekRow {
          required property int index
          y: mv.headH + index * mv.rh
          width: mv.width; height: mv.rh
          row: index
          grid: mv
          start: Cal.addDays(mv.first, index * 7)
        }
      }
      // The event being dragged, under the pointer.
      Rectangle {
        visible: !!mv.drag
        x: mv.dragAt.x - 24; y: mv.dragAt.y - 11; z: 10
        width: Math.min(200, mv.cw - 8); height: 20; radius: 5
        color: mv.drag ? app.colorOf(mv.drag.o.ev) : "transparent"; opacity: 0.94
        Txt { x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 14; text: mv.drag ? mv.drag.o.ev.title : ""; color: "#ffffff"; font.pixelSize: Theme.small; font.weight: Font.DemiBold }
      }
    }

    // A week of the month view.
    component WeekRow: Item {
      id: wr
      required property var grid   // the MonthView
      required property int row
      required property real start
      readonly property real cw: wr.grid.cw
      readonly property real laneH: 20
      readonly property real headH: 32
      readonly property int fits: Math.max(1, Math.floor((height - headH - 3) / laneH))
      readonly property var lay: app.layoutWeek(wr.grid.all, start, 7)
      readonly property var count: { const c = [0, 0, 0, 0, 0, 0, 0]; lay.forEach(x => { for (let i = x.a; i <= x.b; i++) c[i]++ }); return c }
      readonly property var limit: count.map(n => n > fits ? fits - 1 : fits)
      readonly property var shown: lay.filter(x => { for (let i = x.a; i <= x.b; i++) if (x.lane >= limit[i]) return false; return true })
      readonly property var hidden: { const h = [0, 0, 0, 0, 0, 0, 0]; lay.forEach(x => { if (shown.indexOf(x) < 0) for (let i = x.a; i <= x.b; i++) h[i]++ }); return h }

      Repeater {
        model: 7
        delegate: Rectangle {
          id: dc
          required property int index
          readonly property real day: Cal.addDays(wr.start, index)
          readonly property bool inMonth: new Date(day).getMonth() === wr.grid.m0
          readonly property bool today: Cal.sameDay(day, app.now)
          readonly property bool chosen: Cal.sameDay(day, app.selDay)
          readonly property bool weekend: index >= 5
          x: index * wr.cw; width: wr.cw; height: wr.height
          color: wr.grid.over === wr.row * 7 + index ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
            : chosen ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, Theme.dark ? 0.055 : 0.04)
            : weekend ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, Theme.dark ? 0.02 : 0.025) : "transparent"
          Behavior on color { ColorAnimation { duration: Theme.fast } }
          Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.separator }
          Rectangle { visible: dc.index > 0; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.separator }
          // The day number, in a red circle today; "Nov 1" on the first.
          Rectangle {
            anchors { right: parent.right; rightMargin: 6; top: parent.top; topMargin: 5 }
            width: Math.max(24, dn.implicitWidth + 14); height: 24; radius: 12
            color: dc.today ? app.tint : "transparent"
            Txt {
              id: dn
              anchors.centerIn: parent
              readonly property bool firstDay: new Date(dc.day).getDate() === 1
              text: (firstDay ? Qt.formatDate(new Date(dc.day), "MMM ") : "") + new Date(dc.day).getDate()
              font.pixelSize: Theme.fontSize; font.weight: dc.today || firstDay ? Font.DemiBold : Font.Normal
              font.features: { "tnum": 1 }
              color: dc.today ? "#ffffff" : (dc.inMonth ? Theme.text : Theme.textFaint)
            }
          }
          TapHandler {
            onTapped: { app.selDay = dc.day; app.selId = "" }
            onDoubleTapped: { app.selDay = dc.day; app.newEvent({ start: dc.day + 9 * 3600000, end: dc.day + 10 * 3600000 }, dc) }
          }
        }
      }
      Repeater {
        model: wr.shown
        delegate: Bar {
          required property var modelData
          it: modelData
          x: modelData.a * wr.cw + (modelData.contL ? 0 : 4)
          width: (modelData.b - modelData.a + 1) * wr.cw - (modelData.contL ? 0 : 4) - (modelData.contR ? 0 : 4)
          y: wr.headH + modelData.lane * wr.laneH
          height: wr.laneH - 2
          dim: new Date(Cal.addDays(wr.start, modelData.a)).getMonth() !== wr.grid.m0 && new Date(Cal.addDays(wr.start, modelData.b)).getMonth() !== wr.grid.m0
          month: wr.grid
        }
      }
      Repeater {
        model: 7
        delegate: Rectangle {
          required property int index
          visible: wr.hidden[index] > 0
          x: index * wr.cw + 4; y: wr.headH + wr.limit[index] * wr.laneH
          width: mt.implicitWidth + 12; height: wr.laneH - 2; radius: 5
          color: mth.hovered ? Theme.hover : "transparent"
          Txt { id: mt; x: 6; anchors.verticalCenter: parent.verticalCenter; text: wr.hidden[index] + " more"; color: Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Medium }
          HoverHandler { id: mth; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: { const d = Cal.addDays(wr.start, index); app.dir = 0; app.goTo(d); app.view = "day" } }
        }
      }
    }

    // An event as a bar: filled for all-day ones, a dot and the time for the
    // others. In the month it can be dragged to another day.
    component Bar: Rectangle {
      id: br
      property var it
      property var month: null
      property bool dim: false
      readonly property var o: it.o
      readonly property color c: app.colorOf(o.ev)
      readonly property bool fill: !!o.ev.allDay
      readonly property bool chosen: app.selId === o.ev.id
      radius: 5
      opacity: dim ? 0.5 : 1
      color: chosen ? c : (fill ? Qt.rgba(c.r, c.g, c.b, (Theme.dark ? 0.3 : 0.18) + (bh.hovered ? 0.08 : 0)) : (bh.hovered ? Theme.hover : "transparent"))
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      Rectangle { visible: !br.fill; x: 6; anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 3.5; color: br.chosen ? "#ffffff" : br.c }
      Txt {
        x: br.fill ? 7 : 18; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - (tm.visible ? tm.implicitWidth + 12 : 6)
        text: br.o.ev.title
        font.pixelSize: Theme.small + 0.5; font.weight: br.fill ? Font.DemiBold : Font.Medium
        color: br.chosen ? "#ffffff" : (br.fill ? (Theme.dark ? Qt.lighter(br.c, 1.35) : Qt.darker(br.c, 1.5)) : Theme.text)
      }
      Txt {
        id: tm
        visible: !br.fill && br.width > 110
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        text: app.time(br.o.start); color: br.chosen ? Qt.rgba(1, 1, 1, 0.85) : Theme.textDim; font.pixelSize: Theme.small - 0.5
        font.features: { "tnum": 1 }
      }
      HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
      TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: { app.selDay = Cal.startOfDay(br.o.start); app.select(br.o.ev.id, br, br.o.start) } }
      DragHandler {
        target: null
        enabled: !br.o.ev.holiday && !!br.month
        onActiveChanged: {
          const m = br.month
          if (active) { app.selId = ""; const p = br.mapToItem(m, centroid.pressPosition.x, centroid.pressPosition.y); m.drag = { o: br.o, grab: m.cellAt(p) }; m.dragAt = p; return }
          const d = m.drag, to = m.over
          m.drag = null; m.over = -1
          if (d && to >= 0 && d.grab >= 0) app.shift(d.o.ev, to - d.grab, 0)
        }
        onCentroidChanged: if (active) { const p = br.mapToItem(br.month, centroid.position.x, centroid.position.y); br.month.dragAt = p; br.month.over = br.month.cellAt(p) }
      }
    }

    // ---- Day and Week: the hours, with events where they fall; drag one to
    // move it, its bottom edge to make it longer or shorter.
    component WeekView: Item {
      id: wv
      property int days: 7
      readonly property real first: days === 7 ? Cal.weekStart(app.cursor) : Cal.startOfDay(app.cursor)
      readonly property real gutter: 62
      readonly property real colW: (width - gutter - 14) / days
      readonly property real hourH: 50
      readonly property var all: app.occ(first, Cal.addDays(first, days))
      readonly property var band: app.layoutWeek(all.filter(o => o.ev.allDay), first, days)
      readonly property int bandLanes: Math.max(1, Math.min(3, band.reduce((m, x) => Math.max(m, x.lane + 1), 0)))
      // Timed events of a day, side by side where they overlap.
      function lanes(day) {
        const list = all.filter(o => !o.ev.allDay && Cal.sameDay(o.start, day)).map(o => ({ o: o, lane: 0, of: 1 }))
        const ends = []
        list.forEach(x => {
          let l = ends.findIndex(e => e <= x.o.start)
          if (l < 0) { l = ends.length; ends.push(0) }
          ends[l] = x.o.end; x.lane = l
        })
        list.forEach(x => { x.of = Math.max(1, list.filter(y => y.o.start < x.o.end && y.o.end > x.o.start).reduce((m, y) => Math.max(m, y.lane + 1), 1)) })
        return list
      }
      function label(h) { return Prefs.clock24 ? String(h).padStart(2, "0") + ":00" : (h === 12 ? "Noon" : ((h % 12) || 12) + (h < 12 ? " AM" : " PM")) }

      // Day names and numbers.
      Row {
        id: wh
        x: wv.gutter; height: 40
        Repeater {
          model: wv.days
          delegate: Item {
            id: hd
            required property int index
            readonly property real day: Cal.addDays(wv.first, index)
            readonly property bool today: Cal.sameDay(day, app.now)
            width: wv.colW; height: 40
            Row {
              x: wv.days === 1 ? 10 : (parent.width - width) / 2
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6
              Txt { anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDate(new Date(hd.day), wv.days === 1 ? "dddd" : "ddd"); color: hd.today ? app.tint : Theme.textDim; font.weight: wv.days === 1 ? Font.DemiBold : Font.Normal; font.pixelSize: wv.days === 1 ? Theme.large : Theme.fontSize }
              Rectangle {
                visible: wv.days === 7
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(28, dnum.implicitWidth + 12); height: 28; radius: 14
                color: hd.today ? app.tint : "transparent"
                Txt { id: dnum; anchors.centerIn: parent; text: new Date(hd.day).getDate(); font.pixelSize: 17; font.weight: hd.today ? Font.DemiBold : Font.Normal; font.features: { "tnum": 1 }; color: hd.today ? "#ffffff" : Theme.text }
              }
            }
            TapHandler { onTapped: { app.selDay = hd.day; app.selId = "" } onDoubleTapped: { app.dir = 0; app.goTo(hd.day); app.view = "day" } }
          }
        }
      }
      // All-day events across the top.
      Item {
        id: allBox
        anchors { top: wh.bottom; left: parent.left; right: parent.right }
        height: wv.bandLanes * 22 + 8
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.separator }
        Txt { width: wv.gutter - 10; horizontalAlignment: Text.AlignRight; y: 6; height: 18; text: "all-day"; color: Theme.textFaint; font.pixelSize: Theme.small - 1 }
        Repeater {
          model: wv.days
          delegate: Item {
            required property int index
            readonly property real day: Cal.addDays(wv.first, index)
            x: wv.gutter + index * wv.colW; width: wv.colW; height: allBox.height
            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.separator; opacity: 0.6 }
            TapHandler { onTapped: { app.selDay = parent.day; app.selId = "" } onDoubleTapped: app.newEvent({ start: parent.day, end: parent.day, allDay: true }, parent) }
          }
        }
        Repeater {
          model: wv.band.filter(x => x.lane < 3)
          delegate: Bar {
            required property var modelData
            it: modelData
            x: wv.gutter + modelData.a * wv.colW + (modelData.contL ? 1 : 3)
            width: (modelData.b - modelData.a + 1) * wv.colW - (modelData.contL ? 1 : 3) - (modelData.contR ? 0 : 3)
            y: 4 + modelData.lane * 22
            height: 20
          }
        }
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.separator }
      }
      Flickable {
        id: hours
        anchors { top: allBox.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        contentHeight: 24 * wv.hourH + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        acceptedButtons: Qt.NoButton     // the mouse drags events; the wheel and fingers scroll
        Component.onCompleted: {
          const today = Cal.startOfDay(app.now) >= wv.first && Cal.startOfDay(app.now) < Cal.addDays(wv.first, wv.days)
          const h = today ? Math.max(0, new Date(app.now).getHours() + new Date(app.now).getMinutes() / 60 - 2.5) : 7.5
          contentY = Math.max(0, Math.min(contentHeight - height, h * wv.hourH))
        }
        readonly property real nowY: 10 + (app.now - Cal.startOfDay(app.now)) / 3600000 * wv.hourH
        readonly property bool nowHere: Cal.startOfDay(app.now) >= wv.first && Cal.startOfDay(app.now) < Cal.addDays(wv.first, wv.days)
        // Weekends a shade darker, the chosen day a shade lighter.
        Repeater {
          model: wv.days
          delegate: Rectangle {
            required property int index
            readonly property real day: Cal.addDays(wv.first, index)
            x: wv.gutter + index * wv.colW; y: 10; width: wv.colW; height: 24 * wv.hourH
            color: wv.days === 7 && Cal.sameDay(day, app.selDay) ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, Theme.dark ? 0.035 : 0.03)
              : wv.days === 7 && index >= 5 ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, Theme.dark ? 0.018 : 0.022) : "transparent"
          }
        }
        Repeater {
          model: 24
          delegate: Item {
            required property int index
            y: index * wv.hourH + 10; width: hours.width; height: wv.hourH
            Txt {
              visible: index > 0 && !(hours.nowHere && Math.abs(parent.y - hours.nowY) < 12)
              width: wv.gutter - 12; horizontalAlignment: Text.AlignRight; y: -8; height: 16
              text: wv.label(index); color: Theme.textFaint; font.pixelSize: Theme.small - 1; font.features: { "tnum": 1 }
            }
            Rectangle { x: wv.gutter - 4; width: hours.width - wv.gutter - 10; height: 1; color: Theme.separator }
            Rectangle { x: wv.gutter; y: wv.hourH / 2; width: hours.width - wv.gutter - 14; height: 1; color: Theme.separator; opacity: 0.4 }
          }
        }
        Repeater {
          model: wv.days
          delegate: Item {
            id: dcol
            required property int index
            readonly property real day: Cal.addDays(wv.first, index)
            x: wv.gutter + index * wv.colW; y: 10; width: wv.colW; height: 24 * wv.hourH
            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.separator; opacity: 0.6 }
            // A double-click on an empty half hour: a new event there.
            TapHandler {
              onTapped: { app.selDay = dcol.day; app.selId = "" }
              onDoubleTapped: ev => {
                const m = Math.floor(ev.position.y / wv.hourH * 2) * 30
                app.newEvent({ start: dcol.day + m * 60000, end: dcol.day + (m + 60) * 60000 })
              }
            }
            Repeater {
              model: wv.lanes(dcol.day)
              delegate: Rectangle {
                id: blk
                required property var modelData
                readonly property var o: modelData.o
                readonly property color c: app.colorOf(o.ev)
                readonly property bool chosen: app.selId === o.ev.id
                readonly property real m0: (o.start - dcol.day) / 60000
                readonly property real m1: Math.min(24 * 60, (o.end - dcol.day) / 60000)
                property real dy: 0          // minutes moved while dragging
                property int dd: 0           // days moved
                property real dh: 0          // minutes added to its end
                readonly property bool busy: mover.active || sizer.active
                readonly property real s: o.start + dy * 60000
                readonly property real e: o.end + (dy + dh) * 60000
                z: busy ? 6 : (chosen ? 2 : 1)
                x: (busy ? 1 : 1 + modelData.lane * (dcol.width - 4) / modelData.of) + dd * wv.colW
                width: busy ? dcol.width - 4 : (dcol.width - 4) / modelData.of - 1
                y: (m0 + dy) / 60 * wv.hourH + 1
                height: Math.max(19, (m1 - m0 + dh) / 60 * wv.hourH - 2)
                radius: 6
                color: chosen || busy ? c : Qt.rgba(c.r, c.g, c.b, (Theme.dark ? 0.27 : 0.16) + (bkh.hovered ? 0.07 : 0))
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                opacity: busy ? 0.94 : 1
                Rectangle { visible: !blk.chosen && !blk.busy; x: 0; width: 3; height: parent.height; radius: 1.5; color: blk.c }
                Column {
                  x: 9; y: blk.height > 30 ? 5 : 2; width: parent.width - 14
                  spacing: 1
                  Txt {
                    width: parent.width; text: blk.o.ev.title
                    font.pixelSize: Theme.small + 0.5; font.weight: Font.DemiBold
                    color: blk.chosen || blk.busy ? "#ffffff" : (Theme.dark ? Qt.lighter(blk.c, 1.4) : Qt.darker(blk.c, 1.55))
                  }
                  Txt {
                    visible: blk.height > 34
                    width: parent.width; font.pixelSize: Theme.small - 0.5; font.features: { "tnum": 1 }
                    text: app.time(blk.s) + " – " + app.time(blk.e) + (blk.o.ev.location && !blk.busy ? " · " + blk.o.ev.location : "")
                    color: blk.chosen || blk.busy ? Qt.rgba(1, 1, 1, 0.85) : (Theme.dark ? Qt.rgba(Qt.lighter(blk.c, 1.4).r, Qt.lighter(blk.c, 1.4).g, Qt.lighter(blk.c, 1.4).b, 0.8) : Qt.rgba(Qt.darker(blk.c, 1.55).r, Qt.darker(blk.c, 1.55).g, Qt.darker(blk.c, 1.55).b, 0.8))
                  }
                }
                HoverHandler { id: bkh; cursorShape: blk.busy ? Qt.ClosedHandCursor : Qt.PointingHandCursor }
                TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: { app.selDay = dcol.day; app.select(blk.o.ev.id, blk, blk.o.start) } }
                DragHandler {
                  id: mover
                  target: null
                  enabled: !blk.o.ev.holiday
                  onActiveChanged: {
                    if (active) { app.selId = ""; return }
                    const ev = blk.o.ev, d = blk.dd, m = blk.dy
                    blk.dd = 0; blk.dy = 0
                    app.shift(ev, d, m)
                  }
                  onActiveTranslationChanged: if (active) {
                    blk.dy = Math.max(-blk.m0, Math.min(24 * 60 - 15 - blk.m0, Math.round(activeTranslation.y / wv.hourH * 4) * 15))
                    blk.dd = Math.max(-dcol.index, Math.min(wv.days - 1 - dcol.index, Math.round(activeTranslation.x / wv.colW)))
                  }
                }
                // The bottom edge: longer or shorter.
                Item {
                  anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                  height: 7
                  HoverHandler { cursorShape: Qt.SizeVerCursor }
                  DragHandler {
                    id: sizer
                    target: null
                    enabled: !blk.o.ev.holiday
                    onActiveChanged: {
                      if (active) { app.selId = ""; return }
                      const ev = blk.o.ev, m = blk.dh
                      blk.dh = 0
                      app.stretch(ev, m)
                    }
                    onActiveTranslationChanged: if (active) blk.dh = Math.max(15 - (blk.m1 - blk.m0), Math.round(activeTranslation.y / wv.hourH * 4) * 15)
                  }
                }
              }
            }
          }
        }
        // Now: a red line across today, faint across the other days.
        Item {
          readonly property real d0: Cal.startOfDay(app.now)
          readonly property int col: Math.round((d0 - wv.first) / Cal.DAY)
          visible: hours.nowHere
          y: hours.nowY; z: 8
          width: hours.width; height: 2
          Rectangle { x: wv.gutter; width: wv.colW * wv.days; height: 1; color: app.tint; opacity: 0.35 }
          Rectangle { x: wv.gutter + parent.col * wv.colW; width: wv.colW; y: -0.5; height: 2; color: app.tint }
          Rectangle { x: wv.gutter + parent.col * wv.colW - 4; y: -3.5; width: 8; height: 8; radius: 4; color: app.tint }
          Rectangle {
            x: wv.gutter - 4 - width; y: -8; height: 16; radius: 8
            width: nowT.implicitWidth + 10
            color: app.tint
            Txt { id: nowT; anchors.centerIn: parent; text: app.time(app.now); color: "#ffffff"; font.pixelSize: Theme.small - 1.5; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
          }
        }
      }
    }

    // ---- Year: twelve months; a day is shaded by how much is on it.
    component YearView: Flickable {
      id: yv
      readonly property int y0: new Date(app.cursor).getFullYear()
      readonly property int cols: width > 1000 ? 4 : (width > 640 ? 3 : 2)
      contentHeight: yg.implicitHeight + 40
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Grid {
        id: yg
        x: 26; y: 6
        columns: yv.cols
        columnSpacing: 34; rowSpacing: 18
        Repeater {
          model: 12
          delegate: MiniMonth {
            required property int index
            width: (yv.width - 52 - (yv.cols - 1) * 34) / yv.cols
            month: index; year: yv.y0; compact: true; marks: true
            onPicked: d => { app.dir = 0; app.goTo(d); app.view = "day" }
            onTitleClicked: { app.dir = 0; app.cursor = new Date(yv.y0, index, 1).getTime(); app.view = "month" }
          }
        }
      }
    }

    // ---- the event's card, beside it
    component EventCard: Rectangle {
      id: ins
      readonly property var ev: app.sel
      readonly property bool shown: !!ev
      readonly property bool ro: !ev || !!ev.holiday
      readonly property bool typing: ttl.activeFocus || loc.activeFocus || notes.activeFocus
      readonly property rect r: app.selRect
      function focusTitle() { ttl.forceActiveFocus(); ttl.selectAll() }
      function askDelete() {
        const e = ev; if (!e || e.holiday) return
        if (e.repeat && e.repeat !== "none") {
          pop.choose(delBtn, ["Delete Only This One", "Delete All of Them"], v => app.removeEvent(e, v.indexOf("Only") >= 0, app.selOcc || e.start))
        } else confirm.ask({ title: "Delete “" + e.title + "”?", message: "You can't undo this.", action: "Delete", onAccept: () => app.removeEvent(e, false, 0) })
      }
      visible: shown
      width: Math.min(340, floats.width - 20)
      height: Math.min(floats.height - 20, ic.implicitHeight + 34)
      // Beside what was clicked: on its right if there's room, else on its left.
      readonly property bool onRight: r.width > 0 && r.x + r.width + 10 + width <= floats.width - 10
      x: {
        if (r.width <= 0) return floats.width - width - 16
        if (onRight) return r.x + r.width + 10
        if (r.x - width - 10 >= 10) return r.x - width - 10
        return Math.max(10, Math.min(floats.width - width - 10, r.x + r.width / 2 - width / 2))
      }
      y: Math.max(10, Math.min(floats.height - height - 10, r.width <= 0 ? 104 : r.y + Math.min(r.height, 40) / 2 - 40))
      radius: 14
      color: Theme.popover
      border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
      transformOrigin: onRight ? Item.Left : Item.Right
      Connections { target: app; function onSelIdChanged() { if (app.selId) cardIn.restart() } }
      ParallelAnimation {
        id: cardIn
        NumberAnimation { target: ins; property: "opacity"; from: 0; to: 1; duration: Theme.fast; easing.type: Easing.OutCubic }
        NumberAnimation { target: ins; property: "scale"; from: 0.95; to: 1; duration: Theme.normal; easing.type: Easing.OutQuint }
      }
      MouseArea { anchors.fill: parent }
      Flickable {
        anchors.fill: parent
        contentHeight: ic.implicitHeight + 34
        interactive: contentHeight > height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
          id: ic
          x: 18; y: 16; width: ins.width - 36
          spacing: 10
          // Title and place; the calendar's colour on the right picks the calendar.
          RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 3
              TextInput {
                id: ttl
                Layout.fillWidth: true
                text: ins.ev ? ins.ev.title : ""
                readOnly: ins.ro
                color: Theme.text; font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold
                wrapMode: TextInput.Wrap
                selectByMouse: true
                onTextEdited: app.update(ins.ev, "title", text)
                Keys.onReturnPressed: focus = false
              }
              TextInput {
                id: loc
                visible: !ins.ro
                Layout.fillWidth: true
                text: ins.ev ? (ins.ev.location || "") : ""
                color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.fontSize
                selectByMouse: true; clip: true
                onTextEdited: app.update(ins.ev, "location", text)
                Keys.onReturnPressed: focus = false
                Txt { visible: !loc.text; anchors.verticalCenter: parent.verticalCenter; text: "Add Location"; color: Theme.textFaint }
              }
              Txt {
                visible: !!ins.ev && !!ins.ev.holiday
                Layout.fillWidth: true; wrapMode: Text.Wrap; elide: Text.ElideNone
                text: "A public holiday in " + app.countryName(app.cc) + (ins.ev ? " · " + Qt.formatDate(new Date(ins.ev.start), "dddd d MMMM yyyy") : "")
                color: Theme.textDim
              }
            }
            Rectangle {
              id: calPick
              Layout.alignment: Qt.AlignTop
              Layout.topMargin: 3
              width: 34; height: 22; radius: 6
              visible: !ins.ro
              color: cph.hovered ? Theme.pressed : Theme.hover
              Rectangle { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 3.5; color: ins.ev ? app.colorOf(ins.ev) : "transparent" }
              Sym { x: 21; anchors.verticalCenter: parent.verticalCenter; name: "chevron"; rotation: 90; width: 8; height: 8; color: Theme.textDim }
              HoverHandler { id: cph; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: pop.choose(calPick, app.calendars.map(c => c.name), v => app.update(ins.ev, "cal", app.calendars.find(c => c.name === v).id)) }
              Tip { text: ins.ev ? "Calendar: " + app.calOf(ins.ev.cal).name : "" }
            }
          }
          Sep { visible: !ins.ro }
          // When.
          Row2 {
            label: "All-day"
            visible: !ins.ro
            Switch2 { on: !!ins.ev && ins.ev.allDay; onToggled: v => { const e = ins.ev; e.allDay = v; if (v) { e.start = Cal.startOfDay(e.start); e.end = Cal.startOfDay(e.end); e.alert = -1 } else { e.start = Cal.startOfDay(e.start) + 9 * 3600000; e.end = Cal.startOfDay(e.end) + 10 * 3600000; e.alert = 10 } app.changed() } }
          }
          Row2 {
            visible: !ins.ro
            label: ins.ev && ins.ev.allDay ? "From" : "Starts"
            DateTime { t: ins.ev ? ins.ev.start : 0; allDay: !!ins.ev && ins.ev.allDay; ro: ins.ro
              onMoved: v => { const e = ins.ev, len = e.end - e.start; e.start = v; e.end = v + len; app.changed() } }
          }
          Row2 {
            visible: !ins.ro
            label: ins.ev && ins.ev.allDay ? "To" : "Ends"
            DateTime { t: ins.ev ? ins.ev.end : 0; allDay: !!ins.ev && ins.ev.allDay; ro: ins.ro; onMoved: v => app.update(ins.ev, "end", v) }
          }
          Sep { visible: !ins.ro }
          Row2 {
            visible: !ins.ro
            label: "Repeat"
            Pill2 {
              id: repPill
              readonly property var names: ({ none: "Never", daily: "Every Day", weekly: "Every Week", monthly: "Every Month", yearly: "Every Year" })
              text: ins.ev ? names[ins.ev.repeat || "none"] : ""
              onClicked: pop.choose(repPill, ["Never", "Every Day", "Every Week", "Every Month", "Every Year"], v => app.update(ins.ev, "repeat", Object.keys(names).find(k => names[k] === v)))
            }
          }
          Row2 {
            visible: !ins.ro
            label: "Alert"
            Pill2 {
              id: alertPill
              readonly property var opts: [[-1, "None"], [0, "At the start"], [5, "5 minutes before"], [10, "10 minutes before"], [15, "15 minutes before"], [30, "30 minutes before"], [60, "1 hour before"], [120, "2 hours before"], [1440, "1 day before"], [2880, "2 days before"]]
              text: ins.ev ? ((opts.find(o => o[0] === (ins.ev.alert === undefined ? -1 : ins.ev.alert)) || [0, "None"])[1]) : ""
              onClicked: pop.choose(alertPill, opts.map(o => o[1]), v => app.update(ins.ev, "alert", opts.find(o => o[1] === v)[0]))
            }
          }
          Sep { visible: !ins.ro }
          Item {
            visible: !ins.ro
            Layout.fillWidth: true
            implicitHeight: Math.max(44, notes.contentHeight + 8)
            TextEdit {
              id: notes
              y: 4; width: parent.width
              text: ins.ev ? (ins.ev.notes || "") : ""
              color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize
              wrapMode: TextEdit.Wrap; selectByMouse: true
              onTextChanged: if (activeFocus) app.update(ins.ev, "notes", text)
              Txt { visible: !notes.text && !notes.activeFocus; text: "Add Notes"; color: Theme.textFaint }
            }
          }
          Rectangle {
            id: delBtn
            visible: !ins.ro
            Layout.alignment: Qt.AlignLeft
            implicitWidth: dlt.implicitWidth + 20; implicitHeight: 28; radius: 7
            color: dh.hovered ? Qt.rgba(1, 0.23, 0.19, 0.14) : "transparent"
            Txt { id: dlt; anchors.centerIn: parent; text: "Delete Event"; color: Theme.red; font.weight: Font.Medium }
            HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ins.askDelete() }
            Tip { text: "Delete" }
          }
        }
      }
    }
    component Sep: Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.separator }
    component Row2: Item {
      id: r2
      property string label
      default property alias content: r2c.data
      Layout.fillWidth: true
      implicitHeight: 30
      Txt { anchors.verticalCenter: parent.verticalCenter; text: r2.label; color: Theme.textDim }
      Row { id: r2c; anchors { right: parent.right; verticalCenter: parent.verticalCenter } spacing: 6 }
    }
    component Pill2: Rectangle {
      id: p2
      property string text
      signal clicked()
      width: Math.min(190, pt.implicitWidth + 34); height: 26; radius: 7
      color: ph2.hovered ? Theme.pressed : Theme.hover
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      Txt { id: pt; x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 30; text: p2.text }
      Sym { anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter } name: "chevron"; rotation: 90; width: 8; height: 8; color: Theme.textDim }
      HoverHandler { id: ph2; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: p2.clicked() }
    }
    component Switch2: Rectangle {
      id: s2
      property bool on: false
      signal toggled(bool v)
      width: 38; height: 22; radius: 11
      color: on ? Theme.green : (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      Rectangle { width: 18; height: 18; radius: 9; y: 2; x: s2.on ? 18 : 2; color: "#ffffff"; Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } } }
      HoverHandler { cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: s2.toggled(!s2.on) }
    }
    // A date (tap for a month to pick from) and, unless all-day, a time you can
    // type or scroll in 15-minute steps.
    component DateTime: Row {
      id: dt
      property real t
      property bool allDay: false
      property bool ro: false
      signal moved(real v)
      spacing: 6
      Rectangle {
        id: datePill
        width: dtt.implicitWidth + 20; height: 26; radius: 7
        color: dph.hovered ? Theme.pressed : Theme.hover
        Txt { id: dtt; anchors.centerIn: parent; text: dt.t ? Qt.formatDate(new Date(dt.t), "ddd d MMM yyyy") : ""; font.features: { "tnum": 1 } }
        HoverHandler { id: dph; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: if (!dt.ro) pop.pickDate(datePill, dt.t, d => dt.moved(d + (dt.t - Cal.startOfDay(dt.t)))) }
      }
      Rectangle {
        visible: !dt.allDay
        width: 58; height: 26; radius: 7
        color: tin.activeFocus ? Theme.field : Theme.hover
        border.width: tin.activeFocus ? 1.5 : 0
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7)
        TextInput {
          id: tin
          anchors.centerIn: parent
          width: parent.width - 10
          horizontalAlignment: TextInput.AlignHCenter
          readOnly: dt.ro
          selectByMouse: true
          text: dt.t ? Qt.formatTime(new Date(dt.t), "HH:mm") : ""
          color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize; font.features: { "tnum": 1 }
          validator: RegularExpressionValidator { regularExpression: /^([01]?\d|2[0-3])[:.]?([0-5]\d)?$/ }
          onEditingFinished: {
            const m = text.match(/^(\d{1,2})[:.]?(\d{2})?$/)
            if (m) dt.moved(Cal.startOfDay(dt.t) + (+m[1]) * 3600000 + (+(m[2] || 0)) * 60000)
          }
          Keys.onUpPressed: dt.moved(dt.t + 15 * 60000)
          Keys.onDownPressed: dt.moved(dt.t - 15 * 60000)
        }
        WheelHandler { enabled: !dt.ro; onWheel: ev => dt.moved(dt.t + (ev.angleDelta.y > 0 ? 15 : -15) * 60000) }
      }
    }

    // A small list (or a month) next to what was clicked.
    component Pop: Item {
      id: pp
      anchors.fill: parent
      z: 900
      property bool open: false
      property var items: []
      property var onPick: null
      property bool dateMode: false
      property real dateVal: 0
      property point at
      visible: open
      function place(item) { const p = item.mapToItem(pp, 0, item.height + 4); at = Qt.point(Math.max(8, Math.min(width - 250, p.x)), p.y) }
      function choose(item, list, cb) { place(item); dateMode = false; items = list; onPick = cb; open = true; popAnim.restart() }
      function pickDate(item, t, cb) { place(item); dateMode = true; dateVal = t; onPick = cb; open = true; popAnim.restart() }
      function close() { open = false }
      MouseArea { anchors.fill: parent; onClicked: pp.close() }
      Rectangle {
        id: popBox
        x: pp.at.x; y: Math.min(pp.at.y, pp.height - height - 8)
        width: pp.dateMode ? 250 : Math.max(180, lcol.implicitWidth + 12)
        height: pp.dateMode ? dm.implicitHeight + 20 : Math.min(pp.height - 16, lcol.implicitHeight + 12)
        radius: 12
        color: Theme.popover
        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
        clip: true
        NumberAnimation { id: popAnim; target: popBox; property: "opacity"; from: 0; to: 1; duration: Theme.fast; easing.type: Easing.OutCubic }
        MouseArea { anchors.fill: parent }
        Flickable {
          visible: !pp.dateMode
          anchors.fill: parent
          contentHeight: lcol.implicitHeight + 12
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          Column {
            id: lcol
            x: 6; y: 6
            Repeater {
              model: pp.dateMode ? [] : pp.items
              delegate: Rectangle {
                required property string modelData
                width: Math.max(168, lt2.implicitWidth + 24); height: 26; radius: 6
                color: lh.hovered ? Theme.accent : "transparent"
                Txt { id: lt2; x: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: lh.hovered ? "#ffffff" : (modelData.startsWith("Delete") ? Theme.red : Theme.text) }
                HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { pp.close(); if (pp.onPick) pp.onPick(modelData) } }
              }
            }
          }
        }
        MiniMonth {
          id: dm
          visible: pp.dateMode
          x: 10; y: 10; width: 230
          property real shown: pp.dateVal
          month: new Date(shown || Date.now()).getMonth(); year: new Date(shown || Date.now()).getFullYear()
          selected: pp.dateVal
          onStepped: n => shown = new Date(year, month + n, 1).getTime()
          onPicked: d => { pp.close(); if (pp.onPick) pp.onPick(d) }
          Connections { target: pp; function onDateValChanged() { dm.shown = pp.dateVal } }
        }
      }
    }
  }

  readonly property var countries: CalData.countries
  function countryName(c) { const x = countries.find(k => k[0] === c); return x ? x[1] : c }
}
