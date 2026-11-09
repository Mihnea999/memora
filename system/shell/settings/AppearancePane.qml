import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  title: "Appearance"
  Kit.Group {
    Item {
      Layout.fillWidth: true
      implicitHeight: 170
      Row {
        anchors.centerIn: parent
        spacing: 26
        Repeater {
          model: [{ id: "light", name: "Light" }, { id: "dark", name: "Dark" }]
          delegate: Column {
            required property var modelData
            spacing: 8
            Rectangle {
              width: 150; height: 96; radius: 10
              border.width: Theme.mode === modelData.id ? 3 : 1
              border.color: Theme.mode === modelData.id ? Theme.accent : Theme.separator
              clip: true
              Image { anchors.fill: parent; anchors.margins: 3; source: "file://" + Theme.wallpaperFor(modelData.id); sourceSize: Qt.size(300, 190); fillMode: Image.PreserveAspectCrop }
              Rectangle { x: 14; y: 16; width: 74; height: 50; radius: 6; color: modelData.id === "dark" ? "#2a2a2e" : "#ffffff"; opacity: 0.92
                Row { x: 6; y: 6; spacing: 3; Repeater { model: ["#ff5f57", "#febc2e", "#28c840"]; delegate: Rectangle { required property string modelData; width: 5; height: 5; radius: 2.5; color: modelData } } } }
              TapHandler { onTapped: Quickshell.execDetached(["memora-theme", "set", modelData.id]) }
            }
            Txt { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.name; font.weight: Theme.mode === modelData.id ? Font.Bold : Font.Normal }
          }
        }
      }
    }
  }
  Kit.Group {
    header: "Liquid Glass"
    // A live sample of the glass over your desktop picture.
    Item {
      Layout.fillWidth: true
      implicitHeight: 150
      Rectangle {
        id: sample
        anchors { fill: parent; margins: 10 }
        radius: 10
        clip: true
        color: "transparent"
        Image {
          id: pic
          anchors.fill: parent
          source: "file://" + Theme.wallpaper; sourceSize: Qt.size(640, 400); fillMode: Image.PreserveAspectCrop
          visible: false
        }
        MultiEffect { anchors.fill: parent; source: pic }
        Item {
          id: under
          anchors.centerIn: parent
          width: 340; height: 84
          clip: true
          MultiEffect {
            x: -under.x; y: -under.y
            width: sample.width; height: sample.height
            source: pic
            blurEnabled: !Prefs.reduceTransparency
            blur: Prefs.blur; blurMax: 48
            saturation: Prefs.vibrancy * 0.5
          }
        }
        Glass {
          anchors.fill: under
          radius: 16
          fill: Theme.glassStrong
          shadowSize: 18
          RowLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 12
            Rectangle { Layout.preferredWidth: 44; Layout.preferredHeight: 44; radius: 11; color: Theme.accent
              Sym { anchors.centerIn: parent; name: "sparkle"; width: 22; height: 22; color: "#ffffff" } }
            ColumnLayout {
              spacing: 2
              Txt { text: "Memora"; font.weight: Font.Bold }
              Txt { text: "Live preview of your glass"; color: Theme.textDim; font.pixelSize: Theme.small }
            }
          }
        }
      }
    }
    Kit.Row {
      label: "Style"
      enabled: !Prefs.reduceTransparency; opacity: enabled ? 1 : 0.4
      Kit.Choice { value: Prefs.glassStyle; options: [{ text: "Clear", value: "clear" }, { text: "Tinted", value: "tinted" }]; onPicked: v => Prefs.set("glassStyle", v) }
    }
    Kit.Row {
      label: "Transparency"
      enabled: !Prefs.reduceTransparency; opacity: enabled ? 1 : 0.4
      Slider { implicitWidth: 200; sym: "sun"; value: Prefs.transparency; onMoved: v => Prefs.set("transparency", Math.round(v * 20) / 20) }
    }
    Kit.Row {
      label: "Frost"
      enabled: !Prefs.reduceTransparency; opacity: enabled ? 1 : 0.4
      Slider { implicitWidth: 200; sym: "drop"; value: Prefs.blur; onMoved: v => Prefs.set("blur", Math.round(v * 20) / 20) }
    }
    Kit.Row {
      label: "Colour through glass"
      enabled: !Prefs.reduceTransparency; opacity: enabled ? 1 : 0.4
      Slider { implicitWidth: 200; sym: "palette"; value: Prefs.vibrancy; onMoved: v => Prefs.set("vibrancy", Math.round(v * 20) / 20) }
    }
    Kit.Row {
      label: "Edge light"
      Slider { implicitWidth: 200; sym: "sparkle"; value: Prefs.shine; onMoved: v => Prefs.set("shine", Math.round(v * 20) / 20) }
    }
    Kit.Row { label: "Transparent menu bar"; Kit.Switch { checked: Prefs.menuBarTransparent; onToggled: on => Prefs.set("menuBarTransparent", on) } }
    Kit.Row {
      label: "Reduce transparency"; last: true
      Kit.Switch { checked: Prefs.reduceTransparency; onToggled: on => Prefs.set("reduceTransparency", on) }
    }
  }
  Kit.Group {
    Kit.Row {
      label: "Accent colour"; last: true
      Row {
        spacing: 9
        Repeater {
          model: ["blue", "purple", "pink", "red", "orange", "green", "graphite"]
          delegate: Rectangle {
            required property string modelData
            readonly property bool on: Prefs.accent === modelData
            width: 20; height: 20; radius: 10
            color: Theme.accents[modelData][Theme.dark ? 0 : 1]
            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15)
            Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; color: "#ffffff"; visible: parent.on }
            scale: ah.hovered ? 1.12 : 1
            Behavior on scale { NumberAnimation { duration: Theme.fast } }
            HoverHandler { id: ah; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Prefs.set("accent", modelData) }
          }
        }
      }
    }
  }
}
