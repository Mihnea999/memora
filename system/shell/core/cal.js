// Calendar logic shared by the Calendar app (calendar.qml) and the desktop's
// reminders (calendar/Alerts.qml): repeating events, holidays, quick entry.
// Events are { id, title, cal, start, end (ms), allDay, location, notes,
// repeat: none|daily|weekly|monthly|yearly, until (ms, 0 = for ever),
// alert: minutes before (-1 = none), skip: [occurrence starts removed] }.
.pragma library

var DAY = 86400000

function startOfDay(t) { var d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime() }
function addDays(t, n) { var d = new Date(t); d.setDate(d.getDate() + n); return d.getTime() }
function addMonths(t, n) {
  var d = new Date(t), day = d.getDate()
  d.setDate(1); d.setMonth(d.getMonth() + n)
  // 31 January + 1 month: the last day of February, not 3 March.
  var last = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate()
  d.setDate(Math.min(day, last))
  return d.getTime()
}
function sameDay(a, b) { return startOfDay(a) === startOfDay(b) }
// Weeks start on Monday.
function weekStart(t) { var d = new Date(startOfDay(t)); var wd = (d.getDay() + 6) % 7; return addDays(d.getTime(), -wd) }
function monthGridStart(y, m) { return weekStart(new Date(y, m, 1).getTime()) }

// The next occurrence start after `t` for a repeat rule.
function step(t, rule, n) {
  if (rule === "daily") return addDays(t, n)
  if (rule === "weekly") return addDays(t, 7 * n)
  if (rule === "monthly") return addMonths(t, n)
  if (rule === "yearly") return addMonths(t, 12 * n)
  return t
}

// Every occurrence of the events touching [from, to): [{ ev, start, end }].
function occurrences(events, from, to) {
  var out = []
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    var len = Math.max(0, e.end - e.start)
    var skip = e.skip || []
    if (!e.repeat || e.repeat === "none") {
      if (e.start < to && e.end + (e.allDay ? DAY : 0) > from) out.push({ ev: e, start: e.start, end: e.end })
      continue
    }
    // Jump close to the range, then walk.
    var n = 0
    if (e.repeat === "daily") n = Math.max(0, Math.floor((from - e.start - len) / DAY) - 1)
    else if (e.repeat === "weekly") n = Math.max(0, Math.floor((from - e.start - len) / (7 * DAY)) - 1)
    else if (e.repeat === "monthly") n = Math.max(0, Math.floor((from - e.start - len) / (31 * DAY)) - 1)
    else if (e.repeat === "yearly") n = Math.max(0, Math.floor((from - e.start - len) / (366 * DAY)) - 1)
    for (var guard = 0; guard < 2000; guard++, n++) {
      var s = step(e.start, e.repeat, n)
      if (s >= to || (e.until && s > e.until)) break
      var en = s + len
      if (en + (e.allDay ? DAY : 0) > from && skip.indexOf(s) < 0) out.push({ ev: e, start: s, end: en })
    }
  }
  out.sort(function (a, b) { return (b.ev.allDay - a.ev.allDay) || (a.start - b.start) || (a.ev.title < b.ev.title ? -1 : 1) })
  return out
}
// Occurrences on one day.
function onDay(events, day) {
  var s = startOfDay(day)
  return occurrences(events, s, addDays(s, 1)).filter(function (o) {
    return o.ev.allDay ? (startOfDay(o.start) <= s && startOfDay(o.end) >= s) : true
  })
}

