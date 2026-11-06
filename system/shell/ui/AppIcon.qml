import QtQuick
import Quickshell
import qs.core

// An app icon on Memora's grid. Apps without a Memora icon get theirs placed on
// a light squircle tile, so every icon in the Dock and Launchpad shares a shape.
Item {
  id: a
  property string appId: ""
  property string iconName: ""          // overrides the desktop entry's icon
  readonly property string name: iconName !== "" ? iconName : Apps.iconNameFor(appId)
  readonly property bool own: Apps.nativeIcons.indexOf(name) >= 0

  Image {
    anchors.fill: parent
    visible: a.own
    source: a.own ? Quickshell.iconPath(a.name) : ""
    sourceSize: Qt.size(256, 256)
    smooth: true; mipmap: true
  }
  Item {
    anchors.fill: parent
    visible: !a.own
    Image {
      anchors.fill: parent
      source: "file://" + Theme.share + "/icons/tile.png"
      sourceSize: Qt.size(256, 256)
      smooth: true; mipmap: true
    }
    Image {
      anchors.centerIn: parent
      width: parent.width * 0.56; height: width
      source: a.own ? "" : Quickshell.iconPath(a.name, "application-x-executable")
      sourceSize: Qt.size(192, 192)
      smooth: true; mipmap: true
    }
  }
}
