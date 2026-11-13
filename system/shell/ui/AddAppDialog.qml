import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core

// A modal card to add any game, executable or downloaded script to the
// applications list (Launchpad, Spotlight) and create a desktop shortcut.
Item {
  id: root
  anchors.fill: parent
  z: 1000
  visible: shown || fade.running
  property bool shown: false

  property string targetPath: ""
  property string appName: ""
  property string appExec: ""
  property string appDir: ""
  property string appIcon: ""
  property string appCategory: "Game"
  property bool inTerminal: false
  property bool addToApps: true
  property bool addToDesktop: true

  signal done(string name, string execPath)
  signal cancelled()

  readonly property var categories: [
    { id: "Game", name: "Game", sym: "gamepad" },
    { id: "Utility", name: "Utility", sym: "gear" },
    { id: "Productivity", name: "Productivity", sym: "check" },
    { id: "Creativity", name: "Creativity", sym: "palette" },
    { id: "Development", name: "Dev", sym: "keyboard" },
    { id: "AudioVideo", name: "Media", sym: "play" }
  ]

  function open(path) {
    targetPath = path || ""
    if (targetPath) {
      inspectProc.command = ["memora-app-shortcut", "inspect", targetPath]
      inspectProc.running = true
    } else {
      appName = ""
      appExec = ""
      appDir = ""
      appIcon = "gamepad"
      appCategory = "Game"
      inTerminal = false
      addToApps = true
      addToDesktop = true
    }
    shown = true
    Qt.callLater(() => nameInput.forceActiveFocus())
  }

  function close() {
    shown = false
    cancelled()
  }

  function save() {
    if (!appName.trim() || !appExec.trim()) return
    const args = [
      "memora-app-shortcut", "create",
      "--name", appName.trim(),
      "--exec", appExec.trim(),
      "--dir", appDir.trim() || "",
      "--icon", appIcon || "",
      "--category", appCategory
    ]
    if (inTerminal) args.push("--terminal")
    if (addToApps) args.push("--app")
    if (addToDesktop) args.push("--desktop")

    saveProc.command = args
    saveProc.running = true
  }

  Process {
    id: inspectProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const j = JSON.parse(text)
          if (!j.error) {
            root.appName = j.name || ""
            root.appExec = j.exec || ""
            root.appDir = j.dir || ""
            root.appIcon = j.icon || (j.isGame ? "gamepad" : "application-x-executable")
            root.appCategory = j.category || (j.isGame ? "Game" : "Utility")
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: saveProc
    onExited: code => {
      if (code === 0) {
        root.shown = false
        root.done(root.appName, root.appExec)
      }
    }
  }

  // Browse executable with file dialog
  Process {
    id: browseExecProc
    command: ["bash", "-c", "zenity --file-selection --title=\"Select Game or Executable\" 2>/dev/null || true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const p = text.trim()
        if (p) {
          root.appExec = p
          if (!root.appDir) root.appDir = p.substring(0, p.lastIndexOf("/"))
          if (!root.appName) {
            const base = p.split("/").pop().replace(/\.[^/.]+$/, "")
            root.appName = base.charAt(0).toUpperCase() + base.slice(1)
          }
        }
      }
    }
  }

  // Browse working directory with folder dialog
  Process {
    id: browseDirProc
    command: ["bash", "-c", "zenity --file-selection --directory --title=\"Select Working Directory\" 2>/dev/null || true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const p = text.trim()
        if (p) root.appDir = p
      }
    }
  }

  // Browse icon image
  Process {
    id: browseIconProc
    command: ["bash", "-c", "zenity --file-selection --file-filter=\"Images (*.png *.svg *.ico)|*.png *.svg *.ico\" --title=\"Select Icon\" 2>/dev/null || true"]
    stdout: StdioCollector {
      onStreamFinished: {
        const p = text.trim()
        if (p) root.appIcon = p
      }
    }
  }

  Keys.onEscapePressed: close()
  Keys.onReturnPressed: if (appName.trim() && appExec.trim()) save()

  // Soft veil background
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25)
    opacity: root.shown ? 1 : 0
    Behavior on opacity { NumberAnimation { id: fade; duration: Theme.fast } }
    TapHandler { onTapped: root.close() }
  }

  // Dialog Card
  Glass {
    id: card
    anchors.centerIn: parent
    width: 440
    height: col.implicitHeight + 40
    radius: 20
    fill: Theme.dark ? Qt.rgba(0.14, 0.15, 0.18, 0.96) : Qt.rgba(0.99, 0.99, 1, 0.97)
    opacity: root.shown ? 1 : 0
    scale: 0.96 + 0.04 * (root.shown ? 1 : 0)
    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Theme.easingEmph } }
    TapHandler {}

    ColumnLayout {
      id: col
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
      spacing: 12

      // Header with preview icon
      RowLayout {
        Layout.fillWidth: true
        spacing: 14

        Item {
          width: 54; height: 54
          Rectangle {
            anchors.fill: parent
            radius: 14
            color: Theme.dark ? "#262832" : "#e8eaf0"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.15)
          }
          Image {
            id: iconPreview
            anchors.centerIn: parent
            width: 36; height: 36
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(72, 72)
            source: root.appIcon.startsWith("/")
              ? "file://" + root.appIcon
              : Quickshell.iconPath(root.appIcon || (root.appCategory === "Game" ? "gamepad" : "application-x-executable"))
          }
          Sym {
            visible: !iconPreview.status || iconPreview.status === Image.Error || !root.appIcon.startsWith("/")
            anchors.centerIn: parent
            name: root.appCategory === "Game" ? "gamepad" : "gear"
            width: 24; height: 24
            color: Theme.accent
          }
          Rectangle {
            anchors { right: parent.right; bottom: parent.bottom; margins: -3 }
            width: 18; height: 18; radius: 9
            color: Theme.accent
            Sym { anchors.centerIn: parent; name: "plus"; width: 10; height: 10; color: "#ffffff" }
            HoverHandler { id: iconHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: browseIconProc.running = true }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 2
          Txt {
            text: root.appCategory === "Game" ? "Add Game" : "Add Application"
            font.weight: Font.Bold
            font.pixelSize: Theme.fontSize + 3
          }
          Txt {
            text: "Create a shortcut for Launchpad and Desktop"
            color: Theme.textDim
            font.pixelSize: Theme.small
          }
        }
      }

      Rectangle { Layout.fillWidth: true; height: 1; color: Theme.separator }

      // Name Input
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        Txt { text: "Name"; font.weight: Font.Medium; font.pixelSize: Theme.small; color: Theme.textDim }
        Rectangle {
          Layout.fillWidth: true; height: 32; radius: 8
          color: Theme.field
          border.color: nameInput.activeFocus ? Theme.accent : Theme.separator
          border.width: nameInput.activeFocus ? 2 : 1
          TextInput {
            id: nameInput
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13
            text: root.appName
            onTextChanged: root.appName = text
            selectByMouse: true
            selectionColor: Theme.accent
            Txt {
              visible: !nameInput.text
              anchors { fill: parent; leftMargin: 0 }
              verticalAlignment: Text.AlignVCenter
              text: "e.g. Counter-Strike, Minecraft, Blender"
              color: Theme.textFaint
              font.pixelSize: 13
            }
          }
        }
      }

      // Executable Path Input
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        Txt { text: "Executable / Script / Game"; font.weight: Font.Medium; font.pixelSize: Theme.small; color: Theme.textDim }
        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Rectangle {
            Layout.fillWidth: true; height: 32; radius: 8
            color: Theme.field
            border.color: execInput.activeFocus ? Theme.accent : Theme.separator
            border.width: execInput.activeFocus ? 2 : 1
            TextInput {
              id: execInput
              anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
              verticalAlignment: TextInput.AlignVCenter
              color: Theme.text
              font.family: Theme.font; font.pixelSize: 12
              text: root.appExec
              onTextChanged: root.appExec = text
              selectByMouse: true
              selectionColor: Theme.accent
              clip: true
              Txt {
                visible: !execInput.text
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "Path to binary, AppImage, or .sh script"
                color: Theme.textFaint
                font.pixelSize: 12
              }
            }
          }
          Rectangle {
            width: 76; height: 32; radius: 8
            color: browseHover.hovered ? Theme.pressed : Theme.hover
            Txt { anchors.centerIn: parent; text: "Browse…"; font.pixelSize: Theme.small; font.weight: Font.Medium }
            HoverHandler { id: browseHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: browseExecProc.running = true }
          }
        }
      }

      // Working Directory
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        Txt { text: "Working Directory (optional)"; font.weight: Font.Medium; font.pixelSize: Theme.small; color: Theme.textDim }
        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Rectangle {
            Layout.fillWidth: true; height: 30; radius: 8
            color: Theme.field
            border.color: dirInput.activeFocus ? Theme.accent : Theme.separator
            border.width: dirInput.activeFocus ? 2 : 1
            TextInput {
              id: dirInput
              anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
              verticalAlignment: TextInput.AlignVCenter
              color: Theme.text
              font.family: Theme.font; font.pixelSize: 12
              text: root.appDir
              onTextChanged: root.appDir = text
              selectByMouse: true
              clip: true
              Txt {
                visible: !dirInput.text
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: "Game folder (defaults to executable location)"
                color: Theme.textFaint
                font.pixelSize: 12
              }
            }
          }
          Rectangle {
            width: 76; height: 30; radius: 8
            color: dirHover.hovered ? Theme.pressed : Theme.hover
            Txt { anchors.centerIn: parent; text: "Browse…"; font.pixelSize: Theme.small }
            HoverHandler { id: dirHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: browseDirProc.running = true }
          }
        }
      }

      // Category Pills
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 5
        Txt { text: "Category"; font.weight: Font.Medium; font.pixelSize: Theme.small; color: Theme.textDim }
        Flow {
          Layout.fillWidth: true
          spacing: 6
          Repeater {
            model: root.categories
            delegate: Rectangle {
              required property var modelData
              readonly property bool active: root.appCategory === modelData.id
              width: catRow.implicitWidth + 18; height: 26; radius: 13
              color: active ? Theme.accent : (catH.hovered ? Theme.pressed : Theme.hover)
              Row {
                id: catRow
                anchors.centerIn: parent
                spacing: 5
                Sym {
                  name: modelData.sym; width: 12; height: 12
                  color: parent.parent.active ? "#ffffff" : Theme.textDim
                  anchors.verticalCenter: parent.verticalCenter
                }
                Txt {
                  text: modelData.name
                  font.pixelSize: 11
                  font.weight: parent.parent.active ? Font.Bold : Font.Normal
                  color: parent.parent.active ? "#ffffff" : Theme.text
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
              HoverHandler { id: catH; cursorShape: Qt.PointingHandCursor }
              TapHandler {
                onTapped: {
                  root.appCategory = modelData.id
                  if (!root.appIcon || root.appIcon === "gamepad" || root.appIcon === "application-x-executable") {
                    root.appIcon = modelData.id === "Game" ? "gamepad" : "application-x-executable"
                  }
                }
              }
            }
          }
        }
      }

      // Options Checkboxes
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        Layout.topMargin: 2

        // Add to Applications
        RowLayout {
          spacing: 8
          Rectangle {
            width: 16; height: 16; radius: 4
            color: root.addToApps ? Theme.accent : Theme.field
            border.color: root.addToApps ? Theme.accent : Theme.separator
            Sym { visible: root.addToApps; anchors.centerIn: parent; name: "check"; width: 10; height: 10; color: "#ffffff" }
            TapHandler { onTapped: root.addToApps = !root.addToApps }
          }
          Txt { text: "Add to Applications (Launchpad & Spotlight)"; font.pixelSize: Theme.small; Layout.fillWidth: true }
        }

        // Add to Desktop
        RowLayout {
          spacing: 8
          Rectangle {
            width: 16; height: 16; radius: 4
            color: root.addToDesktop ? Theme.accent : Theme.field
            border.color: root.addToDesktop ? Theme.accent : Theme.separator
            Sym { visible: root.addToDesktop; anchors.centerIn: parent; name: "check"; width: 10; height: 10; color: "#ffffff" }
            TapHandler { onTapped: root.addToDesktop = !root.addToDesktop }
          }
          Txt { text: "Create Shortcut on Desktop"; font.pixelSize: Theme.small; Layout.fillWidth: true }
        }

        // Run in terminal
        RowLayout {
          spacing: 8
          Rectangle {
            width: 16; height: 16; radius: 4
            color: root.inTerminal ? Theme.accent : Theme.field
            border.color: root.inTerminal ? Theme.accent : Theme.separator
            Sym { visible: root.inTerminal; anchors.centerIn: parent; name: "check"; width: 10; height: 10; color: "#ffffff" }
            TapHandler { onTapped: root.inTerminal = !root.inTerminal }
          }
          Txt { text: "Run in Terminal (for command-line tools or text games)"; font.pixelSize: Theme.small; Layout.fillWidth: true }
        }
      }

      // Action Buttons
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 8
        spacing: 10

        Rectangle {
          Layout.fillWidth: true; height: 34; radius: 9
          color: cancelH.hovered ? Theme.pressed : Theme.hover
          Txt { anchors.centerIn: parent; text: "Cancel"; font.weight: Font.Medium }
          HoverHandler { id: cancelH; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.close() }
        }

        Rectangle {
          Layout.fillWidth: true; height: 34; radius: 9
          readonly property bool valid: root.appName.trim().length > 0 && root.appExec.trim().length > 0
          color: valid ? Theme.accent : (Theme.dark ? "#333644" : "#d0d4e0")
          opacity: valid ? 1 : 0.6
          Txt {
            anchors.centerIn: parent
            text: root.appCategory === "Game" ? "Add Game" : "Add Application"
            color: "#ffffff"
            font.weight: Font.Bold
          }
          HoverHandler { id: addH; cursorShape: parent.valid ? Qt.PointingHandCursor : Qt.ArrowCursor }
          TapHandler {
            enabled: parent.valid
            onTapped: root.save()
          }
        }
      }
    }
  }
}
