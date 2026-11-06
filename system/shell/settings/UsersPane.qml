import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Users"
  property string status: ""
  Kit.Cmd { id: run; onDone: out => { p.status = out.trim() || "Done."; Host.refresh() } }

  Kit.Group {
    Kit.Row { label: Host.fullName; detail: Host.user + " · Administrator"; badge: "user"; badgeColor: "#2f7bff"; last: true }
  }
  Kit.Group {
    header: "Name"
    Kit.Row {
      label: "Full name"; last: true
      RowLayout { spacing: 8
        Kit.Field { id: nameField; text: Host.fullName; width: 200 }
        Kit.Button { text: "Save"; onClicked: run.exec(["pkexec", "chfn", "-f", nameField.text, Host.user]) }
      }
    }
  }
  Kit.Group {
    header: "Password"
    footer: p.status
    Kit.Row { label: "New password"; Kit.Field { id: pw1; secret: true; width: 200 } }
    Kit.Row { label: "Repeat"; Kit.Field { id: pw2; secret: true; width: 200 } }
    Kit.Row {
      label: ""; last: true
      Kit.Button {
        text: "Change Password"; primary: true
        onClicked: {
          if (pw1.text.length < 4) { p.status = "Use at least 4 characters."; return }
          if (pw1.text !== pw2.text) { p.status = "The passwords do not match."; return }
          run.exec(["bash", "-c", "printf '%s:%s\\n' \"$1\" \"$2\" | pkexec chpasswd && echo 'Password changed.'", "_", Host.user, pw1.text])
          pw1.text = ""; pw2.text = ""
        }
      }
    }
  }
}
