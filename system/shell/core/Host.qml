pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Facts about this computer and its owner, for System Settings and About.
Singleton {
  id: h
  property string user: Quickshell.env("USER")
  property string fullName: user
  property string hostname: ""
  property string kernel: ""
  property string cpu: ""
  property string memory: ""
  property string gpu: ""
  property string disk: ""
  property string version: ""
  property string timezone: ""
  property string uptime: ""

  function refresh() { proc.running = true }
  Component.onCompleted: refresh()

  property Process proc: Process {
    command: ["bash", "-c", [
      "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1",
      "cat /etc/hostname 2>/dev/null || hostname",
      "uname -r",
      "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //'",
      "awk '/MemTotal/ {printf \"%.0f GB\", $2/1048576}' /proc/meminfo",
      "lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -1 | cut -d: -f3- | sed 's/^ //'",
      "df -h --output=avail,size / | tail -1 | awk '{print $1\" available of \"$2}'",
      "cat ${MEMORA_PATH:-/usr/share/memora}/version 2>/dev/null",
      "timedatectl show -p Timezone --value 2>/dev/null",
      "uptime -p | sed 's/^up //'"
    ].join("; echo '\x1f'; ")]
    stdout: StdioCollector {
      onStreamFinished: {
        const f = text.split("\x1f\n").map(s => s.trim())
        h.fullName = f[0] || h.user
        h.hostname = f[1]; h.kernel = f[2]; h.cpu = f[3]; h.memory = f[4]
        h.gpu = f[5]; h.disk = f[6]; h.version = f[7]; h.timezone = f[8]; h.uptime = f[9]
      }
    }
  }
}
