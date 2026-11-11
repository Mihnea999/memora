import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// A liquid-glass surface, drawn by glass.frag (after ybouane/liquidglass): a thin
// tint, a rim rounded like a lens that catches the light, brightest at the top.
// The compositor frosts what is behind it. Where the window itself draws what is
// behind (the desktop picture under the widgets), the rim also bends that
// picture inwards, as real glass does. No shadow, no dark outline.
Item {
  id: g
  property real radius: Theme.radiusLarge
  property color fill: Theme.glass
  // How far in from the edge the rounded rim reaches.
  // How deep the rounded rim reaches in. Small things (buttons, the Dock) are
  // lens all over, as ybouane/liquidglass (40); panels that carry text get a
  // thin rim, or it pulls what is under them (a widget's icon) in under the text.
  property real bevel: Math.min(width, height) <= 90 && Math.max(width, height) <= 160 ? 40 : 16
  // How much what is behind is frosted (System Settings > Frost); 1 frosts it beyond reading.
  property real frost: Prefs.blur
  default property alias content: inner.data
  // In a window that draws what is behind the glass itself (the desktop picture
  // under the widgets) the compositor has nothing to frost: `backdrop` is then
  // that picture already frosted, and backdropRect the part under this glass.
  property Item backdrop: null
  property rect backdropRect

  ShaderEffectSource {
    id: slice
    visible: false
    sourceItem: g.backdrop
    sourceRect: g.backdropRect
    live: g.backdrop !== null
  }
  Item { id: blank; width: 1; height: 1; visible: false; layer.enabled: true }

  ShaderEffect {
    anchors.fill: parent
    readonly property vector2d size: Qt.vector2d(width, height)
    readonly property real radius: g.radius
    readonly property real zRadius: g.bevel
    readonly property real refraction: 0.69
    readonly property real chroma: 0.05
    readonly property real edgeLight: 0.05 * Theme.shine   // ybouane/liquidglass's defaults
    readonly property real fresnel: 1.0 * Theme.shine
    readonly property real hasBackdrop: g.backdrop !== null ? 1 : 0
    readonly property real darkMode: Theme.dark ? 1 : 0
    readonly property real adapt: Theme.tinted || Prefs.reduceTransparency ? 1 : 0
    readonly property color fill: g.fill
    readonly property var source: g.backdrop !== null ? slice : blank
    fragmentShader: Qt.resolvedUrl("glass.frag.qsb")
  }
  Item { id: inner; anchors.fill: parent }

  // In the shell's panels (layer surfaces) the compositor draws what is behind
  // the glass, bent at the rim (system/plugin/glass.cpp): tell it where the
  // glass is, after every frame in which it may have moved, faded or resized.
  readonly property var host: QsWindow.window
  // A menu (a popup) belongs to the panel it hangs from.
  readonly property bool inPopup: !!host && host instanceof PopupWindow
  readonly property var panel: inPopup ? (host.anchor ? host.anchor.window : null) : host
  readonly property string layerName: {
    // Only panels: asking an app window for its layer would make it one.
    if (!panel || backdrop !== null || !(panel instanceof PanelWindow)) return ""
    const ls = panel.WlrLayershell
    return ls && typeof ls.namespace === "string" ? ls.namespace : ""
  }
  property int syncId: 0
  function sync() {
    if (layerName === "" || Prefs.reduceTransparency) { unsync(); return }
    let a = 1
    for (let p = g; p && a > 0.01; p = p.parent) a = p.visible ? a * p.opacity : 0
    if (a <= 0.01 || width < 4 || height < 4) { unsync(); return }
    const r = g.mapToItem(null, 0, 0, width, height)
    const k = r.width / width
    if (!syncId) syncId = GlassSync.newId()
    const scr = panel.screen || host.screen
    GlassSync.put(syncId, [layerName, scr ? scr.name : "-", Math.round(host.width), Math.round(host.height),
      r.x.toFixed(1), r.y.toFixed(1), r.width.toFixed(1), r.height.toFixed(1),
      (Math.min(radius, width / 2, height / 2) * k).toFixed(1), (bevel * k).toFixed(1), a.toFixed(2), inPopup ? "P" : "L", g.frost.toFixed(2), Theme.tinted ? 1 : 0].join(" "))
  }
  function unsync() { if (syncId) GlassSync.drop(syncId) }
  Connections {
    target: g.layerName !== "" ? g.Window.window : null
    function onFrameSwapped() { g.sync() }
  }
  Component.onCompleted: if (layerName !== "") Qt.callLater(sync)
  Component.onDestruction: unsync()
}
