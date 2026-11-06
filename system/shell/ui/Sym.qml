import QtQuick
import qs.core

// Memora's line symbols, drawn in code so they stay sharp at any scale and take
// the current ink. name: wifi, wifi-off, battery, control, search, moon, sound,
// sound-off, bluetooth, sun, ai, power, restart, sleep, lock, logout, chevron,
// check, plus, close, gear, user, arrow.
Canvas {
  id: c
  property string name: "wifi"
  property color color: Theme.text
  property real level: 1      // wifi strength / battery charge / volume, 0..1
  property bool charging: false
  property real stroke: 1.6
  implicitWidth: 16
  implicitHeight: 16
  antialiasing: true

  onNameChanged: requestPaint()
  onColorChanged: requestPaint()
  onLevelChanged: requestPaint()
  onChargingChanged: requestPaint()
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
      ctx.beginPath(); ctx.moveTo(8.6, 0.8); ctx.lineTo(10.8, 3.2); ctx.lineTo(8.2, 4.8); ctx.stroke()
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
    case "check": {
      ctx.lineWidth = 1.9
      ctx.beginPath(); ctx.moveTo(3, 8.4); ctx.lineTo(6.6, 12); ctx.lineTo(13.2, 4.4); ctx.stroke()
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
    case "user": {
      ctx.beginPath(); ctx.arc(8, 5.6, 3, 0, Math.PI * 2); ctx.fill()
      ctx.beginPath(); ctx.moveTo(2.2, 14.4); ctx.quadraticCurveTo(2.6, 9.4, 8, 9.4)
      ctx.quadraticCurveTo(13.4, 9.4, 13.8, 14.4); ctx.closePath(); ctx.fill()
      break
    }
    }
    ctx.restore()
  }
}
