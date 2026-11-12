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
  // Keys only while the desktop menu is open (Escape closes it).
  WlrLayershell.keyboardFocus: menuOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
  color: "black"

  property string file: Theme.wallpaper
  property bool flip: false
  property bool splashNotified: false

  function notifySplash() {
    if (splashNotified) return
    splashNotified = true
    Quickshell.execDetached(["hyprctl", "memora-splash", "done", (w.screen && w.screen.name) ? w.screen.name : ""])
  }

  Item {
    id: pics
    anchors.fill: parent
    Image {
      id: a
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize: Qt.size(w.width, w.height)
      opacity: w.flip ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
      onStatusChanged: if (status === Image.Ready || status === Image.Error) w.notifySplash()
    }
    Image {
      id: b
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize: Qt.size(w.width, w.height)
      opacity: w.flip ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
    }
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

  // Widgets, and the desktop's own menu (right-click on empty space).
  Widgets { id: widgets; visible: w.modelData === Quickshell.screens[0]; backdrop: frosted }
  property point menuAt: Qt.point(-1, -1)
  readonly property bool menuOpen: menuAt.x >= 0
  function closeMenu() { menuAt = Qt.point(-1, -1) }
  TapHandler {
    acceptedButtons: Qt.RightButton
    // One menu at a time: the bar's and the Dock's close first.
    onTapped: ev => { if (Shell.open !== "") Shell.close(); else Shell.closing(); w.menuAt = ev.position }
  }
  TapHandler { onTapped: w.closeMenu() }
  // It goes away as soon as the desktop loses the focus: a click anywhere else
  // (a window, the bar, the Dock), a window taking the focus, another desktop,
  // another menu, Escape.
  OutsideClick { when: w.menuOpen; windows: [w]; onOutside: w.closeMenu() }
  Connections { target: Shell; function onClosing() { w.closeMenu() } function onOpenChanged() { if (Shell.open !== "") w.closeMenu() } }
  Item { focus: w.menuOpen; Keys.onEscapePressed: w.closeMenu() }
  MenuPanel {
    id: deskMenu
    visible: w.menuOpen
    // Glass over the frosted picture, like the widgets (the compositor has nothing to frost here).
    solid: false
    backdrop: frosted
    backdropRect: Qt.rect(deskMenu.x, deskMenu.y, deskMenu.width, deskMenu.height)
    x: Math.min(w.menuAt.x, w.width - width - 8); y: Math.min(w.menuAt.y, w.height - height - 8)
    width: implicitWidth; height: implicitHeight
    items: [
      { text: "Edit Widgets…", action: () => widgets.editing = true },
      { separator: true },
      { text: "Change Wallpaper…", action: () => Apps.run("memora-settings wallpaper") },
      { text: "Display Settings…", action: () => Apps.run("memora-settings displays") }
    ]
    onPicked: item => { const run = item.action; w.closeMenu(); Qt.callLater(run) }
  }

  Component.onCompleted: {
    a.source = "file://" + file
    if (a.status === Image.Ready || a.status === Image.Error) notifySplash()
  }
  onFileChanged: {
    if (flip) a.source = "file://" + file; else b.source = "file://" + file
    flip = !flip
  }
}
