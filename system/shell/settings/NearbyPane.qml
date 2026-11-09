import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core
import qs.ui
import qs.settings

// Nearby Share: who can send you files (like AirDrop's Off / Contacts Only /
// Everyone), the trusted devices, the name others see. The settings live in
// ~/.config/memora/share.json and are changed through bin/memora-share.
Kit.Page {
  id: p
  title: "Nearby Share"
  property var conf: ({})
  readonly property string mode: conf.receive === true || conf.receive === undefined || conf.receive === "everyone" ? "everyone"
                                : conf.receive === "trusted" ? "trusted" : "off"
  readonly property var trusted: conf.trusted || []
  readonly property bool autoAccept: conf.autoAccept !== false
  property string defaultName: ""

  FileView {
    path: Quickshell.env("HOME") + "/.config/memora/share.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { p.conf = JSON.parse(text()) } catch (e) { p.conf = ({}) } }
    onLoadFailed: p.conf = ({})
  }
  // The name it has when you haven't picked one ("Mihnea's Memora").
  Kit.Cmd { id: nm; onDone: out => { try { p.defaultName = JSON.parse(out).me.alias } catch (e) {} } }
  Component.onCompleted: nm.exec(["memora-share", "devices"])

  function run(args) { Quickshell.execDetached(["memora-share"].concat(args)) }

  Kit.Group {
    footer: p.mode === "trusted" ? "Others are turned away without asking you." : ""
    Kit.Row {
      label: "Receive from"; badge: "share"; badgeColor: "#2f7bff"
      Kit.Choice {
        value: p.mode
        options: [{ text: "Off", value: "off" }, { text: "Trusted Devices", value: "trusted" }, { text: "Everyone", value: "everyone" }]
        onPicked: v => p.run(["receive", v])
      }
    }
    Kit.Row {
      label: "Name"; last: true
      Kit.Field {
        id: nameField
        width: 200
        placeholder: p.defaultName
        text: p.conf.alias || ""
        onAccepted: { p.run(["name", text]); focus = false }
        onActiveFocusChanged: if (!activeFocus && text !== (p.conf.alias || "")) p.run(["name", text])
      }
    }
  }

  Kit.Group {
    header: "Trusted Devices"
    footer: "Add one with Always Accept when it sends you something. On public Wi-Fi, keep \"Accept without asking\" off: a device can be imitated."
    Kit.Row {
      label: "Accept without asking"
      last: p.trusted.length === 0
      Kit.Switch { checked: p.autoAccept; onToggled: on => p.run(["autoaccept", on ? "on" : "off"]) }
    }
    Repeater {
      model: p.trusted
      delegate: Kit.Row {
        required property var modelData
        required property int index
        badge: modelData.kind === "Quick Share" ? "phone" : "laptop"
        badgeColor: "#8a8d96"
        label: modelData.name
        detail: modelData.kind
        last: index === p.trusted.length - 1
        Kit.Button { text: "Remove"; danger: true; onClicked: p.run(["trust", "remove", modelData.id]) }
      }
    }
  }
}
