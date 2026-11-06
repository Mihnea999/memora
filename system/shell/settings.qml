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
  property string search: ""

  readonly property var panes: [
    { id: "wifi", title: "Wi-Fi", sym: "wifi", color: "#2f7bff", group: 1 },
    { id: "bluetooth", title: "Bluetooth", sym: "bluetooth", color: "#2f7bff", group: 1 },
    { id: "network", title: "Network", sym: "globe", color: "#3c9bf0", group: 1 },
    { id: "notifications", title: "Notifications", sym: "bell", color: "#ff4d5e", group: 2 },
    { id: "sound", title: "Sound", sym: "sound", color: "#ff4fa0", group: 2 },
    { id: "appearance", title: "Appearance", sym: "moon", color: "#1d1d20", group: 3 },
    { id: "wallpaper", title: "Wallpaper", sym: "photo", color: "#2fb6d9", group: 3 },
    { id: "dock", title: "Dock & Menu Bar", sym: "dock", color: "#46474d", group: 3 },
    { id: "animations", title: "Animations", sym: "play", color: "#ff6b8a", group: 3 },
    { id: "displays", title: "Displays", sym: "display", color: "#2f7bff", group: 3 },
    { id: "keyboard", title: "Keyboard", sym: "keyboard", color: "#8a8d96", group: 4 },
    { id: "mouse", title: "Mouse & Trackpad", sym: "mouse", color: "#8a8d96", group: 4 },
    { id: "battery", title: "Battery", sym: "battery", color: "#34c759", group: 4 },
    { id: "datetime", title: "Date & Time", sym: "clock", color: "#8a8d96", group: 5 },
    { id: "users", title: "Users", sym: "user", color: "#2f7bff", group: 5 },
    { id: "ai", title: "Memora AI", sym: "ai", color: "#8a5cff", group: 6 },
    { id: "update", title: "Software Update", sym: "gear", color: "#8a8d96", group: 6 },
    { id: "about", title: "About", sym: "info", color: "#8a8d96", group: 6 }
  ]
  readonly property var visiblePanes: search ? panes.filter(p => p.title.toLowerCase().indexOf(search.toLowerCase()) >= 0) : panes

  readonly property var paneFiles: ({
    wifi: "Wifi", bluetooth: "BluetoothPane", network: "NetworkPane", notifications: "NotificationsPane",
    sound: "SoundPane", appearance: "AppearancePane", animations: "AnimationsPane", wallpaper: "WallpaperPane", dock: "DockPane",
    displays: "DisplaysPane", keyboard: "KeyboardPane", mouse: "MousePane", battery: "BatteryPane",
    datetime: "DateTimePane", users: "UsersPane", ai: "AiPane", update: "UpdatePane", about: "AboutPane"
  })

  // A second `memora-settings pane` call switches the open window to that pane.
  IpcHandler {
    target: "settings"
    function open(p: string): void { if (app.paneFiles[p]) app.pane = p }
  }

  FloatingWindow {
    id: win
    title: "System Settings"
    implicitWidth: 940
    implicitHeight: 660
    minimumSize: Qt.size(760, 480)
    color: "transparent"

    Rectangle {
      anchors.fill: parent
      color: Theme.dark ? Qt.rgba(0.11, 0.11, 0.13, 0.96) : Qt.rgba(0.97, 0.97, 0.98, 0.97)
    }

    // ---- sidebar ------------------------------------------------------------
    Rectangle {
      id: side
      width: 250
      anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 8 }
      radius: 14
      color: Theme.dark ? Qt.rgba(1, 1, 1, 0.045) : Qt.rgba(0, 0, 0, 0.035)
      border.color: Theme.separator

      // Window buttons
      Row {
        id: lights
        x: 14; y: 14
        spacing: 8
        Repeater {
          model: [["close", Theme.red], ["min", Theme.yellow], ["zoom", Theme.green]]
          delegate: Rectangle {
            required property var modelData
            width: 13; height: 13; radius: 6.5
            color: modelData[1]
            border.color: Qt.rgba(0, 0, 0, 0.15)
            TapHandler {
              onTapped: {
                if (modelData[0] === "close") Qt.quit()
                else if (modelData[0] === "min") Quickshell.execDetached(["memora-shell", "minimize"])
                else Hyprland.dispatch('hl.dsp.window.fullscreen({ mode = "maximized" })')
              }
            }
          }
        }
      }
      // Drag the window by its top strip.
      Item {
        anchors { left: lights.right; right: parent.right; top: parent.top }
        height: 40
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      }

      Rectangle {
        id: searchBox
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 42; leftMargin: 12; rightMargin: 12 }
        height: 28; radius: 8
        color: Theme.field
        border.color: Theme.separator
        Sym { name: "search"; width: 12; height: 12; color: Theme.textDim; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
        TextInput {
          id: searchField
          anchors { left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 8; verticalCenter: parent.verticalCenter }
          color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
          onTextChanged: app.search = text
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

    // ---- content ------------------------------------------------------------
    Item {
      anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom }
      Item {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 40
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      }
      Loader {
        id: loader
        anchors.fill: parent
        source: "settings/" + (app.paneFiles[app.pane] || "Wifi") + ".qml"
        opacity: status === Loader.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
      }
    }
  }
}
