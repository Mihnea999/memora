import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs.core
import qs.ui

// Modal Liquid Glass sheet for adding games or applications, configuring Proton
// versions (Proton GE, Proton Experimental, Wine), creating desktop shortcuts,
// and 1-click launching for non-Linux users.
PanelWindow {
  id: win
  screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
  // While a file is being chosen the sheet goes under the windows, or it would
  // cover the file chooser (it is above everything otherwise).
  property bool picking: false
  visible: Shell.addAppOpen || anim.running
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  WlrLayershell.layer: picking ? WlrLayer.Bottom : WlrLayer.Overlay
  WlrLayershell.namespace: "memora-dialog"
  WlrLayershell.keyboardFocus: Shell.addAppOpen && !picking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  property real shown: Shell.addAppOpen ? 1 : 0
  Behavior on shown { NumberAnimation { id: anim; duration: Theme.normal; easing.type: Theme.easing } }

  property string targetPath: Shell.addAppPath
  property string appName: ""
  property string appExec: ""
  property string appDir: ""
  property string appIcon: "applications-games"
  property string appCategory: "Game"
  property bool isWindowsExe: false
  property var runners: []
  property string selectedRunner: "auto"
  property bool inTerminal: false
  property bool addToApps: true
  property bool addToDesktop: true

  onTargetPathChanged: inspect(targetPath)
  Connections {
    target: Shell
    function onAddAppOpenChanged() {
      win.picking = false
      if (Shell.addAppOpen) {
        inspect(Shell.addAppPath)
      }
    }
  }

  function inspect(path) {
    targetPath = path || ""
    if (targetPath) {
      inspectProc.command = ["memora-proton", "inspect", targetPath]
      inspectProc.running = true
    } else {
      appName = ""
      appExec = ""
      appDir = ""
      appIcon = "applications-games"
      appCategory = "Game"
      isWindowsExe = false
      runners = []
      selectedRunner = "auto"
      inTerminal = false
      addToApps = true
      addToDesktop = true
      // Fetch runners in background anyway
      runnersProc.running = true
    }
  }

  function save(andPlay) {
    if (!appName.trim() || !appExec.trim()) return
    if (isWindowsExe) {
      const args = [
        "memora-proton", "create",
        "--name", appName.trim(),
        "--exec", appExec.trim(),
        "--runner", selectedRunner || "auto",
        "--dir", appDir.trim() || "",
        "--icon", appIcon || ""
      ]
      if (addToApps) args.push("--app")
      if (addToDesktop) args.push("--desktop")
      saveProc.command = args
      saveProc.running = true

      if (andPlay) {
        Quickshell.execDetached(["memora-proton", "run", "--runner", selectedRunner || "auto", appExec.trim()])
        Shell.closeAddApp()
      }
    } else {
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

      if (andPlay) {
        Quickshell.execDetached(["memora-app-shortcut", "launch", appExec.trim()])
        Shell.closeAddApp()
      }
    }
  }

  Process {
    id: runnersProc
    command: ["memora-proton", "runners"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const list = JSON.parse(text)
          if (Array.isArray(list)) {
            win.runners = list
            if (list.length && win.selectedRunner === "auto") {
              const rec = list.find(r => r.recommended) || list[0]
              win.selectedRunner = rec.id
            }
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: inspectProc
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const j = JSON.parse(text)
          if (!j.error) {
            win.appName = j.name || ""
            win.appExec = j.exec || ""
            win.appDir = j.dir || ""
            win.appIcon = j.icon || (j.isWindowsExe ? "applications-games" : "application-x-executable")
            win.appCategory = j.category || (j.isWindowsExe ? "Game" : "Utility")
            win.isWindowsExe = !!j.isWindowsExe
            if (Array.isArray(j.runners) && j.runners.length) {
              win.runners = j.runners
              win.selectedRunner = j.recommendedRunner || (j.runners[0] ? j.runners[0].id : "auto")
            } else {
              runnersProc.running = true
            }
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: saveProc
    onExited: code => {
      if (code === 0) {
        Shell.closeAddApp()
      }
    }
  }

  // The system's file chooser, as in the other apps.
  function local(url) { return decodeURIComponent(String(url).replace(/^file:\/\//, "")) }
  FileDialog {
    id: browseExec
    title: "Choose an Application or Game"
    currentFolder: "file://" + (win.appDir || Quickshell.env("HOME"))
    onAccepted: { win.picking = false; win.inspect(win.local(selectedFile)) }
    onRejected: win.picking = false
  }
  FileDialog {
    id: browseIcon
    title: "Choose an Icon"
    currentFolder: "file://" + (win.appDir || Quickshell.env("HOME"))
    nameFilters: ["Pictures (*.png *.svg *.ico *.jpg *.jpeg *.webp)"]
    onAccepted: { win.picking = false; win.appIcon = win.local(selectedFile) }
    onRejected: win.picking = false
  }

  // Soft frosted backdrop. Clicking outside closes the sheet.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.22)
    opacity: win.shown
    TapHandler {
      onTapped: ev => {
        const p = card.mapFromItem(null, ev.scenePosition.x, ev.scenePosition.y)
        if (!card.contains(p)) Shell.closeAddApp()
      }
    }
  }

  // Liquid Glass Modal Card
  Glass {
    id: card
    anchors.centerIn: parent
    width: 480
    height: col.implicitHeight + 44
    radius: 22
    // A form to read and fill in: frosted, like the menus.
    fill: Theme.menuGlass
    frost: Math.max(Prefs.blur, 0.6)
    opacity: win.shown
    scale: 0.94 + 0.06 * win.shown
    focus: true
    Keys.onEscapePressed: Shell.closeAddApp()
    Keys.onReturnPressed: win.save(false)

    ColumnLayout {
      id: col
      x: 24; y: 22; width: parent.width - 48
      spacing: 14

      // Header row with Icon, Name, and Auto-Detect Badge
      RowLayout {
        Layout.fillWidth: true
        spacing: 14

        // Icon preview squircle with edit badge
        Item {
          width: 58; height: 58
          Rectangle {
            anchors.fill: parent
            radius: 15
            color: Theme.field
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
          }
          Image {
            id: iconImg
            anchors.centerIn: parent
            width: 40; height: 40
            fillMode: Image.PreserveAspectFit
            source: {
              if (!win.appIcon) return ""
              if (win.appIcon.startsWith("/")) return "file://" + win.appIcon
              return Quickshell.iconPath(win.appIcon, true)   // "" when the theme has none: the glyph below shows
            }
            visible: status === Image.Ready
          }
          Sym {
            visible: !iconImg.visible
            anchors.centerIn: parent
            name: win.isWindowsExe || win.appCategory === "Game" ? "gamepad" : "gear"
            width: 26; height: 26
            color: Theme.accent
          }
          // Small browse icon button
          Rectangle {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: -3; bottomMargin: -3 }
            width: 20; height: 20; radius: 10
            color: Theme.accent
            border.width: 1.5; border.color: Theme.dark ? "#1c1c1e" : "#ffffff"
            Sym { anchors.centerIn: parent; name: "plus"; width: 10; height: 10; color: "#ffffff" }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { win.picking = true; browseIcon.open() } }
            Tip { text: "Change Icon Image…" }
          }
        }

        // Title and Game badge
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 3

          Rectangle {
            Layout.fillWidth: true
            height: 32; radius: 8
            color: nameInput.activeFocus ? Theme.field : "transparent"
            border.width: 1; border.color: nameInput.activeFocus ? Theme.accent : "transparent"
            TextInput {
              id: nameInput
              anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
              verticalAlignment: TextInput.AlignVCenter
              color: Theme.text
              font.family: Theme.font; font.pixelSize: Theme.large + 1; font.weight: Font.DemiBold
              selectByMouse: true
              text: win.appName
              onTextChanged: win.appName = text
              Txt {
                visible: !nameInput.text
                anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left
                text: "Game or App Name"
                color: Theme.textFaint
                font.pixelSize: Theme.large + 1; font.weight: Font.DemiBold
              }
            }
          }

          // Badge: Windows Game or Linux App
          RowLayout {
            spacing: 6
            Sym {
              name: win.isWindowsExe ? "gamepad" : "file"
              width: 12; height: 12
              color: win.isWindowsExe ? Theme.accent : Theme.textDim
            }
            Txt {
              text: win.isWindowsExe ? "Windows Game (.exe)" : "Application / Executable"
              color: win.isWindowsExe ? Theme.accent : Theme.textDim
              font.pixelSize: Theme.small
              font.weight: Font.Medium
            }
            Rectangle {
              visible: win.isWindowsExe
              radius: 5
              color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
              implicitWidth: autoBadge.implicitWidth + 8; implicitHeight: 16
              Txt {
                id: autoBadge
                anchors.centerIn: parent
                text: "Proton Auto-Config"
                color: Theme.accent
                font.pixelSize: Theme.small - 1
                font.weight: Font.Bold
              }
            }
          }
        }
      }

      // Proton Compatibility Section (Automatic, zero configuration)
      Rectangle {
        Layout.fillWidth: true
        visible: win.isWindowsExe || win.runners.length > 0
        radius: 12
        color: Theme.dark ? Qt.rgba(0.08, 0.08, 0.10, 0.5) : Qt.rgba(0.94, 0.94, 0.96, 0.6)
        border.width: 1; border.color: Theme.separator
        implicitHeight: protonCol.implicitHeight + 20

        ColumnLayout {
          id: protonCol
          anchors { fill: parent; margins: 10 }
          spacing: 8

          RowLayout {
            Layout.fillWidth: true
            Sym { name: "gear"; width: 13; height: 13; color: Theme.accent }
            Txt { text: "Proton Version"; font.weight: Font.DemiBold; font.pixelSize: Theme.small + 0.5 }
            Item { Layout.fillWidth: true }
            Txt {
              text: "+ Get More Protons… (ProtonPlus)"
              color: Theme.accent
              font.pixelSize: Theme.small - 0.5
              font.weight: Font.Medium
              HoverHandler { id: ppHov; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: Quickshell.execDetached(["protonplus"]) }
              opacity: ppHov.hovered ? 0.8 : 1
            }
          }

          // Runner selector pills
          Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
              model: win.runners
              delegate: Rectangle {
                id: rPill
                required property var modelData
                readonly property bool chosen: win.selectedRunner === modelData.id
                implicitWidth: rRow.implicitWidth + 14
                implicitHeight: 26
                radius: 13
                color: chosen ? Theme.accent : (rpHov.hovered ? Theme.pressed : Theme.field)
                border.width: 1; border.color: chosen ? Theme.accent : Theme.separator
                Behavior on color { ColorAnimation { duration: Theme.fast } }

                Row {
                  id: rRow
                  anchors.centerIn: parent
                  spacing: 4
                  Txt {
                    text: rPill.modelData.name
                    color: rPill.chosen ? "#ffffff" : Theme.text
                    font.weight: rPill.chosen ? Font.Bold : Font.Normal
                    font.pixelSize: Theme.small
                  }
                  Rectangle {
                    visible: rPill.modelData.recommended || rPill.modelData.is_ge
                    radius: 4
                    color: rPill.chosen ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                    implicitWidth: recText.implicitWidth + 6; implicitHeight: 14
                    anchors.verticalCenter: parent.verticalCenter
                    Txt {
                      id: recText
                      anchors.centerIn: parent
                      text: rPill.modelData.is_ge ? "GE" : "Rec"
                      color: rPill.chosen ? "#ffffff" : Theme.accent
                      font.pixelSize: 9
                      font.weight: Font.Bold
                    }
                  }
                }
                HoverHandler { id: rpHov; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.selectedRunner = rPill.modelData.id }
              }
            }
          }

          // Friendly automatic note
          Txt {
            Layout.fillWidth: true
            text: "Each game runs isolated in its own prefix (~/.local/share/memora/prefixes/). No configuration required."
            color: Theme.textDim
            font.pixelSize: Theme.small - 1.5
            wrapMode: Text.Wrap
          }
        }
      }

      // Executable Path Row (with Browse button)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        Txt { text: "Executable File"; font.pixelSize: Theme.small; color: Theme.textDim; font.weight: Font.Medium }
        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          Rectangle {
            Layout.fillWidth: true
            height: 30; radius: 8
            color: Theme.field
            border.width: 1; border.color: execInput.activeFocus ? Theme.accent : Theme.separator
            TextInput {
              id: execInput
              anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
              verticalAlignment: TextInput.AlignVCenter
              color: Theme.text
              font.family: Theme.font; font.pixelSize: Theme.small
              selectByMouse: true
              text: win.appExec
              onTextChanged: win.appExec = text
              clip: true
            }
          }
          Rectangle {
            implicitWidth: 80; height: 30; radius: 8
            color: bHov.hovered ? Theme.pressed : Theme.field
            border.width: 1; border.color: Theme.separator
            Txt { anchors.centerIn: parent; text: "Browse…"; font.pixelSize: Theme.small; font.weight: Font.Medium }
            HoverHandler { id: bHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { win.picking = true; browseExec.open() } }
          }
        }
      }

      // Options checkboxes
      RowLayout {
        Layout.fillWidth: true
        spacing: 16

        // Add to Applications
        Row {
          spacing: 7
          Rectangle {
            width: 18; height: 18; radius: 5
            color: win.addToApps ? Theme.accent : Theme.field
            border.width: 1; border.color: win.addToApps ? Theme.accent : Theme.separator
            anchors.verticalCenter: parent.verticalCenter
            Sym { visible: win.addToApps; anchors.centerIn: parent; name: "check"; width: 10; height: 10; color: "#ffffff" }
          }
          Txt { text: "Add to Applications"; font.pixelSize: Theme.small; anchors.verticalCenter: parent.verticalCenter }
          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: win.addToApps = !win.addToApps }
        }

        // Add to Desktop
        Row {
          spacing: 7
          Rectangle {
            width: 18; height: 18; radius: 5
            color: win.addToDesktop ? Theme.accent : Theme.field
            border.width: 1; border.color: win.addToDesktop ? Theme.accent : Theme.separator
            anchors.verticalCenter: parent.verticalCenter
            Sym { visible: win.addToDesktop; anchors.centerIn: parent; name: "check"; width: 10; height: 10; color: "#ffffff" }
          }
          Txt { text: "Add to Desktop"; font.pixelSize: Theme.small; anchors.verticalCenter: parent.verticalCenter }
          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: win.addToDesktop = !win.addToDesktop }
        }
      }

      // Action Buttons
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 10

        Btn {
          text: "Cancel"
          implicitWidth: 84
          onClicked: Shell.closeAddApp()
        }

        Item { Layout.fillWidth: true }

        Btn {
          visible: win.isWindowsExe
          text: "Play Now"
          sym: "play"
          implicitWidth: 100
          onClicked: win.save(true)
        }

        Btn {
          text: win.isWindowsExe ? "Add Game" : "Add Application"
          sym: "plus"
          primary: true
          implicitWidth: 120
          onClicked: win.save(false)
        }
      }
    }
  }

  component Btn: Rectangle {
    id: b
    property string text
    property string sym: ""
    property bool primary: false
    signal clicked()
    implicitHeight: 32; radius: 9
    color: primary ? Theme.accent : (bh.hovered ? Theme.pressed : Theme.field)
    border.width: 1; border.color: primary ? Theme.accent : Theme.separator
    opacity: primary && bh.hovered ? 0.9 : 1
    scale: bp.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.fast } }

    Row {
      anchors.centerIn: parent
      spacing: 6
      Sym {
        visible: b.sym !== ""
        name: b.sym; width: 12; height: 12
        color: b.primary ? "#ffffff" : Theme.text
        anchors.verticalCenter: parent.verticalCenter
      }
      Txt {
        text: b.text
        color: b.primary ? "#ffffff" : Theme.text
        font.weight: b.primary ? Font.Bold : Font.Medium
        font.pixelSize: Theme.small + 0.5
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: bp; onTapped: b.clicked() }
  }
}
