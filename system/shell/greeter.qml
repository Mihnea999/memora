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

  // The chosen person's own look: their desktop picture and light or dark, as
  // the desktop leaves them in /var/lib/memora/look/NAME (memora-theme login-sync).
  // Only from a folder that belongs to that person.
  readonly property string defaultMode: Quickshell.env("MEMORA_MODE") || "dark"
  property string wallpaper: ""
  Process {
    id: look
    property string who: ""
    command: ["bash", "-c", "d=/var/lib/memora/look/$1; u=$(id -u -- \"$1\" 2>/dev/null) || exit 0; " +
      "[[ -d $d && ! -L $d && $(stat -c %u -- \"$d\") == \"$u\" ]] || exit 0; " +
      "m=; [[ -f $d/theme && ! -L $d/theme ]] && m=$(head -c 8 \"$d/theme\"); echo \"${m%%[^a-z]*}\"; " +
      "f=$d/wallpaper; [[ -f $f && ! -L $f && $(stat -c %u -- \"$f\") == \"$u\" ]] && echo \"$f\"", "_", who]
    stdout: StdioCollector {
      onStreamFinished: {
        const [m, w] = text.split("\n")
        Theme.mode = m === "light" || m === "dark" ? m : g.defaultMode
        g.wallpaper = (w || "").trim()
        g.prepareFrame()
      }
    }
  }

  function prepareFrame() {
    const s = Quickshell.screens[0]
    const w = s ? s.width : 1920
    const h = s ? s.height : 1080
    const wall = g.wallpaper !== "" ? g.wallpaper : Theme.wallpaper
    frameProc.running = false
    frameProc.command = ["memora-login-frame", "save", g.user, wall, String(w), String(h)]
    frameProc.running = true
  }
  Process {
    id: frameProc
    onExited: if (view.leaving && !launchTimer.running) Greetd.launch(g.session)
  }

  Timer {
    id: launchTimer
    interval: 160
    repeat: false
    onTriggered: {
      if (!frameProc.running) Greetd.launch(g.session)
    }
  }

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
    look.running = false
    look.who = name
    look.running = true
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
      view.leaving = true
      saveLast.command = ["bash", "-c", "printf %s \"$1\" > /var/lib/memora/last-user; memora-login-frame touch", "_", g.user]
      saveLast.running = true
      launchTimer.restart()
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
      wallpaper: g.wallpaper !== "" ? g.wallpaper : Theme.wallpaper
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
