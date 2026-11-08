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

`create` answers whether it loaded or gives the QML error: fix it and create
again until it loads. Then take a screenshot and look at it: fix anything that
is cut off, overlaps or is hard to read. Tell the person it is on their desktop
(they can drag it, or remove it with Edit Widgets: right-click the desktop).

## What a widget can use
- Imports: `QtQuick`, `QtQuick.Layouts`, `QtQuick.Shapes`, `Quickshell`,
  `Quickshell.Io` (Process, StdioCollector, FileView). Not `qs.*`.
- Declare `property var memora` on the root: the desktop fills it with
  `{ dark, text, dim, accent, font, small, large, medium }` (colours that follow
  light/dark mode and the accent colour; `medium` is true for the wide size).
  Use them for every colour and font: `color: memora ? memora.text : "white"`.
- Data: a `Process` running a command (curl to a public API with `-s`,
  `date`, reading a file), parsed in `StdioCollector.onStreamFinished`, with a
  `Timer` to refresh (`triggeredOnStart: true`; every minute or slower for the
  network). Keep data in properties; show "…" until it arrives and a short
  message if it fails. No API keys in widgets unless the person gives one.
- Clicks: `TapHandler { onTapped: Quickshell.execDetached(["xdg-open", url]) }`.

## Design, so it looks like it belongs to Memora
- Font: `memora.font` (JetBrains Mono). Keep it in a root property with another
  name (`face`): inside a Text, `font` is the Text's own font. Title or label at the top in bold,
  `memora.small` size and `memora.dim` colour, e.g. "BITCOIN".
- One big number or word as the hero (32–44 px, `Font.Light` or `Font.Medium`),
  details below it in `memora.small` and `memora.dim`.
- At most one accent: `memora.accent`, or green `#34c759` / red `#ff3b30` for
  up/down. No gradients over the whole card, no emoji as decoration.
- Align to the left edge, leave air; nothing closer than 0 px to the edges is
  needed (the card already pads). Text that may be long: `elide: Text.ElideRight`
  and a `width`.
- Small charts: a `Canvas` or `Shapes` line, 1.5–2 px, in `memora.accent`.

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
    Text { text: days; color: ink; font.family: face; font.pixelSize: 44; font.weight: Font.Light }
    Text { text: days === 1 ? "day to go" : "days to go"; color: dim; font.family: face; font.pixelSize: 12 }
  }
}
```

## Other desktop changes
Wallpaper, Dock size and hiding, light/dark, accent colour: `system_setting`.
Window rules, keyboard shortcuts or animations: `~/.config/hypr/user.lua`
(Lua, read the existing file first; `hyprctl reload` applies it).
