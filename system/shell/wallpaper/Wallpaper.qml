import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.ui
import qs.widgets

// Desktop picture. Cross-fades when the appearance changes.
PanelWindow {
  id: w
  required property var modelData
  screen: modelData
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Background
  WlrLayershell.namespace: "memora-wallpaper"
  // Keys while the desktop menu is open (Escape closes it) or an icon is selected / being styled.
  readonly property bool wantKeys: menuOpen || (icons && icons.visible && (icons.selection.length > 0 || icons.typing))
  WlrLayershell.keyboardFocus: wantKeys ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  color: "black"

  property string file: Theme.wallpaper
  property bool flip: false

  Item {
    id: pics
    anchors.fill: parent
    Image { id: a; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(w.width, w.height); opacity: w.flip ? 0 : 1; Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } } }
    Image { id: b; anchors.fill: parent; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(w.width, w.height); opacity: w.flip ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } } }
  }
  // The same picture, frosted: the glass of the widgets shows its part of this
  // (nothing is behind the desktop for the compositor to blur).
  MultiEffect {
    id: frosted
    anchors.fill: parent
    visible: false
    source: pics
    blurEnabled: !Prefs.reduceTransparency
    blur: Prefs.blur * 0.8; blurMax: 48
    saturation: Prefs.vibrancy * 0.5
    brightness: Theme.dark ? -0.04 : 0.0
  }

  // Icons on the primary desktop (~/Desktop), widgets, and the desktop menu.
  DesktopIcons {
    id: icons
    visible: Quickshell.screens.length > 0 && w.modelData === Quickshell.screens[0]
    screen: w.screen
    widgets: widgets
    backdrop: frosted
  }
  Widgets { id: widgets; visible: Quickshell.screens.length > 0 && w.modelData === Quickshell.screens[0]; backdrop: frosted }

  property point menuAt: Qt.point(-1, -1)
  readonly property bool menuOpen: menuAt.x >= 0
  function closeMenu() { menuAt = Qt.point(-1, -1) }

  property var menuList: [
    { text: "Edit Widgets…", action: () => widgets.editing = true },
    { separator: true },
    { text: "Change Wallpaper…", action: () => Apps.run("memora-settings wallpaper") },
    { text: "Display Settings…", action: () => Apps.run("memora-settings displays") }
  ]
  function menuItems(x, y) {
    if (icons && icons.visible) {
      const im = icons.menuAt(x, y)
      if (im) return im
      return icons.deskItems(x, y).concat([
        { text: "Edit Widgets…", action: () => widgets.editing = true },
        { separator: true },
        { text: "Change Wallpaper…", action: () => Apps.run("memora-settings wallpaper") },
        { text: "Display Settings…", action: () => Apps.run("memora-settings displays") }
      ])
    }
    return [
      { text: "Edit Widgets…", action: () => widgets.editing = true },
      { separator: true },
      { text: "Change Wallpaper…", action: () => Apps.run("memora-settings wallpaper") },
      { text: "Display Settings…", action: () => Apps.run("memora-settings displays") }
    ]
  }

  TapHandler {
    acceptedButtons: Qt.RightButton
    // One menu at a time: the bar's and the Dock's close first.
    onTapped: ev => {
      if (Shell.open !== "") Shell.close(); else Shell.closing()
      if (icons && icons.styling !== "") icons.styling = ""
      w.menuList = w.menuItems(ev.position.x, ev.position.y)
      w.menuAt = ev.position
    }
  }
  TapHandler {
    id: deskTap
    onTapped: ev => {
      w.closeMenu()
      if (icons && icons.visible) {
        if (icons.styling !== "") icons.styling = ""
        icons.tapped(ev.position.x, ev.position.y, deskTap.point.modifiers, 1)
      }
    }
    onDoubleTapped: ev => {
      w.closeMenu()
      if (icons && icons.visible) {
        icons.tapped(ev.position.x, ev.position.y, deskTap.point.modifiers, 2)
      }
    }
  }
  // It goes away as soon as the desktop loses the focus: a click anywhere else
  // (a window, the bar, the Dock), a window taking the focus, another desktop,
  // another menu, Escape.
  OutsideClick { when: w.menuOpen; windows: [w]; onOutside: w.closeMenu() }
  OutsideClick { when: icons && icons.visible && icons.styling !== ""; windows: [w]; onOutside: icons.styling = "" }
  OutsideClick { when: icons && icons.visible && icons.renaming !== ""; windows: [w]; onOutside: icons.commitRename() }
  Connections {
    target: Shell
    function onClosing() { w.closeMenu(); if (icons) icons.styling = "" }
    function onOpenChanged() { if (Shell.open !== "") { w.closeMenu(); if (icons) icons.styling = "" } }
  }
  Item { focus: w.menuOpen; Keys.onEscapePressed: w.closeMenu() }
  MenuPanel {
    id: deskMenu
    visible: w.menuOpen
    // Glass over the frosted picture, like the widgets (the compositor has nothing to frost here).
    solid: false
    backdrop: frosted
    backdropRect: Qt.rect(deskMenu.x, deskMenu.y, deskMenu.width, deskMenu.height)
    x: Math.max(8, Math.min(w.menuAt.x, w.width - width - 8)); y: Math.max(8, Math.min(w.menuAt.y, w.height - height - 8))
    width: implicitWidth; height: implicitHeight
    items: w.menuList
    onPicked: item => { const run = item.action; w.closeMenu(); if (run) Qt.callLater(run) }
  }

  Component.onCompleted: a.source = "file://" + file
  onFileChanged: {
    if (flip) a.source = "file://" + file; else b.source = "file://" + file
    flip = !flip
  }
}
