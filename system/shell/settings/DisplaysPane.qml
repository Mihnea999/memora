import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Displays"
  readonly property var mons: Hyprland.monitors.values
  property bool nightShift: false
  Kit.Cmd { id: ns; onDone: out => p.nightShift = out.trim() !== "" }
  Component.onCompleted: { Hyprland.refreshMonitors(); ns.exec(["pgrep", "-x", "hyprsunset"]) }

  // Scales are kept in ~/.config/hypr/monitors.lua, which the session loads.
  FileView { id: monFile; path: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"; printErrors: false }
  function setScale(m, s) {
    const lines = p.mons.map(x => 'hl.monitor({ output = "' + x.name + '", mode = "preferred", position = "auto", scale = ' + (x === m ? s : x.scale) + ' })')
    monFile.setText("-- Written by System Settings > Displays.\n" + lines.join("\n") + "\n")
    Quickshell.execDetached(["hyprctl", "eval", lines.find(l => l.indexOf('"' + m.name + '"') > 0)])
  }

  Repeater {
    model: p.mons
    delegate: Kit.Group {
      required property var modelData
      header: modelData.description || modelData.name
      Kit.Row { label: "Resolution"; Kit.Value { text: modelData.width + " × " + modelData.height + (modelData.lastIpcObject ? " at " + Math.round(modelData.lastIpcObject.refreshRate || 60) + " Hz" : "") } }
      Kit.Row {
        label: "Scale"; detail: "Larger text and controls, or more space"; last: true
        Kit.Choice {
          value: Math.round(modelData.scale * 100) / 100
          options: [{ text: "100%", value: 1 }, { text: "125%", value: 1.25 }, { text: "150%", value: 1.5 }, { text: "175%", value: 1.75 }, { text: "200%", value: 2 }]
          onPicked: v => p.setScale(modelData, v)
        }
      }
    }
  }
  Kit.Group {
    footer: "Warmer colours after dark are easier on the eyes."
    Kit.Row {
      label: "Night Shift"; badge: "moon"; badgeColor: "#ff9f2e"; last: true
      Kit.Switch {
        checked: p.nightShift
        onToggled: on => { p.nightShift = on; Quickshell.execDetached(on ? ["bash", "-c", "setsid hyprsunset -t 4200 >/dev/null 2>&1 &"] : ["pkill", "-x", "hyprsunset"]) }
      }
    }
  }
}
