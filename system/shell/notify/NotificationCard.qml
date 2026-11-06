import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications
import qs.core
import qs.ui

// One notification: app icon, app name and time, title, text, actions.
Glass {
  id: card
  required property var notif
  property bool banner: true
  signal done()

  radius: 18
  fill: Theme.glassStrong
  shadowSize: banner ? 26 : 10
  width: 360
  implicitHeight: col.implicitHeight + 24

  readonly property string iconSource: {
    if (notif.image) return notif.image
    if (notif.appIcon) return notif.appIcon.indexOf("/") === 0 ? "file://" + notif.appIcon : Quickshell.iconPath(notif.appIcon, "dialog-information")
    return Quickshell.iconPath(Apps.iconNameFor(notif.desktopEntry || ""), "dialog-information")
  }

  RowLayout {
    id: col
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
    spacing: 11
    Image {
      Layout.alignment: Qt.AlignTop
      Layout.preferredWidth: 36; Layout.preferredHeight: 36
      source: card.iconSource
      sourceSize: Qt.size(72, 72)
      fillMode: Image.PreserveAspectFit
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 1
      RowLayout {
        Layout.fillWidth: true
        Txt { Layout.fillWidth: true; text: card.notif.summary || card.notif.appName; font.weight: Font.Bold; font.pixelSize: Theme.small + 1 }
        Txt { text: Notifs.ago(Notifs.timeOf(card.notif)); color: Theme.textDim; font.pixelSize: Theme.small - 1 }
      }
      Txt {
        Layout.fillWidth: true
        visible: text !== ""
        text: card.notif.body
        textFormat: Text.StyledText
        wrapMode: Text.Wrap
        maximumLineCount: card.banner ? 3 : 6
        color: Theme.text
        opacity: 0.85
        font.pixelSize: Theme.small + 0.5
      }
      Flow {
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 6
        visible: card.notif.actions.length > 0
        Repeater {
          model: card.notif.actions
          delegate: Rectangle {
            required property var modelData
            width: at.implicitWidth + 20; height: 26; radius: 8
            color: ah.hovered ? Theme.pressed : Theme.hover
            Txt { id: at; anchors.centerIn: parent; text: modelData.text; font.pixelSize: Theme.small }
            HoverHandler { id: ah }
            TapHandler { onTapped: { modelData.invoke(); card.done() } }
          }
        }
      }
    }
  }

  // Close button, top-left, on hover.
  Rectangle {
    visible: hov.hovered
    x: -6; y: -6; width: 20; height: 20; radius: 10
    color: Theme.glassSolid
    border.color: Theme.separator
    Sym { anchors.centerIn: parent; name: "close"; width: 9; height: 9; color: Theme.textDim }
    TapHandler { onTapped: card.notif.dismiss() }
  }

  HoverHandler { id: hov }
  TapHandler {
    onTapped: {
      const def = card.notif.actions.find(a => a.identifier === "default")
      if (def) def.invoke()
      card.notif.dismiss()
    }
  }
}
