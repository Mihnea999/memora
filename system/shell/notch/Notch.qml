import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Memora AI lives in a notch at the top of the screen: a small black island in
// the middle of the menu bar. Click it (or Super+A, or ask from Spotlight) and
// it unfolds downwards into a conversation. While it works with the panel
// folded, the island widens to show what it is doing; when it needs your OK it
// opens by itself. The agent is ai/agent.py, speaking JSON lines.
Scope {
  id: ai

  // ---- state -----------------------------------------------------------------
  property bool expanded: false
  property bool busy: false
  property string status: ""
  property string model: ""
  property bool started: false
  // While the assistant works in apps (typing, clicking) it folds into its pill
  // and lets go of the keyboard, so keys reach the app; it opens again after.
  property bool driving: false
  // items: { kind: "user"|"assistant"|"tool"|"confirm"|"error", text, id, ok, done, level, title, detail, why, answered }
  ListModel { id: items }

  function toggle() { expanded ? collapse() : expand() }
  function expand() { started = true; Shell.close(); expanded = true }
  function collapse() { expanded = false }
  function send(obj) { agent.write(JSON.stringify(obj) + "\n") }
  function ask(text) {
    const t = (text || "").trim()
    if (!t || busy) return
    started = true
    items.append({ kind: "user", text: t, id: 0, ok: true, done: true, level: "", title: "", detail: "", why: "", answered: false })
    busy = true; status = "Thinking…"
    if (agent.running) send({ type: "user", text: t })
    else pending = t
  }
  property string pending: ""
  function newChat() { if (busy) send({ type: "stop" }); items.clear(); send({ type: "new" }); busy = false; status = "" }
  function lastAssistant() {
    if (items.count && items.get(items.count - 1).kind === "assistant") return items.count - 1
    items.append({ kind: "assistant", text: "", id: 0, ok: true, done: false, level: "", title: "", detail: "", why: "", answered: false })
    return items.count - 1
  }
  function find(kind, id) { for (let i = items.count - 1; i >= 0; i--) { const it = items.get(i); if (it.kind === kind && it.id === id) return i } return -1 }
  function answer(index, ok) {
    const it = items.get(index)
    send({ type: "confirm", id: it.id, ok: ok })
    items.setProperty(index, "answered", true); items.setProperty(index, "ok", ok)
    status = ok ? "Working…" : ""
    if (ok && driving) expanded = false
  }

  // The agent starts the first time it is needed and then stays.
  Process {
    id: agent
    running: ai.started
    stdinEnabled: true
    command: ["python3", Theme.share + "/ai/agent.py", "serve"]
    onRunningChanged: if (running && ai.pending) { ai.send({ type: "user", text: ai.pending }); ai.pending = "" }
    stdout: SplitParser {
      onRead: line => {
        let m; try { m = JSON.parse(line) } catch (e) { return }
        switch (m.type) {
        case "ready": ai.model = m.provider === "anthropic" ? (m.model || "Claude") : (m.provider === "deepseek" ? "DeepSeek" : m.provider); break
        case "text": { const i = ai.lastAssistant(); items.setProperty(i, "text", items.get(i).text + m.delta); ai.status = "Writing…"; break }
        case "status": ai.status = m.text; break
        case "hands":
          if (m.on && !ai.driving) { ai.driving = true; ai.expanded = false }
          else if (!m.on) ai.driving = false
          break
        case "tool": items.append({ kind: "tool", text: m.summary, id: m.id, ok: true, done: false, level: "", title: m.name, detail: "", why: "", answered: false }); ai.status = m.summary; break
        case "tool_done": { const i = ai.find("tool", m.id); if (i >= 0) { items.setProperty(i, "done", true); items.setProperty(i, "ok", m.ok) } break }
        case "confirm":
          items.append({ kind: "confirm", text: "", id: m.id, ok: false, done: false, level: m.level, title: m.title, detail: m.detail, why: m.why, answered: false })
          ai.status = "Needs your OK"; ai.expanded = true
          break
        case "error": items.append({ kind: "error", text: m.message, id: 0, ok: false, done: true, level: "", title: "", detail: "", why: "", answered: false }); break
        case "done":
          ai.busy = false; ai.status = ""
          // After working in apps it stays folded, so what it opened stays in
          // view; the pill glows and a click shows the answer.
          ai.driving = false
          if (!ai.expanded) ai.flash = true
          break
        }
      }
    }
    onExited: { if (ai.busy) items.append({ kind: "error", text: "The assistant stopped. Ask again to restart it.", id: 0, ok: false, done: true, level: "", title: "", detail: "", why: "", answered: false }); ai.busy = false; ai.started = false }
  }
  // A short glow on the island when an answer finishes while folded.
  property bool flash: false
  Timer { running: ai.flash; interval: 2600; onTriggered: ai.flash = false }

  IpcHandler {
    target: "ai"
    function toggle(): void { ai.toggle() }
    function open(): void { ai.expand() }
    function ask(q: string): void { ai.expand(); ai.ask(q) }
  }
  Connections { target: Shell; function onOpenChanged() { if (Shell.open !== "" && ai.expanded) ai.collapse() } }

  // ---- the island, on the screen you are working on --------------------------
  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      readonly property bool here: Hyprland.focusedMonitor ? modelData.name === Hyprland.focusedMonitor.name : modelData === Quickshell.screens[0]
      visible: here
      anchors { top: true; left: true; right: true }
      implicitHeight: 720
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-notch"
      WlrLayershell.keyboardFocus: ai.expanded && here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      // Only the island takes the pointer; the rest stays click-through.
      mask: Region { item: island }

      // Ink for a dark island in both appearances.
      readonly property color ink: "#f5f5f7"
      readonly property color dim: Qt.rgba(0.96, 0.96, 0.97, 0.56)
      readonly property color faint: Qt.rgba(0.96, 0.96, 0.97, 0.3)
      readonly property color well: Qt.rgba(1, 1, 1, 0.08)
      readonly property color line: Qt.rgba(1, 1, 1, 0.1)

      // Folded: a pill in the bar; working: wider, with what it is doing.
      readonly property real foldedW: ai.busy ? Math.min(460, statusText.implicitWidth + 86) : (ai.flash ? 210 : 132)
      readonly property real openW: Math.min(win.width - 40, 680)
      readonly property real openH: Math.min(win.height - 40, items.count ? 600 : 250)

      Item {
        id: island
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: ai.expanded ? win.openW : win.foldedW
        height: ai.expanded ? win.openH : 30
        Behavior on width { SpringAnimation { spring: 3.2; damping: 0.32; epsilon: 0.5; mass: 1.0 } }
        Behavior on height { SpringAnimation { spring: 3.0; damping: 0.34; epsilon: 0.5; mass: 1.0 } }

        // The shape: flat against the top edge, rounded below.
        Rectangle {
          id: shape
          anchors { fill: parent; topMargin: -radius }
          radius: ai.expanded ? 30 : 15
          Behavior on radius { NumberAnimation { duration: Theme.normal } }
          color: "#050506"
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, ai.expanded ? 0.1 : 0.06)
        }
        // ---- folded content
        Item {
          anchors.fill: parent
          opacity: ai.expanded ? 0 : 1
          visible: opacity > 0
          Behavior on opacity { NumberAnimation { duration: Theme.fast } }
          Sym {
            id: spark
            x: 14; anchors.verticalCenter: parent.verticalCenter
            name: "sparkle"; width: 13; height: 13
            color: ai.busy ? Theme.accent : (ai.flash ? Theme.green : Qt.rgba(1, 1, 1, 0.85))
            SequentialAnimation on scale {
              running: ai.busy; loops: Animation.Infinite
              NumberAnimation { to: 1.25; duration: 520; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1.0; duration: 520; easing.type: Easing.InOutSine }
            }
          }
          Txt {
            id: statusText
            anchors { left: spark.right; leftMargin: 9; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            text: ai.busy ? (ai.status || "Working…") : (ai.flash ? "Answer ready" : "Ask AI")
            color: ai.busy || ai.flash ? win.ink : win.dim
            font.pixelSize: Theme.small
            elide: Text.ElideRight
          }
        }
        HoverHandler { id: islandHover; cursorShape: ai.expanded ? Qt.ArrowCursor : Qt.PointingHandCursor }
        TapHandler { enabled: !ai.expanded; onTapped: { ai.flash = false; ai.expand() } }
        scale: !ai.expanded && islandHover.hovered ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }

        // ---- open content
        Item {
          id: body
          anchors { fill: parent; margins: 18; topMargin: 14 }
          opacity: ai.expanded ? 1 : 0
          visible: opacity > 0
          Behavior on opacity { SequentialAnimation { PauseAnimation { duration: ai.expanded ? Prefs.motion(120) : 0 } NumberAnimation { duration: Theme.normal } } }

          // Header
          RowLayout {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 28
            spacing: 10
            Image { source: Quickshell.iconPath("memora-ai"); Layout.preferredWidth: 22; Layout.preferredHeight: 22; sourceSize: Qt.size(44, 44) }
            Txt { text: "Memora AI"; color: win.ink; font.weight: Font.Bold }
            Txt { text: ai.model; color: win.faint; font.pixelSize: Theme.small; visible: text !== "" }
            Item { Layout.fillWidth: true }
            Pill { visible: items.count > 0; text: "New Chat"; onClicked: ai.newChat() }
            Pill { text: "Close"; onClicked: ai.collapse() }
          }

          // Empty: suggestions
          Column {
            visible: items.count === 0
            anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: 22 }
            spacing: 12
            Txt { text: "What can I do for you?"; color: win.ink; font.pixelSize: 18; font.weight: Font.Bold }
            Flow {
              width: parent.width; spacing: 8
              Repeater {
                model: ["Switch to light mode", "What is using my memory?", "Free up disk space", "Install a video editor", "Arrange my windows side by side"]
                delegate: Pill { required property string modelData; text: modelData; onClicked: ai.ask(modelData) }
              }
            }
          }

          // Conversation
          ListView {
            id: list
            visible: items.count > 0
            anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: 10; bottom: input.top; bottomMargin: 10 }
            clip: true
            model: items
            spacing: 10
            boundsBehavior: Flickable.StopAtBounds
            onCountChanged: Qt.callLater(() => list.positionViewAtEnd())
            onContentHeightChanged: if (atYEnd || ai.busy) Qt.callLater(() => list.positionViewAtEnd())
            add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.normal } NumberAnimation { property: "y"; from: list.contentHeight + 10; duration: Theme.normal; easing.type: Theme.easing } }
            delegate: Item {
              id: d
              required property int index
              required property string kind
              required property string text
              required property int id
              required property bool ok
              required property bool done
              required property string level
              required property string title
              required property string detail
              required property string why
              required property bool answered
              width: list.width
              implicitHeight: kind === "user" ? ub.height : kind === "assistant" ? at.implicitHeight + 2
                : kind === "tool" ? 24 : kind === "confirm" ? cc.height : et.implicitHeight + 8

              Rectangle {
                id: ub
                visible: d.kind === "user"
                anchors.right: parent.right
                width: Math.min(ut.implicitWidth + 26, d.width * 0.75); height: ut.implicitHeight + 16
                radius: 15; color: Theme.accent
                Txt { id: ut; x: 13; y: 8; width: parent.width - 26; text: d.kind === "user" ? d.text : ""; color: "#ffffff"; wrapMode: Text.Wrap }
              }
              Text {
                id: at
                visible: d.kind === "assistant"
                width: d.width - 20
                text: d.kind === "assistant" ? d.text : ""
                textFormat: Text.MarkdownText; wrapMode: Text.Wrap
                color: win.ink; linkColor: Theme.accent
                font.family: Theme.font; font.pixelSize: Theme.fontSize
                onLinkActivated: link => Qt.openUrlExternally(link)
              }
              Row {
                visible: d.kind === "tool"
                spacing: 8; height: 24
                Rectangle {
                  width: 15; height: 15; radius: 7.5
                  anchors.verticalCenter: parent.verticalCenter
                  color: !d.done ? "transparent" : (d.ok ? Qt.rgba(0.2, 0.78, 0.35, 0.22) : Qt.rgba(1, 0.37, 0.34, 0.22))
                  border.color: !d.done ? win.faint : "transparent"; border.width: 2
                  RotationAnimation on rotation { running: d.kind === "tool" && !d.done; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                  Sym { visible: d.done; anchors.centerIn: parent; name: d.ok ? "check" : "close"; width: 8; height: 8; color: d.ok ? Theme.green : Theme.red }
                }
                Txt { anchors.verticalCenter: parent.verticalCenter; text: d.kind === "tool" ? d.text : ""; color: win.dim; font.pixelSize: Theme.small; width: Math.min(implicitWidth, d.width - 40); elide: Text.ElideRight }
              }
              Rectangle {
                id: cc
                visible: d.kind === "confirm"
                width: d.width; height: ccol.implicitHeight + 24
                radius: 16
                color: d.level === "critical" ? Qt.rgba(1, 0.3, 0.3, 0.14) : win.well
                border.color: d.level === "critical" ? Theme.red : win.line
                border.width: d.level === "critical" ? 2 : 1
                ColumnLayout {
                  id: ccol
                  x: 14; y: 12; width: parent.width - 28
                  spacing: 8
                  Txt { Layout.fillWidth: true; wrapMode: Text.Wrap; font.weight: Font.Bold
                    text: d.level === "critical" ? "This could do serious, permanent damage" : d.title
                    color: d.level === "critical" ? Theme.red : win.ink }
                  Txt { visible: d.level === "critical"; text: d.title; color: win.ink; font.weight: Font.Bold; Layout.fillWidth: true; wrapMode: Text.Wrap }
                  Rectangle {
                    Layout.fillWidth: true; implicitHeight: dt.implicitHeight + 14; radius: 9
                    color: Qt.rgba(0, 0, 0, 0.45)
                    Txt { id: dt; x: 10; y: 7; width: parent.width - 20; text: d.kind === "confirm" ? d.detail : ""; color: win.ink; wrapMode: Text.WrapAnywhere; maximumLineCount: 12; font.pixelSize: Theme.small + 0.5 }
                  }
                  Txt { text: d.why; color: win.dim; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: Theme.small + 0.5; visible: text !== "" }
                  RowLayout {
                    visible: !d.answered
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    Pill { text: "Don't Allow"; onClicked: ai.answer(d.index, false) }
                    Pill { text: d.level === "critical" ? "Allow Anyway" : "Allow"; strong: true; danger: d.level === "critical"; onClicked: ai.answer(d.index, true) }
                  }
                  Txt { visible: d.answered; text: d.ok ? "Allowed" : "Not allowed"; color: win.dim; font.pixelSize: Theme.small }
                }
              }
              Txt { id: et; visible: d.kind === "error"; width: d.width; y: 4; text: d.kind === "error" ? d.text : ""; color: "#ff7b73"; wrapMode: Text.Wrap }
            }
          }

          // Input
          Rectangle {
            id: input
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Math.min(130, Math.max(44, field.contentHeight + 22))
            radius: 22
            color: win.well
            border.color: field.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7) : win.line
            Behavior on height { NumberAnimation { duration: Theme.fast } }
            Flickable {
              id: ff
              anchors { left: parent.left; right: go.left; top: parent.top; bottom: parent.bottom; leftMargin: 16; rightMargin: 8; topMargin: 11; bottomMargin: 11 }
              contentHeight: field.contentHeight; clip: true
              TextEdit {
                id: field
                width: ff.width
                wrapMode: TextEdit.Wrap
                color: win.ink; selectionColor: Theme.accent
                font.family: Theme.font; font.pixelSize: Theme.fontSize
                Keys.onEscapePressed: ai.collapse()
                Keys.onReturnPressed: ev => {
                  if (ev.modifiers & Qt.ShiftModifier) { ev.accepted = false; return }
                  ai.ask(text); text = ""
                }
                Txt { visible: !field.text; text: ai.busy ? (ai.status || "Working…") : "Ask anything, or tell it what to do"; color: win.faint }
              }
            }
            Rectangle {
              id: go
              anchors { right: parent.right; rightMargin: 7; bottom: parent.bottom; bottomMargin: 7 }
              width: 30; height: 30; radius: 15
              color: ai.busy ? win.ink : (field.text.trim() ? Theme.accent : win.well)
              Behavior on color { ColorAnimation { duration: Theme.fast } }
              Sym { anchors.centerIn: parent; visible: !ai.busy; name: "arrow"; width: 14; height: 14; rotation: -90; color: field.text.trim() ? "#ffffff" : win.dim }
              Rectangle { anchors.centerIn: parent; visible: ai.busy; width: 10; height: 10; radius: 2; color: "#000" }
              TapHandler { onTapped: { if (ai.busy) ai.send({ type: "stop" }); else { ai.ask(field.text); field.text = "" } } }
            }
          }
          Connections { target: ai; function onExpandedChanged() { if (ai.expanded && win.here) Qt.callLater(() => field.forceActiveFocus()) } }
        }
      }
    }
  }

  component Pill: Rectangle {
    id: pl
    property string text
    property bool strong: false
    property bool danger: false
    signal clicked()
    implicitWidth: pt.implicitWidth + 24; implicitHeight: 28
    width: implicitWidth; height: implicitHeight
    radius: 14
    color: strong ? (danger ? Theme.red : Theme.accent) : (ph.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.09))
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Txt { id: pt; anchors.centerIn: parent; text: pl.text; color: "#f5f5f7"; font.pixelSize: Theme.small + 0.5; font.weight: pl.strong ? Font.Bold : Font.Normal }
    HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: pl.clicked() }
  }
}
