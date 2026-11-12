pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../ui/glyphs.js" as Glyphs

// Folder colours and engraved symbols, as on a Mac: any folder can take a colour
// and a symbol pressed into its front. Kept in ~/.config/memora/folders.json
// (path -> { color, symbol }), which the shell (desktop) and Files both watch.
Singleton {
  id: f
  property var looks: ({})

  // Each colour: back panel (top, bottom), front panel (top, bottom), the ink
  // of the engraved symbol. Blue is Memora's own folder.
  readonly property var tints: ({
    blue:     ["#64b2f5", "#3d8fe6", "#9fd3ff", "#6db8fb", "#2f7fd6"],
    red:      ["#f4807a", "#e2453f", "#ffb0ab", "#f97d75", "#cf3832"],
    orange:   ["#fbae60", "#f08a2b", "#ffd29c", "#ffae5f", "#de7618"],
    yellow:   ["#f8d250", "#ebb714", "#ffe99a", "#fdd75f", "#c99a05"],
    green:    ["#72d481", "#3cb453", "#abecb4", "#76db88", "#2e9d45"],
    mint:     ["#63d6c7", "#2dbba8", "#a2f0e4", "#66dccb", "#1f9f8d"],
    cyan:     ["#5cc8e9", "#28a6d4", "#a0e4f8", "#62cff1", "#1a8fbd"],
    indigo:   ["#8287ee", "#5a5fdc", "#b5b8ff", "#8b90f8", "#4a4fc8"],
    purple:   ["#c47fe9", "#a04ed6", "#e3b6ff", "#c98cf6", "#8b3cc0"],
    pink:     ["#f57fa9", "#e44884", "#ffb1cc", "#fb83ac", "#cc3a72"],
    brown:    ["#c79f7a", "#a5774e", "#e5c8aa", "#cba27b", "#8d6440"],
    graphite: ["#a6aab2", "#7c818a", "#d4d7dd", "#b0b4bc", "#686d76"]
  })
  readonly property var colorNames: ["blue", "red", "orange", "yellow", "green", "mint", "cyan", "indigo", "purple", "pink", "brown", "graphite"]
  readonly property var groups: Glyphs.groups
  // A colour to show for a tint in a swatch (the front of the folder).
  function swatch(name) { return (tints[name] || tints.blue)[3] }

  // Symbols whose name or words contain the text typed.
  function search(text) {
    const t = String(text || "").trim().toLowerCase()
    const all = [].concat.apply([], Glyphs.groups.map(g => g.symbols))
    if (!t) return all
    return all.filter(n => n.indexOf(t) >= 0 || (Glyphs.words[n] || "").indexOf(t) >= 0)
  }
  function glyph(name) { return Glyphs.paths[name] || "" }

  // The folder as SVG: Memora's folder (tools/icons.py place()) in the colour,
  // with the symbol engraved: a darker copy pressed in, lit from below.
  function svg(color, symbol) {
    const t = tints[color] || tints.blue
    const d = Glyphs.paths[symbol] || ""
    const lg = (id, a, b) => '<linearGradient id="' + id + '" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + a + '"/><stop offset="1" stop-color="' + b + '"/></linearGradient>'
    let g = ""
    if (d) {
      g = '<g transform="translate(372 445) scale(1.094)">' +
        '<path d="' + d + '" fill="#ffffff" fill-opacity="0.5" transform="translate(0 5)"/>' +
        '<path d="' + d + '" fill="' + t[4] + '" fill-opacity="0.78"/>' +
        '<path d="' + d + '" fill="#000000" fill-opacity="0.07" transform="translate(0 -2)"/>' +
        '</g>'
    }
    return '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><defs>' +
      lg("b", t[0], t[1]) + lg("f", t[2], t[3]) + '</defs>' +
      '<path d="M110 250 q0 -46 46 -46 h232 q30 0 50 24 l42 50 h388 q46 0 46 46 v460 q0 46 -46 46 h-712 q-46 0 -46 -46 Z" fill="url(#b)"/>' +
      '<path d="M110 370 q0 -40 40 -40 h724 q40 0 40 40 v420 q0 46 -46 46 h-712 q-46 0 -46 -46 Z" fill="url(#f)"/>' +
      '<path d="M150 336 h724" stroke="#ffffff" stroke-opacity="0.55" stroke-width="6"/>' + g + '</svg>'
  }
  function url(color, symbol) { return "data:image/svg+xml;utf8," + encodeURIComponent(svg(color, symbol)) }

  // The picture for this folder when it has a look of its own, else "".
  function lookOf(path) { return looks[String(path).replace(/\/+$/, "")] || null }
  function iconUrl(path) { const l = lookOf(path); return l ? url(l.color, l.symbol) : "" }

  // ---- icons for files and folders (Files and the desktop) ---------------------
  readonly property string home: Quickshell.env("HOME")
  readonly property var kinds: ({
    png: "image", jpg: "image", jpeg: "image", webp: "image", gif: "image", bmp: "image", svg: "image", heic: "image",
    mp4: "video", mkv: "video", webm: "video", mov: "video", avi: "video",
    mp3: "audio", flac: "audio", ogg: "audio", wav: "audio", m4a: "audio", opus: "audio",
    pdf: "pdf", txt: "text", md: "text", log: "text", json: "code", js: "code", ts: "code", py: "code", sh: "code", rs: "code", go: "code", c: "code", cpp: "code", h: "code", qml: "code", lua: "code", html: "code", css: "code",
    zip: "archive", tar: "archive", gz: "archive", xz: "archive", zst: "archive", "7z": "archive", rar: "archive", tgz: "archive", bz2: "archive",
    tbz2: "archive", txz: "archive", tzst: "archive", lz: "archive", lz4: "archive", lzma: "archive", cab: "archive", arj: "archive", lzh: "archive", cpio: "archive", "001": "archive",
    iso: "disc", img: "disc", deb: "package", AppImage: "package", doc: "document", docx: "document", odt: "document",
    xls: "sheet", xlsx: "sheet", ods: "sheet", ppt: "slides", pptx: "slides", odp: "slides"
  })
  function kindOf(name, isDir) {
    if (isDir) return "folder"
    const ext = name.indexOf(".") > 0 ? name.split(".").pop() : ""
    return kinds[ext] || kinds[ext.toLowerCase()] || "file"
  }
  function iconFor(p, name, isDir) {
    if (isDir) {
      const own = iconUrl(p)
      if (own) return own
      const special = { Desktop: "user-desktop", Documents: "folder-documents", Downloads: "folder-download", Music: "folder-music",
        Pictures: "folder-pictures", Videos: "folder-videos", Projects: "folder-projects", Public: "folder-publicshare", Templates: "folder-templates" }
      const parent = p.substring(0, p.lastIndexOf("/"))
      return Quickshell.iconPath(parent === home && special[name] ? special[name] : "folder")
    }
    const k = kindOf(name, false)
    const map = { video: "video-x-generic", audio: "audio-x-generic", pdf: "application-pdf", text: "text-x-generic", code: "text-x-script",
      archive: "package-x-generic", disc: "media-optical", package: "package-x-generic", document: "x-office-document", sheet: "x-office-spreadsheet",
      slides: "x-office-presentation", file: "text-x-generic" }
    return Quickshell.iconPath(map[k] || "text-x-generic", "text-x-generic")
  }

  function write(l) { looks = l; file.setText(JSON.stringify(l, null, 1) + "\n") }
  function set(path, color, symbol) {
    const p = String(path).replace(/\/+$/, ""), l = Object.assign({}, looks)
    if ((!color || color === "blue") && !symbol) delete l[p]
    else l[p] = { color: color || "blue", symbol: symbol || "" }
    write(l)
  }
  // A folder renamed or moved keeps its look (also what is inside it).
  function moved(from, to) {
    const a = String(from).replace(/\/+$/, ""), b = String(to).replace(/\/+$/, "")
    let changed = false
    const l = {}
    Object.keys(looks).forEach(k => {
      if (k === a || k.startsWith(a + "/")) { l[b + k.substring(a.length)] = looks[k]; changed = true }
      else l[k] = looks[k]
    })
    if (changed) write(l)
  }

  property FileView file: FileView {
    path: Quickshell.env("HOME") + "/.config/memora/folders.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { const j = JSON.parse(text()); f.looks = j && typeof j === "object" ? j : {} } catch (e) {} }
  }
}
