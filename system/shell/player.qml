//@ pragma UseQApplication
//@ pragma AppId memora-player
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui

// Player: films and music. Videos fill the window and the controls float over
// them, fading away while you watch; songs show their cover over a soft wash
// of its colours, with the rest of the folder as a playlist. Drop files on the
// window to play them.
ShellRoot {
  id: app
  readonly property string home: Quickshell.env("HOME")
  property string file: Quickshell.env("MEMORA_PLAYER_FILE") || ""
  readonly property string folder: file ? file.substring(0, file.lastIndexOf("/")) : home + "/Music"
  readonly property var videoExt: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "ts"]
  readonly property bool isVideo: file !== "" && videoExt.indexOf(file.split(".").pop().toLowerCase()) >= 0
  property bool chrome: true

  FolderListModel {
    id: list
    folder: "file://" + app.folder
    nameFilters: app.isVideo ? app.videoExt.map(e => "*." + e) : ["*.mp3", "*.flac", "*.ogg", "*.opus", "*.m4a", "*.wav", "*.aac", "*.wma"]
    showDirs: false
    sortField: FolderListModel.Name
  }
  function indexOf(f) { for (let i = 0; i < list.count; i++) if (list.get(i, "filePath") === f) return i; return -1 }
  function play(f) { file = f; player.source = "file://" + f; player.play() }
  function step(d) {
    const i = indexOf(file)
    if (i < 0 || list.count < 2) return
    play(list.get((i + d + list.count) % list.count, "filePath"))
  }
  function time(ms) {
    const s = Math.floor(ms / 1000), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), ss = s % 60
    return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(ss).padStart(2, "0")
  }

  IpcHandler {
    target: "player"
    function open(path: string): void { app.play(path) }
  }

  MediaPlayer {
    id: player
    source: app.file ? "file://" + app.file : ""
    audioOutput: AudioOutput { id: audio; volume: 0.8 }
    videoOutput: video
    Component.onCompleted: if (app.file) play()
    onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) app.step(1)
  }

  Timer { id: hide; interval: 2400; onTriggered: if (app.isVideo && player.playbackState === MediaPlayer.PlayingState) app.chrome = false }

  FloatingWindow {
    id: win
    onVisibleChanged: if (!visible) Qt.quit()
    title: player.metaData.stringValue(MediaMetaData.Title) || (app.file ? app.file.split("/").pop() : "Player")
    implicitWidth: app.isVideo ? 1100 : 860
    implicitHeight: app.isVideo ? 660 : 540
    minimumSize: Qt.size(520, 360)
    color: "transparent"

    Shortcut { sequence: "Space"; onActivated: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
    Shortcut { sequence: "Right"; onActivated: player.position = Math.min(player.duration, player.position + 5000) }
    Shortcut { sequence: "Left"; onActivated: player.position = Math.max(0, player.position - 5000) }
    Shortcut { sequence: "Up"; onActivated: audio.volume = Math.min(1, audio.volume + 0.05) }
    Shortcut { sequence: "Down"; onActivated: audio.volume = Math.max(0, audio.volume - 0.05) }
    Shortcut { sequence: "M"; onActivated: audio.muted = !audio.muted }
    Shortcut { sequence: "F"; onActivated: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen() }
    Shortcut { sequence: "Escape"; onActivated: if (win.visibility === Window.FullScreen) win.showNormal() }
    Shortcut { sequence: "N"; onActivated: app.step(1) }
    Shortcut { sequence: "P"; onActivated: app.step(-1) }
    Shortcut { sequence: "Ctrl+W"; onActivated: Qt.quit() }

    Rectangle { anchors.fill: parent; color: app.isVideo ? "#000000" : Theme.window }

    // ---- music: cover over a wash of its colours ------------------------------
    Item {
      anchors.fill: parent
      visible: !app.isVideo
      Image {
        id: wash
        anchors.fill: parent
        source: cover.source
        fillMode: Image.PreserveAspectCrop
        visible: false
      }
      MultiEffect { anchors.fill: parent; source: wash; blurEnabled: true; blur: 1; blurMax: 64; saturation: 0.4; opacity: cover.status === Image.Ready ? 0.55 : 0 }
      Rectangle { anchors.fill: parent; color: Theme.dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.35) }
      RowLayout {
        anchors { fill: parent; margins: 28; topMargin: 56; bottomMargin: 120 }
        spacing: 28
        Rectangle {
          Layout.preferredWidth: Math.min(parent.height, 300); Layout.preferredHeight: Layout.preferredWidth
          Layout.alignment: Qt.AlignVCenter
          radius: 18; clip: true
          color: Theme.field
          Image {
            id: cover
            anchors.fill: parent
            source: { const img = player.metaData.value(MediaMetaData.CoverArtImage) || player.metaData.value(MediaMetaData.ThumbnailImage); return img ? img : "" }
            fillMode: Image.PreserveAspectCrop
          }
          Image {
            anchors.centerIn: parent; visible: cover.status !== Image.Ready
            source: Quickshell.iconPath("memora-player"); width: 110; height: 110; sourceSize: Qt.size(220, 220)
          }
          scale: player.playbackState === MediaPlayer.PlayingState ? 1 : 0.92
          Behavior on scale { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutBack } }
        }
        ColumnLayout {
          Layout.fillWidth: true; Layout.fillHeight: true
          spacing: 4
          Txt { text: player.metaData.stringValue(MediaMetaData.Title) || (app.file ? app.file.split("/").pop().replace(/\.[^.]+$/, "") : "Nothing playing"); font.pixelSize: 22; font.weight: Font.Bold; Layout.fillWidth: true; elide: Text.ElideRight }
          Txt { text: player.metaData.stringValue(MediaMetaData.ContributingArtist) || player.metaData.stringValue(MediaMetaData.AlbumArtist) || ""; color: Theme.textDim; Layout.fillWidth: true; elide: Text.ElideRight }
          Txt { text: player.metaData.stringValue(MediaMetaData.AlbumTitle) || ""; color: Theme.textFaint; font.pixelSize: Theme.small; Layout.fillWidth: true; elide: Text.ElideRight }
          Item { Layout.preferredHeight: 10 }
          // The folder, as a playlist.
          ListView {
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true
            model: list
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
              required property string filePath
              required property string fileName
              required property int index
              readonly property bool now: filePath === app.file
              width: ListView.view.width; height: 32; radius: 8
              color: now ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2) : (rh.hovered ? Theme.hover : "transparent")
              Txt { x: 10; anchors.verticalCenter: parent.verticalCenter; text: (index + 1); width: 22; color: Theme.textFaint; font.pixelSize: Theme.small }
              Txt { x: 36; width: parent.width - 46; anchors.verticalCenter: parent.verticalCenter; text: fileName.replace(/\.[^.]+$/, ""); elide: Text.ElideRight; font.weight: parent.now ? Font.Bold : Font.Normal; color: parent.now ? Theme.accent : Theme.text }
              HoverHandler { id: rh }
              TapHandler { onTapped: app.play(filePath) }
            }
          }
        }
      }
    }

    // ---- video ---------------------------------------------------------------------
    VideoOutput {
      id: video
      anchors.fill: parent
      visible: app.isVideo
      fillMode: VideoOutput.PreserveAspectFit
    }
    TapHandler { enabled: app.isVideo; onTapped: { app.chrome = true; hide.restart() } onDoubleTapped: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen() }
    HoverHandler { onPointChanged: { app.chrome = true; hide.restart() } }

    // Nothing open yet.
    Column {
      anchors.centerIn: parent
      visible: app.file === ""
      spacing: 10
      Image { anchors.horizontalCenter: parent.horizontalCenter; source: Quickshell.iconPath("memora-player"); width: 84; height: 84; sourceSize: Qt.size(168, 168) }
      Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Drop a film or a song here"; font.pixelSize: 18; font.weight: Font.Bold }
      Txt { anchors.horizontalCenter: parent.horizontalCenter; text: "Or open one from Files."; color: Theme.textDim }
    }
    DropArea {
      anchors.fill: parent
      onDropped: drop => { if (drop.hasUrls) app.play(decodeURIComponent(String(drop.urls[0]).replace("file://", ""))) }
    }

    // ---- title bar --------------------------------------------------------------------
    Item {
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: 44
      opacity: app.chrome || !app.isVideo ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.normal } }
      Rectangle { anchors.fill: parent; visible: app.isVideo
        gradient: Gradient { GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.6) } GradientStop { position: 1; color: "transparent" } } }
      DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
      WindowControls { x: 14; anchors.verticalCenter: parent.verticalCenter; window: win; onCloseRequested: Qt.quit() }
      Txt { anchors.centerIn: parent; visible: app.isVideo; text: win.title; color: "#ffffff"; font.weight: Font.Bold; width: Math.min(implicitWidth, parent.width - 200); elide: Text.ElideMiddle }
    }

    // ---- controls -----------------------------------------------------------------------
    Glass {
      id: bar
      visible: app.file !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      y: parent.height - (app.chrome || !app.isVideo ? height + 18 : -20)
      opacity: app.chrome || !app.isVideo ? 1 : 0
      Behavior on y { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } }
      Behavior on opacity { NumberAnimation { duration: Theme.normal } }
      width: Math.min(parent.width - 40, 640); height: 86
      radius: 22
      fill: app.isVideo ? Qt.rgba(0.08, 0.08, 0.1, 0.72) : Theme.glassStrong
      HoverHandler { onHoveredChanged: if (hovered) { app.chrome = true; hide.stop() } else hide.restart() }
      readonly property color ink: app.isVideo ? "#ffffff" : Theme.text
      readonly property color dim: app.isVideo ? Qt.rgba(1, 1, 1, 0.6) : Theme.textDim

      // Seek
      RowLayout {
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 18; rightMargin: 18; topMargin: 14 }
        spacing: 10
        Txt { text: app.time(player.position); color: bar.dim; font.pixelSize: Theme.small; Layout.preferredWidth: 48 }
        Item {
          id: seek
          Layout.fillWidth: true; height: 14
          readonly property real frac: player.duration > 0 ? player.position / player.duration : 0
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: sh.hovered || sd.active ? 6 : 4; radius: 3; color: app.isVideo ? Qt.rgba(1, 1, 1, 0.2) : Theme.field
            Behavior on height { NumberAnimation { duration: Theme.fast } }
            Rectangle { width: parent.width * seek.frac; height: parent.height; radius: 3; color: bar.ink } }
          HoverHandler { id: sh }
          DragHandler { id: sd; target: null; xAxis.enabled: true; yAxis.enabled: false
            onCentroidChanged: if (active) player.position = Math.max(0, Math.min(1, centroid.position.x / seek.width)) * player.duration }
          TapHandler { onTapped: ev => player.position = Math.max(0, Math.min(1, ev.position.x / seek.width)) * player.duration }
        }
        Txt { text: "-" + app.time(Math.max(0, player.duration - player.position)); color: bar.dim; font.pixelSize: Theme.small; horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 56 }
      }
      // Buttons
      Item {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 10 }
        height: 40
        Row {
          anchors.centerIn: parent
          spacing: 26
          Btn { sym: "next"; flip: true; size: 18; onClicked: app.step(-1) }
          Btn { sym: player.playbackState === MediaPlayer.PlayingState ? "pause" : "play"; size: 26; onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play() }
          Btn { sym: "next"; size: 18; onClicked: app.step(1) }
        }
        Row {
          anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
          spacing: 8
          Btn { sym: audio.muted || audio.volume === 0 ? "sound-off" : "sound"; size: 16; onClicked: audio.muted = !audio.muted }
          Item {
            id: vol
            width: 84; height: 14; anchors.verticalCenter: parent.verticalCenter
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: app.isVideo ? Qt.rgba(1, 1, 1, 0.2) : Theme.field
              Rectangle { width: parent.width * (audio.muted ? 0 : audio.volume); height: parent.height; radius: 2; color: bar.ink } }
            DragHandler { target: null; xAxis.enabled: true; yAxis.enabled: false; onCentroidChanged: if (active) { audio.muted = false; audio.volume = Math.max(0, Math.min(1, centroid.position.x / vol.width)) } }
            TapHandler { onTapped: ev => { audio.muted = false; audio.volume = Math.max(0, Math.min(1, ev.position.x / vol.width)) } }
          }
        }
        Row {
          anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
          spacing: 10
          Rectangle {
            width: rt.implicitWidth + 14; height: 22; radius: 6; anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(bar.ink.r, bar.ink.g, bar.ink.b, 0.12)
            Txt { id: rt; anchors.centerIn: parent; text: player.playbackRate + "×"; color: bar.ink; font.pixelSize: Theme.small - 0.5 }
            TapHandler { onTapped: { const r = [1, 1.25, 1.5, 2, 0.75]; player.playbackRate = r[(r.indexOf(player.playbackRate) + 1) % r.length] } }
          }
          Btn { visible: app.isVideo; sym: "display"; size: 16; onClicked: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen() }
        }
      }
    }
  }

  component Btn: Item {
    id: b
    property string sym
    property real size: 18
    property bool flip: false
    signal clicked()
    width: size + 14; height: size + 14
    Sym { anchors.centerIn: parent; name: b.sym; width: b.size; height: b.size; color: bar.ink; rotation: b.flip ? 180 : 0 }
    scale: bt.pressed ? 0.86 : (bh.hovered ? 1.1 : 1)
    Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack } }
    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: bt; onTapped: b.clicked() }
  }
}
