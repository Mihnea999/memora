import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import qs.core
import qs.ui

// Spotlight: one field for apps, files, quick maths, settings and asking the AI.
PanelWindow {
  id: sp
  required property var modelData
  screen: modelData
  readonly property string mode: ["spotlight", "clipboard", "keys"].indexOf(Shell.open) >= 0 ? Shell.open : ""
  readonly property bool open: mode !== "" && (!Shell.menuScreen || Shell.menuScreen === modelData.name || Quickshell.screens.length === 1)

  visible: open || anim.running
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "memora-spotlight"
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  color: "transparent"

  property real shown: open ? 1 : 0
  Behavior on shown { NumberAnimation { id: anim; duration: Theme.normal; easing.type: Theme.easing } }

  property string query: ""
  property int current: 0
  property var files: []

  onOpenChanged: if (open) { field.text = ""; query = ""; current = 0; files = []; field.forceActiveFocus(); if (mode === "clipboard") clipProc.running = true; if (mode === "keys") keysProc.running = true }
  property var clips: []
  property var binds: []
  Process {
    id: clipProc
    command: ["cliphist", "list"]
    stdout: StdioCollector { onStreamFinished: sp.clips = text.split("\n").filter(l => l).slice(0, 200).map(l => { const t = l.indexOf("\t"); return { id: l.slice(0, t), text: l.slice(t + 1) } }) }
  }
  Process {
    id: keysProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        let list = []
        try { list = JSON.parse(text) } catch (e) {}
        const mods = m => [m & 64 ? "Super" : "", m & 4 ? "Ctrl" : "", m & 8 ? "Alt" : "", m & 1 ? "Shift" : ""].filter(x => x)
        const seen = {}
        sp.binds = list.filter(b => b.has_description && !seen[b.description] && (seen[b.description] = true))
          .map(b => ({ keys: mods(b.modmask).concat([b.key.replace("SUPER_L", "").replace("ALT_L", "")]).filter(x => x).join(" + "), text: b.description }))
      }
    }
  }

  // ---- results ---------------------------------------------------------------
  readonly property var settingsPages: [
    ["Wi-Fi", "wifi"], ["Bluetooth", "bluetooth"], ["Sound", "sound"], ["Displays", "displays"],
    ["Appearance", "appearance"], ["Wallpaper", "wallpaper"], ["Dock & Menu Bar", "dock"], ["Windows & Desktops", "windows"], ["Animations", "animations"],
    ["Keyboard", "keyboard"], ["Mouse & Trackpad", "mouse"], ["Battery", "battery"],
    ["Date & Time", "datetime"], ["Users", "users"], ["Privacy & Security", "privacy"], ["Memora AI", "ai"], ["Software Update", "update"], ["About", "about"]
  ]

  function calc(q) {
    if (!/^[\d\s.+\-*/%()^,]+$/.test(q) || !/\d/.test(q) || !/[+\-*/%^]/.test(q)) return null
    try {
      const v = Function('"use strict"; return (' + q.replace(/\^/g, "**").replace(/,/g, ".") + ")")()
      return (typeof v === "number" && isFinite(v)) ? String(Math.round(v * 1e10) / 1e10) : null
    } catch (e) { return null }
  }

  readonly property var results: {
    const q = query.trim()
    const lq0 = q.toLowerCase()
    if (mode === "clipboard")
      return clips.filter(c => !q || c.text.toLowerCase().indexOf(lq0) >= 0).slice(0, 40).map(c => ({ kind: "clip", title: c.text.slice(0, 120), sub: "Copy again", icon: "", iconName: "edit-paste", run: () => Apps.run("cliphist decode " + c.id + " | wl-copy") }))
    if (mode === "keys")
      return binds.filter(b => !q || b.text.toLowerCase().indexOf(lq0) >= 0 || b.keys.toLowerCase().indexOf(lq0) >= 0).map(b => ({ kind: "key", title: b.text, sub: b.keys, icon: "", iconName: "preferences-desktop-keyboard", run: () => {} }))
    if (!q) return []
    const lq = q.toLowerCase()
    const out = []
    const c = calc(q)
    if (c !== null) out.push({ kind: "calc", title: c, sub: q + " =", icon: "org.gnome.Calculator", run: () => Apps.run("printf %s '" + c + "' | wl-copy") })
    const apps = Apps.all.filter(e => e.name.toLowerCase().indexOf(lq) >= 0 || (e.keywords || []).some(k => k.toLowerCase().indexOf(lq) >= 0) || (e.genericName || "").toLowerCase().indexOf(lq) >= 0)
    apps.sort((a, b) => (a.name.toLowerCase().startsWith(lq) ? 0 : 1) - (b.name.toLowerCase().startsWith(lq) ? 0 : 1))
    apps.slice(0, 6).forEach(e => out.push({ kind: "app", title: e.name, sub: e.comment || e.genericName || "Application", icon: e.id, run: () => Apps.launch(e.id) }))
    settingsPages.filter(p => p[0].toLowerCase().indexOf(lq) >= 0).slice(0, 3).forEach(p =>
      out.push({ kind: "setting", title: p[0], sub: "System Settings", icon: "memora-settings", run: () => Apps.run("memora-settings " + p[1]) }))
    files.slice(0, 6).forEach(f => out.push({ kind: "file", title: f.split("/").pop(), sub: f.replace(Quickshell.env("HOME"), "~"), iconName: "folder", run: () => Apps.run("xdg-open '" + f.replace(/'/g, "'\\''") + "'") }))
    out.push({ kind: "ai", title: "Ask Memora AI", sub: q, icon: "memora-ai", run: () => Quickshell.execDetached(["memora-ai", "window", q]) })
    return out
  }
  onResultsChanged: current = Math.min(current, Math.max(0, results.length - 1))

  Process {
    id: finder
    stdout: StdioCollector { onStreamFinished: sp.files = text.split("\n").filter(l => l.length) }
  }
  Timer {
    id: findLater
    interval: 220
    onTriggered: {
      const q = sp.query.trim()
      if (q.length < 2) { sp.files = []; return }
      finder.running = false
      finder.command = ["bash", "-c", "find \"$HOME\" -maxdepth 4 -not -path '*/.*' -iname \"*$1*\" 2>/dev/null | head -20", "_", q]
      finder.running = true
    }
  }

  function go(i) {
    const r = results[i]
    if (!r) return
    Shell.close()
    r.run()
  }

  // ---- view -----------------------------------------------------------------
  Item { id: full; anchors.fill: parent }
  TapHandler { onTapped: ev => { if (!card.contains(card.mapFromItem(sp.contentItem, ev.position.x, ev.position.y))) Shell.close() } }

  Glass {
    id: card
    width: 680
    height: 60 + (list.count ? Math.min(list.contentHeight, 440) + 14 : 0)
    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height * 0.22 - 10 * (1 - sp.shown)
    opacity: sp.shown
    radius: 22
    fill: Theme.glassStrong
    shadowSize: 40
    Behavior on height { NumberAnimation { duration: Theme.fast; easing.type: Theme.easing } }

    TapHandler {}   // keep clicks on the card from closing it

    Sym { id: lens; name: "search"; width: 22; height: 22; color: Theme.textDim; anchors { left: parent.left; leftMargin: 20; top: parent.top; topMargin: 19 } }
    TextInput {
      id: field
      anchors { left: lens.right; leftMargin: 14; right: parent.right; rightMargin: 20; top: parent.top; topMargin: 15 }
      height: 30
      color: Theme.text
      font.family: Theme.font; font.pixelSize: 22
      verticalAlignment: TextInput.AlignVCenter
      selectionColor: Theme.accent
      onTextChanged: { sp.query = text; sp.current = 0; findLater.restart() }
      Keys.onEscapePressed: Shell.close()
      Keys.onReturnPressed: sp.go(sp.current)
      Keys.onDownPressed: sp.current = Math.min(sp.results.length - 1, sp.current + 1)
      Keys.onUpPressed: sp.current = Math.max(0, sp.current - 1)
      Keys.onTabPressed: sp.current = (sp.current + 1) % Math.max(1, sp.results.length)
      Txt { visible: !field.text; text: sp.mode === "clipboard" ? "Clipboard History" : (sp.mode === "keys" ? "Keyboard Shortcuts" : "Spotlight Search"); color: Theme.textFaint; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
    }

    Rectangle { visible: list.count > 0; anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 60 } height: 1; color: Theme.separator }

    ListView {
      id: list
      anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 67; bottom: parent.bottom; bottomMargin: 7; leftMargin: 8; rightMargin: 8 }
      clip: true
      model: sp.results
      currentIndex: sp.current
      boundsBehavior: Flickable.StopAtBounds
      delegate: Item {
        required property var modelData
        required property int index
        width: list.width
        height: 48
        Rectangle {
          anchors.fill: parent
          radius: 10
          color: index === sp.current ? Theme.accent : (h.hovered ? Theme.hover : "transparent")
        }
        AppIcon {
          id: ri
          width: 32; height: 32
          anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
          appId: modelData.icon || ""
          iconName: modelData.iconName || ""
        }
        Column {
          anchors { left: ri.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
          Txt { width: parent.width; text: modelData.title; font.weight: Font.Medium; color: index === sp.current ? Theme.accentText : Theme.text }
          Txt { width: parent.width; text: modelData.sub; font.pixelSize: Theme.small; color: index === sp.current ? Qt.rgba(1, 1, 1, 0.75) : Theme.textDim }
        }
        HoverHandler { id: h; onHoveredChanged: if (hovered) sp.current = index }
        TapHandler { onTapped: sp.go(index) }
      }
    }
  }
}