// ---- holidays ---------------------------------------------------------------
// Easter Sunday: Western (Gregorian) and Orthodox (Julian, given in Gregorian).
function easter(y) {
  var a = y % 19, b = Math.floor(y / 100), c = y % 100, d = Math.floor(b / 4), e = b % 4
  var f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30
  var i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451)
  var month = Math.floor((h + l - 7 * m + 114) / 31), day = ((h + l - 7 * m + 114) % 31) + 1
  return new Date(y, month - 1, day).getTime()
}
function orthodoxEaster(y) {
  var a = y % 4, b = y % 7, c = y % 19, d = (19 * c + 15) % 30, e = (2 * a + 4 * b - d + 34) % 7
  var month = Math.floor((d + e + 114) / 31), day = ((d + e + 114) % 31) + 1
  // Julian to Gregorian: 13 days in 1900–2099.
  return addDays(new Date(y, month - 1, day).getTime(), 13)
}
// Built in for when there's no internet: [{ date (ms), name }].
function builtinHolidays(country, y) {
  var d = function (m, day) { return new Date(y, m - 1, day).getTime() }
  var list = []
  if (country === "RO") {
    var oe = orthodoxEaster(y)
    list = [[d(1, 1), "Anul Nou"], [d(1, 2), "Anul Nou"], [d(1, 6), "Boboteaza"], [d(1, 7), "Sfântul Ioan"],
      [d(1, 24), "Ziua Unirii Principatelor Române"], [addDays(oe, -2), "Vinerea Mare"], [oe, "Paștele"], [addDays(oe, 1), "A doua zi de Paște"],
      [d(5, 1), "Ziua Muncii"], [d(6, 1), "Ziua Copilului"], [addDays(oe, 49), "Rusaliile"], [addDays(oe, 50), "A doua zi de Rusalii"],
      [d(8, 15), "Adormirea Maicii Domnului"], [d(11, 30), "Sfântul Andrei"], [d(12, 1), "Ziua Națională a României"],
      [d(12, 25), "Crăciunul"], [d(12, 26), "A doua zi de Crăciun"]]
  } else if (country === "US") {
    var nth = function (m, wd, n) { var t = new Date(y, m - 1, 1); var add = (wd - t.getDay() + 7) % 7 + 7 * (n - 1); return d(m, 1 + add) }
    var last = function (m, wd) { var t = new Date(y, m, 0); return d(m, t.getDate() - ((t.getDay() - wd + 7) % 7)) }
    list = [[d(1, 1), "New Year's Day"], [nth(1, 1, 3), "Martin Luther King Jr. Day"], [nth(2, 1, 3), "Presidents' Day"],
      [last(5, 1), "Memorial Day"], [d(6, 19), "Juneteenth"], [d(7, 4), "Independence Day"], [nth(9, 1, 1), "Labor Day"],
      [nth(10, 1, 2), "Columbus Day"], [d(11, 11), "Veterans Day"], [nth(11, 4, 4), "Thanksgiving"], [d(12, 25), "Christmas Day"]]
  } else {
    var we = easter(y)
    list = [[d(1, 1), "New Year's Day"], [addDays(we, -2), "Good Friday"], [we, "Easter Sunday"], [addDays(we, 1), "Easter Monday"],
      [d(5, 1), "Labour Day"], [d(12, 25), "Christmas Day"], [d(12, 26), "Boxing Day"]]
  }
  return list.map(function (h) { return { date: h[0], name: h[1] } })
}
// nager.at's answer to holidays: [{ date (ms), name }] (in the country's language).
function parseNager(text) {
  var j = JSON.parse(text), out = []
  for (var i = 0; i < j.length; i++) {
    var p = (j[i].date || "").split("-")
    if (p.length === 3 && (!j[i].types || j[i].types.indexOf("Public") >= 0))
      out.push({ date: new Date(+p[0], +p[1] - 1, +p[2]).getTime(), name: j[i].localName || j[i].name })
  }
  return out
}

// ---- quick entry ------------------------------------------------------------
// "Lunch with Ana tomorrow at 13", "Dentist fri 9:30", "Trip 12 dec",
// "Mâine la 18 sală". Gives { title, start, end, allDay }.
var WEEKDAYS = [["sun", "sunday", "dum", "duminica", "duminică"], ["mon", "monday", "lun", "luni"], ["tue", "tues", "tuesday", "mar", "marti", "marți"],
  ["wed", "wednesday", "mie", "miercuri"], ["thu", "thur", "thurs", "thursday", "joi"], ["fri", "friday", "vin", "vineri"], ["sat", "saturday", "sam", "sambata", "sâmbătă"]]
