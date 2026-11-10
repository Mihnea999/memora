pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tells the compositor where the shell's glass is (system/plugin/glass.cpp),
// so it can draw what is behind it bent like a lens. Without the plugin the
// socket isn't there and nothing is sent: Hyprland's blur stays the frost.
Singleton {
  id: s
  property int next: 0
  property var lines: ({})   // id -> last line sent

  function newId() { return ++next }
  function put(id, line) {
    if (lines[id] === line) return
    lines[id] = line
    send("R " + id + " " + line)
  }
  function drop(id) {
    if (lines[id] === undefined) return
    delete lines[id]
    send("D " + id)
  }
  function send(text) {
    if (!sock.connected) return
    sock.write(text + "\n")
    sock.flush()
  }

  Socket {
    id: sock
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/memora-glass.sock"
    connected: true
    onConnectedChanged: {
      if (!connected) { retry.start(); return }
      // (Re)connected: the compositor knows nothing yet.
      for (const id in s.lines) sock.write("R " + id + " " + s.lines[id] + "\n")
      sock.flush()
    }
    onError: retry.start()
  }
  // Hyprland may start the plugin after the shell, or reload it.
  Timer { id: retry; interval: 3000; onTriggered: { sock.connected = false; sock.connected = true } }
}
