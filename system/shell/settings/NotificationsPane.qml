import QtQuick
import QtQuick.Layouts
import qs.core
import qs.ui
import qs.settings

Kit.Page {
  title: "Notifications"
  Kit.Group {
    Kit.Row {
      label: "Focus"; badge: "moon"; badgeColor: "#6e5cff"; last: true
      Kit.Switch { checked: Shell.focusMode; onToggled: on => Shell.focusMode = on }
    }
  }
}
