import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

// Reset: the settings back to how they came, or the whole computer erased
// (bin/memora-reset). Each asks once more before doing anything; erasing also
// asks for the password.
Kit.Page {
  id: p
  title: "Reset"
  property string asking: ""          // "" | settings | all
  property string status: ""
  property bool busy: false

  Kit.Cmd {
    id: run
    onDone: out => { p.busy = false; p.status = out.trim() }
    // Erase: nothing comes back when the password dialog is closed.
    onExited: code => { if (p.busy) { p.busy = false; p.status = code === 0 ? "" : "Nothing was erased." } }
  }

  Kit.Group {
    header: "Settings"
    footer: p.asking === "settings" ? "" : (p.status || "The look, Dock, sounds, widgets, keyboard shortcuts, displays and Memora AI go back to how they were on the first day. Your files and apps stay as they are.")
    Kit.Row {
      label: "Reset Settings"; last: p.asking !== "settings"
      Kit.Button { text: "Reset Settings…"; enabled: !p.busy; opacity: enabled ? 1 : 0.4; onClicked: { p.status = ""; p.asking = "settings" } }
    }
    Confirm {
      visible: p.asking === "settings"
      text: "Put all settings back to how they came? Your files and apps are not touched. The desktop blinks once while it starts again."
      action: "Reset Settings"
      onAccepted: { p.asking = ""; p.busy = true; p.status = "Resetting…"; run.exec(["memora-reset", "settings"]) }
    }
  }

  Kit.Group {
    header: "This Computer"
    footer: p.asking === "all" ? "" : "For giving the computer away or starting over. Everything in your home folder is deleted (documents, pictures, downloads, mail, passwords kept by apps), with the apps you added, saved Wi-Fi networks and Bluetooth devices. Memora itself and your account stay: the name and password are the ones you have now."
    Kit.Row {
      label: "Erase All Content and Settings"; last: p.asking !== "all"
      Kit.Button { text: "Erase…"; danger: true; enabled: !p.busy; opacity: enabled ? 1 : 0.4; onClicked: { p.status = ""; p.asking = "all" } }
    }
    Confirm {
      visible: p.asking === "all"
      danger: true
      text: "Erase this computer? Everything in your home folder, the apps you added and the saved networks are deleted for good. This can't be undone. Copy what you want to keep to another disk first.\nAfter your password the session ends, and the computer restarts by itself when it is done."
      action: "Erase This Computer"
      onAccepted: { p.asking = ""; p.busy = true; run.exec(["memora-reset", "all"]) }
    }
  }

  // The second question, inside the group it belongs to.
  component Confirm: Item {
    id: c
    property string text: ""
    property string action: "OK"
    property bool danger: false
    signal accepted()
    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 24
    ColumnLayout {
      id: body
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
      spacing: 10
      Txt { Layout.fillWidth: true; text: c.text; wrapMode: Text.Wrap; color: c.danger ? Theme.red : Theme.text; font.pixelSize: Theme.small + 0.5 }
      RowLayout {
        Layout.alignment: Qt.AlignRight
        spacing: 8
        Kit.Button { text: "Cancel"; onClicked: p.asking = "" }
        Kit.Button { text: c.action; primary: !c.danger; danger: c.danger; onClicked: c.accepted() }
      }
    }
  }
}
