import QtQuick
import Quickshell
import qs.core

// The top-left corner of a Memora app whose window is narrow: its sidebar is
// tucked away, so the window buttons move here, with a button that slides the
// sidebar in over the content (and out again).
Row {
  id: cb
  property var window
  property bool sideOpen: false
  signal toggled()
  signal closeRequested()
  spacing: 14
  WindowControls { anchors.verticalCenter: parent.verticalCenter; window: cb.window; onCloseRequested: cb.closeRequested() }
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: 28; height: 24; radius: 6
    color: cb.sideOpen ? Theme.pressed : (th.hovered ? Theme.hover : "transparent")
    Sym { anchors.centerIn: parent; name: "sidebar"; width: 16; height: 16; color: Theme.textDim }
    HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: cb.toggled() }
    Tip { text: cb.sideOpen ? "Hide the sidebar" : "Show the sidebar" }
  }
}
