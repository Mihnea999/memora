import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  title: "Appearance"
  Kit.Group {
    Item {
      Layout.fillWidth: true
      implicitHeight: 170
      Row {
        anchors.centerIn: parent
        spacing: 26
        Repeater {
          model: [{ id: "light", name: "Light" }, { id: "dark", name: "Dark" }]
          delegate: Column {
            required property var modelData
            spacing: 8
            Rectangle {
              width: 150; height: 96; radius: 10
              border.width: Theme.mode === modelData.id ? 3 : 1
              border.color: Theme.mode === modelData.id ? Theme.accent : Theme.separator
              clip: true
              Image { anchors.fill: parent; anchors.margins: 3; source: "file://" + Theme.share + "/themes/" + modelData.id + "/wallpaper.jpg"; sourceSize: Qt.size(300, 190); fillMode: Image.PreserveAspectCrop }
              Rectangle { x: 14; y: 16; width: 74; height: 50; radius: 6; color: modelData.id === "dark" ? "#2a2a2e" : "#ffffff"; opacity: 0.92
                Row { x: 6; y: 6; spacing: 3; Repeater { model: ["#ff5f57", "#febc2e", "#28c840"]; delegate: Rectangle { required property string modelData; width: 5; height: 5; radius: 2.5; color: modelData } } } }
              TapHandler { onTapped: Quickshell.execDetached(["memora-theme", "set", modelData.id]) }
            }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; font.weight: Theme.mode === modelData.id ? Font.Bold : Font.Normal }
          }
        }
      }
    }
  }
  Kit.Group {
    footer: "Windows, the menu bar, the Dock and every Memora app follow the appearance. The font is JetBrains Mono everywhere."
    Kit.Row { label: "Accent colour"; last: true; Rectangle { width: 18; height: 18; radius: 9; color: Theme.accent; border.color: Theme.separator } }
  }
}
