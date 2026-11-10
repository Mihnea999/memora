//@ pragma UseQApplication
//@ pragma AppId memora-settings
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.ui
import qs.settings

// System Settings. Run as `memora-settings [pane]`.
ShellRoot {
  id: app
  property string pane: (Quickshell.env("MEMORA_SETTINGS_PANE") || "wifi")
  // A computer without Wi-Fi has no Wi-Fi pane: it opens on Network.
  readonly property bool noWifi: !Host.hasWifi
  onNoWifiChanged: if (noWifi && pane === "wifi") pane = "network"
  property string search: ""

  // What this computer has decides what's listed (Host.qml): a desktop has no
  // Battery or Trackpad pane, one without Wi-Fi no Wi-Fi pane.
  readonly property var panes: [
    { id: "wifi", title: "Wi-Fi", sym: "wifi", color: "#2f7bff", group: 1, hide: !Host.hasWifi },
    { id: "bluetooth", title: "Bluetooth", sym: "bluetooth", color: "#2f7bff", group: 1 },
    { id: "network", title: "Network", sym: "globe", color: "#3c9bf0", group: 1 },
    { id: "nearby", title: "Nearby Share", sym: "share", color: "#2f7bff", group: 1 },
    { id: "notifications", title: "Notifications", sym: "bell", color: "#ff4d5e", group: 2 },
    { id: "sound", title: "Sound", sym: "sound", color: "#ff4fa0", group: 2 },
    { id: "appearance", title: "Appearance", sym: "moon", color: "#1d1d20", group: 3 },
    { id: "wallpaper", title: "Wallpaper", sym: "photo", color: "#2fb6d9", group: 3 },
    { id: "dock", title: "Dock & Menu Bar", sym: "dock", color: "#46474d", group: 3 },
    { id: "windows", title: "Windows & Desktops", sym: "display", color: "#5e5ce6", group: 3 },
    { id: "animations", title: "Animations", sym: "play", color: "#ff6b8a", group: 3 },
    { id: "displays", title: "Displays", sym: "display", color: "#2f7bff", group: 3 },
    { id: "keyboard", title: "Keyboard", sym: "keyboard", color: "#8a8d96", group: 4 },
    { id: "mouse", title: Host.hasTouchpad ? "Trackpad & Mouse" : "Mouse", sym: "mouse", color: "#8a8d96", group: 4 },
    { id: "battery", title: Host.isLaptop ? "Battery" : "Energy", sym: "battery", color: "#34c759", group: 4 },
    { id: "datetime", title: "Date & Time", sym: "clock", color: "#8a8d96", group: 5 },
    { id: "users", title: "Users", sym: "user", color: "#2f7bff", group: 5 },
    { id: "privacy", title: "Privacy & Security", sym: "shield", color: "#34c759", group: 5 },
    { id: "ai", title: "Memora AI", sym: "ai", color: "#8a5cff", group: 6 },
    { id: "update", title: "Software Update", sym: "download", color: "#2f7bff", group: 6 },
    { id: "reset", title: "Reset", sym: "restart", color: "#8a8d96", group: 6 },
    { id: "about", title: "About", sym: "info", color: "#8a8d96", group: 6 }
  ]
  readonly property var visiblePanes: panes.filter(p => !p.hide && (!search || p.title.toLowerCase().indexOf(search.toLowerCase()) >= 0))
  // The keyboard: ↑ and ↓ in the search field walk the list of panes.
  function step(d) {
    const l = visiblePanes
    if (!l.length) return
    const i = l.findIndex(p => p.id === pane)
    pane = l[i < 0 ? (d > 0 ? 0 : l.length - 1) : Math.max(0, Math.min(l.length - 1, i + d))].id
  }

  readonly property var paneFiles: ({
    wifi: "Wifi", bluetooth: "BluetoothPane", network: "NetworkPane", nearby: "NearbyPane", notifications: "NotificationsPane",
    sound: "SoundPane", appearance: "AppearancePane", animations: "AnimationsPane", windows: "WindowsPane", wallpaper: "WallpaperPane", dock: "DockPane",
    displays: "DisplaysPane", keyboard: "KeyboardPane", mouse: "MousePane", battery: "BatteryPane",
    datetime: "DateTimePane", users: "UsersPane", privacy: "PrivacyPane", ai: "AiPane", update: "UpdatePane", reset: "ResetPane", about: "AboutPane"
  })

  // A second `memora-settings pane` call switches the open window to that pane.
  IpcHandler {
    target: "settings"
    function open(p: string): void { if (app.paneFiles[p]) app.pane = p }
  }

  FloatingWindow {
    id: win
    // Closed by the compositor (Alt+F4, Quit, Super+Q): end the app too, so it
    // opens again next time instead of lingering without a window.
    onVisibleChanged: if (!visible) Qt.quit()
    title: "System Settings"
    implicitWidth: 940
    implicitHeight: 660
    minimumSize: Qt.size(480, 400)
    color: "transparent"
    // Narrow (docked beside another app on a small screen): the sidebar tucks
    // away and slides in over the panes when wanted.
    readonly property bool compact: width < 720
    property bool sideOpen: false
    onCompactChanged: sideOpen = false
    Connections {
      target: app
      function onPaneChanged() {
        win.sideOpen = false
        const i = app.visiblePanes.findIndex(p => p.id === app.pane)
        if (i >= 0) nav.positionViewAtIndex(i, ListView.Contain)
      }
    }
    Shortcut { sequence: "Ctrl+F"; onActivated: { if (win.compact) win.sideOpen = true; searchField.forceActiveFocus(); searchField.selectAll() } }

    Rectangle {
      anchors.fill: parent
      color: Theme.window
    }

    // ---- sidebar ------------------------------------------------------------
    Rectangle {
      id: side
      width: 250
      z: win.compact ? 10 : 0
      anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 8 }
      anchors.leftMargin: win.compact && !win.sideOpen ? -width - 24 : 8
      Behavior on anchors.leftMargin { NumberAnimation { duration: Theme.normal; easing.type: Theme.easingEmph } }
      radius: 14
      color: win.compact ? Theme.glassSolid : Theme.sidebar
      border.color: Theme.separator

      // Window buttons
      WindowControls { id: lights; x: 14; y: 14; window: win; onCloseRequested: Qt.quit() }
      // Drag the window by its top strip.
      Item {
        anchors { left: lights.right; right: parent.right; top: parent.top }
        height: 40
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) }
      }

      Rectangle {
        id: searchBox
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 42; leftMargin: 12; rightMargin: 12 }
        height: 28; radius: 8
        color: Theme.field
        border.color: searchField.activeFocus ? Theme.accent : Theme.separator
        Sym { name: "search"; width: 12; height: 12; color: Theme.textDim; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
        TextInput {
          id: searchField
          clip: true   // long text scrolls inside the field, never spills out
          anchors { left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 8; verticalCenter: parent.verticalCenter }
          color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
          onTextChanged: app.search = text
          // Typing searches straight away; ↑ ↓ pick a pane, Return takes the
          // first match, Esc clears. Tab goes on to the pane's own controls.
          focus: true
          activeFocusOnTab: true
          selectByMouse: true
          Keys.onDownPressed: app.step(1)
          Keys.onUpPressed: app.step(-1)
          Keys.onReturnPressed: if (app.search && app.visiblePanes.length && !app.visiblePanes.some(p => p.id === app.pane)) app.pane = app.visiblePanes[0].id
          Keys.onEscapePressed: text = ""
          Txt { visible: !searchField.text; text: "Search"; color: Theme.textFaint; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
        }
      }

      // The person
      Item {
        id: me
        anchors { left: parent.left; right: parent.right; top: searchBox.bottom; topMargin: 12 }
        height: 56
        Rectangle { anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; radius: 9; color: app.pane === "users" ? Theme.accent : (mh.hovered ? Theme.hover : "transparent") }
        Rectangle {
          id: avatar
          x: 14; width: 38; height: 38; radius: 19
          anchors.verticalCenter: parent.verticalCenter
          gradient: Gradient { GradientStop { position: 0; color: "#c5c9d2" } GradientStop { position: 1; color: "#8d929d" } }
          Txt { anchors.centerIn: parent; text: (Host.fullName || "M").charAt(0).toUpperCase(); color: "#fff"; font.weight: Font.Bold; font.pixelSize: 16 }
        }
        Column {
          anchors { left: avatar.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
          Txt { text: Host.fullName; font.weight: Font.Bold; color: app.pane === "users" ? "#fff" : Theme.text }
          Txt { text: "This computer's account"; font.pixelSize: Theme.small - 0.5; color: app.pane === "users" ? Qt.rgba(1, 1, 1, 0.8) : Theme.textDim }
        }
        HoverHandler { id: mh }
        TapHandler { onTapped: app.pane = "users" }
      }

      ListView {
        id: nav
        anchors { left: parent.left; right: parent.right; top: me.bottom; bottom: parent.bottom; topMargin: 8; leftMargin: 6; rightMargin: 6; bottomMargin: 8 }
        clip: true
        model: app.visiblePanes
        spacing: 1
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
          required property var modelData
          required property int index
          readonly property bool gap: index > 0 && app.visiblePanes[index - 1].group !== modelData.group && !app.search
          width: nav.width
          height: 30 + (gap ? 10 : 0)
          Rectangle {
            y: parent.gap ? 10 : 0
            width: parent.width; height: 30; radius: 7
            color: app.pane === modelData.id ? Theme.accent : (nh.hovered ? Theme.hover : "transparent")
            Rectangle {
              x: 8; width: 20; height: 20; radius: 5
              anchors.verticalCenter: parent.verticalCenter
              color: modelData.color
              Sym { anchors.centerIn: parent; name: modelData.sym; width: 12; height: 12; color: "#ffffff" }
            }
            Txt { x: 36; anchors.verticalCenter: parent.verticalCenter; text: modelData.title; color: app.pane === modelData.id ? "#ffffff" : Theme.text }
          }
          HoverHandler { id: nh }
          TapHandler { onTapped: app.pane = modelData.id }
        }
      }
    }

    // Narrow: the window buttons and the sidebar button, top left; a tap beside
    // the slid-in sidebar puts it away.
    CompactBar {
      x: 14; y: 12; z: 5
      visible: win.compact
      window: win; sideOpen: win.sideOpen
      onToggled: win.sideOpen = !win.sideOpen
      onCloseRequested: Qt.quit()
    }
    MouseArea { anchors.fill: parent; z: 9; visible: win.compact && win.sideOpen; onClicked: win.sideOpen = false }

    // ---- content ------------------------------------------------------------
    Item {
      anchors { left: win.compact ? parent.left : side.right; right: parent.right; top: parent.top; bottom: parent.bottom }
      Item {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 40
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) }
      }
      // Each pane settles in: a short rise and fade.
      Loader {
        id: loader
        anchors.fill: parent
        anchors.topMargin: win.compact ? 30 : 0
        source: "settings/" + (app.paneFiles[app.pane] || "Wifi") + ".qml"
        transform: Translate { id: rise; y: 0 }
        onLoaded: enter.restart()
        ParallelAnimation {
          id: enter
          NumberAnimation { target: loader; property: "opacity"; from: 0; to: 1; duration: Theme.normal; easing.type: Theme.easing }
          NumberAnimation { target: rise; property: "y"; from: 14; to: 0; duration: Theme.slow; easing.type: Easing.OutQuint }
        }
      }
    }
  }
}
