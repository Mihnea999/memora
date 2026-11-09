import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  title: "About"
  Item {
    Layout.fillWidth: true
    implicitHeight: 200
    Column {
      anchors.centerIn: parent
      spacing: 8
      Image { anchors.horizontalCenter: parent.horizontalCenter; source: "file://" + Theme.share + "/themes/" + Theme.mode + "/logo.png"; width: 72; height: 72; sourceSize: Qt.size(144, 144) }
      Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Memora"; font.pixelSize: 26; font.weight: Font.Bold }
      Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Version " + Host.version; color: Theme.textDim }
    }
  }
  Kit.Group {
    Kit.Row { visible: Host.model !== ""; label: Host.isLaptop ? "Laptop" : "Computer"; Kit.Value { text: Host.model; width: 360; elide: Text.ElideRight } }
    Kit.Row { label: "Name"; Kit.Value { text: Host.hostname } }
    Kit.Row { label: "Processor"; Kit.Value { text: Host.cpu; width: 360; elide: Text.ElideLeft } }
    Kit.Row { label: "Memory"; Kit.Value { text: Host.memory } }
    Kit.Row { label: "Graphics"; Kit.Value { text: Host.gpu; width: 360; elide: Text.ElideLeft } }
    Kit.Row { label: "Storage"; Kit.Value { text: Host.disk } }
    Kit.Row { label: "Kernel"; Kit.Value { text: Host.kernel } }
    Kit.Row { label: "Up for"; last: true; Kit.Value { text: Host.uptime } }
  }
}
