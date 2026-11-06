import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  id: p
  title: "Bluetooth"
  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: adapter ? adapter.devices.values.slice().sort((a, b) => (b.paired - a.paired) || (b.connected - a.connected)) : []

  Component.onCompleted: if (adapter && adapter.enabled) adapter.discovering = true
  Component.onDestruction: if (adapter) adapter.discovering = false

  Kit.Group {
    Kit.Row {
      label: "Bluetooth"; badge: "bluetooth"; badgeColor: "#2f7bff"; last: true
      detail: !p.adapter ? "No Bluetooth adapter found" : (p.adapter.enabled ? "Discoverable as \"" + Host.hostname + "\"" : "Off")
      Kit.Switch { visible: !!p.adapter; checked: p.adapter ? p.adapter.enabled : false; onToggled: on => { p.adapter.enabled = on; if (on) p.adapter.discovering = true } }
    }
  }

  Kit.Group {
    header: "Devices"
    visible: !!p.adapter && p.adapter.enabled
    Repeater {
      model: p.devices
      delegate: Kit.Row {
        required property var modelData
        required property int index
        label: modelData.name || modelData.address
        detail: modelData.connected ? "Connected" + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "%" : "") : (modelData.paired ? "Not connected" : "")
        last: index === p.devices.length - 1
        RowLayout {
          spacing: 8
          Kit.Button {
            text: modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair")
            primary: !modelData.paired
            onClicked: {
              if (modelData.connected) modelData.disconnect()
              else if (modelData.paired) modelData.connect()
              else { modelData.trusted = true; modelData.pair() }
            }
          }
          Kit.Button { visible: modelData.paired; text: "Forget"; danger: true; onClicked: modelData.forget() }
        }
      }
    }
    Kit.Row { visible: p.devices.length === 0; label: "Looking for devices…"; last: true }
  }
}
