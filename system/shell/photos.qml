//@ pragma UseQApplication
//@ pragma AppId memora-photos
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui

// Photos: look at pictures. Opens one (memora-photos FILE) and lets you move
// through the others in its folder with the arrow keys or the filmstrip; with
// nothing to open, shows your Pictures. Scroll or pinch to zoom, drag to look
// around, double-click to switch between fitting and actual size.
ShellRoot {
  id: app
  readonly property string home: Quickshell.env("HOME")
  property string file: Quickshell.env("MEMORA_PHOTOS_FILE") || ""
  property string folder: file ? file.substring(0, file.lastIndexOf("/")) : home + "/Pictures"
  readonly property var exts: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.gif", "*.bmp", "*.svg", "*.tif", "*.tiff", "*.avif", "*.heic", "*.jxl", "*.JPG", "*.JPEG", "*.PNG", "*.WEBP"]

  FolderListModel {
    id: pics
    folder: "file://" + app.folder
    nameFilters: app.exts
    showDirs: false
    sortField: FolderListModel.Name
    onStatusChanged: if (status === FolderListModel.Ready) app.syncIndex()
  }
  property int index: -1
  function syncIndex() {
    if (!file) { index = -1; return }
    for (let i = 0; i < pics.count; i++) if (pics.get(i, "filePath") === file) { index = i; return }
  }
  function show(i) {
    if (pics.count === 0) return
    const n = (i + pics.count) % pics.count
    dir = n > index || (index === pics.count - 1 && n === 0) ? 1 : -1
    index = n; file = pics.get(n, "filePath")
    view.reset()
  }
  property int dir: 1
  property int turn: 0            // rotation, in quarter turns
  property bool chrome: true      // toolbar and filmstrip showing
  property bool info: false
  property bool slideshow: false
  property var meta: ({})

  IpcHandler {
    target: "photos"
    function open(path: string): void { app.file = path; app.folder = path.substring(0, path.lastIndexOf("/")); app.syncIndex(); view.reset() }
  }

  Process {
    id: metaProc
    command: ["bash", "-c", "f=\"$1\"; stat -c '%s|%y' \"$f\"; identify -format '%w|%h\\n' \"$f[0]\" 2>/dev/null | head -1", "_", app.file]
    stdout: StdioCollector { onStreamFinished: { const l = text.trim().split("\n"); const a = (l[0] || "").split("|"), b = (l[1] || "").split("|"); app.meta = { size: Number(a[0]), date: a[1] || "", w: b[0] || "", h: b[1] || "" } } }
  }
  onFileChanged: { meta = ({}); turn = 0; if (file) metaProc.running = true }
  function human(b) { return b > 1e6 ? (b / 1e6).toFixed(1) + " MB" : Math.round(b / 1e3) + " KB" }

  Process { id: runner }
  function run(args) { runner.command = args; runner.running = true }
  function trash() {
    if (!file) return
    const was = index
    run(["gio", "trash", "--", file])
    // The folder model drops it; show the next one.
    Qt.callLater(() => { if (pics.count > 1) show(Math.min(was, pics.count - 2)); else { file = ""; index = -1 } })
  }

  Timer { running: app.slideshow; interval: 3500; repeat: true; onTriggered: app.show(app.index + 1) }
  Timer { id: hideChrome; interval: 2600; onTriggered: if (app.file && !app.info) app.chrome = false }

  FloatingWindow {
    id: win
    onVisibleChanged: if (!visible) Qt.quit()
    title: app.file ? app.file.split("/").pop() : "Photos"
    implicitWidth: 1180
    implicitHeight: 780
    minimumSize: Qt.size(560, 420)
    color: "transparent"
    Rectangle { anchors.fill: parent; color: app.file ? (Theme.dark ? "#0b0b0d" : "#f2f2f4") : Theme.window }

    Shortcut { sequence: "Right"; onActivated: app.show(app.index + 1) }
    Shortcut { sequence: "Left"; onActivated: app.show(app.index - 1) }
    Shortcut { sequence: "Space"; onActivated: app.slideshow = !app.slideshow }
    Shortcut { sequence: "Escape"; onActivated: app.slideshow ? app.slideshow = false : (win.visibility === Window.FullScreen ? win.showNormal() : (app.file && pics.count > 1 ? app.file = "" : Qt.quit())) }
    Shortcut { sequence: "F"; onActivated: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen() }
    Shortcut { sequence: "R"; onActivated: app.turn = (app.turn + 1) % 4 }
    Shortcut { sequence: "I"; onActivated: app.info = !app.info }
    Shortcut { sequence: "Delete"; onActivated: app.trash() }
    Shortcut { sequence: "Ctrl+="; onActivated: view.zoomBy(1.25) }
    Shortcut { sequence: "Ctrl+-"; onActivated: view.zoomBy(0.8) }
    Shortcut { sequence: "Ctrl+0"; onActivated: view.reset() }
    Shortcut { sequence: "Ctrl+W"; onActivated: Qt.quit() }

    HoverHandler { onPointChanged: { app.chrome = true; hideChrome.restart() } }

    // ---- the picture ---------------------------------------------------------
    Item {
      id: view
      anchors.fill: parent
      visible: app.file !== ""
      clip: true
      property real zoom: 1          // 1 = fit
      property real px: 0
      property real py: 0
      function reset() { zoom = 1; px = 0; py = 0 }
      function zoomBy(f) { zoom = Math.max(1, Math.min(12, zoom * f)); if (zoom === 1) { px = 0; py = 0 } }
      Behavior on zoom { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }

      // Two layers so the next picture slides in over the last one.
      Repeater {
        model: 1
        Item {
          anchors.fill: parent
          AnimatedImage {
            id: img
            readonly property bool turned: app.turn % 2 === 1
            readonly property real fit: Math.min((view.width - 40) / Math.max(1, turned ? sourceSize.height : sourceSize.width), (view.height - 40) / Math.max(1, turned ? sourceSize.width : sourceSize.height), 1)
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: view.px
            anchors.verticalCenterOffset: view.py
            width: sourceSize.width * fit * view.zoom
            height: sourceSize.height * fit * view.zoom
            source: app.file ? "file://" + app.file : ""
            asynchronous: true
            cache: false
            smooth: true; mipmap: true
            rotation: app.turn * 90
            Behavior on rotation { NumberAnimation { duration: Theme.normal; easing.type: Theme.easing } }
            onSourceChanged: { fadeIn.restart() }
            opacity: 0
            NumberAnimation { id: fadeIn; target: img; property: "opacity"; from: 0; to: 1; duration: Theme.normal }
            transform: Translate { id: slide; x: 0 }
            Connections { target: app; function onIndexChanged() { slideIn.restart() } }
            NumberAnimation { id: slideIn; target: slide; property: "x"; from: app.dir * 40; to: 0; duration: Theme.slow; easing.type: Easing.OutCubic }
          }
          Txt { anchors.centerIn: parent; visible: img.status === Image.Error; text: "Can't open this picture"; color: Theme.textDim }
        }
      }
      DragHandler { target: null; enabled: view.zoom > 1; property real sx; property real sy
        onActiveChanged: if (active) { sx = view.px; sy = view.py }
        onTranslationChanged: { view.px = sx + translation.x; view.py = sy + translation.y } }
      WheelHandler { onWheel: ev => view.zoomBy(ev.angleDelta.y > 0 ? 1.15 : 1 / 1.15) }
      PinchHandler { target: null; onScaleChanged: delta => view.zoomBy(delta) }
      TapHandler { onDoubleTapped: view.zoom > 1 ? view.reset() : view.zoomBy(2.5) }
    }

    // ---- toolbar ---------------------------------------------------------------
    Item {
      id: top
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: 52
      opacity: app.chrome || !app.file ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.normal } }
      Rectangle {
        anchors.fill: parent
        visible: app.file !== ""
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.55 : 0.12) }
          GradientStop { position: 1; color: "transparent" }
        }
      }
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      WindowControls { x: 16; anchors.verticalCenter: parent.verticalCenter; window: win; onCloseRequested: Qt.quit() }
      Column {
        anchors.centerIn: parent
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: app.file ? app.file.split("/").pop() : "Pictures"; font.weight: Font.Bold; color: app.file && Theme.dark ? "#ffffff" : Theme.text; elide: Text.ElideMiddle; width: Math.min(implicitWidth, win.width - 420) }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; visible: app.file !== "" && pics.count > 1; text: (app.index + 1) + " of " + pics.count; color: Theme.textDim; font.pixelSize: Theme.small - 1 }
      }
      Row {
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 4
        visible: app.file !== ""
        Tool { sym: "restart"; tip: "Rotate (R)"; onClicked: app.turn = (app.turn + 1) % 4 }
        Tool { sym: "play"; tip: app.slideshow ? "Stop slideshow (Space)" : "Slideshow (Space)"; on: app.slideshow; onClicked: app.slideshow = !app.slideshow }
        Tool { sym: "photo"; tip: "Use as wallpaper"; onClicked: Prefs.set("wallpaper", app.file) }
        Tool { sym: "info"; tip: "Info (I)"; on: app.info; onClicked: app.info = !app.info }
        Tool { sym: "close"; tip: "Move to Trash (Delete)"; onClicked: app.trash() }
      }
    }

    // ---- info -------------------------------------------------------------------
    Glass {
      anchors { right: parent.right; top: top.bottom; margins: 12 }
      width: 250; height: infoCol.implicitHeight + 28
      radius: 16
      fill: Theme.glassStrong
      opacity: app.info && app.file ? 1 : 0
      visible: opacity > 0
      x: app.info ? 0 : 20
      Behavior on opacity { NumberAnimation { duration: Theme.normal } }
      ColumnLayout {
        id: infoCol
        x: 14; y: 14; width: parent.width - 28
        spacing: 8
        Txt { text: app.file.split("/").pop(); font.weight: Font.Bold; Layout.fillWidth: true; elide: Text.ElideMiddle }
        Repeater {
          model: [["Dimensions", app.meta.w ? app.meta.w + " × " + app.meta.h : "…"], ["Size", app.meta.size ? app.human(app.meta.size) : "…"],
                  ["Taken", app.meta.date ? app.meta.date.slice(0, 16) : "…"], ["Where", app.folder.replace(app.home, "~")]]
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            Txt { text: modelData[0]; color: Theme.textDim; font.pixelSize: Theme.small; Layout.preferredWidth: 78 }
            Txt { text: modelData[1]; font.pixelSize: Theme.small; Layout.fillWidth: true; elide: Text.ElideMiddle }
          }
        }
      }
    }

    // ---- filmstrip ---------------------------------------------------------------
    Glass {
      id: strip
      visible: app.file !== "" && pics.count > 1
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - (app.chrome ? height + 16 : -10)
      Behavior on y { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
      width: Math.min(parent.width - 60, filmList.contentWidth + 20); height: 74
      radius: 18
      fill: Theme.glassStrong
      ListView {
        id: filmList
        anchors { fill: parent; margins: 10 }
        orientation: ListView.Horizontal
        spacing: 6
        model: pics
        clip: true
        currentIndex: app.index
        highlightMoveDuration: Theme.normal
        preferredHighlightBegin: width / 2 - 27; preferredHighlightEnd: width / 2 + 27
        highlightRangeMode: ListView.ApplyRange
        delegate: Rectangle {
          required property int index
          required property string filePath
          width: 54; height: 54; radius: 9
          color: "transparent"
          border.width: index === app.index ? 2 : 0
          border.color: Theme.accent
          scale: index === app.index ? 1 : (th.hovered ? 0.97 : 0.9)
          Behavior on scale { NumberAnimation { duration: Theme.fast } }
          Image { anchors { fill: parent; margins: 2 } source: "file://" + filePath; sourceSize: Qt.size(108, 108); fillMode: Image.PreserveAspectCrop; asynchronous: true; clip: true }
          HoverHandler { id: th }
          TapHandler { onTapped: app.show(index) }
        }
      }
    }

    // ---- Pictures (nothing open) --------------------------------------------------
    GridView {
      id: gallery
      visible: app.file === ""
      anchors { fill: parent; topMargin: 60; leftMargin: 20; rightMargin: 20 }
      clip: true
      model: pics
      cellWidth: Math.floor(width / Math.max(2, Math.floor(width / 190))); cellHeight: cellWidth
      delegate: Item {
        required property int index
        required property string filePath
        width: gallery.cellWidth; height: gallery.cellHeight
        Rectangle {
          anchors { fill: parent; margins: 4 }
          radius: 10; clip: true
          color: Theme.field
          scale: gh.hovered ? 1.02 : 1
          Behavior on scale { NumberAnimation { duration: Theme.fast } }
          Image { anchors.fill: parent; source: "file://" + filePath; sourceSize: Qt.size(380, 380); fillMode: Image.PreserveAspectCrop; asynchronous: true }
        }
        HoverHandler { id: gh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { app.index = index; app.file = filePath; view.reset() } }
      }
      Column {
        anchors.centerIn: parent
        visible: pics.count === 0
        spacing: 8
        Sym { anchors.horizontalCenter: parent.horizontalCenter; name: "photo"; width: 44; height: 44; color: Theme.textFaint }
        Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "No pictures in " + app.folder.replace(app.home, "~"); color: Theme.textDim }
      }
    }
  }

  component Tool: Rectangle {
    id: tl
    property string sym
    property string tip
    property bool on: false
    signal clicked()
    width: 32; height: 30; radius: 8
    color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3) : (th2.hovered ? Qt.rgba(1, 1, 1, 0.14) : "transparent")
    Sym { anchors.centerIn: parent; name: tl.sym; width: 15; height: 15; color: app.file && Theme.dark ? "#ffffff" : Theme.text }
    HoverHandler { id: th2 }
    TapHandler { onTapped: tl.clicked() }
  }
}
