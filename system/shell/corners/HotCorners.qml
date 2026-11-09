import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core

// Hot Corners (System Settings > Windows & Desktops): push the pointer into a
// corner of a screen and something happens there. A short rest in the corner
// is needed (longer over a full-screen app), and nothing fires while a button
// is held (dragging a window) or while the screen is locked.
Scope {
  id: hc
  readonly property var actions: ({
    overview: () => Shell.toggle("overview"),
    expose: () => Quickshell.execDetached(["memora-shell", "desktop", "expose", ""]),
    desktop: () => Quickshell.execDetached(["memora-shell", "show-desktop"]),
    launchpad: () => Shell.toggle("launchpad"),
    notifications: s => { Shell.menuScreen = s; Shell.toggle("calendar") },
    control: s => { Shell.menuScreen = s; Shell.toggle("control") },
    ai: () => Quickshell.execDetached(["memora-ai", "window"]),
    lock: () => Quickshell.execDetached(["memora-lock"]),
    display: () => Quickshell.execDetached(["bash", "-c", "sleep 0.6; hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'"])
  })
  function fire(corner, screen) {
    const a = (Prefs.hotCorners || {})[corner]
    if (!a || !actions[a] || Shell.dragging) return
    actions[a](screen)
  }

  Variants {
    model: Quickshell.screens
    Scope {
      id: per
      required property var modelData
      Repeater {
        model: ["tl", "tr", "bl", "br"]
        delegate: PanelWindow {
          id: c
          required property string modelData
          screen: per.modelData
          visible: !!(Prefs.hotCorners || {})[modelData]
          anchors { top: modelData[0] === "t"; bottom: modelData[0] === "b"; left: modelData[1] === "l"; right: modelData[1] === "r" }
          implicitWidth: 3; implicitHeight: 3
          exclusionMode: ExclusionMode.Ignore
          color: "transparent"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.namespace: "memora-corner"
          HoverHandler {
            onHoveredChanged: if (hovered) dwell.restart(); else dwell.stop()
          }
          Timer { id: dwell; interval: Shell.fullscreenApp ? 450 : 160; onTriggered: hc.fire(c.modelData, per.modelData.name) }
        }
      }
    }
  }
}
