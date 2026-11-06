import QtQuick
import qs.core

// A thick glass slider with its symbol inside the track, as in Control Center.
Item {
  id: s
  property real value: 0.5
  property string sym: "sound"
  signal moved(real v)
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
      color: Theme.dark ? "#f2f2f5" : "#ffffff"
      Behavior on width { enabled: !drag.active; NumberAnimation { duration: Theme.fast } }
    }
    Sym {
      name: s.sym
      level: s.value
      width: 15; height: 15
      anchors { left: parent.left; leftMargin: 7; verticalCenter: parent.verticalCenter }
      color: "#3a3a3f"
    }
  }
  function at(x) { return Math.max(0, Math.min(1, x / width)) }
  DragHandler {
    id: drag
    target: null
    xAxis.enabled: true; yAxis.enabled: false
    onCentroidChanged: if (active) s.moved(s.at(centroid.position.x))
  }
  TapHandler { onTapped: ev => s.moved(s.at(ev.position.x)) }
}
