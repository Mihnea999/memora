import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.core
import qs.ui
import qs.settings

// Displays: how screens work together, and each screen's resolution, refresh
// rate and scale. Everything goes through memora-display, which writes
// ~/.config/hypr/monitors.lua and applies it at once.
Kit.Page {
  id: p
  title: "Displays"
  property var cfg: ({ mode: "extend", main: "", arrange: "right", scale: {}, res: {} })
  property var mons: []           // hyprctl monitors all
  property bool nightShift: false
  Kit.Cmd { id: ns; onDone: out => p.nightShift = out.trim() !== "" }
  Kit.Cmd {
    id: st
    onDone: out => { try { const j = JSON.parse(out); p.cfg = j.config; p.mons = j.monitors } catch (e) {} }
  }
  Kit.Cmd { id: setter; onDone: refreshLater.restart() }
  Timer { id: refreshLater; interval: 600; onTriggered: p.refresh() }
  function refresh() { st.exec(["memora-display", "state"]) }
  function set(k, v) { setter.exec(["memora-display", "set", k, String(v)]) }
  function mode(m) { setter.exec(["memora-display", "mode", m]) }
  Component.onCompleted: { refresh(); ns.exec(["pgrep", "-x", "hyprsunset"]); gq.exec(["memora-gpu", "info"]) }
  Connections { target: Hyprland; function onRawEvent(ev) { if (ev.name.indexOf("monitor") === 0) refreshLater.restart() } }

  readonly property string mainName: p.cfg.main && p.mons.some(m => m.name === p.cfg.main) ? p.cfg.main : (p.mons[0] ? p.mons[0].name : "")
  function label(m) { return (m.make && m.model ? m.make + " " + m.model : (m.description || m.name)).replace(/\s+\(.*\)$/, "") }
  // A few sensible modes: unique resolutions, each with its best refresh rate.
  function modesOf(m) {
    const seen = {}, out = []
    ;(m.availableModes || []).forEach(s => {
      const r = s.match(/^(\d+)x(\d+)@([\d.]+)Hz$/); if (!r) return
      const k = r[1] + "x" + r[2]
      if (!seen[k]) { seen[k] = []; out.push(k) }
      seen[k].push(Math.round(parseFloat(r[3])))
    })
    return out.slice(0, 6).map(k => ({ res: k, rates: Array.from(new Set(seen[k])).sort((a, b) => b - a).slice(0, 4) }))
  }

  // ---- several screens --------------------------------------------------------
  Kit.Group {
    visible: p.mons.length > 1
    header: "Arrangement"
    footer: "Super+P"
    Kit.Row {
      label: "Use screens"
      Kit.Choice {
        value: p.cfg.mode
        options: [{ text: "Extend", value: "extend" }, { text: "Mirror", value: "mirror" }, { text: "Main Only", value: "main" }, { text: "Other Only", value: "second" }]
        onPicked: v => p.mode(v)
      }
    }
    Kit.Row {
      label: "Main screen"
      Kit.Choice {
        value: p.mainName
        options: p.mons.map(m => ({ text: m.model || m.name, value: m.name }))
        onPicked: v => p.set("main", v)
      }
    }
    Kit.Row {
      label: "Other screens are"; last: true
      enabled: p.cfg.mode === "extend"; opacity: enabled ? 1 : 0.4
      Kit.Choice {
        value: p.cfg.arrange
        options: [{ text: "Left", value: "left" }, { text: "Right", value: "right" }, { text: "Above", value: "above" }, { text: "Below", value: "below" }]
        onPicked: v => p.set("arrange", v)
      }
    }
  }

  // ---- each screen ------------------------------------------------------------------
  Repeater {
    model: p.mons
    delegate: Kit.Group {
      id: g
      required property var modelData
      readonly property var modes: p.modesOf(modelData)
      readonly property string curRes: modelData.width + "x" + modelData.height
      readonly property int curRate: Math.round(modelData.refreshRate || 60)
      header: p.label(modelData) + (modelData.name === p.mainName && p.mons.length > 1 ? " · Main" : "") + (modelData.disabled ? " · Off" : "")
      Kit.Row {
        label: "Resolution"
        Kit.Choice {
          value: g.curRes
          options: g.modes.slice(0, 4).map(x => ({ text: x.res.replace("x", "×"), value: x.res }))
          onPicked: v => { const mm = g.modes.find(x => x.res === v); p.set("res." + g.modelData.name, v + "@" + (mm ? mm.rates[0] : 60)) }
        }
      }
      Kit.Row {
        id: rateRow
        label: "Refresh rate"
        readonly property var rates: (g.modes.find(x => x.res === g.curRes) || { rates: [g.curRate] }).rates
        Kit.Choice {
          value: g.curRate
          options: rateRow.rates.map(r => ({ text: r + " Hz", value: r }))
          onPicked: v => p.set("res." + g.modelData.name, g.curRes + "@" + v)
        }
      }
      // Text size, like a Mac: from Larger Text to More Space, each showing the
      // size the screen then looks like (memora-display state lists the scales
      // Hyprland accepts and the screen's own default).
      Item {
        id: ts
        Layout.fillWidth: true
        implicitHeight: 150
        readonly property real cur: Math.round((p.cfg.scale[g.modelData.name] || g.modelData.scale || 1) * 1000) / 1000
        readonly property real def: g.modelData.defaultScale || 1
        // Up to five, centred on the default: two bigger, two smaller (never below
        // 1, never so big the screen looks smaller than 960 wide).
        readonly property var opts: {
          const all = (g.modelData.scales || []).filter(x => x.w >= 960 || x.scale === 1)
          if (!all.length) return []
          let i = all.findIndex(x => Math.abs(x.scale - ts.def) < 0.01)
          if (i < 0) i = 0
          let lo = Math.max(0, i - 2), hi = Math.min(all.length, lo + 5)
          lo = Math.max(0, hi - 5)
          return all.slice(lo, hi).reverse()
        }
        Txt { x: 12; y: 10; text: "Text size"; }
        Txt { anchors { right: parent.right; rightMargin: 12 } y: 10; text: "Larger Text  ←→  More Space"; color: Theme.textDim; font.pixelSize: Theme.small }
        Row {
          x: 12; y: 36
          spacing: 10
          Repeater {
            model: ts.opts
            delegate: Item {
              id: card
              required property var modelData
              readonly property bool on: Math.abs(modelData.scale - ts.cur) < 0.01
              readonly property bool isDefault: Math.abs(modelData.scale - ts.def) < 0.01
              width: Math.min(110, (ts.width - 24 - 40) / 5); height: 104
              // A small screen: the bigger the text, the bigger the window and bar in it.
              Rectangle {
                id: scr
                width: parent.width; height: width * 0.62; radius: 6
                color: Theme.field; clip: true
                border.width: card.on ? 2 : 1; border.color: card.on ? Theme.accent : Theme.separator
                readonly property real k: Math.min(1.6, card.modelData.scale / Math.max(1, ts.opts.length ? ts.opts[ts.opts.length - 1].scale : 1))
                Rectangle { width: parent.width; height: 3 * scr.k; color: Theme.textFaint; opacity: 0.6 }
                Rectangle {
                  x: 6; y: 3 * scr.k + 4; width: Math.min(parent.width - 10, 26 * scr.k); height: Math.min(parent.height - 14, 18 * scr.k)
                  radius: 2; color: Theme.dark ? "#3a3a40" : "#ffffff"; border.color: Theme.separator
                }
              }
              Txt { anchors { top: scr.bottom; topMargin: 5; horizontalCenter: scr.horizontalCenter } text: card.modelData.w + " × " + card.modelData.h; font.pixelSize: Theme.small - 0.5; font.weight: card.on ? Font.Bold : Font.Normal }
              Txt { anchors { top: scr.bottom; topMargin: 21; horizontalCenter: scr.horizontalCenter } visible: card.isDefault; text: "Default"; color: Theme.textDim; font.pixelSize: Theme.small - 1 }
              HoverHandler { cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: p.set("scale." + g.modelData.name, card.isDefault ? "default" : card.modelData.scale) }
              Tip { text: "Looks like " + card.modelData.w + " × " + card.modelData.h }
            }
          }
        }
      }
    }
  }

  // ---- graphics ----------------------------------------------------------------
  property var gpu: ({ cards: [], nvidiaDriver: "", hybrid: false, legacy: false, gamesOnDedicated: false })
  Kit.Cmd { id: gq; onDone: out => { try { p.gpu = JSON.parse(out) } catch (e) {} } }
  Kit.Cmd { id: gset; onDone: gq.exec(["memora-gpu", "info"]) }
  Kit.Group {
    header: "Graphics"
    footer: p.gpu.hybrid ? "The desktop runs on the built-in chip to save battery; games run on the NVIDIA card. To send another app there, start it with: memora-gpu run APP"
      : (p.gpu.legacy ? "This NVIDIA card is older than the current NVIDIA driver supports, so it uses the open-source driver." : "Drivers come with system updates, always the newest stable version.")
    Repeater {
      model: p.gpu.cards
      delegate: Kit.Row {
        required property string modelData
        required property int index
        label: modelData.replace(/\s*\[[0-9a-f]{4}:[0-9a-f]{4}\].*$/, "").replace(/^.*?: /, "").replace(/ Corporation| Inc\.|\(rev [0-9a-f]+\)/g, "")
        detail: modelData.toLowerCase().indexOf("nvidia") >= 0 && p.gpu.nvidiaDriver ? "NVIDIA driver " + p.gpu.nvidiaDriver : ""
        badge: "display"; badgeColor: modelData.toLowerCase().indexOf("nvidia") >= 0 ? "#76b900" : "#8a8d96"
        last: index === p.gpu.cards.length - 1 && !p.gpu.hybrid
      }
    }
    Kit.Row {
      visible: p.gpu.hybrid
      label: "Games use the NVIDIA card"; detail: "Steam, and every game it starts, native or Windows"; last: true
      Kit.Switch { checked: p.gpu.gamesOnDedicated; onToggled: on => gset.exec(["memora-gpu", "games", on ? "on" : "off"]) }
    }
  }

  Kit.Group {
    Kit.Row {
      label: "Night Shift"; badge: "moon"; badgeColor: "#ff9f2e"; last: true
      Kit.Switch {
        checked: p.nightShift
        onToggled: on => { p.nightShift = on; Quickshell.execDetached(on ? ["bash", "-c", "setsid hyprsunset -t 4200 >/dev/null 2>&1 &"] : ["pkill", "-x", "hyprsunset"]) }
      }
    }
  }
}
