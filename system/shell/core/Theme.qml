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
  // The desktop picture for a mode (yours if you picked one, else the chosen set).
  readonly property var wallpaperSets: ["candy", "ember", "tide", "horizon", "dunes", "silk"]
  function wallpaperFor(m) { return Prefs.wallpaper !== "" ? Prefs.wallpaper : share + "/wallpapers/" + (wallpaperSets.indexOf(Prefs.wallpaperSet) >= 0 ? Prefs.wallpaperSet : "candy") + "-" + m + ".jpg" }
  readonly property string wallpaper: wallpaperFor(mode)

  // Type
  // The system face: yours from System Settings > Appearance (Inter unless changed).
  // mono is for code and anything that must line up in columns.
  readonly property string font: Prefs.font || "Inter"
  readonly property string mono: "JetBrainsMono Nerd Font"
  readonly property real fontSize: 13
  readonly property real small: 11.5
  readonly property real large: 15

  // Ink
  readonly property color text: dark ? "#f5f5f7" : "#1c1c1e"
  readonly property color textDim: dark ? Qt.rgba(0.96, 0.96, 0.97, 0.58) : Qt.rgba(0.11, 0.11, 0.12, 0.55)
  readonly property color textFaint: dark ? Qt.rgba(0.96, 0.96, 0.97, 0.32) : Qt.rgba(0.11, 0.11, 0.12, 0.3)
  // Accent (System Settings > Appearance): [dark, light]
  readonly property var accents: ({
    blue: ["#3d8bff", "#2b74f0"], purple: ["#a565f5", "#8a4ee0"], pink: ["#f2609e", "#e0457f"],
    red: ["#ff5e57", "#e8433c"], orange: ["#ff8a3d", "#f07322"], green: ["#34c759", "#22a447"],
    graphite: ["#9a9aa2", "#7c7c84"] })
  readonly property color accent: (accents[Prefs.accent] || accents.blue)[dark ? 0 : 1]
  readonly property color accentText: "#ffffff"
  readonly property color red: "#ff5f57"
  readonly property color yellow: "#febc2e"
  readonly property color green: "#28c840"

  // Glass: a thin tint over what is behind it (Hyprland frosts that lightly and,
  // in the dark look, dims it: default/hypr/look.lua) and light caught on its
  // rounded rim (ui/glass.frag). No shadow. Clear is close to see-through, as
  // on a Mac; Tinted is calmer; Transparency scales both; Reduce Transparency makes it solid.
  // The fills stay above the alpha under which Hyprland leaves a layer unblurred
  // (ignore_alpha in default/hypr/rules.lua: 0.13 light, 0.16 dark).
  readonly property bool tinted: Prefs.glassStyle === "tinted"
  function see(a) {
    if (Prefs.reduceTransparency) return 0.97
    const base = tinted ? a + (0.9 - a) * 0.45 : a
    return base + (0.96 - base) * (1 - Prefs.transparency)
  }
  readonly property color glass: dark ? Qt.rgba(0.08, 0.08, 0.10, see(0.22)) : Qt.rgba(1, 1, 1, see(0.17))
  // Strong glass carries text (menus, panels). The light one is thicker than the
  // dark one: dark ink needs a bright sheet under it over a dark or vivid picture
  // (what is behind dark glass is dimmed by the compositor instead).
  readonly property color glassStrong: dark ? Qt.rgba(0.10, 0.10, 0.12, see(0.20)) : Qt.rgba(1, 1, 1, see(0.24))
  // Menus and sheets drawn inside a window: nothing frosts what is behind them
  // there (the compositor only blurs behind whole windows and layers), so they
  // are close to solid, or the window's text would show through theirs.
  readonly property color popover: dark ? Qt.rgba(0.15, 0.15, 0.17, 0.97) : Qt.rgba(0.975, 0.975, 0.985, 0.98)
  readonly property color glassSolid: dark ? "#232326" : "#f5f5f7"
  // App windows: only a hint of glass, so text in them always reads well over
  // whatever is behind (Frost blurs the rest).
  readonly property color window: dark ? Qt.rgba(0.105, 0.105, 0.12, see(0.9)) : Qt.rgba(0.975, 0.975, 0.98, see(0.92))
  readonly property color sidebar: dark ? Qt.rgba(1, 1, 1, 0.045) : Qt.rgba(0, 0, 0, 0.035)
  readonly property color bar: Prefs.menuBarTransparent && !Prefs.reduceTransparency ? Qt.rgba(0, 0, 0, 0) : (dark ? Qt.rgba(0.06, 0.06, 0.08, see(0.24)) : Qt.rgba(1, 1, 1, see(0.22)))
  readonly property real shine: Prefs.reduceTransparency ? 0.3 : Prefs.shine
  readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
  readonly property color pressed: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.11)
  readonly property color separator: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.09)
  readonly property color field: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
  readonly property color tile: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.55)
  readonly property color tileOn: accent

  // Shape
  readonly property real radiusSmall: 7
  readonly property real radius: 12
  readonly property real radiusLarge: 18
  readonly property real radiusPanel: 22

  // Motion: quick and calm, nothing bouncy except the dock.
  readonly property int fast: Prefs.motion(140)
  readonly property int normal: Prefs.motion(260)
  readonly property int slow: Prefs.motion(420)
  readonly property int easing: Easing.OutCubic
  readonly property int easingEmph: Easing.OutQuint
}
