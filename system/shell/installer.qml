//@ pragma UseQApplication
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui
import qs.settings

// The Memora installer, shown full screen from the live USB (cage). It asks a
// few questions, then runs memora-install with the answers and shows progress.
ShellRoot {
  id: app
  // Pages: 0 hello, 1 network, 2 disk, 3 you, 4 region, 5 look, 6 review, 7 installing, 8 done
  property int page: 0
  property bool online: false
  property var disks: []
  property string disk: ""
  property bool probing: true
  // "alongside" keeps what's on the disk and makes room; "erase" takes it all.
  property string mode: "erase"
  property real size: 0                 // bytes for Memora when alongside
  readonly property real minSize: 30 * 1073741824
  property bool encrypt: true
  property string fullName: ""
  property string userName: ""
  property bool userEdited: false
  property string password: ""
  property string password2: ""
  property string hostName: "memora"
  property string timezone: "UTC"
  property string locale: "en_US.UTF-8"
  property var keyboard: ({ name: "English (US)", keymap: "us", xkb: "us" })
  property string look: "dark"
  property var toolkits: ["gaming", "node", "claude"]
  // installing
  property string step: ""
  property real progress: 0
  property string pkg: ""
  property string error: ""
  property string log: ""

  readonly property var keyboards: [
    { name: "English (US)", keymap: "us", xkb: "us" }, { name: "Romanian", keymap: "ro_std", xkb: "ro" },
    { name: "English (UK)", keymap: "uk", xkb: "gb" }, { name: "German", keymap: "de-latin1", xkb: "de" },
    { name: "French", keymap: "fr", xkb: "fr" }, { name: "Spanish", keymap: "es", xkb: "es" },
    { name: "Italian", keymap: "it", xkb: "it" }, { name: "Polish", keymap: "pl", xkb: "pl" },
    { name: "Hungarian", keymap: "hu", xkb: "hu" }]
  readonly property var locales: [["en_US.UTF-8", "English (US)"], ["en_GB.UTF-8", "English (UK)"], ["ro_RO.UTF-8", "Română"],
    ["de_DE.UTF-8", "Deutsch"], ["fr_FR.UTF-8", "Français"], ["es_ES.UTF-8", "Español"], ["it_IT.UTF-8", "Italiano"]]
  readonly property var kits: [["gaming", "Gaming (Steam, Proton)"], ["node", "Node.js"], ["python", "Python"], ["claude", "Claude Code"], ["docker", "Docker"],
    ["rust", "Rust"], ["go", "Go"], ["flutter", "Flutter"], ["android", "Android tools"], ["ollama", "Local AI (Ollama)"]]

  readonly property string userError: userName && !/^[a-z_][a-z0-9_-]{0,31}$/.test(userName) ? "Lowercase letters, digits, - and _" : ""
  readonly property string passError: password && password.length < 4 ? "At least 4 characters" : (password2 && password !== password2 ? "The passwords don't match" : "")
  readonly property bool youOk: fullName.trim() !== "" && userName !== "" && !userError && password.length >= 4 && password === password2 && /^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$/.test(hostName)
  readonly property var chosenDisk: disks.find(d => d.path === disk) || null
  // What else lives on a disk, in words ("Windows", "Windows and Ubuntu").
  function others(d) { return d && d.systems.length ? d.systems.join(" and ") : "" }
  // How much Memora may take next to what's there.
  function room(d) { return d ? Math.max(d.free, d.shrink && d.shrink.state === "ok" ? d.shrink.room : 0) : 0 }
  function canAlongside(d) { return d && d.pttype === "gpt" && d.parts.length > 0 && room(d) >= minSize }
  // Why it can't, in plain words (empty when it can, or when there's nothing to keep).
  function alongsideProblem(d) {
    if (!d || d.parts.length === 0 || canAlongside(d)) return ""
    const what = others(d) || "what's on it"
    if (d.pttype !== "gpt") return "This disk uses the older MBR layout, so Memora can't go next to " + what + "."
    const st = d.shrink ? d.shrink.state : ""
    if (st === "hibernated") return "Windows is still asleep (Fast Startup). Start Windows, hold Shift while you click Shut Down, then start the installer again."
    if (st === "dirty") return "Windows needs to check its disk. Start Windows, restart it once, shut it down, then start the installer again."
    if (st === "locked") return "Windows is encrypted with BitLocker, so it can't be resized from here. In Windows, open Disk Management, right-click C: and choose Shrink Volume (30 GB or more), then start the installer again."
    return "There isn't enough room next to " + what + ". Memora needs 30 GB."
  }
  // A sensible split: all the free space, or half of what the other system can give.
  function defaultSize(d) {
    if (!canAlongside(d)) return 0
    if (d.free >= minSize) return d.free
    const sh = d.shrink
    return Math.max(minSize, Math.min(room(d), Math.round((sh.size - sh.min) / 2)))
  }
  function pickDisk(path) {
    disk = path
    const d = chosenDisk
    mode = canAlongside(d) ? "alongside" : "erase"
    size = defaultSize(d)
  }
  // The partition that shrinks, and to what size (alongside, without enough free space).
  readonly property real otherAfter: chosenDisk && mode === "alongside" && chosenDisk.free < size && chosenDisk.shrink ? chosenDisk.shrink.size - size : 0
  readonly property var summary: [
    ["Disk", chosenDisk ? (mode === "alongside" ? gb(size) + " on " : "All of ") + chosenDisk.model + " (" + gb(chosenDisk.size) + ")" : ""],
    ["Next to", mode === "alongside" ? (others(chosenDisk) || "your files") + (otherAfter > 0 ? " (resized to " + gb(otherAfter) + ")" : "") : "Nothing (the disk is erased)"],
    ["Encryption", encrypt ? "On" : "Off"],
    ["Account", fullName.trim() + " (" + userName + ")"],
    ["Computer", hostName],
    ["Time zone", timezone.replace(/_/g, " ")],
    ["Keyboard", keyboard.name],
    ["Look", look === "dark" ? "Dark" : "Light"],
    ["Extras", toolkits.length ? toolkits.map(k => (kits.find(x => x[0] === k) || [k, k])[1]).join(", ") : "None"]]

  function canGo(p) {
    if (p === 1) return online
    if (p === 2) return !probing && disk !== "" && (mode === "erase" || size >= minSize)
    if (p === 3) return youOk
    return true
  }
  function next() {
    let n = page + 1
    if (n === 1 && online) n = 2
    page = n
  }
  function back() {
    let n = page - 1
    if (n === 1 && online) n = 0
    page = Math.max(0, n)
  }
  function slug(s) { return s.toLowerCase().split(" ")[0].normalize("NFD").replace(/[^a-z0-9_-]/g, "") }
  onFullNameChanged: if (!userEdited) userName = slug(fullName)

  // ---- facts about this computer ------------------------------------------
  Process {
    id: netCheck
    running: true
    command: ["bash", "-c", "curl -sfI --max-time 5 https://geo.mirror.pkgbuild.com >/dev/null && echo yes"]
    stdout: StdioCollector { onStreamFinished: app.online = text.trim() === "yes" }
  }
  Timer { interval: 4000; repeat: true; running: !app.online && app.page <= 1; onTriggered: netCheck.running = true }

  Process {
    id: diskList
    running: true
    // Every disk except the USB stick, with what's on it (memora-disks).
    command: ["memora-disks"]
    onRunningChanged: if (running) app.probing = true
    stdout: StdioCollector {
      onStreamFinished: {
        let list = []
        try { list = JSON.parse(text) } catch (e) {}
        app.disks = list
        app.probing = false
        // Keep the choice when looking again; otherwise suggest the disk that
        // already has a system (to go next to it), or the only one.
        const keep = list.find(d => d.path === app.disk)
        const pick = keep || (list.length === 1 ? list[0] : list.find(d => app.canAlongside(d)))
        if (pick) app.pickDisk(pick.path)
      }
    }
  }
  function gb(b) { return b >= 1e12 ? (b / 1e12).toFixed(1) + " TB" : Math.round(b / 1e9) + " GB" }

  // On battery? Installing takes a while.
  property bool onBattery: false
  Process {
    running: true
    command: ["bash", "-c", "cat /sys/class/power_supply/BAT*/status 2>/dev/null | grep -qx Discharging && echo yes"]
    stdout: StdioCollector { onStreamFinished: app.onBattery = text.trim() === "yes" }
  }

  property var zones: []
  Process {
    running: true
    command: ["bash", "-c", "timedatectl list-timezones; echo '--'; curl -sf --max-time 4 https://ipapi.co/timezone 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const [list, guess] = text.split("--\n")
        app.zones = list.split("\n").filter(l => l)
        const g = (guess || "").trim()
        if (g && app.zones.indexOf(g) >= 0) app.timezone = g
      }
    }
  }

  // Wi-Fi through iwd.
  property var networks: []
  property string wifiDev: ""
  property string joining: ""
  property string wifiMsg: ""
  Process {
    id: scan
    command: ["bash", "-c", "d=$(iwctl device list 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g' | awk '/station/ {print $1; exit}'); [ -n \"$d\" ] || exit 0; echo \"$d\"; iwctl station \"$d\" scan; sleep 2.5; iwctl station \"$d\" get-networks | sed 's/\\x1b\\[[0-9;]*m//g' | awk 'NR>4 && NF' | sed -E 's/^ *>? *//; s/ {2,}/\\t/g'"]
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.split("\n").filter(l => l.trim())
        app.wifiDev = lines.length ? lines[0].trim() : ""
        app.networks = lines.slice(1).map(l => { const f = l.split("\t"); return { ssid: f[0], open: (f[1] || "") === "open", signal: (f[2] || "").length } }).filter(n => n.ssid)
      }
    }
  }
  Timer { interval: 8000; repeat: true; triggeredOnStart: true; running: app.page === 1 && !app.online && !scan.running && app.joining === ""; onTriggered: scan.running = true }
  Process {
    id: join
    stdout: StdioCollector { onStreamFinished: { app.joining = ""; netCheck.running = true; app.wifiMsg = text.indexOf("fail") >= 0 ? "Couldn't connect. Check the password." : "" } }
  }
  function connect(ssid, pass) {
    joining = ssid; wifiMsg = ""
    join.command = ["bash", "-c", "if [ -n \"$3\" ]; then iwctl --passphrase \"$3\" station \"$1\" connect \"$2\"; else iwctl station \"$1\" connect \"$2\"; fi && sleep 4 || echo fail", "_", wifiDev, ssid, pass]
    join.running = true
  }

  // ---- install --------------------------------------------------------------
  Process {
    id: writeAnswers
    onExited: code => { if (code === 0) installer.running = true; else app.error = "Couldn't start the installation." }
  }
  Process {
    id: installer
    command: ["memora-install", "--answers", "/tmp/memora-answers"]
    stdout: SplitParser {
      onRead: line => {
        if (line.startsWith("@step ")) {
          const f = line.split(" "); const n = Number(f[1])
          app.step = f.slice(3).join(" ")
          app.progress = Math.max(app.progress, n === 1 ? 0.03 : (n === 2 ? 0.06 : 0.86))
        } else if (line.startsWith("@pkg ")) {
          const f = line.split(" ")
          app.pkg = f[3] || ""
          app.progress = Math.max(app.progress, 0.06 + 0.8 * Number(f[1]) / Math.max(1, Number(f[2])))
        } else if (line.startsWith("@error ")) app.error = line.slice(7)
        else if (line === "@done") { app.progress = 1; app.page = 8 }
        else app.log = (app.log + line + "\n").slice(-12000)
      }
    }
    stderr: SplitParser { onRead: line => app.log = (app.log + line + "\n").slice(-12000) }
    onExited: code => { if (code !== 0 && !app.error) app.error = "The installation stopped. Details are in /var/log/memora-install.log." }
  }
  function install() {
    page = 7; error = ""; progress = 0.01; step = "Starting"
    writeAnswers.command = ["bash", "-c",
      "umask 077; { printf 'DISK=%q\\nUSERNAME=%q\\nFULLNAME=%q\\nPASSWORD=%q\\nHOSTNAME_=%q\\nTIMEZONE=%q\\nLOCALE=%q\\nKEYMAP=%q\\nXKB=%q\\nTHEME=%q\\nTOOLKITS=%q\\nENCRYPT=%q\\nMODE=%q\\nSIZE=%q\\n' \"$@\"; } > /tmp/memora-answers",
      "_", disk, userName, fullName.trim(), password, hostName, timezone, locale, keyboard.keymap, keyboard.xkb, look, toolkits.join(" "), encrypt ? "1" : "0", mode, mode === "alongside" ? String(Math.floor(size)) : "0"]
    writeAnswers.running = true
    password = ""; password2 = ""
  }

  // ---- the screen -----------------------------------------------------------
  FloatingWindow {
    id: win
    title: "Install Memora"
    color: "black"
    // Full screen in cage; a large window anywhere else.
    implicitWidth: 1280
    implicitHeight: 800
    Image {
      anchors.fill: parent
      source: "file://" + Theme.share + "/wallpapers/ember-" + app.look + ".jpg"
      sourceSize: Qt.size(2560, 1600)
      fillMode: Image.PreserveAspectCrop
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, app.look === "dark" ? 0.25 : 0.05) }

    Glass {
      id: card
      anchors.centerIn: parent
      width: Math.min(parent.width - 48, 780)
      height: Math.min(parent.height - 48, 620)
      radius: 26
      fill: Theme.dark ? Qt.rgba(0.09, 0.09, 0.11, 0.82) : Qt.rgba(0.98, 0.98, 0.99, 0.86)
      shadowSize: 50

      // Steps along the top.
      Row {
        id: dots
        anchors { top: parent.top; topMargin: 22; horizontalCenter: parent.horizontalCenter }
        spacing: 7
        visible: app.page > 0 && app.page < 7
        Repeater {
          model: 6
          delegate: Rectangle {
            required property int index
            width: index + 1 === app.page ? 22 : 7; height: 7; radius: 3.5
            color: index + 1 <= app.page ? Theme.accent : Theme.separator
            Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
          }
        }
      }

      Item {
        id: stage
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: foot.top; topMargin: 50; bottomMargin: 18; leftMargin: 48; rightMargin: 48 }
        clip: true

        // 0 — hello
        Page {
          index: 0
          ColumnLayout {
            anchors.centerIn: parent
            width: parent.width
            spacing: 14
            Image { Layout.alignment: Qt.AlignHCenter; source: "file://" + Theme.share + "/themes/" + Theme.mode + "/logo.png"; Layout.preferredWidth: 104; Layout.preferredHeight: 104; sourceSize: Qt.size(208, 208) }
            Txt { Layout.alignment: Qt.AlignHCenter; text: "Install Memora"; font.pixelSize: 30; font.weight: Font.Bold }
            Txt { Layout.alignment: Qt.AlignHCenter; text: "A calm, beautiful desktop. It takes about ten minutes."; color: Theme.textDim }
            Txt {
              Layout.alignment: Qt.AlignHCenter; visible: app.onBattery
              text: "Plug in the charger: installing takes a while."; color: "#f07322"; font.pixelSize: Theme.small + 0.5
            }
            Item { Layout.preferredHeight: 18 }
            GridLayout {
              Layout.alignment: Qt.AlignHCenter
              columns: 2; columnSpacing: 14; rowSpacing: 10
              Txt { text: "Keyboard"; color: Theme.textDim; Layout.alignment: Qt.AlignRight }
              Pick { model: app.keyboards.map(k => k.name); current: app.keyboard.name; onPicked: v => app.keyboard = app.keyboards.find(k => k.name === v) }
              Txt { text: "Language"; color: Theme.textDim; Layout.alignment: Qt.AlignRight }
              Pick { model: app.locales.map(l => l[1]); current: (app.locales.find(l => l[0] === app.locale) || app.locales[0])[1]; onPicked: v => app.locale = app.locales.find(l => l[1] === v)[0] }
            }
          }
        }

        // 1 — network
        Page {
          index: 1
          ColumnLayout {
            anchors.fill: parent
            spacing: 10
            Heading { title: "Connect to the internet"; sub: "Memora downloads the latest version of everything while it installs." }
            Rectangle {
              Layout.fillWidth: true; Layout.fillHeight: true
              radius: 12; color: Theme.field; border.color: Theme.separator
              clip: true
              ListView {
                id: nets
                anchors { fill: parent; margins: 6 }
                model: app.networks
                spacing: 2
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool open: nets.currentIndex === index
                  required property int index
                  width: nets.width; height: open && !modelData.open ? 84 : 40; radius: 8
                  color: open ? Theme.hover : (nh.hovered ? Theme.hover : "transparent")
                  Behavior on height { NumberAnimation { duration: Theme.fast } }
                  Sym { x: 12; y: 12; name: "wifi"; level: modelData.signal / 4; width: 16; height: 16 }
                  Txt { x: 40; y: 11; text: modelData.ssid; font.weight: open ? Font.Bold : Font.Normal }
                  Txt { anchors { right: parent.right; rightMargin: 12 } y: 11; text: app.joining === modelData.ssid ? "Connecting…" : (modelData.open ? "" : "Locked"); color: Theme.textDim; font.pixelSize: Theme.small }
                  HoverHandler { id: nh }
                  TapHandler { onTapped: { nets.currentIndex = index; if (modelData.open) app.connect(modelData.ssid, "") } }
                  RowLayout {
                    visible: parent.open && !modelData.open
                    x: 40; y: 44; width: parent.width - 52
                    Kit.Field { id: wpass; Layout.fillWidth: true; secret: true; placeholder: "Password"; onAccepted: app.connect(modelData.ssid, text) }
                    Kit.Button { text: "Join"; primary: true; onClicked: app.connect(modelData.ssid, wpass.text) }
                  }
                }
                Txt {
                  anchors.centerIn: parent; visible: nets.count === 0
                  text: app.wifiDev === "" && !scan.running ? "No Wi-Fi here. Plug in a network cable." : "Looking for networks…"
                  color: Theme.textDim
                }
              }
            }
            Txt { text: app.online ? "Connected." : app.wifiMsg; color: app.online ? Theme.green : Theme.red; font.pixelSize: Theme.small; visible: text !== "" }
          }
        }

        // 2 — disk
        Page {
          index: 2
          ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Heading {
              title: "Where should Memora go?"
              sub: app.probing ? "Looking at your disks…" : (app.disks.length > 1 ? "Pick a disk, then how to use it." : "Choose how to use this disk.")
            }
            // The disks, side by side.
            Flow {
              Layout.fillWidth: true
              spacing: 10
              visible: !app.probing
              Repeater {
                model: app.disks
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool on: app.disk === modelData.path
                  width: app.disks.length === 1 ? stage.width : (stage.width - 10 * (Math.min(app.disks.length, 3) - 1)) / Math.min(app.disks.length, 3)
                  height: 58; radius: 12
                  color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (dh.hovered ? Theme.hover : Theme.field)
                  border.width: on ? 2 : 1; border.color: on ? Theme.accent : Theme.separator
                  Behavior on color { ColorAnimation { duration: Theme.fast } }
                  Rectangle {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34; radius: 9; color: modelData.systems.length ? "#3b82f6" : "#8a8d96"
                    Sym { anchors.centerIn: parent; name: "display"; width: 17; height: 17; color: "#ffffff" }
                  }
                  Column {
                    x: 56; width: parent.width - 66; anchors.verticalCenter: parent.verticalCenter
                    Txt { width: parent.width; text: modelData.model; font.weight: Font.Bold; elide: Text.ElideRight }
                    Txt {
                      width: parent.width; elide: Text.ElideRight
                      text: app.gb(modelData.size) + " · " + (modelData.systems.length ? modelData.systems.join(", ") : (modelData.parts.length ? "Files" : "Empty"))
                      color: Theme.textDim; font.pixelSize: Theme.small
                    }
                  }
                  HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: app.pickDisk(modelData.path) }
                }
              }
            }
            Txt { visible: !app.probing && app.disks.length === 0; text: "No disk found to install on."; color: Theme.red }

            // How to use it.
            Choice {
              visible: app.chosenDisk !== null && app.chosenDisk.parts.length > 0
              on: app.mode === "alongside"
              enabled: app.canAlongside(app.chosenDisk)
              title: app.others(app.chosenDisk) ? "Install next to " + app.others(app.chosenDisk) : "Use the free space"
              detail: enabled ? (app.others(app.chosenDisk) ? "Keep " + app.others(app.chosenDisk) + " and your files. Pick a system each time the computer starts."
                                                            : "Keep the files on this disk; Memora takes the space you give it.")
                              : app.alongsideProblem(app.chosenDisk)
              onPicked: { app.mode = "alongside"; if (app.size < app.minSize) app.size = app.defaultSize(app.chosenDisk) }
            }
            Choice {
              visible: app.chosenDisk !== null
              on: app.mode === "erase"
              title: app.chosenDisk && app.chosenDisk.parts.length ? "Erase the disk and install Memora" : "Install Memora on this disk"
              detail: !app.chosenDisk ? "" : (app.others(app.chosenDisk) ? app.others(app.chosenDisk) + " and everything else on this disk will be removed."
                                     : (app.chosenDisk.parts.length ? "Everything on this disk will be removed." : "Memora uses the whole disk."))
              onPicked: app.mode = "erase"
            }

            // Next to another system: share the disk by dragging the line.
            Item {
              Layout.fillWidth: true
              implicitHeight: 70
              visible: app.mode === "alongside" && app.chosenDisk !== null
              readonly property var d: app.chosenDisk
              readonly property real total: d ? d.size : 1
              readonly property real hi: app.room(d)
              Rectangle {
                id: bar
                width: parent.width; height: 40; radius: 10
                color: Theme.field; border.color: Theme.separator
                clip: true
                // Memora's share sits on the right.
                Rectangle {
                  id: mem
                  anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                  width: Math.max(80, parent.width * app.size / parent.parent.total)
                  radius: 10
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.15) }
                    GradientStop { position: 1; color: Theme.accent }
                  }
                  Txt { anchors.centerIn: parent; text: "Memora"; color: "#ffffff"; font.weight: Font.Bold; font.pixelSize: Theme.small + 0.5 }
                }
                Txt {
                  anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                  width: bar.width - mem.width - 28; elide: Text.ElideRight
                  text: app.others(parent.parent.d) || "Your files"; font.weight: Font.Bold; font.pixelSize: Theme.small + 0.5
                }
              }
              // The handle on the line between them.
              Rectangle {
                id: knob
                x: bar.width - mem.width - width / 2; anchors.verticalCenter: bar.verticalCenter
                width: 14; height: 52; radius: 7
                visible: parent.hi > app.minSize + 1e9
                color: Theme.dark ? "#f2f2f4" : "#ffffff"
                border.color: kd.active ? Theme.accent : Theme.separator; border.width: kd.active ? 2 : 1
                Rectangle { anchors.centerIn: parent; width: 2; height: 18; radius: 1; color: Theme.textFaint }
                HoverHandler { cursorShape: Qt.SplitHCursor }
                DragHandler {
                  id: kd
                  target: null; yAxis.enabled: false
                  // Measured on the screen: the handle itself moves while dragged.
                  property real from: 0
                  property real x0: 0
                  onActiveChanged: if (active) { from = app.size; x0 = centroid.scenePosition.x }
                  onCentroidChanged: if (active) {
                    const it = knob.parent
                    const v = from - (centroid.scenePosition.x - x0) / bar.width * it.total
                    // Whole gigabytes, never past what can be taken.
                    app.size = Math.max(app.minSize, Math.min(it.hi, Math.round(v / 1e9) * 1e9))
                  }
                }
                Tip { text: "Drag to share the disk"; delay: 500 }
              }
              Txt {
                y: 48; text: (app.others(parent.d) || "Your files") + " · " + app.gb(app.otherAfter > 0 ? app.otherAfter : parent.total - app.size)
                color: Theme.textDim; font.pixelSize: Theme.small
              }
              Txt {
                y: 48; anchors.right: parent.right
                text: "Memora · " + app.gb(app.size) + (parent.hi > app.minSize + 1e9 ? "  (up to " + app.gb(parent.hi) + ")" : "")
                color: Theme.textDim; font.pixelSize: Theme.small
              }
            }
            Item { Layout.fillHeight: true }
            Rectangle {
              Layout.fillWidth: true; implicitHeight: 52; radius: 12
              visible: !app.probing
              color: Theme.field; border.color: Theme.separator
              Sym { x: 16; anchors.verticalCenter: parent.verticalCenter; name: "lock"; width: 18; height: 18 }
              Column {
                x: 46; anchors.verticalCenter: parent.verticalCenter
                Txt { text: "Encrypt Memora" }
                Txt { text: "Recommended. Your password is asked when the computer starts."; color: Theme.textDim; font.pixelSize: Theme.small }
              }
              Kit.Switch { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } checked: app.encrypt; onToggled: on => app.encrypt = on }
            }
          }
        }

        // 3 — you
        Page {
          index: 3
          ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Heading { title: "Create your account"; sub: "Your password also protects changes to the system." }
            GridLayout {
              Layout.fillWidth: true
              columns: 2; columnSpacing: 16; rowSpacing: 12
              Txt { text: "Full name"; color: Theme.textDim; Layout.alignment: Qt.AlignRight }
              Kit.Field { Layout.fillWidth: true; placeholder: "Your name"; onTextChanged: app.fullName = text }
              Txt { text: "Username"; color: Theme.textDim; Layout.alignment: Qt.AlignRight }
              Kit.Field {
                Layout.fillWidth: true; text: app.userName
                onTextChanged: if (text !== app.userName) { app.userEdited = true; app.userName = text }
              }
              Item { width: 1; height: 1; visible: app.userError !== "" }
              Txt { visible: app.userError !== ""; text: app.userError; color: Theme.red; font.pixelSize: Theme.small }
              Txt { text: "Password"; color: Theme.textDim; Layout.alignment: Qt.AlignRight }
              Kit.Field { Layout.fillWidth: true; secret: true; text: app.password; onTextChanged: if (text !== app.password) app.password = text }
              Txt { text: "Again"; color: Theme.textDim; Layout.alignment: Qt.AlignRight }
              Kit.Field { Layout.fillWidth: true; secret: true; text: app.password2; onTextChanged: if (text !== app.password2) app.password2 = text }
              Item { width: 1; height: 1; visible: app.passError !== "" }
              Txt { visible: app.passError !== ""; text: app.passError; color: Theme.red; font.pixelSize: Theme.small }
              Txt { text: "Computer name"; color: Theme.textDim; Layout.alignment: Qt.AlignRight }
              Kit.Field { Layout.fillWidth: true; text: app.hostName; onTextChanged: app.hostName = text }
            }
            Item { Layout.fillHeight: true }
          }
        }

        // 4 — region
        Page {
          index: 4
          ColumnLayout {
            anchors.fill: parent
            spacing: 10
            Heading { title: "Time zone"; sub: "Selected: " + app.timezone.replace(/_/g, " ") }
            Kit.Field { id: tzq; Layout.fillWidth: true; placeholder: "Search for a city, e.g. Bucharest" }
            Rectangle {
              Layout.fillWidth: true; Layout.fillHeight: true
              radius: 12; color: Theme.field; border.color: Theme.separator
              clip: true
              ListView {
                id: tzl
                anchors { fill: parent; margins: 6 }
                model: app.zones.filter(z => !tzq.text || z.toLowerCase().replace(/_/g, " ").indexOf(tzq.text.toLowerCase()) >= 0)
                boundsBehavior: Flickable.StopAtBounds
                // Open on the zone already chosen (guessed from the network).
                Connections {
                  target: app
                  function onPageChanged() { if (app.page === 4 && !tzq.text) tzl.positionViewAtIndex(Math.max(0, app.zones.indexOf(app.timezone)), ListView.Center) }
                }
                delegate: Rectangle {
                  required property string modelData
                  width: tzl.width; height: 30; radius: 7
                  color: app.timezone === modelData ? Theme.accent : (zh.hovered ? Theme.hover : "transparent")
                  Txt { x: 12; anchors.verticalCenter: parent.verticalCenter; text: modelData.replace(/_/g, " ").replace(/\//g, " / "); color: app.timezone === modelData ? "#ffffff" : Theme.text }
                  HoverHandler { id: zh }
                  TapHandler { onTapped: app.timezone = modelData }
                }
              }
            }
          }
        }

        // 5 — look and extras
        Page {
          index: 5
          ColumnLayout {
            anchors.fill: parent
            spacing: 14
            Heading { title: "Choose your look"; sub: "Switch any time in Control Center." }
            Row {
              Layout.alignment: Qt.AlignHCenter
              spacing: 26
              Repeater {
                model: [["light", "Light"], ["dark", "Dark"]]
                delegate: Column {
                  required property var modelData
                  spacing: 8
                  Rectangle {
                    width: 200; height: 125; radius: 12
                    border.width: app.look === modelData[0] ? 3 : 1
                    border.color: app.look === modelData[0] ? Theme.accent : Theme.separator
                    clip: true
                    Image { anchors { fill: parent; margins: 3 } source: "file://" + Theme.share + "/wallpapers/ember-" + modelData[0] + ".jpg"; sourceSize: Qt.size(400, 250); fillMode: Image.PreserveAspectCrop }
                    Rectangle { x: 20; y: 22; width: 100; height: 66; radius: 8; color: modelData[0] === "dark" ? "#2a2a2e" : "#ffffff"; opacity: 0.92 }
                    TapHandler { onTapped: { app.look = modelData[0]; Theme.mode = modelData[0] } }
                  }
                  Txt { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; font.weight: app.look === modelData[0] ? Font.Bold : Font.Normal }
                }
              }
            }
            Txt { text: "Extras (optional)"; font.weight: Font.Bold; Layout.topMargin: 8 }
            Flow {
              Layout.fillWidth: true
              spacing: 8
              Repeater {
                model: app.kits
                delegate: Rectangle {
                  required property var modelData
                  readonly property bool on: app.toolkits.indexOf(modelData[0]) >= 0
                  width: kt.implicitWidth + 28; height: 30; radius: 15
                  color: on ? Theme.accent : Theme.field
                  border.color: on ? "transparent" : Theme.separator
                  Txt { id: kt; anchors.centerIn: parent; text: modelData[1]; color: parent.on ? "#ffffff" : Theme.text; font.pixelSize: Theme.small + 0.5 }
                  TapHandler { onTapped: app.toolkits = parent.on ? app.toolkits.filter(k => k !== modelData[0]) : app.toolkits.concat([modelData[0]]) }
                }
              }
            }
            Item { Layout.fillHeight: true }
          }
        }

        // 6 — review
        Page {
          index: 6
          ColumnLayout {
            anchors.fill: parent
            spacing: 12
            Heading { title: "Ready to install"; sub: "Check everything, then install." }
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: sum.implicitHeight + 24
              radius: 12; color: Theme.field; border.color: Theme.separator
              GridLayout {
                id: sum
                x: 18; y: 12; width: parent.width - 36
                columns: 2; columnSpacing: 18; rowSpacing: 7
                Repeater {
                  model: app.summary.length * 2
                  delegate: Txt {
                    required property int index
                    readonly property var row: app.summary[Math.floor(index / 2)]
                    Layout.fillWidth: index % 2 === 1; elide: Text.ElideRight
                    text: row[index % 2]; color: index % 2 ? Theme.text : Theme.textDim
                  }
                }
              }
            }
            Rectangle {
              Layout.fillWidth: true; implicitHeight: warn.implicitHeight + 22; radius: 12
              readonly property color tone: app.mode === "erase" ? Qt.rgba(1, 0.37, 0.34, 1) : Theme.accent
              color: Qt.rgba(tone.r, tone.g, tone.b, Theme.dark ? 0.14 : 0.1); border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.5)
              Txt { id: warn; x: 16; y: 11; width: parent.width - 32; wrapMode: Text.Wrap
                text: app.mode === "erase"
                  ? "Everything on " + (app.chosenDisk ? app.chosenDisk.model : "the disk") + " will be erased. This can't be undone."
                  : (app.otherAfter > 0
                     ? (app.others(app.chosenDisk) || "Your files") + " keep" + (app.others(app.chosenDisk) ? "s" : "") + " everything, in " + app.gb(app.otherAfter) + ". Resizing is safe, but as with any change to a disk, back up what you can't lose first."
                     : "Memora goes in the free space. Nothing on the disk is changed.") }
            }
            Item { Layout.fillHeight: true }
          }
        }

        // 7 — installing
        Page {
          index: 7
          ColumnLayout {
            anchors.centerIn: parent
            width: parent.width
            spacing: 14
            Image { Layout.alignment: Qt.AlignHCenter; source: "file://" + Theme.share + "/themes/" + Theme.mode + "/logo.png"; Layout.preferredWidth: 80; Layout.preferredHeight: 80; sourceSize: Qt.size(160, 160) }
            Txt { Layout.alignment: Qt.AlignHCenter; text: app.error ? "Installation stopped" : "Installing Memora"; font.pixelSize: 24; font.weight: Font.Bold }
            Txt {
              Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
              text: app.error || (app.step + (app.pkg ? " · " + app.pkg : ""))
              color: app.error ? Theme.red : Theme.textDim; font.pixelSize: Theme.small + 0.5
            }
            Rectangle {
              Layout.fillWidth: true; Layout.leftMargin: 40; Layout.rightMargin: 40
              height: 8; radius: 4; color: Theme.field
              Rectangle {
                height: parent.height; radius: 4; color: app.error ? Theme.red : Theme.accent
                width: Math.max(parent.height, parent.width * app.progress)
                Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Theme.easing } }
              }
            }
            Txt { Layout.alignment: Qt.AlignHCenter; visible: !app.error; text: Math.round(app.progress * 100) + "%"; color: Theme.textFaint; font.pixelSize: Theme.small }
            Kit.Button { Layout.alignment: Qt.AlignHCenter; visible: app.error !== ""; text: "Start Over"; onClicked: { app.error = ""; app.progress = 0; app.page = 2; diskList.running = true } }
          }
        }

        // 8 — done
        Page {
          index: 8
          ColumnLayout {
            anchors.centerIn: parent
            width: parent.width
            spacing: 14
            Rectangle {
              Layout.alignment: Qt.AlignHCenter
              width: 84; height: 84; radius: 42; color: Theme.green
              Sym { anchors.centerIn: parent; name: "check"; width: 40; height: 40; color: "#ffffff"; stroke: 2.4 }
            }
            Txt { Layout.alignment: Qt.AlignHCenter; text: "Memora is installed"; font.pixelSize: 28; font.weight: Font.Bold }
            Txt { Layout.alignment: Qt.AlignHCenter; text: "Remove the USB stick, then restart."; color: Theme.textDim }
            Txt {
              Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; Layout.maximumWidth: 520
              horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
              visible: app.mode === "alongside" && app.others(app.chosenDisk) !== ""
              text: "When the computer starts, pick Memora or " + app.others(app.chosenDisk) + " from the menu. Memora starts by itself after a few seconds."
                + (app.otherAfter > 0 && app.chosenDisk.shrink.fstype === "ntfs" ? " The first time, Windows may check its disk — that's normal." : "")
              color: Theme.textDim; font.pixelSize: Theme.small + 0.5
            }
          }
        }
      }

      // Buttons along the bottom.
      Item {
        id: foot
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 26 }
        height: 36
        visible: app.page !== 7
        Kit.Button {
          visible: app.page > 0 && app.page < 7
          anchors.left: parent.left
          text: "Back"; onClicked: app.back()
        }
        Kit.Button {
          visible: app.page === 0
          anchors.left: parent.left
          text: "Power Off"; onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
        }
        Big {
          anchors.right: parent.right
          text: app.page === 0 ? "Get Started" : (app.page === 6 ? (app.mode === "erase" ? "Erase and Install" : "Install") : (app.page === 8 ? "Restart" : "Continue"))
          danger: app.page === 6 && app.mode === "erase"
          enabled: app.canGo(app.page)
          onClicked: {
            if (app.page === 6) app.install()
            else if (app.page === 8) Quickshell.execDetached(["systemctl", "reboot"])
            else app.next()
          }
        }
      }
    }
  }

  // ---- pieces ---------------------------------------------------------------
  component Page: Item {
    required property int index
    width: stage.width; height: stage.height
    x: (index - app.page) * (stage.width + 60)
    opacity: index === app.page ? 1 : 0
    visible: Math.abs(index - app.page) <= 1
    Behavior on x { NumberAnimation { duration: Theme.slow; easing.type: Theme.easingEmph } }
    Behavior on opacity { NumberAnimation { duration: Theme.normal } }
  }
  // One way to use the disk: a radio card.
  component Choice: Rectangle {
    id: ch
    property bool on: false
    property string title
    property string detail
    signal picked()
    Layout.fillWidth: true
    implicitHeight: chc.implicitHeight + 22; radius: 12
    color: on && enabled ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : (chh.hovered && enabled ? Theme.hover : Theme.field)
    border.width: on && enabled ? 2 : 1; border.color: on && enabled ? Theme.accent : Theme.separator
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Rectangle {
      x: 16; y: 14; width: 18; height: 18; radius: 9
      color: "transparent"; border.width: 2; border.color: ch.on && ch.enabled ? Theme.accent : Theme.textFaint
      Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Theme.accent; visible: ch.on && ch.enabled }
    }
    Column {
      id: chc
      x: 46; y: 11; width: parent.width - 62; spacing: 2
      Txt { text: ch.title; font.weight: Font.Bold; opacity: ch.enabled ? 1 : 0.55 }
      Txt { width: parent.width; text: ch.detail; wrapMode: Text.Wrap; color: ch.enabled ? Theme.textDim : "#f07322"; font.pixelSize: Theme.small; visible: text !== "" }
    }
    HoverHandler { id: chh; cursorShape: ch.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: ch.enabled; onTapped: ch.picked() }
  }
  component Heading: ColumnLayout {
    property string title
    property string sub
    spacing: 4
    Layout.fillWidth: true
    Layout.bottomMargin: 6
    Txt { text: parent.title; font.pixelSize: 22; font.weight: Font.Bold }
    Txt { text: parent.sub; color: Theme.textDim; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap }
  }
  component Big: Rectangle {
    id: bb
    property string text
    property bool danger: false
    signal clicked()
    width: bt.implicitWidth + 40; height: 36; radius: 10
    color: !enabled ? Theme.field : (danger ? Theme.red : Theme.accent)
    opacity: enabled ? (bh.hovered ? 0.92 : 1) : 0.7
    Txt { id: bt; anchors.centerIn: parent; text: bb.text; color: bb.enabled ? "#ffffff" : Theme.textFaint; font.weight: Font.Bold }
    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: bb.enabled; onTapped: bb.clicked() }
  }
  // A small dropdown: the current value, and a list under it.
  component Pick: Rectangle {
    id: pk
    property var model: []
    property string current: ""
    property bool open: false
    signal picked(string v)
    width: 240; height: 32; radius: 8
    color: Theme.field; border.color: open ? Theme.accent : Theme.separator
    z: open ? 10 : 0
    Txt { x: 12; anchors.verticalCenter: parent.verticalCenter; text: pk.current }
    Sym { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } name: "chevron"; rotation: 90; width: 10; height: 10; color: Theme.textDim }
    TapHandler { onTapped: pk.open = !pk.open }
    Glass {
      visible: pk.open
      y: pk.height + 4; width: pk.width; height: Math.min(260, col.implicitHeight + 10)
      radius: 10; fill: Theme.dark ? "#2a2a2e" : "#ffffff"; shadowSize: 18
      Flickable {
        anchors { fill: parent; margins: 5 }
        contentHeight: col.implicitHeight; clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
          id: col
          width: parent.width
          Repeater {
            model: pk.model
            delegate: Rectangle {
              required property string modelData
              width: col.width; height: 28; radius: 6
              color: ih.hovered ? Theme.accent : "transparent"
              Txt { x: 8; anchors.verticalCenter: parent.verticalCenter; text: modelData; color: ih.hovered ? "#ffffff" : Theme.text }
              HoverHandler { id: ih }
              TapHandler { onTapped: { pk.open = false; pk.picked(modelData) } }
            }
          }
        }
      }
    }
  }
}
