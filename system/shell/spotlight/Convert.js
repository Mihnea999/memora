.pragma library
// Spotlight's quick answers: maths, unit and currency conversions, number
// bases, dates. answer(query, rates) gives [{ title, sub, copy }] (most useful
// first) or []. `rates`: { base: "EUR", rates: { USD: 1.08, … } } or null; a
// currency question without rates returns [{ needRates: true }].

// ---- units: factor to the base unit of their kind ----------------------------------
const U = {}
function unit(kind, factor, names) { names.forEach(n => U[n] = { kind: kind, f: factor, name: names[0] }) }
// length (m)
unit("length", 0.001, ["mm", "millimeter", "millimeters", "millimetre", "millimetres", "milimetri", "milimetru"])
unit("length", 0.01, ["cm", "centimeter", "centimeters", "centimetre", "centimetres", "centimetri", "centimetru"])
unit("length", 0.1, ["dm", "decimeter", "decimeters", "decimetri"])
unit("length", 1, ["m", "meter", "meters", "metre", "metres", "metri", "metru"])
unit("length", 1000, ["km", "kilometer", "kilometers", "kilometre", "kilometres", "kilometri", "kilometru"])
unit("length", 0.0254, ["in", "inch", "inches", "inci", "\""])
unit("length", 0.3048, ["ft", "foot", "feet", "picioare", "'"])
unit("length", 0.9144, ["yd", "yard", "yards"])
unit("length", 1609.344, ["mi", "mile", "miles", "mila", "mile terestre"])
unit("length", 1852, ["nmi", "nautical mile", "nautical miles", "mila marina"])
// mass (kg)
unit("mass", 1e-6, ["mg", "milligram", "milligrams", "miligrame"])
unit("mass", 0.001, ["g", "gram", "grams", "gramme", "grame"])
unit("mass", 1, ["kg", "kilogram", "kilograms", "kilo", "kilos", "kilograme"])
unit("mass", 1000, ["t", "tonne", "tonnes", "ton", "tons", "tone", "tona"])
unit("mass", 0.028349523125, ["oz", "ounce", "ounces", "uncii"])
unit("mass", 0.45359237, ["lb", "lbs", "pound", "pounds", "livre"])
unit("mass", 6.35029318, ["st", "stone", "stones"])
// volume (l)
unit("volume", 0.001, ["ml", "milliliter", "milliliters", "millilitre", "mililitri"])
unit("volume", 0.01, ["cl", "centiliter", "centilitri"])
unit("volume", 0.1, ["dl", "deciliter", "decilitri"])
unit("volume", 1, ["l", "liter", "liters", "litre", "litres", "litri", "litru"])
unit("volume", 1000, ["m3", "m³", "cubic meter", "cubic meters", "metri cubi"])
unit("volume", 3.785411784, ["gal", "gallon", "gallons", "galoane"])
unit("volume", 0.946352946, ["qt", "quart", "quarts"])
unit("volume", 0.473176473, ["pt", "pint", "pints"])
unit("volume", 0.24, ["cup", "cups", "cana", "cani"])
unit("volume", 0.0295735295625, ["floz", "fl oz", "fluid ounce", "fluid ounces"])
unit("volume", 0.01478676478125, ["tbsp", "tablespoon", "tablespoons", "lingura", "linguri"])
unit("volume", 0.00492892159375, ["tsp", "teaspoon", "teaspoons", "lingurita", "lingurite"])
// area (m²)
unit("area", 1e-4, ["cm2", "cm²", "square centimeter", "square centimeters"])
unit("area", 1, ["m2", "m²", "sqm", "square meter", "square meters", "metri patrati", "mp"])
unit("area", 1e4, ["ha", "hectare", "hectares", "hectar", "hectare"])
unit("area", 1e6, ["km2", "km²", "square kilometer", "square kilometers", "kilometri patrati"])
unit("area", 0.09290304, ["ft2", "ft²", "sqft", "square foot", "square feet"])
unit("area", 4046.8564224, ["acre", "acres", "acri"])
// speed (m/s)
unit("speed", 1, ["m/s", "mps", "meters per second"])
unit("speed", 1 / 3.6, ["km/h", "kmh", "kph", "kilometers per hour", "km/ora"])
unit("speed", 0.44704, ["mph", "miles per hour"])
unit("speed", 0.514444, ["kn", "knot", "knots", "noduri"])
// time (s)
unit("time", 0.001, ["ms", "millisecond", "milliseconds", "milisecunde"])
unit("time", 1, ["s", "sec", "secs", "second", "seconds", "secunde", "secunda"])
unit("time", 60, ["min", "mins", "minute", "minutes", "minut"])
unit("time", 3600, ["h", "hr", "hrs", "hour", "hours", "ore", "ora"])
unit("time", 86400, ["d", "day", "days", "zile", "zi"])
unit("time", 604800, ["wk", "week", "weeks", "saptamani", "saptamana"])
unit("time", 2629746, ["mo", "month", "months", "luni", "luna"])
unit("time", 31556952, ["yr", "year", "years", "ani", "an"])
// data (bytes)
unit("data", 0.125, ["bit", "bits"])
unit("data", 1, ["b", "byte", "bytes", "octeti"])
unit("data", 1e3, ["kb", "kilobyte", "kilobytes"])
unit("data", 1e6, ["mb", "megabyte", "megabytes"])
unit("data", 1e9, ["gb", "gigabyte", "gigabytes"])
unit("data", 1e12, ["tb", "terabyte", "terabytes"])
unit("data", 1024, ["kib", "kibibyte"])
unit("data", 1048576, ["mib", "mebibyte"])
unit("data", 1073741824, ["gib", "gibibyte"])
unit("data", 1099511627776, ["tib", "tebibyte"])
unit("data", 125000, ["mbit", "mbps", "megabit", "megabits"])
unit("data", 125000000, ["gbit", "gbps", "gigabit", "gigabits"])
// energy (J)
unit("energy", 1, ["j", "joule", "joules"])
unit("energy", 1000, ["kj", "kilojoule", "kilojoules"])
unit("energy", 4184, ["kcal", "calorie", "calories", "calorii", "cal"])
unit("energy", 3600, ["wh", "watt hour", "watt hours"])
unit("energy", 3.6e6, ["kwh", "kilowatt hour", "kilowatt hours"])
// pressure (Pa)
unit("pressure", 1, ["pa", "pascal"])
unit("pressure", 1000, ["kpa"])
unit("pressure", 1e5, ["bar"])
unit("pressure", 6894.757, ["psi"])
unit("pressure", 101325, ["atm", "atmosphere", "atmosfere"])
// angle (rad)
unit("angle", Math.PI / 180, ["deg", "degree", "degrees", "grade", "°"])
unit("angle", 1, ["rad", "radian", "radians", "radiani"])
// temperature: handled apart
const TEMP = { c: "c", "°c": "c", celsius: "c", f: "f", "°f": "f", fahrenheit: "f", k: "k", kelvin: "k" }

