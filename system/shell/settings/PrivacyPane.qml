import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Privacy & Security"
  property string firewall: "…"        // on | off | …
  property string disk: "…"            // encrypted | plain
  property bool screenControl: true
  readonly property string aiFile: Quickshell.env("HOME") + "/.config/memora/ai.json"

  Kit.Cmd { id: fwq; onDone: out => p.firewall = out.trim() === "on" ? "on" : "off" }
  Kit.Cmd { id: fwset; onDone: p.checkFirewall() }
  Kit.Cmd { id: diskq; onDone: out => p.disk = out.trim() === "yes" ? "encrypted" : "plain" }
  function checkFirewall() { fwq.exec(["bash", "-c", "systemctl is-active -q ufw && grep -q '^ENABLED=yes' /etc/ufw/ufw.conf && echo on || echo off"]) }
  Component.onCompleted: {
    checkFirewall()
    diskq.exec(["bash", "-c", "lsblk -no TYPE \"$(findmnt -no SOURCE / | sed 's/\\[.*//')\" -s 2>/dev/null | grep -q crypt && echo yes"])
  }
  FileView {
    id: ai
    path: p.aiFile; printErrors: false
    onLoaded: { try { p.screenControl = JSON.parse(text()).screenControl !== false } catch (e) {} }
  }
  function setScreenControl(on) {
    let c = {}
    try { c = JSON.parse(ai.text()) } catch (e) {}
    c.screenControl = on
    ai.setText(JSON.stringify(c, null, 2) + "\n")
    p.screenControl = on
  }

  Kit.Group {
    header: "Security"
    Kit.Row {
      label: "Firewall"; badge: "shield"; badgeColor: "#34c759"
      detail: p.firewall === "on" ? "On: other computers cannot connect to this one" : (p.firewall === "off" ? "Off: incoming connections are allowed" : "Checking…")
      Kit.Switch {
        checked: p.firewall === "on"
        onToggled: on => { p.firewall = "…"; fwset.exec(["pkexec", "/usr/share/memora/bin/memora-admin", "firewall", on ? "on" : "off"]) }
      }
    }
    Kit.Row {
      label: "Disk encryption"; badge: "lock"; badgeColor: "#2f7bff"
      detail: p.disk === "encrypted" ? "On: your files can't be read without your password" : (p.disk === "plain" ? "Off: chosen when Memora was installed" : "Checking…")
      Kit.Value { text: p.disk === "encrypted" ? "On" : (p.disk === "plain" ? "Off" : "") }
    }
    Kit.Row {
      label: "Administrator"; badge: "user"; badgeColor: "#8a8d96"; last: true
      detail: "Changes to the system always ask for your password"
      Kit.Value { text: "Protected" }
    }
  }

  Kit.Group {
    header: "Lock Screen"
    footer: "The screen also locks when the computer goes to sleep or the lid closes, and your password is needed to get back in."
    Kit.Row {
      label: "Lock after inactivity"
      Kit.Choice {
        value: Prefs.lockAfter
        options: [{ text: "2 min", value: 2 }, { text: "5 min", value: 5 }, { text: "15 min", value: 15 }, { text: "Never", value: 0 }]
        onPicked: v => Prefs.set("lockAfter", v)
      }
    }
    Kit.Row {
      label: "Sleep after inactivity"; last: true
      Kit.Choice {
        value: Prefs.sleepAfter
        options: [{ text: "15 min", value: 15 }, { text: "30 min", value: 30 }, { text: "1 hour", value: 60 }, { text: "Never", value: 0 }]
        onPicked: v => Prefs.set("sleepAfter", v)
      }
    }
  }

  Kit.Group {
    header: "Privacy"
    footer: "Memora sends nothing about you anywhere. Memora AI talks only to the provider you chose in its settings, and only when you ask it something."
    Kit.Row {
      label: "Memora AI can see and use the screen"; badge: "ai"; badgeColor: "#8a5cff"
      detail: "Screenshots, clicks and typing in apps, to do what you ask"
      Kit.Switch { checked: p.screenControl; onToggled: on => p.setScreenControl(on) }
    }
    Kit.Row {
      label: "Clipboard history"; badge: "info"; badgeColor: "#8a8d96"; last: true
      detail: "Kept on this computer only"
      Kit.Button { text: "Clear"; onClicked: Quickshell.execDetached(["bash", "-c", "cliphist wipe && notify-send -a Memora 'Clipboard history cleared'"]) }
    }
  }

  Kit.Group {
    header: "Updates"
    Kit.Row {
      label: "Check for updates automatically"; badge: "download"; badgeColor: "#2f7bff"; last: true
      detail: "Security fixes arrive with system updates"
      Kit.Switch { checked: Prefs.updateCheck; onToggled: on => Prefs.set("updateCheck", on) }
    }
  }
}
