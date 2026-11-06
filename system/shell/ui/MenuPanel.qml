import QtQuick
import QtQuick.Layouts
import qs.core

// A dropdown menu card. items: [{ text, keys, enabled, checked, action } | { separator: true }]
Glass {
  id: m
  property var items: []
  signal picked(var item)
  radius: 12
  fill: Theme.glassStrong
  shadowSize: 24
  implicitWidth: Math.max(220, col.implicitWidth + 12)
  implicitHeight: col.implicitHeight + 10

  ColumnLayout {
    id: col
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 5 }
    spacing: 0
    Repeater {
      model: m.items
      delegate: Item {
        required property var modelData
        readonly property bool sep: !!modelData.separator
        readonly property bool on: modelData.enabled !== false
        Layout.fillWidth: true
        implicitHeight: sep ? 11 : 26
        implicitWidth: row.implicitWidth + 24

        Rectangle {
          visible: parent.sep
          anchors.centerIn: parent
          width: parent.width - 18; height: 1
          color: Theme.separator
        }
        Rectangle {
          id: hl
          visible: !parent.sep
          anchors.fill: parent
          radius: 6
          color: hover.hovered && parent.on ? Theme.accent : "transparent"
        }
        RowLayout {
          id: row
          visible: !parent.sep
          anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
          spacing: 24
          Txt {
            text: (modelData.checked ? "✓ " : "") + (modelData.text || "")
            color: hover.hovered && parent.parent.on ? Theme.accentText : (parent.parent.on ? Theme.text : Theme.textFaint)
            Layout.fillWidth: true
          }
          Txt {
            visible: !!modelData.keys
            text: modelData.keys || ""
            color: hover.hovered && parent.parent.on ? Qt.rgba(1, 1, 1, 0.8) : Theme.textDim
            font.pixelSize: Theme.small
          }
        }
        HoverHandler { id: hover }
        TapHandler {
          enabled: !parent.sep && parent.on
          onTapped: m.picked(modelData)
        }
      }
    }
  }
}
