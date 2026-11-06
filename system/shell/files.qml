//@ pragma UseQApplication
//@ pragma AppId memora-files
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui
import qs.filesapp

// Files. One process, any number of windows: `memora-files [FOLDER]`.
ShellRoot {
  id: root
  readonly property string home: Quickshell.env("HOME")
  ListModel { id: windows }
  // Cut / copy between windows.
  property var clip: []
  property bool clipCut: false

  function openWindow(path) { windows.append({ start: path || home }) }
  Component.onCompleted: openWindow(Quickshell.env("MEMORA_FILES_PATH") || home)
  IpcHandler {
    target: "files"
    function open(path: string): void { root.openWindow(path) }
  }

  Instantiator {
    model: windows
    delegate: FilesWindow {
      required property string start
      required property int index
      app: root
      startPath: start
      onCloseMe: { windows.remove(index); if (windows.count === 0) Qt.quit() }
    }
  }
}