// What to show when only an amount and a unit are typed ("5 km").
const COMMON = { length: ["km", "m", "mi", "ft"], mass: ["kg", "lb", "g", "oz"], volume: ["l", "ml", "gal", "cup"], area: ["m2", "ha", "ft2", "acre"],
  speed: ["km/h", "mph", "m/s"], time: ["s", "min", "h", "day"], data: ["mb", "gb", "mib", "gib"], energy: ["kcal", "kj", "kwh"],
  pressure: ["bar", "psi", "atm"], angle: ["deg", "rad"] }

const CUR = { "$": "USD", usd: "USD", dollar: "USD", dollars: "USD", dolari: "USD", dolar: "USD",
  "€": "EUR", eur: "EUR", euro: "EUR", euros: "EUR",
  "£": "GBP", gbp: "GBP", pound: "GBP", pounds: "GBP", lire: "GBP",
  lei: "RON", leu: "RON", ron: "RON", "¥": "JPY", yen: "JPY", jpy: "JPY",
  chf: "CHF", franc: "CHF", francs: "CHF", huf: "HUF", forint: "HUF", pln: "PLN", zlot: "PLN", zloty: "PLN",
  czk: "CZK", bgn: "BGN", sek: "SEK", nok: "NOK", dkk: "DKK", cad: "CAD", aud: "AUD", cny: "CNY", yuan: "CNY",
  inr: "INR", rupee: "INR", rupees: "INR", try: "TRY", lira: "TRY", mxn: "MXN", brl: "BRL", krw: "KRW", nzd: "NZD",
  sgd: "SGD", hkd: "HKD", zar: "ZAR", ils: "ILS", thb: "THB", isk: "ISK", php: "PHP", idr: "IDR", myr: "MYR", uah: "UAH", mdl: "MDL" }

