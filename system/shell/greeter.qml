//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import qs.core
import qs.lock

// Login screen, run by greetd inside cage: pick a person, type the password,
// and the Memora session starts.
ShellRoot {
  id: g
  property var users: []
  property string user: ""
  property string fullName: user
  property string message: ""
  property string pending: ""
  // Quietly: uwsm reports every step on the console, which would flash on screen.
  readonly property var session: ["memora-session"]

  // People who can log in, and who logged in last.
  Process {
    running: true
    command: ["bash", "-c", "getent passwd | awk -F: '$3>=1000 && $3<60000 && $7 !~ /nologin|false/ {print $1\":\"$5}'; echo '--'; cat /var/lib/memora/last-user 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const [list, last] = text.split("--\n")
        g.users = list.split("\n").filter(l => l).map(l => { const [n, f] = l.split(":"); return { name: n, full: (f || n).split(",")[0] || n } })
        const pick = g.users.find(u => u.name === (last || "").trim()) || g.users[0]
        if (pick) g.choose(pick.name)
      }
    }
  }

  function choose(name) {
    user = name
    const u = users.find(x => x.name === name)
    fullName = u ? u.full : name
    message = ""
    if (Greetd.state !== GreetdState.Inactive) Greetd.cancelSession()
  }

  function login(pw) {
    pending = pw
    message = ""
    Greetd.createSession(user)
  }

  Connections {
    target: Greetd
    function onAuthMessage(msg, error, responseRequired, echoResponse) {
      if (responseRequired) Greetd.respond(g.pending)
      else if (error) g.message = msg
    }
    function onAuthFailure(msg) {
      g.message = "Incorrect password"
      g.pending = ""
      view.shake()
    }
    function onReadyToLaunch() {
      saveLast.command = ["bash", "-c", "printf %s \"$1\" > /var/lib/memora/last-user", "_", g.user]
      saveLast.running = true
      Greetd.launch(g.session)
    }
    function onError(err) { g.message = err }
  }
  Process { id: saveLast }

  FloatingWindow {
    color: "black"
    LockView {
      id: view
      anchors.fill: parent
      userName: g.user
      fullName: g.fullName
      users: g.users
      message: g.message
      busy: Greetd.state === GreetdState.Authenticating
      showPower: true
      onSubmit: pw => g.login(pw)
      onPickUser: name => { g.choose(name); view.focusField() }
      onPower: action => Quickshell.execDetached(["systemctl", action])
      Component.onCompleted: focusField()
    }
  }
}
