import QtQuick
import qs.core

// A thick glass slider with its symbol inside the track, as in Control Center.
Item {
  id: s
  property real value: 0.5
  property string sym: "sound"
  // Muted: the level stays where it was but greys out, with "Muted" on it.
  property bool muted: false
  // The symbol is a button (mute on/off) instead of part of the track.
  property bool symToggles: false
  signal moved(real v)
  signal symClicked()
  implicitHeight: 28
  implicitWidth: 260

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
    clip: true
    Rectangle {
      width: Math.max(track.height, track.width * s.value)
      height: parent.height
      radius: height / 2
      color: s.muted ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.16)) : (Theme.dark ? "#f2f2f5" : "#ffffff")
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      Behavior on width { enabled: !drag.active; NumberAnimation { duration: Theme.fast } }
    }
    Sym {
      name: s.sym
      level: s.value
      width: 15; height: 15
      anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
      color: s.muted ? (Theme.dark ? "#ff6961" : Theme.red) : "#3a3a3f"
    }
    Txt {
      visible: s.muted
      anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
      text: "Muted"; color: Theme.textDim; font.pixelSize: Theme.small; font.weight: Font.Bold
    }
  }
  function at(x) { return Math.max(0, Math.min(1, x / width)) }
  DragHandler {
    id: drag
    target: null
    xAxis.enabled: true; yAxis.enabled: false
    onCentroidChanged: if (active) s.moved(s.at(centroid.position.x))
  }
  TapHandler { onTapped: ev => { if (s.symToggles && ev.position.x < s.height + 4) s.symClicked(); else s.moved(s.at(ev.position.x)) } }
  HoverHandler { cursorShape: s.symToggles && point.position.x < s.height + 4 ? Qt.PointingHandCursor : Qt.ArrowCursor }
}
