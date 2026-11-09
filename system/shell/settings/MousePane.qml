import QtQuick
import QtQuick.Layouts
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  title: Host.hasTouchpad ? "Trackpad & Mouse" : "Mouse"
  InputPrefs { id: prefs }
  Kit.Group {
    header: "Pointer"
    Kit.Row {
      label: "Tracking speed"; last: true
      Slider { implicitWidth: 220; sym: "arrow"; value: (prefs.get("speed", 0) + 1) / 2; onMoved: v => prefs.set("speed", Math.round((v * 2 - 1) * 100) / 100) }
    }
  }
  Kit.Group {
    visible: Host.hasTouchpad
    header: "Trackpad"
    Kit.Row { label: "Tap to click"; Kit.Switch { checked: prefs.get("tap_to_click", true); onToggled: on => prefs.set("tap_to_click", on) } }
    Kit.Row { label: "Natural scrolling"; last: true; Kit.Switch { checked: prefs.get("natural_scroll", true); onToggled: on => prefs.set("natural_scroll", on) } }
  }
  Kit.Group {
    header: "Mouse"
    Kit.Row { label: "Natural scrolling"; last: true; Kit.Switch { checked: prefs.get("mouse_natural", false); onToggled: on => prefs.set("mouse_natural", on) } }
  }
  Kit.Group {
    header: "Windows"
    Kit.Row {
      label: "Focus follows the pointer"; last: true
      detail: "Off: a window takes the keyboard when you click it, as on a Mac"
      Kit.Switch { checked: prefs.get("focus_follows", false); onToggled: on => prefs.set("focus_follows", on) }
    }
  }
}
