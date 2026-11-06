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

  readonly property var builtIn: [
    { file: "", name: "Silk (follows appearance)" },
    { file: Theme.share + "/themes/light/wallpaper.png", name: "Silk Light" },
    { file: Theme.share + "/themes/dark/wallpaper.png", name: "Silk Dark" }
  ]

  Kit.Group {
    header: "Memora"
    Grid {
      Layout.fillWidth: true
      Layout.margins: 12
      columns: 3; spacing: 14
      Repeater { model: p.builtIn; delegate: Thumb { file: modelData.file; name: modelData.name } }
    }
  }
  Kit.Group {
    header: "Your pictures"
    footer: p.pictures.length ? "" : "Put images in the Pictures folder to see them here."
    Grid {
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
        source: "file://" + (file || (Theme.share + "/themes/" + Theme.mode + "/wallpaper.png"))
        sourceSize: Qt.size(340, 212); fillMode: Image.PreserveAspectCrop; asynchronous: true
      }
      TapHandler { onTapped: Prefs.set("wallpaper", file) }
    }
    Txt { width: 170; text: name; font.pixelSize: Theme.small; color: Theme.textDim; horizontalAlignment: Text.AlignHCenter }
  }
}