function num(s) {
  s = String(s).trim().replace(/\s/g, "")
  if (/^\d{1,3}(\.\d{3})+(,\d+)?$/.test(s)) s = s.replace(/\./g, "").replace(",", ".")   // 1.234,5
  else if (/^\d+,\d+$/.test(s)) s = s.replace(",", ".")                                // 2,5
  else s = s.replace(/,/g, "")                                                            // 1,234.5
  const v = parseFloat(s)
  return isFinite(v) ? v : NaN
}

// 0.1 + 0.2 → 0.3; big and tiny numbers readable, thousands spaced.
function fmt(v) {
  if (!isFinite(v)) return String(v)
  if (v !== 0 && (Math.abs(v) >= 1e15 || Math.abs(v) < 1e-6)) return v.toExponential(6).replace(/\.?0+e/, "e")
  const r = Math.round(v * 1e10) / 1e10
  const [i, d] = String(Math.abs(r) >= 1 ? +r.toPrecision(12) : r).split(".")
  const intPart = i.replace(/\B(?=(\d{3})+(?!\d))/g, " ")
  return d ? intPart + "." + d : intPart
}
function plain(v) { return String(Math.round(v * 1e10) / 1e10) }
// Conversions: what matters, not 10 decimals (6.21371 mi, 37.78 °C, 0.0833 h).
function nice(v) { return Math.abs(v) >= 100 ? Math.round(v * 100) / 100 : Math.abs(v) >= 1 ? Math.round(v * 1e4) / 1e4 : +v.toPrecision(4) }

const SEP = /\s+(?:to|in|into|în|in\b|as|=|->|→|cat|cât)\s+|\s*(?:->|→|=)\s*/i

function unitOf(s) { s = s.trim().toLowerCase().replace(/\.$/, ""); return U[s] || U[s.replace(/s$/, "")] || null }
function tempOf(s) { return TEMP[s.trim().toLowerCase().replace(/^degrees?\s+|^grade\s+/, "")] || null }
function curOf(s) {
  s = s.trim().toLowerCase()
  if (CUR[s]) return CUR[s]
  return /^[a-z]{3}$/.test(s) && !U[s] && !U[s.replace(/s$/, "")] && !TEMP[s] ? s.toUpperCase() : null   // a code like CZK, not "gal"
}

// "10 km", "10km", "$50", "50 $", "5.5 kg"
function amount(s) {
  s = s.trim()
  let m = s.match(/^([$€£¥])\s*([\d.,\s]*\d)$/)
  if (m) return { v: num(m[2]), u: m[1] }
  m = s.match(/^(-?[\d.,]*\d)\s*(.+)$/)
  if (m) return { v: num(m[1]), u: m[2].trim() }
  return null
}

function temperature(v, from, to) {
  const c = from === "c" ? v : from === "f" ? (v - 32) * 5 / 9 : v - 273.15
  return to === "c" ? c : to === "f" ? c * 9 / 5 + 32 : c + 273.15
}
const TNAME = { c: "°C", f: "°F", k: "K" }

