import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.core
import qs.ui

// Alt+Tab: open windows, most recent first. Keep Alt held and press Tab to move,
// let go of Alt to switch.
Scope {
  id: sw
  property bool open: false
  property int index: 0
  property var list: []

  function build() {
    const ws = Apps.windows.slice()
    ws.sort((a, b) => (a.lastIpcObject.focusHistoryID || 0) - (b.lastIpcObject.focusHistoryID || 0))
    // The window in front is always first, so one Tab goes to the one before it.
    const act = Hyprland.activeToplevel
    const i = act ? ws.findIndex(w => w.address === act.address) : -1
    if (i > 0) ws.unshift(ws.splice(i, 1)[0])
    list = ws
  }
  function step(d) {
    if (!open) { Hyprland.refreshToplevels(); build(); if (list.length < 1) return; open = true; index = list.length > 1 ? 1 : 0; return }
    index = (index + d + list.length) % list.length
  }
  function commit() {
    if (!open) return
    open = false
    const w = list[index]
    if (w) Apps.focus(w)
  }

  // Super or Alt let go (reported by the Memora plugin): finish switching.
  Connections {
    target: Hyprland
    function onRawEvent(ev) { if (ev.name === "memorakeyup" && sw.open) sw.commit() }
  }

  IpcHandler {
    target: "switcher"
    function next(): void { sw.step(1) }
    function prev(): void { sw.step(-1) }
    function commit(): void { sw.commit() }
    function cancel(): void { sw.open = false }
    // Super let go: finish switching, or (a tap on its own) open Apps.
    function superUp(): void { if (sw.open) sw.commit(); else Shell.toggle("launchpad") }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      visible: sw.open && modelData === (Hyprland.focusedMonitor ? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0] : Quickshell.screens[0])
      implicitWidth: Math.min(screen.width - 80, row.implicitWidth + 40)
      implicitHeight: 170
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
        }
      }

      Glass {
        anchors.fill: parent
        anchors.margins: 6
        radius: 26
        fill: Theme.glassStrong
        shadowSize: 30
        Row {
          id: row
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -10
          spacing: 8
          Repeater {
            model: sw.list
            delegate: Item {
              required property var modelData
              required property int index
              width: 112; height: 112
              Rectangle { anchors.fill: parent; radius: 22; color: index === sw.index ? Theme.pressed : "transparent" }
              AppIcon { anchors.centerIn: parent; width: 84; height: 84; appId: Apps.classOf(modelData) }
              TapHandler { onTapped: { sw.index = index; sw.commit() } }
            }
          }
        }
        Txt {
          anchors { bottom: parent.bottom; bottomMargin: 12; horizontalCenter: parent.horizontalCenter }
          width: parent.width - 40
          horizontalAlignment: Text.AlignHCenter
          text: sw.list[sw.index] ? (sw.list[sw.index].title || Apps.nameFor(Apps.classOf(sw.list[sw.index]))) : ""
          color: Theme.textDim
        }
      }
    }
  }
}
