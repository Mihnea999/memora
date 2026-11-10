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

// Calendar: your events by week, month or year, in calendars of their own
// colour, with the public holidays of your country. Type an event the way you'd
// say it ("Lunch with Ana tomorrow at 13"), drag it to another day, and the
// desktop reminds you before it starts (calendar/Alerts.qml). Everything lives
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
  property string view: "month"          // week | month | year
  property real cursor: Cal.startOfDay(Date.now())  // the day in focus
  property real selDay: cursor
  property string selId: ""              // the event in the inspector
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
        const j = JSON.parse(text())
        if (j.calendars && j.calendars.length) app.calendars = j.calendars
        app.events = j.events || []
        if (j.country !== undefined) app.country = j.country
        if (j.showHolidays !== undefined) app.showHolidays = j.showHolidays
      } catch (e) {}
      app.loaded = true
    }
    onLoadFailed: app.loaded = true
  }
  FileView { id: backup; path: app.store + ".bak"; printErrors: false }
  property string lastSaved: ""
  Timer { id: saveLater; interval: 500; onTriggered: app.saveNow() }
  function saveNow() {
    if (!loaded) return
    const t = JSON.stringify({ version: 1, calendars: calendars, events: events, country: country, showHolidays: showHolidays }, null, 1)
    if (t === lastSaved) return
    lastSaved = t
    Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/share/memora"])
    file.setText(t); backup.setText(t)
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

  function newEvent(o) {
    const c = calendars.find(x => x.on) || calendars[0]
    const ev = Object.assign({ id: "e" + Date.now() + Math.floor(Math.random() * 1000), title: "New Event", cal: c.id,
      start: selDay + 9 * 3600000, end: selDay + 10 * 3600000, allDay: false, location: "", notes: "", repeat: "none", until: 0, alert: 10, skip: [] }, o || {})
    if (ev.allDay) ev.alert = -1
    events = events.concat([ev])
    selDay = Cal.startOfDay(ev.start)
    selId = ev.id
    changed()
    Qt.callLater(() => inspector.focusTitle())
    return ev
  }
  function quickAdd(text) {
    if (!text.trim()) return
    const q = Cal.quick(text, Date.now())
    newEvent({ title: q.title, start: q.start, end: q.end, allDay: q.allDay })
    goTo(q.start)
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
  // Dragged to another day: the time of day stays.
  function moveBy(ev, days) {
    if (!ev || ev.holiday || !days) return
    ev.start = Cal.addDays(ev.start, days); ev.end = Cal.addDays(ev.end, days)
    changed()
  }

  // ---- moving around
  function goTo(t) { const d = Cal.startOfDay(t); dir = d > cursor ? 1 : (d < cursor ? -1 : 0); cursor = d; selDay = d }
  function stepView(n) {
    dir = n
    if (view === "week") cursor = Cal.addDays(cursor, 7 * n)
    else if (view === "month") { const d = new Date(cursor); cursor = new Date(d.getFullYear(), d.getMonth() + n, 1).getTime() }
    else { const d = new Date(cursor); cursor = new Date(d.getFullYear() + n, d.getMonth(), 1).getTime() }
  }
  function time(t) { return Qt.formatTime(new Date(t), Prefs.clock24 ? "HH:mm" : "h:mm AP") }
  function span(o) {
    if (o.ev.allDay) return Cal.sameDay(o.start, o.end) ? "All day" : Qt.formatDate(new Date(o.start), "d MMM") + " – " + Qt.formatDate(new Date(o.end), "d MMM")
    return time(o.start) + " – " + time(o.end)
  }
  readonly property string title: {
    const d = new Date(cursor)
    if (view === "year") return String(d.getFullYear())
    if (view === "week") {
      const a = new Date(Cal.weekStart(cursor)), b = new Date(Cal.addDays(Cal.weekStart(cursor), 6))
      return a.getMonth() === b.getMonth() ? Qt.formatDate(a, "MMMM yyyy") : Qt.formatDate(a, "MMM") + " – " + Qt.formatDate(b, "MMM yyyy")
    }
    return Qt.formatDate(d, "MMMM yyyy")
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
    implicitWidth: 1220
    implicitHeight: 780
    minimumSize: Qt.size(560, 440)
    color: "transparent"
    Rectangle { anchors.fill: parent; color: Theme.window }
    ConfirmSheet { id: confirm }

    readonly property bool narrow: width < 920
    property bool sideHere: false
    onNarrowChanged: sideHere = false
    readonly property bool sideOpen: narrow ? sideHere : true

    Shortcut { sequence: "Ctrl+N"; onActivated: app.newEvent() }
    Shortcut { sequence: "Ctrl+T"; onActivated: app.goTo(Date.now()) }
    Shortcut { sequence: "Ctrl+1"; onActivated: app.view = "week" }
    Shortcut { sequence: "Ctrl+2"; onActivated: app.view = "month" }
    Shortcut { sequence: "Ctrl+3"; onActivated: app.view = "year" }
    Shortcut { sequence: "Ctrl+Right"; onActivated: app.stepView(1) }
    Shortcut { sequence: "Ctrl+Left"; onActivated: app.stepView(-1) }
    Shortcut { sequence: "Ctrl+F"; onActivated: quick.forceActiveFocus() }
    Shortcut { sequence: "Escape"; onActivated: { if (pop.open) pop.close(); else if (app.selId) app.selId = ""; else quick.focus = false } }
    Shortcut { sequence: "Delete"; enabled: !!app.sel && !app.sel.holiday && !inspector.typing; onActivated: inspector.askDelete() }
    Shortcut { sequence: "Ctrl+W"; onActivated: { app.saveNow(); Qt.quit() } }

    // ---- sidebar
    Rectangle {
      id: side
      width: 248
      x: win.sideOpen ? (win.narrow ? 8 : 0) : -width - 20
      Behavior on x { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
      z: win.narrow ? 20 : 1
      anchors { top: parent.top; bottom: parent.bottom; topMargin: win.narrow ? 8 : 0; bottomMargin: win.narrow ? 8 : 0 }
      radius: win.narrow ? 14 : 0
      color: win.narrow ? Theme.glassSolid : Theme.sidebar
      border.color: win.narrow ? Theme.separator : "transparent"
      Rectangle { visible: !win.narrow; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.separator }
      Item { anchors { left: parent.left; right: parent.right; top: parent.top } height: 44; DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) } }
      WindowControls { x: 18; y: 16; window: win; onCloseRequested: { app.saveNow(); Qt.quit() } }

      Flickable {
        anchors { fill: parent; topMargin: 50 }
        contentHeight: sideCol.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: sideCol
          x: 16; width: side.width - 32
          spacing: 18
          MiniMonth {
            width: parent.width
            month: new Date(app.cursor).getMonth(); year: new Date(app.cursor).getFullYear()
            selected: app.selDay
            onPicked: d => { app.goTo(d); if (win.narrow) win.sideHere = false }
            onStepped: n => { app.dir = n; app.cursor = new Date(year, month + n, 1).getTime() }
          }

          Column {
            width: parent.width
            spacing: 2
            Head { text: "Calendars" }
            Repeater {
              model: app.calendars
              delegate: CalRow {
                required property var modelData
                required property int index
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
            Item {
              width: sideCol.width; height: 30
              Sym { x: 6; anchors.verticalCenter: parent.verticalCenter; name: "plus"; width: 12; height: 12; color: Theme.textDim }
              Txt { x: 28; anchors.verticalCenter: parent.verticalCenter; text: "New Calendar"; color: Theme.textDim; font.pixelSize: Theme.small + 0.5 }
              HoverHandler { cursorShape: Qt.PointingHandCursor }
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
            spacing: 4
            Head { text: "Up Next" }
            Txt { visible: app.upNext.length === 0; text: "Nothing in the next two weeks."; color: Theme.textFaint; font.pixelSize: Theme.small; width: parent.width; wrapMode: Text.Wrap }
            Repeater {
              model: app.upNext
              delegate: Rectangle {
                required property var modelData
                width: sideCol.width; height: 46; radius: 9
                color: uh.hovered ? Theme.hover : "transparent"
                Rectangle { x: 8; y: 8; width: 3; height: 30; radius: 1.5; color: app.colorOf(modelData.ev) }
                Column {
                  x: 20; y: 6; width: parent.width - 28; spacing: 1
                  Txt { width: parent.width; text: modelData.ev.title; font.weight: Font.Medium; elide: Text.ElideRight }
                  Txt {
                    width: parent.width; elide: Text.ElideRight; color: Theme.textDim; font.pixelSize: Theme.small
                    text: (Cal.sameDay(modelData.start, app.now) ? "Today" : (Cal.sameDay(modelData.start, Cal.addDays(app.now, 1)) ? "Tomorrow" : Qt.formatDate(new Date(modelData.start), "ddd d MMM")))
                      + (modelData.ev.allDay ? "" : " · " + app.time(modelData.start))
                  }
                }
                HoverHandler { id: uh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { app.goTo(modelData.start); app.selId = modelData.ev.id } }
              }
            }
          }
        }
      }
    }
    MouseArea { anchors.fill: parent; z: 19; visible: win.narrow && win.sideHere; onClicked: win.sideHere = false }

    // ---- toolbar
    Item {
      id: bar
      anchors { left: win.narrow ? parent.left : side.right; right: inspector.left; top: parent.top }
      height: 62
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) }
      CompactBar { visible: win.narrow; x: 16; anchors.verticalCenter: parent.verticalCenter; window: win; sideOpen: win.sideHere; onToggled: win.sideHere = !win.sideHere; onCloseRequested: { app.saveNow(); Qt.quit() } }
      Row {
        id: heading
        x: win.narrow ? 128 : 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Txt {
          anchors.verticalCenter: parent.verticalCenter
          text: app.view === "year" ? "" : app.title.replace(/ \d{4}$/, "")
          font.pixelSize: 24; font.weight: Font.Bold
          visible: text !== ""
        }
        Txt { anchors.verticalCenter: parent.verticalCenter; text: new Date(app.cursor).getFullYear(); font.pixelSize: 24; font.weight: Font.Light; color: app.view === "year" ? Theme.text : Theme.textDim }
      }
      Row {
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 8
        // Quick entry: type it the way you'd say it.
        Rectangle {
          visible: bar.width > 860
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(300, bar.width - 640); height: 32; radius: 9
          color: Theme.field; border.color: quick.activeFocus ? app.tint : Theme.separator
          Sym { x: 10; anchors.verticalCenter: parent.verticalCenter; name: "plus"; width: 12; height: 12; color: Theme.textDim }
          TextInput {
            id: quick
            anchors { left: parent.left; leftMargin: 30; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5; clip: true
            Keys.onReturnPressed: { app.quickAdd(text); text = "" }
            Keys.onEscapePressed: { text = ""; focus = false }
            Txt { visible: !quick.text; anchors.verticalCenter: parent.verticalCenter; width: parent.width; text: "Lunch with Ana tomorrow at 13"; color: Theme.textFaint; font.pixelSize: Theme.small + 0.5 }
          }
          Tip { text: "Type an event the way you'd say it, then Return" }
        }
        Seg {
          anchors.verticalCenter: parent.verticalCenter
          options: [["week", "Week"], ["month", "Month"], ["year", "Year"]]
          value: app.view
          onPicked: v => { app.dir = 0; app.view = v }
        }
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Tool { sym: "chevron"; flip: true; tip: "Previous (Ctrl+←)"; onClicked: app.stepView(-1) }
          Tool { label: "Today"; tip: "Go to today (Ctrl+T)"; onClicked: app.goTo(Date.now()) }
          Tool { sym: "chevron"; tip: "Next (Ctrl+→)"; onClicked: app.stepView(1) }
        }
        Tool { anchors.verticalCenter: parent.verticalCenter; sym: "plus"; tip: "New Event (Ctrl+N)"; onClicked: app.newEvent() }
      }
    }

    // ---- the calendar itself
    Item {
      id: body
      anchors { left: win.narrow ? parent.left : side.right; right: inspector.left; top: bar.bottom; bottom: parent.bottom }
      clip: true
      SwipeNav { onBack: app.stepView(-1) }

      // A short slide when moving to the next or previous month, week or year.
      Item {
        id: slide
        width: body.width; height: body.height
        transform: Translate { id: slideT }
        Connections {
          target: app
          function onCursorChanged() { if (app.dir !== 0) { slideAnim.restart() } }
          function onViewChanged() { fadeAnim.restart() }
        }
        ParallelAnimation {
          id: slideAnim
          NumberAnimation { target: slideT; property: "x"; from: app.dir * 36; to: 0; duration: Theme.slow; easing.type: Easing.OutQuint }
          NumberAnimation { target: slide; property: "opacity"; from: 0.25; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }
        }
        NumberAnimation { id: fadeAnim; target: slide; property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Easing.OutCubic }

        MonthView { anchors.fill: parent; visible: app.view === "month" }
        WeekView { anchors.fill: parent; visible: app.view === "week" }
        YearView { anchors.fill: parent; visible: app.view === "year" }
      }
    }

    // ---- the event, on the right
    Inspector {
      id: inspector
      anchors { top: parent.top; bottom: parent.bottom }
      width: app.sel ? Math.min(340, win.width * 0.42) : 0
      x: win.width - width
      Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutQuint } }
    }

    // ---- a list to choose from, or a date, by the thing clicked
    Pop { id: pop }

    // ============================================================ pieces
    component Head: Txt {
      height: 26; verticalAlignment: Text.AlignBottom; bottomPadding: 5
      color: Theme.textDim; font.pixelSize: Theme.small - 0.5; font.weight: Font.Bold
    }

    component Tool: Rectangle {
      id: tl
      property string sym: ""
      property string label: ""
      property string tip: ""
      property bool flip: false
      property bool on: false
      signal clicked()
      width: sym ? 32 : lt.implicitWidth + 22; height: 30; radius: 8
      color: on ? Theme.pressed : (th.hovered ? Theme.hover : "transparent")
      border.color: label ? Theme.separator : "transparent"
      scale: tt.pressed ? 0.94 : 1
      Behavior on scale { NumberAnimation { duration: Theme.fast } }
      Sym { visible: tl.sym !== ""; anchors.centerIn: parent; name: tl.sym || "plus"; rotation: tl.flip ? 180 : 0; width: 13; height: 13; color: Theme.text }
      Txt { id: lt; visible: tl.label !== ""; anchors.centerIn: parent; text: tl.label; font.pixelSize: Theme.small + 0.5; font.weight: Font.Medium }
      HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
      TapHandler { id: tt; onTapped: tl.clicked() }
      Tip { text: tl.tip }
    }

    component Seg: Rectangle {
      id: sg
      property var options: []
      property string value
      signal picked(string v)
      width: sr.implicitWidth + 4; height: 30; radius: 9
      color: Theme.field; border.color: Theme.separator
      Row {
        id: sr
        anchors.centerIn: parent
        Repeater {
          model: sg.options
          delegate: Rectangle {
            required property var modelData
            readonly property bool on: sg.value === modelData[0]
            width: st.implicitWidth + 24; height: 26; radius: 7
            color: on ? (Theme.dark ? "#5a5a60" : "#ffffff") : (sh.hovered ? Theme.hover : "transparent")
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Txt { id: st; anchors.centerIn: parent; text: modelData[1]; font.pixelSize: Theme.small + 0.5; font.weight: parent.on ? Font.Bold : Font.Normal }
            HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sg.picked(modelData[0]) }
          }
        }
      }
    }

    // A calendar in the sidebar: its colour (a click shows or hides it), its name
    // (double-click to rename), right-click for colour and delete.
    component CalRow: Item {
      id: cr
      property var cal
      property bool fixed: false
      property string detail: ""
      signal toggled()
      signal renamed(string name)
      signal recolor()
      signal remove()
      signal pickCountry(var item)
      height: 30
      property bool renaming: !!cal && !!cal.fresh
      Rectangle { anchors.fill: parent; radius: 7; color: crh.hovered ? Theme.hover : "transparent" }
      Rectangle {
        id: dot
        x: 6; anchors.verticalCenter: parent.verticalCenter
        width: 16; height: 16; radius: 5
        color: cr.cal && cr.cal.on ? cr.cal.color : "transparent"
        border.width: 2; border.color: cr.cal ? cr.cal.color : Theme.textDim
        Sym { anchors.centerIn: parent; visible: cr.cal && cr.cal.on; name: "check"; width: 9; height: 9; color: "#ffffff"; stroke: 2.2 }
        TapHandler { onTapped: cr.toggled() }
      }
      Txt { visible: !cr.renaming; anchors { left: dot.right; leftMargin: 10; right: tag.left; rightMargin: 6; verticalCenter: parent.verticalCenter } text: cr.cal ? cr.cal.name : "" }
      TextInput {
        visible: cr.renaming
        anchors { left: dot.right; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize; clip: true
        onVisibleChanged: if (visible) { text = cr.cal.name; forceActiveFocus(); selectAll() }
        Component.onCompleted: if (visible) { text = cr.cal.name; forceActiveFocus(); selectAll() }
        Keys.onReturnPressed: focus = false
        Keys.onEscapePressed: focus = false
        onActiveFocusChanged: if (!activeFocus && cr.renaming) { if (cr.cal.fresh) delete cr.cal.fresh; cr.renaming = false; if (text.trim()) cr.renamed(text.trim()) }
      }
      Rectangle {
        id: tag
        visible: cr.detail !== ""
        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
        width: visible ? tt2.implicitWidth + 16 : 0; height: 20; radius: 6
        color: tgh.hovered ? Theme.pressed : Theme.field
        Txt { id: tt2; anchors.centerIn: parent; text: cr.detail; color: Theme.textDim; font.pixelSize: Theme.small - 1; font.weight: Font.Bold }
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

    // A month: weekday letters, its days; dots under days with events.
    component MiniMonth: Column {
      id: mm
      property int month
      property int year
      property real selected: 0
      property bool compact: false
      property bool header: true
      signal picked(real day)
      signal stepped(int n)
      signal titleClicked()
      spacing: 4
      readonly property real cell: width / 7
      readonly property real first: Cal.monthGridStart(year, month)
      Item {
        visible: mm.header
        width: parent.width; height: 26
        Txt {
          anchors.verticalCenter: parent.verticalCenter; x: 4
          text: Qt.formatDate(new Date(mm.year, mm.month, 1), mm.compact ? "MMMM" : "MMMM yyyy")
          font.weight: Font.Bold; color: mm.compact && mm.month === new Date(app.now).getMonth() && mm.year === new Date(app.now).getFullYear() ? app.tint : Theme.text
          TapHandler { onTapped: mm.titleClicked() }
          HoverHandler { cursorShape: mm.compact ? Qt.PointingHandCursor : Qt.ArrowCursor }
        }
        Row {
          visible: !mm.compact
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          Tool { sym: "chevron"; flip: true; width: 26; height: 24; onClicked: mm.stepped(-1) }
          Tool { sym: "chevron"; width: 26; height: 24; onClicked: mm.stepped(1) }
        }
      }
      Row {
        Repeater {
          model: ["M", "T", "W", "T", "F", "S", "S"]
          delegate: Txt { required property string modelData; width: mm.cell; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.textFaint; font.pixelSize: Theme.small - 1.5; font.weight: Font.Bold }
        }
      }
      Grid {
        columns: 7
        Repeater {
          model: 42
          delegate: Item {
            required property int index
            readonly property real day: Cal.addDays(mm.first, index)
            readonly property bool inMonth: new Date(day).getMonth() === mm.month
            readonly property bool today: Cal.sameDay(day, app.now)
            readonly property bool chosen: !mm.compact && Cal.sameDay(day, mm.selected)
            readonly property bool busy: !mm.compact && inMonth && app.dayOcc(day).length > 0
            width: mm.cell; height: mm.compact ? mm.cell * 0.86 : mm.cell * 0.92
            Rectangle {
              anchors.centerIn: parent
              width: Math.min(parent.width, parent.height) - 2; height: width; radius: width / 2
              color: parent.today ? app.tint : (parent.chosen ? Theme.pressed : (mh.hovered ? Theme.hover : "transparent"))
            }
            Txt {
              anchors.centerIn: parent
              text: new Date(parent.day).getDate()
              font.pixelSize: mm.compact ? Theme.small - 1 : Theme.small
              font.weight: parent.today || parent.chosen ? Font.Bold : Font.Normal
              color: parent.today ? "#ffffff" : (parent.inMonth ? Theme.text : Theme.textFaint)
              opacity: parent.inMonth || !mm.compact ? 1 : 0
            }
            Rectangle {
              visible: parent.busy && !parent.today && !mm.compact
              anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 1 }
              width: 4; height: 4; radius: 2; color: Theme.textDim
            }
            HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: mm.picked(parent.day) }
          }
        }
      }
    }

    // ---- Month
    component MonthView: Item {
      id: mv
      readonly property int y0: new Date(app.cursor).getFullYear()
      readonly property int m0: new Date(app.cursor).getMonth()
      readonly property real first: Cal.monthGridStart(y0, m0)
      readonly property int rows: 6
      readonly property real cw: (width - 24) / 7
      readonly property real chH: (height - 26 - 12) / rows
      // All of it at once (faster than asking per day): day index -> occurrences.
      readonly property var byDay: {
        const out = []
        for (let i = 0; i < 42; i++) out.push([])
        const from = first, to = Cal.addDays(first, 42)
        app.occ(from, to).forEach(o => {
          let a = Math.max(0, Math.round((Cal.startOfDay(o.start) - from) / Cal.DAY))
          let b = o.ev.allDay ? Math.min(41, Math.round((Cal.startOfDay(o.end) - from) / Cal.DAY)) : a
          if (o.ev.allDay && Cal.startOfDay(o.start) < from) a = 0
          for (let i = a; i <= b && i < 42; i++) out[i].push(o)
        })
        return out
      }
      // Dragging an event to another day.
      property var drag: null            // { o, from (day index) }
      property point dragAt
      property int over: -1
      function cellAt(p) {
        const c = Math.floor((p.x - 12) / cw), r = Math.floor((p.y - 26) / chH)
        return c >= 0 && c < 7 && r >= 0 && r < 6 ? r * 7 + c : -1
      }

      Row {
        x: 12; height: 26
        Repeater {
          model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
          delegate: Txt { required property string modelData; required property int index; width: mv.cw; height: 26; horizontalAlignment: Text.AlignRight; rightPadding: 10; text: modelData; color: index >= 5 ? Theme.textFaint : Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Bold }
        }
      }
      Grid {
        id: grid
        x: 12; y: 26
        columns: 7
        Repeater {
          model: 42
          delegate: Rectangle {
            id: cell
            required property int index
            readonly property real day: Cal.addDays(mv.first, index)
            readonly property bool inMonth: new Date(day).getMonth() === mv.m0
            readonly property bool today: Cal.sameDay(day, app.now)
            readonly property bool chosen: Cal.sameDay(day, app.selDay)
            readonly property var list: mv.byDay[index] || []
            readonly property int fits: Math.max(0, Math.floor((height - 32) / 20))
            readonly property bool weekend: index % 7 >= 5
            width: mv.cw; height: mv.chH
            color: mv.over === index ? Qt.rgba(app.tint.r, app.tint.g, app.tint.b, 0.12)
              : (chosen ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, Theme.dark ? 0.06 : 0.045)
              : (weekend ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.018) : "transparent"))
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            border.width: 0
            Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.separator }
            Rectangle { visible: index % 7 !== 0; anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.separator; opacity: 0.6 }
            // The day number, in a red circle today.
            Rectangle {
              anchors { right: parent.right; rightMargin: 6; top: parent.top; topMargin: 5 }
              width: Math.max(24, dn.implicitWidth + 12); height: 24; radius: 12
              color: cell.today ? app.tint : "transparent"
              Txt {
                id: dn
                anchors.centerIn: parent
                text: (new Date(cell.day).getDate() === 1 ? Qt.formatDate(new Date(cell.day), "MMM ") : "") + new Date(cell.day).getDate()
                font.pixelSize: Theme.fontSize; font.weight: cell.today || new Date(cell.day).getDate() === 1 ? Font.Bold : Font.Normal
                color: cell.today ? "#ffffff" : (cell.inMonth ? Theme.text : Theme.textFaint)
              }
            }
            Column {
              x: 4; y: 32; width: parent.width - 8
              spacing: 2
              Repeater {
                model: cell.list.slice(0, cell.list.length > cell.fits ? Math.max(0, cell.fits - 1) : cell.fits)
                delegate: Chip { required property var modelData; o: modelData; width: parent.width; dim: !cell.inMonth; month: mv }
              }
              Txt {
                visible: cell.list.length > cell.fits && cell.fits > 0
                x: 6; text: "+" + (cell.list.length - Math.max(0, cell.fits - 1)) + " more"
                color: Theme.textDim; font.pixelSize: Theme.small - 0.5; font.weight: Font.Medium
                TapHandler { onTapped: { app.selDay = cell.day; app.cursor = cell.day; app.dir = 0; app.view = "week" } }
              }
            }
            TapHandler {
              onTapped: { app.selDay = cell.day; app.selId = "" }
              onDoubleTapped: { app.selDay = cell.day; app.newEvent({ start: cell.day + 9 * 3600000, end: cell.day + 10 * 3600000 }) }
            }
          }
        }
      }
      // The event being dragged, under the pointer.
      Rectangle {
        visible: !!mv.drag
        x: mv.dragAt.x - 20; y: mv.dragAt.y - 10; z: 10
        width: Math.min(200, mv.cw - 8); height: 20; radius: 6
        color: mv.drag ? app.colorOf(mv.drag.o.ev) : "transparent"; opacity: 0.92
        Txt { x: 8; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 14; text: mv.drag ? mv.drag.o.ev.title : ""; color: "#ffffff"; font.pixelSize: Theme.small; font.weight: Font.Medium }
      }
    }

    // One event in a day of the month: a filled bar for all-day ones, a dot
    // with the time for the others. Drag it to another day.
    component Chip: Rectangle {
      id: ch
      property var o
      property bool dim: false
      property var month: null
      readonly property color c: app.colorOf(o.ev)
      readonly property bool chosen: app.selId === o.ev.id
      height: 18; radius: 5
      opacity: dim ? 0.5 : 1
      color: o.ev.allDay ? (chosen ? c : Qt.rgba(c.r, c.g, c.b, Theme.dark ? 0.32 : 0.2)) : (chosen ? Qt.rgba(c.r, c.g, c.b, 0.9) : (chh.hovered ? Theme.hover : "transparent"))
      Rectangle { visible: !ch.o.ev.allDay; x: 5; anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 3.5; color: ch.chosen ? "#ffffff" : ch.c }
      Txt {
        x: ch.o.ev.allDay ? 6 : 16; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - (tm.visible ? tm.width + 8 : 6)
        text: ch.o.ev.title; elide: Text.ElideRight
        font.pixelSize: Theme.small; font.weight: Font.Medium
        color: ch.chosen ? "#ffffff" : (ch.o.ev.allDay ? (Theme.dark ? Qt.lighter(ch.c, 1.35) : Qt.darker(ch.c, 1.45)) : Theme.text)
      }
      Txt {
        id: tm
        visible: !ch.o.ev.allDay && ch.width > 120
        anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
        text: app.time(ch.o.start); color: ch.chosen ? "#ffffff" : Theme.textDim; font.pixelSize: Theme.small - 1
      }
      HoverHandler { id: chh; cursorShape: Qt.PointingHandCursor }
      TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: { app.selDay = Cal.startOfDay(ch.o.start); app.selId = ch.o.ev.id } }
      DragHandler {
        target: null
        enabled: !ch.o.ev.holiday && !!ch.month
        onActiveChanged: {
          const m = ch.month
          if (active) { m.drag = { o: ch.o }; return }
          const to = m.over
          m.drag = null; m.over = -1
          if (to >= 0) {
            const days = Math.round((Cal.addDays(m.first, to) - Cal.startOfDay(ch.o.start)) / Cal.DAY)
            app.moveBy(ch.o.ev, days)
          }
        }
        onCentroidChanged: if (active) { const p = ch.mapToItem(ch.month, centroid.position.x, centroid.position.y); ch.month.dragAt = p; ch.month.over = ch.month.cellAt(p) }
      }
    }

    // ---- Week
    component WeekView: Item {
      id: wv
      readonly property real first: Cal.weekStart(app.cursor)
      readonly property real gutter: 56
      readonly property real colW: (width - gutter - 12) / 7
      readonly property real hourH: 52
      readonly property var all: app.occ(first, Cal.addDays(first, 7))
      readonly property var allDay: all.filter(o => o.ev.allDay)
      readonly property int allRows: Math.min(4, Math.max(1, ...[0, 1, 2, 3, 4, 5, 6].map(i => allDay.filter(o => Cal.startOfDay(o.start) <= Cal.addDays(first, i) && Cal.startOfDay(o.end) >= Cal.addDays(first, i)).length)))
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
      // Day names and numbers.
      Row {
        id: wh
        x: wv.gutter; height: 50
        Repeater {
          model: 7
          delegate: Item {
            required property int index
            readonly property real day: Cal.addDays(wv.first, index)
            readonly property bool today: Cal.sameDay(day, app.now)
            width: wv.colW; height: 50
            Row {
              anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
              spacing: 6
              Txt { anchors.verticalCenter: parent.verticalCenter; text: Qt.formatDate(new Date(parent.parent.day), "ddd"); color: parent.parent.today ? app.tint : Theme.textDim; font.pixelSize: Theme.small + 0.5 }
              Rectangle {
                width: Math.max(28, dnum.implicitWidth + 12); height: 28; radius: 14
                color: parent.parent.today ? app.tint : "transparent"
                Txt { id: dnum; anchors.centerIn: parent; text: new Date(parent.parent.parent.day).getDate(); font.pixelSize: 17; font.weight: parent.parent.parent.today ? Font.Bold : Font.Medium; color: parent.parent.parent.today ? "#ffffff" : Theme.text }
              }
            }
            TapHandler { onTapped: { app.selDay = parent.day; app.selId = "" } onDoubleTapped: app.newEvent({ start: parent.day, end: parent.day, allDay: true }) }
          }
        }
      }
      // All-day events across the top.
      Item {
        id: allBox
        anchors { top: wh.bottom; left: parent.left; right: parent.right }
        height: wv.allRows * 22 + 8
        Txt { width: wv.gutter - 8; horizontalAlignment: Text.AlignRight; y: 4; text: "all-day"; color: Theme.textFaint; font.pixelSize: Theme.small - 1 }
        Repeater {
          model: 7
          delegate: Column {
            required property int index
            readonly property real day: Cal.addDays(wv.first, index)
            x: wv.gutter + index * wv.colW + 2; y: 4; width: wv.colW - 4; spacing: 2
            Repeater {
              model: wv.allDay.filter(o => Cal.startOfDay(o.start) <= parent.day && Cal.startOfDay(o.end) >= parent.day).slice(0, 4)
              delegate: Chip { required property var modelData; o: modelData; width: parent.width }
            }
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
        Component.onCompleted: contentY = Math.max(0, (new Date(app.now).getHours() - 2) * wv.hourH)
        Repeater {
          model: 24
          delegate: Item {
            required property int index
            y: index * wv.hourH + 10; width: hours.width; height: wv.hourH
            Txt { visible: index > 0; width: wv.gutter - 10; horizontalAlignment: Text.AlignRight; y: -8; text: Prefs.clock24 ? String(index).padStart(2, "0") + ":00" : ((index % 12) || 12) + (index < 12 ? " AM" : " PM"); color: Theme.textFaint; font.pixelSize: Theme.small - 1 }
            Rectangle { x: wv.gutter; width: hours.width - wv.gutter - 12; height: 1; color: Theme.separator; opacity: 0.7 }
          }
        }
        Repeater {
          model: 7
          delegate: Item {
            id: dcol
            required property int index
            readonly property real day: Cal.addDays(wv.first, index)
            x: wv.gutter + index * wv.colW; y: 10; width: wv.colW; height: 24 * wv.hourH
            Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.separator; opacity: 0.6 }
            Rectangle { anchors.fill: parent; color: Cal.sameDay(dcol.day, app.selDay) ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03) : "transparent" }
            // A double-click on an empty hour: a new event there.
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
                required property var modelData
                readonly property var o: modelData.o
                readonly property color c: app.colorOf(o.ev)
                readonly property bool chosen: app.selId === o.ev.id
                readonly property real m0: (o.start - dcol.day) / 60000
                readonly property real m1: Math.min(24 * 60, (o.end - dcol.day) / 60000)
                x: 2 + modelData.lane * (dcol.width - 4) / modelData.of
                width: (dcol.width - 4) / modelData.of - 2
                y: m0 / 60 * wv.hourH + 1
                height: Math.max(20, (m1 - m0) / 60 * wv.hourH - 2)
                radius: 7
                color: chosen ? c : Qt.rgba(c.r, c.g, c.b, Theme.dark ? 0.3 : 0.18)
                border.color: Qt.rgba(c.r, c.g, c.b, 0.6)
                Rectangle { x: 0; width: 3; height: parent.height; radius: 1.5; color: parent.c }
                Column {
                  x: 9; y: 4; width: parent.width - 14
                  Txt { width: parent.width; text: o.ev.title; font.pixelSize: Theme.small; font.weight: Font.Bold; elide: Text.ElideRight; color: chosen ? "#ffffff" : (Theme.dark ? Qt.lighter(c, 1.4) : Qt.darker(c, 1.5)) }
                  Txt { visible: parent.parent.height > 36; width: parent.width; text: app.time(o.start) + (o.ev.location ? " · " + o.ev.location : ""); font.pixelSize: Theme.small - 1; elide: Text.ElideRight; color: chosen ? "#ffffff" : Theme.textDim }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: { app.selDay = dcol.day; app.selId = o.ev.id } }
              }
            }
          }
        }
        // Now: a red line across today.
        Item {
          readonly property real d0: Cal.startOfDay(app.now)
          readonly property int col: Math.round((d0 - wv.first) / Cal.DAY)
          visible: col >= 0 && col < 7
          y: 10 + (app.now - d0) / 3600000 * wv.hourH
          x: wv.gutter; width: hours.width - wv.gutter - 12; height: 2
          Rectangle { x: parent.col * wv.colW; width: wv.colW; height: 2; color: app.tint }
          Rectangle { x: parent.col * wv.colW - 4; y: -3; width: 8; height: 8; radius: 4; color: app.tint }
          Txt { x: -wv.gutter; width: wv.gutter - 10; y: -8; horizontalAlignment: Text.AlignRight; text: app.time(app.now); color: app.tint; font.pixelSize: Theme.small - 1; font.weight: Font.Bold
            Rectangle { anchors.fill: parent; anchors.margins: -2; z: -1; color: Theme.window; radius: 4 } }
        }
      }
    }

    // ---- Year
    component YearView: Flickable {
      id: yv
      readonly property int y0: new Date(app.cursor).getFullYear()
      readonly property int cols: width > 1000 ? 4 : (width > 640 ? 3 : 2)
      contentHeight: yg.implicitHeight + 40
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Grid {
        id: yg
        x: 24; y: 10
        columns: yv.cols
        columnSpacing: 28; rowSpacing: 22
        Repeater {
          model: 12
          delegate: MiniMonth {
            required property int index
            width: (yv.width - 48 - (yv.cols - 1) * 28) / yv.cols
            month: index; year: yv.y0; compact: true
            onPicked: d => { app.goTo(d); app.view = "month" }
            onTitleClicked: { app.cursor = new Date(yv.y0, index, 1).getTime(); app.dir = 0; app.view = "month" }
          }
        }
      }
    }

    // ---- the inspector
    component Inspector: Rectangle {
      id: ins
      readonly property var ev: app.sel
      readonly property bool ro: !ev || !!ev.holiday
      readonly property bool typing: ttl.activeFocus || loc.activeFocus || notes.activeFocus
      function focusTitle() { ttl.forceActiveFocus(); ttl.selectAll() }
      function askDelete() {
        const e = ev; if (!e || e.holiday) return
        if (e.repeat && e.repeat !== "none") {
          const occ = app.dayOcc(app.selDay).find(o => o.ev === e)
          pop.choose(delBtn, ["Delete Only This One", "Delete All of Them"], v => app.removeEvent(e, v.indexOf("Only") >= 0, occ ? occ.start : e.start))
        } else confirm.ask({ title: "Delete “" + e.title + "”?", message: "You can't undo this.", action: "Delete", onAccept: () => app.removeEvent(e, false, 0) })
      }
      clip: true
      color: Theme.dark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.02)
      Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 1; color: Theme.separator }
      Item {
        id: insTop
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 62
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        Tool { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } sym: "close"; tip: "Close (Esc)"; onClicked: app.selId = "" }
      }
      Flickable {
        anchors { left: parent.left; right: parent.right; top: insTop.bottom; bottom: parent.bottom }
        contentHeight: ic.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
          id: ic
          x: 20; width: Math.max(260, ins.width) - 40
          spacing: 14
          visible: !!ins.ev
          // Title, in the calendar's colour.
          RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle { Layout.preferredWidth: 4; Layout.fillHeight: true; radius: 2; color: ins.ev ? app.colorOf(ins.ev) : "transparent" }
            TextInput {
              id: ttl
              Layout.fillWidth: true
              text: ins.ev ? ins.ev.title : ""
              readOnly: ins.ro
              color: Theme.text; font.family: Theme.font; font.pixelSize: 21; font.weight: Font.Bold
              wrapMode: TextInput.Wrap
              selectByMouse: true
              onTextEdited: app.update(ins.ev, "title", text)
              Keys.onReturnPressed: focus = false
            }
          }
          Txt {
            visible: !!ins.ev && !!ins.ev.holiday
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "A public holiday in " + app.countryName(app.cc) + "."
            color: Theme.textDim
          }
          // When.
          Box {
            Layout.fillWidth: true
            Row2 {
              label: "All-day"
              visible: !ins.ro
              Switch2 { on: !!ins.ev && ins.ev.allDay; onToggled: v => { const e = ins.ev; e.allDay = v; if (v) { e.start = Cal.startOfDay(e.start); e.end = Cal.startOfDay(e.end); e.alert = -1 } else { e.start = Cal.startOfDay(e.start) + 9 * 3600000; e.end = Cal.startOfDay(e.end) + 10 * 3600000; e.alert = 10 } app.changed() } }
            }
            Row2 {
              label: ins.ev && ins.ev.allDay ? "From" : "Starts"
              DateTime { t: ins.ev ? ins.ev.start : 0; allDay: !!ins.ev && ins.ev.allDay; ro: ins.ro
                onMoved: v => { const e = ins.ev, len = e.end - e.start; e.start = v; e.end = v + len; app.changed() } }
            }
            Row2 {
              label: ins.ev && ins.ev.allDay ? "To" : "Ends"; last: true
              visible: !ins.ev || !ins.ev.holiday
              DateTime { t: ins.ev ? ins.ev.end : 0; allDay: !!ins.ev && ins.ev.allDay; ro: ins.ro; onMoved: v => app.update(ins.ev, "end", v) }
            }
          }
          Box {
            Layout.fillWidth: true
            visible: !ins.ro
            Row2 {
              label: "Calendar"
              Pill2 {
                id: calPill
                text: ins.ev ? app.calOf(ins.ev.cal).name : ""; dot: ins.ev ? app.colorOf(ins.ev) : "transparent"
                onClicked: pop.choose(calPill, app.calendars.map(c => c.name), v => app.update(ins.ev, "cal", app.calendars.find(c => c.name === v).id))
              }
            }
            Row2 {
              label: "Repeat"
              Pill2 {
                id: repPill
                readonly property var names: ({ none: "Never", daily: "Every Day", weekly: "Every Week", monthly: "Every Month", yearly: "Every Year" })
                text: ins.ev ? names[ins.ev.repeat || "none"] : ""
                onClicked: pop.choose(repPill, ["Never", "Every Day", "Every Week", "Every Month", "Every Year"], v => app.update(ins.ev, "repeat", Object.keys(names).find(k => names[k] === v)))
              }
            }
            Row2 {
              label: "Alert"; last: true
              Pill2 {
                id: alertPill
                readonly property var opts: [[-1, "None"], [0, "At the start"], [5, "5 minutes before"], [10, "10 minutes before"], [15, "15 minutes before"], [30, "30 minutes before"], [60, "1 hour before"], [120, "2 hours before"], [1440, "1 day before"], [2880, "2 days before"]]
                text: ins.ev ? ((opts.find(o => o[0] === (ins.ev.alert === undefined ? -1 : ins.ev.alert)) || [0, "None"])[1]) : ""
                onClicked: pop.choose(alertPill, opts.map(o => o[1]), v => app.update(ins.ev, "alert", opts.find(o => o[1] === v)[0]))
              }
            }
          }
          Box {
            Layout.fillWidth: true
            visible: !ins.ro
            Item {
              width: parent.width; height: 40
              Sym { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "globe"; width: 14; height: 14; color: Theme.textDim }
              TextInput {
                id: loc
                anchors { left: parent.left; leftMargin: 36; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                text: ins.ev ? (ins.ev.location || "") : ""
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize; clip: true
                onTextEdited: app.update(ins.ev, "location", text)
                Keys.onReturnPressed: focus = false
                Txt { visible: !loc.text; anchors.verticalCenter: parent.verticalCenter; text: "Add a place"; color: Theme.textFaint }
              }
            }
          }
          Box {
            Layout.fillWidth: true
            visible: !ins.ro
            Item {
              width: parent.width; height: Math.max(90, notes.contentHeight + 22)
              TextEdit {
                id: notes
                x: 12; y: 11; width: parent.width - 24
                text: ins.ev ? (ins.ev.notes || "") : ""
                color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.fontSize
                wrapMode: TextEdit.Wrap; selectByMouse: true
                onTextChanged: if (activeFocus) app.update(ins.ev, "notes", text)
                Txt { visible: !notes.text && !notes.activeFocus; text: "Notes"; color: Theme.textFaint }
              }
            }
          }
          Rectangle {
            id: delBtn
            visible: !ins.ro
            Layout.fillWidth: true; implicitHeight: 34; radius: 9
            color: dh.hovered ? Qt.rgba(1, 0.23, 0.19, 0.16) : "transparent"
            border.color: Qt.rgba(1, 0.23, 0.19, 0.35)
            Txt { anchors.centerIn: parent; text: "Delete Event"; color: Theme.red; font.weight: Font.Medium }
            HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ins.askDelete() }
          }
        }
      }
    }
    component Box: Rectangle {
      default property alias content: bc.data
      implicitHeight: bc.implicitHeight
      radius: 11
      color: Theme.field
      border.color: Theme.separator
      Column { id: bc; width: parent.width }
    }
    component Row2: Item {
      id: r2
      property string label
      property bool last: false
      default property alias content: r2c.data
      width: parent ? parent.width : 0; height: visible ? 42 : 0
      Txt { x: 12; anchors.verticalCenter: parent.verticalCenter; text: r2.label; color: Theme.textDim }
      Row { id: r2c; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } spacing: 6 }
      Rectangle { visible: !r2.last; anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 12 } height: 1; color: Theme.separator }
    }
    component Pill2: Rectangle {
      id: p2
      property string text
      property color dot: "transparent"
      signal clicked()
      width: Math.min(190, pt.implicitWidth + (dot.a > 0 ? 40 : 26)); height: 28; radius: 8
      color: ph2.hovered ? Theme.pressed : Theme.hover
      Rectangle { visible: p2.dot.a > 0; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; radius: 4.5; color: p2.dot }
      Txt { id: pt; x: p2.dot.a > 0 ? 25 : 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 12; text: p2.text; font.pixelSize: Theme.small + 0.5; elide: Text.ElideRight }
      HoverHandler { id: ph2; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: p2.clicked() }
    }
    component Switch2: Rectangle {
      id: s2
      property bool on: false
      signal toggled(bool v)
      width: 40; height: 24; radius: 12
      color: on ? Theme.green : (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      Rectangle { width: 20; height: 20; radius: 10; y: 2; x: s2.on ? 18 : 2; color: "#ffffff"; Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } } }
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
      Pill2 {
        id: datePill
        text: dt.t ? Qt.formatDate(new Date(dt.t), "ddd d MMM yyyy") : ""
        onClicked: if (!dt.ro) pop.pickDate(datePill, dt.t, d => dt.moved(d + (dt.t - Cal.startOfDay(dt.t))))
      }
      Rectangle {
        visible: !dt.allDay
        width: 64; height: 28; radius: 8
        color: tin.activeFocus ? Theme.field : Theme.hover
        border.color: tin.activeFocus ? app.tint : "transparent"
        TextInput {
          id: tin
          anchors.centerIn: parent
          width: parent.width - 12
          horizontalAlignment: TextInput.AlignHCenter
          readOnly: dt.ro
          text: dt.t ? Qt.formatTime(new Date(dt.t), "HH:mm") : ""
          color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
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
      function choose(item, list, cb) { place(item); dateMode = false; items = list; onPick = cb; open = true }
      function pickDate(item, t, cb) { place(item); dateMode = true; dateVal = t; onPick = cb; open = true }
      function close() { open = false }
      MouseArea { anchors.fill: parent; onClicked: pp.close() }
      Glass {
        x: pp.at.x; y: Math.min(pp.at.y, pp.height - height - 8)
        width: pp.dateMode ? 250 : Math.max(180, lcol.implicitWidth + 12)
        height: pp.dateMode ? dm.implicitHeight + 20 : lcol.implicitHeight + 12
        radius: 12; fill: Theme.dark ? Qt.rgba(0.16, 0.16, 0.18, 0.98) : Qt.rgba(0.99, 0.99, 1, 0.98); shadowSize: 24
        MouseArea { anchors.fill: parent }
        Column {
          id: lcol
          visible: !pp.dateMode
          x: 6; y: 6
          Repeater {
            model: pp.dateMode ? [] : pp.items
            delegate: Rectangle {
              required property string modelData
              width: Math.max(168, lt2.implicitWidth + 24); height: 30; radius: 7
              color: lh.hovered ? app.tint : "transparent"
              Txt { id: lt2; x: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: lh.hovered ? "#ffffff" : (modelData.startsWith("Delete") ? Theme.red : Theme.text) }
              HoverHandler { id: lh; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: { pp.close(); if (pp.onPick) pp.onPick(modelData) } }
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

  // Countries whose public holidays date.nager.at knows (the common ones).
  readonly property var countries: [["AT", "Austria"], ["BE", "Belgium"], ["BG", "Bulgaria"], ["BR", "Brazil"], ["CA", "Canada"], ["CH", "Switzerland"],
    ["CZ", "Czechia"], ["DE", "Germany"], ["DK", "Denmark"], ["ES", "Spain"], ["FI", "Finland"], ["FR", "France"], ["GB", "United Kingdom"],
    ["GR", "Greece"], ["HU", "Hungary"], ["IE", "Ireland"], ["IT", "Italy"], ["MD", "Moldova"], ["NL", "Netherlands"], ["NO", "Norway"],
    ["PL", "Poland"], ["PT", "Portugal"], ["RO", "Romania"], ["RS", "Serbia"], ["SE", "Sweden"], ["TR", "Türkiye"], ["UA", "Ukraine"], ["US", "United States"]]
  function countryName(c) { const x = countries.find(k => k[0] === c); return x ? x[1] : c }
}
