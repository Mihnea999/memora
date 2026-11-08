import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import qs.core

// Close, minimize and zoom for Memora's own windows. Rest on the green button
// and a panel of layouts appears: halves, quarters, thirds or the whole screen.
Item {
  id: wc
  property var window                       // the FloatingWindow
  signal closeRequested()
  // 16px circles 28px apart: the same in every app (the Browser draws its own so).
  width: row.width; height: 16
  readonly property bool over: hov.hovered || layouts.hovered
  property bool onGreen: false

  Row {
    id: row
    spacing: 12
    Repeater {
      model: [["close", Theme.red, "close"], ["min", Theme.yellow, "minus"], ["zoom", Theme.green, "plus"]]
      delegate: Rectangle {
        required property var modelData
        width: 16; height: 16; radius: 8
        color: modelData[1]
        border.color: Qt.rgba(0, 0, 0, 0.15)
        scale: press.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
        // Symbols appear while the pointer is over the group.
        Canvas {
          anchors.fill: parent
          opacity: wc.over ? 0.65 : 0
          Behavior on opacity { NumberAnimation { duration: Theme.fast } }
          onPaint: {
            const c = getContext("2d"); c.reset(); c.strokeStyle = "#000"; c.lineWidth = 1.3; c.lineCap = "round"
            const m = width / 2
            if (modelData[2] === "close") { c.moveTo(m - 3, m - 3); c.lineTo(m + 3, m + 3); c.moveTo(m + 3, m - 3); c.lineTo(m - 3, m + 3) }
            else if (modelData[2] === "minus") { c.moveTo(m - 3.5, m); c.lineTo(m + 3.5, m) }
            else { c.moveTo(m - 3.5, m); c.lineTo(m + 3.5, m); c.moveTo(m, m - 3.5); c.lineTo(m, m + 3.5) }
            c.stroke()
          }
        }
        TapHandler {
          id: press
          onTapped: {
            if (modelData[0] === "close") wc.closeRequested()
            else if (modelData[0] === "min") Quickshell.execDetached(["memora-shell", "minimize"])
            else Quickshell.execDetached(["memora-window", "fill"])
          }
        }
        // No tooltip on the green button: resting there opens the layouts panel,
        // which explains itself (a tooltip would cover it).
        Tip { text: ({ close: "Close", min: "Minimize to the Dock", zoom: "" })[modelData[0]] }
        HoverHandler { enabled: modelData[0] === "zoom"; onHoveredChanged: { wc.onGreen = hovered; if (hovered) { hideLater.stop(); if (!layouts.open) showLater.restart() } else { showLater.stop(); hideLater.restart() } } }
      }
    }
  }
  HoverHandler { id: hov }
  // The panel lives on top of the whole window (not inside the title bar, where
  // the window's content would cover it and take the pointer): placed from here.
  readonly property var host: wc.Window.contentItem
  property point panelAt: Qt.point(0, 0)
  Timer { id: showLater; interval: 450; onTriggered: { wc.panelAt = wc.mapToItem(wc.host, 0, 0); layouts.open = true } }
  Timer { id: hideLater; interval: 500; onTriggered: if (!layouts.hovered && !wc.onGreen) layouts.open = false }

  // Between the green button and the panel: the pointer passing through keeps it open.
  Item {
    parent: wc.host || wc
    z: 9999
    visible: layouts.open
    x: wc.panelAt.x + 40; y: wc.panelAt.y + 8
    width: 36; height: 22 - 8 + 4
    HoverHandler { id: bridgeHover; onHoveredChanged: if (hovered) hideLater.stop(); else hideLater.restart() }
  }

  // The layouts panel, under the green button.
  Glass {
    id: layouts
    property bool open: false
    readonly property bool hovered: lh.hovered || bridgeHover.hovered
    parent: wc.host || wc
    x: wc.panelAt.x + 42; y: wc.panelAt.y + 22
    z: 10000
    width: grid.width + 20; height: grid.height + 40
    radius: 12
    // Solid: inside a window nothing blurs what is under it, so glass would let the text show through.
    fill: Theme.dark ? Qt.rgba(0.15, 0.15, 0.17, 0.98) : Qt.rgba(0.98, 0.98, 0.99, 0.98)
    shadowSize: 22
    visible: opacity > 0
    opacity: open ? 1 : 0
    scale: open ? 1 : 0.9
    transformOrigin: Item.TopLeft
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
    HoverHandler { id: lh; onHoveredChanged: if (hovered) hideLater.stop(); else hideLater.restart() }

    Text {
      x: 10; y: 8
      text: "Move & Resize"
      color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.small - 1
    }
    Grid {
      id: grid
      x: 10; y: 28
      columns: 4; spacing: 6
      Repeater {
        // [zone, x, y, w, h] in a 4x3 preview
        model: [["left", 0, 0, 2, 3], ["right", 2, 0, 2, 3], ["top", 0, 0, 4, 1.5], ["bottom", 0, 1.5, 4, 1.5],
                ["top-left", 0, 0, 2, 1.5], ["top-right", 2, 0, 2, 1.5], ["bottom-left", 0, 1.5, 2, 1.5], ["bottom-right", 2, 1.5, 2, 1.5],
                ["left-third", 0, 0, 1.33, 3], ["center-third", 1.33, 0, 1.33, 3], ["right-third", 2.66, 0, 1.34, 3], ["fill", 0, 0, 4, 3]]
        delegate: Rectangle {
          required property var modelData
          width: 44; height: 32; radius: 6
          color: zh.hovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : Theme.field
          border.color: zh.hovered ? Theme.accent : Theme.separator
          Rectangle {
            x: 3 + modelData[1] / 4 * (parent.width - 6); y: 3 + modelData[2] / 3 * (parent.height - 6)
            width: modelData[3] / 4 * (parent.width - 6) - 1; height: modelData[4] / 3 * (parent.height - 6) - 1
            radius: 3
            color: zh.hovered ? Theme.accent : Theme.textFaint
          }
          HoverHandler { id: zh }
          TapHandler { onTapped: { layouts.open = false; Quickshell.execDetached(["memora-window", modelData[0]]) } }
        }
      }
    }
  }
}
