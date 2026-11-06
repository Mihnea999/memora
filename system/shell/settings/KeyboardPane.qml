import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Keyboard"
  InputPrefs { id: prefs }
  readonly property var layouts: [["us", "English (US)"], ["gb", "English (UK)"], ["ro", "Romanian"], ["de", "German"], ["fr", "French"],
    ["es", "Spanish"], ["it", "Italian"], ["pt", "Portuguese"], ["hu", "Hungarian"], ["pl", "Polish"], ["ru", "Russian"], ["ua", "Ukrainian"]]

  Kit.Group {
    header: "Input source"
    Repeater {
      model: p.layouts
      delegate: Kit.Row {
        required property var modelData
        required property int index
        label: modelData[1]
        last: index === p.layouts.length - 1
        clickable: true
        onClicked: prefs.set("layout", modelData[0])
        Sym { visible: prefs.get("layout", "") === modelData[0]; name: "check"; width: 14; height: 14; color: Theme.accent }
      }
    }
  }
  Kit.Group {
    header: "Key repeat"
    Kit.Row {
      label: "Repeat rate"
      Slider { implicitWidth: 200; sym: "plus"; value: (prefs.get("repeat_rate", 40) - 10) / 50; onMoved: v => prefs.set("repeat_rate", Math.round(10 + v * 50)) }
    }
    Kit.Row {
      label: "Delay until repeat"; last: true
      Slider { implicitWidth: 200; sym: "plus"; value: 1 - (prefs.get("repeat_delay", 250) - 150) / 650; onMoved: v => prefs.set("repeat_delay", Math.round(150 + (1 - v) * 650)) }
    }
  }
  Kit.Group {
    Kit.Row { label: "Keyboard Shortcuts…"; last: true; clickable: true; onClicked: Quickshell.execDetached(["memora-keys"]); Sym { name: "chevron"; width: 12; height: 12; color: Theme.textDim } }
  }
}
