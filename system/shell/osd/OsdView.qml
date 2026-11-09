import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.ui

// Volume and brightness feedback: a glass pill near the bottom of the screen.
PanelWindow {
  id: osd
  required property var modelData
  screen: modelData
  visible: shown > 0
  anchors { bottom: true }
  margins { bottom: Shell.bottomInset + 6 }
  implicitWidth: 260
  implicitHeight: 70
  exclusiveZone: 0
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "memora-osd"
  mask: Region {}

  property string kind: Osd.kind
  property real shown: Osd.visible ? 1 : 0
  Behavior on shown { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }

  Glass {
    anchors.centerIn: parent
    width: 230; height: 48
    radius: 24
    fill: Theme.glassStrong
    opacity: osd.shown
    scale: 0.94 + 0.06 * osd.shown
    Sym {
      id: s
      anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
      width: 18; height: 18
      name: Osd.kind === "brightness" ? "sun" : (Osd.muted ? "sound-off" : "sound")
      level: Osd.value
    }
    Rectangle {
      anchors { left: s.right; leftMargin: 12; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
      height: 6; radius: 3
      color: Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.1)
      Rectangle {
        width: parent.width * (Osd.muted ? 0 : Osd.value); height: parent.height; radius: 3
        color: Theme.text
        Behavior on width { NumberAnimation { duration: Theme.fast } }
      }
    }
  }
}
