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

  onOpenChanged: if (open) { query = ""; search.text = ""; page = 0; menuApp = ""; search.forceActiveFocus() }

  // Dragging to the Dock, and the right-click menu.
  property string dragApp: ""
  property point dragPos: Qt.point(0, 0)
  readonly property bool overDock: dragApp !== "" && dragPos.y > height - 150
  property bool pinnedFlash: false
  Timer { id: flashOff; interval: 900; onTriggered: lp.pinnedFlash = false }
  property string menuApp: ""
  property point menuPos: Qt.point(0, 0)

  Rectangle {
    anchors.fill: parent
    color: Theme.dark ? Qt.rgba(0.03, 0.03, 0.05, 0.42) : Qt.rgba(0.95, 0.95, 0.97, 0.30)
    opacity: lp.shown
  }

  // Click on empty space closes (or just the menu, if one is open).
  TapHandler { onTapped: lp.menuApp !== "" ? lp.menuApp = "" : Shell.close() }

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
            id: pageGrid
            required property int index
            width: pager.width; height: pager.height
            columns: lp.cols
            readonly property real cellW: pager.width / lp.cols
            readonly property real cellH: pager.height / lp.rows
            Repeater {
              model: lp.apps.slice(index * lp.perPage, (index + 1) * lp.perPage)
              delegate: Item {
                required property var modelData
                required property int index
                width: parent.cellW; height: parent.cellH
                // Each icon settles in a moment after the one before it.
                property real enter: lp.open ? 1 : 0
                Behavior on enter { SequentialAnimation {
                  PauseAnimation { duration: lp.open ? Prefs.motion(Math.min(index, 34) * 9) : 0 }
                  NumberAnimation { duration: Prefs.motion(lp.open ? 420 : 160); easing.type: lp.open ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.2 }
                } }
                opacity: (lp.dragApp === modelData.id ? 0.35 : 1) * enter
                transform: [Scale { origin.x: width / 2; origin.y: height / 2; xScale: 1.25 - 0.25 * enter; yScale: 1.25 - 0.25 * enter }]
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
                TapHandler {
                  acceptedButtons: Qt.RightButton
                  onTapped: ev => { const p = parent.mapToItem(lp.contentItem, ev.position.x, ev.position.y); lp.menuApp = modelData.id; lp.menuPos = p }
                }
                // Drag an app down onto the Dock to keep it there.
                DragHandler {
                  target: null
                  onActiveChanged: {
                    if (active) { lp.dragApp = modelData.id; return }
                    if (lp.overDock) { Apps.pin(modelData.id); lp.pinnedFlash = true; flashOff.restart() }
                    lp.dragApp = ""
                  }
                  onCentroidChanged: if (active) lp.dragPos = parent.mapToItem(lp.contentItem, centroid.position.x, centroid.position.y)
                }

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

  // Where to drop to keep an app in the Dock.
  Glass {
    visible: opacity > 0
    opacity: lp.dragApp !== "" || lp.pinnedFlash ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 14 }
    width: 520; height: 96
    radius: 26
    fill: lp.overDock || lp.pinnedFlash ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.glass
    Behavior on fill { ColorAnimation { duration: Theme.fast } }
    Txt { anchors.centerIn: parent; text: lp.pinnedFlash ? "Added to the Dock" : (lp.overDock ? "Release to keep in the Dock" : "Drag here to keep in the Dock"); font.weight: Font.Medium }
  }
  AppIcon {
    visible: lp.dragApp !== ""
    appId: lp.dragApp
    width: 96; height: 96
    x: lp.dragPos.x - 48; y: lp.dragPos.y - 48
    scale: lp.overDock ? 0.8 : 1.05
    Behavior on scale { NumberAnimation { duration: Theme.fast } }
  }
  MenuPanel {
    visible: lp.menuApp !== ""
    x: Math.min(lp.menuPos.x, lp.width - width - 10); y: Math.min(lp.menuPos.y, lp.height - height - 10)
    width: implicitWidth; height: implicitHeight
    items: lp.menuApp === "" ? [] : [
      { text: "Open", action: () => { Apps.launch(lp.menuApp); Shell.close() } },
      { separator: true },
      Apps.pinned.indexOf(lp.menuApp) >= 0
        ? { text: "Remove from Dock", action: () => Apps.unpin(lp.menuApp) }
        : { text: "Keep in Dock", action: () => Apps.pin(lp.menuApp) }
    ]
    onPicked: item => { const run = item.action; Qt.callLater(() => { run(); lp.menuApp = "" }) }
  }
}
