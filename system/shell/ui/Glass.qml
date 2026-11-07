import QtQuick
import QtQuick.Effects
import qs.core

// A liquid-glass surface: translucent fill (the compositor blurs what is behind
// it), a bright hairline on the inside, a dark hairline outside, a soft shadow.
Item {
  id: g
  property real radius: Theme.radiusLarge
  property color fill: Theme.glass
  property bool shadow: true
  property real shadowSize: 28
  default property alias content: inner.data

  RectangularShadow {
    visible: g.shadow
    anchors.fill: parent
    radius: g.radius
    blur: g.shadowSize
    spread: -4
    offset.y: g.shadowSize * 0.35
    color: Theme.shadow
  }
  Rectangle {
    anchors.fill: parent
    radius: g.radius
    color: g.fill
    border.width: 1
    border.color: Theme.outline
  }
  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: g.radius - 1
    color: "transparent"
    border.width: 1
    border.color: Theme.edge
    opacity: 0.9
  }
  // Light catching the top edge.
  Rectangle {
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
    height: Math.min(parent.height / 2, 40)
    radius: g.radius - 1
    gradient: Gradient {
      GradientStop { position: 0; color: Qt.rgba(1, 1, 1, (Theme.dark ? 0.09 : 0.3) * Theme.shine) }
      GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
    }
  }
  Item { id: inner; anchors.fill: parent }
}
