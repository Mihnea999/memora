import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  title: "Animations"
  Kit.Group {
    Kit.Row {
      label: "Animations"; badge: "play"; badgeColor: "#ff6b8a"
      Kit.Switch { checked: Prefs.animations; onToggled: on => Prefs.set("animations", on) }
    }
    Kit.Row {
      label: "Speed"; detail: Prefs.animationSpeed < 0.8 ? "Relaxed" : (Prefs.animationSpeed > 1.3 ? "Brisk" : "Natural")
      opacity: Prefs.animations ? 1 : 0.4
      Slider { implicitWidth: 220; sym: "play"; value: (Prefs.animationSpeed - 0.5) / 1.5; onMoved: v => Prefs.set("animationSpeed", Math.round((0.5 + v * 1.5) * 20) / 20) }
    }
    Kit.Row {
      label: "Windows appear"; last: true
      opacity: Prefs.animations ? 1 : 0.4
      Kit.Choice {
        value: Prefs.windowStyle
        options: [{ text: "Pop", value: "pop" }, { text: "Slide", value: "slide" }, { text: "Fade", value: "fade" }]
        onPicked: v => Prefs.set("windowStyle", v)
      }
    }
  }
  Kit.Group {
    header: "Dock"
    Kit.Row { label: "Magnify icons under the pointer"; Kit.Switch { checked: Prefs.magnify; onToggled: on => Prefs.set("magnify", on) } }
    Kit.Row { label: "Bounce apps while they open"; last: true; Kit.Switch { checked: Prefs.dockBounce; onToggled: on => Prefs.set("dockBounce", on) } }
  }

}
