---
name: widgets
when: Making something new for the desktop: a widget (a countdown, a habit tracker, crypto or stock prices, a to-do card, a photo frame, a quote of the day, server status…), or changing one made before.
---
# Desktop widgets

Widgets are the glass cards on the desktop picture (like the clock and weather
ones). You make your own with `widget(action="create", name, size, qml)`:
- `name`: short, lowercase, dashes (`btc-price`). The same name again updates it.
- `size`: `small` (a square) or `medium` (twice as wide).
- `qml`: one QML file whose root is an `Item`. The desktop puts it inside a
  rounded glass card with 16 px padding, so draw only the content, no card,
  no background, no shadow, no border.
  Space inside the card: small 136 × 136, medium 320 × 136 (logical pixels).

`create` answers whether it loaded or gives the QML error. Once it loads, it is
drawn off screen, given 7 seconds for its data, and described to you: every
text with its position and size, and anything wrong — CUT OFF, OUTSIDE THE
CARD, words drawn over each other, STILL WAITING FOR DATA, a broken value
(undefined, NaN), a picture that didn't load, and QML warnings while it runs
(`line 15: TypeError…`). Fix every problem and create it again until it says
"No problems found". `widget(action="check", name)` looks again at any time.
Then tell the person it is on their desktop (they can drag it, or remove it
with Edit Widgets: right-click the desktop).

## What a widget can use
- Imports: `QtQuick`, `QtQuick.Layouts`, `QtQuick.Shapes`, `Quickshell`,
  `Quickshell.Io` (Process, StdioCollector, FileView). Not `qs.*`.
- Declare `property var memora` on the root: the desktop fills it with
  `{ dark, text, dim, accent, font, small, large, medium }` (colours that follow
  light/dark mode and the accent colour; `medium` is true for the wide size).
  It is empty for a moment at the start: always `memora ? memora.text : "#f5f5f7"`
  (keep them in root properties, as in the example).
- Data: a `Process` running a command (curl to a public API with `-s`,
  `date`, reading a file), parsed in `StdioCollector.onStreamFinished` inside
  `try { … } catch (e) { failed = true }`, with a `Timer` to refresh
  (`triggeredOnStart: true`; every minute or slower for the network; set
  `p.running = true` in it). Keep data in properties; show "…" until it
  arrives and a short message ("Offline") if it fails. No API keys unless the
  person gives one.
- Clicks: `TapHandler { onTapped: Quickshell.execDetached(["xdg-open", url]) }`.
- Pictures: `Image { source: "https://…"; asynchronous: true; fillMode: Image.PreserveAspectFit }`
  works for logos and photos from the web, or `file:///home/…` for local ones.

## Symbols
The font has thousands of icons. Put one in a Text with
`String.fromCodePoint(0x…)` (same font, any size and colour):

| | | | |
|---|---|---|---|
| bitcoin F0813 | ethereum F086A | dollar F01C1 | euro F01AD |
| up-trend F0535 | down-trend F0533 | bar chart F0128 | cash F0114 |
| sunny F0599 | cloudy F0590 | rain F0597 | snow F0598 |
| wind F059D | thermometer F050F | humidity F058E | drop F058C |
| air quality / filter F0D43 | leaf F032A | CO₂ F07E4 | sprout F0E66 |
| heart F02D1 | star F04CE | home F02DC | calendar F00ED |
| clock F0150 | bell F009A | battery F0079 | wifi F05A9 |
| server F048B | cpu F0EE0 | memory F035B | disk F02CA |
| github F02A4 | music F075A | book F00BE | run F070E |
| coffee F0176 | check F05E0 | alert F0026 | fire F0238 |
| flash F0241 | earth F01E7 | map pin F034E | rocket F0463 |
| car F010B | train F052C | plane F001D | gas F0298 |
| cart F0110 | pill F0402 | gamepad F0297 | email F01EE |

Plain characters work too: ₿ € $ ° ▲ ▼ ● ✓.

## Data that needs no key
- Crypto: `https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true`
  → `{"bitcoin":{"usd":97000,"usd_24h_change":-1.2}}`; last day for a chart:
  `https://api.coingecko.com/api/v3/coins/bitcoin/market_chart?vs_currency=usd&days=1`
  → `{"prices":[[ms, price], …]}` (about 288 points).
- Where the computer is: the command `memora-location` →
  `{"latitude":48.85,"longitude":2.35,"city":"Paris","country":"FR"}` (kept for a
  day, with spare services when one is busy: don't call ipapi.co yourself, it refuses
  when asked often).
