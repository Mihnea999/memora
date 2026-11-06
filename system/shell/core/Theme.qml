pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Memora design tokens: one place for colour, type, shape and motion.
// The mode (light/dark) comes from ~/.config/memora/theme, written by memora-theme.
Singleton {
  id: t

  property string mode: Quickshell.env("MEMORA_MODE") || "dark"
  readonly property bool dark: mode !== "light"

  property FileView modeFile: FileView {
    path: Quickshell.env("HOME") + "/.config/memora/theme"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: t.mode = (text() || "dark").trim()
  }

  readonly property string share: Quickshell.env("MEMORA_PATH") || "/usr/share/memora"

  // Type
  readonly property string font: "JetBrainsMono Nerd Font"
  readonly property real fontSize: 13
  readonly property real small: 11.5
  readonly property real large: 15

  // Ink
  readonly property color text: dark ? "#f5f5f7" : "#1c1c1e"
  readonly property color textDim: dark ? Qt.rgba(0.96, 0.96, 0.97, 0.58) : Qt.rgba(0.11, 0.11, 0.12, 0.55)
  readonly property color textFaint: dark ? Qt.rgba(0.96, 0.96, 0.97, 0.32) : Qt.rgba(0.11, 0.11, 0.12, 0.3)
  readonly property color accent: dark ? "#3d8bff" : "#2b74f0"
  readonly property color accentText: "#ffffff"
  readonly property color red: "#ff5f57"
  readonly property color yellow: "#febc2e"
  readonly property color green: "#28c840"

  // Glass: translucent fill (Hyprland blurs what is behind), a bright inner edge and a dark outer edge.
  readonly property color glass: dark ? Qt.rgba(0.10, 0.10, 0.12, 0.34) : Qt.rgba(0.98, 0.98, 0.99, 0.34)
  readonly property color glassStrong: dark ? Qt.rgba(0.12, 0.12, 0.14, 0.46) : Qt.rgba(0.99, 0.99, 1.0, 0.50)
  readonly property color glassSolid: dark ? "#232326" : "#f5f5f7"
  readonly property color bar: dark ? Qt.rgba(0.06, 0.06, 0.08, 0.28) : Qt.rgba(1, 1, 1, 0.30)
  readonly property color edge: dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(1, 1, 1, 0.75)
  readonly property color outline: dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(0, 0, 0, 0.10)
  readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
  readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.11)
  readonly property color separator: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.09)
  readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
  readonly property color tile: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55)
  readonly property color tileOn: accent
  readonly property color shadow: Qt.rgba(0, 0, 0, dark ? 0.45 : 0.18)

  // Shape
  readonly property real radiusSmall: 7
  readonly property real radius: 12
  readonly property real radiusLarge: 18
  readonly property real radiusPanel: 22

  // Motion: quick and calm, nothing bouncy except the dock.
  readonly property int fast: 120
  readonly property int normal: 220
  readonly property int slow: 340
  readonly property int easing: Easing.OutCubic
  readonly property int easingEmph: Easing.OutQuint
}
