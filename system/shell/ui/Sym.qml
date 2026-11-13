import QtQuick
import qs.core

// Memora's line symbols, drawn in code so they stay sharp at any scale and take
// the current ink. name: wifi, wifi-off, battery, control, search, moon, sound,
// sound-off, bluetooth, sun, ai, power, restart, sleep, lock, cup, logout, chevron,
// check, plus, close, gear, user, arrow, folder, archive, compress, resize, rotate,
// text, film, convert (and the others in the switch below).
Canvas {
  id: c
  property string name: "wifi"
  property color color: Theme.text
  property real level: 1      // wifi strength / battery charge / volume, 0..1
  property bool charging: false
  property bool filled: false  // heart: filled in (a favourite)
  property real stroke: 1.6
  implicitWidth: 16
  implicitHeight: 16
  antialiasing: true

  onNameChanged: requestPaint()
  onColorChanged: requestPaint()
  onLevelChanged: requestPaint()
  onChargingChanged: requestPaint()
  onFilledChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  function rr(ctx, x, y, w, h, r) {
    ctx.beginPath()
    ctx.moveTo(x + r, y); ctx.lineTo(x + w - r, y); ctx.arcTo(x + w, y, x + w, y + r, r)
    ctx.lineTo(x + w, y + h - r); ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
    ctx.lineTo(x + r, y + h); ctx.arcTo(x, y + h, x, y + h - r, r)
    ctx.lineTo(x, y + r); ctx.arcTo(x, y, x + r, y, r); ctx.closePath()
  }

  onPaint: {
    const ctx = getContext("2d")
    ctx.reset()
    const s = Math.min(width, height) / 16
    ctx.save()
    ctx.translate((width - 16 * s) / 2, (height - 16 * s) / 2)
    ctx.scale(s, s)
    ctx.strokeStyle = c.color
    ctx.fillStyle = c.color
    ctx.lineWidth = c.stroke
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    const dim = Qt.rgba(c.color.r, c.color.g, c.color.b, 0.28)

    switch (c.name) {
    case "wifi":
    case "wifi-off": {
      const bars = c.name === "wifi-off" ? 0 : Math.ceil(c.level * 3)
      for (let i = 0; i < 3; i++) {
        const r = 4 + i * 3.6
        ctx.strokeStyle = i < bars ? c.color : dim
        ctx.lineWidth = 1.9
        ctx.beginPath(); ctx.arc(8, 13.4, r, Math.PI * 1.25, Math.PI * 1.75); ctx.stroke()
      }
      ctx.fillStyle = bars > 0 ? c.color : dim
      ctx.beginPath(); ctx.arc(8, 13.2, 1.5, 0, Math.PI * 2); ctx.fill()
      break
    }
    case "battery": {
      ctx.globalAlpha = 0.45
      rr(ctx, 0.8, 4.2, 12.6, 7.6, 2.4); ctx.lineWidth = 1.1; ctx.stroke()
      ctx.globalAlpha = 0.45
      rr(ctx, 14.2, 6.6, 1.3, 2.8, 0.6); ctx.fill()
      ctx.globalAlpha = 1
      const w = Math.max(1.2, 10.4 * c.level)
      ctx.fillStyle = c.level < 0.15 && !c.charging ? Theme.red : c.color
      rr(ctx, 1.9, 5.3, w, 5.4, 1.5); ctx.fill()
      if (c.charging) {
        ctx.fillStyle = Theme.dark ? "#000" : "#fff"
        ctx.beginPath(); ctx.moveTo(7.8, 4.6); ctx.lineTo(5.6, 8.4); ctx.lineTo(7.4, 8.4)
        ctx.lineTo(6.6, 11.4); ctx.lineTo(9.0, 7.4); ctx.lineTo(7.2, 7.4); ctx.closePath(); ctx.fill()
      }
      break
    }
    case "control": {
      ctx.lineWidth = 1.2
      rr(ctx, 1.5, 3, 13, 4.4, 2.2); ctx.stroke()
      rr(ctx, 1.5, 8.8, 13, 4.4, 2.2); ctx.stroke()
      ctx.beginPath(); ctx.arc(4.2, 5.2, 1.4, 0, Math.PI * 2); ctx.fill()
      ctx.beginPath(); ctx.arc(11.8, 11, 1.4, 0, Math.PI * 2); ctx.fill()
      break
    }
    case "search": {
      ctx.lineWidth = 1.7
      ctx.beginPath(); ctx.arc(6.8, 6.8, 4.6, 0, Math.PI * 2); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(10.3, 10.3); ctx.lineTo(14.2, 14.2); ctx.stroke()
      break
    }
    case "moon": {
      ctx.beginPath(); ctx.arc(8, 8, 6, 0, Math.PI * 2); ctx.fill()
      ctx.globalCompositeOperation = "destination-out"
      ctx.beginPath(); ctx.arc(11.2, 5.2, 5.2, 0, Math.PI * 2); ctx.fill()
      ctx.globalCompositeOperation = "source-over"
      break
    }
    case "sun": {
      ctx.beginPath(); ctx.arc(8, 8, 3, 0, Math.PI * 2); ctx.fill()
      ctx.lineWidth = 1.5
      for (let i = 0; i < 8; i++) {
        const a = i * Math.PI / 4
        ctx.beginPath(); ctx.moveTo(8 + Math.cos(a) * 5, 8 + Math.sin(a) * 5)
        ctx.lineTo(8 + Math.cos(a) * 6.8, 8 + Math.sin(a) * 6.8); ctx.stroke()
      }
      break
    }
    case "sound":
    case "sound-off": {
      ctx.beginPath(); ctx.moveTo(1.5, 6); ctx.lineTo(4.5, 6); ctx.lineTo(8, 2.8); ctx.lineTo(8, 13.2)
      ctx.lineTo(4.5, 10); ctx.lineTo(1.5, 10); ctx.closePath(); ctx.fill()
      ctx.lineWidth = 1.4
      if (c.name === "sound-off") {
        ctx.beginPath(); ctx.moveTo(10.5, 5.5); ctx.lineTo(15, 10.5); ctx.moveTo(15, 5.5); ctx.lineTo(10.5, 10.5); ctx.stroke()
      } else {
        const waves = Math.ceil(c.level * 3)
        for (let i = 0; i < 3; i++) {
          ctx.strokeStyle = i < waves ? c.color : dim
          ctx.beginPath(); ctx.arc(8, 8, 3 + i * 2.4, -Math.PI / 4, Math.PI / 4); ctx.stroke()
        }
      }
      break
    }
    case "bluetooth": {
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(4.5, 4.8); ctx.lineTo(11.2, 10.8); ctx.lineTo(8, 13.8); ctx.lineTo(8, 2.2)
      ctx.lineTo(11.2, 5.2); ctx.lineTo(4.5, 11.2); ctx.stroke()
      break
    }
    case "ai": {
      // Four-point spark.
      ctx.beginPath(); ctx.moveTo(8, 1.2)
      ctx.quadraticCurveTo(8.8, 7.2, 14.8, 8); ctx.quadraticCurveTo(8.8, 8.8, 8, 14.8)
      ctx.quadraticCurveTo(7.2, 8.8, 1.2, 8); ctx.quadraticCurveTo(7.2, 7.2, 8, 1.2); ctx.fill()
      break
    }
    case "power": {
      ctx.lineWidth = 1.7
      ctx.beginPath(); ctx.arc(8, 8.6, 5.4, -Math.PI * 0.32, Math.PI * 1.32); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(8, 1.8); ctx.lineTo(8, 7.6); ctx.stroke()
      break
    }
    case "restart": {
      ctx.lineWidth = 1.7
      ctx.beginPath(); ctx.arc(8, 8.4, 5.4, -Math.PI * 0.45, Math.PI * 1.25); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(5.2, 6.7); ctx.lineTo(5.3, 3.45); ctx.lineTo(2.0, 3.6); ctx.stroke()  // head at the end of the arc, turning clockwise
      break
    }
    case "sleep": {
      ctx.beginPath(); ctx.arc(8, 8, 6, 0, Math.PI * 2); ctx.lineWidth = 1.5; ctx.stroke()
      ctx.beginPath(); ctx.arc(8, 8, 4.2, 0, Math.PI * 2); ctx.fill()
      ctx.globalCompositeOperation = "destination-out"
      ctx.beginPath(); ctx.arc(10.4, 6, 3.6, 0, Math.PI * 2); ctx.fill()
      ctx.globalCompositeOperation = "source-over"
      break
    }
    case "lock": {
      ctx.lineWidth = 1.6
      ctx.beginPath(); ctx.arc(8, 6.2, 3.2, Math.PI, 0); ctx.lineTo(11.2, 7.4); ctx.moveTo(4.8, 7.4); ctx.lineTo(4.8, 6.2); ctx.stroke()
      rr(ctx, 3, 7.2, 10, 7.4, 2); ctx.fill()
      break
    }
    case "cup": {   // Keep Awake: a cup of coffee
      ctx.lineWidth = 1.6
      ctx.beginPath(); ctx.moveTo(2.6, 6.4); ctx.lineTo(11.4, 6.4); ctx.lineTo(10.6, 12.2)
      ctx.quadraticCurveTo(10.3, 14.2, 8.4, 14.2); ctx.lineTo(5.6, 14.2); ctx.quadraticCurveTo(3.7, 14.2, 3.4, 12.2); ctx.closePath(); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(11.3, 7.8); ctx.quadraticCurveTo(14.4, 7.6, 14, 10); ctx.quadraticCurveTo(13.6, 11.8, 10.9, 11.4); ctx.stroke()
      ctx.lineWidth = 1.3
      ctx.beginPath(); ctx.moveTo(5.4, 4.6); ctx.quadraticCurveTo(4.4, 3.4, 5.4, 2.2); ctx.moveTo(8.4, 4.6); ctx.quadraticCurveTo(7.4, 3.4, 8.4, 2.2); ctx.stroke()
      break
    }
    case "logout": {
      ctx.lineWidth = 1.6
      ctx.beginPath(); ctx.moveTo(9.5, 2.5); ctx.lineTo(3, 2.5); ctx.lineTo(3, 13.5); ctx.lineTo(9.5, 13.5); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(7, 8); ctx.lineTo(14.5, 8); ctx.moveTo(12, 5.4); ctx.lineTo(14.6, 8); ctx.lineTo(12, 10.6); ctx.stroke()
      break
    }
    case "chevron": {
      ctx.lineWidth = 1.8
      ctx.beginPath(); ctx.moveTo(6, 3.5); ctx.lineTo(10.5, 8); ctx.lineTo(6, 12.5); ctx.stroke()
      break
    }
    case "arrow": {
      ctx.lineWidth = 1.9
      ctx.beginPath(); ctx.moveTo(2.5, 8); ctx.lineTo(13.5, 8); ctx.moveTo(9, 3.5); ctx.lineTo(13.5, 8); ctx.lineTo(9, 12.5); ctx.stroke()
      break
    }
    case "shortcut": case "alias": {
      ctx.lineWidth = 1.7
      ctx.beginPath()
      ctx.moveTo(3.5, 12.5)
      ctx.bezierCurveTo(4.0, 7.5, 7.0, 4.5, 12.0, 4.5)
      ctx.moveTo(8.5, 2.0); ctx.lineTo(12.5, 4.5); ctx.lineTo(8.5, 7.5)
      ctx.stroke()
      break
    }
    case "check": {
      ctx.lineWidth = 1.9
      ctx.beginPath(); ctx.moveTo(3, 8.4); ctx.lineTo(6.6, 12); ctx.lineTo(13.2, 4.4); ctx.stroke()
      break
    }
    case "copy": {   // two overlapping pages
      ctx.lineWidth = 1.5
      rr(ctx, 5.5, 5.5, 8.5, 8.5, 1.8); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(10.5, 3.6); ctx.lineTo(10.5, 3.4); ctx.quadraticCurveTo(10.5, 2, 9.1, 2); ctx.lineTo(3.4, 2)
      ctx.quadraticCurveTo(2, 2, 2, 3.4); ctx.lineTo(2, 9.1); ctx.quadraticCurveTo(2, 10.5, 3.4, 10.5); ctx.lineTo(3.6, 10.5); ctx.stroke()
      break
    }
    case "file": {   // a page with a folded corner
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(9.5, 1.8); ctx.lineTo(4.2, 1.8); ctx.quadraticCurveTo(3, 1.8, 3, 3); ctx.lineTo(3, 13)
      ctx.quadraticCurveTo(3, 14.2, 4.2, 14.2); ctx.lineTo(11.8, 14.2); ctx.quadraticCurveTo(13, 14.2, 13, 13); ctx.lineTo(13, 5.3); ctx.closePath(); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(9.5, 1.8); ctx.lineTo(9.5, 5.3); ctx.lineTo(13, 5.3); ctx.stroke()
      break
    }
    case "folder": {
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(1.8, 4); ctx.quadraticCurveTo(1.8, 2.6, 3.2, 2.6); ctx.lineTo(5.8, 2.6); ctx.lineTo(7.4, 4.2); ctx.lineTo(12.8, 4.2)
      ctx.quadraticCurveTo(14.2, 4.2, 14.2, 5.6); ctx.lineTo(14.2, 12); ctx.quadraticCurveTo(14.2, 13.4, 12.8, 13.4); ctx.lineTo(3.2, 13.4)
      ctx.quadraticCurveTo(1.8, 13.4, 1.8, 12); ctx.closePath(); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(1.8, 6.4); ctx.lineTo(14.2, 6.4); ctx.stroke()
      break
    }
    case "archive": {   // a box with a lid and a handle
      ctx.lineWidth = 1.5
      rr(ctx, 1.6, 2.4, 12.8, 3.4, 1); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(2.6, 5.8); ctx.lineTo(2.6, 12.4); ctx.quadraticCurveTo(2.6, 13.6, 3.8, 13.6); ctx.lineTo(12.2, 13.6)
      ctx.quadraticCurveTo(13.4, 13.6, 13.4, 12.4); ctx.lineTo(13.4, 5.8); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(6.4, 8.6); ctx.lineTo(9.6, 8.6); ctx.stroke()
      break
    }
    case "compress": {   // two arrows meeting in the middle
      ctx.lineWidth = 1.6
      ctx.beginPath(); ctx.moveTo(2, 2); ctx.lineTo(6.6, 6.6); ctx.moveTo(6.6, 3.2); ctx.lineTo(6.6, 6.6); ctx.lineTo(3.2, 6.6)
      ctx.moveTo(14, 14); ctx.lineTo(9.4, 9.4); ctx.moveTo(9.4, 12.8); ctx.lineTo(9.4, 9.4); ctx.lineTo(12.8, 9.4); ctx.stroke()
      break
    }
    case "resize": {   // two arrows going out to the corners
      ctx.lineWidth = 1.6
      ctx.beginPath(); ctx.moveTo(6.4, 9.6); ctx.lineTo(2.2, 13.8); ctx.moveTo(2.2, 9.8); ctx.lineTo(2.2, 13.8); ctx.lineTo(6.2, 13.8)
      ctx.moveTo(9.6, 6.4); ctx.lineTo(13.8, 2.2); ctx.moveTo(9.8, 2.2); ctx.lineTo(13.8, 2.2); ctx.lineTo(13.8, 6.2); ctx.stroke()
      break
    }
    case "rotate": {   // an arc with an arrow head, turning right
      ctx.lineWidth = 1.6
      ctx.beginPath(); ctx.arc(8, 8.6, 5.4, Math.PI * 1.15, Math.PI * 2.75); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(1.8, 3.2); ctx.lineTo(3.4, 6.4); ctx.lineTo(6.6, 5); ctx.stroke()
      break
    }
    case "text": {   // a page of lines
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(2.4, 3); ctx.lineTo(13.6, 3); ctx.moveTo(2.4, 6.4); ctx.lineTo(13.6, 6.4)
      ctx.moveTo(2.4, 9.8); ctx.lineTo(13.6, 9.8); ctx.moveTo(2.4, 13.2); ctx.lineTo(9, 13.2); ctx.stroke()
      break
    }
    case "film": {
      ctx.lineWidth = 1.4
      rr(ctx, 1.6, 2.4, 12.8, 11.2, 1.8); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(4.6, 2.4); ctx.lineTo(4.6, 13.6); ctx.moveTo(11.4, 2.4); ctx.lineTo(11.4, 13.6)
      ctx.moveTo(1.6, 8); ctx.lineTo(4.6, 8); ctx.moveTo(11.4, 8); ctx.lineTo(14.4, 8)
      ctx.moveTo(1.6, 5.2); ctx.lineTo(4.6, 5.2); ctx.moveTo(11.4, 5.2); ctx.lineTo(14.4, 5.2)
      ctx.moveTo(1.6, 10.8); ctx.lineTo(4.6, 10.8); ctx.moveTo(11.4, 10.8); ctx.lineTo(14.4, 10.8); ctx.stroke()
      break
    }
    case "convert": {   // two arrows, one over the other, going opposite ways
      ctx.lineWidth = 1.6
      ctx.beginPath(); ctx.moveTo(2, 5); ctx.lineTo(13.4, 5); ctx.moveTo(10.6, 2.2); ctx.lineTo(13.4, 5); ctx.lineTo(10.6, 7.8)
      ctx.moveTo(14, 11); ctx.lineTo(2.6, 11); ctx.moveTo(5.4, 8.2); ctx.lineTo(2.6, 11); ctx.lineTo(5.4, 13.8); ctx.stroke()
      break
    }
    case "plus": {
      ctx.lineWidth = 1.7
      ctx.beginPath(); ctx.moveTo(8, 2.5); ctx.lineTo(8, 13.5); ctx.moveTo(2.5, 8); ctx.lineTo(13.5, 8); ctx.stroke()
      break
    }
    case "close": {
      ctx.lineWidth = 1.7
      ctx.beginPath(); ctx.moveTo(3.5, 3.5); ctx.lineTo(12.5, 12.5); ctx.moveTo(12.5, 3.5); ctx.lineTo(3.5, 12.5); ctx.stroke()
      break
    }
    case "gear": {
      ctx.lineWidth = 1.5
      for (let i = 0; i < 8; i++) {
        const a = i * Math.PI / 4
        ctx.beginPath(); ctx.moveTo(8 + Math.cos(a) * 4.6, 8 + Math.sin(a) * 4.6)
        ctx.lineTo(8 + Math.cos(a) * 6.8, 8 + Math.sin(a) * 6.8); ctx.lineWidth = 2.4; ctx.stroke()
      }
      ctx.lineWidth = 1.6
      ctx.beginPath(); ctx.arc(8, 8, 4.4, 0, Math.PI * 2); ctx.stroke()
      ctx.beginPath(); ctx.arc(8, 8, 1.8, 0, Math.PI * 2); ctx.stroke()
      break
    }
    case "play": {
      ctx.beginPath(); ctx.moveTo(4.5, 2.5); ctx.lineTo(13.5, 8); ctx.lineTo(4.5, 13.5); ctx.closePath(); ctx.fill()
      break
    }
    case "pause": {
      rr(ctx, 3.5, 2.5, 3.2, 11, 1); ctx.fill(); rr(ctx, 9.3, 2.5, 3.2, 11, 1); ctx.fill()
      break
    }
    case "next": {
      ctx.beginPath(); ctx.moveTo(1.5, 3.5); ctx.lineTo(8, 8); ctx.lineTo(1.5, 12.5); ctx.closePath(); ctx.fill()
      ctx.beginPath(); ctx.moveTo(8, 3.5); ctx.lineTo(14.5, 8); ctx.lineTo(8, 12.5); ctx.closePath(); ctx.fill()
      break
    }
    case "prev": {
      ctx.beginPath(); ctx.moveTo(14.5, 3.5); ctx.lineTo(8, 8); ctx.lineTo(14.5, 12.5); ctx.closePath(); ctx.fill()
      ctx.beginPath(); ctx.moveTo(8, 3.5); ctx.lineTo(1.5, 8); ctx.lineTo(8, 12.5); ctx.closePath(); ctx.fill()
      break
    }
    case "shuffle": {   // two crossing arrows
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(1.5, 4.5); ctx.lineTo(4.5, 4.5); ctx.bezierCurveTo(8, 4.5, 8, 11.5, 11.5, 11.5); ctx.lineTo(14, 11.5); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(1.5, 11.5); ctx.lineTo(4.5, 11.5); ctx.bezierCurveTo(8, 11.5, 8, 4.5, 11.5, 4.5); ctx.lineTo(14, 4.5); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(12, 2.5); ctx.lineTo(14.2, 4.5); ctx.lineTo(12, 6.5); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(12, 9.5); ctx.lineTo(14.2, 11.5); ctx.lineTo(12, 13.5); ctx.stroke()
      break
    }
    case "repeat": case "repeat-one": {   // a loop of two arrows
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(2.5, 7.5); ctx.lineTo(2.5, 6.5); ctx.quadraticCurveTo(2.5, 4.5, 4.5, 4.5); ctx.lineTo(13, 4.5); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(11, 2.5); ctx.lineTo(13.2, 4.5); ctx.lineTo(11, 6.5); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(13.5, 8.5); ctx.lineTo(13.5, 9.5); ctx.quadraticCurveTo(13.5, 11.5, 11.5, 11.5); ctx.lineTo(3, 11.5); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(5, 9.5); ctx.lineTo(2.8, 11.5); ctx.lineTo(5, 13.5); ctx.stroke()
      if (c.name === "repeat-one") { ctx.font = "bold 6px sans-serif"; ctx.textAlign = "center"; ctx.fillText("1", 8, 10.2) }
      break
    }
    case "queue": {   // lines with a play mark: up next
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(2, 4); ctx.lineTo(14, 4); ctx.moveTo(2, 8); ctx.lineTo(9, 8); ctx.moveTo(2, 12); ctx.lineTo(9, 12); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(11.5, 8.5); ctx.lineTo(14.5, 10.5); ctx.lineTo(11.5, 12.5); ctx.closePath(); ctx.fill()
      break
    }
    case "lyrics": {   // a speech bubble with a quote
      ctx.lineWidth = 1.5
      rr(ctx, 1.8, 2.5, 12.4, 9, 2.5); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(5, 11.5); ctx.lineTo(4.5, 14); ctx.lineTo(7.5, 11.5); ctx.stroke()
      ctx.beginPath(); ctx.arc(6, 7, 1.1, 0, Math.PI * 2); ctx.fill(); ctx.beginPath(); ctx.arc(10, 7, 1.1, 0, Math.PI * 2); ctx.fill()
      break
    }
    case "music": {   // a note
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(6, 12); ctx.lineTo(6, 3); ctx.lineTo(13, 1.8); ctx.lineTo(13, 10.5); ctx.stroke()
      ctx.beginPath(); ctx.ellipse(1.8, 10.2, 4.6, 3.8); ctx.fill()     // (Qt's ellipse takes its bounding box)
      ctx.beginPath(); ctx.ellipse(8.8, 8.7, 4.6, 3.8); ctx.fill()
      break
    }
    case "display": {
      ctx.lineWidth = 1.5
      rr(ctx, 1.5, 2.5, 13, 9, 1.8); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(5.5, 14); ctx.lineTo(10.5, 14); ctx.moveTo(8, 11.5); ctx.lineTo(8, 14); ctx.stroke()
      break
    }
    case "phone": {   // a phone, upright
      ctx.lineWidth = 1.5
      rr(ctx, 4.2, 1.2, 7.6, 13.6, 1.8); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(7, 3.2); ctx.lineTo(9, 3.2); ctx.stroke()
      break
    }
    case "laptop": {
      ctx.lineWidth = 1.5
      rr(ctx, 2.8, 3, 10.4, 7.4, 1.2); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(1, 12.6); ctx.lineTo(15, 12.6); ctx.stroke()
      break
    }
    case "share": {   // a box with an arrow out of it
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(5.4, 6); ctx.lineTo(3.6, 6); ctx.lineTo(3.6, 14.2); ctx.lineTo(12.4, 14.2); ctx.lineTo(12.4, 6); ctx.lineTo(10.6, 6); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(8, 10); ctx.lineTo(8, 1.6); ctx.moveTo(5.4, 4.2); ctx.lineTo(8, 1.6); ctx.lineTo(10.6, 4.2); ctx.stroke()
      break
    }
    case "heart": {
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(8, 13.6)
      ctx.bezierCurveTo(2.4, 9.8, 1.2, 7.4, 1.6, 5.2); ctx.bezierCurveTo(2, 2.8, 4.2, 1.8, 5.9, 2.4)
      ctx.bezierCurveTo(6.9, 2.8, 7.6, 3.6, 8, 4.4); ctx.bezierCurveTo(8.4, 3.6, 9.1, 2.8, 10.1, 2.4)
      ctx.bezierCurveTo(11.8, 1.8, 14, 2.8, 14.4, 5.2); ctx.bezierCurveTo(14.8, 7.4, 13.6, 9.8, 8, 13.6); ctx.closePath()
      if (c.filled) ctx.fill(); ctx.stroke()
      break
    }
    case "trash": {
      ctx.lineWidth = 1.4
      ctx.beginPath(); ctx.moveTo(2, 4); ctx.lineTo(14, 4); ctx.moveTo(6, 4); ctx.lineTo(6.4, 2); ctx.lineTo(9.6, 2); ctx.lineTo(10, 4); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(3.4, 4); ctx.lineTo(4.2, 13.4); ctx.quadraticCurveTo(4.3, 14.4, 5.3, 14.4); ctx.lineTo(10.7, 14.4)
      ctx.quadraticCurveTo(11.7, 14.4, 11.8, 13.4); ctx.lineTo(12.6, 4); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(6.6, 6.6); ctx.lineTo(6.8, 12); ctx.moveTo(9.4, 6.6); ctx.lineTo(9.2, 12); ctx.stroke()
      break
    }
    case "photo": {
      ctx.lineWidth = 1.4
      rr(ctx, 1.5, 2.5, 13, 11, 2); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(2.5, 12); ctx.lineTo(6, 7.8); ctx.lineTo(9, 10.6); ctx.lineTo(10.8, 9); ctx.lineTo(13.6, 12); ctx.stroke()
      ctx.beginPath(); ctx.arc(10.6, 5.8, 1.2, 0, Math.PI * 2); ctx.fill()
      break
    }
    case "keyboard": {
      ctx.lineWidth = 1.3
      rr(ctx, 0.8, 3.5, 14.4, 9, 1.8); ctx.stroke()
      for (let r = 0; r < 2; r++) for (let k = 0; k < 5; k++) { ctx.fillRect(2.6 + k * 2.4, 5.3 + r * 2.2, 1.4, 1.3) }
      ctx.fillRect(4.4, 9.8, 7.2, 1.3)
      break
    }
    case "mouse": {
      ctx.lineWidth = 1.5
      rr(ctx, 4, 1.5, 8, 13, 4); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(8, 3.5); ctx.lineTo(8, 6.5); ctx.stroke()
      break
    }
    case "clock": {
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.arc(8, 8, 6.2, 0, Math.PI * 2); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(8, 4.2); ctx.lineTo(8, 8.2); ctx.lineTo(10.8, 9.8); ctx.stroke()
      break
    }
    case "bell": {
      ctx.beginPath(); ctx.moveTo(8, 1.8); ctx.quadraticCurveTo(3.2, 2.4, 3.6, 8); ctx.lineTo(2.2, 11.6); ctx.lineTo(13.8, 11.6)
      ctx.lineTo(12.4, 8); ctx.quadraticCurveTo(12.8, 2.4, 8, 1.8); ctx.fill()
      ctx.beginPath(); ctx.arc(8, 12.8, 1.8, 0, Math.PI); ctx.fill()
      break
    }
    case "sidebar": {
      ctx.lineWidth = 1.4
      rr(ctx, 1.5, 2.5, 13, 11, 2.2); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(6, 2.5); ctx.lineTo(6, 13.5); ctx.stroke()
      break
    }
    case "dock": {
      ctx.lineWidth = 1.4
      rr(ctx, 1.5, 2, 13, 12, 2); ctx.stroke()
      rr(ctx, 3.5, 10, 9, 2.4, 1.2); ctx.fill()
      break
    }
    case "globe": {
      ctx.lineWidth = 1.3
      ctx.beginPath(); ctx.arc(8, 8, 6.2, 0, Math.PI * 2); ctx.stroke()
      ctx.beginPath(); ctx.ellipse(5.4, 1.8, 5.2, 12.4); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(1.8, 8); ctx.lineTo(14.2, 8); ctx.stroke()
      break
    }
    case "info": {
      ctx.beginPath(); ctx.arc(8, 8, 6.6, 0, Math.PI * 2); ctx.fill()
      ctx.fillStyle = Theme.dark ? "#2a2a2e" : "#ffffff"
      ctx.fillRect(7.1, 7, 1.8, 5); ctx.beginPath(); ctx.arc(8, 4.9, 1.1, 0, Math.PI * 2); ctx.fill()
      break
    }
    case "user": {
      ctx.beginPath(); ctx.arc(8, 5.6, 3, 0, Math.PI * 2); ctx.fill()
      ctx.beginPath(); ctx.moveTo(2.2, 14.4); ctx.quadraticCurveTo(2.6, 9.4, 8, 9.4)
      ctx.quadraticCurveTo(13.4, 9.4, 13.8, 14.4); ctx.closePath(); ctx.fill()
      break
    }
    case "star": {
      ctx.lineWidth = 1.4
      ctx.beginPath()
      for (let i = 0; i < 10; i++) {
        const r = i % 2 ? 2.9 : 6.6, a = -Math.PI / 2 + i * Math.PI / 5
        const px = 8 + Math.cos(a) * r, py = 8.5 + Math.sin(a) * r
        if (i) ctx.lineTo(px, py); else ctx.moveTo(px, py)
      }
      ctx.closePath()
      if (c.filled) ctx.fill(); ctx.stroke()
      break
    }
    case "gamepad": {
      ctx.lineWidth = 1.4
      rr(ctx, 1.4, 4.4, 13.2, 7.6, 3.7); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(3.9, 8.2); ctx.lineTo(6.7, 8.2); ctx.moveTo(5.3, 6.8); ctx.lineTo(5.3, 9.6); ctx.stroke()
      ctx.beginPath(); ctx.arc(10.2, 9.1, 0.85, 0, Math.PI * 2); ctx.fill()
      ctx.beginPath(); ctx.arc(11.9, 7.3, 0.85, 0, Math.PI * 2); ctx.fill()
      break
    }
    case "sparkle": {
      ctx.beginPath(); ctx.moveTo(8, 1.2)
      ctx.quadraticCurveTo(8.9, 7.1, 14.8, 8); ctx.quadraticCurveTo(8.9, 8.9, 8, 14.8)
      ctx.quadraticCurveTo(7.1, 8.9, 1.2, 8); ctx.quadraticCurveTo(7.1, 7.1, 8, 1.2); ctx.closePath(); ctx.fill()
      break
    }
    case "drop": {
      ctx.beginPath(); ctx.moveTo(8, 1.6)
      ctx.bezierCurveTo(11, 5.4, 13, 7.8, 13, 10); ctx.arc(8, 10, 5, 0, Math.PI); ctx.bezierCurveTo(3, 7.8, 5, 5.4, 8, 1.6)
      ctx.closePath(); ctx.fill()
      break
    }
    case "palette": {
      ctx.lineWidth = 1.4
      ctx.beginPath(); ctx.arc(8, 8, 6.2, 0, Math.PI * 2); ctx.stroke()
      ;[[5.2, 6.2], [8, 4.4], [10.8, 6.2], [10.6, 9.6]].forEach(p => { ctx.beginPath(); ctx.arc(p[0], p[1], 1.15, 0, Math.PI * 2); ctx.fill() })
      break
    }
    case "shield": {
      ctx.beginPath(); ctx.moveTo(8, 1.4); ctx.lineTo(13.6, 3.4); ctx.lineTo(13.6, 7.6)
      ctx.quadraticCurveTo(13.4, 12.4, 8, 14.8); ctx.quadraticCurveTo(2.6, 12.4, 2.4, 7.6); ctx.lineTo(2.4, 3.4); ctx.closePath(); ctx.fill()
      break
    }
    case "download": {
      ctx.lineWidth = 1.6; ctx.lineCap = "round"; ctx.lineJoin = "round"
      ctx.beginPath(); ctx.moveTo(8, 2); ctx.lineTo(8, 10.4); ctx.moveTo(4.6, 7.2); ctx.lineTo(8, 10.6); ctx.lineTo(11.4, 7.2); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(2.6, 11.6); ctx.lineTo(2.6, 13.8); ctx.lineTo(13.4, 13.8); ctx.lineTo(13.4, 11.6); ctx.stroke()
      break
    }
    case "cloud": case "rain": case "snow": case "storm": case "fog": case "suncloud": {
      const cloud = (ox, oy, k) => {
        ctx.beginPath()
        ctx.moveTo(ox + 3.4 * k, oy + 11 * k)
        ctx.arc(ox + 4.2 * k, oy + 8.6 * k, 2.6 * k, Math.PI * 0.6, Math.PI * 1.45)
        ctx.arc(ox + 7.6 * k, oy + 6.4 * k, 3.6 * k, Math.PI * 1.1, Math.PI * 1.95)
        ctx.arc(ox + 11.4 * k, oy + 8.8 * k, 2.4 * k, Math.PI * 1.5, Math.PI * 0.45)
        ctx.closePath(); ctx.fill()
      }
      if (c.name === "suncloud") {
        ctx.beginPath(); ctx.arc(10.6, 5.2, 2.6, 0, Math.PI * 2); ctx.fill()
        ctx.lineWidth = 1.2
        for (let i = 0; i < 6; i++) { const a = -Math.PI * 0.95 + i * Math.PI / 4.2; ctx.beginPath(); ctx.moveTo(10.6 + Math.cos(a) * 3.9, 5.2 + Math.sin(a) * 3.9); ctx.lineTo(10.6 + Math.cos(a) * 5.2, 5.2 + Math.sin(a) * 5.2); ctx.stroke() }
        cloud(-0.6, 1.6, 1)
      } else cloud(0, c.name === "cloud" || c.name === "fog" ? 1.5 : -0.6, 1)
      ctx.lineWidth = 1.4; ctx.lineCap = "round"
      if (c.name === "rain") for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.moveTo(5 + i * 3, 12.2); ctx.lineTo(4.2 + i * 3, 14.8); ctx.stroke() }
      if (c.name === "snow") for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.arc(4.8 + i * 3, 13.4 + (i % 2), 0.9, 0, Math.PI * 2); ctx.fill() }
      if (c.name === "storm") { ctx.beginPath(); ctx.moveTo(8.6, 10.6); ctx.lineTo(6.8, 13.4); ctx.lineTo(8.6, 13.4); ctx.lineTo(7.4, 15.6); ctx.stroke() }
      if (c.name === "fog") for (let i = 0; i < 2; i++) { ctx.beginPath(); ctx.moveTo(3, 13.6 + i * 1.8); ctx.lineTo(13, 13.6 + i * 1.8); ctx.stroke() }
      break
    }
    }
    ctx.restore()
  }
}
