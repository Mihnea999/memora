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

  IpcHandler {
    target: "switcher"
    function next(): void { sw.step(1) }
    function prev(): void { sw.step(-1) }
    function commit(): void { sw.commit() }
    function cancel(): void { sw.open = false }
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
