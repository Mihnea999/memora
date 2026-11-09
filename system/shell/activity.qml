//@ pragma UseQApplication
//@ pragma AppId memora-activity
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.ui

// Activity Monitor: what is running, what it uses, and a way to stop it.
ShellRoot {
  id: app
  property string tab: "cpu"          // cpu | memory
  property string filter: ""
  property var procs: []
  property int selected: -1
  property var cpuHistory: []
  property real cpuUser: 0
  property real cpuSys: 0
  property real memUsed: 0
  property real memTotal: 1
  property real swapUsed: 0
  property real swapTotal: 0
  property int threads: 0
  property var prevCpu: null
  property string asking: ""
  readonly property var friendly: ({
    "chromium": "Browser", "nautilus": "Files", "ghostty": "Terminal",
    "gnome-text-editor": "Text Editor", "gnome-calculator": "Calculator", "loupe": "Photos", "papers": "Documents",
    "qs": "Memora", "quickshell": "Memora", "Hyprland": "Hyprland (window server)", "mpv": "Media Player"
  })          // "quit" | "force" while the confirmation shows

  readonly property var shown: {
    const f = filter.toLowerCase()
    const list = procs.filter(p => !f || p.name.toLowerCase().indexOf(f) >= 0 || String(p.pid) === f)
    list.sort((a, b) => tab === "cpu" ? b.cpu - a.cpu : b.mem - a.mem)
    return list.slice(0, 150)
  }
  readonly property var current: shown.find(p => p.pid === selected) || null

  function human(kb) {
    if (kb >= 1048576) return (kb / 1048576).toFixed(2) + " GB"
    if (kb >= 1024) return (kb / 1024).toFixed(1) + " MB"
    return kb + " KB"
  }

  Process {
    id: sample
    command: ["bash", "-c", "head -1 /proc/stat; echo '--'; grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo; echo '--'; ps -eo pid=,user=,pcpu=,rss=,nlwp=,comm=,args= --sort=-pcpu | head -400"]
    stdout: StdioCollector {
      onStreamFinished: {
        const [cpuLine, memLines, psLines] = text.split("--\n")
        const c = cpuLine.trim().split(/\s+/).slice(1).map(Number)
        if (app.prevCpu) {
          const d = c.map((v, i) => v - app.prevCpu[i])
          const total = d.reduce((a, b) => a + b, 0) || 1
          app.cpuUser = (d[0] + d[1]) / total
          app.cpuSys = (d[2] + d[5] + d[6]) / total
          app.cpuHistory = app.cpuHistory.concat([app.cpuUser + app.cpuSys]).slice(-60)
        }
        app.prevCpu = c
        const m = {}
        memLines.split("\n").forEach(l => { const p = l.split(/\s+/); if (p[0]) m[p[0].replace(":", "")] = parseInt(p[1]) })
        app.memTotal = m.MemTotal || 1
        app.memUsed = (m.MemTotal || 0) - (m.MemAvailable || 0)
        app.swapTotal = m.SwapTotal || 0
        app.swapUsed = (m.SwapTotal || 0) - (m.SwapFree || 0)
        let th = 0
        app.procs = psLines.split("\n").filter(l => l.trim()).map(l => {
          const f = l.trim().split(/\s+/)
          th += parseInt(f[4]) || 0
          // Full program name (comm is cut at 15 characters), and app names people know.
          const exe = (f[6] || f[5]).split("/").pop()
          const base = exe.length > f[5].length && exe.startsWith(f[5].slice(0, 12)) ? exe : f[5]
          let name = app.friendly[base] || base
          // Memora's own apps all run in Quickshell: name them by what they show.
          if (base === "qs" || base === "quickshell") {
            const target = f.slice(7).find(a => a.indexOf("/memora/shell") >= 0) || ""
            const file = target.endsWith(".qml") ? target.split("/").pop().replace(".qml", "") : "shell"
            name = ({ shell: "Memora desktop", settings: "System Settings", notes: "Notes", store: "App Store", activity: "Activity Monitor",
              ai: "Memora AI", files: "Files", welcome: "Welcome", greeter: "Login window", installer: "Installer" })[file] || "Memora"
          }
          return { pid: parseInt(f[0]), user: f[1], cpu: parseFloat(f[2]), mem: parseInt(f[3]), name: name }
        }).filter(p => p.name !== "ps" && p.name !== "head")
        app.threads = th
      }
    }
  }
  Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: sample.running = true }
  Process { id: killer }
  function stop(force) {
    if (!current) return
    killer.command = ["kill", force ? "-KILL" : "-TERM", String(current.pid)]
    killer.running = true
    asking = ""
    selected = -1
  }

  FloatingWindow {
    id: win
    // Closed by the compositor (Alt+F4, Quit, Super+Q): end the app too, so it
    // opens again next time instead of lingering without a window.
    onVisibleChanged: if (!visible) Qt.quit()
    title: "Activity Monitor"
    implicitWidth: 880
    implicitHeight: 620
    minimumSize: Qt.size(640, 420)
    color: "transparent"
    Rectangle { anchors.fill: parent; color: Theme.window }

    // ---- toolbar
    Item {
      id: bar
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: 54
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      WindowControls { x: 16; anchors.verticalCenter: parent.verticalCenter; window: win; onCloseRequested: Qt.quit() }
      Column {
        x: 90; anchors.verticalCenter: parent.verticalCenter
        Txt { text: "Activity Monitor"; font.weight: Font.Bold }
        Txt { text: app.procs.length + " processes"; color: Theme.textDim; font.pixelSize: Theme.small - 1 }
      }
      // Stop the selected process
      Rectangle {
        id: stopBtn
        anchors { right: tabs.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        width: 30; height: 28; radius: 8
        opacity: app.current ? 1 : 0.35
        color: sh.hovered && app.current ? Theme.pressed : Theme.hover
        Sym { anchors.centerIn: parent; name: "close"; width: 11; height: 11 }
        HoverHandler { id: sh }
        TapHandler { onTapped: if (app.current) app.asking = "quit" }
      }
      Rectangle {
        id: tabs
        anchors { right: search.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        width: tabRow.implicitWidth + 4; height: 28; radius: 8
        color: Theme.field; border.color: Theme.separator
        Row {
          id: tabRow
          anchors.centerIn: parent
          Repeater {
            model: [["cpu", "CPU"], ["memory", "Memory"]]
            delegate: Rectangle {
              required property var modelData
              width: tt.implicitWidth + 26; height: 24; radius: 6
              color: app.tab === modelData[0] ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.18) : "#ffffff") : "transparent"
              Txt { id: tt; anchors.centerIn: parent; text: modelData[1]; font.pixelSize: Theme.small + 0.5 }
              TapHandler { onTapped: app.tab = modelData[0] }
            }
          }
        }
      }
      Rectangle {
        id: search
        anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
        width: 190; height: 28; radius: 8
        color: Theme.field; border.color: sf.activeFocus ? Theme.accent : Theme.separator
        Sym { name: "search"; width: 12; height: 12; color: Theme.textDim; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
        TextInput {
          id: sf
          clip: true   // long text scrolls inside the field, never spills out
          anchors { left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 8; verticalCenter: parent.verticalCenter }
          color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
          onTextChanged: app.filter = text
          Txt { visible: !sf.text; text: "Search"; color: Theme.textFaint; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
        }
      }
      Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.separator }
    }

    // ---- table
    Item {
      id: head
      anchors { left: parent.left; right: parent.right; top: bar.bottom }
      height: 30
      Row {
        x: 20; anchors.verticalCenter: parent.verticalCenter
        Txt { width: head.width - 20 - 3 * 110 - 80; text: "Process Name"; color: Theme.textDim; font.pixelSize: Theme.small }
        Txt { width: 110; text: "% CPU"; horizontalAlignment: Text.AlignRight; color: app.tab === "cpu" ? Theme.text : Theme.textDim; font.weight: app.tab === "cpu" ? Font.Bold : Font.Normal; font.pixelSize: Theme.small }
        Txt { width: 110; text: "Memory"; horizontalAlignment: Text.AlignRight; color: app.tab === "memory" ? Theme.text : Theme.textDim; font.weight: app.tab === "memory" ? Font.Bold : Font.Normal; font.pixelSize: Theme.small }
        Txt { width: 110; text: "PID"; horizontalAlignment: Text.AlignRight; color: Theme.textDim; font.pixelSize: Theme.small }
      }
      Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.separator }
    }

    ListView {
      id: table
      anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: stats.top }
      clip: true
      model: app.shown
      boundsBehavior: Flickable.StopAtBounds
      delegate: Rectangle {
        required property var modelData
        required property int index
        width: table.width; height: 28
        color: app.selected === modelData.pid ? Theme.accent : (index % 2 ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.025) : Qt.rgba(0, 0, 0, 0.025)) : "transparent")
        readonly property color ink: app.selected === modelData.pid ? "#ffffff" : Theme.text
        Row {
          x: 20; anchors.verticalCenter: parent.verticalCenter
          Txt { width: table.width - 20 - 3 * 110 - 80; text: modelData.name; color: parent.parent.ink }
          Txt { width: 110; text: modelData.cpu.toFixed(1); horizontalAlignment: Text.AlignRight; color: parent.parent.ink }
          Txt { width: 110; text: app.human(modelData.mem); horizontalAlignment: Text.AlignRight; color: parent.parent.ink }
          Txt { width: 110; text: modelData.pid; horizontalAlignment: Text.AlignRight; color: app.selected === modelData.pid ? Qt.rgba(1, 1, 1, 0.8) : Theme.textDim }
        }
        TapHandler { onTapped: app.selected = modelData.pid }
        TapHandler { acceptedButtons: Qt.LeftButton; onDoubleTapped: { app.selected = modelData.pid; app.asking = "quit" } }
      }
    }

    // ---- totals
    Rectangle {
      id: stats
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: 150
      color: Theme.dark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(0, 0, 0, 0.025)
      Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.separator }

      RowLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 26

        // CPU: numbers and a graph of the last two minutes.
        ColumnLayout {
          visible: app.tab === "cpu"
          Layout.preferredWidth: 200
          spacing: 6
          Stat { label: "System"; value: Math.round(app.cpuSys * 100) + "%"; tone: Theme.red }
          Stat { label: "User"; value: Math.round(app.cpuUser * 100) + "%"; tone: Theme.accent }
          Stat { label: "Idle"; value: Math.round((1 - app.cpuSys - app.cpuUser) * 100) + "%"; tone: Theme.textDim }
          Stat { label: "Threads"; value: app.threads; tone: Theme.textDim }
        }
        Canvas {
          id: graph
          visible: app.tab === "cpu"
          Layout.fillWidth: true; Layout.fillHeight: true
          property var data: app.cpuHistory
          onDataChanged: requestPaint()
          onPaint: {
            const ctx = getContext("2d"); ctx.reset()
            const n = 60, w = width, h = height
            ctx.fillStyle = Theme.dark ? "rgba(255,255,255,0.05)" : "rgba(0,0,0,0.04)"
            ctx.fillRect(0, 0, w, h)
            if (data.length < 2) return
            ctx.beginPath(); ctx.moveTo(w - (data.length - 1) * w / (n - 1), h)
            data.forEach((v, i) => ctx.lineTo(w - (data.length - 1 - i) * w / (n - 1), h - v * h))
            ctx.lineTo(w, h); ctx.closePath()
            ctx.fillStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25); ctx.fill()
            ctx.beginPath()
            data.forEach((v, i) => { const x = w - (data.length - 1 - i) * w / (n - 1), y = h - v * h; i ? ctx.lineTo(x, y) : ctx.moveTo(x, y) })
            ctx.strokeStyle = Theme.accent; ctx.lineWidth = 1.6; ctx.stroke()
          }
        }

        // Memory: how full, in one bar, and the numbers.
        ColumnLayout {
          visible: app.tab === "memory"
          Layout.fillWidth: true
          spacing: 10
          Txt { text: "Memory used"; color: Theme.textDim; font.pixelSize: Theme.small }
          Rectangle {
            Layout.fillWidth: true; height: 14; radius: 7
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
            Rectangle {
              width: parent.width * Math.min(1, app.memUsed / app.memTotal); height: parent.height; radius: 7
              color: app.memUsed / app.memTotal > 0.85 ? Theme.red : (app.memUsed / app.memTotal > 0.65 ? Theme.yellow : Theme.green)
              Behavior on width { NumberAnimation { duration: Theme.slow } }
            }
          }
          RowLayout {
            spacing: 30
            Stat { label: "Used"; value: app.human(app.memUsed); tone: Theme.accent }
            Stat { label: "Total"; value: app.human(app.memTotal); tone: Theme.textDim }
            Stat { label: "Swap"; value: app.human(app.swapUsed) + " of " + app.human(app.swapTotal); tone: Theme.textDim }
          }
        }
      }
    }

    // ---- confirmation
    Rectangle {
      anchors.fill: parent
      visible: app.asking !== ""
      color: Qt.rgba(0, 0, 0, 0.25)
      TapHandler { onTapped: app.asking = "" }
      Glass {
        anchors.centerIn: parent
        width: 360; height: cq.implicitHeight + 40
        radius: 18
        fill: Theme.glassStrong
        TapHandler {}
        ColumnLayout {
          id: cq
          x: 20; y: 20; width: parent.width - 40
          spacing: 10
          Txt { text: "Quit “" + (app.current ? app.current.name : "") + "”?"; font.weight: Font.Bold; Layout.fillWidth: true }
          Txt { text: "Unsaved work in it may be lost. Force Quit stops it at once, even if it is not responding."; wrapMode: Text.Wrap; color: Theme.textDim; Layout.fillWidth: true; font.pixelSize: Theme.small + 0.5 }
          RowLayout {
            Layout.topMargin: 6
            spacing: 8
            Item { Layout.fillWidth: true }
            Btn { text: "Cancel"; onClicked: app.asking = "" }
            Btn { text: "Force Quit"; onClicked: app.stop(true) }
            Btn { text: "Quit"; primary: true; onClicked: app.stop(false) }
          }
        }
      }
    }
  }

  component Stat: Row {
    property string label
    property var value
    property color tone
    spacing: 8
    Rectangle { width: 8; height: 8; radius: 4; color: parent.tone; anchors.verticalCenter: parent.verticalCenter }
    Txt { width: 64; text: parent.label; color: Theme.textDim; font.pixelSize: Theme.small }
    Txt { text: String(parent.value); font.weight: Font.Medium; font.pixelSize: Theme.small + 0.5 }
  }
  component Btn: Rectangle {
    id: b
    property string text
    property bool primary: false
    signal clicked()
    width: bt.implicitWidth + 24; height: 28; radius: 8
    color: primary ? Theme.accent : (bh.hovered ? Theme.pressed : Theme.hover)
    Txt { id: bt; anchors.centerIn: parent; text: b.text; color: b.primary ? "#ffffff" : Theme.text; font.weight: b.primary ? Font.Bold : Font.Normal }
    HoverHandler { id: bh }
    TapHandler { onTapped: b.clicked() }
  }
}