var MONTHS = [["jan", "january", "ian", "ianuarie"], ["feb", "february", "februarie"], ["mar", "march", "martie"], ["apr", "april", "aprilie"],
  ["may", "mai"], ["jun", "june", "iun", "iunie"], ["jul", "july", "iul", "iulie"], ["aug", "august"], ["sep", "sept", "september", "septembrie"],
  ["oct", "october", "octombrie"], ["nov", "november", "noiembrie"], ["dec", "december", "decembrie"]]
function quick(text, base) {
  var words = text.trim().split(/\s+/), keep = [], day = null, hour = -1, min = 0
  var today = startOfDay(base || Date.now())
  for (var i = 0; i < words.length; i++) {
    var w = words[i], lw = w.toLowerCase().replace(/[,.]$/, "")
    var m
    if (lw === "today" || lw === "azi" || lw === "astazi" || lw === "astăzi") { day = today; continue }
    if (lw === "tomorrow" || lw === "maine" || lw === "mâine") { day = addDays(today, 1); continue }
    if (lw === "at" || lw === "la" || lw === "on" || lw === "pe" || lw === "ora") continue
    var wd = -1
    for (var k = 0; k < 7; k++) if (WEEKDAYS[k].indexOf(lw) >= 0) wd = k
    if (wd >= 0) { var diff = (wd - new Date(today).getDay() + 7) % 7; day = addDays(today, diff === 0 ? 7 : diff); continue }
    if ((m = lw.match(/^(\d{1,2}):(\d{2})$/))) { hour = +m[1]; min = +m[2]; continue }
    if ((m = lw.match(/^(\d{1,2})(?::(\d{2}))?(am|pm)$/))) { hour = (+m[1] % 12) + (m[3] === "pm" ? 12 : 0); min = +(m[2] || 0); continue }
    if ((m = lw.match(/^(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?$/))) {
      var yy = m[3] ? (+m[3] < 100 ? 2000 + +m[3] : +m[3]) : new Date(today).getFullYear()
      day = new Date(yy, +m[2] - 1, +m[1]).getTime(); if (!m[3] && day < today) day = new Date(yy + 1, +m[2] - 1, +m[1]).getTime(); continue
    }
    if (/^\d{1,2}$/.test(lw) && i + 1 < words.length) {
      var mo = -1, nw = words[i + 1].toLowerCase().replace(/[,.]$/, "")
      for (var q = 0; q < 12; q++) if (MONTHS[q].indexOf(nw) >= 0) mo = q
      if (mo >= 0) {
        var y0 = new Date(today).getFullYear()
        day = new Date(y0, mo, +lw).getTime(); if (day < today) day = new Date(y0 + 1, mo, +lw).getTime()
        i++; continue
      }
      // "at 13" / "la 18": a bare number after at/la is the hour.
      var prev = i > 0 ? words[i - 1].toLowerCase() : ""
      if ((prev === "at" || prev === "la" || prev === "ora") && +lw < 24) { hour = +lw; continue }
    }
    if (/^\d{1,2}$/.test(lw) && i > 0 && ["at", "la", "ora"].indexOf(words[i - 1].toLowerCase()) >= 0 && +lw < 24) { hour = +lw; continue }
    keep.push(w)
  }
  var title = keep.join(" ").trim() || "New Event"
  var d0 = day === null ? today : day
  if (hour < 0) return { title: title, start: d0, end: d0, allDay: true }
  var start = d0 + hour * 3600000 + min * 60000
  if (day === null && start < Date.now()) start = addDays(start, 1)
  return { title: title, start: start, end: start + 3600000, allDay: false }
}
