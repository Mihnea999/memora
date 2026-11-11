import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.core
import qs.ui

// "Move & Resize" for apps that aren't Memora's: the title bar Memora draws for
// them (plugin/titlebar.cpp) says when the pointer rests on its green button,
// and the same panel as on Memora's own windows (ui/WindowControls) opens under it.
//   memora-shell layouts hover ADDRESS X Y   (X Y: the button's bottom-left, global)
//   memora-shell layouts leave | close
Scope {
  id: ly
  property string addr: ""
  property point at: Qt.point(0, 0)
  property bool onGreen: false
  property size minSize: Qt.size(0, 0)

  IpcHandler {
    target: "layouts"
    function hover(addr: string, x: int, y: int): void {
      ly.onGreen = true
      hideLater.stop()
      if (card.open && ly.addr === Apps.addrKey(addr)) return
      ly.addr = Apps.addrKey(addr); ly.at = Qt.point(x, y)
      sizes.running = true
      showLater.restart()
    }
    function leave(): void { ly.onGreen = false; showLater.stop(); hideLater.restart() }
    function close(): void { ly.onGreen = false; showLater.stop(); card.open = false }
  }
  Timer { id: showLater; interval: 450; onTriggered: { Shell.close(); card.open = true } }
  Timer { id: hideLater; interval: 500; onTriggered: if (!card.hovered && !ly.onGreen) card.open = false }
  Connections { target: Shell; function onOpenChanged() { if (Shell.open !== "") card.open = false } }

  // The window's smallest size, so the parts it can't shrink to are dimmed.
  Process {
    id: sizes
    command: ["hyprctl", "memora-sizes"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const w = JSON.parse(text).find(x => Apps.addrKey(x.address) === ly.addr)
          ly.minSize = w ? Qt.size(w.min[0], w.min[1]) : Qt.size(0, 0)
        } catch (e) { ly.minSize = Qt.size(0, 0) }
      }
    }
  }

  function pick(zone) {
    const a = "0x" + addr
    if (zone === "arrange") {
      Apps.dispatch('hl.dsp.focus({ window = "address:' + a + '" })')
      Quickshell.execDetached(["memora-window", "arrange"])
    } else Quickshell.execDetached(["memora-window", zone, a])
  }

  // The screen the button is on.
  readonly property var screen: {
    const s = Quickshell.screens
    for (let i = 0; i < s.length; i++)
      if (at.x >= s[i].x && at.x < s[i].x + s[i].width && at.y >= s[i].y && at.y < s[i].y + s[i].height) return s[i]
    return s.length ? s[0] : null
  }

  PanelWindow {
    id: wl
    screen: ly.screen
    visible: card.visible
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "memora-panel"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Only the panel takes the pointer: the bar and its green button stay reachable.
    mask: Region { item: card }

    LayoutsCard {
      id: card
      x: Math.min(ly.at.x - (ly.screen ? ly.screen.x : 0) - 6, wl.width - width - 8)
      y: Math.min(ly.at.y - (ly.screen ? ly.screen.y : 0) + 6, wl.height - height - 8)
      readonly property real sw: ly.screen ? ly.screen.width : 1920
      readonly property real sh: ly.screen ? ly.screen.height : 1080
      areaW: sw - (Prefs.dockPosition === "bottom" ? 20 : Prefs.dockSize + 40)
      areaH: sh - 50 - (Prefs.dockPosition === "bottom" ? Prefs.dockSize + 28 : 0)
      minSize: ly.minSize
      onHoveredChanged: if (hovered) hideLater.stop(); else hideLater.restart()
      onPicked: zone => ly.pick(zone)
    }
  }
}
