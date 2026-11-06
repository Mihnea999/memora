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
      label: "Magnified size"; last: true
      opacity: Prefs.magnify ? 1 : 0.4
      Slider { implicitWidth: 220; sym: "plus"; value: (Prefs.magnifySize - 56) / 56; onMoved: v => Prefs.set("magnifySize", Math.round(56 + v * 56)) }
    }
  }
  Kit.Group {
    header: "Menu Bar"
    Kit.Row { label: "Show the date"; Kit.Switch { checked: Prefs.showDate; onToggled: on => Prefs.set("showDate", on) } }
    Kit.Row { label: "24-hour time"; last: true; Kit.Switch { checked: Prefs.clock24; onToggled: on => Prefs.set("clock24", on) } }
  }
}
