pragma Singleton
import QtQuick
import Quickshell
import qs.core

// Menu bar menus. App menus work for any app by sending the standard shortcut
// to the focused window, so File > Save is Ctrl+S in every program.
Singleton {
  id: m

  function titles(desktop) {
    return [
      { id: "file", title: "File" }, { id: "edit", title: "Edit" }, { id: "view", title: "View" },
      { id: "go", title: "Go" }, { id: "window", title: "Window" }, { id: "help", title: "Help" }
    ]
  }

  function sep() { return { separator: true } }
  readonly property var keyNames: ({ ctrl: "Ctrl", shift: "Shift", alt: "Alt", comma: ",", equal: "+", minus: "-", Left: "Left", Right: "Right" })
  function label(keys) {
    return keys.split("+").map(p => m.keyNames[p] || (p.length === 1 ? p.toUpperCase() : p)).join(" ")
  }
  function k(text, keys, enabled) {
    return { text: text, keys: label(keys), action: () => Apps.keys(keys), enabled: enabled !== false }
  }
  function open(path) { Apps.run("nautilus --new-window " + path) }
  readonly property string home: Quickshell.env("HOME")

  function items(id, cls, appName, win) {
    const hasWin = !!win && cls !== ""
    switch (id) {
    case "system": return [
      { text: "About This Memora", action: () => Apps.run("memora-settings about") },
      sep(),
      { text: "System Settings…", action: () => Apps.run("memora-settings") },
      { text: "Launchpad", action: () => Shell.show("launchpad") },
      sep(),
      { text: "Force Quit " + (hasWin ? appName : "…"), enabled: hasWin, action: () => Apps.run("kill -9 " + win.lastIpcObject.pid) },
      sep(),
      { text: "Sleep", action: () => Apps.run("systemctl suspend") },
      { text: "Restart…", action: () => Apps.run("memora-power restart") },
      { text: "Shut Down…", action: () => Apps.run("memora-power shutdown") },
      sep(),
      { text: "Lock Screen", keys: "Super L", action: () => Apps.run("memora-lock") },
      { text: "Log Out " + Quickshell.env("USER") + "…", action: () => Apps.run("memora-power logout") }
    ]
    case "app": return hasWin ? [
      { text: "About " + appName, action: () => Apps.run("memora-ai ask 'What is the app " + appName.replace(/'/g, "") + " on Memora and what can it do?'") },
      sep(),
      k("Settings…", "ctrl+comma"),
      sep(),
      { text: "Hide " + appName, action: () => Apps.windowsOf(cls).forEach(w => Apps.minimize(w.address)) },
      { text: "Hide Others", action: () => Apps.windows.filter(w => Apps.classOf(w) !== cls && !Apps.isMinimized(w)).forEach(w => Apps.minimize(w.address)) },
      { text: "Show All", action: () => Apps.windows.filter(w => Apps.isMinimized(w)).forEach(w => Apps.restore(w)) },
      sep(),
      { text: "Quit " + appName, keys: "Ctrl Q", action: () => Apps.quit(cls) }
    ] : [
      { text: "About Memora", action: () => Apps.run("memora-settings about") },
      sep(),
      { text: "Settings…", action: () => Apps.run("memora-settings") },
      sep(),
      { text: "Show All", action: () => Apps.windows.filter(w => Apps.isMinimized(w)).forEach(w => Apps.restore(w)) }
    ]
    case "file": return hasWin ? [
      k("New Window", "ctrl+n"), k("New Tab", "ctrl+t"), k("Open…", "ctrl+o"),
      sep(),
      k("Save", "ctrl+s"), k("Save As…", "ctrl+shift+s"),
      sep(),
      k("Print…", "ctrl+p"),
      sep(),
      k("Close Tab", "ctrl+w"),
      { text: "Close Window", action: () => Apps.close(win) }
    ] : [
      { text: "New Files Window", keys: "Super E", action: () => m.open(m.home) },
      { text: "New Terminal", keys: "Super Return", action: () => Apps.launch("org.gnome.Ptyxis") },
      sep(),
      { text: "Open Downloads", action: () => m.open(m.home + "/Downloads") }
    ]
    case "edit": return [
      k("Undo", "ctrl+z", hasWin), k("Redo", "ctrl+shift+z", hasWin),
      sep(),
      k("Cut", "ctrl+x", hasWin), k("Copy", "ctrl+c", hasWin), k("Paste", "ctrl+v", hasWin),
      k("Select All", "ctrl+a", hasWin),
      sep(),
      k("Find…", "ctrl+f", hasWin),
      sep(),
      { text: "Clipboard History…", keys: "Super V", action: () => Shell.show("spotlight") }
    ]
    case "view": return [
      k("Zoom In", "ctrl+equal", hasWin), k("Zoom Out", "ctrl+minus", hasWin), k("Actual Size", "ctrl+0", hasWin),
      sep(),
      k("Reload", "ctrl+r", hasWin),
      sep(),
      { text: "Enter Full Screen", keys: "F11", enabled: hasWin, action: () => Apps.dispatch('hl.dsp.window.fullscreen({ mode = "fullscreen" })') },
      sep(),
      { text: Theme.dark ? "Use Light Appearance" : "Use Dark Appearance", action: () => Apps.run("memora-theme next") }
    ]
    case "go": return [
      k("Back", "alt+Left", hasWin), k("Forward", "alt+Right", hasWin),
      sep(),
      { text: "Home", action: () => m.open(m.home) },
      { text: "Desktop", action: () => m.open(m.home + "/Desktop") },
      { text: "Documents", action: () => m.open(m.home + "/Documents") },
      { text: "Downloads", action: () => m.open(m.home + "/Downloads") },
      { text: "Applications", action: () => Shell.show("launchpad") },
      sep(),
      { text: "Trash", action: () => m.open("trash:///") }
    ]
    case "window": return [
      { text: "Minimize", keys: "Super M", enabled: hasWin, action: () => Apps.minimize(win.address) },
      { text: "Zoom", enabled: hasWin, action: () => Apps.zoom(win) },
      { text: "Fill", keys: "Super Up", enabled: hasWin, action: () => Apps.run("memora-window fill") },
      { text: "Center", keys: "Super C", enabled: hasWin, action: () => Apps.run("memora-window center") },
      sep(),
      { text: "Move to Left Half", keys: "Super Left", enabled: hasWin, action: () => Apps.run("memora-window left") },
      { text: "Move to Right Half", keys: "Super Right", enabled: hasWin, action: () => Apps.run("memora-window right") },
      { text: "Tile Window", keys: "Super T", enabled: hasWin, action: () => Apps.dispatch('hl.dsp.window.float({ action = "toggle" })') },
      sep(),
      { text: "Show All Windows", action: () => Apps.windows.filter(w => Apps.isMinimized(w)).forEach(w => Apps.restore(w)) },
      sep(),
      { text: "Close Window", keys: "Alt F4", enabled: hasWin, action: () => Apps.close(win) }
    ]
    case "help": return [
      { text: "Ask Memora AI…", keys: "Super A", action: () => Apps.run("memora-ai window") },
      { text: "Keyboard Shortcuts", action: () => Apps.run("memora-keys") },
      sep(),
      { text: "About Memora", action: () => Apps.run("memora-settings about") }
    ]
    }
    return []
  }
}
