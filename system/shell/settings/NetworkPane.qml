import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Network"
  property var devs: []
  property string ip: ""
  Kit.Cmd { id: c; onDone: out => {
    const [d, a] = out.split("--\n")
    p.devs = d.split("\n").filter(l => l && !l.startsWith("lo:")).map(l => { const f = l.split(":"); return { name: f[0], type: f[1], state: f[2], conn: f[3] } })
    p.ip = (a || "").trim()
  } }
  Component.onCompleted: c.exec(["bash", "-c", "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION dev; echo '--'; ip -4 -o addr show scope global | awk '{print $4}' | head -3"])

  Kit.Group {
    Repeater {
      model: p.devs
      delegate: Kit.Row {
        required property var modelData
        required property int index
        badge: modelData.type === "wifi" ? "wifi" : "control"
        badgeColor: modelData.state === "connected" ? "#34c759" : "#8a8d96"
        label: modelData.type === "wifi" ? "Wi-Fi" : (modelData.type === "ethernet" ? "Ethernet" : modelData.name)
        detail: modelData.state === "connected" ? "Connected · " + modelData.conn : (modelData.state || "")
        last: index === p.devs.length - 1
        Kit.Value { text: modelData.name }
      }
    }
  }
  Kit.Group {
    header: "Details"
    Kit.Row { label: "IP address"; Kit.Value { text: p.ip || "None" } }
    Kit.Row { label: "Advanced settings"; last: true; Kit.Button { text: "Open…"; onClicked: Quickshell.execDetached(["nm-connection-editor"]) } }
  }
}
