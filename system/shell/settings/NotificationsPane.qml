import QtQuick
import QtQuick.Layouts
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  title: "Notifications"
  Kit.Group {
    footer: "Focus silences banners. Notifications still collect in Notification Center (click the clock)."
    Kit.Row {
      label: "Focus"; badge: "moon"; badgeColor: "#6e5cff"; detail: "Do Not Disturb"; last: true
      Kit.Switch { checked: Shell.focusMode; onToggled: on => Shell.focusMode = on }
    }
  }
}
