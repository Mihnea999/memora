import QtQuick
import QtQuick.Layouts
import qs.core

// Colour & Symbol for a folder, as on a Mac: pick a colour, and a symbol to
// engrave on its front. Changes show on the folder at once; Done closes.
Glass {
  id: s
  property string path: ""
  property bool solid: true
  signal done()
  fill: solid ? Theme.popover : Theme.glassStrong
  radius: Theme.radiusLarge
  width: 368
  height: 470

  readonly property var look: Folders.lookOf(path)
  readonly property string color: look ? look.color : "blue"
  readonly property string symbol: look ? look.symbol : ""
  readonly property string name: path.split("/").pop()
  property string query: ""
  function focusSearch() { field.forceActiveFocus() }
  function glyphUrl(n, ink) {
    return "data:image/svg+xml;utf8," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"><path d="' + Folders.glyph(n) + '" fill="' + ink + '"/></svg>')
  }
  onPathChanged: { query = ""; field.text = ""; grid.contentY = 0 }

  // Keys: Escape or Return closes.
  Keys.onEscapePressed: s.done()

  ColumnLayout {
    anchors { fill: parent; margins: 16 }
    spacing: 12

    RowLayout {
      spacing: 12
      Image {
        Layout.preferredWidth: 72; Layout.preferredHeight: 72
        sourceSize: Qt.size(144, 144)
        source: Folders.url(s.color, s.symbol)
      }
      ColumnLayout {
        spacing: 2
        Layout.fillWidth: true
        Txt { text: s.name; font.pixelSize: Theme.large; font.weight: Font.DemiBold; Layout.fillWidth: true }
        Txt { text: "Colour & Symbol"; color: Theme.textDim; font.pixelSize: Theme.small }
      }
    }

    // Colours
    Flow {
      Layout.fillWidth: true
      spacing: 4
      Repeater {
        model: Folders.colorNames
        delegate: Item {
          id: sw
          required property string modelData
          width: 23; height: 23
          Rectangle {
            anchors.centerIn: parent
            width: 23; height: 23; radius: 12
            color: "transparent"
            border.width: 2
            border.color: s.color === parent.modelData ? Theme.accent : "transparent"
          }
          Rectangle {
            anchors.centerIn: parent
            width: 17; height: 17; radius: 9
            gradient: Gradient {
              GradientStop { position: 0; color: Folders.tints[sw.modelData][2] }
              GradientStop { position: 1; color: Folders.tints[sw.modelData][1] }
            }
            scale: dot.hovered ? 1.12 : 1
            Behavior on scale { NumberAnimation { duration: Theme.fast } }
          }
          HoverHandler { id: dot; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: Folders.set(s.path, parent.modelData, s.symbol) }
          Tip { text: parent.modelData.charAt(0).toUpperCase() + parent.modelData.slice(1) }
        }
      }
    }

    // Search
    Rectangle {
      Layout.fillWidth: true
      height: 28; radius: 8
      color: Theme.field
      border.color: field.activeFocus ? Theme.accent : Theme.separator
      Sym { name: "search"; width: 12; height: 12; color: Theme.textDim; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
      TextInput {
        id: field
        clip: true
        anchors { left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 8; verticalCenter: parent.verticalCenter }
        color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
        selectByMouse: true
        onTextChanged: s.query = text
        Keys.onEscapePressed: { if (text) text = ""; else s.done() }
        Keys.onReturnPressed: { const r = Folders.search(s.query); if (s.query && r.length) Folders.set(s.path, s.color, r[0]); s.done() }
        Txt { visible: !field.text; text: "Search symbols"; color: Theme.textFaint; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
      }
    }

    // Symbols: none first, then by group (or what the search found).
    GridView {
      id: grid
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      cellWidth: Math.floor(width / 8); cellHeight: cellWidth
      boundsBehavior: Flickable.StopAtBounds
      model: [""].concat(Folders.search(s.query))
      delegate: Item {
        required property string modelData
        width: grid.cellWidth; height: grid.cellHeight
        readonly property bool on: s.symbol === modelData
        Rectangle {
          anchors { fill: parent; margins: 2 }
          radius: 8
          color: parent.on ? Theme.accent : (cellHover.hovered ? Theme.hover : "transparent")
        }
        Image {
          visible: parent.modelData !== ""
          anchors.centerIn: parent
          width: 20; height: 20
          sourceSize: Qt.size(40, 40)
          source: visible ? s.glyphUrl(parent.modelData, parent.on ? "#ffffff" : Theme.text) : ""
        }
        // No symbol: a slashed circle.
        Rectangle {
          visible: parent.modelData === ""
          anchors.centerIn: parent
          width: 18; height: 18; radius: 9
          color: "transparent"
          border.width: 1.5
          border.color: parent.on ? "#ffffff" : Theme.textDim
          Rectangle { anchors.centerIn: parent; width: 1.5; height: 22; rotation: 45; color: parent.border.color }
        }
        HoverHandler { id: cellHover }
        TapHandler { onTapped: Folders.set(s.path, s.color, parent.modelData) }
      }
      Txt {
        anchors.centerIn: parent
        visible: grid.count <= 1
        text: "No symbols match"
        color: Theme.textDim
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: 8
      Item { Layout.fillWidth: true }
      Rectangle {
        visible: s.look !== null
        implicitWidth: resetLabel.implicitWidth + 24; implicitHeight: 28; radius: 8
        color: resetHover.hovered ? Theme.pressed : Theme.field
        Txt { id: resetLabel; anchors.centerIn: parent; text: "Reset" }
        HoverHandler { id: resetHover }
        TapHandler { onTapped: Folders.set(s.path, "", "") }
      }
      Rectangle {
        implicitWidth: doneLabel.implicitWidth + 28; implicitHeight: 28; radius: 8
        color: Theme.accent
        opacity: doneHover.hovered ? 0.88 : 1
        Txt { id: doneLabel; anchors.centerIn: parent; text: "Done"; color: Theme.accentText; font.weight: Font.Medium }
        HoverHandler { id: doneHover }
        TapHandler { onTapped: s.done() }
      }
    }
  }
}
