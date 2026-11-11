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
  // Over a full-screen app it must be above it to show at all.
  WlrLayershell.layer: fullscreen ? WlrLayer.Overlay : WlrLayer.Top
  mask: Region { item: bar.tucked ? topEdge : whole }

  // Full screen (the green button, F11), as on a Mac: the bar steps aside and
  // slides down over the app when the pointer reaches the top edge; it goes
  // again once the pointer moves away (not while one of its menus is open).
  readonly property var monitor: Hyprland.monitors.values.find(m => m.name === modelData.name) || null
  readonly property var fsWindow: {
    const ws = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    return Apps.windows.find(w => w.lastIpcObject.fullscreen === 2 && w.lastIpcObject.workspace && w.lastIpcObject.workspace.id === ws) || null
  }
  readonly property bool fullscreen: fsWindow !== null
  property bool revealed: false
  readonly property bool inUse: barHover.hovered || drop.visible || (Shell.open !== "" && Shell.menuScreen === modelData.name)
  readonly property bool tucked: fullscreen && !revealed && !inUse
  onFullscreenChanged: revealed = false
  onInUseChanged: if (!inUse && revealed) leave.restart()
  Timer { id: arrive; interval: 120; onTriggered: { bar.revealed = true; leave.restart() } }
  Timer { id: leave; interval: 500; onTriggered: if (!bar.inUse && !edgeHover.hovered) bar.revealed = false; else if (!bar.inUse) restart() }
  property real slide: tucked ? -height : 0
  Behavior on slide { NumberAnimation { duration: Prefs.motion(220); easing.type: Easing.OutCubic } }
  Translate { id: slideT; y: bar.slide }
  Item { id: whole; anchors.fill: parent }
  // On the bar itself, so the titles (which take hover too) don't hide it.
  HoverHandler { id: barHover }
  Item {
    id: topEdge
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: 2
    HoverHandler { id: edgeHover; onHoveredChanged: if (hovered && bar.tucked) arrive.restart(); else if (!hovered) arrive.stop() }
  }

  // (Over a full-screen app Hyprland.activeToplevel comes back empty: the
  // menus act on the full-screen window then.)
  readonly property var active: Hyprland.activeToplevel || fsWindow
  readonly property string cls: Apps.activeClass
  readonly property bool desktop: cls === ""
  readonly property string appName: desktop ? "Files" : Apps.nameFor(cls)

  // The bar's ink follows the picture under it, not only the appearance: white
  // on a dark picture (also in the light appearance), dark on a bright one.
  property real wallLum: Theme.dark ? 0.2 : 0.8      // brightness of the picture's top strip, 0..1
  Process {
    id: lumProbe
    command: ["magick", Theme.wallpaper + "[0]", "-gravity", "North", "-crop", "100%x4%+0+0", "+repage", "-resize", "1x1!", "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"]
    stdout: StdioCollector { onStreamFinished: { const v = parseFloat(text); if (!isNaN(v)) bar.wallLum = v } }
  }
  readonly property string wall: Theme.wallpaper
  onWallChanged: { lumProbe.running = false; lumProbe.running = true }
  Component.onCompleted: lumProbe.running = true
  // A frosted bar adds its own tint over the picture.
  readonly property real under: Prefs.reduceTransparency ? (Theme.dark ? 0.1 : 0.95)
    : Prefs.menuBarTransparent ? wallLum : wallLum * 0.66 + (Theme.dark ? 0.02 : 0.33)
  // Over a full-screen app the bar is solid, in the appearance's colours.
  readonly property bool onDark: fullscreen ? Theme.dark : under < 0.56
  property color ink: onDark ? "#f5f5f7" : "#1c1c1e"
  Behavior on ink { ColorAnimation { duration: Theme.slow } }
  function plate(a) { return onDark ? Qt.rgba(1, 1, 1, a) : Qt.rgba(0, 0, 0, a * 0.7) }

  // Room for the app's menus: up to the AI notch when it is on this screen.
  // Menus that don't fit go under "»" (small screens, apps with many menus).
  readonly property bool hasNotch: !!Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === modelData.name && !Shell.fullscreenApp
  readonly property real notchW: hasNotch ? Shell.notchWidth : 0
  readonly property real room: hasNotch ? (bar.width - notchW) / 2 - 10 - 14 : statusRow.x - 10 - 24
  readonly property var titles: [{ id: "app:" + bar.cls, title: bar.appName, bold: true }].concat(Menus.titles(bar.cls).map(t => ({ id: t.id, title: t.title, cls: bar.cls })))
  FontMetrics { id: fm; font.family: Theme.font; font.pixelSize: Theme.fontSize }
  FontMetrics { id: fmb; font.family: Theme.font; font.pixelSize: Theme.fontSize; font.bold: true }
  readonly property int fits: {
    let x = 34
    const more = fm.advanceWidth("»") + 18
    for (let i = 0; i < titles.length; i++) {
      const w = (titles[i].bold ? fmb : fm).advanceWidth(titles[i].title) + 18
      const need = i < titles.length - 1 ? more : 0
      if (i > 0 && x + w + need > room) return i
      x += w
    }
    return titles.length
  }

  Rectangle {
    anchors.fill: parent
    transform: slideT
    color: bar.fullscreen ? (Theme.dark ? Qt.rgba(0.11, 0.11, 0.13, 0.97) : Qt.rgba(0.97, 0.97, 0.98, 0.97)) : Theme.bar
    Behavior on color { ColorAnimation { duration: Theme.slow } }
  }
  // Transparent bar: nothing at all behind the text, as on a Mac (no veil, no
  // frost: rules.lua never blurs this layer). The ink follows the picture
  // instead, so it reads on any of them.

  // ---------------------------------------------------------------- left side
  RowLayout {
    id: left
    transform: slideT
    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
    spacing: 0

    BarTitle {
      id: logoTitle
      menuId: "system"
      Image {
        anchors.centerIn: parent
        source: "file://" + Theme.share + "/themes/" + (bar.onDark ? "dark" : "light") + "/logo.png"
        sourceSize: Qt.size(32, 32)
        width: 15; height: 15
        cache: false
      }
      implicitWidth: 34
    }

    // The app's name and its own menus; when another app comes forward they
    // slide in one after another.
    Repeater {
      model: bar.titles
      delegate: BarTitle {
        id: bt
        required property var modelData
        required property int index
        visible: index < bar.fits
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
    // The menus that didn't fit.
    BarTitle {
      visible: bar.fits < bar.titles.length
      menuId: "overflow"
      label: "»"
      onOpening: Shell.moreMenus = bar.titles.slice(bar.fits).map(t => ({ id: t.id.startsWith("app:") ? "app" : t.id, title: t.title }))
    }
  }

  // --------------------------------------------------------------- right side
  // The date goes when the status items would reach the notch.
  readonly property string dateText: Qt.formatDateTime(now.date, "ddd MMM d") + "   "
  readonly property string timeText: Qt.formatDateTime(now.date, Prefs.clock24 ? "HH:mm" : "h:mm AP")
  readonly property bool dateFits: Prefs.showDate && (bar.width + notchW) / 2 + 14 + statusRow.implicitWidth + fm.advanceWidth(dateText + timeText) + 30 < bar.width
  RowLayout {
    id: statusRow
    transform: slideT
    anchors { right: clock.left; rightMargin: 2; verticalCenter: parent.verticalCenter }
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
      Sym { anchors.centerIn: parent; color: bar.ink; name: "cup"; width: 16; height: 16 }
      onClicked: Shell.setAwake(0)
    }

    BarButton {
      // The notch is already the way in; on a narrow bar this one makes room.
      visible: !bar.hasNotch || bar.width >= 1400
      tip: "Memora AI (Super+A)"
      Sym { anchors.centerIn: parent; color: bar.ink; name: "ai"; width: 15; height: 15 }
      onClicked: Apps.run("memora-ai window")
    }

    BarButton {
      visible: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
      implicitWidth: batRow.implicitWidth + 12
      tip: visible && !Prefs.batteryPercent ? Math.round(UPower.displayDevice.percentage * 100) + "%" : ""
      Row {
        id: batRow
        anchors.centerIn: parent
        spacing: 5
        Txt {
          visible: Prefs.batteryPercent
          anchors.verticalCenter: parent.verticalCenter
          text: UPower.displayDevice ? Math.round(UPower.displayDevice.percentage * 100) + "%" : ""
          font.pixelSize: Theme.small + 0.5
          // Low and not charging: red, as on a Mac.
          color: UPower.displayDevice && UPower.displayDevice.percentage <= 0.1 && UPower.displayDevice.state !== UPowerDeviceState.Charging ? Theme.red : bar.ink
        }
        Sym {
          anchors.verticalCenter: parent.verticalCenter
          name: "battery"; width: 22; height: 22; color: bar.ink
          level: UPower.displayDevice ? UPower.displayDevice.percentage : 1
          charging: UPower.displayDevice && UPower.displayDevice.state === UPowerDeviceState.Charging
        }
      }
      menu: "battery"
    }

    BarButton {
      visible: Sys.btAvailable
      tip: "Bluetooth"
      Sym { anchors.centerIn: parent; color: bar.ink; name: "bluetooth"; width: 15; height: 15; opacity: Sys.btOn ? 1 : 0.45 }
      menu: "bluetooth"
    }

    BarButton {
      tip: Net.label
      // A computer on a cable (no Wi-Fi in it) shows its network as a globe.
      Sym { anchors.centerIn: parent; color: bar.ink; name: !Host.hasWifi ? "globe" : (Net.online ? "wifi" : "wifi-off"); level: Net.strength; width: Host.hasWifi ? 17 : 15; height: Host.hasWifi ? 17 : 15; opacity: Host.hasWifi || Net.online ? 1 : 0.45 }
      menu: Host.hasWifi ? "wifi" : ""
      onClicked: if (!Host.hasWifi) Apps.run("memora-settings network")
    }

    BarButton {
      visible: !!Sys.sink
      tip: "Sound"
      // Muted shows in red, so it can't pass for "very low".
      Sym { anchors.centerIn: parent; name: Sys.muted || Sys.volume === 0 ? "sound-off" : "sound"; level: Sys.volume; width: 16; height: 16; color: Sys.muted ? Theme.red : bar.ink }
      menu: "sound"
      onScrolled: up => Sys.changeVolume(Sys.volume + (up ? 0.05 : -0.05))
    }

    BarButton {
      tip: "Search (Super+Space)"
      Sym { anchors.centerIn: parent; color: bar.ink; name: "search"; width: 14; height: 14 }
      onClicked: Shell.toggle("spotlight")
    }

    BarButton {
      id: ccButton
      tip: "Control Center"
      highlighted: Shell.open === "control" && Shell.menuScreen === bar.modelData.name
      Sym { anchors.centerIn: parent; color: bar.ink; name: "control"; width: 16; height: 16 }
      onClicked: { Shell.menuScreen = bar.modelData.name; Shell.toggle("control") }
    }

  }

  BarButton {
    id: clock
    transform: slideT
    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
    tip: "Calendar and notifications"
    implicitWidth: clockText.implicitWidth + 16
    highlighted: Shell.open === "calendar" && Shell.menuScreen === bar.modelData.name
    Txt {
      id: clockText
      anchors.centerIn: parent
      color: bar.ink
      font.features: { "tnum": 1 }   // digits of one width: the clock doesn't shift as it ticks
      font.weight: Font.Medium
      text: (bar.dateFits ? bar.dateText : "") + bar.timeText
    }
    onClicked: { Shell.menuScreen = bar.modelData.name; Shell.toggle("calendar") }
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
      solid: false
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
      color: title.current ? bar.plate(0.16) : "transparent"
    }
    Txt {
      id: labelText
      anchors.centerIn: parent
      color: bar.ink
      text: title.label
      font.weight: title.bold ? Font.Bold : Font.Normal
      visible: title.label !== ""
    }
    signal opening()
    function openHere() { title.opening(); Shell.openMenu(menuId, title.mapToItem(null, 0, 0).x, bar.modelData.name) }
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
      color: btn.highlighted ? bar.plate(0.16) : (hh.hovered ? bar.plate(0.10) : "transparent")
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
