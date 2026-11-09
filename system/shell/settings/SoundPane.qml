import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Sound"
  readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)
  readonly property var sources: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
  PwObjectTracker { objects: p.sinks.concat(p.sources) }

  // Alert sounds in system/sounds (made by tools/sounds.py).
  readonly property var alerts: [
    { id: "glint", name: "Glint" }, { id: "drop", name: "Drop" }, { id: "chime", name: "Chime" }, { id: "bell", name: "Bell" },
    { id: "pebble", name: "Pebble" }, { id: "bubble", name: "Bubble" }, { id: "breeze", name: "Breeze" }, { id: "pluck", name: "Pluck" }]
  function preview(id) { Quickshell.execDetached(["memora-sound", "preview", id]) }
  // Hear the new alert volume once the slider stops.
  Timer { id: volPreview; interval: 350; onTriggered: p.preview(Prefs.alertSound) }

  Kit.Group {
    Kit.Row {
      label: "Output volume"; badge: "sound"; badgeColor: "#ff4fa0"; last: true
      RowLayout {
        spacing: 10
        Slider { implicitWidth: 220; sym: Sys.muted || Sys.volume === 0 ? "sound-off" : "sound"; value: Sys.volume; muted: Sys.muted; symToggles: true; onSymClicked: Sys.toggleMute(); onMoved: v => Sys.changeVolume(v) }
        Kit.Switch { checked: !Sys.muted; onToggled: Sys.toggleMute() }
      }
    }
  }
  Kit.Group {
    header: "Sound Effects"
    Kit.Row {
      label: "Alert volume"; badge: "sound"; badgeColor: "#ff9f0a"
      Slider { implicitWidth: 220; sym: Prefs.alertVolume > 0 ? "sound" : "sound-off"; value: Prefs.alertVolume; onMoved: v => { Prefs.set("alertVolume", Math.round(v * 100) / 100); volPreview.restart() } }
    }
    Kit.Row {
      label: "Play sound on startup"
      Kit.Switch { checked: Prefs.startupSound; onToggled: on => Prefs.set("startupSound", on) }
    }
    Kit.Row {
      label: "Play user interface sound effects"
      detail: "Screenshots, emptying the Trash, plugging in a charger"
      Kit.Switch { checked: Prefs.uiSounds; onToggled: on => Prefs.set("uiSounds", on) }
    }
    Kit.Row {
      label: "Play feedback when volume is changed"
      last: true
      Kit.Switch { checked: Prefs.volumeFeedback; onToggled: on => Prefs.set("volumeFeedback", on) }
    }
  }
  Kit.Group {
    header: "Alert sound"
    Repeater {
      model: p.alerts
      delegate: Kit.Row {
        required property var modelData
        required property int index
        label: modelData.name
        last: index === p.alerts.length - 1
        clickable: true
        onClicked: { Prefs.set("alertSound", modelData.id); p.preview(modelData.id) }
        Sym { visible: Prefs.alertSound === modelData.id; name: "check"; width: 14; height: 14; color: Theme.accent }
      }
    }
  }
  Kit.Group {
    header: "Output"
    Repeater {
      model: p.sinks
      delegate: Kit.Row {
        required property var modelData
        required property int index
        label: modelData.description || modelData.nickname || modelData.name
        last: index === p.sinks.length - 1
        clickable: true
        onClicked: Pipewire.preferredDefaultAudioSink = modelData
        Sym { visible: Pipewire.defaultAudioSink === modelData; name: "check"; width: 14; height: 14; color: Theme.accent }
      }
    }
    Kit.Row { visible: p.sinks.length === 0; label: "No output devices"; last: true }
  }
  Kit.Group {
    header: "Input"
    Repeater {
      model: p.sources
      delegate: Kit.Row {
        required property var modelData
        required property int index
        label: modelData.description || modelData.nickname || modelData.name
        last: index === p.sources.length - 1
        clickable: true
        onClicked: Pipewire.preferredDefaultAudioSource = modelData
        RowLayout {
          spacing: 10
          Slider { implicitWidth: 160; sym: "sound"; value: modelData.audio ? modelData.audio.volume : 0; onMoved: v => modelData.audio.volume = v }
          Sym { visible: Pipewire.defaultAudioSource === modelData; name: "check"; width: 14; height: 14; color: Theme.accent }
        }
      }
    }
    Kit.Row { visible: p.sources.length === 0; label: "No input devices"; last: true }
  }
}
