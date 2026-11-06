pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Network state for the bar and Control Center, read from NetworkManager.
Singleton {
  id: n
  property bool online: false
  property bool wifi: false
  property bool wifiEnabled: true
  property string ssid: ""
  property real strength: 0
  readonly property string label: !online ? "Not connected" : (wifi ? ssid : "Ethernet")

  function refresh() { proc.running = true }

  property Process proc: Process {
    command: ["bash", "-c", "nmcli -t -f TYPE,STATE,CONNECTION dev 2>/dev/null; echo '--'; nmcli -t -f ACTIVE,SIGNAL,SSID dev wifi 2>/dev/null | grep '^yes' | head -1; echo '--'; nmcli radio wifi 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        const parts = text.split("--\n")
        const devs = (parts[0] || "").split("\n").filter(l => l.length)
        const eth = devs.some(l => l.startsWith("ethernet:connected"))
        const wl = devs.some(l => l.startsWith("wifi:connected"))
        n.online = eth || wl
        n.wifi = wl && !eth
        const w = (parts[1] || "").trim().split(":")
        n.strength = wl ? Math.min(1, (parseInt(w[1]) || 0) / 80) : (eth ? 1 : 0)
        n.ssid = wl ? w.slice(2).join(":") : ""
        n.wifiEnabled = (parts[2] || "").trim() === "enabled"
      }
    }
  }
  property Timer timer: Timer { interval: 8000; running: true; repeat: true; triggeredOnStart: true; onTriggered: n.refresh() }
}
