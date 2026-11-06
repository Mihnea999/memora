import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui
import qs.notify

// Opened from the clock: this month's calendar and the notifications you missed.
PanelWindow {
  id: nc
  required property var modelData
  screen: modelData
  readonly property bool open: Shell.open === "calendar" && (Shell.menuScreen === modelData.name || !Shell.menuScreen)

  visible: open || anim.running
  anchors { top: true; right: true; bottom: true }
  margins { top: 6; right: 8; bottom: 90 }
  implicitWidth: 400
  exclusiveZone: 0
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "memora-panel"
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  property real shown: open ? 1 : 0
  Behavior on shown { NumberAnimation { id: anim; duration: Theme.normal; easing.type: Theme.easing } }

  HyprlandFocusGrab { active: nc.open; windows: [nc]; onCleared: if (nc.open) Shell.close() }

  SystemClock { id: clock; precision: SystemClock.Minutes }
  property date month: new Date()
  onOpenChanged: if (open) month = new Date()

  ColumnLayout {
    x: 20; y: 0
    width: 360
    spacing: 10
    opacity: nc.shown
    transform: Translate { x: 30 * (1 - nc.shown) }

    // Calendar
    Glass {
      Layout.fillWidth: true
      Layout.preferredHeight: cal.implicitHeight + 28
      radius: 18
      fill: Theme.glassStrong
      shadowSize: 20
      ColumnLayout {
        id: cal
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 8
        RowLayout {
          Layout.fillWidth: true
          Txt { text: Qt.formatDate(nc.month, "MMMM yyyy"); font.weight: Font.Bold; font.pixelSize: Theme.large; Layout.fillWidth: true }
          Sym { name: "chevron"; width: 14; height: 14; rotation: 180; TapHandler { onTapped: nc.month = new Date(nc.month.getFullYear(), nc.month.getMonth() - 1, 1) } }
          Item { width: 8 }
          Sym { name: "chevron"; width: 14; height: 14; TapHandler { onTapped: nc.month = new Date(nc.month.getFullYear(), nc.month.getMonth() + 1, 1) } }
        }
        Grid {
          columns: 7
          Layout.fillWidth: true
          readonly property real cell: (cal.width) / 7
          Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            delegate: Txt { required property string modelData; width: parent.cell; height: 22; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.textDim; font.pixelSize: Theme.small - 1 }
          }
          Repeater {
            model: 42
            delegate: Item {
              required property int index
              readonly property var first: new Date(nc.month.getFullYear(), nc.month.getMonth(), 1)
              readonly property int lead: (first.getDay() + 6) % 7
              readonly property var day: new Date(nc.month.getFullYear(), nc.month.getMonth(), index - lead + 1)
              readonly property bool inMonth: day.getMonth() === nc.month.getMonth()
              readonly property bool today: day.toDateString() === clock.date.toDateString()
              width: parent.cell; height: 30
              Rectangle { anchors.centerIn: parent; width: 26; height: 26; radius: 13; color: Theme.accent; visible: today }
              Txt { anchors.centerIn: parent; text: day.getDate(); color: today ? "#ffffff" : (inMonth ? Theme.text : Theme.textFaint); font.weight: today ? Font.Bold : Font.Normal }
            }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      visible: Notifs.history.length > 0
      Txt { text: "Notifications"; font.weight: Font.Bold; Layout.fillWidth: true; color: Theme.dark ? "#ffffff" : Theme.text }
      Rectangle {
        width: ct.implicitWidth + 18; height: 24; radius: 12
        color: ch.hovered ? Theme.pressed : Theme.glassStrong
        Txt { id: ct; anchors.centerIn: parent; text: "Clear All"; font.pixelSize: Theme.small }
        HoverHandler { id: ch }
        TapHandler { onTapped: Notifs.clearAll() }
      }
    }

    Txt {
      visible: Notifs.history.length === 0
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: 20
      text: "No Notifications"
      color: Theme.textDim
    }

    Repeater {
      model: Notifs.history.slice(0, 8)
      delegate: NotificationCard {
        required property var modelData
        notif: modelData
        banner: false
        Layout.fillWidth: true
      }
    }
  }
}
