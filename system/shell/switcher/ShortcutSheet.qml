import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Hold Super on its own for a second: a sheet of the shortcuts that go with it
// (from Hyprland's binds and their descriptions, like Help > Keyboard
// Shortcuts), grouped. It goes when Super is let go or another key is pressed.
Scope {
  id: ks
  property bool open: false
  property var groups: []
  property bool wanted: false        // Super is still held since the sheet was asked for
  Timer { id: hold; interval: 1000; onTriggered: if (Shell.open === "" && !Shell.dragging) { ks.wanted = true; binds.running = true } }
  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      if (ev.name === "memorakeydown") hold.restart()
      else if (ev.name === "memorachord") { hold.stop(); ks.close() }
      else if (ev.name === "memorakeyup" && ev.data === "super") { hold.stop(); ks.close() }
    }
  }
  Connections { target: Shell; function onSuperChord() { hold.stop(); ks.close() } }
  function close() { wanted = false; if (open) { open = false; Shell.sheetClosedAt = Date.now() } }
  readonly property var mods: [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]]
  Process {
    id: binds
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        let list; try { list = JSON.parse(text) } catch (e) { return }
        const seen = {}, g = { "Windows": [], "Desktops": [], "Apps and search": [], "Capture and more": [] }
        list.filter(b => b.has_description && (b.modmask & 64) && b.key !== "SUPER_L" && !seen[b.description] && (seen[b.description] = true)).forEach(b => {
          const keys = ks.mods.filter(m => b.modmask & m[0]).map(m => m[1]).concat([b.key.replace(/^(\w)(\w*)$/, (x, a, r) => a.toUpperCase() + r.toLowerCase())
            .replace("Left", "←").replace("Right", "→").replace("Up", "↑").replace("Down", "↓").replace("Grave", "`")]).join("+")
          const d = b.description
          const k = /desktop|Mission/i.test(d) ? "Desktops" : /window|screen|Full|Minimize|Center|Tile|Arrange|top|Hide|Quit|Close|docked|half|quarter/i.test(d) ? "Windows"
            : /Screenshot|Lock|Reload|Volume|Bright|Power/i.test(d) ? "Capture and more" : "Apps and search"
          g[k].push({ keys: keys, text: d })
        })
        ks.groups = Object.keys(g).filter(k => g[k].length).map(k => ({ title: k, items: g[k] }))
        if (ks.wanted) ks.open = true
      }
    }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      readonly property bool here: Hyprland.focusedMonitor ? modelData.name === Hyprland.focusedMonitor.name : modelData === Quickshell.screens[0]
      visible: here && (ks.open || fade.running)
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-dialog"
      mask: Region {}
      property real shown: ks.open ? 1 : 0
      Behavior on shown { NumberAnimation { id: fade; duration: Theme.normal; easing.type: Theme.easing } }
      Glass {
        anchors.centerIn: parent
        width: Math.min(win.width - 80, grid.implicitWidth + 56)
        height: Math.min(win.height - 120, grid.implicitHeight + 70)
        radius: 26
        fill: Theme.glassStrong
        shadowSize: 40
        opacity: win.shown
        scale: 0.96 + 0.04 * win.shown
        clip: true
        Txt { x: 28; y: 20; text: "Shortcuts with Super"; font.weight: Font.Bold; font.pixelSize: Theme.large }
        GridLayout {
          id: grid
          x: 28; y: 54
          columns: Math.max(1, Math.min(ks.groups.length, Math.floor((win.width - 140) / 340)))
          columnSpacing: 36; rowSpacing: 18
          Repeater {
            model: ks.groups
            delegate: ColumnLayout {
              required property var modelData
              Layout.alignment: Qt.AlignTop
              spacing: 5
              Txt { text: modelData.title; color: Theme.textDim; font.weight: Font.Bold; font.pixelSize: Theme.small }
              Repeater {
                model: modelData.items
                delegate: RowLayout {
                  required property var modelData
                  spacing: 12
                  Txt { Layout.preferredWidth: 130; text: modelData.keys; color: Theme.accent; font.pixelSize: Theme.small }
                  Txt { Layout.preferredWidth: 190; text: modelData.text; font.pixelSize: Theme.small; elide: Text.ElideRight }
                }
              }
            }
          }
        }
      }
    }
  }
}
