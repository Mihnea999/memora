import QtQuick
import QtQuick.Window
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
    // The control Tab lands on is scrolled into view.
    readonly property Item focused: Window.activeFocusItem
    onFocusedChanged: {
      let it = focused, inside = false
      for (let q = it; q; q = q.parent) if (q === col) { inside = true; break }
      if (!inside) return
      const y = it.mapToItem(col, 0, 0).y + col.y
      if (y < contentY + 12) contentY = Math.max(0, y - 12)
      else if (y + it.height > contentY + height - 12) contentY = Math.min(Math.max(0, contentHeight - height), y + it.height - height + 12)
    }
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
      visible: inner.implicitHeight > 0
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
    activeFocusOnTab: clickable
    Keys.onSpacePressed: if (clickable) clicked()
    Keys.onReturnPressed: if (clickable) clicked()
    Rectangle { anchors.fill: parent; anchors.margins: 2; radius: 10; color: "transparent"; border.width: 2; border.color: Theme.accent; visible: row.clickable && row.activeFocus }
  }

  component Switch: Item {
    id: sw
    property bool checked: false
    signal toggled(bool on)
    width: 38; height: 22
    activeFocusOnTab: true
    Keys.onSpacePressed: toggled(!checked)
    Keys.onReturnPressed: toggled(!checked)
    // Reached with Tab: a ring shows where the keyboard is.
    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 14; color: "transparent"; border.width: 2; border.color: Theme.accent; visible: sw.activeFocus }
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
    activeFocusOnTab: true
    Keys.onSpacePressed: clicked()
    Keys.onReturnPressed: clicked()
    // Reached with Tab: a ring shows where the keyboard is.
    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 10; color: "transparent"; border.width: 2; border.color: Theme.accent; visible: b.activeFocus }
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
    activeFocusOnTab: true
    // ← and → move the choice.
    function move(d) {
      const i = options.findIndex(o => o.value === value), n = Math.max(0, Math.min(options.length - 1, (i < 0 ? 0 : i) + d))
      if (options.length && n !== i) picked(options[n].value)
    }
    Keys.onLeftPressed: move(-1)
    Keys.onRightPressed: move(1)
    // Reached with Tab: a ring shows where the keyboard is.
    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 10; color: "transparent"; border.width: 2; border.color: Theme.accent; visible: ch.activeFocus }
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

  // A pop-up choice for longer lists: options [{ text, value }].
  component Select: Rectangle {
    id: sel
    property var options: []
    property var value
    property bool open: false
    signal picked(var value)
    readonly property var current: options.find(o => o.value === value) || options[0] || { text: "" }
    width: Math.max(120, st.implicitWidth + 40); height: 26; radius: 7
    color: sh.hovered || open ? Theme.pressed : Theme.field
    border.color: Theme.separator
    Txt { id: st; anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter } text: sel.current.text; font.pixelSize: Theme.small + 0.5 }
    Sym { anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter } name: "chevron"; width: 9; height: 9; rotation: 90; color: Theme.textDim }
    HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: sel.open = !sel.open }
    activeFocusOnTab: true
    onActiveFocusChanged: if (!activeFocus) open = false
    // Space opens the list; ↑ and ↓ change the choice; Esc closes.
    function move(d) {
      const i = options.findIndex(o => o.value === value), n = Math.max(0, Math.min(options.length - 1, (i < 0 ? 0 : i) + d))
      if (options.length && n !== i) picked(options[n].value)
    }
    Keys.onSpacePressed: open = !open
    Keys.onReturnPressed: open = !open
    Keys.onUpPressed: move(-1)
    Keys.onDownPressed: move(1)
    Keys.onEscapePressed: ev => { if (open) open = false; else ev.accepted = false }
    // Reached with Tab: a ring shows where the keyboard is.
    Rectangle { anchors.fill: parent; anchors.margins: -3; radius: 10; color: "transparent"; border.width: 2; border.color: Theme.accent; visible: sel.activeFocus }
    readonly property Item host: sel.Window.contentItem
    // Over the whole window while open: a click outside closes it.
    MouseArea {
      parent: sel.host
      visible: sel.open
      anchors.fill: parent
      z: 9998
      onClicked: sel.open = false
    }
    MenuPanel {
      parent: sel.host
      visible: sel.open
      z: 9999
      readonly property point at: sel.open && sel.host ? sel.mapToItem(sel.host, 0, sel.height + 4) : Qt.point(0, 0)
      x: Math.min(at.x, (sel.host ? sel.host.width : 0) - width - 8)
      y: at.y + height > (sel.host ? sel.host.height : 0) - 8 ? at.y - height - sel.height - 8 : at.y
      width: implicitWidth; height: implicitHeight
      items: sel.options.map(o => ({ text: o.text, checked: o.value === sel.value, value: o.value }))
      onPicked: item => { sel.open = false; sel.picked(item.value) }
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
      activeFocusOnTab: true
      Keys.onReturnPressed: f.accepted()
      Keys.onEnterPressed: f.accepted()
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
    // The same, with `input` on the command's standard input (passwords, keys).
    property var pending: null
    function execWith(args, input) { pending = input; stdinEnabled = true; command = args; running = true }
    onStarted: if (pending !== null) { write(pending); pending = null; stdinEnabled = false }
  }
}
