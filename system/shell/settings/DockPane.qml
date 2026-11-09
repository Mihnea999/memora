import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  title: "Dock & Menu Bar"
  Kit.Group {
    header: "Dock"
    Kit.Row {
      label: "Size"
      Slider { implicitWidth: 220; sym: "plus"; value: (Prefs.dockSize - 36) / 36; onMoved: v => Prefs.set("dockSize", Math.round(36 + v * 36)) }
    }
    Kit.Row {
      label: "Magnification"
      Kit.Switch { checked: Prefs.magnify; onToggled: on => Prefs.set("magnify", on) }
    }
    Kit.Row {
      label: "Magnified size"
      opacity: Prefs.magnify ? 1 : 0.4
      Slider { implicitWidth: 220; sym: "plus"; value: (Prefs.magnifySize - 56) / 56; onMoved: v => Prefs.set("magnifySize", Math.round(56 + v * 56)) }
    }
    Kit.Row {
      label: "Position on screen"
      Kit.Choice {
        value: Prefs.dockPosition
        options: [{ text: "Left", value: "left" }, { text: "Bottom", value: "bottom" }, { text: "Right", value: "right" }]
        onPicked: v => Prefs.set("dockPosition", v)
      }
    }
    Kit.Row {
      label: "Hide the Dock"
      detail: (Prefs.dockHiding || (Prefs.dockAutohide ? "always" : "auto")) === "auto" ? "Automatic: when a window needs the room on small screens · Super+Alt+D"
        : "Point at the edge of the screen to show it · Super+Alt+D"
      Kit.Choice {
        value: Prefs.dockHiding || (Prefs.dockAutohide ? "always" : "auto")
        options: [{ text: "Auto", value: "auto" }, { text: "Never", value: "never" }, { text: "When Needed", value: "smart" }, { text: "Always", value: "always" }]
        onPicked: v => Prefs.set("dockHiding", v)
      }
    }
    Kit.Row {
      label: "Show indicators for open apps"
      Kit.Switch { checked: Prefs.dockDots; onToggled: on => Prefs.set("dockDots", on) }
    }
    Kit.Row {
      label: "Animate opening apps"; last: true
      Kit.Switch { checked: Prefs.dockBounce; onToggled: on => Prefs.set("dockBounce", on) }
    }
  }
  Kit.Group {
    header: "Menu Bar"
    Kit.Row { label: "Show the date"; Kit.Switch { checked: Prefs.showDate; onToggled: on => Prefs.set("showDate", on) } }
    Kit.Row { label: "24-hour time"; last: true; Kit.Switch { checked: Prefs.clock24; onToggled: on => Prefs.set("clock24", on) } }
  }
}
