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
    "org.gnome.Nautilus": "Files", "memora-files": "Files", "memora-notes": "Notes", "memora-store": "App Store", "chromium": "Browser", "org.gnome.Ptyxis": "Terminal",
    "kitty": "Terminal", "memora-ai": "Memora AI", "memora-settings": "Settings",
    "org.gnome.TextEditor": "Text Editor", "org.gnome.Calculator": "Calculator",
    "org.gnome.Papers": "Documents", "org.gnome.Loupe": "Photos", "mpv": "Media Player",
    "memora-store": "App Store", "memora-photos": "Gallery", "memora-player": "Music", "com.mitchellh.ghostty": "Terminal", "memora-float": "Memora", "memora-activity": "Activity Monitor", "memora-welcome": "Welcome", "gcr-prompter": "Passwords", "": "Files"
  })

  function nameFor(appId) {
    if (names[appId] !== undefined) return names[appId]
    const e = entry(appId)
    if (e) return e.name
    // A reverse-DNS id (org.gimp.GIMP) whose entry isn't known yet: its last part.
    if (appId && appId.indexOf(".") > 0) return appId.split(".").pop().replace(/[-_]/g, " ")
    return appId || "Files"
  }

  // Icons drawn for Memora (tools/icons.py); others are shown on a tile.
  readonly property var nativeIcons: ["memora-store", "memora-photos", "memora-player", "com.mitchellh.ghostty", "memora-files", "memora-notes", "org.gnome.Nautilus", "memora-launchpad", "chromium", "org.gnome.Ptyxis",
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
  // Apps Memora has its own version of: kept installed (files open in them, the
  // Trash uses Nautilus) but not listed twice in Launchpad and Spotlight.
  readonly property var duplicates: ["org.gnome.Nautilus", "org.gnome.Loupe", "mpv", "org.gnome.Ptyxis"]
  // The name an app goes by in Memora (Ghostty is "Terminal").
  function displayName(e) { return !e.id.startsWith("memora-") && names[e.id] ? names[e.id] : e.name }
  readonly property var all: {
    const list = DesktopEntries.applications.values.filter(e => !e.noDisplay && duplicates.indexOf(e.id) < 0)
    list.sort((a, b) => displayName(a).localeCompare(displayName(b)))
    return list
  }

  // ---- dock: pinned apps, kept in ~/.config/memora/dock ---------------------
  readonly property var defaultPinned: [
    "memora-files", "memora-launchpad", "chromium", "com.mitchellh.ghostty",
    "memora-notes", "memora-photos",
    "memora-store", "memora-settings"
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

  // Windows docked together (memora-window keeps them in ~/.cache/memora/windows.json):
  // bringing one forward brings the others too, so a split comes back whole.
  property var docked: ({})
  property FileView dockedFile: FileView {
    path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/memora/windows.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { apps.docked = JSON.parse(text()) } catch (e) { apps.docked = {} } }
  }
  function groupOf(w) {
    const a = "0x" + addrKey(w.address), g = (docked[a] || {}).group
    if (!g) return []
    return windows.filter(x => x !== w && (docked["0x" + addrKey(x.address)] || {}).group === g && !isMinimized(x)
      && x.workspace && w.workspace && x.workspace.id === w.workspace.id)
  }
  function focus(w) {
    if (isMinimized(w)) return restore(w)
    groupOf(w).forEach(x => dispatch('hl.dsp.window.alter_zorder({ mode = "top", window = "' + sel(x.address) + '" })'))
    dispatch('hl.dsp.focus({ window = "' + sel(w.address) + '" })')
    // Floating windows: also bring it in front of the others.
    dispatch('hl.dsp.window.alter_zorder({ mode = "top", window = "' + sel(w.address) + '" })')
  }
  // Minimizing plays the Genie animation (dock/Genie.qml), which then calls finishMinimize.
  signal minimizing(string addr, var win, rect from)
  signal restoring(string addr, var win, rect to)
  property point dockTarget: Qt.point(0, 0)      // where minimized windows land, set by the Dock
  function byAddr(addr) {
    const a = String(addr).replace(/^0x/, "")
    return Hyprland.toplevels.values.find(t => String(t.address).replace(/^0x/, "") === a) || null
  }
  function rectOf(w) {
    const o = w && w.lastIpcObject
    return o && o.at ? Qt.rect(o.at[0], o.at[1], o.size[0], o.size[1]) : Qt.rect(0, 0, 0, 0)
  }
  function minimize(addr) {
    const w = byAddr(addr)
    if (w && isMinimized(w)) return
    minimizing(String(addr), w, rectOf(w))
  }
  function finishMinimize(addr) {
    dispatch('hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "' + sel(addr) + '" })')
  }
  function restore(w) { restoring(String(w.address), w, rectOf(w)) }
  function finishRestore(addr) {
    const ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = true, window = "' + sel(addr) + '" })')
    dispatch('hl.dsp.focus({ window = "' + sel(addr) + '" })')
  }
  // Semi full screen: the window fills the screen under the menu bar and the
  // Dock steps aside (it comes back at the bottom edge). Again to leave.
  function addrKey(a) { return String(a).replace(/^0x/, "") }
  function forgetSemi(a) { const k = addrKey(a); if (Shell.semi[k]) { const s = Object.assign({}, Shell.semi); delete s[k]; Shell.semi = s } }
  function semiFullscreen() {
    const t = Hyprland.activeToplevel
    if (!t) return
    const k = addrKey(t.address)
    const w = windows.find(x => addrKey(x.address) === k)
    const maximized = w && w.lastIpcObject && w.lastIpcObject.fullscreen === 1
    const s = Object.assign({}, Shell.semi)
    if (s[k]) {
      delete s[k]
      if (maximized) dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })')
    } else {
      s[k] = true
      if (w && w.lastIpcObject && w.lastIpcObject.fullscreen === 2) dispatch('hl.dsp.window.fullscreen({ mode = "fullscreen" })')
      if (!maximized) dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })')
    }
    Shell.semi = s
  }
  function close(w) { if (w && w.wayland) w.wayland.close() }
  function zoom(w) {
    forgetSemi(w.address)
    dispatch('hl.dsp.focus({ window = "' + sel(w.address) + '" })')
    dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })')
  }

  // Dock click, as on a Mac: an app that isn't open opens; an open one comes to
  // the front with all its windows (on this desktop, else where they are), the
  // one used last on top; if all its windows are minimized, the last one comes
  // back. Clicking the app already in front leaves it as it is.
  function activate(appId) {
    if (appId === "memora-launchpad") return Shell.toggle("launchpad")
    const ws = windowsOf(appId)
    if (ws.length === 0) return launch(appId)
    const shown = ws.filter(w => !isMinimized(w))
    const recent = list => list.slice().sort((a, b) => (a.lastIpcObject.focusHistoryID ?? 99) - (b.lastIpcObject.focusHistoryID ?? 99))
    if (shown.length === 0) return restore(recent(ws)[0])
    if (shown.some(w => w.activated)) return
    const cur = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    const here = shown.filter(w => w.workspace && w.workspace.id === cur)
    const pick = recent(here.length ? here : shown)
    // The others first, so the last used ends on top.
    pick.slice(1).reverse().forEach(w => dispatch('hl.dsp.window.alter_zorder({ mode = "top", window = "' + sel(w.address) + '" })'))
    focus(pick[0])
  }

  function quit(appId) { windowsOf(appId).forEach(w => close(w)) }

  // Apps from the App Store (Flathub) can be uninstalled from their menu.
  function removable(appId) {
    const e = entry(appId)
    return !!(e && /\bflatpak\b.*\brun\b/.test(e.execString || "") && appId.indexOf(".") > 0)
  }
  function uninstall(appId) {
    if (!removable(appId)) return
    const name = nameFor(appId), id = appId.replace(/\.desktop$/, "")
    Shell.ask({ title: "Uninstall " + name + "?", sym: "close", danger: true, action: "Uninstall",
      message: name + " will be removed from this computer. Your documents stay, and so do its settings, in case you get it again from the App Store.",
      onAccept: () => {
        quit(appId)
        run("if flatpak uninstall --user -y --noninteractive '" + id + "' || pkexec flatpak uninstall --system -y --noninteractive '" + id + "'; then notify-send -a 'App Store' '" + name.replace(/'/g, "") + " was uninstalled'; else notify-send -a 'App Store' 'Couldn'\\''t uninstall " + name.replace(/'/g, "") + "'; fi")
        unpin(appId)
      } })
  }

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
