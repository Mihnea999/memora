pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "cal.js" as Cal

// The Calendar's data for the desktop (the month next to the clock): your events
// and your country's public holidays, read from the same file and cache as the
// Calendar app, so a change in one shows in the other. Choosing whose holidays
// (or hiding them) here writes it to the file, and the app follows.
Singleton {
  id: cd
  readonly property string store: Quickshell.env("HOME") + "/.local/share/memora/calendar.json"
  readonly property color holidayColor: "#ff3b30"

  property var calendars: [{ id: "personal", color: "#3d8bff", on: true }, { id: "work", color: "#ff9f0a", on: true }, { id: "family", color: "#30d158", on: true }]
  property var events: []
  property string country: ""            // two letters; "" = from the time zone
  property bool showHolidays: true
  property string raw: ""
  property bool loaded: false            // nothing is written before the file is read
  property var pending: null             // changes asked for before that

  FileView {
    id: file
    path: cd.store
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        const j = JSON.parse(text())
        cd.raw = text()
        if (j.calendars && j.calendars.length) cd.calendars = j.calendars
        cd.events = j.events || []
        cd.country = j.country || ""
        cd.showHolidays = j.showHolidays !== false
        cd.loaded = true
      } catch (e) {
        // Being written right now (or damaged): never write over it from here.
        return
      }
      cd.flush()
    }
    onLoadFailed: err => { if (err === FileViewError.FileNotFound) { cd.raw = ""; cd.loaded = true; cd.flush() } }
  }

  // Whose holidays: yours, or the time zone's country (the language's, else US).
  property string autoCountry: ""
  readonly property string cc: (country || autoCountry || "US").toUpperCase()
  Process {
    running: true
    command: ["bash", "-c", "tz=$(timedatectl show -p Timezone --value 2>/dev/null || readlink /etc/localtime | sed 's|.*/zoneinfo/||'); awk -v tz=\"$tz\" '$3 == tz { split($1, c, \",\"); print c[1]; exit }' /usr/share/zoneinfo/zone1970.tab 2>/dev/null | grep . || { l=\"${LC_TIME:-${LANG:-}}\"; l=${l%%.*}; [ \"${l#*_}\" != \"$l\" ] && echo \"${l#*_}\"; }"]
    stdout: StdioCollector { onStreamFinished: cd.autoCountry = (text.trim().split("\n")[0] || "US").slice(0, 2).toUpperCase() }
  }

  // Holidays by year, from date.nager.at (the cache the app keeps too), or built in.
  property var years: ({})                // "RO-2026" -> [{ date, name }]
  property var asked: ({})
  onCcChanged: { asked = ({}); years = ({}) }
  function want(y) {
    const key = cc + "-" + y
    if (asked[key] || (!autoCountry && !country)) return
    asked[key] = true
    const p = fetcher.createObject(cd, { key: key, year: y, code: cc })
    p.running = true
  }
  Component {
    id: fetcher
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
          const y = Object.assign({}, cd.years); y[key] = list; cd.years = y
        }
      }
    }
  }

  // What is on a day: the holidays' names and the events (title, colour).
  function holidaysOn(t) {
    if (!showHolidays) return []
    const y = new Date(t).getFullYear()
    want(y)
    const list = years[cc + "-" + y] || []
    return list.filter(h => Cal.sameDay(h.date, t)).map(h => h.name)
  }
  readonly property var shown: events.filter(e => { const c = calendars.find(x => x.id === e.cal); return !c || c.on !== false })
  function colorOf(ev) { const c = calendars.find(x => x.id === ev.cal) || calendars[0]; return c ? c.color : "#3d8bff" }
  function eventsOn(t) { return Cal.onDay(shown, t).map(o => ({ title: o.ev.title, color: colorOf(o.ev), allDay: !!o.ev.allDay, start: o.start })) }

  // Change whose holidays, or hide them: written to the file the app reads.
  function setCountry(code) { country = code; write({ country: code }) }
  function setShowHolidays(on) { showHolidays = on; write({ showHolidays: on }) }
  function write(patch) {
    pending = Object.assign(pending || {}, patch)
    if (loaded) flush()
  }
  function flush() {
    if (!pending) return
    let j = {}
    try { j = JSON.parse(raw || "{}") } catch (e) { return }
    if (!j.version) j.version = 1
    if (!j.events) j.events = []
    Object.assign(j, pending)
    if (pending.country !== undefined) country = pending.country
    if (pending.showHolidays !== undefined) showHolidays = pending.showHolidays
    pending = null
    raw = JSON.stringify(j, null, 1)
    writeLater.restart()
  }
  // One write for changes made together, the way the app writes it (so each
  // sees the other's at once); the folder made first, for the very first one.
  Timer { id: writeLater; interval: 60; onTriggered: if (!mkdir.running) mkdir.running = true }
  Process {
    id: mkdir
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/share/memora"]
    onExited: file.setText(cd.raw)
  }

  // Countries whose public holidays date.nager.at knows (the common ones).
  readonly property var countries: [["AT", "Austria"], ["BE", "Belgium"], ["BG", "Bulgaria"], ["BR", "Brazil"], ["CA", "Canada"], ["CH", "Switzerland"],
    ["CZ", "Czechia"], ["DE", "Germany"], ["DK", "Denmark"], ["ES", "Spain"], ["FI", "Finland"], ["FR", "France"], ["GB", "United Kingdom"],
    ["GR", "Greece"], ["HU", "Hungary"], ["IE", "Ireland"], ["IT", "Italy"], ["MD", "Moldova"], ["NL", "Netherlands"], ["NO", "Norway"],
    ["PL", "Poland"], ["PT", "Portugal"], ["RO", "Romania"], ["RS", "Serbia"], ["SE", "Sweden"], ["TR", "Türkiye"], ["UA", "Ukraine"], ["US", "United States"]]
  function countryName(c) { const x = countries.find(k => k[0] === c); return x ? x[1] : c }
}
