//@ pragma UseQApplication
//@ pragma AppId memora-dialog
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.ui

// The question Hyprland asks about an app: "not responding", "wants to capture
// your screen" … Run by bin/hyprland-dialog (which stands in for Hyprland's
// own grey box) with TITLE, APPTITLE, TEXT, BUTTONS (";"-separated) and OUT
// (the file the chosen button's name is written to).
ShellRoot {
  id: root
  readonly property string title: Quickshell.env("APPTITLE") || Quickshell.env("TITLE") || ""
  readonly property string text: Quickshell.env("TEXT") || ""
  readonly property var buttons: (Quickshell.env("BUTTONS") || "OK").split(";").filter(b => b.length)
  readonly property string out: Quickshell.env("OUT") || ""
  readonly property bool notResponding: /not responding/i.test(Quickshell.env("TEXT") || "")
  // What Return does: "Wait" for a hung app (never Terminate by accident), else the first.
  readonly property string primary: buttons.indexOf("Wait") >= 0 ? "Wait" : buttons[0]
  property bool done: false

  function choose(b) {
    if (done) return
    done = true
    if (out) Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" > \"$2\"", "_", b, out])
    quit.start()
  }
  Timer { id: quit; interval: 120; onTriggered: Qt.quit() }

  PanelWindow {
    id: win
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "memora-dialog"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    property real shown: 0
    Component.onCompleted: shown = 1
    Behavior on shown { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28); opacity: win.shown }

    Glass {
      anchors.centerIn: parent
      width: 380
      height: body.implicitHeight + 44
      radius: 22
      fill: Theme.glassStrong
      opacity: win.shown
      scale: 0.96 + 0.04 * win.shown
      focus: true
      Keys.onEscapePressed: root.choose("")
      Keys.onReturnPressed: root.choose(root.primary)
      Component.onCompleted: forceActiveFocus()

      ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
        spacing: 10
        Rectangle {
          Layout.alignment: Qt.AlignHCenter
          width: 64; height: 64; radius: 16
          gradient: Gradient {
            GradientStop { position: 0; color: root.notResponding ? "#ffb340" : "#cfd2d9" }
            GradientStop { position: 1; color: root.notResponding ? "#ff8a00" : "#8c9099" }
          }
          Sym { anchors.centerIn: parent; name: "info"; width: 30; height: 30; color: "#ffffff" }
        }
        Txt {
          Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
          visible: text !== ""
          text: root.notResponding ? "This app is not responding" : root.title
          font.weight: Font.Bold; font.pixelSize: Theme.fontSize + 1
        }
        Txt {
          Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
          visible: text !== ""
          textFormat: Text.StyledText
          text: root.text.replace(/\n/g, "<br>")
          color: Theme.textDim; font.pixelSize: Theme.small + 0.5
        }
        RowLayout {
          Layout.fillWidth: true; Layout.topMargin: 8
          spacing: 10
          Repeater {
            model: root.buttons
            delegate: Rectangle {
              id: b
              required property string modelData
              readonly property bool primary: modelData === root.primary
              readonly property bool danger: /^(terminate|force quit|deny)$/i.test(modelData) && !primary
              Layout.fillWidth: true
              implicitHeight: 32; radius: 9
              color: primary ? Theme.accent : (bh.hovered ? Theme.pressed : Theme.hover)
              Txt { anchors.centerIn: parent; text: b.modelData; color: b.primary ? "#ffffff" : (b.danger ? Theme.red : Theme.text); font.weight: b.primary ? Font.Bold : Font.Normal }
              HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.choose(b.modelData) }
            }
          }
        }
      }
    }
  }
}
