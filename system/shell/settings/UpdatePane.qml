import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Software Update"
  property string count: ""
  property string last: ""
  Kit.Cmd { id: q; onDone: out => { const [c, l] = out.split("--\n"); p.count = c.trim(); p.last = (l || "").trim() } }
  function check() { p.count = "…"; q.exec(["bash", "-c", "(checkupdates 2>/dev/null || pacman -Qu 2>/dev/null) | wc -l; echo '--'; grep -m1 -oP '^\\[\\K[^]]+(?=\\] \\[PACMAN\\] starting full system upgrade)' <(tac /var/log/pacman.log) 2>/dev/null"]) }
  Component.onCompleted: check()

  Kit.Group {
    Kit.Row {
      label: p.count === "0" ? "Memora is up to date" : (p.count === "…" ? "Checking…" : p.count + " updates available")
      detail: "Memora " + Host.version + (p.last ? " · last updated " + p.last.slice(0, 10) : "")
      badge: "gear"; badgeColor: "#8a8d96"; last: true
      RowLayout { spacing: 8
        Kit.Button { text: "Check"; onClicked: p.check() }
        Kit.Button { text: "Update Now"; primary: true; onClicked: Quickshell.execDetached(["ptyxis", "--new-window", "--", "memora-update"]) }
      }
    }
  }
  Kit.Group {
    footer: "A snapshot of the system is taken before every update, so you can go back if something breaks."
    Kit.Row { label: "Snapshots"; last: true; Kit.Button { text: "Show…"; onClicked: Quickshell.execDetached(["ptyxis", "--new-window", "--", "bash", "-c", "sudo snapper list; read -rsn1 -p 'Press a key to close'"]) } }
  }
}
