import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import qs.core
import qs.ui

// The notch's file panel: what was dropped on it, the formats it can become
// and what else can be done with it, then the result, ready to open, share or
// drag out. The state and the work are in Notch.qml (n) and memora-convert.
Item {
  id: fp
  required property var n
  property bool shown: false
  implicitHeight: col.implicitHeight

  readonly property color ink: "#f5f5f7"
  readonly property color dim: Qt.rgba(0.96, 0.96, 0.97, 0.56)
  readonly property color faint: Qt.rgba(0.96, 0.96, 0.97, 0.3)
  readonly property color well: Qt.rgba(1, 1, 1, 0.06)
  readonly property color line: Qt.rgba(1, 1, 1, 0.08)

  readonly property var files: n.shelf
  readonly property var first: files.length ? files[0] : null
  readonly property bool busy: n.jobState === "running"
  readonly property var kinds: { const k = {}; for (const f of files) k[f.kind] = true; return Object.keys(k) }
  readonly property bool all1: kinds.length === 1
  readonly property string kind: all1 ? kinds[0] : "mixed"

  // ---- what can be done -------------------------------------------------------
  function paths(kindsOk) { return files.filter(f => !kindsOk || kindsOk.indexOf(f.kind) >= 0).map(f => f.path) }
  readonly property var formats: {
    const same = id => all1 && files.every(f => f.ext === id || (id === "jpg" && f.ext === "jpeg"))
    const f = []
    if (kind === "image") for (const x of [["png", "PNG"], ["jpg", "JPEG"], ["webp", "WebP"], ["avif", "AVIF"], ["heic", "HEIC"]]) { if (!same(x[0])) f.push({ id: "img-" + x[0], label: x[1], busy: "Converting to " + x[1] + "…" }) }
    if (kind === "image" || (files.length > 1 && files.every(x => x.kind === "image" || x.kind === "pdf")))
      f.push({ id: "pdf", label: files.length > 1 ? "One PDF" : "PDF", busy: files.length > 1 ? "Combining into one PDF…" : "Making a PDF…" })
    if (kind === "video") {
      for (const x of [["mp4", "MP4"], ["webm", "WebM"], ["mov", "MOV"]]) if (!same(x[0])) f.push({ id: "vid-" + x[0], label: x[1], busy: "Converting to " + x[1] + "…" })
      f.push({ id: "vid-gif", label: "GIF", busy: "Making a GIF…" })
      if (files.some(x => x.audio)) f.push({ id: "vid-mp3", label: "MP3 audio", busy: "Taking out the sound…" })
    }
    if (kind === "audio") for (const x of [["mp3", "MP3"], ["m4a", "M4A"], ["ogg", "OGG"], ["wav", "WAV"], ["flac", "FLAC"]]) { if (!same(x[0])) f.push({ id: "aud-" + x[0], label: x[1], busy: "Converting to " + x[1] + "…" }) }
    return f
  }
  readonly property var tools: {
    const t = []
    const one = files.length === 1
    if (kind === "image") {
      t.push({ id: "img-compress", label: "Compress", sym: "compress", busy: "Compressing…" })
      t.push({ id: "img-half", label: "Half Size", sym: "resize", busy: "Resizing…" })
      t.push({ id: "img-1920", label: "Fit 1920 px", sym: "display", busy: "Resizing…" })
      t.push({ id: "img-rotate", label: "Rotate", sym: "rotate", busy: "Rotating…" })
      t.push({ id: "img-text", label: "Copy Text", sym: "text", busy: "Reading the text…" })
      t.push({ id: "img-strip", label: "Remove Info", sym: "shield", busy: "Removing the info…" })
      if (one) t.push({ id: "img-clip", label: "Copy Picture", sym: "copy", busy: "Copying…" })
      if (one) t.push({ id: "@wall", label: "Set as Wallpaper", sym: "photo" })
    }
    if (kind === "video") {
      t.push({ id: "vid-compress", label: "Compress", sym: "compress", busy: "Compressing…" })
      if (files.some(x => x.audio)) t.push({ id: "vid-mute", label: "Remove Sound", sym: "sound-off", busy: "Removing the sound…" })
      t.push({ id: "vid-frame", label: "Save a Frame", sym: "photo", busy: "Saving a frame…" })
    }
    if (kind === "pdf") {
      t.push({ id: "pdf-compress", label: "Compress", sym: "compress", busy: "Compressing…" })
      if (!one) t.push({ id: "pdf", label: "Combine", sym: "copy", busy: "Combining…" })
      t.push({ id: "pdf-images", label: "Pages to Pictures", sym: "photo", busy: "Making pictures of the pages…" })
      t.push({ id: "pdf-text", label: "Copy Text", sym: "text", busy: "Reading the text…" })
    }
    if (kind === "archive") t.push({ id: "extract", label: "Extract", sym: "folder", busy: "Extracting…" })
    if (kind !== "archive") t.push({ id: "zip", label: one ? "Zip" : "Zip Together", sym: "archive", busy: "Zipping…" })
    t.push({ id: "@share", label: "Nearby Share", sym: "share" })
    t.push({ id: "@copy", label: one ? "Copy File" : "Copy Files", sym: "copy" })
    t.push({ id: "@show", label: "Show in Files", sym: "folder" })
    return t
  }
  function act(a) {
    const all = files.map(f => f.path)
    switch (a.id) {
    case "@share": Shell.shareFiles = all; n.collapse(); return
    case "@show": Quickshell.execDetached(["memora-files", all[0]]); n.collapse(); return
    case "@copy": copyUris(all); return
    case "@wall":
      Prefs.set("wallpaper", all[0])
      n.jobAction = a.id; n.jobState = "done"; n.jobOut = []; n.jobText = ""; n.jobLabel = "Wallpaper changed"
      return
    }
    n.runAction(a, all)
  }
  function copyUris(list) {
    Quickshell.execDetached(["bash", "-c", "printf '%s\\r\\n' \"$@\" | wl-copy --type text/uri-list", "_"].concat(list.map(p => "file://" + encodeURI(p))))
    copied.restart()
  }
  Timer { id: copied; interval: 1600 }

  // ---- how things read ----------------------------------------------------------
  function bytes(b) {
    if (b < 0) return ""
    if (b < 1000) return b + " bytes"
    const u = ["KB", "MB", "GB", "TB"]; let i = -1
    do { b /= 1000; i++ } while (b >= 1000 && i < u.length - 1)
    return (b >= 100 ? b.toFixed(0) : b >= 10 ? b.toFixed(1) : b.toFixed(1)).replace(/\.0$/, "") + " " + u[i]
  }
  function clock(s) {
    s = Math.round(s); const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, x = s % 60
    return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0")
  }
  function kindName(f) {
    const e = (f.ext || "").toUpperCase()
    return ({ image: e + " picture", video: e + " video", audio: e + " audio", pdf: "PDF document", archive: e + " archive", doc: e + " document", text: e + " text", folder: "Folder" })[f.kind] || (e ? e + " file" : "File")
  }
  function meta(f) {
    const p = [kindName(f)]
    if (f.w && f.h) p.push(f.w + " × " + f.h)
    if (f.duration) p.push(clock(f.duration))
    if (f.pages) p.push(f.pages + (f.pages === 1 ? " page" : " pages"))
    if (f.size >= 0) p.push(bytes(f.size))
    return p.join("  ·  ")
  }
  readonly property real totalSize: files.reduce((s, f) => s + Math.max(0, f.size), 0)
  readonly property string title: files.length === 1 ? files[0].name : files.length + " " + (kind === "image" ? "pictures" : kind === "video" ? "videos" : kind === "audio" ? "songs" : kind === "pdf" ? "PDFs" : "items")
  readonly property string subtitle: files.length === 1 ? meta(files[0]) : (totalSize > 0 ? bytes(totalSize) + " in all" : "")
  function tint(k) {
    return ({ image: ["#ff9f0a", "#ff375f"], video: ["#bf5af2", "#5e5ce6"], audio: ["#ff375f", "#ff2d55"], pdf: ["#ff453a", "#d70015"],
              archive: ["#d4a373", "#a2845e"], doc: ["#0a84ff", "#5e5ce6"], text: ["#64d2ff", "#0a84ff"], folder: ["#64d2ff", "#0a84ff"] })[k] || ["#8e8e93", "#636366"]
  }

  Keys.onEscapePressed: n.collapse()
  onShownChanged: if (shown) Qt.callLater(() => fp.forceActiveFocus())

  ColumnLayout {
    id: col
    width: parent.width
    spacing: 16

    // ---- header: the files, fanned like a little stack -----------------------------
    RowLayout {
      Layout.fillWidth: true
      spacing: 14
      Item {
        id: stack
        Layout.preferredWidth: 64; Layout.preferredHeight: 64
        Repeater {
          model: fp.files.slice(0, 3).reverse()
          delegate: Thumb {
            required property var modelData
            required property int index
            readonly property int depth: Math.min(fp.files.length, 3) - 1 - index
            file: modelData
            width: 56; height: 56
            x: 4 + depth * 3; y: 4 - depth * 2
            rotation: depth === 0 ? 0 : (depth === 1 ? -7 : 8)
            opacity: depth === 0 ? 1 : 0.8 - depth * 0.15
            Behavior on rotation { SpringAnimation { spring: 4; damping: 0.3 } }
            scale: fp.shown ? 1 : 0.6
            Behavior on scale { SpringAnimation { spring: 3.5; damping: 0.26; epsilon: 0.005 } }
          }
        }
        // How many, when there are more than one.
        Rectangle {
          visible: fp.files.length > 1
          anchors { right: parent.right; bottom: parent.bottom; rightMargin: -4; bottomMargin: -2 }
          width: Math.max(20, cnt.implicitWidth + 10); height: 20; radius: 10
          color: Theme.accent
          Txt { id: cnt; anchors.centerIn: parent; text: fp.files.length; color: "#ffffff"; font.pixelSize: Theme.small; font.weight: Font.Bold }
        }
        DragOut { anchors.fill: parent; paths: fp.files.map(f => f.path); grab: stack }
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        Txt { Layout.fillWidth: true; text: fp.title; color: fp.ink; font.pixelSize: 15; font.weight: Font.Bold; elide: Text.ElideMiddle }
        Txt { Layout.fillWidth: true; text: fp.subtitle; color: fp.dim; font.pixelSize: Theme.small; elide: Text.ElideRight }
        // Several files: their names, small, with a way to leave one out.
        Flow {
          visible: fp.files.length > 1
          Layout.fillWidth: true; Layout.topMargin: 3
          spacing: 5
          Repeater {
            model: fp.files.slice(0, 8)
            delegate: Rectangle {
              required property var modelData
              width: Math.min(150, nm.implicitWidth + 30); height: 20; radius: 10
              color: Qt.rgba(1, 1, 1, 0.07)
              Txt { id: nm; x: 9; width: parent.width - 28; anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: fp.dim; font.pixelSize: Theme.small - 1; elide: Text.ElideMiddle }
              Sym { anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter } name: "close"; width: 7; height: 7; color: xh.hovered ? fp.ink : fp.faint
                HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor; margin: 4 }
                TapHandler { margin: 4; onTapped: fp.n.removeFile(modelData.path) } }
            }
          }
          Txt { visible: fp.files.length > 8; text: "+" + (fp.files.length - 8); color: fp.faint; font.pixelSize: Theme.small - 1; height: 20; verticalAlignment: Text.AlignVCenter }
        }
      }
      Pill { Layout.alignment: Qt.AlignTop; sym: "sparkle"; text: "Ask AI"; onClicked: fp.n.askAbout(fp.files.map(f => f.path)) }
      Round { Layout.alignment: Qt.AlignTop; sym: "close"; onClicked: fp.n.closeFiles() }
    }

    // ---- convert to ------------------------------------------------------------------
    ColumnLayout {
      visible: fp.formats.length > 0
      Layout.fillWidth: true
      spacing: 8
      Caption { text: "Convert to" }
      Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
          model: fp.formats
          delegate: Chip { required property var modelData; required property int index; act: modelData; order: index }
        }
      }
    }

    // ---- more -------------------------------------------------------------------------
    ColumnLayout {
      Layout.fillWidth: true
      spacing: 8
      Caption { text: fp.kind === "image" || fp.kind === "video" || fp.kind === "pdf" ? "Quick actions" : "Actions" }
      Grid {
        id: grid
        Layout.fillWidth: true
        readonly property int cols: Math.max(3, Math.floor((width + spacing) / (98 + spacing)))
        columns: cols
        spacing: 8
        readonly property real tileW: (width - (cols - 1) * spacing) / cols
        Repeater {
          model: fp.tools
          delegate: Tile { required property var modelData; required property int index; act: modelData; order: index + fp.formats.length; width: grid.tileW }
        }
      }
    }

    // ---- working, then the result ----------------------------------------------------------
    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: status.height
      visible: fp.n.jobState !== ""
      Rectangle {
        id: status
        width: parent.width
        height: fp.n.jobState === "running" ? 60 : fp.n.jobState === "error" ? errRow.implicitHeight + 28 : resultCol.implicitHeight + 28
        Behavior on height { SpringAnimation { spring: 3; damping: 0.32; epsilon: 0.5 } }
        radius: 20
        color: fp.n.jobState === "error" ? Qt.rgba(1, 0.3, 0.3, 0.12) : fp.well
        border.color: fp.n.jobState === "done" ? Qt.rgba(0.2, 0.84, 0.4, 0.28) : fp.line
        Behavior on border.color { ColorAnimation { duration: Theme.normal } }

        // Slides up into place when it appears.
        property real enter: 0
        transform: Translate { y: (1 - status.enter) * 18 }
        opacity: enter
        Connections {
          target: fp.n
          function onJobStateChanged() {
            if (fp.n.jobState === "") { enterAnim.stop(); status.enter = 0 }
            else if (fp.n.jobState === "running" || status.enter === 0) { status.enter = 0; enterAnim.restart() }
          }
        }
        NumberAnimation { id: enterAnim; target: status; property: "enter"; from: 0; to: 1; duration: Prefs.motion(380); easing.type: Easing.OutBack; easing.overshoot: 1.2 }

        // Running: what it is doing, a bar that fills, and Stop.
        Item {
          anchors.fill: parent
          visible: fp.n.jobState === "running"
          Ring { id: busyRing; x: 16; anchors.verticalCenter: parent.verticalCenter; width: 28; height: 28; value: fp.n.jobProgress; spinning: fp.n.jobProgress <= 0.01 }
          Txt { anchors { left: busyRing.right; leftMargin: 12; top: parent.top; topMargin: 13 } text: fp.n.jobLabel; color: fp.ink; font.weight: Font.Bold }
          Txt { id: pct; anchors { right: stopBtn.left; rightMargin: 12; top: parent.top; topMargin: 13 } text: Math.round(fp.n.jobProgress * 100) + "%"; color: fp.dim; font.pixelSize: Theme.small; font.features: { "tnum": 1 } }
          // The bar, with a soft light running along it.
          Rectangle {
            id: track
            anchors { left: busyRing.right; leftMargin: 12; right: stopBtn.left; rightMargin: 12; bottom: parent.bottom; bottomMargin: 15 }
            height: 5; radius: 2.5; color: Qt.rgba(1, 1, 1, 0.1); clip: true
            Rectangle {
              id: fill
              height: parent.height; radius: parent.radius
              width: Math.max(parent.height, parent.width * fp.n.jobProgress)
              Behavior on width { SmoothedAnimation { velocity: 400 } }
              gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.25) }
                GradientStop { position: 1; color: Theme.accent } }
            }
            Rectangle {
              width: 60; height: parent.height
              gradient: Gradient { orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.45) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) } }
              NumberAnimation on x { running: fp.busy; from: -60; to: track.width; duration: 1300; loops: Animation.Infinite; easing.type: Easing.InOutQuad }
            }
          }
          Round { id: stopBtn; anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } sym: "close"; tip: "Stop"; onClicked: fp.n.cancelJob() }
        }

        // Failed: why, and Try Again.
        RowLayout {
          id: errRow
          visible: fp.n.jobState === "error"
          x: 16; y: 14; width: parent.width - 32
          spacing: 12
          Rectangle { Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 14; color: Qt.rgba(1, 0.37, 0.34, 0.2)
            Txt { anchors.centerIn: parent; text: "!"; color: Theme.red; font.weight: Font.Black } }
          ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Txt { text: "Couldn't do it"; color: fp.ink; font.weight: Font.Bold }
            Txt { Layout.fillWidth: true; text: fp.n.jobMsg; color: fp.dim; font.pixelSize: Theme.small; wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight }
          }
          Pill { text: "OK"; onClicked: fp.n.resetJob() }
        }

        // Done: a check that draws itself, what came out, and what to do with it.
        ColumnLayout {
          id: resultCol
          visible: fp.n.jobState === "done"
          x: 16; y: 14; width: parent.width - 32
          spacing: 12
          RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Check { id: check; Layout.preferredWidth: 28; Layout.preferredHeight: 28; play: fp.n.jobState === "done" }
            ColumnLayout {
              Layout.fillWidth: true; spacing: 1
              Txt {
                Layout.fillWidth: true; color: fp.ink; font.weight: Font.Bold; elide: Text.ElideMiddle
                text: fp.n.jobAction === "@wall" ? "Wallpaper changed"
                  : fp.n.jobText !== "" && !fp.n.jobOut.length ? "Text copied"
                  : fp.n.jobAction === "img-clip" ? "Picture copied"
                  : fp.n.jobOut.length === 1 ? "Saved “" + fp.n.jobOut[0].name + "”"
                  : fp.n.jobOut.length > 1 ? "Saved " + fp.n.jobOut.length + " files" : "Done"
              }
              Txt {
                readonly property real outSize: fp.n.jobOut.reduce((s, o) => s + Math.max(0, o.size), 0)
                readonly property bool known: fp.n.jobOut.length > 0 && fp.n.jobOut.every(o => o.size >= 0) && fp.n.jobInSize > 0
                visible: text !== ""
                Layout.fillWidth: true; color: fp.dim; font.pixelSize: Theme.small; elide: Text.ElideRight
                text: fp.n.jobText !== "" ? "On the clipboard — paste it anywhere"
                  : fp.n.jobAction === "img-clip" ? "On the clipboard — paste it anywhere"
                  : known ? fp.bytes(fp.n.jobInSize) + "  →  " + fp.bytes(outSize) : fp.n.jobOut.length ? "Next to the original" : ""
              }
            }
            // Smaller by…: a green badge that pops in.
            Rectangle {
              id: badge
              readonly property real outSize: fp.n.jobOut.reduce((s, o) => s + Math.max(0, o.size), 0)
              readonly property int saved: fp.n.jobInSize > 0 && fp.n.jobOut.length && fp.n.jobOut.every(o => o.size >= 0) ? Math.round((1 - outSize / fp.n.jobInSize) * 100) : 0
              visible: saved >= 3
              implicitWidth: bt.implicitWidth + 18; implicitHeight: 24; radius: 12
              color: Qt.rgba(0.2, 0.84, 0.4, 0.18)
              Txt { id: bt; anchors.centerIn: parent; text: "−" + badge.saved + "%"; color: "#30d158"; font.weight: Font.Bold; font.pixelSize: Theme.small }
              scale: visible ? 1 : 0.3
              Behavior on scale { SpringAnimation { spring: 4; damping: 0.22; epsilon: 0.01 } }
            }
          }
          // Found text: the beginning of it.
          Rectangle {
            visible: fp.n.jobText !== ""
            Layout.fillWidth: true
            implicitHeight: ft.implicitHeight + 18; radius: 12
            color: Qt.rgba(0, 0, 0, 0.35)
            Txt { id: ft; x: 12; y: 9; width: parent.width - 24; text: fp.n.jobText.slice(0, 600); color: fp.ink; wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight; font.pixelSize: Theme.small + 0.5 }
          }
          // What came out: drag it anywhere, or click to open.
          Flow {
            visible: fp.n.jobOut.length > 0
            Layout.fillWidth: true
            spacing: 8
            Repeater {
              model: fp.n.jobOut.slice(0, 6)
              delegate: Rectangle {
                id: oc
                required property var modelData
                required property int index
                width: Math.min(resultCol.width, Math.max(170, on.implicitWidth + 74)); height: 52; radius: 14
                color: och.hovered ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Thumb { id: ot; x: 8; anchors.verticalCenter: parent.verticalCenter; width: 36; height: 36; file: oc.modelData; small: true }
                Column {
                  anchors { left: ot.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                  spacing: 1
                  Txt { id: on; width: parent.width; text: oc.modelData.name; color: fp.ink; font.pixelSize: Theme.small + 0.5; elide: Text.ElideMiddle }
                  Txt { width: parent.width; text: oc.modelData.size >= 0 ? fp.bytes(oc.modelData.size) : " "; color: fp.faint; font.pixelSize: Theme.small - 1 }
                }
                HoverHandler { id: och; cursorShape: Qt.OpenHandCursor }
                TapHandler { onTapped: Quickshell.execDetached(["xdg-open", oc.modelData.path]) }
                DragOut { anchors.fill: parent; paths: [oc.modelData.path]; grab: ot }
                // In one after the other.
                opacity: 0; scale: 0.85
                Component.onCompleted: popIn.start()
                SequentialAnimation {
                  id: popIn
                  PauseAnimation { duration: Prefs.motion(120 + oc.index * 60) }
                  ParallelAnimation {
                    NumberAnimation { target: oc; property: "opacity"; to: 1; duration: Prefs.motion(220) }
                    SpringAnimation { target: oc; property: "scale"; to: 1; spring: 4; damping: 0.28; epsilon: 0.005 }
                  }
                }
              }
            }
          }
          RowLayout {
            visible: fp.n.jobOut.length > 0
            Layout.fillWidth: true
            spacing: 8
            Pill { text: "Show in Files"; sym: "folder"; onClicked: { Quickshell.execDetached(["memora-files", fp.n.jobOut[0].path]); fp.n.collapse() } }
            Pill { text: "Share"; sym: "share"; onClicked: { Shell.shareFiles = fp.n.jobOut.map(o => o.path); fp.n.collapse() } }
            Pill { text: copied.running ? "Copied" : "Copy"; sym: copied.running ? "check" : "copy"; onClicked: fp.copyUris(fp.n.jobOut.map(o => o.path)) }
            Item { Layout.fillWidth: true }
            Pill { text: "Keep Going"; sym: "arrow"; symRotation: 0; strong: true; onClicked: fp.n.keepGoing(); Tip { text: "Work on what came out: convert it again, compress it, share it…"; delay: 500 } }
          }
        }
      }
    }
  }

  // ---- pieces -------------------------------------------------------------------------------
  component Caption: Txt {
    color: fp.faint; font.pixelSize: Theme.small - 1; font.weight: Font.Bold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.8
  }

  // A picture's thumbnail, or a coloured tile with the file type on it.
  component Thumb: Rectangle {
    id: th
    property var file: null
    property bool small: false
    readonly property bool pic: !!file && file.kind === "image" && !/\.(heic|heif|svg)$/i.test(file.path)
    readonly property var c: fp.tint(file ? file.kind : "")
    radius: small ? 9 : 13
    clip: true
    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.14)
    gradient: Gradient {
      GradientStop { position: 0; color: th.c[0] }
      GradientStop { position: 1; color: th.c[1] }
    }
    Sym {
      visible: !th.pic || img.status !== Image.Ready
      anchors.centerIn: parent; anchors.verticalCenterOffset: th.small ? 0 : -6
      width: th.small ? 16 : 22; height: width; color: "#ffffff"
      name: !th.file ? "file" : ({ image: "photo", video: "film", audio: "music", pdf: "text", archive: "archive", folder: "folder", text: "text", doc: "text" })[th.file.kind] || "file"
    }
    Txt {
      visible: !th.small && (!th.pic || img.status !== Image.Ready) && !!th.file && th.file.ext !== ""
      anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 6 }
      text: th.file ? th.file.ext.toUpperCase().slice(0, 5) : ""
      color: "#ffffff"; font.pixelSize: 10; font.weight: Font.Black; font.letterSpacing: 0.5
    }
    Image {
      id: img
      anchors.fill: parent
      visible: th.pic && status === Image.Ready
      source: th.pic ? "file://" + th.file.path : ""
      fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: false
      sourceSize: Qt.size(128, 128)
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.normal } }
    }
  }

  // A file format to convert to.
  component Chip: Rectangle {
    id: ch
    property var act
    property int order: 0
    readonly property bool mine: fp.n.jobAction === act.id && fp.busy
    readonly property bool off: fp.busy && !mine
    implicitWidth: cl.implicitWidth + 32; implicitHeight: 36
    radius: 18
    color: mine ? Theme.accent : chh.hovered && !off ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Qt.rgba(1, 1, 1, 0.07)
    border.width: 1
    border.color: chh.hovered && !off ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.7) : fp.line
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on border.color { ColorAnimation { duration: Theme.fast } }
    Txt { id: cl; anchors.centerIn: parent; text: ch.act.label; color: "#ffffff"; font.weight: Font.DemiBold; font.letterSpacing: 0.3 }
    property real dimK: off ? 0.4 : 1
    Behavior on dimK { NumberAnimation { duration: Theme.fast } }
    opacity: dimK * enter
    scale: chtap.pressed ? 0.93 : chh.hovered && !off ? 1.05 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.005 } }
    HoverHandler { id: chh; cursorShape: ch.off ? Qt.ArrowCursor : Qt.PointingHandCursor }
    TapHandler { id: chtap; enabled: !fp.busy; onTapped: fp.act(ch.act) }
    property real enter: 0
    transform: Translate { y: (1 - ch.enter) * 10 }
    Entrance { target: ch; order: ch.order }
  }

  // An action: a symbol over its name; a ring fills around the symbol while it runs.
  component Tile: Rectangle {
    id: tl
    property var act
    property int order: 0
    readonly property bool mine: fp.n.jobAction === act.id && fp.busy
    readonly property bool done: fp.n.jobAction === act.id && fp.n.jobState === "done"
    readonly property bool off: fp.busy && !mine && act.id[0] !== "@"
    readonly property bool flashCopy: act.id === "@copy" && copied.running
    height: 80
    radius: 18
    color: tlh.hovered && !off ? Qt.rgba(1, 1, 1, 0.12) : fp.well
    border.width: 1; border.color: mine ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : fp.line
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Item {
      id: ic
      anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 11 }
      width: 34; height: 34
      Rectangle {
        anchors.fill: parent; radius: 17
        color: tl.mine || tl.done || tl.flashCopy ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.08)
        Behavior on color { ColorAnimation { duration: Theme.normal } }
      }
      Sym {
        anchors.centerIn: parent; width: 16; height: 16
        name: tl.done || tl.flashCopy ? "check" : tl.act.sym
        color: tl.done || tl.flashCopy ? "#30d158" : "#ffffff"
        scale: tlh.hovered && !tl.off ? 1.12 : 1
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.25; epsilon: 0.005 } }
      }
      Ring { anchors.fill: parent; anchors.margins: -3; visible: tl.mine; value: fp.n.jobProgress; spinning: fp.n.jobProgress <= 0.01; thin: true }
    }
    Txt {
      anchors { left: parent.left; right: parent.right; top: ic.bottom; topMargin: 7; leftMargin: 6; rightMargin: 6 }
      text: tl.flashCopy ? "Copied" : tl.act.label; color: fp.ink; font.pixelSize: Theme.small
      horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; lineHeight: 0.92
    }
    property real dimK: off ? 0.4 : 1
    Behavior on dimK { NumberAnimation { duration: Theme.fast } }
    opacity: dimK * enter
    scale: tltap.pressed ? 0.94 : tlh.hovered && !off ? 1.035 : 1
    Behavior on scale { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.005 } }
    HoverHandler { id: tlh; cursorShape: tl.off ? Qt.ArrowCursor : Qt.PointingHandCursor }
    TapHandler { id: tltap; enabled: !tl.off && !tl.mine; onTapped: fp.act(tl.act) }
    property real enter: 0
    transform: Translate { y: (1 - tl.enter) * 12 }
    Entrance { target: tl; order: tl.order }
  }

  // In one after another each time the panel opens.
  component Entrance: Item {
    id: en
    property Item target
    property int order: 0
    function go() {
      anim.stop(); target.enter = 0
      if (fp.shown) anim.start()
    }
    Connections { target: fp; function onShownChanged() { en.go() } }
    Component.onCompleted: { if (fp.shown) target.enter = 1 }
    SequentialAnimation {
      id: anim
      PauseAnimation { duration: Prefs.motion(70 + Math.min(en.order, 14) * 22) }
      NumberAnimation { target: en.target; property: "enter"; to: 1; duration: Prefs.motion(340); easing.type: Easing.OutBack; easing.overshoot: 1.4 }
    }
  }

  // A progress ring (spinning while there is no progress to show yet).
  component Ring: Shape {
    id: rg
    property real value: 0
    property bool spinning: false
    property bool thin: false
    preferredRendererType: Shape.CurveRenderer
    readonly property real r: Math.min(width, height) / 2 - (thin ? 1.5 : 2)
    property real disp: value
    Behavior on disp { SmoothedAnimation { velocity: 1.2 } }
    ShapePath {
      strokeColor: Qt.rgba(1, 1, 1, rg.thin ? 0 : 0.14); strokeWidth: rg.thin ? 2 : 3; fillColor: "transparent"
      PathAngleArc { centerX: rg.width / 2; centerY: rg.height / 2; radiusX: rg.r; radiusY: rg.r; startAngle: 0; sweepAngle: 360 }
    }
    ShapePath {
      strokeColor: Theme.accent; strokeWidth: rg.thin ? 2 : 3; fillColor: "transparent"; capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: rg.width / 2; centerY: rg.height / 2; radiusX: rg.r; radiusY: rg.r; startAngle: -90; sweepAngle: rg.spinning ? 90 : Math.max(4, 360 * rg.disp) }
    }
    RotationAnimation on rotation { running: rg.spinning && rg.visible; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
    onSpinningChanged: if (!spinning) rotation = 0
  }

  // A green circle that pops in with a check that draws itself.
  component Check: Item {
    id: ck
    property bool play: false
    property real t: 0
    onPlayChanged: { t = 0; if (play) drawIt.restart() }
    Component.onCompleted: if (play) drawIt.restart()
    Rectangle {
      anchors.centerIn: parent
      width: parent.width; height: parent.height; radius: width / 2
      color: "#30d158"
      scale: ck.t > 0 ? Math.min(1, 0.4 + ck.t * 1.6) : 0.4
      opacity: Math.min(1, ck.t * 3)
    }
    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      opacity: ck.t > 0.3 ? 1 : 0
      ShapePath {
        id: cp
        strokeColor: "#ffffff"; strokeWidth: 2.6; fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
        // The two strokes of the check, grown with t.
        readonly property real k: Math.max(0, Math.min(1, (ck.t - 0.3) / 0.7))
        startX: ck.width * 0.29; startY: ck.height * 0.52
        PathLine { x: ck.width * (0.29 + 0.14 * Math.min(1, cp.k / 0.4)); y: ck.height * (0.52 + 0.14 * Math.min(1, cp.k / 0.4)) }
        PathLine { x: ck.width * (0.43 + 0.3 * Math.max(0, (cp.k - 0.4) / 0.6)); y: ck.height * (0.66 - 0.32 * Math.max(0, (cp.k - 0.4) / 0.6)) }
      }
    }
    NumberAnimation { id: drawIt; target: ck; property: "t"; from: 0; to: 1; duration: Prefs.motion(560); easing.type: Easing.OutCubic }
  }

  // Drags files out of the notch to anywhere that takes them (Files, the desktop, a browser…).
  component DragOut: Item {
    id: dout
    property var paths: []
    property Item grab
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.mimeData: ({ "text/uri-list": paths.map(p => "file://" + encodeURI(p)).join("\r\n") + "\r\n" })
    Drag.onDragFinished: Drag.active = false
    DragHandler {
      target: null
      onActiveChanged: {
        if (!active || dout.Drag.active || !dout.paths.length) return
        if (dout.grab) dout.grab.grabToImage(r => { dout.Drag.imageSource = r.url; dout.Drag.active = true }, Qt.size(dout.grab.width, dout.grab.height))
        else dout.Drag.active = true
      }
    }
  }

  component Pill: Rectangle {
    id: pl
    property string text
    property string sym: ""
    property real symRotation: 0
    property bool strong: false
    signal clicked()
    implicitWidth: pt.implicitWidth + (sym ? 42 : 26); implicitHeight: 30
    radius: 15
    color: strong ? (ph.hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent) : (ph.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Sym { id: ps; visible: pl.sym !== ""; x: 12; anchors.verticalCenter: parent.verticalCenter; name: pl.sym || "file"; width: 12; height: 12; color: "#ffffff"; rotation: pl.symRotation }
    Txt { id: pt; x: pl.sym ? 30 : 13; anchors.verticalCenter: parent.verticalCenter; text: pl.text; color: "#f5f5f7"; font.pixelSize: Theme.small + 0.5; font.weight: pl.strong ? Font.Bold : Font.Normal }
    scale: ptap.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: Theme.fast } }
    HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: ptap; onTapped: pl.clicked() }
  }

  component Round: Rectangle {
    id: rd
    property string sym
    property string tip: ""
    signal clicked()
    width: 30; height: 30; radius: 15
    color: rh.hovered ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Sym { anchors.centerIn: parent; name: rd.sym; width: 10; height: 10; color: "#ffffff" }
    HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: rd.clicked() }
    Tip { text: rd.tip; delay: 400; visible: rd.tip !== "" }
  }
}
