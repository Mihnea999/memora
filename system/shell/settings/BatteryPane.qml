import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Battery"
  readonly property var dev: UPower.displayDevice
  readonly property bool has: dev && dev.isLaptopBattery
  property string profile: ""
  Kit.Cmd { id: get; onDone: out => p.profile = out.trim() }
  Component.onCompleted: get.exec(["powerprofilesctl", "get"])

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
}
