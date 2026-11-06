import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Wi-Fi"
  property var nets: []
  property string joining: ""
  property string status: ""

  Kit.Cmd { id: scan; onDone: out => p.nets = out.split("\n").filter(l => l).map(l => {
    const f = l.replace(/\\:/g, "\u0001").split(":").map(x => x.replace(/\u0001/g, ":"))
    return { inUse: f[0] === "*", ssid: f[1], signal: parseInt(f[2]) || 0, secure: !!f[3] && f[3] !== "--" }
  }).filter(n => n.ssid).filter((n, i, a) => a.findIndex(m => m.ssid === n.ssid) === i) }
  Kit.Cmd { id: act; onDone: out => { p.status = out.trim().split("\n").pop(); p.joining = ""; Net.refresh(); refresh() } }
  function refresh() { scan.exec(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"]) }
  Component.onCompleted: refresh()
  Timer { interval: 8000; running: true; repeat: true; onTriggered: p.refresh() }

  Kit.Group {
    Kit.Row {
      label: "Wi-Fi"; badge: "wifi"; badgeColor: "#2f7bff"; last: true
      detail: Net.wifi ? "Connected to " + Net.ssid : (Net.online ? "Using Ethernet" : "")
      Kit.Switch { checked: Net.wifiEnabled; onToggled: on => { Sys.setWifi(on); p.refresh() } }
    }
  }

  Kit.Group {
    header: "Networks"
    visible: Net.wifiEnabled
    footer: p.status
    Repeater {
      model: p.nets
      delegate: Kit.Row {
        required property var modelData
        required property int index
        label: modelData.ssid
        detail: modelData.inUse ? "Connected" : ""
        last: index === p.nets.length - 1 && p.joining !== modelData.ssid
        clickable: !modelData.inUse
        onClicked: {
          if (!modelData.secure) act.exec(["nmcli", "dev", "wifi", "connect", modelData.ssid])
          else p.joining = modelData.ssid
        }
        RowLayout {
          spacing: 10
          Sym { visible: modelData.secure; name: "lock"; width: 11; height: 11; color: Theme.textDim }
          Sym { name: "wifi"; level: modelData.signal / 80; width: 16; height: 16 }
          Kit.Button { visible: modelData.inUse; text: "Disconnect"; onClicked: act.exec(["nmcli", "con", "down", "id", modelData.ssid]) }
        }
      }
    }
    Kit.Row {
      visible: p.joining !== ""
      label: "Password for " + p.joining
      last: true
      RowLayout {
        spacing: 8
        Kit.Field { id: pw; secret: true; placeholder: "Password"; width: 180; onAccepted: join.clicked() }
        Kit.Button { id: join; text: "Join"; primary: true; onClicked: { p.status = "Joining " + p.joining + "…"; act.exec(["nmcli", "dev", "wifi", "connect", p.joining, "password", pw.text]); pw.text = "" } }
      }
    }
    Kit.Row { visible: p.nets.length === 0; label: "Looking for networks…"; last: true }
  }
}
