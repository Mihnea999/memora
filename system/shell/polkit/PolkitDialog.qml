import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.core
import qs.ui

// The password prompt apps get when they need administrator rights.
Scope {
  id: root
  property var flow: agent.flow
  readonly property bool active: !!flow && !flow.isCompleted

  PolkitAgent { id: agent; path: "/org/memora/PolkitAgent" }

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

      Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28); opacity: win.shown }

      Glass {
        id: card
        visible: win.main
        anchors.centerIn: parent
        width: 340
        height: body.implicitHeight + 44
        radius: 22
        fill: Theme.glassStrong
        shadowSize: 50
        opacity: win.shown
        scale: 0.96 + 0.04 * win.shown
        transform: Translate { id: shake; x: 0 }

        ColumnLayout {
          id: body
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
          spacing: 10

          Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 64; height: 64; radius: 16
            gradient: Gradient {
              GradientStop { position: 0; color: "#cfd2d9" }
              GradientStop { position: 1; color: "#8c9099" }
            }
            Sym { anchors.centerIn: parent; name: "lock"; width: 30; height: 30; color: "#ffffff" }
          }
          Txt {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "Administrator rights needed"
            font.weight: Font.Bold
            font.pixelSize: Theme.fontSize + 1
          }
          Txt {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.flow ? root.flow.message : ""
            color: Theme.textDim
            font.pixelSize: Theme.small + 0.5
          }
          Txt {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: !!root.flow && root.flow.supplementaryMessage !== ""
            text: root.flow ? root.flow.supplementaryMessage : ""
            color: root.flow && root.flow.supplementaryIsError ? Theme.red : Theme.textDim
            font.pixelSize: Theme.small
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            height: 32; radius: 8
            color: Theme.field
            border.color: pass.activeFocus ? Theme.accent : Theme.separator
            border.width: pass.activeFocus ? 2 : 1
            TextInput {
              id: pass
              clip: true   // long text scrolls inside the field, never spills out
              anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
              verticalAlignment: TextInput.AlignVCenter
              color: Theme.text
              font.family: Theme.font; font.pixelSize: Theme.fontSize
              echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
              passwordCharacter: "•"
              focus: true
              onTextChanged: root._pw = text
              Keys.onReturnPressed: root.submit()
              Keys.onEscapePressed: root.cancel()
              Txt { visible: !pass.text; anchors.verticalCenter: parent.verticalCenter; text: "Password"; color: Theme.textFaint }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 10
            DialogButton { Layout.fillWidth: true; text: "Cancel"; onClicked: root.cancel() }
            DialogButton { Layout.fillWidth: true; text: "OK"; primary: true; onClicked: root.submit() }
          }
        }
        Connections {
          target: root
          function onActiveChanged() { if (root.active) { pass.text = ""; pass.forceActiveFocus() } }
        }
      }

      SequentialAnimation {
        id: wobble
        loops: 2
        NumberAnimation { target: shake; property: "x"; to: -10; duration: 50 }
        NumberAnimation { target: shake; property: "x"; to: 10; duration: 80 }
        NumberAnimation { target: shake; property: "x"; to: 0; duration: 50 }
      }
      Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() { wobble.restart() }
      }
    }
  }

  function submit() { if (flow && flow.isResponseRequired) flow.submit(passText()) }
  function cancel() { if (flow) flow.cancelAuthenticationRequest() }
  property string _pw: ""
  function passText() { return _pw }

  component DialogButton: Rectangle {
    id: btn
    property string text
    property bool primary: false
    signal clicked()
    height: 30; radius: 8
    color: primary ? Theme.accent : (bh.hovered ? Theme.pressed : Theme.hover)
    Txt { anchors.centerIn: parent; text: btn.text; color: btn.primary ? "#ffffff" : Theme.text; font.weight: btn.primary ? Font.Bold : Font.Normal }
    HoverHandler { id: bh }
    TapHandler { onTapped: btn.clicked() }
  }
}
