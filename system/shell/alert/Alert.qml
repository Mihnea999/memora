import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.ui

// Questions the desktop asks before doing something that can't be undone:
// shutting down, restarting, logging out, emptying the Trash.
Scope {
  id: root
  readonly property var a: Shell.alert
  readonly property bool active: !!a
  // Shut down and restart go ahead by themselves after a minute, as on a Mac.
  property int left: 60

  function accept() { const x = a; Shell.alert = null; if (x && x.onAccept) x.onAccept() }
  function cancel() { Shell.alert = null }
  onActiveChanged: left = 60
  Timer {
    running: root.active && !!root.a && root.a.countdown === true
    interval: 1000; repeat: true
    onTriggered: { root.left--; if (root.left <= 0) root.accept() }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      readonly property bool main: modelData === Quickshell.screens[0]
      visible: root.active || anim.running
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-dialog"
      WlrLayershell.keyboardFocus: root.active && main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      property real shown: root.active ? 1 : 0
      Behavior on shown { NumberAnimation { id: anim; duration: Theme.normal; easing.type: Theme.easing } }
      // Keep the last question on screen while it fades out.
      property var shownAlert: null
      Connections { target: root; function onAChanged() { if (root.a) win.shownAlert = root.a } }

      Rectangle {
        anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28); opacity: win.shown
        TapHandler { onTapped: root.cancel() }
      }

      Glass {
        visible: win.main
        anchors.centerIn: parent
        width: 340
        height: body.implicitHeight + 44
        radius: 22
        fill: Theme.glassStrong
        shadowSize: 50
        opacity: win.shown
        scale: 0.96 + 0.04 * win.shown
        focus: true
        Keys.onEscapePressed: root.cancel()
        Keys.onReturnPressed: root.accept()
        TapHandler {}

        ColumnLayout {
          id: body
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
          spacing: 10
          Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 64; height: 64; radius: 16
            color: win.shownAlert && win.shownAlert.destructive === false ? Theme.accent : "transparent"
            gradient: win.shownAlert && win.shownAlert.destructive === false ? null : grad
            Gradient { id: grad
              GradientStop { position: 0; color: "#cfd2d9" }
              GradientStop { position: 1; color: "#8c9099" } }
            Sym { anchors.centerIn: parent; name: win.shownAlert ? (win.shownAlert.sym || "info") : "info"; width: 30; height: 30; color: "#ffffff" }
          }
          Txt {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: win.shownAlert ? win.shownAlert.title : ""
            font.weight: Font.Bold; font.pixelSize: Theme.fontSize + 1
          }
          Txt {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            visible: text !== ""
            text: !win.shownAlert ? "" : (win.shownAlert.countdown ? (win.shownAlert.message || "") .replace("%s", root.left) : (win.shownAlert.message || ""))
            color: Theme.textDim; font.pixelSize: Theme.small + 0.5
          }
          RowLayout {
            Layout.fillWidth: true; Layout.topMargin: 8
            spacing: 10
            Btn { Layout.fillWidth: true; text: "Cancel"; onClicked: root.cancel() }
            Btn { Layout.fillWidth: true; text: win.shownAlert ? win.shownAlert.action : "OK"; primary: true
              danger: !!win.shownAlert && win.shownAlert.danger === true; onClicked: root.accept() }
          }
        }
      }
    }
  }

  component Btn: Rectangle {
    id: b
    property string text
    property bool primary: false
    property bool danger: false
    signal clicked()
    implicitHeight: 32; radius: 9
    color: primary ? (danger ? Theme.red : Theme.accent) : (bh.hovered ? Theme.pressed : Theme.hover)
    opacity: primary && bh.hovered ? 0.9 : 1
    Txt { anchors.centerIn: parent; text: b.text; color: b.primary ? "#ffffff" : Theme.text; font.weight: b.primary ? Font.Bold : Font.Normal }
    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: b.clicked() }
  }
}
