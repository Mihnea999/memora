import QtQuick
import QtQuick.Layouts
import qs.core

// A confirmation that slides down over a window, for anything that can't be
// undone. ask({ title, message, action: "Delete", destructive: true, onAccept })
Item {
  id: sheet
  anchors.fill: parent
  z: 1000
  visible: shown || fade.running
  property bool shown: false
  property string title: ""
  property string message: ""
  property string action: "OK"
  property bool destructive: true
  property var onAccept: null

  function ask(o) {
    title = o.title || ""; message = o.message || ""; action = o.action || "OK"
    destructive = o.destructive !== false; onAccept = o.onAccept || null
    shown = true
    forceActiveFocus()
  }
  function accept() { shown = false; if (onAccept) onAccept() }
  function cancel() { shown = false }

  Keys.onEscapePressed: cancel()
  Keys.onReturnPressed: accept()

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.18)
    opacity: sheet.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { id: fade; duration: Theme.fast } }
    TapHandler { onTapped: sheet.cancel() }
  }
  Glass {
    id: card
    anchors.horizontalCenter: parent.horizontalCenter
    y: sheet.shown ? 56 : 20
    opacity: sheet.shown ? 1 : 0
    Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Theme.easingEmph } }
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    width: 340; height: col.implicitHeight + 40
    radius: 16
    fill: Theme.dark ? Qt.rgba(0.16, 0.16, 0.18, 0.96) : Qt.rgba(0.99, 0.99, 1, 0.97)
    TapHandler {}  // keep taps on the card from closing it
    ColumnLayout {
      id: col
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
      spacing: 8
      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        width: 44; height: 44; radius: 12
        color: sheet.destructive ? Theme.red : Theme.accent
        Sym { anchors.centerIn: parent; name: sheet.destructive ? "close" : "info"; width: 20; height: 20; color: "#ffffff" }
      }
      Txt { Layout.fillWidth: true; Layout.topMargin: 4; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: sheet.title; font.weight: Font.Bold; font.pixelSize: Theme.fontSize + 1 }
      Txt { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: sheet.message; color: Theme.textDim; font.pixelSize: Theme.small + 0.5; visible: text !== "" }
      RowLayout {
        Layout.fillWidth: true; Layout.topMargin: 10
        spacing: 10
        SheetButton { Layout.fillWidth: true; text: "Cancel"; onClicked: sheet.cancel() }
        SheetButton { Layout.fillWidth: true; text: sheet.action; strong: true; onClicked: sheet.accept() }
      }
    }
  }

  component SheetButton: Rectangle {
    id: b
    property string text
    property bool strong: false
    signal clicked()
    implicitHeight: 32; radius: 9
    color: strong ? (sheet.destructive ? Theme.red : Theme.accent) : (bh.hovered ? Theme.pressed : Theme.hover)
    opacity: strong && bh.hovered ? 0.9 : 1
    Txt { anchors.centerIn: parent; text: b.text; color: b.strong ? "#ffffff" : Theme.text; font.weight: b.strong ? Font.Bold : Font.Normal }
    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: b.clicked() }
  }
}
