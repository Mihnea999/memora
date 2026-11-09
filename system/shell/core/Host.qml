pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Facts about this computer and its owner, for System Settings and About,
// and what kind of computer it is, so the desktop shows what it has: a laptop
// gets its battery, brightness, trackpad and lid settings; a desktop doesn't
// get empty ones.
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
  // The hardware (read once at start).
  property string chassis: ""          // laptop, desktop, convertible, tablet, server, vm…
  property string model: ""            // "ThinkPad X1 Carbon Gen 11"
  property bool hasTouchpad: false
  property bool hasWifi: true
  property bool hasLid: false
  property bool hasBattery: false
  property bool hasTouchscreen: false
  property bool hasAccelerometer: false
  readonly property bool isLaptop: hasBattery || hasLid || ["laptop", "notebook", "convertible", "tablet", "handset"].indexOf(chassis) >= 0
  property int batteryHealth: 0        // % of the design capacity it still holds (0: unknown)
  property int batteryCycles: -1
  property int chargeLimit: -1         // % it stops charging at; -1: the laptop can't do it
  property int conservation: -1        // Lenovo's Conservation Mode instead: 1 on, 0 off, -1 not there
  function refreshHardware() { hw.running = true }
  Component.onCompleted: { refresh(); refreshHardware() }
  property Process hw: Process {
    command: ["bash", "-c", `
      c=$(hostnamectl chassis 2>/dev/null); [ -n "$c" ] || c=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)
      case "$c" in 8|9|10|14) c=laptop;; 30) c=tablet;; 31|32) c=convertible;; 3|4|5|6|7|13|15|16|35|36) c=desktop;; esac; echo "$c"
      v=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null); n=$(cat /sys/class/dmi/id/product_name 2>/dev/null); pv=$(cat /sys/class/dmi/id/product_version 2>/dev/null)
      case "$v" in LENOVO) m="$pv";; *) m="$n";; esac
      case "$m" in ""|"To be filled"*|"System Product Name"*|Default*|"Not Applicable"*) m="";; esac
      v=$(echo "$v" | sed 's/ Inc\.*$//; s/,.*$//; s/^ASUSTeK.*/ASUS/; s/^Micro-Star.*/MSI/; s/^Hewlett-Packard/HP/; s/^LENOVO$/Lenovo/; s/^Dell.*/Dell/')
      case "$m" in "$v"*|"") echo "$m";; *) echo "$v $m";; esac
      grep -qi touchpad /proc/bus/input/devices 2>/dev/null && echo 1 || echo 0
      ls /sys/class/ieee80211 2>/dev/null | grep -q . && echo 1 || echo 0
      ls /proc/acpi/button/lid 2>/dev/null | grep -q . && echo 1 || echo 0
      b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
      if [ -n "$b" ]; then
        echo 1
        f=$(cat $b/energy_full $b/charge_full 2>/dev/null | head -1); d=$(cat $b/energy_full_design $b/charge_full_design 2>/dev/null | head -1)
        [ -n "$f" ] && [ -n "$d" ] && [ "$d" -gt 0 ] && echo $(( f * 100 / d )) || echo 0
        cat $b/cycle_count 2>/dev/null || echo -1
        cat $b/charge_control_end_threshold 2>/dev/null || echo -1
      else echo 0; echo 0; echo -1; echo -1; fi
      cm=$(cat /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode 2>/dev/null | head -1); echo "\${cm:--1}"
      udevadm info --export-db 2>/dev/null | grep -q 'ID_INPUT_TOUCHSCREEN=1' && echo 1 || echo 0
      ls /sys/bus/iio/devices/iio:device*/in_accel_x_raw >/dev/null 2>&1 && echo 1 || echo 0`]
    stdout: StdioCollector {
      onStreamFinished: {
        const f = text.split("\n").map(s => s.trim())
        h.chassis = f[0] || ""; h.model = f[1] || ""
        h.hasTouchpad = f[2] === "1"; h.hasWifi = f[3] === "1"; h.hasLid = f[4] === "1"; h.hasBattery = f[5] === "1"
        h.batteryHealth = Math.min(100, parseInt(f[6]) || 0); h.batteryCycles = parseInt(f[7]); h.chargeLimit = parseInt(f[8])
        if (isNaN(h.batteryCycles)) h.batteryCycles = -1
        if (isNaN(h.chargeLimit)) h.chargeLimit = -1
        h.conservation = f[9] === "1" ? 1 : f[9] === "0" ? 0 : -1
        h.hasTouchscreen = f[10] === "1"; h.hasAccelerometer = f[11] === "1"
      }
    }
  }

  function refresh() { proc.running = true }

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
