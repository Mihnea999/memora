import QtQuick
import Quickshell.Hyprland

// Closes a menu or panel when you click outside it, when a window takes the
// focus, or when the desktop changes. The grab is armed a moment after the
// panel appears: armed sooner, the panel's own surface is not part of it yet,
// and a click inside would count as outside.
Item {
  id: oc
  property bool when: false
  property var windows: []
  signal outside()
  property bool armed: false
  onWhenChanged: { armed = false; if (when) arm.restart() }
  Timer { id: arm; interval: 150; onTriggered: oc.armed = oc.when }
  HyprlandFocusGrab {
    active: oc.when && oc.armed
    windows: oc.windows
    onCleared: if (oc.when) oc.outside()
  }
  // The grab only sees clicks; focus can also move by keyboard (Alt-Tab, a
  // binding, a window that opens) or the desktop can switch under the panel.
  // "activewindow" with no class is the desktop or a shell surface: ignore it.
  Connections {
    target: Hyprland
    enabled: oc.when && oc.armed
    function onRawEvent(ev) {
      if (ev.name === "workspace" || (ev.name === "activewindow" && ev.data.replace(/,/g, "") !== "")) oc.outside()
    }
  }
}
