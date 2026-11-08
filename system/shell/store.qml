//@ pragma UseQApplication
//@ pragma AppId memora-store
//@ pragma IconTheme Memora
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui

// App Store: a hand-picked set of good apps from Flathub. Apps install into your
// account (no password), sandboxed, and show up in Launchpad right away.
ShellRoot {
  id: app
  readonly property string home: Quickshell.env("HOME")
  // Flathub's catalogue lives in a folder named after its checksum; found after the update.
  property string iconDir: ""
  property var catalog: ({ featured: [], categories: [], apps: [] })
  property var installed: ({})          // id -> true
  property var extra: ({})              // apps from Flathub outside the hand-picked list: id -> { id, name, summary, category }
  property var updates: []              // ids with an update waiting
  property var found: []                // ids found on Flathub for the search (not in the hand-picked list)
  property bool searching: false
  property var jobs: ({})               // id -> { kind: "install"|"remove"|"update", progress: 0..1 }
  property var procs: ({})              // id -> its running Process (to cancel a download)
  property string section: "Discover"
  property string query: ""
  property string detail: ""            // app id shown in detail
  property bool ready: false            // Flathub reachable and its catalogue fetched
  property string status: "Connecting to Flathub…"

  FileView {
    path: Theme.share + "/store/catalog.json"
    onLoaded: { try { app.catalog = JSON.parse(text()) } catch (e) {} }
  }

  // ---- Flathub
  Process {
    id: setup
    running: true
    command: ["bash", "-c", "flatpak remote-add --user --if-not-exists artcraft-oci https://getartcraft.com/artcraft-oci.flatpakrepo >/dev/null 2>&1; flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo && flatpak update --user --appstream flathub >/dev/null 2>&1; echo $?; d=$(ls -dt ~/.local/share/flatpak/appstream/flathub/x86_64/*/icons/128x128 2>/dev/null | head -1); echo \"$d\""]
    stdout: StdioCollector { onStreamFinished: { const f = text.trim().split("\n"); app.iconDir = f[1] ? f[1] + "/" : ""; app.ready = f[0] === "0"; app.status = app.ready ? "" : "Flathub can't be reached. Check the internet connection." ; app.refresh() } }
  }
  Process {
    id: lister
    command: ["bash", "-c", "flatpak list --user --app --columns=application,name,description; memora-store-cli list"]
    stdout: StdioCollector { onStreamFinished: {
      const m = {}, x = Object.assign({}, app.extra)
      text.split("\n").forEach(l => {
        const f = l.split("\t"), id = f[0].trim()
        if (!id) return
        m[id] = true
        if (f.length > 1 && !app.catalog.apps.find(a => a.id === id) && !x[id])
          x[id] = { id: id, name: f[1] || id, summary: f[2] || "", category: "Flathub", description: f[2] || "" }
      })
      app.extra = x; app.installed = m
    } }
  }
  // Updates waiting on Flathub for apps installed here.
  Process {
    id: updLister
    command: ["bash", "-c", "flatpak remote-ls --user --updates --app --columns=application 2>/dev/null"]
    stdout: StdioCollector { onStreamFinished: app.updates = text.split("\n").map(l => l.trim()).filter(l => l && l !== "Application ID") }
  }
  function refresh() { lister.running = true; if (ready) updLister.running = true }

  // Search all of Flathub, beyond the hand-picked apps.
  Timer { id: searchLater; interval: 450; onTriggered: if (app.query.length >= 2 && app.ready) { searcher.running = false; searcher.running = true } }
  onQueryChanged: { found = []; searching = query.length >= 2 && ready; searchLater.restart() }
  Process {
    id: searcher
    command: ["flatpak", "search", "--columns=application,name,description,remotes", app.query]
    stdout: StdioCollector { onStreamFinished: {
      const x = Object.assign({}, app.extra), ids = []
      text.split("\n").forEach(l => {
        const f = l.split("\t"), id = (f[0] || "").trim()
        // Apps only: not plugins, manuals, codecs and the like.
        if (/\.(Plugin|Extension|Manual|Docs|Codecs|Locale|Debug|BaseApp)(\.|$)/i.test(id)) return
        if (!id || (f[3] || "").indexOf("flathub") < 0 || app.catalog.apps.find(a => a.id === id) || ids.indexOf(id) >= 0) return
        if (!x[id]) x[id] = { id: id, name: f[1] || id, summary: f[2] || "", category: "Flathub", description: f[2] || "" }
        ids.push(id)
      })
      app.extra = x; app.found = ids.slice(0, 24); app.searching = false
    } }
  }

  Component { id: jobProc; Process {
    property string appId
    property string kind
    command: appId.startsWith("cli.") ? ["memora-store-cli", kind, appId]
      // memora-flatpak reports "PROGRESS n" for the whole job (flatpak itself
      // shows no progress without a terminal).
      : kind === "install"
      ? ["memora-flatpak", "install", (app.entry(appId) || {}).remote || "flathub", appId]
      : kind === "update"
      ? (appId === "*" ? ["memora-flatpak", "update"] : ["memora-flatpak", "update", appId])
      : ["memora-flatpak", "uninstall", appId]
    property bool cancelled: false
    running: true
    stdout: SplitParser {
      onRead: line => {
        let m = line.match(/^PROGRESS (\d{1,3})/)
        if (!m) m = line.match(/(\d{1,3})%\s*$/)          // memora-store-cli
        if (m) app.setProgress(appId, Math.min(100, parseInt(m[1])) / 100)
      }
    }
    onExited: code => {
      const j = Object.assign({}, app.jobs); delete j[appId]; app.jobs = j
      const pr = Object.assign({}, app.procs); delete pr[appId]; app.procs = pr
      app.refresh()
      if (cancelled) app.status = ""
      else if (code !== 0) app.status = ({ install: "Couldn't install ", update: "Couldn't update ", remove: "Couldn't remove " })[kind] + (appId === "*" ? "the apps" : app.nameOf(appId)) + "."
      else if (kind === "update") Quickshell.execDetached(["notify-send", "-a", "App Store", appId === "*" ? "Apps updated" : app.nameOf(appId) + " is up to date", "The new versions open next time you start them."])
      else if (kind === "install") Quickshell.execDetached(["notify-send", "-a", "App Store", app.nameOf(appId) + " is ready", appId.startsWith("cli.") ? "Open it from the App Store, or type its name in Terminal." : "Find it in Apps."])
      destroy()
    }
  } }
  // A new job object each time: the ring only notices a different object.
  function setProgress(id, p) { if (!jobs[id] || jobs[id].progress === p) return; const j = Object.assign({}, jobs); j[id] = Object.assign({}, j[id], { progress: p }); jobs = j }
  function start(id, kind) {
    if (jobs[id]) return
    const j = Object.assign({}, jobs); j[id] = { kind: kind, progress: 0 }; jobs = j
    status = ""
    const pr = Object.assign({}, procs); pr[id] = jobProc.createObject(app, { appId: id, kind: kind }); procs = pr
  }
  // Stop a download that is under way (tap its ring).
  function cancel(id) {
    const pr = procs[id]
    if (!pr || jobs[id].kind === "remove") return
    pr.cancelled = true
    pr.signal(15)
    Quickshell.execDetached(["notify-send", "-a", "App Store", "Download stopped", nameOf(id) + " wasn't installed."])
  }
  function open(id) { Quickshell.execDetached(id.startsWith("cli.") ? ["memora-store-cli", "open", id] : ["flatpak", "run", id]) }
  function entry(id) { return catalog.apps.find(x => x.id === id) || extra[id] || null }
  function nameOf(id) { const a = entry(id); return a ? a.name : id }
  function iconOf(id) { const e = entry(id); return iconDir && id && !id.startsWith("cli.") && !(e && e.remote) ? "file://" + iconDir + id + ".png" : "" }

  readonly property var shown: {
    const q = query.toLowerCase()
    if (q) return catalog.apps.filter(a => (a.name + " " + a.summary + " " + a.category).toLowerCase().indexOf(q) >= 0)
    if (section === "Installed") return catalog.apps.filter(a => installed[a.id]).concat(Object.keys(installed).filter(id => !catalog.apps.find(a => a.id === id) && extra[id]).map(id => extra[id]))
    if (section === "Updates") return updates.map(id => entry(id) || { id: id, name: nameOf(id), summary: "", category: "" })
    if (section === "Discover") return catalog.apps
    return catalog.apps.filter(a => a.category === section)
  }

  // ================================================================ window
  FloatingWindow {
    id: win
    // Closed by the compositor (Alt+F4, Quit, Super+Q): end the app too, so it
    // opens again next time instead of lingering without a window.
    onVisibleChanged: if (!visible) Qt.quit()
    title: "App Store"
    implicitWidth: 1120
    implicitHeight: 720
    minimumSize: Qt.size(820, 520)
    color: "transparent"
    Rectangle { anchors.fill: parent; color: Theme.window }

    // ---- sidebar
    Rectangle {
      id: side
      width: 220
      anchors { top: parent.top; bottom: parent.bottom; left: parent.left; margins: 8 }
      radius: 12
      color: Theme.sidebar
      border.color: Theme.separator
      WindowControls { x: 14; y: 14; window: win; onCloseRequested: Qt.quit() }
      Item { anchors { left: parent.left; right: parent.right; top: parent.top } height: 40; DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() } }

      Rectangle {
        id: search
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 44; leftMargin: 12; rightMargin: 12 }
        height: 30; radius: 8
        color: Theme.field; border.color: sf.activeFocus ? Theme.accent : Theme.separator
        Sym { name: "search"; width: 12; height: 12; color: Theme.textDim; anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter } }
        TextInput {
          id: sf
          anchors { left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 8; verticalCenter: parent.verticalCenter }
          color: Theme.text; font.family: Theme.font; font.pixelSize: Theme.small + 0.5
          clip: true
          onTextChanged: { app.query = text; app.detail = "" }
          Keys.onEscapePressed: text = ""
          Txt { visible: !sf.text; text: "Search"; color: Theme.textFaint; font.pixelSize: Theme.small + 0.5; anchors.verticalCenter: parent.verticalCenter }
        }
      }
      Column {
        anchors { left: parent.left; right: parent.right; top: search.bottom; topMargin: 12 }
        spacing: 1
        Repeater {
          model: ["Discover"].concat(app.catalog.categories).concat(["Installed", "Updates"])
          delegate: Item {
            required property string modelData
            required property int index
            readonly property bool here: app.section === modelData && !app.query
            width: parent.width; height: 32 + (modelData === "Installed" ? 10 : 0)
            // How many updates are waiting.
            Rectangle {
              visible: modelData === "Updates" && app.updates.length > 0
              anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
              width: Math.max(20, un.implicitWidth + 10); height: 18; radius: 9; color: Theme.red
              Txt { id: un; anchors.centerIn: parent; text: app.updates.length; color: "#ffffff"; font.pixelSize: Theme.small - 1; font.weight: Font.Bold }
            }
            Rectangle {
              y: modelData === "Installed" ? 10 : 0
              x: 6; width: parent.width - 12; height: 32; radius: 8
              color: parent.here ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.35 : 0.18) : (nh.hovered ? Theme.hover : "transparent")
              Behavior on color { ColorAnimation { duration: Theme.fast } }
              Sym { id: ns; x: 10; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; color: parent.parent.here ? Theme.accent : Theme.textDim
                    name: ({ Discover: "sparkle", AI: "ai", Electronics: "gear", "Virtual Machines": "display", ArtCraft: "palette", Productivity: "check", Internet: "globe", Creativity: "photo", Development: "keyboard", Media: "play", Games: "mouse", Utilities: "gear", Installed: "arrow", Updates: "download" })[modelData] || "plus" }
              Txt { anchors { left: ns.right; leftMargin: 10; verticalCenter: parent.verticalCenter } text: modelData; font.weight: parent.parent.here ? Font.Bold : Font.Normal }
            }
            HoverHandler { id: nh }
            TapHandler { onTapped: { app.section = modelData; app.detail = ""; sf.text = ""; listIn.restart() } }
          }
        }
      }
    }

    // ---- content
    Item {
      id: main
      anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 6 }
      Item { anchors { left: parent.left; right: parent.right; top: parent.top } height: 40; DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() } }

      Flickable {
        id: flick
        anchors { fill: parent; topMargin: 14 }
        contentHeight: col.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: app.detail === ""
        opacity: 1
        transform: Translate { id: lshift }
        SequentialAnimation {
          id: listIn
          PropertyAction { target: flick; property: "opacity"; value: 0 }
          PropertyAction { target: lshift; property: "y"; value: 12 }
          ParallelAnimation {
            NumberAnimation { target: flick; property: "opacity"; to: 1; duration: Theme.normal }
            NumberAnimation { target: lshift; property: "y"; to: 0; duration: Theme.slow; easing.type: Easing.OutQuint }
          }
        }

        ColumnLayout {
          id: col
          x: 28; width: flick.width - 56
          spacing: 18
          RowLayout {
            Layout.fillWidth: true
            Txt { text: app.query ? "Results" : app.section; font.pixelSize: 26; font.weight: Font.Bold; Layout.fillWidth: true }
            // Updates: all at once.
            Rectangle {
              visible: app.section === "Updates" && !app.query && app.updates.length > 0 && !app.jobs["*"]
              width: ua.implicitWidth + 30; height: 30; radius: 15
              color: uh.hovered ? Qt.darker(Theme.accent, 1.1) : Theme.accent
              Txt { id: ua; anchors.centerIn: parent; text: "Update All"; color: "#ffffff"; font.weight: Font.Bold }
              HoverHandler { id: uh }
              TapHandler { onTapped: app.start("*", "update") }
            }
            Txt { visible: !!app.jobs["*"]; text: "Updating…"; color: Theme.textDim }
          }
          Txt { visible: app.status !== ""; text: app.status; color: Theme.textDim }

          // Featured: three large cards on Discover.
          RowLayout {
            visible: app.section === "Discover" && !app.query
            Layout.fillWidth: true
            spacing: 16
            Repeater {
              model: app.catalog.featured
              delegate: Rectangle {
                required property string modelData
                required property int index
                readonly property var a: app.catalog.apps.find(x => x.id === modelData) || ({ name: "", summary: "" })
                Layout.fillWidth: true
                Layout.preferredHeight: 190
                radius: 18
                clip: true
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0; color: ["#5b4bd6", "#e2683b", "#2a73d9"][index % 3] }
                  GradientStop { position: 1; color: ["#9a6bff", "#f5a14a", "#35b6e0"][index % 3] }
                }
                scale: fh.hovered ? 1.02 : 1
                Behavior on scale { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
                Txt { x: 20; y: 18; text: ["New: Claude for Memora", "ArtCraft", "For engineers"][index % 3]; color: Qt.rgba(1, 1, 1, 0.8); font.pixelSize: Theme.small; font.weight: Font.Bold }
                Txt { x: 20; y: 40; width: parent.width - 130; height: 28; text: parent.a.name; color: "#ffffff"; font.pixelSize: 22; font.weight: Font.Bold; fontSizeMode: Text.HorizontalFit; minimumPixelSize: 13; verticalAlignment: Text.AlignVCenter }
                Txt { x: 20; y: 72; width: parent.width - 130; text: parent.a.summary; color: Qt.rgba(1, 1, 1, 0.85); wrapMode: Text.Wrap; maximumLineCount: 3 }
                StoreIcon { appId: parent.modelData; width: 86; height: 86; anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter } }
                GetButton { appId: parent.modelData; anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 18 } light: true }
                HoverHandler { id: fh }
                TapHandler { onTapped: app.detail = parent.modelData }
              }
            }
          }

          // Grouped by category on Discover, a single grid elsewhere.
          Repeater {
            model: app.section === "Discover" && !app.query ? app.catalog.categories : [""]
            delegate: ColumnLayout {
              required property string modelData
              Layout.fillWidth: true
              spacing: 10
              RowLayout {
                visible: modelData !== ""
                Layout.fillWidth: true
                Txt { text: modelData; font.pixelSize: Theme.large + 2; font.weight: Font.Bold; Layout.fillWidth: true }
                Txt { text: "See All"; color: Theme.accent; TapHandler { onTapped: { app.section = modelData; listIn.restart() } } }
              }
              GridLayout {
                Layout.fillWidth: true
                columns: Math.max(1, Math.floor(col.width / 300))
                columnSpacing: 14; rowSpacing: 4
                Repeater {
                  model: modelData !== "" ? app.catalog.apps.filter(a => a.category === modelData).slice(0, Math.max(1, Math.floor(col.width / 300)) * 2) : app.shown
                  delegate: Card { required property var modelData; a: modelData; Layout.fillWidth: true }
                }
              }
              Txt { visible: modelData === "" && app.shown.length === 0 && !(app.query && (app.found.length || app.searching))
                text: app.query ? "Nothing matches." : ({ Installed: "Apps you get here will show up here.", Updates: app.ready ? "All your apps are up to date." : "Updates show up here once Flathub can be reached." })[app.section] || "Nothing here yet."
                color: Theme.textDim }
              // The rest of Flathub, for a search.
              ColumnLayout {
                visible: modelData === "" && !!app.query && (app.found.length > 0 || app.searching)
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 10
                Txt { text: app.searching ? "Searching Flathub…" : "More on Flathub"; font.pixelSize: Theme.large + 2; font.weight: Font.Bold }
                GridLayout {
                  Layout.fillWidth: true
                  columns: Math.max(1, Math.floor(col.width / 300))
                  columnSpacing: 14; rowSpacing: 4
                  Repeater {
                    model: app.found.map(id => app.extra[id]).filter(a => !!a)
                    delegate: Card { required property var modelData; a: modelData; Layout.fillWidth: true }
                  }
                }
              }
            }
          }
        }
      }

      // ---- one app
      Item {
        id: page
        anchors.fill: parent
        visible: app.detail !== ""
        readonly property var a: app.entry(app.detail) || ({ name: "", summary: "", description: "", category: "" })
        opacity: visible ? 1 : 0
        transform: Translate { x: page.visible ? 0 : 40; Behavior on x { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutQuint } } }
        Behavior on opacity { NumberAnimation { duration: Theme.normal } }

        Row {
          x: 24; y: 14
          spacing: 6
          Sym { name: "chevron"; rotation: 180; width: 12; height: 12; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
          Txt { text: app.query ? "Results" : app.section; color: Theme.accent }
          TapHandler { onTapped: app.detail = "" }
        }
        ColumnLayout {
          x: 40; y: 60; width: parent.width - 80
          spacing: 18
          RowLayout {
            spacing: 22
            StoreIcon { appId: app.detail; Layout.preferredWidth: 128; Layout.preferredHeight: 128 }
            ColumnLayout {
              spacing: 6
              Txt { text: page.a.name; font.pixelSize: 28; font.weight: Font.Bold }
              Txt { text: page.a.summary; color: Theme.textDim; font.pixelSize: Theme.large }
              Txt { text: page.a.category; color: Theme.accent; font.pixelSize: Theme.small }
              Row {
                Layout.topMargin: 8
                spacing: 10
                GetButton { appId: app.detail; big: true }
                Rectangle {
                  visible: app.updates.indexOf(app.detail) >= 0 && !app.jobs[app.detail]
                  width: upt.implicitWidth + 26; height: 32; radius: 16
                  color: uph.hovered ? Theme.pressed : Theme.hover
                  Txt { id: upt; anchors.centerIn: parent; text: "Update"; color: Theme.accent; font.weight: Font.Bold }
                  HoverHandler { id: uph }
                  TapHandler { onTapped: app.start(app.detail, "update") }
                }
                Rectangle {
                  visible: !!app.installed[app.detail] && !app.jobs[app.detail]
                  width: rt.implicitWidth + 26; height: 32; radius: 16
                  color: rh.hovered ? Theme.pressed : Theme.hover
                  Txt { id: rt; anchors.centerIn: parent; text: "Remove"; color: Theme.red }
                  HoverHandler { id: rh }
                  TapHandler { onTapped: app.start(app.detail, "remove") }
                }
              }
            }
          }
          Rectangle { Layout.fillWidth: true; height: 1; color: Theme.separator }
          Txt { Layout.fillWidth: true; text: page.a.description; wrapMode: Text.Wrap; font.pixelSize: Theme.fontSize + 1; lineHeight: 1.3 }
          Rectangle {
            Layout.fillWidth: true
            implicitHeight: inf.implicitHeight + 24
            radius: 12; color: Theme.field; border.color: Theme.separator
            GridLayout {
              id: inf
              x: 16; y: 12; width: parent.width - 32
              columns: 2; columnSpacing: 20; rowSpacing: 6
              Txt { text: "Source"; color: Theme.textDim; font.pixelSize: Theme.small } Txt { text: app.detail.startsWith("cli.") ? "Its makers' official installer" : ((app.entry(app.detail) || {}).remote === "artcraft-oci" ? "ArtCraft (getartcraft.com)" : "Flathub"); font.pixelSize: Theme.small }
              Txt { text: "Identifier"; color: Theme.textDim; font.pixelSize: Theme.small } Txt { text: app.detail; font.pixelSize: Theme.small }
              Txt { text: "Installs for"; color: Theme.textDim; font.pixelSize: Theme.small } Txt { text: app.detail.startsWith("cli.") ? "You; opens in Terminal" : "You (no password needed), in its own sandbox"; font.pixelSize: Theme.small }
            }
          }
        }
      }
    }

    // ---- pieces
    component StoreIcon: Item {
      id: si
      property string appId
      Image {
        id: ii
        anchors.fill: parent
        source: app.iconOf(si.appId)
        // Some apps' icons are filed under their desktop file name.
        onStatusChanged: if (status === Image.Error && String(source).indexOf(".desktop.png") < 0 && si.appId) source = app.iconDir ? "file://" + app.iconDir + si.appId + ".desktop.png" : ""
        sourceSize: Qt.size(256, 256)
        smooth: true; mipmap: true
        asynchronous: true
        visible: status === Image.Ready
      }
      // Command-line tools: their mark on their colour.
      readonly property var e: app.entry(si.appId)
      Rectangle {
        anchors.fill: parent
        visible: !!si.e && !!si.e.color && ii.status !== Image.Ready
        radius: width * 0.22
        gradient: Gradient {
          GradientStop { position: 0; color: si.e && si.e.color ? Qt.lighter(si.e.color, 1.25) : "#555" }
          GradientStop { position: 1; color: si.e && si.e.color ? si.e.color : "#333" }
        }
        border.color: Qt.rgba(1, 1, 1, 0.18)
        Txt { anchors.centerIn: parent; text: si.e ? (si.e.mark || si.e.name.charAt(0)) : ""; font.pixelSize: parent.width * (si.e && si.e.mark && si.e.mark.length > 2 ? 0.26 : 0.4); font.weight: Font.Bold; color: "#ffffff" }
      }
      // Until Flathub's icon is here: the app's initial on a tile.
      Rectangle {
        anchors.fill: parent
        visible: ii.status !== Image.Ready && !(si.e && si.e.color)
        radius: width * 0.22
        color: Theme.tile
        border.color: Theme.separator
        Txt { anchors.centerIn: parent; text: app.nameOf(si.appId).charAt(0); font.pixelSize: parent.width * 0.42; font.weight: Font.Bold; color: Theme.textDim }
      }
    }

    component Card: Rectangle {
      id: card
      property var a
      implicitHeight: 76
      radius: 12
      color: ch.hovered ? Theme.hover : "transparent"
      Behavior on color { ColorAnimation { duration: Theme.fast } }
      StoreIcon { id: ci; appId: card.a.id; width: 56; height: 56; x: 10; anchors.verticalCenter: parent.verticalCenter }
      Column {
        anchors { left: ci.right; leftMargin: 12; right: gb.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
        spacing: 3
        Txt { width: parent.width; text: card.a.name; font.weight: Font.Bold }
        Txt { width: parent.width; text: card.a.summary; color: Theme.textDim; font.pixelSize: Theme.small }
      }
      GetButton { id: gb; appId: card.a.id; update: app.section === "Updates" && !app.query && app.updates.indexOf(card.a.id) >= 0; anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } }
      Rectangle { anchors { left: ci.right; leftMargin: 12; right: parent.right; bottom: parent.bottom } height: 1; color: Theme.separator; opacity: 0.6 }
      HoverHandler { id: ch }
      // Not when the tap was on its Get/Open button.
      TapHandler { onTapped: ev => { const q = gb.mapFromItem(card, ev.position.x, ev.position.y); if (!gb.contains(q)) app.detail = card.a.id } }
    }

    // Get / progress ring / Open, in one pill.
    component GetButton: Item {
      id: gbtn
      property string appId
      property bool big: false
      property bool light: false
      property bool update: false           // "Update" instead of "Open"
      readonly property var job: app.jobs[appId] || (update && app.jobs["*"] ? app.jobs["*"] : undefined)
      readonly property bool have: !!app.installed[appId]
      width: job ? height : pill.width
      height: big ? 32 : 28
      Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }
      Rectangle {
        id: pill
        visible: !gbtn.job
        width: gt.implicitWidth + (gbtn.big ? 40 : 30); height: parent.height; radius: height / 2
        color: gbtn.light ? Qt.rgba(1, 1, 1, 0.92) : (gbtn.have ? Theme.hover : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16))
        scale: pt.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: Theme.fast } }
        Txt { id: gt; anchors.centerIn: parent; text: gbtn.update ? "Update" : (gbtn.have ? "Open" : "Get"); font.weight: Font.Bold; color: gbtn.light ? "#1c1c1e" : Theme.accent }
        TapHandler { id: pt; enabled: app.ready || gbtn.have; onTapped: gbtn.update ? app.start(gbtn.appId, "update") : (gbtn.have ? app.open(gbtn.appId) : app.start(gbtn.appId, "install")) }
      }
      // Progress ring while it downloads, as on a Mac: a grey track that fills
      // with the accent colour from the top, and a stop square that stays still
      // in the middle. Until the size is known, a short arc goes round instead.
      Item {
        anchors.fill: parent
        visible: !!gbtn.job
        readonly property real p: gbtn.job ? gbtn.job.progress : 0
        readonly property bool waiting: !!gbtn.job && p <= 0
        Canvas {
          id: track
          anchors.fill: parent
          onPaint: {
            const c = getContext("2d"); c.reset()
            c.lineWidth = 2.5; c.strokeStyle = Theme.separator
            c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 2, 0, Math.PI * 2); c.stroke()
          }
          Component.onCompleted: requestPaint()
        }
        Canvas {
          id: arc
          anchors.fill: parent
          property real p: parent.p
          property bool waiting: parent.waiting
          onPChanged: requestPaint()
          onWaitingChanged: { requestPaint(); if (!waiting) rotation = 0 }
          onVisibleChanged: requestPaint()
          RotationAnimation on rotation { running: arc.waiting && arc.visible; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
          onPaint: {
            const c = getContext("2d"); c.reset()
            c.lineWidth = 2.5; c.lineCap = "round"; c.strokeStyle = Theme.accent
            const a = waiting ? 0.22 : Math.max(0.02, Math.min(1, p))
            c.beginPath(); c.arc(width / 2, height / 2, width / 2 - 2, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * a); c.stroke()
          }
        }
        Rectangle {
          anchors.centerIn: parent
          width: 8; height: 8; radius: 1.5
          color: Theme.accent
        }
        // The square in the middle stops the download.
        TapHandler { enabled: !!gbtn.job && gbtn.job.kind === "install"; onTapped: app.cancel(gbtn.appId) }
        HoverHandler { enabled: !!gbtn.job && gbtn.job.kind === "install"; cursorShape: Qt.PointingHandCursor }
      }
    }
  }
}
