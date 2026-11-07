import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Wallpaper"
  property var pictures: []
  Kit.Cmd { id: find; onDone: out => p.pictures = out.split("\n").filter(l => l) }
  Component.onCompleted: find.exec(["bash", "-c", "find \"$HOME/Pictures\" -maxdepth 2 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) 2>/dev/null | head -40"])

  readonly property var sets: [["ember", "Ember"], ["tide", "Tide"], ["horizon", "Horizon"], ["dunes", "Dunes"], ["silk", "Silk"]]

  Kit.Group {
    header: "Memora"
    footer: "Each one has a light and a dark version and follows the appearance."
    Grid {
      id: setsGrid
      Layout.fillWidth: true
      Layout.margins: 12
      columns: 5; spacing: 12
      readonly property real tw: Math.floor((width - 4 * spacing) / 5)
      Repeater {
        model: p.sets
        delegate: Column {
          required property var modelData
          readonly property bool on: Prefs.wallpaper === "" && Prefs.wallpaperSet === modelData[0]
          spacing: 6
          Rectangle {
            width: setsGrid.tw; height: Math.round(setsGrid.tw * 0.64); radius: 9
            border.width: parent.on ? 3 : 1
            border.color: parent.on ? Theme.accent : Theme.separator
            clip: true
            scale: wh.hovered ? 1.03 : 1
            Behavior on scale { NumberAnimation { duration: Theme.fast } }
            // Half light, half dark.
            Image { x: 3; y: 3; width: (parent.width - 6) / 2; height: parent.height - 6; source: "file://" + Theme.share + "/wallpapers/" + modelData[0] + "-light.jpg"; sourceSize: Qt.size(270, 170); fillMode: Image.PreserveAspectCrop; horizontalAlignment: Image.AlignLeft; asynchronous: true }
            Image { x: parent.width / 2; y: 3; width: (parent.width - 6) / 2; height: parent.height - 6; source: "file://" + Theme.share + "/wallpapers/" + modelData[0] + "-dark.jpg"; sourceSize: Qt.size(270, 170); fillMode: Image.PreserveAspectCrop; horizontalAlignment: Image.AlignRight; asynchronous: true }
            HoverHandler { id: wh }
            TapHandler { onTapped: { Prefs.set("wallpaper", ""); Prefs.set("wallpaperSet", modelData[0]) } }
          }
          Txt { width: setsGrid.tw; text: modelData[1]; horizontalAlignment: Text.AlignHCenter; font.weight: parent.on ? Font.Bold : Font.Normal; font.pixelSize: Theme.small + 0.5 }
        }
      }
    }
  }
  Kit.Group {
    header: "Your pictures"
    footer: p.pictures.length ? "" : "Put images in the Pictures folder to see them here."
    Grid {
      visible: p.pictures.length > 0
      Layout.fillWidth: true
      Layout.margins: 12
      columns: 3; spacing: 14
      Repeater { model: p.pictures; delegate: Thumb { file: modelData; name: modelData.split("/").pop() } }
    }
  }

  component Thumb: Column {
    property string file
    property string name
    spacing: 6
    Rectangle {
      width: 170; height: 106; radius: 9
      border.width: Prefs.wallpaper === file ? 3 : 1
      border.color: Prefs.wallpaper === file ? Theme.accent : Theme.separator
      clip: true
      Image {
        anchors.fill: parent; anchors.margins: 3
        source: "file://" + file
        sourceSize: Qt.size(340, 212); fillMode: Image.PreserveAspectCrop; asynchronous: true
      }
      TapHandler { onTapped: Prefs.set("wallpaper", file) }
    }
    Txt { width: 170; text: name; font.pixelSize: Theme.small; color: Theme.textDim; horizontalAlignment: Text.AlignHCenter }
  }
}
