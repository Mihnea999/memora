import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Software Update"
  // idle | checking | ready | updating | done | failed
  property string phase: "checking"
  property var items: []             // [{ source, name, old, new }]
  property string checked: ""
  property string step: ""
  property real progress: 0
  property string log: ""
  property string error: ""
  property bool needRestart: false
  property bool showLog: false

  readonly property int systemCount: items.filter(i => i.source === "system").length
  readonly property int appCount: items.filter(i => i.source === "app").length
  readonly property bool memoraNew: items.some(i => i.source === "memora")

  function check() {
    p.phase = "checking"
    checker.exec(["memora-update", "check"])
  }
  Kit.Cmd {
    id: checker
    onDone: out => {
      const lines = out.split("\n").filter(l => l.trim())
      const err = lines.find(l => l.startsWith("@error "))
      p.items = lines.filter(l => !l.startsWith("@")).map(l => { const f = l.split("\t"); return { source: f[0], name: f[1], old: f[2] || "", "new": f[3] || "" } })
      p.checked = Qt.formatTime(new Date(), Prefs.clock24 ? "HH:mm" : "h:mm AP")
      p.phase = p.items.length ? "ready" : (err ? "failed" : "idle")
      p.error = err ? err.slice(7) : ""
    }
  }
  Component.onCompleted: check()

  Process {
    id: updater
    command: ["memora-update", "apply"]
    stdout: SplitParser {
      onRead: line => {
        if (line.startsWith("@step ")) {
          const f = line.split(" ")
          p.progress = Number(f[1]) / Number(f[2]); p.step = f.slice(3).join(" ")
        } else if (line.startsWith("@error ")) { p.error = line.slice(7) }
        else if (line.startsWith("@warn ")) { p.log += line.slice(6) + "\n" }
        else if (line === "@restart") p.needRestart = true
        else if (line === "@done") p.progress = 1
        else p.log = (p.log + line + "\n").slice(-20000)
      }
    }
    stderr: SplitParser { onRead: line => p.log = (p.log + line + "\n").slice(-20000) }
    onExited: code => {
      if (code === 0 && !p.error) { p.phase = "done"; p.items = []; Host.refresh() }
      else { p.phase = "failed"; if (!p.error) p.error = "The update did not finish." }
    }
  }
  function update() {
    p.log = ""; p.error = ""; p.progress = 0; p.step = "Preparing"; p.needRestart = false
    p.phase = "updating"
    updater.running = true
  }

  // ---- status ---------------------------------------------------------------
  Kit.Group {
    Item {
      Layout.fillWidth: true
      implicitHeight: 92
      Rectangle {
        id: badge
        x: 16; anchors.verticalCenter: parent.verticalCenter
        width: 56; height: 56; radius: 14
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.25) }
          GradientStop { position: 1; color: Theme.accent }
        }
        Sym { anchors.centerIn: parent; width: 28; height: 28; color: "#ffffff"
          name: p.phase === "idle" || p.phase === "done" ? "check" : "download" }
      }
      ColumnLayout {
        anchors { left: badge.right; leftMargin: 14; right: actions.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 3
        Txt {
          Layout.fillWidth: true; elide: Text.ElideRight
          font.pixelSize: Theme.large; font.weight: Font.Bold
          text: ({
            checking: "Checking for updates…",
            idle: "Memora is up to date",
            ready: p.items.length + (p.items.length === 1 ? " update available" : " updates available"),
            updating: p.step + "…",
            done: p.needRestart ? "Restart to finish updating" : "Everything is up to date",
            failed: p.items.length || p.log ? "Update didn't finish" : "Couldn't check for updates"
          })[p.phase]
        }
        Txt {
          Layout.fillWidth: true; wrapMode: Text.Wrap
          color: p.phase === "failed" ? Theme.red : Theme.textDim; font.pixelSize: Theme.small
          text: p.phase === "failed" ? p.error
            : p.phase === "ready" ? [p.memoraNew ? "Memora" : "", p.systemCount ? p.systemCount + " system" : "", p.appCount ? p.appCount + (p.appCount === 1 ? " app" : " apps") : ""].filter(x => x).join(" · ")
            : p.phase === "updating" ? "You can keep working. Don't turn the computer off."
            : p.phase === "done" && p.needRestart ? "A new system core was installed."
            : "Memora " + Host.version + (p.checked ? " · checked at " + p.checked : "")
        }
        // Progress
        Rectangle {
          visible: p.phase === "updating"
          Layout.fillWidth: true; Layout.topMargin: 6
          height: 6; radius: 3
          color: Theme.field
          Rectangle {
            height: parent.height; radius: 3; color: Theme.accent
            width: Math.max(parent.height, parent.width * Math.max(0.04, p.progress))
            Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Theme.easing } }
          }
        }
      }
      RowLayout {
        id: actions
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        spacing: 8
        Kit.Button { visible: p.phase === "idle" || p.phase === "ready" || p.phase === "failed"; text: "Check Now"; onClicked: p.check() }
        Kit.Button { visible: p.phase === "ready" || (p.phase === "failed" && p.log !== ""); text: p.phase === "failed" ? "Try Again" : "Update Now"; primary: true; onClicked: p.update() }
        Kit.Button { visible: p.phase === "done" && p.needRestart; text: "Restart"; primary: true; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
      }
    }
  }

  // ---- what will change -----------------------------------------------------
  Kit.Group {
    visible: p.phase === "ready" && p.items.length > 0
    header: "What's new"
    Repeater {
      model: p.items.slice(0, 40)
      delegate: Kit.Row {
        required property var modelData
        required property int index
        label: modelData.name
        detail: modelData.old ? modelData.old + "  →  " + modelData["new"] : (modelData["new"] ? "Version " + modelData["new"] : "")
        badge: modelData.source === "app" ? "dock" : (modelData.source === "memora" ? "sparkle" : "gear")
        badgeColor: modelData.source === "app" ? "#2fb6d9" : (modelData.source === "memora" ? Theme.accent : "#8a8d96")
        last: index === Math.min(p.items.length, 40) - 1
        Kit.Value { text: modelData.source === "app" ? "App" : (modelData.source === "memora" ? "Memora" : "System") }
      }
    }
  }
  Txt {
    visible: p.phase === "ready" && p.items.length > 40
    text: "and " + (p.items.length - 40) + " more"; color: Theme.textDim; font.pixelSize: Theme.small
    Layout.leftMargin: 4
  }

  // ---- details while/after updating -----------------------------------------
  Kit.Group {
    visible: p.phase === "updating" || p.phase === "done" || p.phase === "failed"
    Kit.Row {
      label: "Details"; clickable: true; last: !p.showLog
      onClicked: p.showLog = !p.showLog
      Sym { name: "chevron"; width: 12; height: 12; color: Theme.textDim; rotation: p.showLog ? 90 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.fast } } }
    }
    Item {
      visible: p.showLog
      Layout.fillWidth: true
      implicitHeight: 200
      Flickable {
        id: lf
        anchors { fill: parent; margins: 12 }
        clip: true
        contentHeight: logText.implicitHeight
        onContentHeightChanged: if (p.phase === "updating") contentY = Math.max(0, contentHeight - height)
        Txt { id: logText; width: lf.width; text: p.log || "…"; wrapMode: Text.WrapAnywhere; font.pixelSize: Theme.small - 0.5; color: Theme.textDim }
      }
    }
  }

  // ---- settings -------------------------------------------------------------
  Kit.Group {
    footer: "A snapshot is taken before each update; pick it in the boot menu to go back."
    Kit.Row {
      label: "Check for updates automatically"
      Kit.Switch { checked: Prefs.updateCheck; onToggled: on => Prefs.set("updateCheck", on) }
    }
    Kit.Row {
      label: "Firmware"; last: true
      Kit.Button { text: "Check…"; onClicked: Quickshell.execDetached(["ghostty", "-e", "bash", "-c", "fwupdmgr refresh >/dev/null 2>&1; fwupdmgr get-updates && fwupdmgr update; read -rsn1 -p 'Press a key to close'"]) }
    }
  }
}
