import QtQuick
import Quickshell
import qs.core

// A menu (or a small list) of an app as a little window of its own above it,
// as on a Mac: Hyprland frosts what is under it, the app's own window too
// (decoration:blur:popups), which it can't do for anything drawn inside a
// window; and it is kept on screen, even where it hangs out of the window.
// Put the card inside at 0,0; `item` and `at` say where it opens (in `item`).
// The app still closes it on a click outside (over its own window).
PopupWindow {
  id: mp
  property Item item
  property point at: Qt.point(0, 0)
  default property alias content: holder.data
  anchor.item: item
  anchor.rect.x: at.x
  anchor.rect.y: at.y
  anchor.adjustment: PopupAdjustment.All
  color: "transparent"
  implicitWidth: Math.max(1, holder.childrenRect.x + holder.childrenRect.width)
  implicitHeight: Math.max(1, holder.childrenRect.y + holder.childrenRect.height)
  Item { id: holder; anchors.fill: parent }
}
