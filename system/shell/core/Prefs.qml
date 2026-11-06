pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shell preferences, shared by the shell and System Settings through
// ~/.config/memora/shell.json (both watch the file).
Singleton {
  id: p
  property int dockSize: 52
  property bool magnify: true
  property int magnifySize: 80
  property bool clock24: true
  property bool showDate: true
  property string wallpaper: ""        // empty: the theme's own picture

  readonly property var keys: ["dockSize", "magnify", "magnifySize", "clock24", "showDate", "wallpaper"]

  property FileView file: FileView {
    path: Quickshell.env("HOME") + "/.config/memora/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const j = JSON.parse(text())
        p.keys.forEach(k => { if (j[k] !== undefined) p[k] = j[k] })
      } catch (e) {}
    }
  }

  function set(key, value) {
    p[key] = value
    const j = {}
    keys.forEach(k => j[k] = p[k])
    file.setText(JSON.stringify(j, null, 2) + "\n")
  }
}
