import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Desktops (Hyprland workspaces 1…N) and the overview of them (Mission Control).
//   Ctrl+Super+Left/Right   previous / next desktop (three fingers sideways too)
//   Ctrl+Super+Shift+…      take the focused window along
//   Ctrl+Super+Up, F3, Super+S   the overview: every desktop along the top,
//                           this desktop's windows laid out below; click one to
//                           go to it, drag one onto a desktop to move it there.
Scope {
  id: dk

  readonly property int current: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
  // Desktops in use: the ones you made, and any other with windows on it.
  readonly property int count: {
    let n = Math.max(1, Prefs.desktops)
    Hyprland.workspaces.values.forEach(w => { if (w.id > n && w.id < 100) n = w.id })
    return Math.max(n, current > 0 && current < 100 ? current : 1)
  }
  function windowsOn(id) { return Apps.windows.filter(w => w.lastIpcObject.workspace && w.lastIpcObject.workspace.id === id) }

  function go(n) {
    n = Math.max(1, Math.min(count, n))
    if (n === current) { pulse(); return }
    Hyprland.dispatch('hl.dsp.focus({ workspace = "' + n + '" })')
    pulse()
  }
  function carry(n) {
    n = Math.max(1, Math.min(count, n))
    const w = Hyprland.activeToplevel
    // Only a window on this desktop (an empty desktop has none in front).
    if (!w || n === current || !w.workspace || w.workspace.id !== current) return
    Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + n + '", window = "address:0x' + String(w.address).replace(/^0x/, "") + '" })')
    go(n)
  }
  function add() { Prefs.set("desktops", count + 1) }
  // Removing a desktop moves its windows to the one before it.
  function remove(n) {
    if (count <= 1) return
    const to = n > 1 ? n - 1 : 2
    windowsOn(n).forEach(w => Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + to + '", window = "address:0x' + String(w.address).replace(/^0x/, "") + '", follow = false })'))
    // Desktops after it slide down by one.
    for (let i = n + 1; i <= count; i++)
      windowsOn(i).forEach(w => Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + (i - 1) + '", window = "address:0x' + String(w.address).replace(/^0x/, "") + '", follow = false })'))
    Prefs.set("desktops", Math.max(1, count - 1))
    if (current >= n) Qt.callLater(() => go(Math.max(1, current - 1)))
  }

  IpcHandler {
    target: "desktops"
    function next(x: string): void { dk.go(dk.current + 1) }
    function prev(x: string): void { dk.go(dk.current - 1) }
    function go(n: string): void { dk.go(parseInt(n)) }
    function carry(n: string): void { dk.carry(parseInt(n)) }
    function carryNext(x: string): void { dk.carry(dk.current + 1) }
    function carryPrev(x: string): void { dk.carry(dk.current - 1) }
  }

  // ---- the little indicator when switching -----------------------------------
  property bool showPill: false
  function pulse() { showPill = true; pillOff.restart() }
  Timer { id: pillOff; interval: 900; onTriggered: dk.showPill = false }
  Connections { target: Hyprland; function onFocusedWorkspaceChanged() { if (Shell.open !== "overview") dk.pulse() } }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      readonly property bool here: Hyprland.focusedMonitor ? modelData.name === Hyprland.focusedMonitor.name : modelData === Quickshell.screens[0]
      visible: here && (dk.showPill || pillFade.running) && dk.count > 1
      anchors { bottom: true }
      margins.bottom: 118
      implicitWidth: pill.width + 20; implicitHeight: pill.height + 20
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-osd"
      mask: Region {}
      Glass {
        id: pill
        anchors.centerIn: parent
        width: dots.implicitWidth + 32; height: 34
        radius: 17
        fill: Theme.glassStrong
        shadowSize: 18
        opacity: dk.showPill ? 1 : 0
        scale: dk.showPill ? 1 : 0.9
        Behavior on opacity { NumberAnimation { id: pillFade; duration: Theme.normal } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
        Row {
          id: dots
          anchors.centerIn: parent
          spacing: 7
          Repeater {
            model: dk.count
            delegate: Rectangle {
              required property int index
              readonly property bool on: index + 1 === dk.current
              width: on ? 22 : 8; height: 8; radius: 4
              color: on ? Theme.accent : Theme.textFaint
              Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
              Behavior on color { ColorAnimation { duration: Theme.normal } }
            }
          }
        }
      }
    }
  }

  // ---- the overview -------------------------------------------------------------
  readonly property bool open: Shell.open === "overview"
  onOpenChanged: if (open) { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); dk.shownDesk = dk.current }
  property int shownDesk: 1

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: ov
      required property var modelData
      screen: modelData
      readonly property bool here: Hyprland.focusedMonitor ? modelData.name === Hyprland.focusedMonitor.name : modelData === Quickshell.screens[0]
      visible: here && (dk.open || fade.running)
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-overview"
      WlrLayershell.keyboardFocus: dk.open && here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      property real shown: dk.open ? 1 : 0
      Behavior on shown { NumberAnimation { id: fade; duration: Prefs.motion(dk.open ? 380 : 220); easing.type: dk.open ? Easing.OutQuint : Easing.InCubic } }

      // The monitor in logical pixels, for placing windows.
      readonly property real mx: modelData.x
      readonly property real my: modelData.y
      readonly property real mw: modelData.width
      readonly property real mh: modelData.height

      Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25); opacity: ov.shown }
      Item {
        anchors.fill: parent
        focus: dk.open
        Keys.onEscapePressed: Shell.close()
        Keys.onLeftPressed: dk.shownDesk = Math.max(1, dk.shownDesk - 1)
        Keys.onRightPressed: dk.shownDesk = Math.min(dk.count, dk.shownDesk + 1)
        Keys.onReturnPressed: { dk.go(dk.shownDesk); Shell.close() }
        TapHandler { onTapped: { if (dk.shownDesk !== dk.current) dk.go(dk.shownDesk); Shell.close() } }
      }

      // ---- desktops along the top
      property int dropOn: 0           // the desktop a dragged window would go to
      Row {
        id: strip
        anchors.horizontalCenter: parent.horizontalCenter
        y: 44 - (1 - ov.shown) * 30
        opacity: ov.shown
        spacing: 16
        readonly property real tw: Math.min(220, (ov.width - 120) / (dk.count + 1) - 16)
        readonly property real th: tw * ov.mh / ov.mw
        Repeater {
          model: dk.count
          delegate: Item {
            id: desk
            required property int index
            readonly property int num: index + 1
            readonly property bool active: num === dk.shownDesk
            width: strip.tw; height: strip.th + 24
            Rectangle {
              id: thumb
              width: strip.tw; height: strip.th
              radius: 10; clip: true
              color: "black"
              border.width: desk.active || ov.dropOn === desk.num ? 3 : 1
              border.color: ov.dropOn === desk.num ? Theme.green : (desk.active ? Theme.accent : Qt.rgba(1, 1, 1, 0.2))
              scale: dh.hovered || ov.dropOn === desk.num ? 1.04 : 1
              Behavior on scale { NumberAnimation { duration: Theme.fast } }
              Image { anchors.fill: parent; source: "file://" + Theme.wallpaper; sourceSize: Qt.size(440, 280); fillMode: Image.PreserveAspectCrop }
              // Its windows, as small cards with their icons.
              Repeater {
                model: dk.open ? dk.windowsOn(desk.num) : []
                delegate: Rectangle {
                  required property var modelData
                  readonly property var o: modelData.lastIpcObject
                  x: (o.at[0] - ov.mx) / ov.mw * thumb.width; y: (o.at[1] - ov.my) / ov.mh * thumb.height
                  width: Math.max(14, o.size[0] / ov.mw * thumb.width); height: Math.max(10, o.size[1] / ov.mh * thumb.height)
                  radius: 3
                  color: Theme.dark ? Qt.rgba(0.16, 0.16, 0.19, 0.95) : Qt.rgba(0.97, 0.97, 0.98, 0.95)
                  border.color: Qt.rgba(1, 1, 1, 0.25)
                  AppIcon { anchors.centerIn: parent; appId: Apps.classOf(parent.modelData); width: Math.min(22, parent.height * 0.7); height: width }
                }
              }
              HoverHandler { id: dh }
              TapHandler { onTapped: { dk.go(desk.num); Shell.close() } }
              // Remove (×), on hover, when there is more than one.
              Rectangle {
                visible: dh.hovered && dk.count > 1
                x: -7; y: -7; width: 22; height: 22; radius: 11
                color: Theme.dark ? "#3a3a3e" : "#e5e5ea"; border.color: Qt.rgba(0, 0, 0, 0.25)
                Sym { anchors.centerIn: parent; name: "close"; width: 9; height: 9 }
                TapHandler { onTapped: dk.remove(desk.num) }
                Tip { text: "Remove this desktop (its windows move over)" }
              }
            }
            Txt {
              anchors { top: thumb.bottom; topMargin: 6; horizontalCenter: thumb.horizontalCenter }
              text: "Desktop " + desk.num; color: "#ffffff"; font.pixelSize: Theme.small
              font.weight: desk.active ? Font.Bold : Font.Normal
            }
          }
        }
        // Add a desktop
        Rectangle {
          width: Math.min(strip.tw, 90); height: strip.th
          radius: 10
          color: ah.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
          border.color: Qt.rgba(1, 1, 1, 0.22)
          Sym { anchors.centerIn: parent; name: "plus"; width: 22; height: 22; color: "#ffffff" }
          HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: dk.add() }
          Tip { text: "Add a desktop" }
        }
      }

      // ---- this desktop's windows, spread out
      Item {
        id: field
        anchors { left: parent.left; right: parent.right; top: strip.bottom; bottom: parent.bottom; margins: 60; topMargin: 50; bottomMargin: 120 }
        readonly property var wins: dk.open ? dk.windowsOn(dk.shownDesk).filter(w => !Apps.isMinimized(w)) : []
        readonly property int n: wins.length
        readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(n * width / Math.max(1, height) * 0.6)))
        readonly property int rows: Math.max(1, Math.ceil(n / cols))
        Txt {
          anchors.centerIn: parent; visible: field.n === 0 && dk.open
          text: "No windows on this desktop"; color: Qt.rgba(1, 1, 1, 0.7)
        }
        Repeater {
          model: field.wins
          delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property var o: modelData.lastIpcObject
            // Its slot in the grid, keeping the window's shape.
            readonly property real cw: field.width / field.cols
            readonly property real ch: field.height / field.rows
            readonly property int r: Math.floor(index / field.cols)
            readonly property int c: index % field.cols
            readonly property int inRow: Math.min(field.cols, field.n - r * field.cols)
            readonly property real k: Math.min((cw - 30) / o.size[0], (ch - 50) / o.size[1], 1)
            readonly property real gw: o.size[0] * k
            readonly property real gh: o.size[1] * k
            readonly property real gx: (field.width - inRow * cw) / 2 + c * cw + (cw - gw) / 2
            readonly property real gy: r * ch + (ch - gh - 22) / 2
            // Where the window really is, relative to this field.
            readonly property real rx: o.at[0] - ov.mx - field.x
            readonly property real ry: o.at[1] - ov.my - field.y
            property real t: ov.shown
            property real dx: 0
            property real dy: 0
            x: rx + (gx - rx) * t + dx
            y: ry + (gy - ry) * t + dy
            width: o.size[0] + (gw - o.size[0]) * t
            height: o.size[1] + (gh - o.size[1]) * t
            property bool dragging: false
            z: dragging ? 10 : 0
            Rectangle {
              anchors.fill: parent
              anchors.margins: -3
              radius: 12
              color: "transparent"
              border.width: 3
              border.color: Theme.accent
              opacity: ch2.hovered && !card.dragging ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            }
            ScreencopyView {
              anchors.fill: parent
              captureSource: dk.open && card.modelData.wayland ? card.modelData.wayland : null
              live: true
              layer.enabled: true
            }
            Row {
              anchors { top: parent.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
              spacing: 6
              opacity: ov.shown
              AppIcon { appId: Apps.classOf(card.modelData); width: 20; height: 20 }
              Txt { text: card.o.title || Apps.nameFor(Apps.classOf(card.modelData)); color: "#ffffff"; font.pixelSize: Theme.small; width: Math.min(implicitWidth, card.width - 30); elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
            }
            scale: dragging ? Math.min(0.9, 180 / Math.max(width, height)) : (ch2.hovered ? 1.03 : 1)
            Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
            HoverHandler { id: ch2; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { Apps.focus(card.modelData); Shell.close() } }
            DragHandler {
              id: dragger
              target: null
              // While dragged the window shrinks and its middle follows the pointer.
              onTranslationChanged: if (active) {
                card.dx = centroid.pressPosition.x + translation.x - card.width / 2
                card.dy = centroid.pressPosition.y + translation.y - card.height / 2
              }
              onActiveChanged: {
                card.dragging = active
                if (!active) { card.dx = 0; card.dy = 0 }
                if (!active) {
                  if (ov.dropOn > 0 && ov.dropOn !== dk.shownDesk)
                    Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + ov.dropOn + '", window = "address:0x' + String(card.modelData.address).replace(/^0x/, "") + '", follow = false })')
                  ov.dropOn = 0
                  Qt.callLater(() => Hyprland.refreshToplevels())
                }
              }
              onCentroidChanged: if (active) {
                const p = card.mapToItem(strip, centroid.position.x, centroid.position.y)
                let hit = 0
                for (let i = 0; i < dk.count; i++) {
                  const x0 = i * (strip.tw + strip.spacing)
                  if (p.x >= x0 - 8 && p.x <= x0 + strip.tw + 8 && p.y >= -60 && p.y <= strip.th + 40) hit = i + 1
                }
                ov.dropOn = hit
              }
            }
          }
        }
      }
      Txt {
        anchors { bottom: parent.bottom; bottomMargin: 40; horizontalCenter: parent.horizontalCenter }
        opacity: ov.shown * 0.75
        text: "Click a window to go to it · drag it onto a desktop to move it · Esc to close"
        color: "#ffffff"; font.pixelSize: Theme.small
      }
    }
  }
}
