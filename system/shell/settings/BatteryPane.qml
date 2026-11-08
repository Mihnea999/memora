import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Battery & Energy"
  readonly property var dev: UPower.displayDevice
  readonly property bool has: dev && dev.isLaptopBattery
  property string profile: ""
  Kit.Cmd { id: get; onDone: out => p.profile = out.trim() }
  Component.onCompleted: get.exec(["powerprofilesctl", "get"])

  // Keep Awake, read from the shared preferences (the shell holds the inhibitor).
  property real now: Date.now()
  Timer { interval: 10000; repeat: true; running: true; onTriggered: p.now = Date.now() }
  property int lastPick: 60
  readonly property int awake: Prefs.awakeUntil === -1 ? -1 : (Prefs.awakeUntil > p.now ? p.lastPick : 0)
  function setAwake(m) { p.now = Date.now(); if (m > 0) p.lastPick = m; Prefs.set("awakeUntil", m === 0 ? 0 : (m < 0 ? -1 : p.now + m * 60000)) }

  function hm(s) { if (!s) return ""; const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60); return (h ? h + " h " : "") + m + " min" }

  Kit.Group {
    Kit.Row {
      label: p.has ? Math.round(p.dev.percentage * 100) + "%" : "No battery"
      badge: "battery"; badgeColor: "#34c759"
      detail: !p.has ? "This computer runs on mains power" : (p.dev.state === UPowerDeviceState.Charging ? "Charging · full in " + p.hm(p.dev.timeToFull) : (p.dev.state === UPowerDeviceState.FullyCharged ? "Fully charged" : p.hm(p.dev.timeToEmpty) + " remaining"))
      last: true
      Sym { visible: p.has; name: "battery"; level: p.has ? p.dev.percentage : 0; width: 34; height: 34 }
    }
  }
  Kit.Group {
    header: "Energy mode"
    visible: p.profile !== ""
    footer: "Low Power uses less energy; High Performance lets the computer run faster and warmer."
    Kit.Row {
      label: "Mode"; last: true
      Kit.Choice {
        value: p.profile
        options: [{ text: "Low Power", value: "power-saver" }, { text: "Automatic", value: "balanced" }, { text: "High Performance", value: "performance" }]
        onPicked: v => { p.profile = v; Quickshell.execDetached(["powerprofilesctl", "set", v]) }
      }
    }
  }

  Kit.Group {
    header: "Keep Awake"
    footer: Prefs.awakeUntil > p.now ? "On until " + Qt.formatTime(new Date(Prefs.awakeUntil), Prefs.clock24 ? "HH:mm" : "h:mm AP") + ". The screen stays on, doesn't lock and the computer doesn't sleep. Also in Control Center (the cup)."
      : "The screen stays on, doesn't lock and the computer doesn't sleep. Also in Control Center; a cup in the menu bar shows it's on."
    Kit.Row {
      label: "Keep Awake"; badge: "cup"; badgeColor: "#c47a35"
      Kit.Choice {
        value: p.awake
        options: [{ text: "Off", value: 0 }, { text: "1 hour", value: 60 }, { text: "2 hours", value: 120 }, { text: "8 hours", value: 480 }, { text: "Always", value: -1 }]
        onPicked: v => p.setAwake(v)
      }
    }
    Kit.Row {
      label: "While an app is full screen"
      detail: "Films, games and presentations keep the screen on"
      last: !p.has
      Kit.Switch { checked: Prefs.awakeFullscreen; onToggled: on => Prefs.set("awakeFullscreen", on) }
    }
    Kit.Row {
      visible: p.has
      label: "Also with the lid closed"
      detail: "While Keep Awake is on, closing the lid doesn't make it sleep (for an external display)"
      last: true
      Kit.Switch { checked: Prefs.awakeLid; onToggled: on => Prefs.set("awakeLid", on) }
    }
  }

  Kit.Group {
    header: "When you're away"
    footer: "Times count from the last time you used the keyboard or mouse. The screen locks after the time set in Privacy & Security (now " + (Prefs.lockAfter ? Prefs.lockAfter + " min" : "never") + ")."
    Kit.Row {
      label: "Turn the screen off after"
      Kit.Choice {
        value: Prefs.displayOffAfter
        options: [{ text: "2 min", value: 2 }, { text: "5 min", value: 5 }, { text: "10 min", value: 10 }, { text: "30 min", value: 30 }, { text: "1 hour", value: 60 }, { text: "Never", value: 0 }]
        onPicked: v => Prefs.set("displayOffAfter", v)
      }
    }
    Kit.Row {
      label: "Sleep after"
      last: !p.has
      Kit.Choice {
        value: Prefs.sleepAfter
        options: [{ text: "15 min", value: 15 }, { text: "30 min", value: 30 }, { text: "1 hour", value: 60 }, { text: "3 hours", value: 180 }, { text: "Never", value: 0 }]
        onPicked: v => Prefs.set("sleepAfter", v)
      }
    }
    Kit.Row {
      visible: p.has
      label: "Sleep when plugged in"
      detail: "Off: only sleeps by itself on battery"
      last: true
      Kit.Switch { checked: Prefs.sleepOnPower; onToggled: on => Prefs.set("sleepOnPower", on) }
    }
  }
}
