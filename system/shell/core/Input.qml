pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// How the computer is being used right now: by touch (a finger was on the
// screen last) or with a pointer. The Memora plugin writes it on each change
// ($XDG_RUNTIME_DIR/memora-input), so every Memora window can read it: in touch
// mode buttons and menu rows get bigger and the on-screen keyboard may show.
Singleton {
  id: inp
  property bool touch: false
  property FileView file: FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/memora-input"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: inp.touch = text().trim() === "touch"
    onLoadFailed: inp.touch = false
  }
}
