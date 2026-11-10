import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.core
import qs.ui

// Switching, as on a Mac and a PC together:
//   Super+Tab   apps, most recent first (hold Super: Tab moves, Q quits the
//               chosen app, H hides it, ` or ↓ shows its windows); let go to switch
//   Alt+Tab     windows, with live pictures: this desktop's first, then the
//               others, minimized ones last
//   Super+`     the windows of the app in front
// Hover picks, click switches. Sizes follow the screen.
Scope {
  id: sw
  property bool open: false
  property bool superAlone: true      // Super has been used on its own since it went down
  property string mode: "windows"     // windows | apps
  property string onlyApp: ""         // windows mode for one app
  property int index: 0
  property var list: []               // windows, or [{ cls, wins }] for apps

  readonly property var recent: {
    const ws = Apps.windows.filter(w => Apps.helperClasses.indexOf(Apps.classOf(w)) < 0)
    return ws.sort((a, b) => (a.lastIpcObject.focusHistoryID ?? 99) - (b.lastIpcObject.focusHistoryID ?? 99))
  }
  function buildWindows(cls) {
    const cur = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    let ws = recent.filter(w => !cls || Apps.sameApp(Apps.classOf(w), cls))
    const here = ws.filter(w => !Apps.isMinimized(w) && w.workspace && w.workspace.id === cur)
    const there = ws.filter(w => !Apps.isMinimized(w) && !(w.workspace && w.workspace.id === cur))
    const mini = ws.filter(w => Apps.isMinimized(w))
    ws = here.concat(there).concat(mini)
    // The window in front first, so one Tab goes to the one before it.
    const act = Hyprland.activeToplevel
    const i = act ? ws.findIndex(w => w.address === act.address) : -1
    if (i > 0) ws.unshift(ws.splice(i, 1)[0])
    return ws
  }
  function buildApps() {
    const out = [], seen = {}
    recent.forEach(w => {
      const c = Apps.classOf(w)
      if (seen[c] !== undefined) { out[seen[c]].wins.push(w); return }
      seen[c] = out.length
      out.push({ cls: c, wins: [w] })
    })
    const act = Hyprland.activeToplevel
    const ac = act ? Apps.classOf(Apps.windows.find(x => x.address === act.address) || act) : ""
    const i = out.findIndex(a => a.cls === ac)
    if (i > 0) out.unshift(out.splice(i, 1)[0])
    return out
  }
  function start(m, cls) {
    Hyprland.refreshToplevels()
    mode = m; onlyApp = cls || ""
    list = m === "apps" ? buildApps() : buildWindows(onlyApp)
    if (list.length < 1) return false
    open = true
    index = list.length > 1 ? 1 : 0
    return true
  }
  function step(d, m) {
    if (!open) { start(m || "windows"); return }
    if (list.length) index = (index + d + list.length) % list.length
  }
  // In apps mode: the chosen app's windows instead.
  function expand() {
    if (mode !== "apps" || !list[index]) return
    const c = list[index].cls
    mode = "windows"; onlyApp = c
    list = buildWindows(c)
    index = 0
  }
  function commit() {
    if (!open) return
    open = false
    const e = list[index]
    if (!e) return
    if (mode === "apps") Apps.activate(e.cls)
    else Apps.focus(e)
  }
  // Q and H while choosing an app (Super+Q / Super+H come here through the shell).
  readonly property string chosenApp: open && mode === "apps" && list[index] ? list[index].cls : ""
  onChosenAppChanged: Shell.switcherApp = chosenApp
  function quitChosen() {
    const c = chosenApp; if (!c) return
    Apps.quit(c)
    list = list.filter(a => a.cls !== c)
    if (!list.length) { open = false; return }
    index = Math.min(index, list.length - 1)
  }
  function hideChosen() {
    const c = chosenApp; if (!c) return
    Apps.windowsOf(c).filter(x => !Apps.isMinimized(x)).forEach(x => Apps.minimize(x.address))
    step(1)
  }

  // Super or Alt let go (reported by the Memora plugin): finish switching.
  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      if (ev.name === "memorakeyup" && sw.open) sw.commit()
      // Super went down: not used with anything yet. A key or a click with it
      // (Super+drag moves a window) means letting go isn't a tap.
      else if (ev.name === "memorakeydown") sw.superAlone = true
      else if (ev.name === "memorachord") sw.superAlone = false
    }
  }
  Connections {
    target: Shell
    function onSwitcherActionChanged() {
      if (Shell.switcherAction === "quit") sw.quitChosen()
      else if (Shell.switcherAction === "hide") sw.hideChosen()
      Shell.switcherAction = ""
    }
  }

  IpcHandler {
    target: "switcher"
    function next(): void { sw.step(1, "windows") }
    function prev(): void { sw.step(-1, "windows") }
    function nextApp(): void { sw.step(1, "apps") }
    function prevApp(): void { sw.step(-1, "apps") }
    // Super+`: the windows of the app in front (or of the chosen app).
    function appWindows(): void {
      if (sw.open && sw.mode === "apps") return sw.expand()
      if (sw.open) return sw.step(1)
      const act = Hyprland.activeToplevel
      if (!act) return
      sw.start("windows", Apps.classOf(Apps.windows.find(x => x.address === act.address) || act))
    }
    function commit(): void { sw.commit() }
    function cancel(): void { sw.open = false }
    // Super let go: finish switching, or (a tap on its own) open Apps.
    function superChord(): void { sw.superAlone = false; Shell.superChord() }
    function superUp(): void { if (sw.open) sw.commit(); else if (sw.superAlone && Date.now() - Shell.sheetClosedAt > 700) Shell.toggle("launchpad") }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: sw.open && modelData === (Hyprland.focusedMonitor ? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0] : Quickshell.screens[0])
      readonly property real maxW: screen.width - 80
      // Apps: icons as big as fit. Windows: pictures about a sixth of the screen tall.
      readonly property real iconSize: Math.max(48, Math.min(96, (maxW - 60) / Math.max(1, sw.list.length) - 16))
      readonly property real thumbH: Math.max(100, Math.min(200, screen.height * 0.17))
      implicitWidth: Math.min(maxW, (sw.mode === "apps" ? appRow.implicitWidth : cards.implicitW) + 84)
      implicitHeight: sw.mode === "apps" ? iconSize + 84 : Math.min(screen.height - 160, cards.implicitHeight + 76)
      exclusiveZone: 0
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-switcher"
      // While open it has the keyboard, to see the held key (Super or Alt) go up:
      // that finishes the switch. Tab presses still reach the compositor's binds.
      WlrLayershell.keyboardFocus: sw.open && visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      Item {
        id: keys
        anchors.fill: parent
        focus: sw.open
        Connections { target: sw; function onOpenChanged() { if (sw.open) Qt.callLater(() => keys.forceActiveFocus()) } }
        Keys.onReleased: ev => {
          if ([Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Alt, Qt.Key_AltGr].indexOf(ev.key) >= 0) sw.commit()
        }
        Keys.onPressed: ev => {
          if (ev.key === Qt.Key_Escape) sw.open = false
          else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Tab) sw.step(1)
          else if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Backtab) sw.step(-1)
          else if (ev.key === Qt.Key_Return) sw.commit()
          else if (sw.mode === "apps" && (ev.key === Qt.Key_Down || ev.key === Qt.Key_QuoteLeft)) sw.expand()
          else if (sw.mode === "apps" && ev.key === Qt.Key_Q) sw.quitChosen()
          else if (sw.mode === "apps" && ev.key === Qt.Key_H) sw.hideChosen()
          else if (sw.mode === "windows" && ev.key === Qt.Key_Down) sw.step(Math.max(1, cards.perRow))
          else if (sw.mode === "windows" && ev.key === Qt.Key_Up) sw.step(-Math.max(1, cards.perRow))
        }
      }

      Glass {
        anchors.fill: parent
        anchors.margins: 6
        radius: 26
        fill: Theme.glassStrong

        // ---- apps
        Row {
          id: appRow
          visible: sw.mode === "apps"
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -10
          spacing: 8
          Repeater {
            model: sw.mode === "apps" ? sw.list : []
            delegate: Item {
              id: ac
              required property var modelData
              required property int index
              width: win.iconSize + 28; height: win.iconSize + 28
              Rectangle { anchors.fill: parent; radius: 22; color: ac.index === sw.index ? Theme.pressed : "transparent" }
              AppIcon {
                anchors.centerIn: parent; width: win.iconSize; height: win.iconSize; appId: ac.modelData.cls
                opacity: ac.modelData.wins.every(w => Apps.isMinimized(w)) ? 0.55 : 1
              }
              // How many windows it has.
              Rectangle {
                visible: ac.modelData.wins.length > 1
                anchors { right: parent.right; top: parent.top; margins: 8 }
                width: Math.max(20, cnt.implicitWidth + 10); height: 20; radius: 10
                color: Theme.accent
                Txt { id: cnt; anchors.centerIn: parent; text: ac.modelData.wins.length; color: "#ffffff"; font.pixelSize: Theme.small; font.weight: Font.Bold }
              }
              HoverHandler { onHoveredChanged: if (hovered) sw.index = ac.index }
              TapHandler { onTapped: { sw.index = ac.index; sw.commit() } }
            }
          }
        }

        // ---- windows
        Flickable {
          visible: sw.mode === "windows"
          anchors { fill: parent; margins: 18; bottomMargin: 46 }
          contentHeight: cards.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Flow {
            id: cards
            width: Math.min(parent.width, implicitW)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14
            readonly property var widths: (sw.mode === "windows" ? sw.list : []).map(w => win.cardW(w))
            readonly property real implicitW: Math.min(win.maxW - 84, widths.reduce((a, b) => a + b + 14, 0))
            readonly property int perRow: Math.max(1, Math.floor((width + 14) / ((widths[0] || 200) + 14)))
            Repeater {
              model: sw.mode === "windows" ? sw.list : []
              delegate: Item {
                id: wc
                required property var modelData
                required property int index
                readonly property bool mini: Apps.isMinimized(modelData)
                readonly property bool sel: index === sw.index
                width: win.cardW(modelData); height: win.thumbH
                Rectangle {
                  id: frame
                  anchors.fill: parent
                  radius: 12; clip: true
                  color: Theme.field
                  border.width: wc.sel ? 3 : 1
                  border.color: wc.sel ? Theme.accent : Theme.separator
                  opacity: wc.mini ? 0.6 : 1
                  ScreencopyView {
                    anchors.fill: parent; anchors.margins: 3
                    captureSource: sw.open && !wc.mini && wc.modelData.wayland ? wc.modelData.wayland : null
                    live: sw.open && sw.list.length <= 12
                  }
                  AppIcon { visible: wc.mini; anchors.centerIn: parent; width: 56; height: 56; appId: Apps.classOf(wc.modelData) }
                }
                AppIcon { anchors { left: parent.left; bottom: parent.bottom; margins: -6 } width: 30; height: 30; appId: Apps.classOf(wc.modelData) }
                // Another desktop: say which.
                Rectangle {
                  readonly property int d: wc.modelData.workspace ? wc.modelData.workspace.id : 0
                  visible: !wc.mini && d > 0 && Hyprland.focusedWorkspace && d !== Hyprland.focusedWorkspace.id
                  anchors { right: parent.right; top: parent.top; margins: 8 }
                  width: dl.implicitWidth + 14; height: 20; radius: 10; color: Theme.glassSolid
                  Txt { id: dl; anchors.centerIn: parent; text: "Desktop " + parent.d; font.pixelSize: Theme.small - 1 }
                }
                scale: wc.sel ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: Theme.fast } }
                HoverHandler { onHoveredChanged: if (hovered) sw.index = wc.index }
                TapHandler { onTapped: { sw.index = wc.index; sw.commit() } }
              }
            }
          }
        }

        Txt {
          anchors { bottom: parent.bottom; bottomMargin: 14; horizontalCenter: parent.horizontalCenter }
          width: parent.width - 40
          horizontalAlignment: Text.AlignHCenter
          font.weight: sw.mode === "apps" ? Font.Bold : Font.Normal
          text: {
            const e = sw.list[sw.index]
            if (!e) return ""
            if (sw.mode === "apps") return Apps.nameFor(e.cls)
            return e.title || Apps.nameFor(Apps.classOf(e))
          }
          color: sw.mode === "apps" ? Theme.text : Theme.textDim
        }
      }

      // A window's card keeps its shape (within reason).
      function cardW(w) {
        const o = w && w.lastIpcObject
        const r = o && o.size && o.size[1] > 0 ? o.size[0] / o.size[1] : 1.6
        return thumbH * Math.max(0.6, Math.min(2.2, r))
      }
    }
  }
}
