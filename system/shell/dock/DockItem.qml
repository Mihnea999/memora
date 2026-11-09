import QtQuick
import Quickshell
import qs.core
import qs.ui

// One Dock icon: magnifies with the pointer, shows its name above, a dot when
// running, bounces while its app starts.
Item {
  id: it
  property var dockRoot
  property var entry
  readonly property string kind: entry ? entry.kind : "app"
  readonly property string appId: entry ? entry.id : ""
  readonly property var wins: kind === "app" ? Apps.windowsOf(appId) : []
  readonly property bool running: wins.length > 0 || (appId === "memora-launchpad" && Shell.open === "launchpad")

  // Centre in the dock plate's coordinates (where the pointer is tracked).
  readonly property real centerX: (parent && parent.parent ? (dockRoot.vertical ? parent.parent.y : parent.parent.x) : 0) + dockRoot.rowX + width / 2
  readonly property real dist: Math.abs(dockRoot.mouseX - centerX)
  readonly property real grow: dockRoot.magnifying && dist < dockRoot.reach ? (Math.cos(dist / dockRoot.reach * Math.PI) + 1) / 2 : 0
  readonly property real size: dockRoot.base + (dockRoot.peak - dockRoot.base) * grow

  width: size
  height: size
  Behavior on width { NumberAnimation { duration: Prefs.motion(110); easing.type: Easing.OutQuad } }
  Behavior on height { NumberAnimation { duration: Prefs.motion(110); easing.type: Easing.OutQuad } }

  readonly property string label: kind === "trash" ? "Trash" : kind === "folder" ? "Downloads"
    : kind === "window" ? (entry.win.title || Apps.nameFor(appId)) : appId === "memora-launchpad" ? "Apps" : Apps.nameFor(appId)

  // Drag to rearrange; drag up out of the Dock to remove (apps only).
  readonly property bool draggable: kind === "app" && appId !== ""
  property point drag: Qt.point(0, 0)
  readonly property bool dragging: dragger.active
  readonly property bool leaving: dragging && dockRoot.outward(drag) > it.height * 1.3 && Apps.pinned.indexOf(appId) >= 0
  z: dragging ? 10 : 0
  DragHandler {
    id: dragger
    enabled: it.draggable
    target: null
    onTranslationChanged: it.drag = Qt.point(translation.x, translation.y)
    onActiveChanged: {
      if (active) { it.dockRoot.draggingId = it.appId; return }
      it.dockRoot.dropped(it, it.drag)
      it.drag = Qt.point(0, 0)
      it.dockRoot.draggingId = ""
    }
  }

  Item {
    id: bouncer
    width: parent.width; height: parent.height
    transform: Translate {
      x: it.dragging ? it.drag.x : 0
      y: it.dragging ? it.drag.y : 0
      Behavior on x { enabled: !it.dragging; NumberAnimation { duration: Theme.normal; easing.type: Theme.easingEmph } }
      Behavior on y { enabled: !it.dragging; NumberAnimation { duration: Theme.normal; easing.type: Theme.easingEmph } }
    }
    opacity: it.leaving ? 0.45 : 1
    scale: it.dragging ? 1.08 : 1
    Behavior on scale { NumberAnimation { duration: Theme.fast } }
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }

    // "Remove" sign while it is being pulled out.
    Rectangle {
      visible: it.leaving
      z: 2
      anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 6 }
      width: rt.implicitWidth + 16; height: 22; radius: 11
      color: Theme.glassSolid
      border.color: Theme.separator
      Txt { id: rt; anchors.centerIn: parent; text: "Remove"; font.pixelSize: Theme.small }
    }

    AppIcon {
      id: icon
      anchors.fill: parent
      anchors.margins: parent.width * 0.02
      appId: it.kind === "app" || it.kind === "window" ? it.appId : ""
      iconName: it.kind === "trash" ? (it.dockRoot.trashFull ? "user-trash-full" : "user-trash")
        : it.kind === "folder" ? "folder-download" : ""
      opacity: tap.pressed ? 0.7 : 1
    }
    // Minimized windows wear a small app badge, like a thumbnail would.
    Rectangle {
      visible: it.kind === "window"
      anchors { right: parent.right; bottom: parent.bottom }
      width: parent.width * 0.36; height: width; radius: width * 0.25
      color: Theme.glassSolid
      border.color: Theme.separator
      Image { anchors.fill: parent; anchors.margins: 2; source: Quickshell.iconPath("view-restore-symbolic", "window-restore"); sourceSize: Qt.size(48, 48) }
    }
  }

  // Running dot, on the screen-edge side of the icon.
  Rectangle {
    visible: it.running && it.kind === "app" && Prefs.dockDots
    width: 4; height: 4; radius: 2
    color: Theme.text
    opacity: 0.75
    x: it.dockRoot.pos === "bottom" ? (parent.width - width) / 2 : (it.dockRoot.pos === "left" ? -6 : parent.width + 2)
    y: it.dockRoot.pos === "bottom" ? parent.height + 2 : (parent.height - height) / 2
  }

  // Name above the icon.
  Glass {
    id: tip
    visible: opacity > 0
    opacity: hover.hovered && it.dockRoot.menuFor === null && !it.dragging ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    radius: 8
    fill: Theme.glassStrong
    shadowSize: 12
    width: tipText.implicitWidth + 22
    height: 26
    // Above the icon, or beside it on a Dock at the side.
    x: it.dockRoot.pos === "bottom" ? (parent.width - width) / 2 : (it.dockRoot.pos === "left" ? parent.width + 12 : -width - 12)
    y: it.dockRoot.pos === "bottom" ? -height - 12 : (parent.height - height) / 2
    Txt { id: tipText; anchors.centerIn: parent; text: it.label; font.pixelSize: Theme.small + 0.5 }
  }

  HoverHandler { id: hover }
  TapHandler {
    id: tap
    acceptedButtons: Qt.LeftButton
    onTapped: it.activate()
  }
  TapHandler {
    acceptedButtons: Qt.RightButton
    onTapped: it.openMenu()
  }
  // Touch: a long press is the right click.
  TapHandler { acceptedDevices: PointerDevice.TouchScreen; onLongPressed: it.openMenu() }
  function openMenu() { it.dockRoot.menuX = it.dockRoot.hitX + it.centerX; it.dockRoot.menuFor = it.entry }

  function activate() {
    if (kind === "trash") return Apps.run("nautilus --new-window trash:///")
    if (kind === "folder") return Apps.run("nautilus --new-window ~/Downloads")
    if (kind === "window") return Apps.restore(entry.win)
    if (Prefs.dockBounce && Prefs.animations && !running && appId !== "memora-launchpad") bounce.restart()
    Apps.activate(appId)
  }

  // Launch feedback: two soft hops, stopping as soon as a window appears.
  SequentialAnimation {
    id: bounce
    loops: 2
    NumberAnimation { target: bouncer; property: it.dockRoot.vertical ? "x" : "y"; to: (it.dockRoot.pos === "left" ? 1 : -1) * it.height * 0.32; duration: Prefs.motion(260); easing.type: Easing.OutQuad }
    NumberAnimation { target: bouncer; property: it.dockRoot.vertical ? "x" : "y"; to: 0; duration: Prefs.motion(260); easing.type: Easing.InQuad }
  }
  onRunningChanged: if (running && bounce.running) { bounce.stop(); bouncer.y = 0; bouncer.x = 0 }
}
