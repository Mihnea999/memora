import QtQuick
import Quickshell.Hyprland

// Closes a menu or panel when you click outside it. The grab is armed a moment
// after the panel appears: armed sooner, the panel's own surface is not part of
// it yet, and a click inside would count as outside.
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
}
