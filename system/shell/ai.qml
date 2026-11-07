//@ pragma UseQApplication
//@ pragma AppId memora-ai
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.ui

// Memora AI: a conversation with the assistant, which can act on this computer.
// The agent (ai/agent.py serve) speaks JSON lines; risky actions come back as
// confirmation cards the person answers here.
ShellRoot {
  id: app
  property bool busy: false
  property string status: ""
  property string model: ""
  // items: { kind: "user"|"assistant"|"tool"|"confirm"|"error", text, id, ok, done, level, title, detail, why, answered }
  ListModel { id: items }

  function send(obj) { agent.write(JSON.stringify(obj) + "\n") }
  function ask(text) {
    const t = text.trim()
    if (!t || busy) return
    items.append({ kind: "user", text: t, id: 0, ok: true, done: true, level: "", title: "", detail: "", why: "", answered: false })
    busy = true; status = "Thinking…"
    send({ type: "user", text: t })
  }
  function lastAssistant() {
    if (items.count && items.get(items.count - 1).kind === "assistant") return items.count - 1
    items.append({ kind: "assistant", text: "", id: 0, ok: true, done: false, level: "", title: "", detail: "", why: "", answered: false })
    return items.count - 1
  }
  function find(kind, id) { for (let i = items.count - 1; i >= 0; i--) { const it = items.get(i); if (it.kind === kind && it.id === id) return i } return -1 }

  Process {
    id: agent
    running: true
    stdinEnabled: true
    command: ["python3", Theme.share + "/ai/agent.py", "serve"]
    stdout: SplitParser {
      onRead: line => {
        let m; try { m = JSON.parse(line) } catch (e) { return }
        switch (m.type) {
        case "ready": app.model = m.provider === "anthropic" ? (m.model || "Claude") : m.provider; break
        case "text": { const i = app.lastAssistant(); items.setProperty(i, "text", items.get(i).text + m.delta); app.status = ""; break }
        case "status": app.status = m.text; break
        case "tool": items.append({ kind: "tool", text: m.summary, id: m.id, ok: true, done: false, level: "", title: m.name, detail: "", why: "", answered: false }); break
        case "tool_done": { const i = app.find("tool", m.id); if (i >= 0) { items.setProperty(i, "done", true); items.setProperty(i, "ok", m.ok) } break }
        case "confirm": items.append({ kind: "confirm", text: "", id: m.id, ok: false, done: false, level: m.level, title: m.title, detail: m.detail, why: m.why, answered: false }); app.status = "Waiting for you"; break
        case "error": items.append({ kind: "error", text: m.message, id: 0, ok: false, done: true, level: "", title: "", detail: "", why: "", answered: false }); break
        case "done": app.busy = false; app.status = ""; break
        }
      }
    }
    onExited: { app.busy = false; items.append({ kind: "error", text: "The assistant stopped. Close and reopen Memora AI.", id: 0, ok: false, done: true, level: "", title: "", detail: "", why: "", answered: false }) }
  }

  // `memora-ai window "question"` asks right away.
  Component.onCompleted: { const q = Quickshell.env("MEMORA_AI_PROMPT"); if (q) Qt.callLater(() => app.ask(q)) }
  IpcHandler {
    target: "ai"
    function ask(q: string): void { app.ask(q) }
  }

  FloatingWindow {
    id: win
    title: "Memora AI"
    implicitWidth: 760
    implicitHeight: 720
    minimumSize: Qt.size(520, 420)
    color: "transparent"

    Rectangle { anchors.fill: parent; color: Theme.window }

    // ---- title bar
    Item {
      id: bar
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: 52
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      WindowControls { x: 16; anchors.verticalCenter: parent.verticalCenter; window: win; onCloseRequested: Qt.quit() }
      Column {
        anchors.centerIn: parent
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Memora AI"; font.weight: Font.Bold }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: app.model; color: Theme.textDim; font.pixelSize: Theme.small - 1; visible: text !== "" }
      }
      Rectangle {
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: nt.implicitWidth + 22; height: 26; radius: 8
        color: nh.hovered ? Theme.pressed : Theme.hover
        Txt { id: nt; anchors.centerIn: parent; text: "New Chat"; font.pixelSize: Theme.small }
        HoverHandler { id: nh }
        TapHandler { onTapped: { if (app.busy) app.send({ type: "stop" }); items.clear(); app.send({ type: "new" }); app.busy = false; field.forceActiveFocus() } }
      }
      Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.separator }
    }

    // ---- empty state
    Column {
      visible: items.count === 0
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -40
      spacing: 14
      Image { anchors.horizontalCenter: parent.horizontalCenter; source: Quickshell.iconPath("memora-ai"); width: 72; height: 72; sourceSize: Qt.size(144, 144) }
      Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "What can I do for you?"; font.pixelSize: 20; font.weight: Font.Bold }
      Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "I can open apps, change settings, sort files and run commands."; color: Theme.textDim }
      Flow {
        width: 520; spacing: 8
        anchors.horizontalCenter: parent.horizontalCenter
        Repeater {
          model: ["Switch to light mode", "What is using my memory?", "Free up disk space", "Make a folder for my photos", "Install a video editor"]
          delegate: Rectangle {
            required property string modelData
            width: st.implicitWidth + 24; height: 30; radius: 15
            color: sh.hovered ? Theme.pressed : Theme.hover
            border.color: Theme.separator
            Txt { id: st; anchors.centerIn: parent; text: modelData; font.pixelSize: Theme.small + 0.5 }
            HoverHandler { id: sh }
            TapHandler { onTapped: app.ask(modelData) }
          }
        }
      }
    }

    // ---- conversation
    ListView {
      id: list
      anchors { left: parent.left; right: parent.right; top: bar.bottom; bottom: inputBox.top; bottomMargin: 8 }
      clip: true
      model: items
      spacing: 10
      topMargin: 16; bottomMargin: 10
      boundsBehavior: Flickable.StopAtBounds
      onCountChanged: Qt.callLater(() => list.positionViewAtEnd())
      onContentHeightChanged: if (atYEnd || app.busy) Qt.callLater(() => list.positionViewAtEnd())

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
        implicitHeight: kind === "user" ? userBubble.height : kind === "assistant" ? answerText.implicitHeight + 4
          : kind === "tool" ? 26 : kind === "confirm" ? confirmCard.height : errorText.implicitHeight + 16

        // You
        Rectangle {
          id: userBubble
          visible: d.kind === "user"
          anchors.right: parent.right; anchors.rightMargin: 20
          width: Math.min(ut.implicitWidth + 28, d.width * 0.72)
          height: ut.implicitHeight + 18
          radius: 16
          color: Theme.accent
          Txt { id: ut; x: 14; y: 9; width: parent.width - 28; text: d.kind === "user" ? d.text : ""; color: "#ffffff"; wrapMode: Text.Wrap; elide: Text.ElideNone }
        }

        // The assistant
        Text {
          id: answerText
          visible: d.kind === "assistant"
          x: 24; width: d.width - 60
          text: d.kind === "assistant" ? d.text : ""
          textFormat: Text.MarkdownText
          wrapMode: Text.Wrap
          color: Theme.text
          font.family: Theme.font; font.pixelSize: Theme.fontSize
          linkColor: Theme.accent
          onLinkActivated: link => Qt.openUrlExternally(link)
        }

        // What it is doing
        Row {
          visible: d.kind === "tool"
          x: 24; spacing: 8
          height: 26
          Rectangle {
            width: 16; height: 16; radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: !d.done ? "transparent" : (d.ok ? Qt.rgba(0.2, 0.78, 0.35, 0.18) : Qt.rgba(1, 0.37, 0.34, 0.18))
            border.color: !d.done ? Theme.textFaint : "transparent"
            border.width: 2
            RotationAnimation on rotation { running: d.kind === "tool" && !d.done; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
            Sym { visible: d.done; anchors.centerIn: parent; name: d.ok ? "check" : "close"; width: 9; height: 9; color: d.ok ? Theme.green : Theme.red }
          }
          Txt { anchors.verticalCenter: parent.verticalCenter; text: d.kind === "tool" ? d.text : ""; color: Theme.textDim; font.pixelSize: Theme.small; width: Math.min(implicitWidth, d.width - 80) }
        }

        // Needs your OK
        Rectangle {
          id: confirmCard
          visible: d.kind === "confirm"
          x: 24; width: d.width - 48
          height: cc.implicitHeight + 28
          radius: 14
          color: d.level === "critical" ? Qt.rgba(1, 0.3, 0.3, Theme.dark ? 0.12 : 0.08) : Theme.field
          border.color: d.level === "critical" ? Theme.red : Theme.separator
          border.width: d.level === "critical" ? 2 : 1
          ColumnLayout {
            id: cc
            x: 14; y: 14; width: parent.width - 28
            spacing: 8
            Txt { text: d.level === "critical" ? "This could do serious, permanent damage" : d.title; font.weight: Font.Bold; color: d.level === "critical" ? Theme.red : Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
            Txt { visible: d.level === "critical"; text: d.title; font.weight: Font.Bold; Layout.fillWidth: true }
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: dt.implicitHeight + 16
              radius: 8
              color: Theme.dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0, 0, 0, 0.05)
              Txt { id: dt; x: 10; y: 8; width: parent.width - 20; text: d.kind === "confirm" ? d.detail : ""; wrapMode: Text.WrapAnywhere; elide: Text.ElideNone; maximumLineCount: 14; font.pixelSize: Theme.small + 0.5 }
            }
            Txt { text: d.why; color: Theme.textDim; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: Theme.small + 0.5 }
            RowLayout {
              visible: !d.answered
              spacing: 8
              Item { Layout.fillWidth: true }
              Rectangle {
                width: dn.implicitWidth + 24; height: 28; radius: 8
                color: dh.hovered ? Theme.pressed : Theme.hover
                Txt { id: dn; anchors.centerIn: parent; text: "Don't Allow" }
                HoverHandler { id: dh }
                TapHandler { onTapped: { app.send({ type: "confirm", id: d.id, ok: false }); items.setProperty(d.index, "answered", true); items.setProperty(d.index, "ok", false); app.status = "" } }
              }
              Rectangle {
                width: al.implicitWidth + 24; height: 28; radius: 8
                color: d.level === "critical" ? Theme.red : Theme.accent
                Txt { id: al; anchors.centerIn: parent; text: d.level === "critical" ? "Allow Anyway" : "Allow"; color: "#ffffff"; font.weight: Font.Bold }
                TapHandler { onTapped: { app.send({ type: "confirm", id: d.id, ok: true }); items.setProperty(d.index, "answered", true); items.setProperty(d.index, "ok", true); app.status = "Working…" } }
              }
            }
            Txt { visible: d.answered; text: d.ok ? "Allowed" : "Not allowed"; color: Theme.textDim; font.pixelSize: Theme.small }
          }
        }

        Txt {
          id: errorText
          visible: d.kind === "error"
          x: 24; width: d.width - 48; y: 8
          text: d.kind === "error" ? d.text : ""
          color: Theme.red; wrapMode: Text.Wrap
        }
      }

      footer: Item {
        width: list.width; height: app.status ? 30 : 0
        Txt { x: 24; anchors.verticalCenter: parent.verticalCenter; text: app.status; color: Theme.textDim; font.pixelSize: Theme.small; visible: app.status !== "" }
      }
    }

    // ---- input
    Rectangle {
      id: inputBox
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
      height: Math.min(160, Math.max(46, field.contentHeight + 24))
      radius: 23
      color: Theme.field
      border.color: field.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : Theme.separator
      Flickable {
        id: flick
        anchors { left: parent.left; right: sendBtn.left; top: parent.top; bottom: parent.bottom; leftMargin: 18; rightMargin: 8; topMargin: 12; bottomMargin: 12 }
        contentHeight: field.contentHeight
        clip: true
        TextEdit {
          id: field
          width: flick.width
          wrapMode: TextEdit.Wrap
          color: Theme.text
          font.family: Theme.font; font.pixelSize: Theme.fontSize
          selectionColor: Theme.accent
          focus: true
          Keys.onReturnPressed: ev => {
            if (ev.modifiers & Qt.ShiftModifier) { ev.accepted = false; return }
            app.ask(text); text = ""
          }
          Txt { visible: !field.text; text: app.busy ? "Working…" : "Ask Memora AI"; color: Theme.textFaint }
        }
      }
      Rectangle {
        id: sendBtn
        anchors { right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 8 }
        width: 30; height: 30; radius: 15
        color: app.busy ? Theme.text : (field.text.trim() ? Theme.accent : Theme.hover)
        Sym { anchors.centerIn: parent; visible: !app.busy; name: "arrow"; width: 14; height: 14; rotation: -90; color: field.text.trim() ? "#ffffff" : Theme.textDim }
        Rectangle { anchors.centerIn: parent; visible: app.busy; width: 10; height: 10; radius: 2; color: Theme.dark ? "#000" : "#fff" }
        TapHandler { onTapped: { if (app.busy) app.send({ type: "stop" }); else { app.ask(field.text); field.text = "" } } }
      }
    }
  }
}
