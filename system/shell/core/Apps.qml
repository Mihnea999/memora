pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

// Applications and their windows: desktop entries, icons, launching, the dock's
// pinned list, and the window actions the bar, dock and switcher share.
Singleton {
  id: apps

  // ---- desktop entries ------------------------------------------------------
  function entry(appId) {
    if (!appId) return null
    return DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId)
  }

  // Friendly names for windows whose desktop entry is missing or generic.
  readonly property var names: ({
    "org.gnome.Nautilus": "Files", "chromium": "Browser", "org.gnome.Ptyxis": "Terminal",
    "kitty": "Terminal", "memora-ai": "Memora AI", "memora-settings": "Settings",
    "org.gnome.TextEditor": "Text Editor", "org.gnome.Calculator": "Calculator",
    "org.gnome.Papers": "Documents", "org.gnome.Loupe": "Photos", "mpv": "Media Player",
    "memora-float": "Memora", "memora-activity": "Activity Monitor", "memora-welcome": "Welcome", "gcr-prompter": "Passwords", "": "Files"
  })

  function nameFor(appId) {
    if (names[appId] !== undefined) return names[appId]
    const e = entry(appId)
    return e ? e.name : (appId || "Files")
  }

  // Icons drawn for Memora (tools/icons.py); others are shown on a tile.
  readonly property var nativeIcons: ["org.gnome.Nautilus", "memora-launchpad", "chromium", "org.gnome.Ptyxis",
    "kitty", "memora-ai", "org.gnome.TextEditor", "org.gnome.Calculator", "org.gnome.Loupe", "org.gnome.Papers",
    "mpv", "memora-settings", "memora-activity", "folder", "folder-download", "user-trash", "user-trash-full"]

  function iconNameFor(appId) {
    if (appId === "memora-launchpad" || appId === "memora-settings") return appId
    const e = entry(appId)
    return e && e.icon ? e.icon : appId
  }

  function iconFor(appId) {
    const e = entry(appId)
    const name = e && e.icon ? e.icon : appId
    return Quickshell.iconPath(name, "application-x-executable")
  }

  function launch(id) {
    // uwsm puts each app in its own systemd scope, so it outlives the shell.
    Quickshell.execDetached(["uwsm", "app", "--", id.endsWith(".desktop") ? id : id + ".desktop"])
  }

  function run(cmd) { Quickshell.execDetached(["bash", "-c", cmd]) }

  // ---- visible applications (Launchpad, Spotlight) --------------------------
  readonly property var all: {
    const list = DesktopEntries.applications.values.filter(e => !e.noDisplay)
    list.sort((a, b) => a.name.localeCompare(b.name))
    return list
  }

  // ---- dock: pinned apps, kept in ~/.config/memora/dock ---------------------
  readonly property var defaultPinned: [
    "org.gnome.Nautilus", "memora-launchpad", "chromium", "org.gnome.Ptyxis", "memora-ai",
    "org.gnome.TextEditor", "org.gnome.Calculator", "org.gnome.Loupe", "org.gnome.Papers",
    "mpv", "memora-settings"
  ]
  property var pinned: defaultPinned

  property FileView dockFile: FileView {
    path: Quickshell.env("HOME") + "/.config/memora/dock"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      const ids = text().split("\n").map(s => s.trim()).filter(s => s.length > 0)
      apps.pinned = ids.length > 0 ? ids : apps.defaultPinned
    }
    onLoadFailed: apps.pinned = apps.defaultPinned
  }

  function savePinned(list) {
    pinned = list
    dockFile.setText(list.join("\n") + "\n")
  }
  function pin(id) { if (pinned.indexOf(id) < 0) savePinned(pinned.concat([id])) }
  function unpin(id) { savePinned(pinned.filter(p => p !== id)) }

  // ---- windows ---------------------------------------------------------------
  // Every mapped window, with its class and whether it sits minimized in the dock.
  readonly property var windows: Hyprland.toplevels.values.filter(w => w.lastIpcObject && w.lastIpcObject.class !== undefined)

  function classOf(w) { return w && w.lastIpcObject ? (w.lastIpcObject.class || "") : "" }
  function isMinimized(w) { return w && w.workspace && w.workspace.name === "special:minimized" }
  function windowsOf(appId) { return windows.filter(w => sameApp(classOf(w), appId)) }
  function sameApp(cls, appId) {
    if (cls === appId) return true
    const e = entry(appId)
    return !!(e && e.startupClass && e.startupClass === cls)
  }

  // Focused app, from Hyprland's activewindow event ("class,title"; empty on the desktop).
  property string activeClass: ""
  readonly property var helperClasses: ["xdg-desktop-portal-gtk", "xdg-desktop-portal-gnome", "gcr-prompter", "org.gnome.Nautilus.FileChooser"]
  property Process activeProc: Process {
    running: true
    command: ["hyprctl", "-j", "activewindow"]
    stdout: StdioCollector { onStreamFinished: { try { apps.activeClass = JSON.parse(text).class || "" } catch (e) { apps.activeClass = "" } } }
  }

  Connections {
    target: Hyprland
    function onRawEvent(ev) {
      if (ev.name === "activewindow") {
        const c = ev.data.split(",")[0]
        // File dialogs and password prompts belong to the app that opened them:
        // the menu bar keeps that app's name.
        if (apps.helperClasses.indexOf(c) < 0) apps.activeClass = c
      }
      if (["openwindow", "closewindow", "movewindowv2", "windowtitlev2", "activewindowv2"].indexOf(ev.name) >= 0)
        Hyprland.refreshToplevels()
      // An app asked to be minimized (its yellow button): park it in the dock.
      if (ev.name === "minimized") {
        const parts = ev.data.split(",")
        if (parts[1] === "1") apps.minimize("0x" + parts[0].replace(/^0x/, ""))
      }
    }
  }

  function sel(addr) { return "address:" + (String(addr).startsWith("0x") ? addr : "0x" + addr) }
  function dispatch(lua) { Hyprland.dispatch(lua) }

  function focus(w) {
    if (isMinimized(w)) return restore(w)
    dispatch('hl.dsp.focus({ window = "' + sel(w.address) + '" })')
  }
  function minimize(addr) {
    dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "' + sel(addr) + '" })')
  }
  function restore(w) {
    const ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = true, window = "' + sel(w.address) + '" })')
    dispatch('hl.dsp.focus({ window = "' + sel(w.address) + '" })')
  }
  function close(w) { if (w && w.wayland) w.wayland.close() }
  function zoom(w) {
    dispatch('hl.dsp.focus({ window = "' + sel(w.address) + '" })')
    dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })')
  }

  // Dock click: open the app, bring its window forward, or cycle its windows.
  function activate(appId) {
    if (appId === "memora-launchpad") return Shell.toggle("launchpad")
    const ws = windowsOf(appId)
    if (ws.length === 0) return launch(appId)
    const active = ws.find(w => w.activated)
    if (active && ws.length === 1) return minimize(active.address)
    const next = active ? ws[(ws.indexOf(active) + 1) % ws.length] : ws[0]
    focus(next)
  }

  function quit(appId) { windowsOf(appId).forEach(w => close(w)) }

  // Send a shortcut to the focused window (menu bar items).
  function keys(combo) {
    // combo like "ctrl+shift+z"
    const parts = combo.split("+")
    const key = parts.pop()
    const args = ["wtype"]
    parts.forEach(m => { args.push("-M"); args.push(m) })
    args.push("-k"); args.push(key)
    parts.reverse().forEach(m => { args.push("-m"); args.push(m) })
    keysProc.command = ["bash", "-c", "sleep 0.12; " + args.map(a => "'" + a + "'").join(" ")]
    keysProc.running = true
  }
  property Process keysProc: Process {}
}
