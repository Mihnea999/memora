//@ pragma UseQApplication
//@ pragma AppId memora-welcome
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui

// First start: say hello, pick the appearance, set up the assistant.
ShellRoot {
  id: app
  property int page: 0
  readonly property int pages: 5

  FloatingWindow {
    id: win
    // Closed by the compositor (Alt+F4, Quit, Super+Q): end the app too, so it
    // opens again next time instead of lingering without a window.
    onVisibleChanged: if (!visible) Qt.quit()
    title: "Welcome to Memora"
    implicitWidth: 720
    implicitHeight: 520
    color: "transparent"
    Rectangle { anchors.fill: parent; color: Theme.window }
    Item {
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: 40
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: Quickshell.execDetached(["memora-shell", "window-menu"]) }
      WindowControls { x: 16; y: 14; window: win; onCloseRequested: Qt.quit() }
    }

    Item {
      id: stage
      anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top; topMargin: 30 }
      clip: true
      // The keyboard alone: Return or → goes on, ← goes back, Esc closes.
      focus: true
      Component.onCompleted: forceActiveFocus()
      function next() { if (app.page === app.pages - 1) Qt.quit(); else app.page++ }
      Keys.onReturnPressed: next()
      Keys.onEnterPressed: next()
      Keys.onRightPressed: if (app.page < app.pages - 1) app.page++
      Keys.onLeftPressed: if (app.page > 0) app.page--
      Keys.onEscapePressed: Qt.quit()
      Row {
        x: -app.page * stage.width
        Behavior on x { NumberAnimation { duration: Theme.slow; easing.type: Theme.easingEmph } }

        // 1. Hello
        Item {
          width: stage.width; height: stage.height
          Column {
            anchors.centerIn: parent
            spacing: 14
            Image { anchors.horizontalCenter: parent.horizontalCenter; source: "file://" + Theme.share + "/themes/" + Theme.mode + "/logo.png"; width: 96; height: 96; sourceSize: Qt.size(192, 192) }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Welcome to Memora"; font.pixelSize: 28; font.weight: Font.Bold }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "A few choices, and you're ready."; color: Theme.textDim }
          }
        }

        // 2. Appearance
        Item {
          width: stage.width; height: stage.height
          Column {
            anchors.centerIn: parent
            spacing: 22
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Choose your look"; font.pixelSize: 22; font.weight: Font.Bold }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 30
              Repeater {
                model: [{ id: "light", name: "Light" }, { id: "dark", name: "Dark" }]
                delegate: Column {
                  required property var modelData
                  spacing: 10
                  Rectangle {
                    width: 200; height: 128; radius: 12
                    border.width: Theme.mode === modelData.id ? 3 : 1
                    border.color: Theme.mode === modelData.id ? Theme.accent : Theme.separator
                    clip: true
                    Image { anchors.fill: parent; anchors.margins: 3; source: "file://" + Theme.wallpaperFor(modelData.id); sourceSize: Qt.size(400, 256); fillMode: Image.PreserveAspectCrop }
                    Rectangle { x: 18; y: 22; width: 100; height: 66; radius: 7; color: modelData.id === "dark" ? "#2a2a2e" : "#ffffff"; opacity: 0.92 }
                    TapHandler { onTapped: Quickshell.execDetached(["memora-theme", "set", modelData.id]) }
                  }
                  Txt { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; font.weight: Theme.mode === modelData.id ? Font.Bold : Font.Normal }
                }
              }
            }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "You can change it any time in Control Center."; color: Theme.textDim; font.pixelSize: Theme.small }
          }
        }

        // 3. Memora AI
        Item {
          width: stage.width; height: stage.height
          Column {
            anchors.centerIn: parent
            spacing: 14
            width: 460
            Image { anchors.horizontalCenter: parent.horizontalCenter; source: Quickshell.iconPath("memora-ai"); width: 84; height: 84; sourceSize: Qt.size(168, 168) }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Memora AI"; font.pixelSize: 22; font.weight: Font.Bold }
            Txt { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; color: Theme.textDim
              text: "Ask it to do things on this computer: change settings, sort files, install apps, fix problems. It asks before doing anything risky." }
            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              width: st.implicitWidth + 32; height: 32; radius: 9; color: Theme.accent
              Txt { id: st; anchors.centerIn: parent; text: "Set Up Memora AI"; color: "#ffffff"; font.weight: Font.Bold }
              TapHandler { onTapped: Quickshell.execDetached(["memora-settings", "ai"]) }
            }
          }
        }

        // 4. Getting around
        Item {
          width: stage.width; height: stage.height
          Column {
            anchors.centerIn: parent
            spacing: 18
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Getting around"; font.pixelSize: 22; font.weight: Font.Bold }
            Grid {
              anchors.horizontalCenter: parent.horizontalCenter
              columns: 2; columnSpacing: 14; rowSpacing: 14
              Repeater {
                model: [["search", "Find anything", "Super+Space"], ["dock", "All your apps", "Tap Super"],
                        ["display", "Desktops & windows", "Ctrl+Super+↑, or three fingers up"], ["sidebar", "Windows side by side", "Drag to an edge, or Super+arrows"]]
                delegate: Rectangle {
                  required property var modelData
                  width: 300; height: 84; radius: 14
                  color: Theme.field; border.color: Theme.separator
                  Rectangle {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 11; color: Theme.accent
                    Sym { anchors.centerIn: parent; name: modelData[0]; width: 20; height: 20; color: "#ffffff" }
                  }
                  Column {
                    x: 68; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 80
                    spacing: 3
                    Txt { text: modelData[1]; font.weight: Font.Bold }
                    Txt { text: modelData[2]; color: Theme.textDim; font.pixelSize: Theme.small; width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2 }
                  }
                }
              }
            }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Super works like ⌘ on a Mac: Super+W closes, Super+Q quits, Super+Tab switches."; color: Theme.textDim; font.pixelSize: Theme.small }
          }
        }

        // 5. Ready
        Item {
          width: stage.width; height: stage.height
          Column {
            anchors.centerIn: parent
            spacing: 16
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "You're all set"; font.pixelSize: 26; font.weight: Font.Bold }
            Grid {
              anchors.horizontalCenter: parent.horizontalCenter
              columns: 2; columnSpacing: 26; rowSpacing: 10
              Repeater {
                // What to press, then what it opens: two cells for each.
                model: ["Tap Super", "All your apps", "Super + Space", "Spotlight search", "Super + Tab", "Switch apps",
                        "Super + A", "Memora AI", "Click the clock", "Calendar and notifications", "Click the switches icon", "Control Center"]
                delegate: Txt {
                  required property var modelData; required property int index
                  text: modelData; font.weight: index % 2 === 0 ? Font.Bold : Font.Normal
                  color: index % 2 === 0 ? Theme.text : Theme.textDim
                }
              }
            }
          }
        }
      }
    }

    Item {
      id: footer
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
      height: 70
      Row {
        anchors.centerIn: parent
        spacing: 8
        Repeater { model: app.pages; delegate: Rectangle { required property int index; width: 7; height: 7; radius: 3.5; color: Theme.text; opacity: index === app.page ? 0.85 : 0.22 } }
      }
      Rectangle {
        visible: app.page > 0
        anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
        width: bt.implicitWidth + 28; height: 32; radius: 9; color: bh.hovered ? Theme.pressed : Theme.hover
        Txt { id: bt; anchors.centerIn: parent; text: "Back" }
        HoverHandler { id: bh }
        TapHandler { onTapped: app.page-- }
      }
      Rectangle {
        anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
        width: nt.implicitWidth + 32; height: 32; radius: 9; color: Theme.accent
        Txt { id: nt; anchors.centerIn: parent; text: app.page === app.pages - 1 ? "Start Using Memora" : "Continue"; color: "#ffffff"; font.weight: Font.Bold }
        TapHandler { onTapped: app.page === app.pages - 1 ? Qt.quit() : app.page++ }
      }
    }
  }
}