function convert(q, rates) {
  const parts = q.split(SEP)
  const a = amount(parts[0])
  if (!a || isNaN(a.v)) return []
  const target = parts.length > 1 ? parts.slice(1).join(" ").trim() : ""
  // temperature
  const tf = tempOf(a.u)
  if (tf) {
    const tos = target ? [tempOf(target)].filter(x => x) : ["c", "f", "k"].filter(x => x !== tf)
    return tos.map(t => { const v = Math.round(temperature(a.v, tf, t) * 100) / 100; return { title: fmt(v) + " " + TNAME[t], sub: fmt(a.v) + " " + TNAME[tf] + " =", copy: plain(v) } })
  }
  // currency
  const cf = curOf(a.u)
  const ct = target ? curOf(target) : null
  if (cf && (ct || (!U[a.u.toLowerCase()] && CUR[a.u.toLowerCase()]))) {
    if (!rates || !rates.rates) return [{ needRates: true }]
    const r = Object.assign({}, rates.rates); r[rates.base] = 1
    if (!r[cf]) return []
    const tos = ct ? [ct] : ["EUR", "USD", "RON", "GBP"].filter(x => x !== cf)
    return tos.filter(t => r[t]).map(t => {
      const v = a.v / r[cf] * r[t]
      return { title: fmt(Math.round(v * 100) / 100) + " " + t, sub: fmt(a.v) + " " + cf + " =  ·  rate of " + rates.date, copy: plain(Math.round(v * 100) / 100) }
    })
  }
  // units
  const uf = unitOf(a.u)
  if (!uf) return []
  let tos
  if (target) { const ut = unitOf(target); if (!ut || ut.kind !== uf.kind) return []; tos = [ut] }
  else tos = (COMMON[uf.kind] || []).map(n => U[n]).filter(u => u.name !== uf.name)
  return tos.map(ut => {
    const v = nice(a.v * uf.f / ut.f)
    return { title: fmt(v) + " " + ut.name, sub: fmt(a.v) + " " + uf.name + " =", copy: plain(v) }
  })
}

// ---- maths -----------------------------------------------------------------------------
const FUNCS = { sqrt: "Math.sqrt", cbrt: "Math.cbrt", sin: "Math.sin", cos: "Math.cos", tan: "Math.tan", asin: "Math.asin", acos: "Math.acos",
  atan: "Math.atan", ln: "Math.log", log: "Math.log10", log2: "Math.log2", abs: "Math.abs", round: "Math.round", floor: "Math.floor",
  ceil: "Math.ceil", exp: "Math.exp" }
