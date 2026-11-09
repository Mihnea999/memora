pragma Singleton
import QtQuick
import Quickshell
import qs.core

// Menu bar menus. App menus work for any app by sending the standard shortcut
// to the focused window, so File > Save is Ctrl+S in every program.
Singleton {
  id: m

  // Each app gets its own menus, as on a Mac; unknown apps get the standard set.
  // An app's spec lists its menus in order; each menu is either its own item list
  // or "std" for Memora's standard one of that name.
  function spec(cls) {
    const S = sep()
    switch (cls) {
    case "chromium": case "google-chrome": case "firefox": case "brave-browser": return [
      ["File", [k("New Tab", "ctrl+t"), k("New Window", "ctrl+n"), k("New Private Window", "ctrl+shift+n"), S,
                k("Open Location…", "ctrl+l"), k("Open File…", "ctrl+o"), S, k("Close Tab", "ctrl+w"), k("Close Window", "ctrl+shift+w"), S,
                k("Save Page As…", "ctrl+s"), k("Print…", "ctrl+p")]],
      ["Edit", "std"],
      ["View", [k("Reload Page", "ctrl+r"), k("Force Reload", "ctrl+shift+r"), S, k("Actual Size", "ctrl+0"), k("Zoom In", "ctrl+equal"), k("Zoom Out", "ctrl+minus"), S,
                k("Enter Full Screen", "F11"), k("Developer Tools", "ctrl+shift+i")]],
      ["History", [k("Back", "alt+Left"), k("Forward", "alt+Right"), S, k("Reopen Closed Tab", "ctrl+shift+t"), k("Show All History", "ctrl+h")]],
      ["Bookmarks", [k("Bookmark This Page…", "ctrl+d"), k("Bookmark Manager", "ctrl+shift+o"), k("Show Bookmarks Bar", "ctrl+shift+b")]],
      ["Tab", [k("Next Tab", "ctrl+Tab"), k("Previous Tab", "ctrl+shift+Tab"), S, k("Downloads", "ctrl+j")]],
      ["Window", "std"], ["Help", "std"]]
    case "com.mitchellh.ghostty": case "org.gnome.Ptyxis": case "kitty": return [
      ["Shell", [k("New Window", "ctrl+shift+n"), k("New Tab", "ctrl+shift+t"), S, k("Close Tab", "ctrl+shift+w"), S,
                 { text: "Ask Memora AI About Terminal…", action: () => Apps.run("memora-ai window") }]],
      ["Edit", [k("Copy", "ctrl+shift+c"), k("Paste", "ctrl+shift+v"), k("Select All", "ctrl+shift+a"), S, k("Find…", "ctrl+shift+f"), S,
                { text: "Clipboard History…", keys: "Super V", action: () => Shell.show("clipboard") }]],
      ["View", [k("Bigger", "ctrl+plus"), k("Smaller", "ctrl+minus"), k("Actual Size", "ctrl+0"), S, k("Enter Full Screen", "F11")]],
      ["Window", "std"], ["Help", "std"]]
    case "memora-files": case "org.gnome.Nautilus": return [
      ["File", [k("New Window", "ctrl+n"), k("New Folder", "ctrl+shift+n"), S, k("Open", "Return"), k("Rename…", "F2"), S,
                k("Move to Trash", "Delete"), S, k("Close Window", "ctrl+w")]],
      ["Edit", [k("Undo", "ctrl+z"), S, k("Cut", "ctrl+x"), k("Copy", "ctrl+c"), k("Paste", "ctrl+v"), k("Select All", "ctrl+a"), S, k("Find…", "ctrl+f")]],
      ["View", [k("as Icons", "ctrl+1"), k("as List", "ctrl+2"), S, k("Show Hidden Files", "ctrl+h"), S, k("Bigger Icons", "ctrl+equal"), k("Smaller Icons", "ctrl+minus")]],
      ["Go", [k("Back", "alt+Left"), k("Forward", "alt+Right"), k("Enclosing Folder", "alt+Up"), S,
              k("Home", "alt+Home"), { text: "Desktop", action: () => m.open(m.home + "/Desktop") }, { text: "Documents", action: () => m.open(m.home + "/Documents") },
              { text: "Downloads", action: () => m.open(m.home + "/Downloads") }, { text: "Applications", action: () => Shell.show("launchpad") }, S,
              k("Go to Folder…", "ctrl+l")]],
      ["Window", "std"], ["Help", "std"]]
    case "memora-notes": return [
      ["File", [k("New Note", "ctrl+n"), k("New Folder", "ctrl+shift+n"), S, k("Delete Note", "ctrl+BackSpace"), S, k("Export as Text…", "ctrl+e")]],
      ["Edit", [k("Undo", "ctrl+z"), k("Redo", "ctrl+shift+z"), S, k("Cut", "ctrl+x"), k("Copy", "ctrl+c"), k("Paste", "ctrl+v"), k("Select All", "ctrl+a"), S, k("Find in Notes…", "ctrl+f")]],
      ["Format", [k("Title", "ctrl+1"), k("Heading", "ctrl+2"), k("Body", "ctrl+0"), S, k("Checklist", "ctrl+shift+l"), k("Bulleted List", "ctrl+shift+8"), S,
                  k("Bold", "ctrl+b"), k("Italic", "ctrl+i"), k("Strikethrough", "ctrl+shift+x")]],
      ["View", [k("Show Folders", "ctrl+alt+s"), S, k("Bigger Text", "ctrl+equal"), k("Smaller Text", "ctrl+minus")]],
      ["Window", "std"], ["Help", "std"]]
    case "org.gnome.TextEditor": return [
      ["File", [k("New", "ctrl+n"), k("Open…", "ctrl+o"), S, k("Save", "ctrl+s"), k("Save As…", "ctrl+shift+s"), S, k("Print…", "ctrl+p"), S, k("Close", "ctrl+w")]],
      ["Edit", "std"],
      ["View", [k("Bigger", "ctrl+plus"), k("Smaller", "ctrl+minus"), k("Actual Size", "ctrl+0"), S, k("Enter Full Screen", "F11")]],
      ["Window", "std"], ["Help", "std"]]
    case "org.gnome.Loupe": return [
      ["File", [k("Open…", "ctrl+o"), S, k("Copy Image", "ctrl+c"), k("Move to Trash", "Delete"), S, k("Close", "ctrl+w")]],
      ["View", [k("Zoom In", "ctrl+equal"), k("Zoom Out", "ctrl+minus"), k("Best Fit", "ctrl+0"), S, k("Rotate Left", "ctrl+Left"), k("Rotate Right", "ctrl+Right"), S, k("Enter Full Screen", "F11")]],
      ["Go", [k("Previous Image", "Left"), k("Next Image", "Right")]],
      ["Window", "std"], ["Help", "std"]]
    case "org.gnome.Calculator": return [
      ["Edit", [k("Copy Result", "ctrl+c"), k("Paste", "ctrl+v"), S, k("Clear", "Escape")]],
      ["View", [k("Basic", "ctrl+b"), k("Advanced", "ctrl+a"), k("Programming", "ctrl+p"), k("Financial", "ctrl+f"), k("Conversion", "ctrl+k")]],
      ["Window", "std"], ["Help", "std"]]
    case "mpv": return [
      ["Playback", [k("Play / Pause", "space"), S, k("Back 10 Seconds", "Left"), k("Forward 10 Seconds", "Right"), S, k("Louder", "0"), k("Quieter", "9"), k("Mute", "m")]],
      ["View", [k("Enter Full Screen", "f"), k("Show Info", "i")]],
      ["Window", "std"], ["Help", "std"]]
    case "memora-settings": case "memora-ai": case "memora-activity": case "memora-welcome": return [
      ["Edit", "std"], ["Window", "std"], ["Help", "std"]]
    case "": return [["File", "std"], ["Edit", "std"], ["View", "std"], ["Go", "std"], ["Window", "std"], ["Help", "std"]]
    }
    return [["File", "std"], ["Edit", "std"], ["View", "std"], ["Window", "std"], ["Help", "std"]]
  }

  function titles(cls) { return spec(cls).map((e, i) => ({ id: "m" + i + ":" + e[0], title: e[0] })) }

  function sep() { return { separator: true } }
  readonly property var keyNames: ({ ctrl: "Ctrl", shift: "Shift", alt: "Alt", comma: ",", equal: "+", minus: "-", Left: "Left", Right: "Right" })
  function label(keys) {
    return keys.split("+").map(p => m.keyNames[p] || (p.length === 1 ? p.toUpperCase() : p)).join(" ")
  }
  function k(text, keys, enabled) {
    return { text: text, keys: label(keys), action: () => Apps.keys(keys), enabled: enabled !== false }
  }
  function open(path) { Apps.run("memora-files '" + path + "'") }
  readonly property string home: Quickshell.env("HOME")

  function items(id, cls, appName, win) {
    const hasWin = !!win && cls !== ""
    if (id.startsWith("m")) {
      const name = id.slice(id.indexOf(":") + 1)
      const e = spec(cls).find(x => x[0] === name)
      if (e && e[1] !== "std") return e[1]
      id = name.toLowerCase()
    }
    switch (id) {
    case "overflow": return Shell.moreMenus.map(t => ({ text: t.title, action: () => Shell.openMenu(t.id, Shell.menuX, Shell.menuScreen) }))
    case "system": return [
      { text: "About This Memora", action: () => Apps.run("memora-settings about") },
      sep(),
      { text: "System Settings…", action: () => Apps.run("memora-settings") },
      { text: "App Store…", action: () => Apps.run("gtk-launch memora-store") },
      { text: "Software Update…", action: () => Apps.run("memora-settings update") },
      { text: "Apps", action: () => Shell.show("launchpad") },
      sep(),
      { text: "Force Quit " + (hasWin ? appName : "…"), enabled: hasWin, action: () => Apps.run("kill -9 " + win.lastIpcObject.pid) },
      sep(),
      { text: "Sleep", action: () => Apps.run("systemctl suspend") },
      { text: "Restart…", action: () => Shell.power("restart") },
      ...Shell.otherSystems.map(o => ({ text: "Restart into " + o.name + "…", action: () => Shell.power("restart:" + o.entry) })),
      { text: "Shut Down…", action: () => Shell.power("shutdown") },
      sep(),
      { text: "Lock Screen", keys: "Super L", action: () => Apps.run("memora-lock") },
      { text: "Log Out " + Quickshell.env("USER") + "…", action: () => Shell.power("logout") }
    ]
    case "app": return hasWin ? [
      { text: "About " + appName, action: () => Apps.run("memora-ai ask 'What is the app " + appName.replace(/'/g, "") + " on Memora and what can it do?'") },
      sep(),
      k("Settings…", "ctrl+comma"),
      sep(),
      { text: "Hide " + appName, action: () => Apps.windowsOf(cls).forEach(w => Apps.minimize(w.address)) },
      { text: "Hide Others", action: () => Apps.windows.filter(w => Apps.classOf(w) !== cls && !Apps.isMinimized(w)).forEach(w => Apps.minimize(w.address)) },
      { text: "Show All", enabled: Apps.windows.some(w => Apps.isMinimized(w)), action: () => Apps.windows.filter(w => Apps.isMinimized(w)).forEach(w => Apps.restore(w)) },
      sep(),
      { text: "Quit " + appName, keys: "Ctrl Q", action: () => Apps.quit(cls) }
    ] : [
      { text: "About Memora", action: () => Apps.run("memora-settings about") },
      sep(),
      { text: "Settings…", action: () => Apps.run("memora-settings") },
      sep(),
      { text: "Show All", enabled: Apps.windows.some(w => Apps.isMinimized(w)), action: () => Apps.windows.filter(w => Apps.isMinimized(w)).forEach(w => Apps.restore(w)) }
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
      { text: "New Terminal", keys: "Super Return", action: () => Apps.launch("com.mitchellh.ghostty") },
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
      { text: "Fill Screen Without Dock", keys: "Shift F11", enabled: hasWin, action: () => Apps.semiFullscreen() },
      { text: "Fill", keys: "Super Up", enabled: hasWin, action: () => Apps.run("memora-window fill") },
      { text: "Center", keys: "Super C", enabled: hasWin, action: () => Apps.run("memora-window center") },
      sep(),
      { text: "Move to Left Half", keys: "Super Left", enabled: hasWin, action: () => Apps.run("memora-window left") },
      { text: "Move to Right Half", keys: "Super Right", enabled: hasWin, action: () => Apps.run("memora-window right") },
      { text: "Tile Window", keys: "Super T", enabled: hasWin, action: () => Apps.dispatch('hl.dsp.window.float({ action = "toggle" })') },
      sep(),
      { text: "Show All Windows", enabled: Apps.windows.some(w => Apps.isMinimized(w)), action: () => Apps.windows.filter(w => Apps.isMinimized(w)).forEach(w => Apps.restore(w)) },
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
