import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.ui

// Launchpad: every app on a frosted full-screen sheet, in pages, with search.
PanelWindow {
  id: lp
  required property var modelData
  screen: modelData
  readonly property bool open: Shell.open === "launchpad"

  visible: open || fade.running
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "memora-launchpad"
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  color: "transparent"

  property real shown: open ? 1 : 0
  Behavior on shown { NumberAnimation { id: fade; duration: Theme.normal; easing.type: Theme.easing } }

  readonly property int cols: 7
  readonly property int rows: 5
  readonly property int perPage: cols * rows
  property string query: ""
  readonly property var apps: {
    const q = query.toLowerCase()
    const list = Apps.all.filter(e => e.id !== "memora-launchpad")
    if (!q) return list
    return list.filter(e => e.name.toLowerCase().indexOf(q) >= 0 || (e.genericName || "").toLowerCase().indexOf(q) >= 0)
  }
  readonly property int pages: Math.max(1, Math.ceil(apps.length / perPage))
  property int page: 0

  onOpenChanged: if (open) { query = ""; search.text = ""; page = 0; search.forceActiveFocus() }

  Rectangle {
    anchors.fill: parent
    color: Theme.dark ? Qt.rgba(0.03, 0.03, 0.05, 0.42) : Qt.rgba(0.95, 0.95, 0.97, 0.30)
    opacity: lp.shown
  }

  // Click on empty space closes.
  TapHandler { onTapped: Shell.close() }

  Item {
    anchors.fill: parent
    opacity: lp.shown
    scale: 1.06 - 0.06 * lp.shown

    // Search
    Glass {
      id: searchBox
      anchors.horizontalCenter: parent.horizontalCenter
      y: 70
      width: 280; height: 34
      radius: 10
      fill: Theme.field
      shadow: false
      Sym { name: "search"; width: 13; height: 13; color: Theme.textDim; anchors { left: parent.left; leftMargin: 11; verticalCenter: parent.verticalCenter } }
      TextInput {
        id: search
        anchors { left: parent.left; right: parent.right; leftMargin: 32; rightMargin: 10; verticalCenter: parent.verticalCenter }
        color: Theme.text
        font.family: Theme.font; font.pixelSize: Theme.fontSize
        selectionColor: Theme.accent
        onTextChanged: { lp.query = text; lp.page = 0 }
        Keys.onEscapePressed: Shell.close()
        Keys.onReturnPressed: if (lp.apps.length) { Apps.launch(lp.apps[0].id); Shell.close() }
        Keys.onRightPressed: lp.page = Math.min(lp.pages - 1, lp.page + 1)
        Keys.onLeftPressed: lp.page = Math.max(0, lp.page - 1)
        Txt { visible: !search.text; text: "Search"; color: Theme.textFaint; anchors.verticalCenter: parent.verticalCenter }
      }
    }

    // Pages
    Item {
      id: pager
      anchors { top: searchBox.bottom; topMargin: 50; bottom: dots.top; bottomMargin: 30 }
      width: Math.min(parent.width - 160, 1280)
      anchors.horizontalCenter: parent.horizontalCenter
      clip: true

      Row {
        x: -lp.page * pager.width
        Behavior on x { NumberAnimation { duration: Theme.slow; easing.type: Theme.easingEmph } }
        Repeater {
          model: lp.pages
          delegate: Grid {
            required property int index
            width: pager.width; height: pager.height
            columns: lp.cols
            readonly property real cellW: pager.width / lp.cols
            readonly property real cellH: pager.height / lp.rows
            Repeater {
              model: lp.apps.slice(index * lp.perPage, (index + 1) * lp.perPage)
              delegate: Item {
                required property var modelData
                width: parent.cellW; height: parent.cellH
                AppIcon {
                  id: ic
                  appId: modelData.id
                  width: Math.min(96, parent.width * 0.62); height: width
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.top: parent.top; anchors.topMargin: (parent.height - height - 34) / 2
                  scale: tap.pressed ? 0.9 : (hov.hovered ? 1.04 : 1)
                  Behavior on scale { NumberAnimation { duration: Theme.fast } }
                }
                Txt {
                  anchors { top: ic.bottom; topMargin: 8; horizontalCenter: parent.horizontalCenter }
                  width: parent.width - 12
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData.name
                  font.pixelSize: Theme.small + 0.5
                  color: Theme.dark ? "#ffffff" : "#1c1c1e"
                  style: Theme.dark ? Text.Raised : Text.Normal
                  styleColor: Qt.rgba(0, 0, 0, 0.35)
                }
                HoverHandler { id: hov }
                TapHandler { id: tap; onTapped: { Apps.launch(modelData.id); Shell.close() } }
              }
            }
          }
        }
      }

      WheelHandler {
        onWheel: ev => {
          const d = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x
          if (d < 0) lp.page = Math.min(lp.pages - 1, lp.page + 1)
          else if (d > 0) lp.page = Math.max(0, lp.page - 1)
        }
      }
    }

    // Page dots
    Row {
      id: dots
      anchors { bottom: parent.bottom; bottomMargin: 120; horizontalCenter: parent.horizontalCenter }
      spacing: 10
      visible: lp.pages > 1
      Repeater {
        model: lp.pages
        delegate: Rectangle {
          required property int index
          width: 8; height: 8; radius: 4
          color: Theme.text
          opacity: index === lp.page ? 0.9 : 0.3
          TapHandler { onTapped: lp.page = index }
        }
      }
    }
  }
}