function maths(q) {
  let s = q.toLowerCase().replace(/×/g, "*").replace(/÷/g, "/").replace(/(\d)\s*x\s*(?=[\d(])/g, "$1*").replace(/\^/g, "**").replace(/π/g, "pi")
  // 20% of 150 → 0.2*150; 150 + 19% → 150*1.19
  s = s.replace(/([\d.]+)\s*%\s*(?:of|din)\s*/g, "($1/100)*")
  s = s.replace(/([\d.]+)\s*([+\-])\s*([\d.]+)\s*%/g, (m, a, op, b) => `(${a}*(1${op}${b}/100))`)
  s = s.replace(/([\d.]+)\s*%/g, "($1/100)")
  if (!/\d|pi|\be\b/.test(s)) return null
  const words = s.match(/[a-z]+\d*/g) || []
  if (words.some(w => !(w in FUNCS) && w !== "pi" && w !== "e")) return null
  if (!/[+\-*/()]|\*\*/.test(s) && !words.length) return null
  if (!/^[\d\s.+\-*/%()a-z,]+$/.test(s)) return null
  s = s.replace(/\b(pi|e)\b/g, m => m === "pi" ? "Math.PI" : "Math.E")
  s = s.replace(/\b([a-z]+\d*)\s*\(/g, (m, f) => FUNCS[f] ? FUNCS[f] + "(" : m)
  s = s.replace(/(\d),(\d)/g, "$1.$2")
  try {
    const v = Function('"use strict"; return (' + s + ")")()
    return typeof v === "number" && isFinite(v) ? v : null
  } catch (e) { return null }
}

// ---- number bases ----------------------------------------------------------------------
function bases(q) {
  let m = q.trim().toLowerCase().match(/^(0x[0-9a-f]+|0b[01]+|0o[0-7]+|\d+)\s*(?:(?:to|in|în|->|=)\s*(hex|bin|binary|oct|octal|dec|decimal))?$/)
  if (!m || (!m[2] && /^\d+$/.test(m[1]))) return []
  const v = parseInt(m[1].replace(/^0[xbo]/, ""), m[1].startsWith("0x") ? 16 : m[1].startsWith("0b") ? 2 : m[1].startsWith("0o") ? 8 : 10)
  if (!isFinite(v)) return []
  const all = { hex: "0x" + v.toString(16).toUpperCase(), bin: "0b" + v.toString(2), oct: "0o" + v.toString(8), dec: String(v) }
  const want = m[2] ? [{ binary: "bin", octal: "oct", decimal: "dec" }[m[2]] || m[2]] : ["dec", "hex", "bin"].filter(k => !m[1].startsWith({ hex: "0x", bin: "0b", oct: "0o" }[k] || "@"))
  return want.map(k => ({ title: all[k], sub: m[1] + " =", copy: all[k] }))
}

// ---- dates -----------------------------------------------------------------------------
const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
const MONTHS_RO = ["ian", "feb", "mar", "apr", "mai", "iun", "iul", "aug", "sep", "oct", "noi", "dec"]
function parseDay(s, now) {
  s = s.trim().toLowerCase()
  if (/^(today|azi)$/.test(s)) return new Date(now.getFullYear(), now.getMonth(), now.getDate())
  if (/^(tomorrow|maine|mâine)$/.test(s)) return new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
  if (/^(christmas|craciun|crăciun)$/.test(s)) s = "25 dec"
  if (/^(new year|anul nou|revelion)$/.test(s)) s = "1 jan"
  let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/)
  if (m) return new Date(+m[1], +m[2] - 1, +m[3])
  m = s.match(/^(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?$/)
  if (m) return withYear(new Date(m[3] ? +(m[3].length === 2 ? "20" + m[3] : m[3]) : now.getFullYear(), +m[2] - 1, +m[1]), !m[3], now)
  m = s.match(/^(\d{1,2})\s+([a-zăâî]+)\.?(?:\s+(\d{4}))?$/) || s.match(/^([a-zăâî]+)\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?$/)
  if (m) {
    const [d, mon] = /^\d/.test(m[1]) ? [m[1], m[2]] : [m[2], m[1]]
    let mi = MONTHS.indexOf(mon.slice(0, 3)); if (mi < 0) mi = MONTHS_RO.indexOf(mon.slice(0, 3))
    if (mi < 0) return null
    return withYear(new Date(m[3] ? +m[3] : now.getFullYear(), mi, +d), !m[3], now)
  }
  return null
}
function withYear(d, guess, now) {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  if (guess && d < today) d.setFullYear(d.getFullYear() + 1)
  return d
}
function dates(q, now) {
  const l = q.trim().toLowerCase()
  let m = l.match(/^(?:days?\s+(?:until|till|to)|cate zile pana la|câte zile până la|zile pana la|zile până la)\s+(.+)$/)
  if (m) {
    const d = parseDay(m[1], now)
    if (!d) return []
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const n = Math.round((d - today) / 86400000)
    return [{ title: n + (Math.abs(n) === 1 ? " day" : " days"), sub: "until " + d.toDateString(), copy: String(n) }]
  }
  m = l.match(/^(\d+)\s*(days?|weeks?|months?|years?|zile|saptamani|săptămâni|luni|ani)\s+(from|after|before|ago|de azi|in urma|în urmă)(?:\s+(today|now|azi))?$/)
  if (m) {
    const n = +m[1], back = /before|ago|urma|urmă/.test(m[3])
    const d = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const k = m[2]
    if (/^(day|zile)/.test(k)) d.setDate(d.getDate() + (back ? -n : n))
    else if (/^(week|sapt|săpt)/.test(k)) d.setDate(d.getDate() + (back ? -7 * n : 7 * n))
    else if (/^(month|luni)/.test(k)) d.setMonth(d.getMonth() + (back ? -n : n))
    else d.setFullYear(d.getFullYear() + (back ? -n : n))
    return [{ title: d.toDateString(), sub: q.trim(), copy: d.toISOString().slice(0, 10) }]
  }
  return []
}

// ---- all of it -------------------------------------------------------------------------
function answer(q, rates, now) {
  q = (q || "").trim()
  if (!q || q.length > 120) return []
  now = now || new Date()
  let out = dates(q, now)
  if (out.length) return out
  out = bases(q)
  if (out.length) return out
  out = convert(q, rates)
  if (out.length) return out
  const v = maths(q)
  if (v !== null && !/^-?[\d.,\s]+$/.test(q)) return [{ title: fmt(v), sub: q + " =", copy: plain(v) }]
  return []
}

// "time in tokyo" → the city asked about, else "".
function timeQuery(q) {
  const m = (q || "").trim().toLowerCase().match(/^(?:time|ora|ceasul)\s+(?:in|în|la)\s+(.+)$/)
  return m ? m[1].trim() : ""
}
