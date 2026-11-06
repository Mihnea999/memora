import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

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

  property string file: Prefs.wallpaper !== "" ? Prefs.wallpaper : Theme.share + "/themes/" + (Theme.dark ? "dark" : "light") + "/wallpaper.jpg"
  property bool flip: false

  Image { id: a; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(w.width, w.height); opacity: w.flip ? 0 : 1; Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } } }
  Image { id: b; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(w.width, w.height); opacity: w.flip ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } } }

  Component.onCompleted: a.source = "file://" + file
  onFileChanged: {
    if (flip) a.source = "file://" + file; else b.source = "file://" + file
    flip = !flip
  }
}
