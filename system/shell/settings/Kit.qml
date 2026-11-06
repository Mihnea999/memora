import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui

// Building blocks for System Settings panes, so every pane looks the same:
// a title, rounded groups of rows, each row a label on the left and its
// control on the right.
QtObject {
  component Page: Flickable {
    id: page
    property string title: ""
    default property alias content: col.data
    contentHeight: col.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ColumnLayout {
      id: col
      x: 28; y: 18
      width: page.width - 56
      spacing: 18
      Txt { text: page.title; font.pixelSize: 20; font.weight: Font.Bold }
    }
  }

  component Group: Rectangle {
    id: grp
    property string header: ""
    property string footer: ""
    default property alias rows: inner.data
    Layout.fillWidth: true
    implicitHeight: inner.implicitHeight + (header ? 26 : 0) + (footer ? footerText.implicitHeight + 10 : 0)
    color: "transparent"
    Txt { visible: grp.header !== ""; text: grp.header; font.weight: Font.Bold; color: Theme.textDim; font.pixelSize: Theme.small; x: 4 }
    Rectangle {
      id: box
      y: grp.header ? 24 : 0
      width: parent.width
      height: inner.implicitHeight
      radius: 12
      color: Theme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(1, 1, 1, 0.75)
      border.color: Theme.separator
      ColumnLayout { id: inner; width: parent.width; spacing: 0 }
    }
    Txt {
      id: footerText
      visible: grp.footer !== ""
      anchors { top: box.bottom; topMargin: 6; left: parent.left; leftMargin: 4; right: parent.right }
      text: grp.footer; wrapMode: Text.Wrap; color: Theme.textDim; font.pixelSize: Theme.small
    }
  }

  // A row: optional badge, label and detail on the left, control on the right.
  component Row: Item {
    id: row
    property string label: ""
    property string detail: ""
    property string badge: ""          // symbol name for a coloured badge
    property color badgeColor: Theme.accent
    property bool last: false
    property bool clickable: false
    signal clicked()
    default property alias control: slot.data
    Layout.fillWidth: true
    implicitHeight: detail ? 52 : 44
    Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 11; color: row.clickable && rh.hovered ? Theme.hover : "transparent" }
    Rectangle {
      id: badgeBox
      visible: row.badge !== ""
      x: 12; width: 24; height: 24; radius: 6
      anchors.verticalCenter: parent.verticalCenter
      color: row.badgeColor
      Sym { anchors.centerIn: parent; name: row.badge; width: 14; height: 14; color: "#ffffff" }
    }
    Column {
      anchors { left: row.badge ? badgeBox.right : parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter; right: slot.left; rightMargin: 12 }
      Txt { width: parent.width; text: row.label }
      Txt { width: parent.width; visible: row.detail !== ""; text: row.detail; color: Theme.textDim; font.pixelSize: Theme.small }
    }
    Item {
      id: slot
      anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
      width: childrenRect.width; height: childrenRect.height
    }
    Rectangle {
      visible: !row.last
      anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: row.badge ? 48 : 12 }
      height: 1; color: Theme.separator
    }
    HoverHandler { id: rh }
    TapHandler { enabled: row.clickable; onTapped: row.clicked() }
  }

  component Switch: Item {
    id: sw
    property bool checked: false
    signal toggled(bool on)
    width: 38; height: 22
    Rectangle {
      anchors.fill: parent; radius: 11
      color: sw.checked ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12))
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      Rectangle {
        width: 18; height: 18; radius: 9; y: 2
        x: sw.checked ? parent.width - width - 2 : 2
        color: "#ffffff"
        Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Theme.easing } }
      }
    }
    TapHandler { onTapped: sw.toggled(!sw.checked) }
  }

  component Button: Rectangle {
    id: b
    property string text: ""
    property bool primary: false
    property bool danger: false
    signal clicked()
    width: bt.implicitWidth + 24; height: 26; radius: 7
    color: primary ? Theme.accent : (bh.hovered ? Theme.pressed : Theme.hover)
    border.color: primary ? "transparent" : Theme.separator
    Txt { id: bt; anchors.centerIn: parent; text: b.text; color: b.primary ? "#ffffff" : (b.danger ? Theme.red : Theme.text); font.pixelSize: Theme.small + 0.5 }
    HoverHandler { id: bh }
    TapHandler { onTapped: b.clicked() }
  }

  // Segmented choice: options [{ text, value }]
  component Choice: Rectangle {
    id: ch
    property var options: []
    property var value
    signal picked(var value)
    width: seg.implicitWidth + 4; height: 26; radius: 7
    color: Theme.field
    border.color: Theme.separator
    RowLayout {
      id: seg
      anchors.centerIn: parent
      spacing: 0
      Repeater {
        model: ch.options
        delegate: Rectangle {
          required property var modelData
          implicitWidth: ot.implicitWidth + 22; implicitHeight: 22; radius: 6
          color: ch.value === modelData.value ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.2) : "#ffffff") : "transparent"
          Txt { id: ot; anchors.centerIn: parent; text: modelData.text; font.pixelSize: Theme.small + 0.5 }
          TapHandler { onTapped: ch.picked(modelData.value) }
        }
      }
    }
  }

  component Field: Rectangle {
    id: f
    property alias text: input.text
    property string placeholder: ""
    property bool secret: false
    signal accepted()
    width: 220; height: 26; radius: 7
    color: Theme.field
    border.color: input.activeFocus ? Theme.accent : Theme.separator
    border.width: input.activeFocus ? 2 : 1
    TextInput {
      id: input
      anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
      verticalAlignment: TextInput.AlignVCenter
      color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
      echoMode: f.secret ? TextInput.Password : TextInput.Normal
      passwordCharacter: "•"
      clip: true
      selectByMouse: true
      Keys.onReturnPressed: f.accepted()
      Txt { visible: !input.text && !input.activeFocus; anchors.verticalCenter: parent.verticalCenter; text: f.placeholder; color: Theme.textFaint; font.pixelSize: Theme.small + 0.5 }
    }
  }

  component Value: Txt {
    color: Theme.textDim
    horizontalAlignment: Text.AlignRight
  }

  // Runs a command and hands back its output.
  component Cmd: Process {
    id: cmd
    property string out: ""
    signal done(string out)
    stdout: StdioCollector { onStreamFinished: { cmd.out = text; cmd.done(text) } }
    function exec(args) { command = args; running = true }
  }
}
