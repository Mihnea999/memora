import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Control Center: connectivity, focus, appearance, display, sound and media,
// hanging from the menu bar's right side.
PanelWindow {
  id: cc
  required property var modelData
  screen: modelData
  readonly property bool open: Shell.open === "control" && (Shell.menuScreen === modelData.name || !Shell.menuScreen)

  visible: open || anim.running
  anchors { top: true; right: true }
  margins { top: 6; right: 8 }
  implicitWidth: 340
  implicitHeight: body.implicitHeight + 40
  exclusiveZone: 0
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "memora-panel"
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  property real shown: open ? 1 : 0
  Behavior on shown { NumberAnimation { id: anim; duration: Theme.normal; easing.type: Theme.easing } }
  onOpenChanged: if (open) Net.refresh()

  // Nearby Share receiving: everyone, trusted devices only, or off (~/.config/memora/share.json).
  property string shareMode: "everyone"
  readonly property bool receiving: shareMode !== "off"
  FileView {
    path: Quickshell.env("HOME") + "/.config/memora/share.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { const r = JSON.parse(text()).receive; cc.shareMode = r === false || r === "off" ? "off" : r === "trusted" ? "trusted" : "everyone" } catch (e) {} }
  }

  OutsideClick {
    when: cc.open
    windows: [cc]
    onOutside: if (cc.open) Shell.close()
  }

  Item {
    anchors.fill: parent
    anchors.margins: 10
    opacity: cc.shown
    transform: Translate { y: -8 * (1 - cc.shown) }
    Keys.onEscapePressed: Shell.close()

    ColumnLayout {
      id: body
      width: parent.width
      spacing: 10

      RowLayout {
        spacing: 10
        Layout.fillWidth: true

        // Wi-Fi, Bluetooth, Nearby Share, Focus
        Module {
          Layout.preferredWidth: 160
          Layout.preferredHeight: 200
          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4
            Toggle {
              visible: Host.hasWifi
              sym: Net.wifiEnabled ? "wifi" : "wifi-off"; title: "Wi-Fi"
              sub: !Net.wifiEnabled ? "Off" : (Net.online ? Net.label : "Not connected")
              on: Net.wifiEnabled
              onToggled: Sys.setWifi(!Net.wifiEnabled)
              onOpened: Shell.openStatus("wifi")
            }
            // No Wi-Fi in this computer (a desktop on a cable): its network instead.
            Toggle {
              visible: !Host.hasWifi
              sym: "globe"; title: "Network"
              sub: Net.online ? "Connected" : "Not connected"
              on: Net.online
              onToggled: { Shell.close(); Quickshell.execDetached(["memora-settings", "network"]) }
              onOpened: { Shell.close(); Quickshell.execDetached(["memora-settings", "network"]) }
            }
            Toggle {
              sym: "bluetooth"; title: "Bluetooth"
              sub: !Sys.btAvailable ? "Unavailable" : (Sys.btOn ? (Sys.btConnected.length ? Sys.btConnected[0].name : "On") : "Off")
              on: Sys.btOn
              enabled: Sys.btAvailable
              onToggled: Sys.toggleBt()
              onOpened: Shell.openStatus("bluetooth")
            }
            // Receiving files from phones and computers nearby (bin/memora-share).
            Toggle {
              sym: "share"; title: "Nearby Share"
              sub: cc.shareMode === "everyone" ? "Everyone" : cc.shareMode === "trusted" ? "Trusted Devices" : "Receiving off"
              on: cc.receiving
              onToggled: Quickshell.execDetached(["memora-share", "receive", cc.receiving ? "off" : "on"])
              // The arrow side: who can send you files, in Settings.
              onOpened: { Shell.close(); Quickshell.execDetached(["memora-settings", "nearby"]) }
            }
            Toggle {
              sym: "moon"; title: "Focus"
              sub: Shell.focusMode ? "Do Not Disturb" : "Off"
              on: Shell.focusMode
              onToggled: Shell.focusMode = !Shell.focusMode
              onOpened: Shell.focusMode = !Shell.focusMode
            }
          }
        }

        ColumnLayout {
          spacing: 10
          Layout.fillWidth: true
          Module {
            Layout.fillWidth: true
            Layout.preferredHeight: 119
            Tile {
              anchors.fill: parent
              sym: Theme.dark ? "moon" : "sun"
              title: Theme.dark ? "Dark" : "Light"
              sub: "Appearance"
              onClicked: Apps.run("memora-theme next")
            }
          }
          RowLayout {
            spacing: 10
            Module {
              Layout.preferredWidth: 71; Layout.preferredHeight: 71
              Square { anchors.fill: parent; sym: "lock"; label: "Lock"; onClicked: { Shell.close(); Apps.run("memora-lock") } }
            }
            Module {
              Layout.preferredWidth: 71; Layout.preferredHeight: 71
              Square { anchors.fill: parent; sym: "ai"; label: "Ask AI"; onClicked: { Shell.close(); Apps.run("memora-ai window") } }
            }
          }
        }
      }

      // Keep Awake: the screen stays on and doesn't lock.
      Module {
        Layout.fillWidth: true
        Layout.preferredHeight: 52
        Rectangle {
          id: awakeDot
          x: 11; width: 30; height: 30; radius: 15
          anchors.verticalCenter: parent.verticalCenter
          color: Shell.keepAwake ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
          Behavior on color { ColorAnimation { duration: Theme.fast } }
          Sym { anchors.centerIn: parent; name: "cup"; width: 16; height: 16; color: Shell.keepAwake ? "#ffffff" : Theme.text }
          TapHandler { onTapped: Shell.setAwake(Shell.keepAwake ? 0 : -1) }
        }
        Column {
          anchors { left: awakeDot.right; leftMargin: 9; verticalCenter: parent.verticalCenter }
          Txt { text: "Keep Awake"; font.weight: Font.Bold; font.pixelSize: Theme.small + 0.5 }
          Txt { text: Shell.awakeLabel; color: Theme.textDim; font.pixelSize: Theme.small - 0.5 }
          TapHandler { onTapped: Shell.setAwake(Shell.keepAwake ? 0 : -1) }
        }
        Row {
          anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
          spacing: 4
          Repeater {
            // For a while, or until turned off.
            model: [[60, "1 h"], [120, "2 h"], [480, "8 h"], [-1, "∞"]]
            delegate: Rectangle {
              required property var modelData
              readonly property bool here: Shell.keepAwake && (modelData[0] === -1 ? Prefs.awakeUntil === -1
                : Prefs.awakeUntil > 0 && Math.abs(Prefs.awakeUntil - Shell.awakeSetAt - modelData[0] * 60000) < 1000)
              width: 34; height: 24; radius: 12
              color: here ? Theme.accent : (ah.hovered ? Theme.hover : (Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.05)))
              Behavior on color { ColorAnimation { duration: Theme.fast } }
              Txt { anchors.centerIn: parent; text: modelData[1]; font.pixelSize: Theme.small - 0.5; font.weight: Font.Medium; color: parent.here ? "#ffffff" : Theme.text }
              HoverHandler { id: ah }
              TapHandler { onTapped: Shell.setAwake(parent.here ? 0 : modelData[0]) }
              Tip { text: modelData[0] === -1 ? "Until you turn it off" : "For " + modelData[1].replace(" h", modelData[0] === 60 ? " hour" : " hours") }
            }
          }
        }
      }

      Module {
        visible: Sys.hasBacklight
        Layout.fillWidth: true
        Layout.preferredHeight: 70
        Txt { text: "Display"; font.weight: Font.Bold; x: 12; y: 10 }
        Slider { x: 12; y: 32; width: parent.width - 24; sym: "sun"; value: Sys.brightness; onMoved: v => Sys.setBrightness(v) }
      }

      Module {
        Layout.fillWidth: true
        Layout.preferredHeight: 70
        Txt {
          text: "Sound"; font.weight: Font.Bold; x: 12; y: 10
          TapHandler { onTapped: Shell.openStatus("sound") }   // outputs, like the menu bar's Sound menu
        }
        Slider { x: 12; y: 32; width: parent.width - 24; sym: Sys.muted || Sys.volume === 0 ? "sound-off" : "sound"; value: Sys.volume; muted: Sys.muted; symToggles: true; onSymClicked: Sys.toggleMute(); onMoved: v => Sys.changeVolume(v) }
      }

      Module {
        visible: !!Sys.player
        Layout.fillWidth: true
        Layout.preferredHeight: 70
        Rectangle {
          id: art
          x: 10; y: 10; width: 50; height: 50; radius: 10
          color: Theme.tile
          clip: true
          Image { anchors.fill: parent; source: Sys.player ? (Sys.player.trackArtUrl || "") : ""; fillMode: Image.PreserveAspectCrop }
        }
        Column {
          anchors { left: art.right; leftMargin: 10; right: controls.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
          Txt { width: parent.width; text: Sys.player ? (Sys.player.trackTitle || Sys.player.identity) : ""; font.weight: Font.Medium }
          Txt { width: parent.width; text: Sys.player ? (Sys.player.trackArtist || "") : ""; color: Theme.textDim; font.pixelSize: Theme.small }
        }
        Row {
          id: controls
          anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
          spacing: 14
          Sym { name: Sys.player && Sys.player.isPlaying ? "pause" : "play"; width: 18; height: 18; TapHandler { onTapped: Sys.player.togglePlaying() } }
          Sym { name: "next"; width: 18; height: 18; TapHandler { onTapped: Sys.player.next() } }
        }
      }

      Module {
        Layout.fillWidth: true
        Layout.preferredHeight: 44
        RowLayout {
          anchors.fill: parent
          anchors.margins: 6
          spacing: 6
          Repeater {
            model: [["gear", "Settings", "memora-settings"], ["sleep", "Sleep", "systemctl suspend"], ["restart", "Restart", "memora-power restart"], ["power", "Shut Down", "memora-power shutdown"]]
            delegate: Item {
              required property var modelData
              Layout.fillWidth: true; Layout.fillHeight: true
              Rectangle { anchors.fill: parent; radius: 9; color: bh.hovered ? Theme.hover : "transparent" }
              Sym { anchors.centerIn: parent; name: modelData[0]; width: 16; height: 16 }
              HoverHandler { id: bh }
              TapHandler { onTapped: { Shell.close(); Apps.run(modelData[2]) } }
              Tip { text: ({ Settings: "System Settings", Sleep: "Sleep: pause and save power", Restart: "Restart the computer", "Shut Down": "Shut down the computer" })[modelData[1]] }
            }
          }
        }
      }
    }
  }

  // ---- pieces -----------------------------------------------------------------
  component Module: Glass {
    id: mod
    radius: 18
    fill: Theme.glassStrong
    shadowSize: 18
    property real enter: cc.open ? 1 : 0
    Behavior on enter { SequentialAnimation {
      // Top to bottom: the delay follows how far down the module sits.
      PauseAnimation { duration: cc.open ? Prefs.motion(Math.round((mod.y + (mod.parent ? mod.parent.y : 0)) / 3)) : 0 }
      NumberAnimation { duration: Prefs.motion(cc.open ? 380 : 140); easing.type: cc.open ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.1 }
    } }
    opacity: enter
    transform: Translate { y: -14 * (1 - mod.enter) }
  }

  component Toggle: Item {
    id: tg
    property string sym; property string title; property string sub; property bool on
    signal toggled(); signal opened()
    Layout.fillWidth: true
    Layout.fillHeight: true
    opacity: enabled ? 1 : 0.45
    Rectangle {
      id: dot
      width: 30; height: 30; radius: 15
      anchors.verticalCenter: parent.verticalCenter
      color: tg.on ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08))
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      Sym { anchors.centerIn: parent; name: tg.sym; width: 15; height: 15; color: tg.on ? "#ffffff" : Theme.text }
      TapHandler { onTapped: tg.toggled() }
    }
    Column {
      anchors { left: dot.right; leftMargin: 9; right: parent.right; verticalCenter: parent.verticalCenter }
      Txt { width: parent.width; text: tg.title; font.weight: Font.Bold; font.pixelSize: Theme.small + 0.5 }
      Txt { width: parent.width; text: tg.sub; color: Theme.textDim; font.pixelSize: Theme.small - 0.5 }
      TapHandler { onTapped: tg.opened() }
    }
  }

  component Tile: Item {
    id: tl
    property string sym; property string title; property string sub
    signal clicked()
    Rectangle {
      id: tdot
      x: 10; width: 30; height: 30; radius: 15
      anchors.verticalCenter: parent.verticalCenter
      color: Theme.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)
      Sym { anchors.centerIn: parent; name: tl.sym; width: 15; height: 15 }
    }
    Column {
      anchors { left: tdot.right; leftMargin: 9; verticalCenter: parent.verticalCenter }
      Txt { text: tl.title; font.weight: Font.Bold; font.pixelSize: Theme.small + 0.5 }
      Txt { text: tl.sub; color: Theme.textDim; font.pixelSize: Theme.small - 0.5 }
    }
    TapHandler { onTapped: tl.clicked() }
  }

  component Square: Item {
    id: sq
    property string sym; property string label
    signal clicked()
    Column {
      anchors.centerIn: parent
      spacing: 5
      Sym { anchors.horizontalCenter: parent.horizontalCenter; name: sq.sym; width: 18; height: 18 }
      Txt { anchors.horizontalCenter: parent.horizontalCenter; text: sq.label; font.pixelSize: Theme.small - 1; color: Theme.textDim }
    }
    TapHandler { onTapped: sq.clicked() }
  }
}
