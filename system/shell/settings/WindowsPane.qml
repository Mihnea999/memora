import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Windows & Desktops"

  // A small picture of each way to dock a window.
  component Idea: ColumnLayout {
    property string name
    property string how
    property var parts: []           // [x, y, w, h] in 0..1, the lit ones
    spacing: 6
    Rectangle {
      Layout.alignment: Qt.AlignHCenter
      width: 112; height: 70; radius: 8
      color: Theme.field; border.color: Theme.separator
      Repeater {
        model: parent.parent.parts
        delegate: Rectangle {
          required property var modelData
          x: 4 + modelData[0] * 104; y: 4 + modelData[1] * 62
          width: modelData[2] * 104 - 3; height: modelData[3] * 62 - 3
          radius: 4; color: Theme.accent; opacity: 0.85
        }
      }
    }
    Txt { Layout.alignment: Qt.AlignHCenter; text: parent.name; font.weight: Font.Bold; font.pixelSize: Theme.small + 0.5 }
    Txt { Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 130; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: parent.how; color: Theme.textDim; font.pixelSize: Theme.small - 0.5 }
  }

  Kit.Group {
    header: "Docking windows"
    Item {
      Layout.fillWidth: true
      implicitHeight: ideas.implicitHeight + 28
      RowLayout {
        id: ideas
        anchors.centerIn: parent
        spacing: 14
        Idea { name: "Halves"; how: "Drag to a side, or Super+←/→"; parts: [[0, 0, 0.5, 1]] }
        Idea { name: "Quarters"; how: "Drag to a corner, or Super+← then ↑"; parts: [[0, 0, 0.5, 0.5]] }
        Idea { name: "Layouts"; how: "Drag to the middle of the top edge"; parts: [[0, 0, 0.667, 1], [0.667, 0, 0.333, 1]] }
        Idea { name: "Fill"; how: "Drag to the top, or Super+↑"; parts: [[0, 0, 1, 1]] }
      }
    }
    Kit.Row {
      label: "Dock windows at the screen edges"; detail: "Drag a window against an edge or corner"
      Kit.Switch { checked: Prefs.snapping; onToggled: on => Prefs.set("snapping", on) }
    }
    Kit.Row {
      label: "Layouts bar"; detail: "Drag a window to the middle of the top edge for halves, thirds and quarters"
      enabled: Prefs.snapping; opacity: enabled ? 1 : 0.4
      Kit.Switch { checked: Prefs.snapLayouts; onToggled: on => Prefs.set("snapLayouts", on) }
    }
    Kit.Row {
      label: "Snap Assist"
      enabled: Prefs.snapping; opacity: enabled ? 1 : 0.4
      Kit.Switch { checked: Prefs.snapAssist; onToggled: on => Prefs.set("snapAssist", on) }
    }
    Kit.Row {
      label: "Resize side by side"; last: true
      Kit.Value { text: Prefs.snapping ? "On" : "Off" }
    }
  }

  Kit.Group {
    header: "Desktops"
    Kit.Row {
      label: "Desktops"; detail: "Add more in Mission Control (Ctrl+Super+↑, F3 or Super+S)"
      RowLayout {
        spacing: 8
        Kit.Button { text: "−"; onClicked: Prefs.set("desktops", Math.max(1, Prefs.desktops - 1)) }
        Txt { text: Prefs.desktops; font.weight: Font.Bold; Layout.preferredWidth: 20; horizontalAlignment: Text.AlignHCenter }
        Kit.Button { text: "+"; onClicked: Prefs.set("desktops", Math.min(9, Prefs.desktops + 1)) }
      }
    }
    Kit.Row { label: "Go to the next or previous desktop"; Kit.Value { text: "Ctrl+Super+← →" } }
    Kit.Row { label: "Take the window with you"; Kit.Value { text: "Ctrl+Super+Shift+← →" } }
    Kit.Row { label: "Mission Control"; last: true; Kit.Value { text: "Ctrl+Super+↑ · F3" } }
  }

  Kit.Group {
    header: "Shortcuts"
    footer: "All shortcuts: Help > Keyboard Shortcuts."
    Repeater {
      model: [["Search", "Super+Space"], ["Apps", "Tap Super"], ["Switch apps", "Super+Tab"], ["Close window", "Super+W"],
              ["Quit app", "Super+Q"], ["Hide app", "Super+H"], ["Minimize", "Super+M"], ["Screenshot", "Super+Shift+3 · 4 · 5"],
              ["Lock screen", "Ctrl+Super+Q"], ["Memora AI", "Super+A"]]
      delegate: Kit.Row {
        required property var modelData
        required property int index
        label: modelData[0]; last: index === 9
        Kit.Value { text: modelData[1] }
      }
    }
  }
}