- Weather: `https://api.open-meteo.com/v1/forecast?latitude=…&longitude=…&current=temperature_2m,weather_code,wind_speed_10m`.
- Air quality: `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=…&longitude=…&current=european_aqi,pm2_5,pm10`
  → `{"current":{"european_aqi":23,"pm2_5":5.1,"pm10":8.2}}`. European AQI:
  0–20 good, 20–40 fair, 40–60 moderate, 60–80 poor, 80–100 very poor, more extremely poor.
  Both in one command, e.g. air quality where the computer is:
  `["bash", "-c", "l=$(memora-location) && curl -s --max-time 15 \"https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$(jq -r .latitude <<<\"$l\")&longitude=$(jq -r .longitude <<<\"$l\")&current=european_aqi,pm2_5,pm10\""]`
  (in QML the inner quotes are `\"`), or chain two Processes (the second starts in the
  first one's `onStreamFinished`).
- Exchange rates: `https://open.er-api.com/v6/latest/EUR`.

## Drawing
Simple pictures and charts: a `Canvas` (with a size!) or `Shapes`.
A line chart: `onPaint` with `getContext("2d")`, map values to the canvas,
`lineWidth = 1.75`, `strokeStyle = accent`, `lineJoin = "round"`; call
`requestPaint()` when the data changes. A ring or gauge: `ctx.arc(...)`. Bars:
`Repeater` of `Rectangle`s with `radius`.

## Design, so it looks like it belongs to Memora
- Font: `memora.font` (JetBrains Mono). Keep it in a root property with another
  name (`face`): inside a Text, `font` is the Text's own font. Title or label at the top in bold,
  11 px, `memora.dim` colour, e.g. "BITCOIN".
- One big number or word as the hero (28–40 px, `Font.Light` or `Font.Medium`):
  measure it, a small card is only 136 px wide (a "$97,215" at 40 px is
  ~170 px: too wide; use 28 px, or `fontSizeMode: Text.HorizontalFit` with
  `minimumPixelSize: 18` and a `width`). Details below it in 11–12 px, `memora.dim`.
- At most one accent: `memora.accent`, or green `#34c759` / red `#ff3b30` for
  up/down. No gradients over the whole card, no emoji as decoration.
- Lay things out with `ColumnLayout`/`RowLayout` and `anchors.fill: parent`,
  never fixed `y` numbers that can overlap. Align to the left edge. Text that
  may be long: a `width` (or `Layout.fillWidth: true`) and `elide: Text.ElideRight`.

## Example (small): a countdown
```qml
import QtQuick
import QtQuick.Layouts

Item {
  property var memora
  readonly property color ink: memora ? memora.text : "#f5f5f7"
  readonly property color dim: memora ? memora.dim : "#8e8e93"
  readonly property string face: memora ? memora.font : "monospace"
  property date target: new Date(2026, 11, 25)
  property int days: 0
  Timer { interval: 60000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: days = Math.max(0, Math.ceil((target - new Date()) / 86400000)) }
  ColumnLayout {
    anchors.fill: parent
    spacing: 2
    Text { text: "CHRISTMAS"; color: dim; font.family: face; font.pixelSize: 11; font.bold: true }
    Item { Layout.fillHeight: true }
    Text { text: days; color: ink; font.family: face; font.pixelSize: 40; font.weight: Font.Light }
    Text { text: days === 1 ? "day to go" : "days to go"; color: dim; font.family: face; font.pixelSize: 12 }
  }
}
```

## Example (medium): a price with its symbol and a chart of the day
```qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

Item {
  id: w
  property var memora
  readonly property color ink: memora ? memora.text : "#f5f5f7"
  readonly property color dim: memora ? memora.dim : "#8e8e93"
  readonly property color accent: memora ? memora.accent : "#3d8bff"
  readonly property string face: memora ? memora.font : "monospace"
  property real price: 0
  property real change: 0
  property var points: []
  property bool failed: false

  Process {
    id: now
    command: ["curl", "-s", "--max-time", "15", "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd&include_24hr_change=true"]
    stdout: StdioCollector { onStreamFinished: {
      try { const j = JSON.parse(text).bitcoin; w.price = j.usd; w.change = j.usd_24h_change; w.failed = false } catch (e) { w.failed = true }
    } }
  }
  Process {
    id: day
    command: ["curl", "-s", "--max-time", "15", "https://api.coingecko.com/api/v3/coins/bitcoin/market_chart?vs_currency=usd&days=1"]
    stdout: StdioCollector { onStreamFinished: {
      try { w.points = JSON.parse(text).prices.map(p => p[1]); chart.requestPaint() } catch (e) {}
    } }
  }
  Timer { interval: 300000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { now.running = true; day.running = true } }

  RowLayout {
    anchors.fill: parent
    spacing: 14
    ColumnLayout {
      Layout.preferredWidth: 130; Layout.maximumWidth: 130; Layout.fillWidth: false; Layout.fillHeight: true
      spacing: 2
      RowLayout {
        spacing: 6
        Text { text: String.fromCodePoint(0xF0813); color: "#f7931a"; font.family: w.face; font.pixelSize: 16 }
        Text { text: "BITCOIN"; color: w.dim; font.family: w.face; font.pixelSize: 11; font.bold: true }
      }
      Item { Layout.fillHeight: true }
      Text {
        Layout.fillWidth: true
        text: w.failed ? "Offline" : (w.price ? "$" + Math.round(w.price).toLocaleString(Qt.locale("en_US"), "f", 0) : "…")
        color: w.ink; font.family: w.face; font.pixelSize: 28; font.weight: Font.Medium
        fontSizeMode: Text.HorizontalFit; minimumPixelSize: 16
      }
      Text {
        visible: w.price > 0
        text: (w.change >= 0 ? "▲ " : "▼ ") + Math.abs(w.change).toFixed(2) + "% today"
        color: w.change >= 0 ? "#34c759" : "#ff3b30"; font.family: w.face; font.pixelSize: 12
      }
    }
    Canvas {
      id: chart
      Layout.fillWidth: true; Layout.fillHeight: true
      onPaint: {
        const c = getContext("2d"); c.reset()
        const p = w.points
        if (p.length < 2) return
        const lo = Math.min(...p), hi = Math.max(...p), span = (hi - lo) || 1
        c.beginPath()
        p.forEach((v, i) => {
          const x = i / (p.length - 1) * width, y = 4 + (1 - (v - lo) / span) * (height - 8)
          i ? c.lineTo(x, y) : c.moveTo(x, y)
        })
        c.lineWidth = 1.75; c.lineJoin = "round"; c.strokeStyle = w.accent; c.stroke()
      }
    }
  }
}
```

## Other desktop changes
Wallpaper, Dock size and hiding, light/dark, accent colour: `system_setting`.
Window rules, keyboard shortcuts or animations: `~/.config/hypr/user.lua`
(Lua, read the existing file first; `hyprctl reload` applies it).
