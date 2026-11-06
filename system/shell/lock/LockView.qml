import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui

// The face of the lock screen and the login screen: the time large, the date,
// and at the bottom the person, their name and a password field.
Item {
  id: v
  property string userName: Quickshell.env("USER")
  property string fullName: userName
  property string message: ""
  property bool error: false
  property bool busy: false
  property bool showPower: false
  property var users: []                  // login screen: [{ name, full }]
  signal submit(string password)
  signal pickUser(string name)
  signal power(string action)

  function shake() { wobble.restart(); field.text = "" }
  function focusField() { field.forceActiveFocus() }

  Image {
    id: bg
    anchors.fill: parent
    source: "file://" + Theme.share + "/themes/" + (Theme.dark ? "dark" : "light") + "/wallpaper.png"
    fillMode: Image.PreserveAspectCrop
    sourceSize: Qt.size(1920, 1200)
    visible: false
  }
  MultiEffect {
    anchors.fill: parent
    source: bg
    blurEnabled: true
    blur: 1.0
    blurMax: 64
    saturation: 0.15
    brightness: Theme.dark ? -0.08 : 0.04
  }
  Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.18 : 0.06) }

  SystemClock { id: clock; precision: SystemClock.Seconds }

  readonly property color ink: "#ffffff"

  Column {
    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.09 }
    spacing: 0
    Txt {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatDate(clock.date, "dddd, MMMM d")
      color: v.ink; font.pixelSize: 22; font.weight: Font.Medium
      style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.15)
    }
    Txt {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatTime(clock.date, "HH:mm")
      color: v.ink; font.pixelSize: 120; font.weight: Font.Bold
      style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.12)
    }
  }

  ColumnLayout {
    id: who
    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.12 }
    spacing: 12
    transform: Translate { id: shakeX }

    // Other people on this computer (login screen).
    Row {
      Layout.alignment: Qt.AlignHCenter
      spacing: 22
      visible: v.users.length > 1
      Repeater {
        model: v.users
        delegate: Column {
          required property var modelData
          spacing: 6
          opacity: modelData.name === v.userName ? 1 : 0.6
          Avatar { size: 44; name: modelData.full; anchors.horizontalCenter: parent.horizontalCenter }
          Txt { text: modelData.full; color: v.ink; font.pixelSize: Theme.small; anchors.horizontalCenter: parent.horizontalCenter }
          TapHandler { onTapped: v.pickUser(modelData.name) }
        }
      }
    }

    Avatar { Layout.alignment: Qt.AlignHCenter; size: 76; name: v.fullName; visible: v.users.length <= 1 }
    Txt {
      Layout.alignment: Qt.AlignHCenter
      text: v.fullName
      color: v.ink; font.pixelSize: 17; font.weight: Font.Bold
      visible: v.users.length <= 1
    }

    Rectangle {
      Layout.alignment: Qt.AlignHCenter
      width: 230; height: 34; radius: 17
      color: Qt.rgba(1, 1, 1, 0.22)
      border.color: Qt.rgba(1, 1, 1, 0.35)
      TextInput {
        id: field
        anchors { left: parent.left; right: go.left; leftMargin: 16; rightMargin: 6; verticalCenter: parent.verticalCenter }
        color: v.ink
        font.family: Theme.font; font.pixelSize: Theme.fontSize
        echoMode: TextInput.Password
        passwordCharacter: "•"
        enabled: !v.busy
        focus: true
        Keys.onReturnPressed: if (text.length) v.submit(text)
        Txt { visible: !field.text; anchors.verticalCenter: parent.verticalCenter; text: "Enter Password"; color: Qt.rgba(1, 1, 1, 0.65) }
      }
      Rectangle {
        id: go
        anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
        width: 26; height: 26; radius: 13
        color: Qt.rgba(1, 1, 1, field.text ? 0.4 : 0.18)
        Sym { anchors.centerIn: parent; name: "arrow"; width: 13; height: 13; color: "#ffffff" }
        TapHandler { onTapped: if (field.text.length) v.submit(field.text) }
      }
    }
    Txt {
      Layout.alignment: Qt.AlignHCenter
      text: v.message
      visible: text !== ""
      color: v.ink
      opacity: 0.85
      font.pixelSize: Theme.small
    }
  }

  SequentialAnimation {
    id: wobble
    loops: 2
    NumberAnimation { target: shakeX; property: "x"; to: -12; duration: 45 }
    NumberAnimation { target: shakeX; property: "x"; to: 12; duration: 90 }
    NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 45 }
  }

  Row {
    visible: v.showPower
    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 30 }
    spacing: 40
    Repeater {
      model: [["sleep", "Sleep", "suspend"], ["restart", "Restart", "reboot"], ["power", "Shut Down", "poweroff"]]
      delegate: Column {
        required property var modelData
        spacing: 6
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: 40; height: 40; radius: 20
          color: Qt.rgba(1, 1, 1, ph.hovered ? 0.3 : 0.18)
          Sym { anchors.centerIn: parent; name: modelData[0]; width: 17; height: 17; color: "#ffffff" }
          HoverHandler { id: ph }
          TapHandler { onTapped: v.power(modelData[2]) }
        }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; color: v.ink; font.pixelSize: Theme.small - 1 }
      }
    }
  }

  component Avatar: Rectangle {
    property real size: 64
    property string name: ""
    width: size; height: size; radius: size / 2
    gradient: Gradient {
      GradientStop { position: 0; color: "#c5c9d2" }
      GradientStop { position: 1; color: "#8d929d" }
    }
    border.color: Qt.rgba(1, 1, 1, 0.5)
    Txt {
      anchors.centerIn: parent
      text: parent.name.split(" ").map(p => p.charAt(0)).join("").slice(0, 2).toUpperCase()
      color: "#ffffff"; font.pixelSize: parent.size * 0.38; font.weight: Font.Bold
    }
  }
}
