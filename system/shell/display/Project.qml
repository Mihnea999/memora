import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Choose how several screens work together: Super+P, or by itself when a
// screen is plugged in. Extend, Mirror, This Screen Only, Other Screen Only.
// Arrow keys or Super+P again to move, Return or click to choose.
Scope {
  id: pj
  property bool open: false
  property int sel: 0
  property string current: "extend"
  readonly property var choices: [
    { id: "extend", name: "Extend", sub: "One big desktop across both" },
    { id: "mirror", name: "Mirror", sub: "The same picture on each" },
    { id: "main", name: "This Screen Only", sub: "Turn the other one off" },
    { id: "second", name: "Other Screen Only", sub: "Turn this one off" }
  ]
  readonly property int screens: Hyprland.monitors.values.length

  Process {
    id: state
    command: ["bash", "-c", "jq -r '.mode // \"extend\"' ~/.config/memora/displays.json 2>/dev/null || echo extend"]
    stdout: StdioCollector { onStreamFinished: { pj.current = text.trim() || "extend"; pj.sel = Math.max(0, pj.choices.findIndex(c => c.id === pj.current)) } }
  }
  function show() { if (open) { sel = (sel + 1) % choices.length; hideLater.restart(); return } Shell.close(); state.running = true; open = true; hideLater.restart() }
  function pick(i) { const c = choices[i]; open = false; current = c.id; Quickshell.execDetached(["memora-display", "mode", c.id]) }
  Timer { id: hideLater; interval: 9000; onTriggered: pj.open = false }

  IpcHandler {
    target: "display"
    function project(): void { pj.show() }
  }
  // A screen arrived: ask how to use it.
  Connections {
    target: Hyprland
    function onRawEvent(ev) { if (ev.name === "monitoraddedv2" || ev.name === "monitoradded") Qt.callLater(() => { Quickshell.execDetached(["memora-display", "apply"]); pj.show() }) }
  }

  PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    visible: pj.open || fade.running
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "memora-dialog"
    WlrLayershell.keyboardFocus: pj.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    property real shown: pj.open ? 1 : 0
    Behavior on shown { NumberAnimation { id: fade; duration: Prefs.motion(pj.open ? 320 : 180); easing.type: pj.open ? Easing.OutQuint : Easing.InCubic } }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.25); opacity: win.shown }
    TapHandler { onTapped: pj.open = false }

    Glass {
      id: card
      anchors.centerIn: parent
      width: row.implicitWidth + 40; height: row.implicitHeight + 76
      radius: 26
      fill: Theme.glassStrong
      opacity: win.shown
      scale: 0.94 + 0.06 * win.shown
      focus: pj.open
      Keys.onLeftPressed: pj.sel = (pj.sel + pj.choices.length - 1) % pj.choices.length
      Keys.onRightPressed: pj.sel = (pj.sel + 1) % pj.choices.length
      Keys.onReturnPressed: pj.pick(pj.sel)
      Keys.onEscapePressed: pj.open = false
      TapHandler {}
      Txt { x: 20; y: 16; text: pj.screens > 1 ? "Screens" : "Screens · only one connected"; font.weight: Font.Bold; color: Theme.textDim; font.pixelSize: Theme.small }
      RowLayout {
        id: row
        x: 20; y: 46
        spacing: 12
        Repeater {
          model: pj.choices
          delegate: Rectangle {
            required property var modelData
            required property int index
            readonly property bool on: index === pj.sel
            implicitWidth: 168; implicitHeight: 164
            radius: 18
            color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.3 : 0.16) : (ch.hovered ? Theme.hover : "transparent")
            border.width: on ? 2 : 0; border.color: Theme.accent
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            // Two little screens showing the idea.
            Item {
              id: pic
              anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 22 }
              width: 120; height: 62
              readonly property color lit: Theme.accent
              readonly property color off: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
              Rectangle { x: modelData.id === "mirror" ? 4 : 0; y: 6; width: 56; height: 38; radius: 6
                color: modelData.id === "second" ? pic.off : pic.lit; opacity: modelData.id === "extend" ? 1 : 0.95
                Rectangle { anchors.centerIn: parent; width: 16; height: 3; radius: 1.5; color: "#ffffff"; visible: modelData.id === "mirror" } }
              Rectangle { x: 64; y: 6; width: 56; height: 38; radius: 6
                color: modelData.id === "main" ? pic.off : (modelData.id === "extend" ? Qt.lighter(pic.lit, 1.3) : pic.lit)
                Rectangle { anchors.centerIn: parent; width: 16; height: 3; radius: 1.5; color: "#ffffff"; visible: modelData.id === "mirror" } }
              Rectangle { x: 52; y: 26; width: 24; height: 3; radius: 1.5; color: Theme.textFaint; visible: modelData.id === "extend" }
              Rectangle { x: 22; y: 48; width: 14; height: 5; radius: 2; color: pic.off }
              Rectangle { x: 85; y: 48; width: 14; height: 5; radius: 2; color: pic.off }
            }
            Column {
              anchors { left: parent.left; right: parent.right; top: pic.bottom; topMargin: 14; leftMargin: 10; rightMargin: 10 }
              spacing: 2
              Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.name; font.weight: Font.Bold }
              Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.sub; color: Theme.textDim; font.pixelSize: Theme.small - 0.5; wrapMode: Text.Wrap }
            }
            HoverHandler { id: ch; onHoveredChanged: if (hovered) pj.sel = index }
            TapHandler { onTapped: pj.pick(index) }
          }
        }
      }
    }
  }
}
