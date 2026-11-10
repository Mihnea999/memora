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
    { name: "Swiss German", keymap: "de_CH-latin1", xkb: "ch" }, { name: "French", keymap: "fr", xkb: "fr" },
    { name: "Belgian", keymap: "be-latin1", xkb: "be" }, { name: "Spanish", keymap: "es", xkb: "es" },
    { name: "Portuguese", keymap: "pt-latin1", xkb: "pt" }, { name: "Brazilian", keymap: "br-abnt2", xkb: "br" },
    { name: "Italian", keymap: "it", xkb: "it" }, { name: "Polish", keymap: "pl", xkb: "pl" },
    { name: "Hungarian", keymap: "hu", xkb: "hu" }, { name: "Czech", keymap: "cz-qwertz", xkb: "cz" },
    { name: "Swedish", keymap: "sv-latin1", xkb: "se" }, { name: "Norwegian", keymap: "no-latin1", xkb: "no" },
    { name: "Danish", keymap: "dk-latin1", xkb: "dk" }, { name: "Finnish", keymap: "fi", xkb: "fi" },
    { name: "Turkish", keymap: "trq", xkb: "tr" }]
  readonly property var locales: [["en_US.UTF-8", "English (US)"], ["en_GB.UTF-8", "English (UK)"], ["ro_RO.UTF-8", "Română"],
    ["de_DE.UTF-8", "Deutsch"], ["fr_FR.UTF-8", "Français"], ["es_ES.UTF-8", "Español"], ["it_IT.UTF-8", "Italiano"],
    ["pt_PT.UTF-8", "Português"], ["pt_BR.UTF-8", "Português (Brasil)"], ["nl_NL.UTF-8", "Nederlands"], ["pl_PL.UTF-8", "Polski"],
    ["hu_HU.UTF-8", "Magyar"], ["cs_CZ.UTF-8", "Čeština"], ["sv_SE.UTF-8", "Svenska"], ["da_DK.UTF-8", "Dansk"],
    ["nb_NO.UTF-8", "Norsk"], ["fi_FI.UTF-8", "Suomi"], ["el_GR.UTF-8", "Ελληνικά"], ["bg_BG.UTF-8", "Български"],
    ["uk_UA.UTF-8", "Українська"], ["ru_RU.UTF-8", "Русский"], ["tr_TR.UTF-8", "Türkçe"], ["ja_JP.UTF-8", "日本語"],
    ["zh_CN.UTF-8", "中文 (简体)"], ["ko_KR.UTF-8", "한국어"]]
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
    ["Drivers", drivers.length ? drivers.join(", ") + " (downloaded automatically)" : "Downloaded automatically"],
    ["Extras", toolkits.length ? toolkits.map(k => (kits.find(x => x[0] === k) || [k, k])[1]).join(", ") : "None"]]

  function canGo(p) {
    if (p === 1) return online
    if (p === 2) return !probing && disk !== "" && (mode === "erase" || size >= minSize)
    if (p === 3) return youOk
    return true
  }
  function next() { page = page + 1 }
  function back() { page = Math.max(0, page - 1) }
  // What the big button does on each page (also Return).
  function go() {
    if (!canGo(page) || page === 7) return
    if (page === 6) install()
    else if (page === 8) Quickshell.execDetached(["systemctl", "reboot"])
    else next()
  }

  // ---- no mouse or keyboard assumed --------------------------------------------
  // Everything can be reached with Tab and pressed with Space or Return; a finger
  // on the screen brings up the on-screen keyboard for the text field in use.
  property bool touched: false          // the last thing used was a finger
  property bool oskPinned: false        // the keyboard button in the corner
  property var target: null             // the text field being typed into
  readonly property bool oskShown: (touched || oskPinned) && target !== null && target.activeFocus && page !== 7
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

  // The drivers this computer needs, downloaded while installing (shown on the
  // review page): graphics, Wi-Fi chips without free firmware, and firmware updates.
  property var drivers: []
  Process {
    running: true
    command: ["memora-drivers"]
    stdout: StdioCollector { onStreamFinished: app.drivers = text.split("\n").filter(l => l) }
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

    Item {
      id: screen
      anchors.fill: parent
      Image {
        anchors.fill: parent
        source: "file://" + Theme.share + "/wallpapers/ember-" + app.look + ".jpg"
        sourceSize: Qt.size(2560, 1600)
        fillMode: Image.PreserveAspectCrop
      }
      Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, app.look === "dark" ? 0.25 : 0.05) }
      // A finger on the screen: text fields bring up the on-screen keyboard.
      PointHandler { acceptedDevices: PointerDevice.TouchScreen; onActiveChanged: if (active) app.touched = true }

      // The room the on-screen keyboard leaves.
      readonly property real free: height - (app.oskShown ? osk.height : 0)

      Glass {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 32, 980)
        height: Math.max(360, Math.min(screen.free - 32, 740))
        y: Math.max(16, (screen.free - height) / 2)
        Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
        Behavior on height { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
        radius: 28
        fill: Theme.dark ? Qt.rgba(0.09, 0.09, 0.11, 0.84) : Qt.rgba(0.98, 0.98, 0.99, 0.88)
        focus: true

        // Return goes on, Escape goes back; Tab moves between everything.
        Keys.onReturnPressed: event => { app.go(); event.accepted = true }
        Keys.onEnterPressed: event => { app.go(); event.accepted = true }
        Keys.onEscapePressed: event => {
          if (sheet.owner) sheet.close()
          else if (app.page > 0 && app.page < 7) app.back()
          event.accepted = true
        }

        // Each page starts with the first thing on it (a text field, a list).
        Connections {
          target: app
          function onPageChanged() { focusTimer.restart() }
        }
        Timer {
          id: focusTimer
          interval: 30
          onTriggered: {
            if (app.page === 3) nameField.input.forceActiveFocus()
            else if (app.page === 4) tzl.forceActiveFocus()
            else if (app.page === 1 && !app.online) nets.forceActiveFocus()
            else nextBtn.forceActiveFocus()
          }
        }
        Component.onCompleted: focusTimer.start()

        // Steps along the top.
        Row {
          id: dots
          anchors { top: parent.top; topMargin: 24; horizontalCenter: parent.horizontalCenter }
          spacing: 8
          visible: app.page > 0 && app.page < 7
          Repeater {
            model: 6
            delegate: Rectangle {
              required property int index
              width: index + 1 === app.page ? 26 : 8; height: 8; radius: 4
              color: index + 1 <= app.page ? Theme.accent : Theme.separator
              Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
            }
          }
        }

        Item {
          id: stage
          anchors { left: parent.left; right: parent.right; top: parent.top; bottom: foot.top; topMargin: 56; bottomMargin: 20; leftMargin: 56; rightMargin: 56 }
          clip: true

          // 0 — hello
          Page {
            index: 0
            Flickable {
              anchors.fill: parent
              contentHeight: Math.max(height, hello.implicitHeight)
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              ColumnLayout {
                id: hello
                width: parent.width
                y: Math.max(0, (parent.parent.height - implicitHeight) / 2)
                spacing: 14
                Image { Layout.alignment: Qt.AlignHCenter; source: "file://" + Theme.share + "/themes/" + Theme.mode + "/logo.png"; Layout.preferredWidth: stage.height < 480 ? 64 : 112; Layout.preferredHeight: Layout.preferredWidth; sourceSize: Qt.size(224, 224) }
                Txt { Layout.alignment: Qt.AlignHCenter; text: "Install Memora"; font.pixelSize: 34; font.weight: Font.Bold }
                Txt { Layout.alignment: Qt.AlignHCenter; text: "A calm, beautiful desktop. It takes about ten minutes."; color: Theme.textDim; font.pixelSize: Theme.large }
                Txt {
                  Layout.alignment: Qt.AlignHCenter; visible: app.onBattery
                  text: "Plug in the charger: installing takes a while."; color: "#f07322"; font.pixelSize: Theme.fontSize
                }
                Item { Layout.preferredHeight: 18 }
                GridLayout {
                  Layout.alignment: Qt.AlignHCenter
                  columns: 2; columnSpacing: 18; rowSpacing: 12
                  Txt { text: "Language"; color: Theme.textDim; font.pixelSize: Theme.large; Layout.alignment: Qt.AlignRight }
                  Pick {
                    title: "Language"
                    model: app.locales.map(l => l[1]); current: (app.locales.find(l => l[0] === app.locale) || app.locales[0])[1]
                    onPicked: v => app.locale = app.locales.find(l => l[1] === v)[0]
                  }
                  Txt { text: "Keyboard"; color: Theme.textDim; font.pixelSize: Theme.large; Layout.alignment: Qt.AlignRight }
                  Pick {
                    title: "Keyboard layout"
                    model: app.keyboards.map(k => k.name); current: app.keyboard.name
                    onPicked: v => app.keyboard = app.keyboards.find(k => k.name === v)
                  }
                }
              }
            }
          }

          // 1 — network
          Page {
            index: 1
            ColumnLayout {
              anchors.fill: parent
              spacing: 12
              Heading {
                title: "Connect to the internet"
                sub: app.online && app.networks.length === 0 ? "You're connected. Memora downloads the latest version of everything while it installs."
                                                            : "Memora downloads the latest version of everything, and the drivers this computer needs, while it installs."
              }
              Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                radius: 14; color: Theme.field; border.color: nets.activeFocus ? Theme.accent : Theme.separator; border.width: nets.activeFocus ? 2 : 1
                clip: true
                ListView {
                  id: nets
                  anchors { fill: parent; margins: 6 }
                  model: app.networks
                  spacing: 2
                  activeFocusOnTab: true
                  keyNavigationEnabled: true
                  boundsBehavior: Flickable.StopAtBounds
                  currentIndex: -1
                  // Space or Return on a network: join it (or ask for its password).
                  function choose(i) {
                    currentIndex = i
                    const n = app.networks[i]
                    if (!n) return
                    if (n.open) app.connect(n.ssid, "")
                    else currentItem && currentItem.pass.input.forceActiveFocus()
                  }
                  Keys.onSpacePressed: event => { choose(Math.max(0, currentIndex)); event.accepted = true }
                  Keys.onReturnPressed: event => { if (currentIndex >= 0) { choose(currentIndex); event.accepted = true } else event.accepted = false }
                  onActiveFocusChanged: if (activeFocus && currentIndex < 0 && count) currentIndex = 0
                  delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool open: nets.currentIndex === index
                    readonly property alias pass: wpass
                    width: nets.width; height: open && !modelData.open ? 116 : 54; radius: 10
                    color: open ? Theme.hover : (nh.hovered ? Theme.hover : "transparent")
                    border.width: open && nets.activeFocus ? 2 : 0; border.color: Theme.accent
                    Behavior on height { NumberAnimation { duration: Theme.fast } }
                    Sym { x: 16; y: 17; name: "wifi"; level: modelData.signal / 4; width: 20; height: 20 }
                    Txt { x: 50; y: 0; height: 54; text: modelData.ssid; font.pixelSize: Theme.large; font.weight: row.open ? Font.Bold : Font.Normal; width: parent.width - 180 }
                    Txt {
                      anchors { right: parent.right; rightMargin: 16 } y: 0; height: 54
                      text: app.joining === modelData.ssid ? "Connecting…" : (modelData.open ? "Open" : "Locked"); color: Theme.textDim
                    }
                    HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: nets.choose(row.index) }
                    RowLayout {
                      visible: row.open && !modelData.open
                      x: 50; y: 58; width: parent.width - 66; spacing: 10
                      Entry { id: wpass; Layout.fillWidth: true; secret: true; placeholder: "Password for " + modelData.ssid; eatReturn: true; onAccepted: app.connect(modelData.ssid, text) }
                      Btn { text: "Join"; primary: true; onClicked: app.connect(modelData.ssid, wpass.text) }
                    }
                  }
                  Column {
                    anchors.centerIn: parent; visible: nets.count === 0
                    spacing: 10
                    Sym { anchors.horizontalCenter: parent.horizontalCenter; name: app.online ? "check" : "wifi"; width: 34; height: 34; color: app.online ? Theme.green : Theme.textDim }
                    Txt {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: app.online ? "Connected with a network cable." : (app.wifiDev === "" && !scan.running ? "No Wi-Fi here. Plug in a network cable." : "Looking for Wi-Fi networks…")
                      color: Theme.textDim; font.pixelSize: Theme.large
                    }
                  }
                }
              }
              RowLayout {
                Layout.fillWidth: true
                Txt { Layout.fillWidth: true; text: app.online ? "Connected." : app.wifiMsg; color: app.online ? Theme.green : Theme.red; visible: text !== "" }
                Btn { text: scan.running ? "Looking…" : "Look Again"; enabled: !scan.running && app.wifiDev !== ""; visible: app.wifiDev !== ""; onClicked: scan.running = true }
              }
            }
          }

          // 2 — disk
          Page {
            index: 2
            Flickable {
              anchors.fill: parent
              contentHeight: Math.max(height, diskPage.implicitHeight)
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              ColumnLayout {
                id: diskPage
                width: parent.width
                height: Math.max(parent.parent.height, implicitHeight)
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
                      id: dk
                      required property var modelData
                      readonly property bool on: app.disk === modelData.path
                      width: app.disks.length === 1 ? stage.width : (stage.width - 10 * (Math.min(app.disks.length, 3) - 1)) / Math.min(app.disks.length, 3)
                      height: 68; radius: 14
                      activeFocusOnTab: true
                      Keys.onSpacePressed: app.pickDisk(modelData.path)
                      color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (dh.hovered ? Theme.hover : Theme.field)
                      border.width: on ? 2 : 1; border.color: on ? Theme.accent : Theme.separator
                      Behavior on color { ColorAnimation { duration: Theme.fast } }
                      Ring {}
                      Rectangle {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 40; radius: 10; color: modelData.systems.length ? "#3b82f6" : "#8a8d96"
                        Sym { anchors.centerIn: parent; name: "display"; width: 20; height: 20; color: "#ffffff" }
                      }
                      Column {
                        x: 66; width: parent.width - 78; anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Txt { width: parent.width; text: modelData.model; font.pixelSize: Theme.large; font.weight: Font.Bold; elide: Text.ElideRight }
                        Txt {
                          width: parent.width; elide: Text.ElideRight
                          text: app.gb(modelData.size) + " · " + (modelData.systems.length ? modelData.systems.join(", ") : (modelData.parts.length ? "Files" : "Empty"))
                          color: Theme.textDim
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

                // Next to another system: share the disk by dragging the line
                // (or with the arrow keys on the handle).
                Item {
                  id: share
                  Layout.fillWidth: true
                  implicitHeight: 80
                  visible: app.mode === "alongside" && app.chosenDisk !== null
                  readonly property var d: app.chosenDisk
                  readonly property real total: d ? d.size : 1
                  readonly property real hi: app.room(d)
                  function nudge(gbs) { app.size = Math.max(app.minSize, Math.min(hi, Math.round(app.size / 1e9 + gbs) * 1e9)) }
                  Rectangle {
                    id: bar
                    width: parent.width; height: 48; radius: 12
                    color: Theme.field; border.color: Theme.separator
                    clip: true
                    // Memora's share sits on the right.
                    Rectangle {
                      id: mem
                      anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                      width: Math.max(90, parent.width * app.size / share.total)
                      radius: 12
                      gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.15) }
                        GradientStop { position: 1; color: Theme.accent }
                      }
                      Txt { anchors.centerIn: parent; text: "Memora"; color: "#ffffff"; font.weight: Font.Bold }
                    }
                    Txt {
                      anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
                      width: bar.width - mem.width - 32; elide: Text.ElideRight
                      text: app.others(share.d) || "Your files"; font.weight: Font.Bold
                    }
                  }
                  // The handle on the line between them.
                  Rectangle {
                    id: knob
                    x: bar.width - mem.width - width / 2; anchors.verticalCenter: bar.verticalCenter
                    width: 18; height: 62; radius: 9
                    visible: share.hi > app.minSize + 1e9
                    activeFocusOnTab: true
                    Keys.onLeftPressed: share.nudge(5)
                    Keys.onRightPressed: share.nudge(-5)
                    color: Theme.dark ? "#f2f2f4" : "#ffffff"
                    border.color: kd.active || activeFocus ? Theme.accent : Theme.separator; border.width: kd.active || activeFocus ? 3 : 1
                    Rectangle { anchors.centerIn: parent; width: 2; height: 22; radius: 1; color: Theme.textFaint }
                    HoverHandler { cursorShape: Qt.SplitHCursor }
                    DragHandler {
                      id: kd
                      target: null; yAxis.enabled: false
                      // Measured on the screen: the handle itself moves while dragged.
                      property real from: 0
                      property real x0: 0
                      onActiveChanged: if (active) { from = app.size; x0 = centroid.scenePosition.x }
                      onCentroidChanged: if (active) {
                        const v = from - (centroid.scenePosition.x - x0) / bar.width * share.total
                        // Whole gigabytes, never past what can be taken.
                        app.size = Math.max(app.minSize, Math.min(share.hi, Math.round(v / 1e9) * 1e9))
                      }
                    }
                    Tip { text: "Drag (or use the arrow keys) to share the disk"; delay: 500 }
                  }
                  Txt {
                    y: 56; text: (app.others(share.d) || "Your files") + " · " + app.gb(app.otherAfter > 0 ? app.otherAfter : share.total - app.size)
                    color: Theme.textDim
                  }
                  Txt {
                    y: 56; anchors.right: parent.right
                    text: "Memora · " + app.gb(app.size) + (share.hi > app.minSize + 1e9 ? "  (up to " + app.gb(share.hi) + ")" : "")
                    color: Theme.textDim
                  }
                }
                Item { Layout.fillHeight: true; Layout.minimumHeight: 4 }
                Rectangle {
                  id: enc
                  Layout.fillWidth: true; implicitHeight: 64; radius: 14
                  visible: !app.probing
                  activeFocusOnTab: true
                  Keys.onSpacePressed: app.encrypt = !app.encrypt
                  color: Theme.field; border.color: Theme.separator
                  Ring {}
                  Sym { x: 18; anchors.verticalCenter: parent.verticalCenter; name: "lock"; width: 20; height: 20 }
                  Column {
                    x: 52; width: parent.width - 130; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Txt { text: "Encrypt Memora"; font.pixelSize: Theme.large }
                    Txt { width: parent.width; text: "Recommended. Your password is asked when the computer starts."; color: Theme.textDim; wrapMode: Text.Wrap }
                  }
                  // Shows the state; the whole row is the switch.
                  Kit.Switch { anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter } checked: app.encrypt; enabled: false }
                  TapHandler { onTapped: app.encrypt = !app.encrypt }
                }
              }
            }
          }

          // 3 — you
          Page {
            index: 3
            Flickable {
              anchors.fill: parent
              contentHeight: you.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              ColumnLayout {
                id: you
                width: parent.width
                spacing: 14
                Heading { title: "Create your account"; sub: "Your password also protects changes to the system." }
                GridLayout {
                  Layout.fillWidth: true
                  columns: 2; columnSpacing: 18; rowSpacing: 12
                  Label { text: "Full name" }
                  Entry { id: nameField; Layout.fillWidth: true; placeholder: "Your name"; onTextChanged: app.fullName = text }
                  Label { text: "Username" }
                  Entry {
                    Layout.fillWidth: true; text: app.userName
                    onTextChanged: if (text !== app.userName) { app.userEdited = true; app.userName = text }
                  }
                  Item { width: 1; height: 1; visible: app.userError !== "" }
                  Txt { visible: app.userError !== ""; text: app.userError; color: Theme.red }
                  Label { text: "Password" }
                  Entry { Layout.fillWidth: true; secret: true; placeholder: "At least 4 characters"; text: app.password; onTextChanged: if (text !== app.password) app.password = text }
                  Label { text: "Again" }
                  Entry { Layout.fillWidth: true; secret: true; placeholder: "The same password"; text: app.password2; onTextChanged: if (text !== app.password2) app.password2 = text }
                  Item { width: 1; height: 1; visible: app.passError !== "" }
                  Txt { visible: app.passError !== ""; text: app.passError; color: Theme.red }
                  Label { text: "Computer name" }
                  Entry { Layout.fillWidth: true; text: app.hostName; onTextChanged: app.hostName = text }
                }
              }
            }
          }

          // 4 — region
          Page {
            index: 4
            ColumnLayout {
              anchors.fill: parent
              spacing: 12
              Heading { title: "Time zone"; sub: "Selected: " + app.timezone.replace(/_/g, " ") }
              Entry { id: tzq; Layout.fillWidth: true; placeholder: "Search for a city, e.g. Bucharest" }
              Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                radius: 14; color: Theme.field; border.color: tzl.activeFocus ? Theme.accent : Theme.separator; border.width: tzl.activeFocus ? 2 : 1
                clip: true
                ListView {
                  id: tzl
                  anchors { fill: parent; margins: 6 }
                  model: app.zones.filter(z => !tzq.text || z.toLowerCase().replace(/_/g, " ").indexOf(tzq.text.toLowerCase()) >= 0)
                  boundsBehavior: Flickable.StopAtBounds
                  activeFocusOnTab: true
                  keyNavigationEnabled: true
                  highlightMoveDuration: 0
                  // Typing a letter on the list searches.
                  Keys.onPressed: event => {
                    if (event.text && /\S/.test(event.text) && !(event.modifiers & Qt.ControlModifier)) {
                      tzq.input.forceActiveFocus(); tzq.text += event.text; event.accepted = true
                    }
                  }
                  // The arrow keys move through the list and pick as they go.
                  onCurrentIndexChanged: if (activeFocus && currentIndex >= 0 && model[currentIndex]) app.timezone = model[currentIndex]
                  onModelChanged: currentIndex = Math.max(0, model.indexOf(app.timezone))
                  // Open on the zone already chosen (guessed from the network).
                  Connections {
                    target: app
                    function onPageChanged() {
                      if (app.page === 4 && !tzq.text) {
                        tzl.currentIndex = Math.max(0, app.zones.indexOf(app.timezone))
                        tzl.positionViewAtIndex(tzl.currentIndex, ListView.Center)
                      }
                    }
                  }
                  delegate: Rectangle {
                    required property string modelData
                    required property int index
                    readonly property bool on: app.timezone === modelData
                    width: tzl.width; height: 44; radius: 9
                    color: on ? Theme.accent : (zh.hovered ? Theme.hover : "transparent")
                    Txt { x: 14; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 28; text: modelData.replace(/_/g, " ").replace(/\//g, " / "); font.pixelSize: Theme.large; color: parent.on ? "#ffffff" : Theme.text }
                    HoverHandler { id: zh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { tzl.currentIndex = index; app.timezone = modelData } }
                  }
                }
              }
            }
          }

          // 5 — look and extras
          Page {
            index: 5
            Flickable {
              anchors.fill: parent
              contentHeight: lookPage.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              ColumnLayout {
                id: lookPage
                width: parent.width
                spacing: 14
                Heading { title: "Choose your look"; sub: "Switch any time in Control Center." }
                Row {
                  Layout.alignment: Qt.AlignHCenter
                  spacing: 28
                  Repeater {
                    model: [["light", "Light"], ["dark", "Dark"]]
                    delegate: Column {
                      required property var modelData
                      spacing: 10
                      Rectangle {
                        width: 230; height: 144; radius: 14
                        activeFocusOnTab: true
                        Keys.onSpacePressed: { app.look = modelData[0]; Theme.mode = modelData[0] }
                        border.width: app.look === modelData[0] ? 3 : 1
                        border.color: app.look === modelData[0] ? Theme.accent : Theme.separator
                        clip: true
                        Image { anchors { fill: parent; margins: 3 } source: "file://" + Theme.share + "/wallpapers/ember-" + modelData[0] + ".jpg"; sourceSize: Qt.size(460, 288); fillMode: Image.PreserveAspectCrop }
                        Rectangle { x: 22; y: 24; width: 116; height: 76; radius: 9; color: modelData[0] === "dark" ? "#2a2a2e" : "#ffffff"; opacity: 0.92 }
                        Ring { border.width: 3 }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { app.look = modelData[0]; Theme.mode = modelData[0] } }
                      }
                      Txt { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; font.pixelSize: Theme.large; font.weight: app.look === modelData[0] ? Font.Bold : Font.Normal }
                    }
                  }
                }
                Txt { text: "Extras (optional)"; font.pixelSize: Theme.large; font.weight: Font.Bold; Layout.topMargin: 8 }
                Flow {
                  Layout.fillWidth: true
                  spacing: 10
                  Repeater {
                    model: app.kits
                    delegate: Rectangle {
                      required property var modelData
                      readonly property bool on: app.toolkits.indexOf(modelData[0]) >= 0
                      function flip() { app.toolkits = on ? app.toolkits.filter(k => k !== modelData[0]) : app.toolkits.concat([modelData[0]]) }
                      width: kt.implicitWidth + 36; height: 42; radius: 21
                      activeFocusOnTab: true
                      Keys.onSpacePressed: flip()
                      color: on ? Theme.accent : Theme.field
                      border.color: on ? "transparent" : Theme.separator
                      Ring {}
                      Txt { id: kt; anchors.centerIn: parent; text: modelData[1]; color: parent.on ? "#ffffff" : Theme.text }
                      HoverHandler { cursorShape: Qt.PointingHandCursor }
                      TapHandler { onTapped: parent.flip() }
                    }
                  }
                }
              }
            }
          }

          // 6 — review
          Page {
            index: 6
            Flickable {
              anchors.fill: parent
              contentHeight: review.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              clip: true
              ColumnLayout {
                id: review
                width: parent.width
                spacing: 12
                Heading { title: "Ready to install"; sub: "Check everything, then install." }
                Rectangle {
                  Layout.fillWidth: true
                  implicitHeight: sum.implicitHeight + 28
                  radius: 14; color: Theme.field; border.color: Theme.separator
                  GridLayout {
                    id: sum
                    x: 20; y: 14; width: parent.width - 40
                    columns: 2; columnSpacing: 20; rowSpacing: 9
                    Repeater {
                      model: app.summary.length * 2
                      delegate: Txt {
                        required property int index
                        readonly property var row: app.summary[Math.floor(index / 2)]
                        Layout.fillWidth: index % 2 === 1; Layout.alignment: Qt.AlignTop
                        wrapMode: index % 2 ? Text.Wrap : Text.NoWrap
                        text: row[index % 2]; color: index % 2 ? Theme.text : Theme.textDim
                      }
                    }
                  }
                }
                Rectangle {
                  Layout.fillWidth: true; implicitHeight: warn.implicitHeight + 26; radius: 14
                  readonly property color tone: app.mode === "erase" ? Qt.rgba(1, 0.37, 0.34, 1) : Theme.accent
                  color: Qt.rgba(tone.r, tone.g, tone.b, Theme.dark ? 0.14 : 0.1); border.color: Qt.rgba(tone.r, tone.g, tone.b, 0.5)
                  Txt { id: warn; x: 18; y: 13; width: parent.width - 36; wrapMode: Text.Wrap
                    text: app.mode === "erase"
                      ? "Everything on " + (app.chosenDisk ? app.chosenDisk.model : "the disk") + " will be erased. This can't be undone."
                      : (app.otherAfter > 0
                         ? (app.others(app.chosenDisk) || "Your files") + " keep" + (app.others(app.chosenDisk) ? "s" : "") + " everything, in " + app.gb(app.otherAfter) + ". Resizing is safe, but as with any change to a disk, back up what you can't lose first."
                         : "Memora goes in the free space. Nothing on the disk is changed.") }
                }
              }
            }
          }

          // 7 — installing
          Page {
            index: 7
            ColumnLayout {
              anchors.centerIn: parent
              width: parent.width
              spacing: 14
              Image { Layout.alignment: Qt.AlignHCenter; source: "file://" + Theme.share + "/themes/" + Theme.mode + "/logo.png"; Layout.preferredWidth: 88; Layout.preferredHeight: 88; sourceSize: Qt.size(176, 176) }
              Txt { Layout.alignment: Qt.AlignHCenter; text: app.error ? "Installation stopped" : "Installing Memora"; font.pixelSize: 26; font.weight: Font.Bold }
              Txt {
                Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                text: app.error || (app.step + (app.pkg ? " · " + app.pkg : ""))
                color: app.error ? Theme.red : Theme.textDim
              }
              Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: 40; Layout.rightMargin: 40
                height: 10; radius: 5; color: Theme.field
                Rectangle {
                  height: parent.height; radius: 5; color: app.error ? Theme.red : Theme.accent
                  width: Math.max(parent.height, parent.width * app.progress)
                  Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Theme.easing } }
                }
              }
              Txt { Layout.alignment: Qt.AlignHCenter; visible: !app.error; text: Math.round(app.progress * 100) + "%"; color: Theme.textFaint }
              Btn { id: overBtn; Layout.alignment: Qt.AlignHCenter; visible: app.error !== ""; text: "Start Over"; onClicked: { app.error = ""; app.progress = 0; app.page = 2; diskList.running = true } }
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
                width: 92; height: 92; radius: 46; color: Theme.green
                Sym { anchors.centerIn: parent; name: "check"; width: 44; height: 44; color: "#ffffff"; stroke: 2.4 }
              }
              Txt { Layout.alignment: Qt.AlignHCenter; text: "Memora is installed"; font.pixelSize: 30; font.weight: Font.Bold }
              Txt { Layout.alignment: Qt.AlignHCenter; text: "Remove the USB stick, then restart."; color: Theme.textDim; font.pixelSize: Theme.large }
              Txt {
                Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; Layout.maximumWidth: 560
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                visible: app.mode === "alongside" && app.others(app.chosenDisk) !== ""
                text: "When the computer starts, pick Memora or " + app.others(app.chosenDisk) + " from the menu. Memora starts by itself after a few seconds."
                  + (app.otherAfter > 0 && app.chosenDisk.shrink.fstype === "ntfs" ? " The first time, Windows may check its disk — that's normal." : "")
                color: Theme.textDim
              }
            }
          }
        }

        // Buttons along the bottom.
        Item {
          id: foot
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 28 }
          height: 48
          visible: app.page !== 7
          Row {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            spacing: 10
            Btn { visible: app.page > 0 && app.page < 7; text: "Back"; onClicked: app.back() }
            Btn { visible: app.page === 0; text: "Power Off"; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
            // The on-screen keyboard, for a computer without one.
            Btn {
              visible: app.page === 1 || app.page === 3 || app.page === 4
              icon: "keyboard"; on: app.oskPinned
              tip: app.oskPinned ? "Hide the on-screen keyboard" : "Show the on-screen keyboard"
              onClicked: app.oskPinned = !app.oskPinned
            }
          }
          Btn {
            id: nextBtn
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            primary: true
            text: app.page === 0 ? "Get Started" : (app.page === 6 ? (app.mode === "erase" ? "Erase and Install" : "Install") : (app.page === 8 ? "Restart" : "Continue"))
            danger: app.page === 6 && app.mode === "erase"
            enabled: app.canGo(app.page)
            onClicked: app.go()
          }
        }

        // A list to choose from, over the whole card (language, keyboard): big
        // rows, scrolls with a finger, the wheel or the arrow keys.
        Rectangle {
          id: sheet
          property var owner: null
          anchors.fill: parent
          radius: card.radius
          color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25)
          visible: opacity > 0
          opacity: owner ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Theme.fast } }
          z: 50
          function show(o) {
            owner = o
            pickList.model = o.model
            pickList.currentIndex = Math.max(0, o.model.indexOf(o.current))
            pickList.positionViewAtIndex(pickList.currentIndex, ListView.Center)
            pickList.forceActiveFocus()
          }
          function choose(i) {
            const o = owner
            if (!o || i < 0) return
            o.picked(o.model[i])
            close()
          }
          function close() {
            const o = owner
            owner = null
            if (o) o.forceActiveFocus()
          }
          MouseArea { anchors.fill: parent; enabled: sheet.owner !== null; onClicked: sheet.close() }
          Glass {
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 480)
            height: Math.min(parent.height - 60, 600)
            radius: 20
            fill: Theme.dark ? "#26262a" : "#ffffff"
            MouseArea { anchors.fill: parent }   // taps inside don't close it
            Txt { x: 22; y: 16; height: 34; text: sheet.owner ? sheet.owner.title : ""; font.pixelSize: 19; font.weight: Font.Bold }
            Btn { anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 12 } icon: "close"; tip: "Close"; onClicked: sheet.close() }
            ListView {
              id: pickList
              anchors { fill: parent; topMargin: 64; leftMargin: 10; rightMargin: 10; bottomMargin: 10 }
              clip: true
              spacing: 2
              keyNavigationEnabled: true
              highlightMoveDuration: 0
              boundsBehavior: Flickable.StopAtBounds
              Keys.onReturnPressed: event => { sheet.choose(currentIndex); event.accepted = true }
              Keys.onEnterPressed: event => { sheet.choose(currentIndex); event.accepted = true }
              Keys.onSpacePressed: event => { sheet.choose(currentIndex); event.accepted = true }
              Keys.onTabPressed: event => { event.accepted = true }
              delegate: Rectangle {
                required property string modelData
                required property int index
                readonly property bool chosen: sheet.owner && sheet.owner.current === modelData
                width: pickList.width; height: 52; radius: 10
                color: pickList.currentIndex === index ? Theme.accent : (ph.hovered ? Theme.hover : "transparent")
                Txt { x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 60; text: modelData; font.pixelSize: Theme.large; color: pickList.currentIndex === index ? "#ffffff" : Theme.text }
                Sym { visible: parent.chosen; anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } name: "check"; width: 18; height: 18; color: pickList.currentIndex === index ? "#ffffff" : Theme.accent }
                HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: sheet.choose(index) }
              }
            }
          }
        }
      }

      // The on-screen keyboard: comes up from the bottom while a text field is
      // in use and a finger was used (or the keyboard button is on).
      Osk {
        id: osk
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width, 1100)
        y: app.oskShown ? parent.height - height : parent.height + 8
        Behavior on y { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
      }
    }
  }

  // ---- pieces ---------------------------------------------------------------
  component Page: Item {
    required property int index
    width: stage.width; height: stage.height
    x: (index - app.page) * (stage.width + 60)
    opacity: index === app.page ? 1 : 0
    // Only the page in view (and one fading out) takes part, so Tab stays on it.
    visible: index === app.page || opacity > 0.01
    enabled: index === app.page
    Behavior on x { NumberAnimation { duration: Theme.slow; easing.type: Theme.easingEmph } }
    Behavior on opacity { NumberAnimation { duration: Theme.normal } }
  }
  // The ring around whatever Tab is on.
  component Ring: Rectangle {
    property real out: 0                  // drawn this far outside (else on the edge)
    anchors.fill: parent
    anchors.margins: -out
    radius: (parent.radius || 10) + out
    color: "transparent"
    border.width: 2.5
    border.color: Theme.accent
    visible: parent.activeFocus
  }
  component Label: Txt {
    color: Theme.textDim
    font.pixelSize: Theme.large
    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
  }
  // A button: tap it, click it, or Tab to it and press Space or Return.
  component Btn: Rectangle {
    id: b
    property string text: ""
    property string icon: ""
    property string tip: ""
    property bool primary: false
    property bool danger: false
    property bool on: false
    signal clicked()
    activeFocusOnTab: true   // hidden or disabled ones are skipped
    implicitWidth: text ? bl.implicitWidth + 44 : 48
    implicitHeight: 48
    width: implicitWidth; height: implicitHeight; radius: 12
    readonly property bool strong: primary || danger || on
    color: !enabled ? Theme.field : (danger ? Theme.red : (primary || on ? Theme.accent : (bh.hovered ? Theme.pressed : Theme.hover)))
    opacity: enabled ? (bh.hovered && strong ? 0.92 : 1) : 0.6
    border.width: strong ? 0 : 1; border.color: Theme.separator
    Keys.onSpacePressed: event => { if (b.enabled) b.clicked(); event.accepted = true }
    Keys.onReturnPressed: event => { if (b.enabled) b.clicked(); event.accepted = true }
    Keys.onEnterPressed: event => { if (b.enabled) b.clicked(); event.accepted = true }
    Ring { out: 4 }
    Txt { id: bl; anchors.centerIn: parent; visible: b.text !== ""; text: b.text; font.pixelSize: Theme.large; font.weight: b.strong ? Font.Bold : Font.Normal; color: b.strong && b.enabled ? "#ffffff" : (b.enabled ? Theme.text : Theme.textFaint) }
    Sym { anchors.centerIn: parent; visible: b.icon !== "" && b.text === ""; name: b.icon || "close"; width: 20; height: 20; color: b.strong ? "#ffffff" : Theme.text }
    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: b.enabled; onTapped: b.clicked() }
    Tip { text: b.tip; delay: 500 }
  }
  // A text field: big enough for a finger, Tab to the next one.
  component Entry: Rectangle {
    id: f
    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property bool secret: false
    property bool eatReturn: false        // Return stays here (else it goes on to the next page)
    signal accepted()
    implicitWidth: 320; implicitHeight: 50; radius: 12
    color: Theme.field
    border.color: input.activeFocus ? Theme.accent : Theme.separator
    border.width: input.activeFocus ? 2 : 1
    TextInput {
      id: input
      anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
      verticalAlignment: TextInput.AlignVCenter
      color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.large + 1
      echoMode: f.secret ? TextInput.Password : TextInput.Normal
      passwordCharacter: "•"
      clip: true
      selectByMouse: true
      activeFocusOnTab: true
      onActiveFocusChanged: if (activeFocus) app.target = input
      // A key from a real keyboard: the on-screen one isn't needed.
      Keys.onPressed: event => { app.touched = false; event.accepted = false }
      Keys.onReturnPressed: event => { f.accepted(); event.accepted = f.eatReturn }
      Keys.onEnterPressed: event => { f.accepted(); event.accepted = f.eatReturn }
      Txt { visible: !input.text && !input.activeFocus; anchors.verticalCenter: parent.verticalCenter; width: parent.width; text: f.placeholder; color: Theme.textFaint; font.pixelSize: Theme.large + 1 }
    }
  }
  // One way to use the disk: a radio card.
  component Choice: Rectangle {
    id: ch
    property bool on: false
    property string title
    property string detail
    signal picked()
    Layout.fillWidth: true
    implicitHeight: chc.implicitHeight + 28; radius: 14
    activeFocusOnTab: true
    Keys.onSpacePressed: ch.picked()
    color: on && enabled ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : (chh.hovered && enabled ? Theme.hover : Theme.field)
    border.width: on && enabled ? 2 : 1; border.color: on && enabled ? Theme.accent : Theme.separator
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Ring {}
    Rectangle {
      x: 18; y: 16; width: 22; height: 22; radius: 11
      color: "transparent"; border.width: 2; border.color: ch.on && ch.enabled ? Theme.accent : Theme.textFaint
      Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: Theme.accent; visible: ch.on && ch.enabled }
    }
    Column {
      id: chc
      x: 54; y: 14; width: parent.width - 72; spacing: 3
      Txt { width: parent.width; text: ch.title; font.pixelSize: Theme.large; font.weight: Font.Bold; opacity: ch.enabled ? 1 : 0.55 }
      Txt { width: parent.width; text: ch.detail; wrapMode: Text.Wrap; color: ch.enabled ? Theme.textDim : "#f07322"; visible: text !== "" }
    }
    HoverHandler { id: chh; cursorShape: ch.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { enabled: ch.enabled; onTapped: ch.picked() }
  }
  component Heading: ColumnLayout {
    property string title
    property string sub
    spacing: 6
    Layout.fillWidth: true
    Layout.bottomMargin: 6
    Txt { text: parent.title; font.pixelSize: 26; font.weight: Font.Bold }
    Txt { text: parent.sub; color: Theme.textDim; font.pixelSize: Theme.large; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap }
  }
  // The current value; tap (or Space) for the whole list over the card.
  component Pick: Rectangle {
    id: pk
    property string title: ""
    property var model: []
    property string current: ""
    signal picked(string v)
    implicitWidth: 340; implicitHeight: 50; radius: 12
    activeFocusOnTab: true
    color: pkh.hovered ? Theme.hover : Theme.field
    border.color: Theme.separator
    Keys.onSpacePressed: sheet.show(pk)
    Keys.onDownPressed: sheet.show(pk)
    Ring {}
    Txt { x: 16; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 52; text: pk.current; font.pixelSize: Theme.large }
    Sym { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } name: "chevron"; rotation: 90; width: 12; height: 12; color: Theme.textDim }
    HoverHandler { id: pkh; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: sheet.show(pk) }
  }
  // An on-screen keyboard that types into the text field in use (no compositor
  // support needed, so it works on the live USB as well).
  component Osk: Rectangle {
    id: kb
    property bool shift: false
    property bool symbols: false
    readonly property var rows: symbols
      ? [["1","2","3","4","5","6","7","8","9","0"], ["@","#","$","_","&","*","-","+","(",")"], ["!","\"","'",":",";","/","?"]]
      : [["q","w","e","r","t","y","u","i","o","p"], ["a","s","d","f","g","h","j","k","l"], ["z","x","c","v","b","n","m"]]
    height: 300
    color: Theme.dark ? Qt.rgba(0.09, 0.09, 0.11, 0.97) : Qt.rgba(0.93, 0.93, 0.95, 0.98)
    radius: 18
    border.color: Theme.separator
    function type(t) {
      const ti = app.target
      if (!ti) return
      if (ti.selectedText) ti.remove(ti.selectionStart, ti.selectionEnd)
      ti.insert(ti.cursorPosition, shift ? t.toUpperCase() : t)
      if (shift) shift = false
    }
    function erase() {
      const ti = app.target
      if (!ti) return
      if (ti.selectedText) ti.remove(ti.selectionStart, ti.selectionEnd)
      else if (ti.cursorPosition > 0) ti.remove(ti.cursorPosition - 1, ti.cursorPosition)
    }
    // Keys never take the focus away from the text field.
    MouseArea { anchors.fill: parent }
    Column {
      anchors { fill: parent; margins: 10 }
      spacing: 8
      readonly property real unit: (width - 9 * 8) / 10
      Repeater {
        model: kb.rows
        delegate: Row {
          required property var modelData
          required property int index
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 8
          // The shift key and backspace sit at the ends of the last row.
          Key { visible: index === 2; w: parent.parent.unit * 1.4; icon: kb.symbols ? "" : "arrow"; label: kb.symbols ? "#+=" : ""; iconRotation: -90; on: kb.shift && !kb.symbols; onHit: if (!kb.symbols) kb.shift = !kb.shift; special: true }
          Repeater {
            model: modelData
            delegate: Key {
              required property string modelData
              w: parent.parent.unit
              label: kb.shift ? modelData.toUpperCase() : modelData
              onHit: kb.type(modelData)
            }
          }
          Key { visible: index === 2; w: parent.parent.unit * 1.4; label: "⌫"; special: true; repeat: true; onHit: kb.erase() }
        }
      }
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        readonly property real unit: parent.unit
        Key { w: parent.unit * 1.4; label: kb.symbols ? "ABC" : "123"; special: true; onHit: kb.symbols = !kb.symbols }
        Key { w: parent.unit; label: kb.symbols ? "=" : ","; onHit: kb.type(label) }
        Key { w: parent.unit * 4; label: "space"; onHit: kb.type(" ") }
        Key { w: parent.unit; label: kb.symbols ? "%" : "."; onHit: kb.type(label) }
        Key { w: parent.unit * 1.2; icon: "keyboard"; special: true; onHit: { app.touched = false; app.oskPinned = false } }
        Key {
          w: parent.unit * 1.4; special: true; on: true
          label: app.target && app.page === 1 ? "Join" : "Next"
          onHit: {
            const ti = app.target
            if (!ti) return
            // Like Tab: the next field; at the last one, like Return.
            const nx = ti.nextItemInFocusChain(true)
            if (nx && nx instanceof TextInput && nx !== ti) nx.forceActiveFocus()
            else if (app.page === 1) { const f = ti.parent; if (f && f.accepted) f.accepted() }
            else { app.touched = false; app.oskPinned = false; app.go() }
          }
        }
      }
    }
  }
  component Key: Rectangle {
    id: k
    property real w: 60
    property string label: ""
    property string icon: ""
    property real iconRotation: 0
    property bool special: false
    property bool on: false
    property bool repeat: false
    signal hit()
    width: w; height: 58; radius: 10
    color: kt.pressed || on ? Theme.accent : (special ? (Theme.dark ? "#2c2c31" : "#d6d6dc") : (Theme.dark ? "#3a3a40" : "#ffffff"))
    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: Qt.rgba(0, 0, 0, 0.25); radius: 10; z: -1; anchors.bottomMargin: -1 }
    Txt { anchors.centerIn: parent; visible: k.icon === ""; text: k.label; font.pixelSize: k.label.length > 1 ? Theme.fontSize : 20; color: kt.pressed || k.on ? "#ffffff" : Theme.text }
    Sym { anchors.centerIn: parent; visible: k.icon !== ""; name: k.icon || "arrow"; rotation: k.iconRotation; width: 20; height: 20; color: kt.pressed || k.on ? "#ffffff" : Theme.text }
    TapHandler { id: kt; onTapped: k.hit(); onLongPressed: if (k.repeat) rep.start(); onPressedChanged: if (!pressed) rep.stop() }
    Timer { id: rep; interval: 70; repeat: true; onTriggered: k.hit() }
  }
}
