import QtQuick
import Quickshell

// Memora AI's look at a desktop widget, without the desktop: the widget is
// drawn off screen in its card, given a few seconds to fetch its data, then
// described in words (every text, where it is, what overlaps, what spills out
// of the card or is cut off, pictures that didn't load) and saved as a picture.
// Run by agent.py (widget tool) with QT_QPA_PLATFORM=offscreen and
//   W=widget.qml SIZE=small|medium|large DARK=1|0 ACCENT=#rrggbb OUT=picture.png WAIT=ms
// Lines starting with "@" are the report.
ShellRoot {
  id: r
  readonly property bool medium: Quickshell.env("SIZE") === "medium" || Quickshell.env("SIZE") === "large"
  readonly property bool tall: Quickshell.env("SIZE") === "large"
  readonly property bool dark: Quickshell.env("DARK") !== "0"
  readonly property real cw: medium ? 320 : 136
  readonly property real ch: tall ? 320 : 136
  readonly property var memora: ({
    dark: dark,
    text: dark ? "#f5f5f7" : "#1c1c1e",
    dim: dark ? Qt.rgba(0.96, 0.96, 0.97, 0.58) : Qt.rgba(0.11, 0.11, 0.12, 0.55),
    accent: Quickshell.env("ACCENT") || "#0a84ff",
    font: "Inter", small: 11.5, large: 15, medium: medium, tall: tall, width: cw, height: ch
  })

  FloatingWindow {
    implicitWidth: r.cw + 32
    implicitHeight: r.ch + 32
    color: r.dark ? "#3a3f4b" : "#c9ced8"
    Rectangle {
      id: card
      anchors.fill: parent
      radius: 22
      color: r.dark ? Qt.rgba(0.09, 0.09, 0.11, 0.55) : Qt.rgba(0.98, 0.98, 0.99, 0.6)
      Loader {
        id: ld
        x: 16; y: 16; width: r.cw; height: r.ch
        source: "file://" + Quickshell.env("W")
        onLoaded: if (item && "memora" in item) item.memora = r.memora
        onStatusChanged: if (status === Loader.Error) { console.log("@error The widget did not load."); Qt.quit() }
      }
    }
    Timer { interval: Number(Quickshell.env("WAIT") || 6000); running: true; onTriggered: r.report() }
  }

  function round(v) { return Math.round(v) }
  // The painted box of a Text, in the card's content coordinates.
  function textBox(t) {
    const p = t.mapToItem(ld, 0, 0)
    const pw = Math.min(t.paintedWidth, t.width > 0 ? t.width : t.paintedWidth)
    const ph = Math.min(t.paintedHeight, t.height > 0 ? t.height : t.paintedHeight)
    let x = p.x, y = p.y
    if (t.horizontalAlignment === Text.AlignRight) x += t.width - pw
    else if (t.horizontalAlignment === Text.AlignHCenter) x += (t.width - pw) / 2
    if (t.verticalAlignment === Text.AlignBottom) y += t.height - ph
    else if (t.verticalAlignment === Text.AlignVCenter) y += (t.height - ph) / 2
    return { x: x, y: y, w: pw, h: ph }
  }
  function shown(it) {
    for (let p = it; p && p !== ld; p = p.parent) if (!p.visible || p.opacity < 0.05) return false
    return true
  }
  function walk(it, out) {
    if (!it) return
    out.push(it)
    for (let i = 0; i < it.children.length; i++) walk(it.children[i], out)
  }

  function report() {
    if (!ld.item) { console.log("@error The widget did not load."); Qt.quit(); return }
    const all = []
    walk(ld.item, all)
    const texts = [], notes = []
    for (const it of all) {
      if (!shown(it)) continue
      const isText = ("truncated" in it) && ("paintedWidth" in it) && ("text" in it) && typeof it.text === "string"
      const isImage = ("fillMode" in it) && ("status" in it) && ("source" in it) && ("sourceSize" in it)
      if (isText && it.text.trim() !== "") {
        const b = textBox(it)
        texts.push({ t: it, b: b })
        const s = it.text.replace(/\n/g, " ").slice(0, 70)
        let line = "@text \"" + s + "\" at x " + round(b.x) + ", y " + round(b.y) + ", " + round(b.w) + "×" + round(b.h) + ", " + round(it.font.pixelSize > 0 ? it.font.pixelSize : it.font.pointSize * 1.33) + " px"
        if (it.truncated) line += ", CUT OFF (doesn't fit; shorten it, make it smaller, or give it more width)"
        if (b.x < -1 || b.y < -1 || b.x + b.w > r.cw + 1 || b.y + b.h > r.ch + 1) line += ", OUTSIDE THE CARD (the card's content is " + r.cw + "×" + r.ch + ")"
        if (/undefined|NaN|null|\[object/.test(s)) line += ", SHOWS A BROKEN VALUE"
        if (/^(…|\.\.\.|loading…?|Loading\.\.\.)$/i.test(s.trim())) line += ", STILL WAITING FOR DATA after " + (Number(Quickshell.env("WAIT") || 6000) / 1000) + " s"
        if (it.color && it.color.a !== undefined && it.color.a < 0.2) line += ", nearly invisible colour"
        console.log(line)
      } else if (isImage && it.source.toString() !== "") {
        if (it.status === Image.Error) notes.push("@image " + it.source + " DID NOT LOAD")
        else if (it.status === Image.Loading) notes.push("@image " + it.source + " still loading")
      } else if (("requestPaint" in it) && ("getContext" in it)) {
        const p = it.mapToItem(ld, 0, 0)
        const desc = "@canvas at x " + round(p.x) + ", y " + round(p.y) + ", " + round(it.width) + "×" + round(it.height)
        if (it.width < 12 || it.height < 12) notes.push(desc + ": ALMOST NO ROOM to draw in (give it a width and height, or Layout.fillWidth/fillHeight, and check its neighbours don't take all the room)")
        else console.log(desc)
      }
    }
    // Words drawn over other words.
    for (let i = 0; i < texts.length; i++)
      for (let j = i + 1; j < texts.length; j++) {
        const a = texts[i].b, b = texts[j].b
        const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
        const oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y)
        if (ox > 2 && oy > 2 && ox * oy > 0.15 * Math.min(a.w * a.h, b.w * b.h))
          notes.push("@overlap \"" + texts[i].t.text.slice(0, 30) + "\" and \"" + texts[j].t.text.slice(0, 30) + "\" are drawn over each other")
      }
    if (!texts.length) notes.push("@empty No text is showing. If it should show data, the data did not arrive or isn't put into the Text.")
    for (const n of notes) console.log(n)
    card.grabToImage(res => { res.saveToFile(Quickshell.env("OUT")); console.log("@done"); Qt.quit() }, Qt.size(card.width * 2, card.height * 2))
  }
}
