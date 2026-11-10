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
  property string model: ""          // shown in the header
  property string modelId: ""
  property string effort: ""
  property var models: []             // [{ id, name }]
  property var efforts: []
  property bool canModel: false
  property bool canEffort: false
  property bool picking: false        // the model and effort chooser is open
  property var pendingSettings: null
  property bool started: false
  // While the assistant works in apps (typing, clicking) it folds into its pill
  // and lets go of the keyboard, so keys reach the app; it opens again after.
  property bool driving: false
  // items: { kind: "user"|"assistant"|"tool"|"confirm"|"error", text, id, ok, done, level, title, detail, why, answered, files }
  // Files and pictures to send with the next message (pasted with Ctrl+V or
  // dropped on the panel): [{ path, name, image }].
  property var attached: []
  readonly property var imageExt: /\.(png|jpe?g|gif|webp|bmp|tiff?|heic|avif)$/i
  function attach(paths) {
    const now = attached.slice()
    for (const p of paths) {
      if (!p || now.some(a => a.path === p)) continue
      now.push({ path: p, name: p.split("/").pop(), image: imageExt.test(p) })
    }
    attached = now.slice(0, 10)
    expand()
  }
  function detach(path) { attached = attached.filter(a => a.path !== path) }
  ListModel { id: items }

  function toggle() { expanded ? collapse() : expand() }
  function expand() { started = true; Shell.close(); expanded = true }
  function collapse() { expanded = false; picking = false }
  function send(obj) { agent.write(JSON.stringify(obj) + "\n") }
  // Model and effort, from the header: the agent keeps them in ai.json.
  function choose(o) {
    if (o.model !== undefined) modelId = o.model
    if (o.effort !== undefined) effort = o.effort
    if (agent.running) send(Object.assign({ type: "settings" }, o))
    else { pendingSettings = Object.assign(pendingSettings || {}, o); started = true }
  }
  function effortName(e) { return ({ low: "Low", medium: "Medium", high: "High", xhigh: "Extra high", max: "Max" })[e] || e }
  function ask(text) {
    const t = (text || "").trim()
    const files = attached.map(a => a.path)
    if ((!t && !files.length) || busy) return
    started = true; picking = false
    items.append({ kind: "user", text: t, id: 0, ok: true, done: true, level: "", title: "", detail: "", why: "", answered: false, files: JSON.stringify(files) })
    attached = []
    busy = true; status = "Thinking…"
    if (agent.running) send({ type: "user", text: t, files: files })
    else { pending = t; pendingFiles = files }
    return true
  }
  property string pending: ""
  property var pendingFiles: []
  // Stop: right away in the window. The agent finishes the stopped turn with a
  // "done"; until then whatever it still sends belongs to the old turn and is
  // dropped (so a New Chat never gets the old answer).
  property int stale: 0
  function stop() {
    if (!busy) return
    send({ type: "stop" })
    stale++
    busy = false; status = ""; driving = false
    const i = items.count - 1
    if (i >= 0 && items.get(i).kind === "tool" && !items.get(i).done) { items.setProperty(i, "done", true); items.setProperty(i, "ok", false) }
    for (let j = 0; j < items.count; j++) if (items.get(j).kind === "confirm" && !items.get(j).answered) { items.setProperty(j, "answered", true); items.setProperty(j, "ok", false) }
  }
  function newChat() { stop(); items.clear(); attached = []; send({ type: "new" }); busy = false; status = "" }
  function lastAssistant() {
    if (items.count && items.get(items.count - 1).kind === "assistant") return items.count - 1
    items.append({ kind: "assistant", text: "", id: 0, ok: true, done: false, level: "", title: "", detail: "", why: "", answered: false, files: "" })
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

  // System Settings > Memora AI changed (another service or model): the header
  // shows it at once, not the one the agent started with.
  FileView {
    path: Quickshell.env("HOME") + "/.config/memora/ai.json"
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); if (agent.running) ai.send({ type: "refresh" }) }
  }
  // The agent starts the first time it is needed and then stays.
  Process {
    id: agent
    running: ai.started
    stdinEnabled: true
    command: ["python3", Theme.share + "/ai/agent.py", "serve"]
    onRunningChanged: {
      if (running && ai.pendingSettings) { ai.send(Object.assign({ type: "settings" }, ai.pendingSettings)); ai.pendingSettings = null }
      if (running && (ai.pending || ai.pendingFiles.length)) { ai.send({ type: "user", text: ai.pending, files: ai.pendingFiles }); ai.pending = ""; ai.pendingFiles = [] }
    }
    stdout: SplitParser {
      onRead: line => {
        let m; try { m = JSON.parse(line) } catch (e) { return }
        if (ai.stale > 0 && m.type !== "ready") {
          if (m.type === "done") ai.stale--
          return
        }
        switch (m.type) {
        case "ready": {
          ai.models = m.models || []; ai.efforts = m.efforts || []
          ai.canModel = !!m.canModel; ai.canEffort = !!m.canEffort
          ai.modelId = m.model || ""; ai.effort = m.effort || ""
          const known = ai.models.find(x => x.id === m.model)
          ai.model = m.provider === "deepseek" ? "DeepSeek" : (m.provider === "ollama" || m.provider === "openai") ? (m.model || m.provider)
            : (known ? known.name : (m.model || (m.provider === "claude-code" ? "Claude Code" : "Claude")))
          break
        }
        case "text": { const i = ai.lastAssistant(); items.setProperty(i, "text", items.get(i).text + m.delta); ai.status = "Writing…"; break }
        case "status": ai.status = m.text; break
        case "hands":
          if (m.on && !ai.driving) { ai.driving = true; ai.expanded = false }
          else if (!m.on) ai.driving = false
          break
        case "tool": items.append({ kind: "tool", text: m.summary, id: m.id, ok: true, done: false, level: "", title: m.name, detail: "", why: "", answered: false, files: "" }); ai.status = m.summary; break
        case "tool_done": { const i = ai.find("tool", m.id); if (i >= 0) { items.setProperty(i, "done", true); items.setProperty(i, "ok", m.ok) } break }
        case "confirm":
          items.append({ kind: "confirm", text: "", id: m.id, ok: false, done: false, level: m.level, title: m.title, detail: m.detail, why: m.why, answered: false, files: "" })
          ai.status = "Needs your OK"; ai.expanded = true
          break
        case "error": items.append({ kind: "error", text: m.message, id: 0, ok: false, done: true, level: "", title: "", detail: "", why: "", answered: false, files: "" }); break
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
    onExited: { ai.stale = 0; if (ai.busy) items.append({ kind: "error", text: "The assistant stopped. Ask again to restart it.", id: 0, ok: false, done: true, level: "", title: "", detail: "", why: "", answered: false, files: "" }); ai.busy = false; ai.started = false }
  }
  Process {
    id: paster
    command: ["bash", "-c", `
      types="$(wl-paste --list-types 2>/dev/null)"
      if grep -qx 'text/uri-list' <<<"$types"; then
        wl-paste --no-newline --type text/uri-list | tr -d '\\r' | sed -n 's|^file://||p' |
          python3 -c 'import sys, urllib.parse; [print("FILE " + urllib.parse.unquote(l.strip())) for l in sys.stdin if l.strip()]'
      elif ! grep -qx 'text/plain' <<<"$types" && img="$(grep -m1 -E '^image/(png|jpeg|webp|gif)$' <<<"$types")"; then
        d="$HOME/.cache/memora/ai"; mkdir -p "$d"; f="$d/pasted-$(date +%Y%m%d-%H%M%S-%N).\${img#image/}"
        wl-paste --type "$img" > "$f" && [ -s "$f" ] && echo "FILE $f"
      fi`]
    property var found: []
    stdout: SplitParser { onRead: line => { if (line.startsWith("FILE ")) paster.found = paster.found.concat([line.slice(5)]) } }
    onExited: { if (found.length) ai.attach(found); else ai.pasteText(); found = [] }
  }
  signal pasteText()

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
      // Out of the way while an app is full screen (a film, a game), unless it is
      // open or working.
      visible: here && (!Shell.fullscreenApp || ai.expanded || ai.busy)
      anchors { top: true; left: true; right: true }
      implicitHeight: 720
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-notch"
      WlrLayershell.keyboardFocus: ai.expanded && here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      // Only the island takes the pointer; the rest stays click-through.
      mask: Region { item: island }
      // A click anywhere else folds it back into the bar (it keeps working).
      OutsideClick { when: ai.expanded && win.here; windows: [win]; onOutside: ai.collapse() }

      // Ink for a dark island in both appearances.
      readonly property color ink: "#f5f5f7"
      readonly property color dim: Qt.rgba(0.96, 0.96, 0.97, 0.56)
      readonly property color faint: Qt.rgba(0.96, 0.96, 0.97, 0.3)
      readonly property color well: Qt.rgba(1, 1, 1, 0.08)
      readonly property color line: Qt.rgba(1, 1, 1, 0.1)

      // Folded: a pill in the bar; working: wider, with what it is doing.
      readonly property real foldedW: ai.busy ? Math.min(460, win.width * 0.3, statusText.implicitWidth + 86) : (ai.flash ? 210 : 132)
      Binding { target: Shell; property: "notchWidth"; value: win.foldedW; when: win.here }
      readonly property real openW: Math.min(win.width - 40, 680)
      readonly property real openH: Math.min(win.height - 40, Math.max(items.count ? 600 : 250 + (ai.attached.length ? 80 : 0), ai.picking ? picker.height + 70 : 0))

      Item {
        id: island
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        width: ai.expanded ? win.openW : win.foldedW
        height: ai.expanded ? win.openH : 30
        // Nothing inside ever shows outside the island while it grows or shrinks
        // (its top edge is the top of the screen, so nothing is lost there).
        clip: true
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
        // ---- folded content (comes back once the island has nearly closed)
        Item {
          anchors.fill: parent
          opacity: !ai.expanded && island.height < 44 ? 1 : 0
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
        scale: !ai.expanded && islandHover.hovered ? 1.04 : 1 + (drop.containsDrag && !ai.expanded ? 0.08 : 0)
        Behavior on scale { NumberAnimation { duration: Theme.fast } }

        // Files and pictures dropped on it (open or folded) go with the next message.
        DropArea {
          id: drop
          anchors.fill: parent
          keys: ["text/uri-list"]
          onEntered: ev => { if (!ev.hasUrls) ev.accepted = false }
          onDropped: ev => {
            const paths = ev.urls.map(u => u.toString()).filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.slice(7)))
            if (paths.length) { ev.acceptProposedAction(); ai.attach(paths) }
          }
        }
        Rectangle {
          anchors { fill: parent; topMargin: -radius }
          visible: drop.containsDrag
          radius: shape.radius; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
          border.width: 2; border.color: Theme.accent
          z: 10
        }

        // ---- open content
        // Laid out at the open size all the time and kept in the middle, so
        // nothing moves around while the island changes size: it is uncovered
        // as it opens, and fades out at once as it closes.
        Item {
          id: body
          anchors.horizontalCenter: parent.horizontalCenter
          y: 14
          width: win.openW - 36
          height: win.openH - 32
          opacity: ai.expanded ? 1 : 0
          visible: opacity > 0
          // Out at once when closing; in after the island has started to open.
          Behavior on opacity { NumberAnimation { id: bodyFade; duration: Prefs.motion(90) } }

          // Header
          RowLayout {
            id: head
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 28
            spacing: 10
            Image { source: Quickshell.iconPath("memora-ai"); Layout.preferredWidth: 22; Layout.preferredHeight: 22; sourceSize: Qt.size(44, 44) }
            Txt { text: "Memora AI"; color: win.ink; font.weight: Font.Bold }
            // Model · effort; a click opens the chooser.
            Rectangle {
              visible: ai.model !== ""
              implicitWidth: chip.implicitWidth + 18; implicitHeight: 22; radius: 11
              color: ai.picking || chipHover.hovered ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
              Txt {
                id: chip; anchors.centerIn: parent
                text: ai.model + (ai.canEffort && ai.effort ? " \u00b7 " + ai.effortName(ai.effort) : "") + ((ai.canModel || ai.canEffort) ? "  \u25BE" : "")
                color: win.dim; font.pixelSize: Theme.small
              }
              HoverHandler { id: chipHover; cursorShape: (ai.canModel || ai.canEffort) ? Qt.PointingHandCursor : Qt.ArrowCursor }
              TapHandler { onTapped: if (ai.canModel || ai.canEffort) ai.picking = !ai.picking }
            }
            Item { Layout.fillWidth: true }
            Pill { visible: items.count > 0; text: "New Chat"; onClicked: ai.newChat() }
            Pill { text: "Close"; onClicked: ai.collapse() }
          }

          // The model and effort chooser, over the conversation.
          Rectangle {
            id: picker
            visible: ai.picking
            z: 50
            anchors { left: parent.left; top: head.bottom; topMargin: 6 }
            width: Math.min(parent.width, 420)
            height: pickCol.implicitHeight + 24
            radius: 16
            color: "#151517"
            border.color: win.line
            ColumnLayout {
              id: pickCol
              anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
              spacing: 6
              Txt { visible: ai.canModel; text: "Model"; color: win.dim; font.pixelSize: Theme.small; font.weight: Font.Bold }
              Repeater {
                model: ai.canModel ? ai.models : []
                delegate: Rectangle {
                  required property var modelData
                  Layout.fillWidth: true; implicitHeight: 30; radius: 8
                  color: mh.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                  Txt { x: 10; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: win.ink }
                  Txt {
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: ({ "claude-fable-5-2": "most capable", "claude-opus-5-5": "deep work", "claude-sonnet-5-5": "fast and smart", "claude-haiku-5-5": "fastest" })[modelData.id] || ""
                    color: win.faint; font.pixelSize: Theme.small
                  }
                  Sym { visible: ai.modelId === modelData.id; anchors { right: parent.right; rightMargin: 110; verticalCenter: parent.verticalCenter } name: "check"; width: 12; height: 12; color: Theme.accent }
                  HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: ai.choose({ model: modelData.id }) }
                }
              }
              Txt { visible: ai.canEffort; Layout.topMargin: 6; text: "Effort \u2014 how hard it thinks before answering"; color: win.dim; font.pixelSize: Theme.small; font.weight: Font.Bold }
              Row {
                visible: ai.canEffort
                spacing: 6
                Repeater {
                  model: ai.canEffort ? ai.efforts : []
                  delegate: Rectangle {
                    required property string modelData
                    width: et2.implicitWidth + 20; height: 28; radius: 14
                    color: ai.effort === modelData ? Theme.accent : (eh.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07))
                    Txt { id: et2; anchors.centerIn: parent; text: ai.effortName(modelData); color: "#ffffff"; font.pixelSize: Theme.small }
                    HoverHandler { id: eh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: ai.choose({ effort: modelData }) }
                  }
                }
              }
              Txt { Layout.fillWidth: true; Layout.topMargin: 4; wrapMode: Text.Wrap; text: "Applies from your next message. Higher effort: better answers to hard questions, but slower."; color: win.faint; font.pixelSize: Theme.small - 0.5 }
            }
          }
          // A click outside the chooser closes it (one inside picks something).
          TapHandler {
            enabled: ai.picking
            onTapped: ev => { const p = picker.mapFromItem(parent, ev.position.x, ev.position.y); if (!picker.contains(p)) ai.picking = false }
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
            anchors { left: parent.left; right: parent.right; top: head.bottom; topMargin: 10; bottom: tray.top; bottomMargin: 10 }
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
              required property string files
              readonly property var fileList: { try { return JSON.parse(files || "[]") } catch (e) { return [] } }
              implicitHeight: kind === "user" ? ub.height + (fileList.length ? uf.height + 6 : 0) : kind === "assistant" ? at.implicitHeight + (copyRow.visible ? 26 : 2)
                : kind === "tool" ? 24 : kind === "confirm" ? cc.height : et.implicitHeight + 8

              Flow {
                id: uf
                visible: d.kind === "user" && d.fileList.length > 0
                anchors.right: parent.right
                width: Math.min(d.width * 0.75, implicitWidth); layoutDirection: Qt.RightToLeft
                spacing: 6
                Repeater { model: d.kind === "user" ? d.fileList : []; delegate: Attachment { required property var modelData; path: modelData } }
              }
              Rectangle {
                id: ub
                visible: d.kind === "user" && d.text !== ""
                anchors.right: parent.right
                y: d.fileList.length ? uf.height + 6 : 0
                width: Math.min(ut.implicitWidth + 26, d.width * 0.75); height: ut.implicitHeight + 16
                radius: 15; color: Theme.accent
                TextEdit {
                  id: ut; x: 13; y: 8; width: parent.width - 26
                  text: d.kind === "user" ? d.text : ""; color: "#ffffff"; wrapMode: Text.Wrap
                  readOnly: true; selectByMouse: true; selectionColor: Qt.rgba(1, 1, 1, 0.35)
                  font.family: Theme.font; font.pixelSize: Theme.fontSize
                }
              }
              // Answers can be selected (drag, then Ctrl+C) or copied whole.
              TextEdit {
                id: at
                visible: d.kind === "assistant"
                width: d.width - 20
                text: (d.kind === "assistant" ? d.text : "").replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1").replace(/<img\b[^>]*>/gi, "")
                textFormat: TextEdit.MarkdownText; wrapMode: TextEdit.Wrap
                readOnly: true; selectByMouse: true; persistentSelection: false
                selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45); selectedTextColor: "#ffffff"
                color: win.ink
                font.family: Theme.font; font.pixelSize: Theme.fontSize
                onLinkActivated: link => { if (/^(https?|mailto):/i.test(link)) Qt.openUrlExternally(link) }
                HoverHandler { cursorShape: at.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
              }
              Row {
                id: copyRow
                visible: d.kind === "assistant" && d.text !== "" && !(ai.busy && d.index === items.count - 1)
                anchors { top: at.bottom; topMargin: 4; left: parent.left }
                spacing: 6
                Rectangle {
                  property bool copied: false
                  width: cpt.implicitWidth + 30; height: 20; radius: 10
                  color: cph.hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.05)
                  Sym { id: cps; x: 8; anchors.verticalCenter: parent.verticalCenter; name: parent.copied ? "check" : "copy"; width: 10; height: 10; color: win.dim }
                  Txt { id: cpt; anchors { left: cps.right; leftMargin: 5; verticalCenter: parent.verticalCenter } text: parent.copied ? "Copied" : "Copy"; color: win.dim; font.pixelSize: Theme.small - 1 }
                  HoverHandler { id: cph; cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: { Quickshell.clipboardText = (at.selectedText || d.text); parent.copied = true; copiedReset.restart() } }
                  Timer { id: copiedReset; interval: 1500; onTriggered: parent.copied = false }
                }
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
                // One line, whatever the command: a multi-line one would spill over its neighbours.
                Txt { anchors.verticalCenter: parent.verticalCenter; text: d.kind === "tool" ? d.text.replace(/\s*\n\s*/g, " ⏎ ") : ""; color: win.dim; font.pixelSize: Theme.small; width: Math.min(implicitWidth, d.width - 40); elide: Text.ElideRight; maximumLineCount: 1; wrapMode: Text.NoWrap }
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

          // Attachments waiting to go with the next message.
          Flow {
            id: tray
            anchors { left: parent.left; right: parent.right; bottom: input.top; bottomMargin: ai.attached.length ? 8 : 0 }
            height: ai.attached.length ? implicitHeight : 0
            spacing: 6
            Repeater { model: ai.attached; delegate: Attachment { required property var modelData; path: modelData.path; removable: true } }
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
                  if (ai.ask(text)) text = ""
                }
                // Ctrl+V: pictures and copied files become attachments.
                Keys.onPressed: ev => {
                  if ((ev.key === Qt.Key_V && (ev.modifiers & Qt.ControlModifier)) || (ev.key === Qt.Key_Insert && (ev.modifiers & Qt.ShiftModifier))) {
                    ev.accepted = true
                    if (!paster.running) paster.running = true
                  }
                }
                Connections { target: ai; function onPasteText() { field.paste() } }
                Txt { visible: !field.text; text: ai.busy ? (ai.status || "Working…") : ai.attached.length ? "Ask about " + (ai.attached.length === 1 ? "it" : "them") : "Ask anything, or drop a file here"; color: win.faint }
              }
            }
            Rectangle {
              id: go
              anchors { right: parent.right; rightMargin: 7; bottom: parent.bottom; bottomMargin: 7 }
              width: 30; height: 30; radius: 15
              readonly property bool ready: field.text.trim() !== "" || ai.attached.length > 0
              color: ai.busy ? win.ink : (ready ? Theme.accent : win.well)
              Behavior on color { ColorAnimation { duration: Theme.fast } }
              Sym { anchors.centerIn: parent; visible: !ai.busy; name: "arrow"; width: 14; height: 14; rotation: -90; color: go.ready ? "#ffffff" : win.dim }
              Rectangle { anchors.centerIn: parent; visible: ai.busy; width: 10; height: 10; radius: 2; color: "#000" }
              HoverHandler { cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: { if (ai.busy) ai.stop(); else if (ai.ask(field.text)) field.text = "" } }
              Tip { text: ai.busy ? "Stop" : "Send"; delay: 400 }
            }
          }
          Connections { target: ai; function onExpandedChanged() { if (ai.expanded && win.here) Qt.callLater(() => field.forceActiveFocus()) } }
        }
      }
    }
  }

  component Attachment: Rectangle {
    id: at
    property string path
    property bool removable: false
    readonly property bool image: ai.imageExt.test(path)
    readonly property string name: path.split("/").pop()
    width: image ? 64 : Math.min(200, fn.implicitWidth + 40); height: image ? 64 : 34
    radius: 10; clip: true
    color: Qt.rgba(1, 1, 1, 0.09)
    border.color: Qt.rgba(1, 1, 1, 0.12)
    Image { anchors.fill: parent; visible: at.image; source: at.image ? "file://" + at.path : ""; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(128, 128) }
    Sym { visible: !at.image; x: 10; anchors.verticalCenter: parent.verticalCenter; name: "file"; width: 14; height: 14; color: "#c7c7cc" }
    Txt { id: fn; visible: !at.image; x: 30; width: parent.width - 38; anchors.verticalCenter: parent.verticalCenter; text: at.name; elide: Text.ElideMiddle; color: "#f5f5f7"; font.pixelSize: Theme.small }
    HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: Quickshell.execDetached(["xdg-open", at.path]) }
    Rectangle {
      visible: at.removable && ah.hovered
      anchors { top: parent.top; right: parent.right; margins: 3 }
      width: 18; height: 18; radius: 9; color: Qt.rgba(0, 0, 0, 0.7)
      Sym { anchors.centerIn: parent; name: "close"; width: 8; height: 8; color: "#ffffff" }
      TapHandler { onTapped: ai.detach(at.path) }
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
