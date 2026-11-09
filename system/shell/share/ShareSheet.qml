import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui

// Nearby Share: "Share…" on files (Files, the Gallery, `memora-shell share`)
// opens this sheet with the phones and computers around you; click one and the
// files go to it, with a ring filling around it, like AirDrop. Android phones
// and tablets come through Quick Share (built in), everything else through the
// LocalSend app, on the same network. The sending and the service are
// bin/memora-share and nearby/quickshare.py.
Scope {
  id: sheet
  readonly property var files: Shell.shareFiles
  readonly property bool active: files.length > 0
  property var devices: []
  property var jobs: ({})             // device id -> { state: waiting|sending|done|error, progress, msg, pin }

  function close() { Shell.shareFiles = []; jobs = ({}) }
  function setJob(id, o) { const j = Object.assign({}, jobs); j[id] = Object.assign({}, j[id] || {}, o); jobs = j }
  function send(d) {
    const j = jobs[d.id]
    if (j && (j.state === "waiting" || j.state === "sending")) return
    setJob(d.id, { state: "waiting", progress: 0, msg: "" })
    sender.createObject(sheet, { devId: d.id, command: ["memora-share", "send", d.id].concat(files) })
  }
  onActiveChanged: if (active) { jobs = ({}); Quickshell.execDetached(["memora-share", "scan"]) }

  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/memora-share/devices.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { sheet.devices = JSON.parse(text()).devices || [] } catch (e) {} }
  }
  // Look again every few seconds while the sheet is open.
  Timer { running: sheet.active; interval: 4000; repeat: true; onTriggered: Quickshell.execDetached(["memora-share", "scan"]) }

  Component {
    id: sender
    Process {
      property string devId
      running: true
      stdout: SplitParser {
        onRead: line => {
          if (line === "WAITING") sheet.setJob(devId, { state: "waiting" })
          else if (line.startsWith("PIN ")) sheet.setJob(devId, { pin: line.slice(4) })
          else if (line.startsWith("PROGRESS ")) sheet.setJob(devId, { state: "sending", progress: parseInt(line.slice(9)) / 100 })
          else if (line === "DONE") sheet.setJob(devId, { state: "done", progress: 1 })
          else if (line.startsWith("ERROR ")) sheet.setJob(devId, { state: "error", msg: line.slice(6) })
        }
      }
      onExited: code => { if (code !== 0 && (sheet.jobs[devId] || {}).state !== "error") sheet.setJob(devId, { state: "error", msg: "Couldn't send." }); destroy() }
    }
  }

  readonly property string what: files.length === 1 ? files[0].split("/").pop() : files.length + " items"
  readonly property bool picture: files.length >= 1 && /\.(jpe?g|png|webp|gif|bmp|avif|heic)$/i.test(files[0])

  PanelWindow {
    id: win
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    visible: sheet.active || anim.running
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "memora-dialog"
    WlrLayershell.keyboardFocus: sheet.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property real shown: sheet.active ? 1 : 0
    Behavior on shown { NumberAnimation { id: anim; duration: Theme.normal; easing.type: Theme.easing } }

    // A click outside the card closes it (one on the card reaches here too).
    Rectangle {
      anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.28); opacity: win.shown
      TapHandler { onTapped: ev => { const p = card.mapFromItem(null, ev.scenePosition.x, ev.scenePosition.y); if (!card.contains(p)) sheet.close() } }
    }

    Glass {
      id: card
      anchors.centerIn: parent
      width: 520
      height: col.implicitHeight + 40
      radius: 22
      fill: Theme.glassStrong
      shadowSize: 50
      opacity: win.shown
      scale: 0.94 + 0.06 * win.shown
      focus: true
      Keys.onEscapePressed: sheet.close()

      ColumnLayout {
        id: col
        x: 22; y: 20; width: parent.width - 44
        spacing: 14

        // What is being shared.
        RowLayout {
          spacing: 12
          Rectangle {
            Layout.preferredWidth: 46; Layout.preferredHeight: 46; radius: 10
            color: Theme.field; clip: true
            Image { anchors.fill: parent; visible: sheet.picture; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize: Qt.size(96, 96); source: sheet.picture ? "file://" + sheet.files[0] : "" }
            Sym { visible: !sheet.picture; anchors.centerIn: parent; name: "share"; width: 20; height: 20; color: Theme.textDim }
          }
          ColumnLayout {
            spacing: 1
            Layout.fillWidth: true
            Txt { text: sheet.what; font.weight: Font.Bold; Layout.fillWidth: true; elide: Text.ElideMiddle }
            Txt { text: "Share with a phone or computer nearby"; color: Theme.textDim; font.pixelSize: Theme.small }
          }
          Rectangle {
            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 14
            color: xh.hovered ? Theme.hover : "transparent"
            Sym { anchors.centerIn: parent; name: "close"; width: 11; height: 11; color: Theme.textDim }
            HoverHandler { id: xh }
            TapHandler { onTapped: sheet.close() }
          }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.separator }

        // The devices around.
        Flow {
          Layout.fillWidth: true
          spacing: 6
          visible: sheet.devices.length > 0
          Repeater {
            model: sheet.devices
            delegate: Item {
              id: dv
              required property var modelData
              readonly property var job: sheet.jobs[modelData.id] || null
              width: 112; height: 118
              Item {
                id: ring
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4; width: 68; height: 68
                Rectangle {
                  anchors.centerIn: parent
                  width: 58; height: 58; radius: 29
                  color: dh.hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent
                  Sym {
                    anchors.centerIn: parent
                    name: dv.job && dv.job.state === "done" ? "check" : (({ mobile: "phone", tablet: "phone", desktop: "laptop", web: "globe", server: "display", headless: "display" })[dv.modelData.type] || "laptop")
                    width: 26; height: 26; color: "#ffffff"
                  }
                }
                // Progress around it while sending.
                Canvas {
                  anchors.fill: parent
                  visible: !!dv.job && dv.job.state !== "error"
                  property real p: dv.job ? (dv.job.state === "waiting" ? 0.12 : dv.job.progress) : 0
                  property bool spin: !!dv.job && dv.job.state === "waiting"
                  onPChanged: requestPaint()
                  onVisibleChanged: requestPaint()
                  RotationAnimation on rotation { running: parent.spin === true; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
                  onPaint: {
                    const c = getContext("2d"); c.reset()
                    c.lineWidth = 3; c.lineCap = "round"
                    c.strokeStyle = Theme.separator
                    c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 2, 0, Math.PI * 2); c.stroke()
                    c.strokeStyle = Theme.accent
                    c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 2, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.02, p)); c.stroke()
                  }
                }
              }
              Txt {
                anchors { top: ring.bottom; topMargin: 6; horizontalCenter: parent.horizontalCenter }
                width: parent.width - 6; horizontalAlignment: Text.AlignHCenter
                text: dv.modelData.alias; font.pixelSize: Theme.small; font.weight: Font.Bold
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
              }
              Txt {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: !dv.job ? dv.modelData.model === "Quick Share" ? "Quick Share" : "" : dv.job.state === "waiting" ? (dv.job.pin ? "PIN " + dv.job.pin : "Waiting…") : dv.job.state === "sending" ? Math.round(dv.job.progress * 100) + "%" : dv.job.state === "done" ? "Sent" : dv.job.msg
                color: dv.job && dv.job.state === "error" ? Theme.red : (dv.job && dv.job.state === "done" ? Theme.green : Theme.textDim)
                font.pixelSize: Theme.small - 1; elide: Text.ElideRight
              }
              HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: sheet.send(dv.modelData) }
            }
          }
        }

        // Nobody yet.
        ColumnLayout {
          visible: sheet.devices.length === 0
          Layout.fillWidth: true
          Layout.topMargin: 6; Layout.bottomMargin: 6
          spacing: 6
          Sym {
            Layout.alignment: Qt.AlignHCenter
            name: "wifi"; width: 30; height: 30; color: Theme.textFaint
            SequentialAnimation on opacity { running: sheet.active; loops: Animation.Infinite
              NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine } }
          }
          Txt { Layout.alignment: Qt.AlignHCenter; text: "Looking for devices nearby…"; font.weight: Font.Bold }
          Txt {
            Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "Android: on the same Wi-Fi, set Quick Share to Everyone. iPhone, Windows and Mac: open LocalSend (free) on the same Wi-Fi."
            color: Theme.textDim; font.pixelSize: Theme.small
          }
        }
      }
    }
  }
}
