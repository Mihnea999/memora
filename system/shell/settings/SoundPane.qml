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

  Kit.Group {
    Kit.Row {
      label: "Output volume"; badge: "sound"; badgeColor: "#ff4fa0"; last: true
      RowLayout {
        spacing: 10
        Slider { implicitWidth: 220; sym: Sys.muted ? "sound-off" : "sound"; value: Sys.muted ? 0 : Sys.volume; onMoved: v => Sys.setVolume(v) }
        Kit.Switch { checked: !Sys.muted; onToggled: Sys.toggleMute() }
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
