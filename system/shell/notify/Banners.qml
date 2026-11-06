import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.ui

// Notification banners, top right, sliding in from the edge.
PanelWindow {
  id: win
  required property var modelData
  screen: modelData
  visible: Notifs.popups.length > 0 && screen === Quickshell.screens[0]
  anchors { top: true; right: true }
  margins { top: 6; right: 4 }
  implicitWidth: 400
  implicitHeight: Math.max(1, stack.implicitHeight + 30)
  exclusiveZone: 0
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "memora-notifications"

  Column {
    id: stack
    x: 20; y: 8
    spacing: 10
    Repeater {
      model: Notifs.popups
      delegate: NotificationCard {
        id: b
        required property var modelData
        notif: modelData
        onDone: Notifs.hide(modelData)
        property real slide: 1
        transform: Translate { x: 420 * b.slide }
        Component.onCompleted: slide = 0
        Behavior on slide { NumberAnimation { duration: Theme.slow; easing.type: Theme.easingEmph } }
        Timer {
          interval: b.notif.expireTimeout > 0 ? b.notif.expireTimeout : 5500
          running: !b.hoverActive && b.notif.urgency !== 2
          onTriggered: Notifs.hide(b.notif)
        }
        readonly property bool hoverActive: hh.hovered
        HoverHandler { id: hh }
      }
    }
  }
}
