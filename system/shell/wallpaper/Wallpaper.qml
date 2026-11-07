import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.ui
import qs.widgets

// Desktop picture. Cross-fades when the appearance changes.
PanelWindow {
  id: w
  required property var modelData
  screen: modelData
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.namespace: "memora-wallpaper"
  color: "black"

  property string file: Theme.wallpaper
  property bool flip: false

  Image { id: a; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(w.width, w.height); opacity: w.flip ? 0 : 1; Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } } }
  Image { id: b; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(w.width, w.height); opacity: w.flip ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } } }

  // Widgets, and the desktop's own menu (right-click on empty space).
  Widgets { id: widgets; visible: w.modelData === Quickshell.screens[0] }
  property point menuAt: Qt.point(-1, -1)
  TapHandler {
    acceptedButtons: Qt.RightButton
    onTapped: ev => w.menuAt = ev.position
  }
  TapHandler { onTapped: w.menuAt = Qt.point(-1, -1) }
  MenuPanel {
    visible: w.menuAt.x >= 0
    x: Math.min(w.menuAt.x, w.width - width - 8); y: Math.min(w.menuAt.y, w.height - height - 8)
    width: implicitWidth; height: implicitHeight
    items: [
      { text: "Edit Widgets…", action: () => widgets.editing = true },
      { separator: true },
      { text: "Change Wallpaper…", action: () => Apps.run("memora-settings wallpaper") },
      { text: "Display Settings…", action: () => Apps.run("memora-settings displays") }
    ]
    onPicked: item => { const run = item.action; w.menuAt = Qt.point(-1, -1); Qt.callLater(run) }
  }

  Component.onCompleted: a.source = "file://" + file
  onFileChanged: {
    if (flip) a.source = "file://" + file; else b.source = "file://" + file
    flip = !flip
  }
}
