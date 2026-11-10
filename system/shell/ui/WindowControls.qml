import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

// Close, minimize and zoom for Memora's own windows. Rest on the green button
// and a panel of layouts appears: halves, quarters, thirds or the whole screen.
Item {
  id: wc
  property var window                       // the FloatingWindow
  signal closeRequested()
  // 16px circles 28px apart: the same in every app (the Browser draws its own so);
  // with a finger, 20px circles 36px apart.
  readonly property real d: Input.touch ? 20 : 16
  width: row.width; height: d
  readonly property bool over: hov.hovered || layouts.hovered
  // Zones and layouts (default/zones.json) for the shape of this window's screen.
  property var zoneData: ({ zones: {}, layouts: {} })
  FileView {
    path: Theme.share + "/default/zones.json"
    printErrors: false
    onLoaded: { try { wc.zoneData = JSON.parse(text()) } catch (e) {} }
  }
  // The screen's free area, roughly: below the menu bar, beside the Dock.
  readonly property var scr: wc.window && wc.window.screen ? wc.window.screen : null
  readonly property real areaW: scr ? scr.width - (Prefs.dockPosition === "bottom" ? 20 : Prefs.dockSize + 40) : 1900
  readonly property real areaH: scr ? scr.height - 50 - (Prefs.dockPosition === "bottom" ? Prefs.dockSize + 28 : 0) : 1000
  readonly property string kind: areaH > areaW ? "portrait" : (areaW / Math.max(1, areaH) >= 2.1 ? "wide" : (areaW < 1400 ? "compact" : "regular"))
  readonly property var layouts: (zoneData.layouts || {})[kind] || []
  function fits(f) {
    const mn = wc.window ? wc.window.minimumSize : Qt.size(0, 0)
    return f[2] * (areaW + 10) - 10 + 2 >= (mn ? mn.width : 0) && f[3] * (areaH + 10) - 10 + 2 >= (mn ? mn.height : 0)
  }
  property bool onGreen: false

  Row {
    id: row
    spacing: Input.touch ? 16 : 12
    Repeater {
      model: [["close", Theme.red, "close"], ["min", Theme.yellow, "minus"], ["zoom", Theme.green, "plus"]]
      delegate: Rectangle {
        required property var modelData
        width: wc.d; height: wc.d; radius: wc.d / 2
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
    HoverHandler { id: lh; onHoveredChanged: if (hovered) hideLater.stop(); else hideLater.restart() }

    Text {
      x: 10; y: 8
      text: "Move & Resize"
      color: Theme.textDim; font.family: Theme.font; font.pixelSize: Theme.small - 1
    }
    // The layouts that suit this window's screen (default/zones.json, shared with
    // docking by dragging); parts the window can't shrink to are dimmed.
    Grid {
      id: grid
      x: 10; y: 28
      columns: 3; spacing: 8
      Repeater {
        model: wc.layouts
        delegate: Item {
          id: cell
          required property var modelData
          width: 64; height: 42
          Rectangle { anchors.fill: parent; radius: 7; color: Theme.field; border.color: Theme.separator }
          Repeater {
            model: cell.modelData
            delegate: Rectangle {
              required property var modelData
              readonly property var f: wc.zoneData.zones[modelData] || [0, 0, 1, 1]
              readonly property bool can: wc.fits(f)
              x: 3 + f[0] * (cell.width - 6) + 1; y: 3 + f[1] * (cell.height - 6) + 1
              width: f[2] * (cell.width - 6) - 2; height: f[3] * (cell.height - 6) - 2
              radius: 3
              opacity: can ? 1 : 0.3
              color: zh.hovered && can ? Theme.accent : Theme.textFaint
              HoverHandler { id: zh; cursorShape: parent.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
              TapHandler { enabled: parent.can; onTapped: { layouts.open = false; Quickshell.execDetached(["memora-window", modelData]) } }
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
      TapHandler { onTapped: { layouts.open = false; Quickshell.execDetached(["memora-window", "arrange"]) } }
    }
  }
}
