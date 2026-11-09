import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Minimize: a picture of the window flies into the Dock, narrowing as it goes;
// restoring plays it backwards. The real window is moved at once; this is only
// the picture.
Scope {
  id: genie

  Connections {
    target: Apps
    function onMinimizing(addr, win, rect) { genie.play(addr, win, rect, false) }
    function onRestoring(addr, win, rect) { genie.play(addr, win, rect, true) }
  }

  function play(addr, win, rect, back) {
    // One genie at a time: one still running (Show All restores many at once)
    // finishes now, so no window is left behind hidden.
    if (view.addr !== "" && view.addr !== addr) { const prev = view.addr, pb = view.backwards; view.addr = ""; done(prev, pb) }
    if (!Prefs.animations || !win || !win.wayland) { done(addr, back); return }
    view.source = null
    view.appId = Apps.classOf(win)
    view.backwards = back
    view.from = rect
    view.screenName = win.monitor ? win.monitor.name : ""
    view.addr = addr
    // A fresh source makes the view take a new picture.
    Qt.callLater(() => { view.source = win.wayland })
  }
  function done(addr, back) { if (back) Apps.finishRestore(addr); else Apps.finishMinimize(addr) }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      id: wl
      required property var modelData
      screen: modelData
      readonly property bool here: view.screenName === "" ? modelData === Quickshell.screens[0] : view.screenName === modelData.name
      // Always mapped (and click-through), so the picture shows the moment it starts.
      visible: here
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "memora-genie"
      mask: Region {}

      Item {
        id: shot
        visible: false
        readonly property bool hasContent: pic.hasContent
        property real t: 0     // 0 at the window, 1 in the Dock
        readonly property rect a: Qt.rect(view.from.x - wl.modelData.x, view.from.y - wl.modelData.y, view.from.width, view.from.height)
        readonly property point b: Qt.point(Apps.dockTarget.x - wl.modelData.x, Apps.dockTarget.y - wl.modelData.y)
        // Shrinks to an icon, and narrows faster than it shortens.
        readonly property real sx: 1 - (1 - 48 / Math.max(1, a.width)) * Math.min(1, t * 1.25)
        readonly property real sy: 1 - (1 - 48 / Math.max(1, a.height)) * t
        // The centre glides to the Dock: sideways evenly, downwards faster and faster.
        readonly property real cx: a.x + a.width / 2 + (b.x - a.x - a.width / 2) * t
        readonly property real cy: a.y + a.height / 2 + (b.y - a.y - a.height / 2) * t * t
        x: cx - width / 2
        y: cy - height / 2
        width: a.width * sx
        height: a.height * sy
        opacity: 1 - Math.max(0, t - 0.75) * 4

        ScreencopyView {
          id: pic
          anchors.fill: parent
          visible: !view.useCard
          live: false
          captureSource: wl.here && !view.useCard ? view.source : null
        }
        Glass {
          anchors.fill: parent
          visible: view.useCard
          radius: Math.min(width, height) * 0.12
          fill: Theme.glassStrong
          shadowSize: 20
          AppIcon { anchors.centerIn: parent; width: Math.min(96, parent.width * 0.5, parent.height * 0.5); height: width; appId: view.appId }
        }
        Connections { target: view; function onKickChanged() { if (wl.here) go.restart() } }

        // Start once the picture has arrived.
        Timer {
          running: wl.here && view.addr !== "" && !view.started && !!view.source
          interval: 30; repeat: true
          onTriggered: if (shot.hasContent) { stop(); go.restart() }
        }
        SequentialAnimation {
          id: go
          ScriptAction { script: { shot.t = view.backwards ? 1 : 0; shot.visible = true; view.started = true; if (!view.backwards) genie.done(view.addr, false) } }
          NumberAnimation { target: shot; property: "t"; to: view.backwards ? 0 : 1; duration: Prefs.motion(view.backwards ? 380 : 460); easing.type: view.backwards ? Easing.OutCubic : Easing.InOutCubic }
          ScriptAction { script: { const a = view.addr, back = view.backwards; shot.visible = false; view.addr = ""; view.source = null; if (back) genie.done(a, true) } }
        }
      }
    }
  }

  // What is being animated.
  QtObject {
    id: view
    property string addr: ""
    property var source: null
    property rect from
    property bool backwards: false
    property string screenName: ""
    property bool started: false
    property bool useCard: false
    property int kick: 0
    property string appId: ""
    onAddrChanged: if (addr) { started = false; useCard = false }
  }
  // No picture (no GPU buffers, or the window is gone): fly a glass card with
  // the app's icon instead.
  Timer {
    running: view.addr !== "" && !view.started
    interval: 160
    onTriggered: if (view.addr !== "" && !view.started) { view.useCard = true; view.kick++ }
  }
}
