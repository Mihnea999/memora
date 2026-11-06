import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Date & Time"
  property bool ntp: true
  property var zones: []
  property string filter: ""
  SystemClock { id: clock; precision: SystemClock.Seconds }
  Kit.Cmd { id: info; onDone: out => p.ntp = out.trim() === "yes" }
  Kit.Cmd { id: list; onDone: out => p.zones = out.split("\n").filter(l => l) }
  Kit.Cmd { id: setter; onDone: { Host.refresh(); info.exec(["timedatectl", "show", "-p", "NTP", "--value"]) } }
  Component.onCompleted: { info.exec(["timedatectl", "show", "-p", "NTP", "--value"]); list.exec(["timedatectl", "list-timezones"]) }

  Kit.Group {
    Kit.Row { label: "Date and time"; Kit.Value { text: Qt.formatDateTime(clock.date, Prefs.clock24 ? "dddd d MMMM yyyy, HH:mm:ss" : "dddd d MMMM yyyy, h:mm:ss AP") } }
    Kit.Row { label: "Set time automatically"; Kit.Switch { checked: p.ntp; onToggled: on => setter.exec(["timedatectl", "set-ntp", on ? "true" : "false"]) } }
    Kit.Row { label: "24-hour time"; last: true; Kit.Switch { checked: Prefs.clock24; onToggled: on => Prefs.set("clock24", on) } }
  }
  Kit.Group {
    header: "Time zone"
    footer: "Changing the time zone asks for your password."
    Kit.Row { label: "Current"; Kit.Value { text: Host.timezone } }
    Kit.Row { label: "Find a city or region"; Kit.Field { placeholder: "e.g. Bucharest"; onTextChanged: p.filter = text } }
    Repeater {
      model: p.filter.length < 2 ? [] : p.zones.filter(z => z.toLowerCase().indexOf(p.filter.toLowerCase()) >= 0).slice(0, 8)
      delegate: Kit.Row {
        required property string modelData
        label: modelData.replace(/_/g, " ")
        clickable: true
        onClicked: setter.exec(["timedatectl", "set-timezone", modelData])
        Sym { visible: Host.timezone === modelData; name: "check"; width: 14; height: 14; color: Theme.accent }
      }
    }
  }
}
