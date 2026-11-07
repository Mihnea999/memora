import QtQuick
import qs.core

// A tooltip: put `Tip { text: "What this does" }` inside any button. It shows
// a moment after the pointer rests on the button, below it (above when there
// is no room), and hides as soon as the pointer leaves.
Item {
  id: tip
  property string text: ""
  property int delay: 550
  anchors.fill: parent
  z: 1000

  HoverHandler { id: hov; onHoveredChanged: if (hovered) wait.restart(); else { wait.stop(); tip.showing = false } }
  TapHandler { acceptedButtons: Qt.AllButtons; gesturePolicy: TapHandler.DragThreshold; onPressedChanged: if (pressed) { wait.stop(); tip.showing = false } }
  Timer { id: wait; interval: tip.delay; onTriggered: tip.showing = tip.text !== "" }
  property bool showing: false

  Rectangle {
    id: bubble
    // The window's root item (works in layer-shell panels too).
    readonly property var win: { let r = tip; while (r.parent) r = r.parent; return r }
    readonly property point at: tip.showing ? tip.mapToItem(win, 0, 0) : Qt.point(0, 0)
    readonly property bool above: at.y + tip.height + height + 12 > win.height
    width: label.implicitWidth + 18; height: label.implicitHeight + 10
    x: { const want = (tip.width - width) / 2; const winW = win ? win.width : 10000; return Math.max(-bubble.at.x + 6, Math.min(want, winW - bubble.at.x - width - 6)) }
    y: above ? -height - 6 : tip.height + 6
    radius: 8
    color: Theme.dark ? Qt.rgba(0.17, 0.17, 0.19, 0.97) : Qt.rgba(0.99, 0.99, 1, 0.98)
    border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.12)
    opacity: tip.showing ? 1 : 0
    visible: opacity > 0
    scale: tip.showing ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Theme.easing } }
    Text {
      id: label
      anchors.centerIn: parent
      text: tip.text
      color: Theme.text
      font.family: Theme.font; font.pixelSize: Theme.small
    }
  }
}
