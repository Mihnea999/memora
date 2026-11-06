import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.core

// Locks the session. The password is checked with PAM (/etc/pam.d/login).
Scope {
  id: lk
  property bool locked: false
  property string message: ""
  property string pending: ""
  property var views: []

  IpcHandler {
    target: "lock"
    function lock(): void { lk.message = ""; lk.locked = true; Shell.close() }
  }

  WlSessionLock {
    id: session
    locked: lk.locked
    WlSessionLockSurface {
      color: "black"
      LockView {
        id: view
        anchors.fill: parent
        fullName: lk.fullName
        message: lk.message
        busy: pam.active
        onSubmit: pw => { lk.pending = pw; lk.message = ""; pam.start() }
        Component.onCompleted: { lk.views = lk.views.concat([view]); focusField() }
        Component.onDestruction: lk.views = lk.views.filter(x => x !== view)
      }
    }
  }

  PamContext {
    id: pam
    config: "login"
    onResponseRequiredChanged: if (responseRequired) respond(lk.pending)
    onCompleted: result => {
      if (result === PamResult.Success) { lk.locked = false; lk.pending = "" }
      else { lk.message = "Incorrect password"; lk.views.forEach(v => v.shake()) }
    }
  }

  // Display name from the user database.
  property string fullName: Quickshell.env("USER")
  Process {
    running: true
    command: ["bash", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
    stdout: StdioCollector { onStreamFinished: if (text.trim()) lk.fullName = text.trim() }
  }
}
