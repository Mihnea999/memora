import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Io
import qs.core
import qs.ui

// The menu bar: the system menu, the focused app's name and its menus on the
// left; status items and the clock on the right.
PanelWindow {
  id: bar
  required property var modelData
  screen: modelData

  anchors { top: true; left: true; right: true }
  implicitHeight: 30
  exclusiveZone: 30
  color: "transparent"
  WlrLayershell.namespace: "memora-bar"
  WlrLayershell.layer: WlrLayer.Top

  readonly property var active: Hyprland.activeToplevel
  readonly property string cls: Apps.activeClass
  readonly property bool desktop: cls === ""
  readonly property string appName: desktop ? "Files" : Apps.nameFor(cls)

  Rectangle {
    anchors.fill: parent
    color: Theme.bar
    Behavior on color { ColorAnimation { duration: Theme.slow } }
  }
  // Transparent bar: a faint veil keeps the text readable on any picture.
  Rectangle {
    visible: Prefs.menuBarTransparent
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: Theme.dark ? Qt.rgba(0, 0, 0, 0.22) : Qt.rgba(1, 1, 1, 0.22) }
      GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
    }
  }

  // ---------------------------------------------------------------- left side
  RowLayout {
    id: left
    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
    spacing: 0

    BarTitle {
      id: logoTitle
      menuId: "system"
      Image {
        anchors.centerIn: parent
        source: "file://" + Theme.share + "/themes/" + Theme.mode + "/logo.png"
        sourceSize: Qt.size(32, 32)
        width: 15; height: 15
        cache: false
      }
      implicitWidth: 34
    }

    // The app's name and its own menus; when another app comes forward they
    // slide in one after another.
    Repeater {
      model: [{ id: "app:" + bar.cls, title: bar.appName, bold: true }].concat(Menus.titles(bar.cls).map(t => ({ id: t.id, title: t.title, cls: bar.cls })))
      delegate: BarTitle {
        id: bt
        required property var modelData
        required property int index
        menuId: modelData.id.startsWith("app:") ? "app" : modelData.id
        label: modelData.title
        bold: !!modelData.bold
        opacity: 0
        transform: Translate { id: tx; x: 8 }
        Component.onCompleted: arrive.start()
        SequentialAnimation {
          id: arrive
          PauseAnimation { duration: Prefs.motion(index * 28) }
          ParallelAnimation {
            NumberAnimation { target: bt; property: "opacity"; to: 1; duration: Prefs.motion(260); easing.type: Easing.OutCubic }
            NumberAnimation { target: tx; property: "x"; to: 0; duration: Prefs.motion(320); easing.type: Easing.OutQuint }
          }
        }
      }
    }
  }

  // --------------------------------------------------------------- right side
  RowLayout {
    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
    spacing: 2

    Repeater {
      model: SystemTray.items
      delegate: BarButton {
        id: trayItem
        required property var modelData
        IconImage {
          anchors.centerIn: parent
          implicitSize: 15
          source: trayItem.modelData.icon
        }
        onClicked: trayItem.modelData.activate()
        onRightClicked: {
          if (trayItem.modelData.hasMenu) trayItem.modelData.display(bar, trayItem.mapToItem(null, 0, 30).x, 30)
        }
      }
    }

    // Keep Awake is on: a cup; click to turn it off.
    BarButton {
      visible: Shell.keepAwake
      tip: "Keep Awake: " + Shell.awakeLabel.toLowerCase() + " · click to turn off"
      Sym { anchors.centerIn: parent; name: "cup"; width: 16; height: 16 }
      onClicked: Shell.setAwake(0)
    }

    BarButton {
      tip: "Memora AI (Super+A)"
      Sym { anchors.centerIn: parent; name: "ai"; width: 15; height: 15 }
      onClicked: Apps.run("memora-ai window")
    }

    BarButton {
      visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
      implicitWidth: 34
      tip: visible ? Math.round(UPower.displayDevice.percentage * 100) + "%" : ""
      Sym {
        anchors.centerIn: parent; name: "battery"; width: 22; height: 22
        level: UPower.displayDevice ? UPower.displayDevice.percentage : 1
        charging: UPower.displayDevice && UPower.displayDevice.state === UPowerDeviceState.Charging
      }
      menu: "battery"
    }

    BarButton {
      visible: Sys.btAvailable
      tip: "Bluetooth"
      Sym { anchors.centerIn: parent; name: "bluetooth"; width: 15; height: 15; opacity: Sys.btOn ? 1 : 0.45 }
      menu: "bluetooth"
    }

    BarButton {
      tip: Net.label
      Sym { anchors.centerIn: parent; name: Net.online ? "wifi" : "wifi-off"; level: Net.strength; width: 17; height: 17 }
      menu: "wifi"
    }

    BarButton {
      visible: !!Sys.sink
      tip: "Sound"
      // Muted shows in red, so it can't pass for "very low".
      Sym { anchors.centerIn: parent; name: Sys.muted || Sys.volume === 0 ? "sound-off" : "sound"; level: Sys.volume; width: 16; height: 16; color: Sys.muted ? Theme.red : Theme.text }
      menu: "sound"
      onScrolled: up => Sys.changeVolume(Sys.volume + (up ? 0.05 : -0.05))
    }

    BarButton {
      tip: "Search (Super+Space)"
      Sym { anchors.centerIn: parent; name: "search"; width: 14; height: 14 }
      onClicked: Shell.toggle("spotlight")
    }

    BarButton {
      id: ccButton
      tip: "Control Center"
      highlighted: Shell.open === "control" && Shell.menuScreen === bar.modelData.name
      Sym { anchors.centerIn: parent; name: "control"; width: 16; height: 16 }
      onClicked: { Shell.menuScreen = bar.modelData.name; Shell.toggle("control") }
    }

    BarButton {
      id: clock
      tip: "Calendar and notifications"
      implicitWidth: clockText.implicitWidth + 16
      highlighted: Shell.open === "calendar" && Shell.menuScreen === bar.modelData.name
      Txt {
        id: clockText
        anchors.centerIn: parent
        font.weight: Font.Medium
        text: (Prefs.showDate ? Qt.formatDateTime(now.date, "ddd MMM d") + "   " : "") + Qt.formatDateTime(now.date, Prefs.clock24 ? "HH:mm" : "h:mm AP")
      }
      onClicked: { Shell.menuScreen = bar.modelData.name; Shell.toggle("calendar") }
    }
  }

  SystemClock { id: now; precision: SystemClock.Minutes }

  // ------------------------------------------------------------- the dropdown
  PopupWindow {
    id: drop
    visible: Shell.open === "menu" && Shell.menuScreen === bar.modelData.name
    anchor.window: bar
    anchor.rect.x: Shell.menuX
    anchor.rect.y: bar.height + 2
    implicitWidth: panel.implicitWidth + 40
    implicitHeight: panel.implicitHeight + 40
    color: "transparent"

    MenuPanel {
      id: panel
      x: 0; y: 0
      width: implicitWidth
      height: implicitHeight
      items: drop.visible ? Menus.items(Shell.menu, bar.cls, bar.appName, bar.active) : []
      onPicked: item => { const run = item.action; Shell.close(); if (run) Qt.callLater(run) }
      opacity: drop.visible ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    }
  }

  OutsideClick {
    when: drop.visible
    windows: [drop, bar]
    onOutside: if (Shell.open === "menu") Shell.close()
  }

  // A title in the bar that opens a menu; while any menu is open, hovering
  // another title switches to it, as on a desktop.
  component BarTitle: Item {
    id: title
    property string menuId: ""
    property string label: ""
    property bool bold: false
    readonly property bool current: Shell.open === "menu" && Shell.menu === menuId && Shell.menuScreen === bar.modelData.name
    implicitHeight: 24
    implicitWidth: labelText.implicitWidth + 18

    Rectangle {
      anchors.fill: parent
      radius: 6
      color: title.current ? Theme.pressed : "transparent"
    }
    Txt {
      id: labelText
      anchors.centerIn: parent
      text: title.label
      font.weight: title.bold ? Font.Bold : Font.Normal
      visible: title.label !== ""
    }
    function openHere() { Shell.openMenu(menuId, title.mapToItem(null, 0, 0).x, bar.modelData.name) }
    HoverHandler {
      onHoveredChanged: if (hovered && Shell.open === "menu" && Shell.menuScreen === bar.modelData.name && Shell.menu !== title.menuId) title.openHere()
    }
    TapHandler {
      onTapped: title.current ? Shell.close() : title.openHere()
    }
  }

  // Opens (or closes) a status item's menu under it (bar/StatusMenu.qml).
  property real hoverSwitched: 0
  function statusMenu(kind, item, byHover) {
    if (byHover) hoverSwitched = Date.now()
    else if (Shell.open === "status" && Shell.menu === kind && Shell.menuScreen === bar.modelData.name) {
      if (Date.now() - hoverSwitched > 400) Shell.close()   // not the click that pointing there just opened
      return
    }
    Shell.menu = kind
    Shell.menuX = item.mapToItem(null, 0, 0).x - 6
    Shell.menuScreen = bar.modelData.name
    Shell.open = "status"
  }
  StatusMenu { bar: bar }

  component BarButton: Item {
    id: btn
    property string tip: ""
    property string menu: ""            // a status menu: wifi, bluetooth, battery, sound
    property bool highlighted: menu !== "" && Shell.open === "status" && Shell.menu === menu && Shell.menuScreen === bar.modelData.name
    signal clicked()
    signal rightClicked()
    signal scrolled(bool up)
    onClicked: if (menu !== "") bar.statusMenu(menu, btn)
    WheelHandler { onWheel: ev => btn.scrolled(ev.angleDelta.y > 0) }
    // While another status menu is open, pointing at this one switches to it.
    HoverHandler { onHoveredChanged: if (hovered && btn.menu !== "" && Shell.open === "status" && Shell.menuScreen === bar.modelData.name && Shell.menu !== btn.menu) bar.statusMenu(btn.menu, btn, true) }
    implicitWidth: 30
    implicitHeight: 24
    Rectangle {
      anchors.fill: parent
      radius: 6
      color: btn.highlighted ? Theme.pressed : (hh.hovered ? Theme.hover : "transparent")
      Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    HoverHandler { id: hh; onHoveredChanged: if (hovered && btn.tip) tipWait.restart(); else { tipWait.stop(); if (bar.tipFor === btn) bar.tipFor = null } }
    Timer { id: tipWait; interval: 550; onTriggered: if (Shell.open === "") bar.tipFor = btn }
    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: { tipWait.stop(); bar.tipFor = null; btn.clicked() } }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: btn.rightClicked() }
  }

  // The tooltip under a menu-bar button (its own little window, below the bar).
  property var tipFor: null
  PopupWindow {
    id: tipWin
    visible: !!bar.tipFor && Shell.open === ""
    anchor.window: bar
    anchor.rect.x: bar.tipFor ? Math.min(bar.width - implicitWidth - 6, Math.max(6, bar.tipFor.mapToItem(null, bar.tipFor.width / 2, 0).x - implicitWidth / 2)) : 0
    anchor.rect.y: bar.height + 4
    implicitWidth: tipText.implicitWidth + 20
    implicitHeight: tipText.implicitHeight + 12
    color: "transparent"
    Rectangle {
      anchors.fill: parent
      radius: 8
      color: Theme.dark ? Qt.rgba(0.17, 0.17, 0.19, 0.97) : Qt.rgba(0.99, 0.99, 1, 0.98)
      border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.12)
      Txt { id: tipText; anchors.centerIn: parent; text: bar.tipFor ? bar.tipFor.tip : ""; font.pixelSize: Theme.small }
    }
  }
}
