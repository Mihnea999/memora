import QtQuick
import Quickshell
import Quickshell.Io

// Keyboard and pointer preferences: ~/.config/memora/input.json, mirrored into
// input.lua for Hyprland, which is reloaded after each change.
QtObject {
  id: ip
  property var data: ({})
  property FileView json: FileView {
    path: Quickshell.env("HOME") + "/.config/memora/input.json"
    printErrors: false
    onLoaded: { try { ip.data = JSON.parse(text()) } catch (e) { ip.data = {} } }
  }
  property FileView lua: FileView { path: Quickshell.env("HOME") + "/.config/memora/input.lua"; printErrors: false }
  function get(k, d) { return data[k] === undefined ? d : data[k] }
  function set(k, v) {
    const d = Object.assign({}, data); d[k] = v; data = d
    json.setText(JSON.stringify(d, null, 2) + "\n")
    const body = Object.keys(d).map(key => "  " + key + " = " + (typeof d[key] === "string" ? '"' + d[key] + '"' : d[key])).join(",\n")
    lua.setText("-- Written by System Settings.\nreturn {\n" + body + "\n}\n")
    reload.restart()
  }
  property Timer reload: Timer { interval: 300; onTriggered: Quickshell.execDetached(["hyprctl", "reload", "config-only"]) }
}
