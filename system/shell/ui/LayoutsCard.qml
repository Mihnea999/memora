import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// "Move & Resize": the layouts that suit a screen (default/zones.json, shared
// with docking by dragging) and Arrange All Windows. Opens from the green
// button, on Memora's own windows (WindowControls) and on the title bar Memora
// draws for other apps (snap/Layouts). Parts the window can't shrink to are dimmed.
Glass {
  id: card
  property bool open: false
  property real areaW: 1900                 // the screen's free area
  property real areaH: 1000
  property size minSize: Qt.size(0, 0)      // the window's smallest size
  readonly property bool hovered: lh.hovered
  signal picked(string zone)                // a zone name, or "arrange"

  property var zoneData: ({ zones: {}, layouts: {} })
  FileView {
    path: Theme.share + "/default/zones.json"
    printErrors: false
    onLoaded: { try { card.zoneData = JSON.parse(text()) } catch (e) {} }
  }
  readonly property string kind: areaH > areaW ? "portrait" : (areaW / Math.max(1, areaH) >= 2.1 ? "wide" : (areaW < 1400 ? "compact" : "regular"))
  readonly property var layouts: (zoneData.layouts || {})[kind] || []
  function fits(f) {
    return f[2] * (areaW + 10) - 10 + 2 >= minSize.width && f[3] * (areaH + 10) - 10 + 2 >= minSize.height
  }

  width: grid.width + 20; height: grid.height + 74
  radius: 12
  // Solid: inside a window nothing blurs what is under it, so glass would let the text show through.
  fill: Theme.dark ? Qt.rgba(0.15, 0.15, 0.17, 0.98) : Qt.rgba(0.98, 0.98, 0.99, 0.98)
  visible: opacity > 0
  opacity: open ? 1 : 0
  scale: open ? 1 : 0.9
  transformOrigin: Item.TopLeft
  Behavior on opacity { NumberAnimation { duration: Theme.fast } }
  Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
  HoverHandler { id: lh }

  Text {
    x: 10; y: 8
    text: "Move & Resize"
    color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.small - 1
  }
  Grid {
    id: grid
    x: 10; y: 28
    columns: 3; spacing: 8
    Repeater {
      model: card.layouts
      delegate: Item {
        id: cell
        required property var modelData
        width: 64; height: 42
        Rectangle { anchors.fill: parent; radius: 7; color: Theme.field; border.color: Theme.separator }
        Repeater {
          model: cell.modelData
          delegate: Rectangle {
            required property var modelData
            readonly property var f: card.zoneData.zones[modelData] || [0, 0, 1, 1]
            readonly property bool can: card.fits(f)
            x: 3 + f[0] * (cell.width - 6) + 1; y: 3 + f[1] * (cell.height - 6) + 1
            width: f[2] * (cell.width - 6) - 2; height: f[3] * (cell.height - 6) - 2
            radius: 3
            opacity: can ? 1 : 0.3
            color: zh.hovered && can ? Theme.accent : Theme.textFaint
            HoverHandler { id: zh; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { enabled: parent.can; onTapped: { card.open = false; card.picked(modelData) } }
          }
        }
      }
    }
  }
  // Every window on this desktop, arranged in a grid that suits the screen.
  Rectangle {
    x: 10; y: grid.y + grid.height + 8
    width: grid.width; height: 26; radius: 7
    color: ah.hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : Theme.field
    border.color: ah.hovered ? Theme.accent : Theme.separator
    Text { anchors.centerIn: parent; text: "Arrange All Windows"; color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small - 0.5 }
    HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: { card.open = false; card.picked("arrange") } }
  }
}
