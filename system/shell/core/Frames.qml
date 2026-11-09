pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

// What windows remember, kept by the desktop shell (Shell.main):
//  - each app's own frame (place and size) when its last window closes, so it
//    opens there next time (default/hypr/rules.lua reads frames.lua);
//  - the open windows by app, so a second window cascades and a dialog opens
//    over its window (open.lua, read by rules.lua as well);
//  - each window's home screen, so it goes back there when that screen is
//    plugged in again;
//  - the apps open when shutting down, to reopen them after logging in.
Singleton {
  id: f
  readonly property bool on: Shell.main
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/memora"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/memora"

  // address -> { cls, at, size, mon, desc, ws, floating, fullscreen, pinned, title }
  property var known: ({})
  // address -> { desc, rel: [x, y], size } for windows whose screen went away
  property var homes: ({})
  property var frames: ({})

  // Windows that never get a frame of their own: the shell's helpers, PiP.
  function skip(o) {
    const c = o ? (o.cls || o.class) : ""
    return !o || !c || Apps.helperClasses.indexOf(c) >= 0 || o.pinned || (o.title || "").match(/^Picture[ -]in[ -]picture/i)
  }
  function monOf(o) { return Hyprland.monitors.values.find(m => m.id === o.monitor) || null }
  function descOf(m) { const o = m && m.lastIpcObject; return o ? (o.description || m.name) : (m ? m.name : "") }

  // Windows move and resize without events: look every second, and soon after
  // anything happens to a window.
  Timer { interval: 1000; repeat: true; running: f.on; onTriggered: f.remember() }
  Timer { id: track; interval: 250; onTriggered: f.remember() }
  function remember() {
    const k = Object.assign({}, known)
    const present = Hyprland.monitors.values.map(m => descOf(m))
    Apps.windows.forEach(w => {
      const o = w.lastIpcObject
      if (!o || !o.at) return
      const a = "0x" + Apps.addrKey(w.address), m = monOf(o)
      k[a] = { cls: o.class, at: o.at, size: o.size, mon: m ? m.name : "", desc: descOf(m), ws: o.workspace ? o.workspace.id : 0,
               floating: o.floating, fullscreen: o.fullscreen, pinned: o.pinned, title: o.title, focus: o.focusHistoryID ?? 99,
               mx: m ? m.x : 0, my: m ? m.y : 0, minimized: Apps.isMinimized(w) }
      // A home screen: where it lives, unless it was only pushed here because
      // its own screen went away.
      const h = homes[a]
      if (h && present.indexOf(h.desc) < 0 && h.desc !== k[a].desc) return
      if (h && h.desc !== k[a].desc) { const hs = Object.assign({}, homes); delete hs[a]; homes = hs }
    })
    known = k
    writeOpen()
  }

  // ---- open.lua: windows open now, by app (for cascading and dialogs) ----------
  FileView { id: openFile; path: f.cacheDir + "/open.lua"; printErrors: false }
  function lua(v) {
    if (typeof v === "string") return '"' + v.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, " ") + '"'
    if (typeof v === "boolean") return v ? "true" : "false"
    if (typeof v === "number") return isFinite(v) ? String(Math.round(v)) : "0"
    if (Array.isArray(v)) return "{ " + v.map(lua).join(", ") + " }"
    if (v && typeof v === "object") return "{ " + Object.keys(v).map(x => "[" + lua(x) + "] = " + lua(v[x])).join(", ") + " }"
    return "nil"
  }
  function writeOpen() {
    const by = {}
    Object.keys(known).forEach(a => {
      const o = known[a]
      if (skip(o) || o.minimized || !o.floating || o.fullscreen) return
      ;(by[o.cls] = by[o.cls] || []).push({ x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1], focus: o.focus })
    })
    openFile.setText("-- Written by the Memora shell: open windows by app.\nreturn " + lua(by) + "\n")
  }

  // ---- frames.lua: the last frame of each app ------------------------------
  FileView {
    id: framesFile
    path: f.stateDir + "/frames.json"
    printErrors: false
    onLoaded: { try { f.frames = JSON.parse(text()) } catch (e) { f.frames = {} } }
  }
  FileView { id: framesLua; path: f.stateDir + "/frames.lua"; printErrors: false }
  function saveFrame(o, a) {
    if (skip(o) || o.fullscreen || !o.floating || o.size[0] < 260 || o.size[1] < 160) return
    // Docked or filled: its own size from before (memora-window's "orig").
    const d = Apps.docked[a]
    const r = d && d.zone && d.orig ? d.orig : [o.at[0], o.at[1], o.size[0], o.size[1]]
    const fr = Object.assign({}, frames)
    fr[o.cls] = { x: r[0], y: r[1], w: r[2], h: r[3], mon: o.mon }
    frames = fr
    framesFile.setText(JSON.stringify(fr) + "\n")
    framesLua.setText("-- Written by the Memora shell: where each app's window was last.\nreturn " + lua(fr) + "\n")
  }

  Connections {
    target: Hyprland
    enabled: f.on
    function onRawEvent(ev) {
      if (ev.name === "closewindow") {
        const a = "0x" + ev.data.replace(/^0x/, "")
        const o = f.known[a]
        if (!o) return
        // The app's last window: remember where it was.
        const others = Object.keys(f.known).filter(x => x !== a && f.known[x].cls === o.cls)
        if (!others.length) f.saveFrame(o, a)
        const k = Object.assign({}, f.known); delete k[a]; f.known = k
        const hs = Object.assign({}, f.homes); delete hs[a]; f.homes = hs
      } else if (ev.name === "monitorremovedv2" || ev.name === "monitorremoved") {
        // Remember where each window of that screen was, before it moves over.
        const name = ev.name === "monitorremovedv2" ? ev.data.split(",")[1] : ev.data
        const hs = Object.assign({}, f.homes)
        Object.keys(f.known).forEach(a => {
          const o = f.known[a]
          if (o.mon === name) hs[a] = { desc: o.desc, rel: [o.at[0] - o.mx, o.at[1] - o.my], size: o.size }
        })
        f.homes = hs
      } else if (ev.name === "monitoraddedv2") {
        backHome.desc = ev.data.split(",").slice(2).join(",")
        backHome.restart()
      } else if (ev.name === "openwindow") {
        f.placeReopened(ev.data.split(",")[0], ev.data.split(",")[2])
      }
      if (["openwindow", "closewindow", "movewindowv2", "activewindowv2"].indexOf(ev.name) >= 0) track.restart()
    }
  }
  // A screen came back: its windows go home, where they were on it.
  Timer {
    id: backHome
    property string desc: ""
    interval: 1600
    onTriggered: {
      const m = Hyprland.monitors.values.find(x => f.descOf(x) === desc || x.name === desc)
      if (!m) return
      Object.keys(f.homes).forEach(a => {
        const h = f.homes[a]
        if (h.desc !== desc && h.desc !== m.name) return
        Hyprland.dispatch('hl.dsp.window.move({ x = ' + Math.round(m.x + h.rel[0]) + ', y = ' + Math.round(m.y + h.rel[1]) + ', window = "address:' + a + '" })')
        Hyprland.dispatch('hl.dsp.window.resize({ x = ' + h.size[0] + ', y = ' + h.size[1] + ', window = "address:' + a + '" })')
        Hyprland.dispatch('hl.dsp.window.move({ x = ' + Math.round(m.x + h.rel[0]) + ', y = ' + Math.round(m.y + h.rel[1]) + ', window = "address:' + a + '" })')
      })
      f.homes = ({})
      Quickshell.execDetached(["bash", "-c", "sleep 0.5; memora-window refit"])
    }
  }

  // ---- reopening windows after logging in -------------------------------------
  FileView { id: sessionFile; path: f.stateDir + "/session.json"; printErrors: false }
  // The apps open now (one entry per app, with the desktop of its front window).
  function saveSession() {
    const seen = {}, out = []
    Apps.windows.slice().sort((a, b) => (a.lastIpcObject.focusHistoryID ?? 99) - (b.lastIpcObject.focusHistoryID ?? 99)).forEach(w => {
      const o = w.lastIpcObject, c = Apps.classOf(w)
      if (!c || seen[c] || skip(o) || c === "memora-float" || c.startsWith("xdg-desktop-portal")) return
      const e = Apps.entry(c)
      if (!e) return
      seen[c] = true
      out.push({ app: e.id, cls: c, ws: o.workspace && o.workspace.id > 0 ? o.workspace.id : 1 })
    })
    sessionFile.setText(JSON.stringify({ at: Date.now(), apps: out }) + "\n")
  }
  property var pendingDesk: ({})      // class -> desktop, for windows being reopened
  function reopen() {
    let s
    try { s = JSON.parse(sessionFile.text()) } catch (e) { return }
    sessionFile.setText("")
    if (!s || !s.apps || Date.now() - s.at > 3 * 24 * 3600 * 1000) return
    const pd = {}
    s.apps.forEach((x, i) => { pd[x.cls] = x.ws; Qt.callLater(() => later.createObject(f, { app: x.app, wait: 400 + i * 350 })) })
    pendingDesk = pd
  }
  property Component later: Component {
    Timer {
      property string app
      property int wait
      interval: wait; running: true
      onTriggered: { Apps.launch(app); destroy() }
    }
  }
  function placeReopened(addr, cls) {
    const ws = pendingDesk[cls]
    if (!ws) return
    const pd = Object.assign({}, pendingDesk); delete pd[cls]; pendingDesk = pd
    const cur = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    if (ws !== cur) Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = "address:0x' + addr.replace(/^0x/, "") + '" })')
  }
  Timer {
    // After the desktop has started (and only in the desktop shell).
    interval: 2500; running: f.on; onTriggered: if (Prefs.reopenWindows) f.reopen()
  }
}
