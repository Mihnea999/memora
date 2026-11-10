import QtQuick
import Quickshell
import Quickshell.Io
import "../core/cal.js" as Cal

// Calendar's reminders, from the desktop (so they come with Calendar closed):
// a notification at each event's alert time ("10 minutes before"), with
// Calendar a click away. Reads ~/.local/share/memora/calendar.json.
Scope {
  id: rm
  property var events: []
  FileView {
    path: Quickshell.env("HOME") + "/.local/share/memora/calendar.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { const j = JSON.parse(text()); const on = (j.calendars || []).filter(c => c.on !== false).map(c => c.id); rm.events = (j.events || []).filter(e => on.indexOf(e.cal) >= 0 && e.alert !== undefined && e.alert >= 0) } catch (e) {} }
  }
  // Each reminder once: event id + occurrence start.
  property var told: ({})
  property real last: Date.now() - 60000
  Timer {
    interval: 20000; running: rm.events.length > 0; repeat: true; triggeredOnStart: true
    onTriggered: {
      const now = Date.now(), from = rm.last
      rm.last = now
      // Look a little past the longest alert (two days).
      Cal.occurrences(rm.events, from - 1, now + 2 * Cal.DAY + 60000).forEach(o => {
        const at = (o.ev.allDay ? Cal.startOfDay(o.start) + 9 * 3600000 : o.start) - o.ev.alert * 60000
        const key = o.ev.id + "@" + o.start
        if (at > from && at <= now && !rm.told[key]) {
          rm.told[key] = true
          const when = o.ev.allDay ? "Today" : (o.ev.alert === 0 ? "Now" : "At " + Qt.formatTime(new Date(o.start), "HH:mm") + " · in " + rm.inWords(o.start - now))
          Quickshell.execDetached(["bash", "-c", "a=$(notify-send -a Calendar -i memora-calendar -A open=Open \"$1\" \"$2\"); [ \"$a\" = open ] && memora-app calendar",
            "_", o.ev.title || "Event", when + (o.ev.location ? " · " + o.ev.location : "")])
        }
      })
    }
  }
  function inWords(ms) {
    const m = Math.max(0, Math.round(ms / 60000))
    if (m < 60) return m + (m === 1 ? " minute" : " minutes")
    const h = Math.round(m / 60)
    if (h < 24) return h + (h === 1 ? " hour" : " hours")
    const d = Math.round(h / 24)
    return d + (d === 1 ? " day" : " days")
  }
}
