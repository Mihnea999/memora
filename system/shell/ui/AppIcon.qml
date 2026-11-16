import QtQuick
import QtQuick.Effects
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
  // System Settings > Desktop & Dock > App icons: in colour, black and white,
  // or tinted with the accent colour (like a Mac's). styled: false keeps colour.
  property bool styled: true
  readonly property string look: styled ? Prefs.iconStyle : "color"
  layer.enabled: look !== "color"
  layer.smooth: true
  layer.effect: MultiEffect {
    saturation: a.look === "mono" ? -1 : 0
    contrast: a.look === "mono" ? 0.08 : 0
    colorization: a.look === "tinted" ? 0.85 : 0
    colorizationColor: Theme.accent
  }

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
      id: inner
      anchors.centerIn: parent
      width: parent.width * 0.56; height: width
      // Apps installed after the desktop started (App Store) aren't in the
      // icon theme's cache yet: look in their export folder directly.
      // A launcher may name a picture file instead (a game's own icon).
      readonly property string themed: a.name ? (a.name.charAt(0) === "/" ? "file://" + a.name : Quickshell.iconPath(a.name, true)) : ""
      Connections { target: a; function onNameChanged() { inner.tryN = 0 } }
      readonly property string exported: Quickshell.env("HOME") + "/.local/share/flatpak/exports/share/icons/hicolor/"
      property int tryN: 0
      source: a.own || a.name === "" ? "" : (themed !== "" ? themed : (["scalable/apps/" + a.name + ".svg", "256x256/apps/" + a.name + ".png", "128x128/apps/" + a.name + ".png"].map(x => "file://" + exported + x)[tryN] || Quickshell.iconPath("application-x-executable")))
      onStatusChanged: if (status === Image.Error && tryN < 3) tryN++
      sourceSize: Qt.size(192, 192)
      smooth: true; mipmap: true
    }
  }
}
