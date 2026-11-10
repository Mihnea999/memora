import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import qs.core
import qs.ui

// The menus under the status items, as on a Mac: Wi-Fi, Bluetooth, Battery and
// Sound each open a small menu with a switch, the networks/devices/outputs and
// a way into System Settings. Shell.open === "status", Shell.menu is the kind.
PopupWindow {
  id: sm
  required property var bar
  readonly property bool shown: Shell.open === "status" && Shell.menuScreen === bar.modelData.name
  readonly property string kind: shown ? Shell.menu : ""
  readonly property int menuWidth: 300

  visible: shown
  anchor.window: bar
  anchor.rect.x: Math.max(6, Math.min(bar.width - menuWidth - 6, Shell.menuX))
  anchor.rect.y: bar.height + 2
  implicitWidth: menuWidth + 40
  implicitHeight: card.implicitHeight + 40
  color: "transparent"

  onKindChanged: {
    if (kind === "wifi") scan.refresh(true)
    if (kind === "battery") profileGet.running = true
    if (kind === "bluetooth" && Sys.adapter && Sys.adapter.enabled) Sys.adapter.discovering = true
    else if (Sys.adapter) Sys.adapter.discovering = false
  }

  OutsideClick {
    when: sm.shown
    windows: [sm, sm.bar]
    onOutside: if (Shell.open === "status") Shell.close()
  }

  function settings(pane) { Shell.close(); Quickshell.execDetached(["memora-settings", pane]) }

  Glass {
    id: card
    x: 0; y: 0
    width: sm.menuWidth
    implicitHeight: body.implicitHeight + 12
    height: implicitHeight
    radius: 14
    fill: Theme.glassStrong
    opacity: sm.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }

    Loader {
      id: body
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
      sourceComponent: ({ wifi: wifiMenu, bluetooth: btMenu, battery: batteryMenu, sound: soundMenu })[sm.kind] || null
    }
  }

  // ---------------------------------------------------------------- Wi-Fi
  QtObject {
    id: scan
    property var nets: []
    property var known: []
    property bool busy: false
    property string joining: ""
    function refresh(rescan) {
      busy = true
      listProc.command = ["bash", "-c", "nmcli -t -f NAME,TYPE con show 2>/dev/null | grep ':802-11-wireless$' | sed 's/:802-11-wireless$//'; echo '--'; " +
        "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list" + (rescan ? " --rescan auto" : "") + " 2>/dev/null"]
      listProc.running = true
    }
  }
  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.split("--\n")
        scan.known = (parts[0] || "").split("\n").filter(l => l)
        scan.nets = (parts[1] || "").split("\n").filter(l => l).map(l => {
          const f = l.replace(/\\:/g, "\u0001").split(":").map(x => x.replace(/\u0001/g, ":"))
          return { inUse: f[0] === "*", ssid: f[1], signal: parseInt(f[2]) || 0, secure: !!f[3] && f[3] !== "--" }
        }).filter(n => n.ssid).filter((n, i, a) => a.findIndex(m => m.ssid === n.ssid) === i)
        scan.busy = false
      }
    }
  }
  Process {
    id: joinProc
    onExited: { scan.joining = ""; Net.refresh(); scan.refresh(false) }
  }
  function join(n) {
    if (n.inUse) return
    if (n.secure && scan.known.indexOf(n.ssid) < 0) {
      // A password is needed: System Settings asks for it (Wi-Fi pane).
      Quickshell.execDetached(["bash", "-c", "mkdir -p ~/.cache/memora && printf '%s' \"$1\" > ~/.cache/memora/wifi-join", "_", n.ssid])
      settings("wifi")
      return
    }
    scan.joining = n.ssid
    joinProc.command = scan.known.indexOf(n.ssid) >= 0 ? ["nmcli", "con", "up", "id", n.ssid] : ["nmcli", "dev", "wifi", "connect", n.ssid]
    joinProc.running = true
  }

  Component {
    id: wifiMenu
    ColumnLayout {
      spacing: 0
      Header { title: "Wi-Fi"; checked: Net.wifiEnabled; onToggled: { Sys.setWifi(!Net.wifiEnabled); refreshLater.restart() } }
      Timer { id: refreshLater; interval: 2500; onTriggered: { Net.refresh(); scan.refresh(true) } }
      Item {
        visible: Net.online && !Net.wifi
        Layout.fillWidth: true; implicitHeight: 40
        Entry { anchors.fill: parent; sym: "globe"; title: "Ethernet"; sub: "Connected"; on: true }
      }
      Section { text: "Known Network"; visible: Net.wifiEnabled && sm.knownNets.length > 0 }
      Repeater {
        model: Net.wifiEnabled ? sm.knownNets : []
        delegate: NetEntry {}
      }
      Section { text: "Other Networks"; visible: Net.wifiEnabled && sm.otherNets.length > 0 }
      Repeater {
        model: Net.wifiEnabled ? sm.otherNets : []
        delegate: NetEntry {}
      }
      Note { visible: Net.wifiEnabled && scan.nets.length === 0; text: scan.busy ? "Looking for networks…" : "No networks found" }
      Sep {}
      Action { text: "Wi-Fi Settings…"; onClicked: sm.settings("wifi") }
    }
  }
  readonly property var knownNets: scan.nets.filter(n => n.inUse || scan.known.indexOf(n.ssid) >= 0)
  readonly property var otherNets: scan.nets.filter(n => !n.inUse && scan.known.indexOf(n.ssid) < 0).slice(0, 8)
  component NetEntry: Entry {
    required property var modelData
    Layout.fillWidth: true
    implicitHeight: 40
    sym: "wifi"; level: modelData.signal / 80
    on: modelData.inUse
    title: modelData.ssid
    sub: scan.joining === modelData.ssid ? "Joining…" : ""
    lock: modelData.secure
    onClicked: sm.join(modelData)
  }

  // ------------------------------------------------------------ Bluetooth
  readonly property var btDevices: Sys.adapter ? Sys.adapter.devices.values.filter(d => d.paired || d.connected)
    .sort((a, b) => (b.connected - a.connected) || String(a.name).localeCompare(String(b.name))) : []
  readonly property var btNearby: Sys.adapter ? Sys.adapter.devices.values.filter(d => !d.paired && !d.connected && d.name).slice(0, 5) : []
  Component {
    id: btMenu
    ColumnLayout {
      spacing: 0
      Header {
        title: "Bluetooth"; checked: Sys.btOn; enabled: Sys.btAvailable
        onToggled: { Sys.toggleBt(); if (Sys.adapter && Sys.adapter.enabled) Sys.adapter.discovering = true }
      }
      Note { visible: !Sys.btAvailable; text: "No Bluetooth adapter found" }
      Section { text: "Devices"; visible: Sys.btOn && sm.btDevices.length > 0 }
      Repeater {
        model: Sys.btOn ? sm.btDevices : []
        delegate: Entry {
          required property var modelData
          Layout.fillWidth: true; implicitHeight: 40
          sym: "bluetooth"; on: modelData.connected
          title: modelData.name || modelData.address
          sub: modelData.state === BluetoothDeviceState.Connecting ? "Connecting…" : (modelData.connected && modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : "")
          onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
        }
      }
      Section { text: "Nearby"; visible: Sys.btOn && sm.btNearby.length > 0 }
      Repeater {
        model: Sys.btOn ? sm.btNearby : []
        delegate: Entry {
          required property var modelData
          Layout.fillWidth: true; implicitHeight: 40
          sym: "bluetooth"; title: modelData.name
          sub: modelData.pairing ? "Pairing…" : ""
          onClicked: { modelData.trusted = true; modelData.pair() }
        }
      }
      Note { visible: Sys.btOn && sm.btDevices.length + sm.btNearby.length === 0; text: "Looking for devices…" }
      Sep {}
      Action { text: "Bluetooth Settings…"; onClicked: sm.settings("bluetooth") }
    }
  }

  // -------------------------------------------------------------- Battery
  property string profile: ""
  Process { id: profileGet; command: ["powerprofilesctl", "get"]; stdout: StdioCollector { onStreamFinished: sm.profile = text.trim() } }
  function hm(s) { if (!s) return ""; const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60); return (h ? h + ":" + (m < 10 ? "0" : "") + m : m + " min") }
  Component {
    id: batteryMenu
    ColumnLayout {
      spacing: 0
      readonly property var dev: UPower.displayDevice
      readonly property bool charging: dev && dev.state === UPowerDeviceState.Charging
      readonly property bool full: dev && dev.state === UPowerDeviceState.FullyCharged
      Item {
        Layout.fillWidth: true; implicitHeight: 34
        Txt { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "Battery"; font.weight: Font.Bold }
        Txt { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: dev ? Math.round(dev.percentage * 100) + "%" : ""; color: Theme.textDim }
      }
      Note {
        text: "Power Source: " + (UPower.onBattery ? "Battery" : "Power Adapter") +
          (charging && dev.timeToFull ? "\n" + sm.hm(dev.timeToFull) + " until full" : "") +
          (full ? "\nFully charged" : "") +
          (UPower.onBattery && dev && dev.timeToEmpty ? "\n" + sm.hm(dev.timeToEmpty) + " remaining" : "")
      }
      Sep { visible: sm.profile !== "" }
      Section { text: "Energy Mode"; visible: sm.profile !== "" }
      Repeater {
        model: sm.profile !== "" ? [{ t: "Low Power", v: "power-saver" }, { t: "Automatic", v: "balanced" }, { t: "High Performance", v: "performance" }] : []
        delegate: Action {
          required property var modelData
          text: modelData.t; checkable: true; checked: sm.profile === modelData.v
          onClicked: { sm.profile = modelData.v; Quickshell.execDetached(["powerprofilesctl", "set", modelData.v]) }
        }
      }
      Sep {}
      Action { text: "Show Percentage"; checkable: true; checked: Prefs.batteryPercent; onClicked: Prefs.set("batteryPercent", !Prefs.batteryPercent) }
      Action { text: "Battery Settings…"; checkable: true; onClicked: sm.settings("battery") }
    }
  }

  // ---------------------------------------------------------------- Sound
  readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
  // Apps playing sound right now (their playback streams), for the mixer.
  // (not filtered on .audio: a node only has it once tracked, which is below)
  readonly property var streams: Pipewire.nodes.values.filter(n => n.type === PwNodeType.AudioOutStream)
  PwObjectTracker { objects: sm.sinks.concat(sm.streams) }
  function appName(n) {
    const p = n.properties || {}
    return p["application.name"] || n.description || n.nickname || n.name || "App"
  }
  function appIcon(n) {
    const p = n.properties || {}
    const id = p["application.icon-name"] || p["application.process.binary"] || p["application.id"] || ""
    return id ? Quickshell.iconPath(id.toLowerCase(), true) : ""
  }
  // Hear the alert volume once its slider stops.
  Timer { id: alertPreview; interval: 350; onTriggered: Quickshell.execDetached(["memora-sound", "preview", Prefs.alertSound]) }
  Component {
    id: soundMenu
    ColumnLayout {
      spacing: 0
      Item {
        Layout.fillWidth: true; implicitHeight: 30
        Txt { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "Sound"; font.weight: Font.Bold }
      }
      Item {
        Layout.fillWidth: true; implicitHeight: 38
        Slider {
          anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
          implicitHeight: 26
          sym: Sys.muted || Sys.volume === 0 ? "sound-off" : "sound"
          value: Sys.volume; muted: Sys.muted
          symToggles: true; onSymClicked: Sys.toggleMute()
          onMoved: v => Sys.changeVolume(v)
        }
      }
      Section { text: "Alerts & System Sounds" }
      Item {
        Layout.fillWidth: true; implicitHeight: 38
        Slider {
          anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
          implicitHeight: 26
          sym: Prefs.alertVolume > 0 ? "bell" : "sound-off"
          value: Prefs.alertVolume
          onMoved: v => { Prefs.set("alertVolume", Math.round(v * 100) / 100); alertPreview.restart() }
        }
      }
      // The mixer: each app that is playing, with its own volume.
      Section { text: "Apps"; visible: sm.streams.length > 0 }
      Repeater {
        model: sm.streams
        delegate: Item {
          required property var modelData
          Layout.fillWidth: true; implicitHeight: 54
          Image {
            id: appIcon
            x: 10; y: 4; width: 16; height: 16
            source: sm.appIcon(modelData); sourceSize: Qt.size(32, 32)
            visible: status === Image.Ready
          }
          Txt {
            anchors { left: appIcon.visible ? appIcon.right : parent.left; leftMargin: appIcon.visible ? 6 : 10; right: parent.right; rightMargin: 10 }
            y: 4; text: sm.appName(modelData); font.pixelSize: Theme.small; elide: Text.ElideRight
          }
          Slider {
            anchors { left: parent.left; right: parent.right; leftMargin: 10; rightMargin: 10; bottom: parent.bottom; bottomMargin: 2 }
            implicitHeight: 26
            readonly property var a: modelData.audio
            sym: !a || a.muted || a.volume === 0 ? "sound-off" : "sound"
            value: a ? Math.min(1, a.volume) : 0; muted: !!a && a.muted
            symToggles: true; onSymClicked: if (a) a.muted = !a.muted
            onMoved: v => { if (a) { a.muted = false; a.volume = v } }
          }
        }
      }
      Sep {}
      Section { text: "Output" }
      Repeater {
        model: sm.sinks
        delegate: Entry {
          required property var modelData
          Layout.fillWidth: true; implicitHeight: 40
          sym: "sound"; on: Pipewire.defaultAudioSink === modelData
          title: modelData.description || modelData.nickname || modelData.name
          onClicked: Pipewire.preferredDefaultAudioSink = modelData
        }
      }
      Note { visible: sm.sinks.length === 0; text: "No output devices" }
      Sep {}
      Action { text: "Sound Settings…"; onClicked: sm.settings("sound") }
    }
  }

  // ------------------------------------------------------------ the parts
  // The menu's title with a switch on the right.
  component Header: Item {
    id: h
    property string title
    property bool checked
    signal toggled()
    Layout.fillWidth: true
    implicitHeight: 34
    Txt { x: 10; anchors.verticalCenter: parent.verticalCenter; text: h.title; font.weight: Font.Bold }
    Rectangle {
      id: sw
      anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
      width: 34; height: 20; radius: 10
      opacity: h.enabled ? 1 : 0.4
      color: h.checked ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14))
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      Rectangle {
        width: 16; height: 16; radius: 8; y: 2
        x: h.checked ? sw.width - width - 2 : 2
        color: "white"
        Behavior on x { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
      }
      TapHandler { enabled: h.enabled; onTapped: h.toggled() }
    }
  }

  // A small grey heading.
  component Section: Txt {
    Layout.fillWidth: true
    Layout.topMargin: 6
    Layout.bottomMargin: 2
    leftPadding: 10
    font.pixelSize: Theme.small
    font.weight: Font.Bold
    color: Theme.textDim
  }

  // Grey text (status, nothing found).
  component Note: Txt {
    Layout.fillWidth: true
    leftPadding: 10; rightPadding: 10; topPadding: 4; bottomPadding: 6
    wrapMode: Text.Wrap
    font.pixelSize: Theme.small
    color: Theme.textDim
  }

  component Sep: Rectangle {
    Layout.fillWidth: true
    Layout.leftMargin: 10; Layout.rightMargin: 10
    Layout.topMargin: 5; Layout.bottomMargin: 5
    implicitHeight: 1
    color: Theme.separator
  }

  // A network, device or output: a round symbol (blue when it's the one in use), its name and a note.
  component Entry: Item {
    id: e
    property string sym: ""
    property real level: 1
    property bool on: false
    property string title
    property string sub: ""
    property bool lock: false
    signal clicked()
    Rectangle { anchors.fill: parent; radius: 8; color: eh.hovered ? Theme.hover : "transparent" }
    Rectangle {
      id: dot
      x: 8; anchors.verticalCenter: parent.verticalCenter
      width: 28; height: 28; radius: 14
      color: e.on ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08))
      Sym { anchors.centerIn: parent; name: e.sym; level: e.level; width: 15; height: 15; color: e.on ? "white" : Theme.text }
    }
    ColumnLayout {
      anchors { left: dot.right; leftMargin: 10; right: lockSym.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
      spacing: 0
      Txt { Layout.fillWidth: true; text: e.title; elide: Text.ElideRight }
      Txt { Layout.fillWidth: true; visible: e.sub !== ""; text: e.sub; font.pixelSize: Theme.small; color: Theme.textDim; elide: Text.ElideRight }
    }
    Sym {
      id: lockSym
      anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
      visible: e.lock; name: "lock"; width: 11; height: 11; color: Theme.textDim
    }
    HoverHandler { id: eh }
    TapHandler { onTapped: e.clicked() }
  }

  // A plain menu line (settings, a mode with a check mark).
  component Action: Item {
    id: a
    property string text
    property bool checked: false
    property bool checkable: false      // keeps room for the check mark, so names line up
    signal clicked()
    Layout.fillWidth: true
    implicitHeight: 28
    Rectangle { anchors.fill: parent; radius: 6; color: ah.hovered ? Theme.accent : "transparent" }
    Sym {
      visible: a.checked
      x: 10; anchors.verticalCenter: parent.verticalCenter
      name: "check"; width: 11; height: 11
      color: ah.hovered ? Theme.accentText : Theme.text
    }
    Txt {
      x: a.checkable || a.checked ? 28 : 10; anchors.verticalCenter: parent.verticalCenter
      text: a.text
      color: ah.hovered ? Theme.accentText : Theme.text
    }
    HoverHandler { id: ah }
    TapHandler { onTapped: a.clicked() }
  }
}
