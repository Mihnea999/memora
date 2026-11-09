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
  function nameOf(n) { const v = (Prefs.desktopNames || [])[n - 1]; return v ? v : "Desktop " + n }
  function rename(n, name) {
    const a = (Prefs.desktopNames || []).slice()
    while (a.length < n) a.push("")
    a[n - 1] = name.trim()
    Prefs.set("desktopNames", a)
  }
  function moveTo(w, n) { Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + n + '", window = "address:0x' + String(w.address).replace(/^0x/, "") + '", follow = false })') }
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
    // App Exposé: every window of one app (the one in front when none is named).
    function expose(cls: string): void {
      let c = cls && cls !== "0" ? cls : ""   // memora-shell passes "0" for none
      if (!c) { const a = Hyprland.activeToplevel; c = a ? Apps.classOf(Apps.windows.find(x => x.address === a.address) || a) : "" }
      if (!c) return
      dk.app = c; Shell.show("overview")
    }
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
      margins.bottom: Shell.bottomInset + 14
      implicitWidth: pill.width + 20; implicitHeight: pill.height + 20
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-osd"
      mask: Region {}
      Glass {
        id: pill
        anchors.centerIn: parent
        width: dots.implicitWidth + 32 + (pillName.visible ? pillName.implicitWidth + 12 : 0); height: 34
        radius: 17
        fill: Theme.glassStrong
        shadowSize: 18
        opacity: dk.showPill ? 1 : 0
        scale: dk.showPill ? 1 : 0.9
        Behavior on opacity { NumberAnimation { id: pillFade; duration: Theme.normal } }
        Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutBack } }
        Txt {
          id: pillName
          visible: ((Prefs.desktopNames || [])[dk.current - 1] || "") !== ""
          anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
          text: dk.nameOf(dk.current); font.pixelSize: Theme.small; font.weight: Font.Bold
        }
        Row {
          id: dots
          x: 16
          anchors.verticalCenter: parent.verticalCenter
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
  onOpenChanged: {
    if (open) { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); dk.shownDesk = dk.current; dk.query = ""; dk.sel = -1 }
    else Qt.callLater(() => { if (!dk.open) dk.app = "" })
  }
  property int shownDesk: 1
  property string app: ""            // App Exposé: only this app's windows
  property string query: ""          // typed to find a window on any desktop
  property int sel: -1               // the window chosen with the arrow keys
  // The windows shown, laid out the way they sit on the screen: in bands from
  // top to bottom, each band from left to right.
  function spatial(list, cols) {
    const c = w => [w.lastIpcObject.at[0] + w.lastIpcObject.size[0] / 2, w.lastIpcObject.at[1] + w.lastIpcObject.size[1] / 2]
    const byY = list.slice().sort((a, b) => c(a)[1] - c(b)[1])
    const out = []
    for (let i = 0; i < byY.length; i += cols) out.push(...byY.slice(i, i + cols).sort((a, b) => c(a)[0] - c(b)[0]))
    return out
  }
  readonly property var shownWindows: {
    if (!open) return []
    const q = query.toLowerCase()
    let ws
    if (app) ws = Apps.windowsOf(app).filter(w => !Apps.isMinimized(w))
    else if (q) ws = Apps.windows.filter(w => !Apps.isMinimized(w) && ((w.title || "").toLowerCase().indexOf(q) >= 0 || Apps.nameFor(Apps.classOf(w)).toLowerCase().indexOf(q) >= 0))
    else ws = windowsOn(shownDesk).filter(w => !Apps.isMinimized(w))
    return ws.filter(w => w.lastIpcObject && w.lastIpcObject.at)
  }
  readonly property var minimizedShown: open && app ? Apps.windowsOf(app).filter(w => Apps.isMinimized(w)) : []

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
        Keys.onPressed: ev => {
          const n = field.list.length
          if (ev.key === Qt.Key_Escape) { if (dk.query) dk.query = ""; else Shell.close() }
          else if ((ev.modifiers & Qt.ControlModifier) && ev.key === Qt.Key_Left) dk.shownDesk = Math.max(1, dk.shownDesk - 1)
          else if ((ev.modifiers & Qt.ControlModifier) && ev.key === Qt.Key_Right) dk.shownDesk = Math.min(dk.count, dk.shownDesk + 1)
          else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Tab) dk.sel = n ? (dk.sel + 1) % n : -1
          else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Backtab) dk.sel = n ? (dk.sel - 1 + n) % n : -1
          else if (ev.key === Qt.Key_Down) dk.sel = n ? Math.min(n - 1, dk.sel + field.cols) : -1
          else if (ev.key === Qt.Key_Up) dk.sel = n ? Math.max(0, dk.sel - field.cols) : -1
          else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
            const w = field.list[dk.sel >= 0 ? dk.sel : 0]
            if (w) Apps.focus(w); else if (!dk.query) dk.go(dk.shownDesk)
            Shell.close()
          }
          else if (ev.key === Qt.Key_Backspace) dk.query = dk.query.slice(0, -1)
          else if (ev.text && ev.text.length === 1 && ev.text >= " " && !(ev.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) { dk.query += ev.text; dk.sel = 0 }
          else return
          ev.accepted = true
        }
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
            // Its name; double-click to rename it.
            Txt {
              id: deskName
              visible: !nameEdit.visible
              anchors { top: thumb.bottom; topMargin: 6; horizontalCenter: thumb.horizontalCenter }
              width: Math.min(implicitWidth, thumb.width)
              text: dk.nameOf(desk.num); color: "#ffffff"; font.pixelSize: Theme.small
              font.weight: desk.active ? Font.Bold : Font.Normal
              TapHandler { onDoubleTapped: { nameEdit.text = (Prefs.desktopNames || [])[desk.num - 1] || ""; nameEdit.visible = true; nameEdit.forceActiveFocus() } }
            }
            TextInput {
              id: nameEdit
              visible: false
              anchors { top: thumb.bottom; topMargin: 6; horizontalCenter: thumb.horizontalCenter }
              width: thumb.width; clip: true
              horizontalAlignment: TextInput.AlignHCenter
              color: "#ffffff"; font.family: Theme.font; font.pixelSize: Theme.small
              selectionColor: Theme.accent
              Rectangle { anchors.fill: parent; anchors.margins: -3; z: -1; radius: 5; color: Qt.rgba(1, 1, 1, 0.15) }
              Keys.onReturnPressed: { dk.rename(desk.num, text); visible = false }
              Keys.onEscapePressed: visible = false
              onActiveFocusChanged: if (!activeFocus && visible) { dk.rename(desk.num, text); visible = false }
            }
          }
        }
        // Add a desktop (drop a window here: a new desktop with it).
        Rectangle {
          id: plus
          width: Math.min(strip.tw, 90); height: strip.th
          radius: 10
          color: ah.hovered || ov.dropOn === dk.count + 1 ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
          border.color: ov.dropOn === dk.count + 1 ? Theme.green : Qt.rgba(1, 1, 1, 0.22)
          border.width: ov.dropOn === dk.count + 1 ? 3 : 1
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
        readonly property var wins: dk.shownWindows
        readonly property int n: wins.length
        readonly property var list: dk.spatial(wins, cols)
        readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(n * width / Math.max(1, height) * 0.6)))
        readonly property int rows: Math.max(1, Math.ceil(n / cols))
        Txt {
          anchors.centerIn: parent; visible: field.n === 0 && dk.open
          text: dk.query ? "No window matches “" + dk.query + "”" : (dk.app ? "No open windows" : "No windows on this desktop"); color: Qt.rgba(1, 1, 1, 0.7)
        }
        Repeater {
          model: field.list
          delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool chosen: dk.sel === index
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
              opacity: (ch2.hovered || card.chosen) && !card.dragging ? 1 : 0
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
            TapHandler { acceptedButtons: Qt.MiddleButton; onTapped: Apps.close(card.modelData) }
            // Another desktop (searching, App Exposé): which one.
            Rectangle {
              readonly property int d: card.o.workspace ? card.o.workspace.id : 0
              visible: d > 0 && d !== dk.shownDesk && ov.shown > 0.9
              anchors { right: parent.right; top: parent.top; margins: 8 }
              width: cdl.implicitWidth + 14; height: 20; radius: 10; color: Theme.glassSolid
              Txt { id: cdl; anchors.centerIn: parent; text: dk.nameOf(parent.d); font.pixelSize: Theme.small - 1 }
            }
            // Close, on hover.
            Rectangle {
              visible: ch2.hovered && !card.dragging && ov.shown > 0.9
              x: -9; y: -9; width: 24; height: 24; radius: 12
              color: xh.hovered ? Theme.red : (Theme.dark ? "#3a3a3e" : "#e5e5ea"); border.color: Qt.rgba(0, 0, 0, 0.25)
              Sym { anchors.centerIn: parent; name: "close"; width: 9; height: 9; color: xh.hovered ? "#ffffff" : Theme.text }
              HoverHandler { id: xh }
              TapHandler { onTapped: Apps.close(card.modelData) }
            }
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
                  if (ov.dropOn === dk.count + 1) { const nn = dk.count + 1; dk.add(); dk.moveTo(card.modelData, nn) }
                  else if (ov.dropOn > 0 && ov.dropOn !== dk.shownDesk) dk.moveTo(card.modelData, ov.dropOn)
                  ov.dropOn = 0
                  Qt.callLater(() => Hyprland.refreshToplevels())
                }
              }
              onCentroidChanged: if (active) {
                const p = card.mapToItem(strip, centroid.position.x, centroid.position.y)
                let hit = 0
                for (let i = 0; i <= dk.count; i++) {   // the last one is "+"
                  const x0 = i * (strip.tw + strip.spacing)
                  if (p.x >= x0 - 8 && p.x <= x0 + strip.tw + 8 && p.y >= -60 && p.y <= strip.th + 40) hit = i + 1
                }
                ov.dropOn = hit
              }
            }
          }
        }
      }
      // App Exposé: the app's minimized windows, along the bottom.
      Row {
        anchors { bottom: parent.bottom; bottomMargin: 66; horizontalCenter: parent.horizontalCenter }
        spacing: 14
        opacity: ov.shown
        Repeater {
          model: dk.minimizedShown
          delegate: Rectangle {
            required property var modelData
            width: 150; height: 96; radius: 10
            color: mh.hovered ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.09)
            border.color: Qt.rgba(1, 1, 1, 0.22)
            AppIcon { anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 } width: 44; height: 44; appId: Apps.classOf(parent.modelData) }
            Txt { anchors { bottom: parent.bottom; bottomMargin: 8; horizontalCenter: parent.horizontalCenter } width: parent.width - 16; horizontalAlignment: Text.AlignHCenter; text: parent.modelData.title || ""; color: "#ffffff"; font.pixelSize: Theme.small - 1 }
            HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { Apps.restore(parent.modelData); Shell.close() } }
          }
        }
      }
      // What was typed.
      Rectangle {
        visible: dk.query !== ""
        anchors { horizontalCenter: parent.horizontalCenter; top: strip.bottom; topMargin: 12 }
        width: qt.implicitWidth + 40; height: 32; radius: 16
        color: Qt.rgba(1, 1, 1, 0.16); border.color: Qt.rgba(1, 1, 1, 0.25)
        Sym { name: "search"; width: 12; height: 12; color: "#ffffff"; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } }
        Txt { id: qt; anchors.centerIn: parent; anchors.horizontalCenterOffset: 8; text: dk.query; color: "#ffffff" }
      }
      Txt {
        anchors { bottom: parent.bottom; bottomMargin: 40; horizontalCenter: parent.horizontalCenter }
        opacity: ov.shown * 0.75
        text: dk.app ? Apps.nameFor(dk.app) + " · click a window to go to it · Esc to close"
          : "Type to find a window · click one to go to it · drag it onto a desktop, or onto + for a new one · Esc to close"
        color: "#ffffff"; font.pixelSize: Theme.small
      }
    }
  }
}
