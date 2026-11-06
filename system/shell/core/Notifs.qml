pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.core

// The notification server. Keeps the history for Notification Center and the
// list of banners currently on screen.
Singleton {
  id: ns

  property var popups: []      // notifications showing as banners
  property var history: []     // newest first
  property var times: ({})     // id -> time received
  function timeOf(n) { return times[n.id] || Date.now() }

  property NotificationServer server: NotificationServer {
    keepOnReload: false
    actionsSupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    imageSupported: true
    persistenceSupported: true
    onNotification: n => {
      n.tracked = true
      ns.times[n.id] = Date.now()
      ns.history = [n].concat(ns.history).slice(0, 60)
      if (!Shell.focusMode || n.urgency === NotificationUrgency.Critical) ns.popups = ns.popups.concat([n])
      n.closed.connect(() => {
        ns.history = ns.history.filter(x => x !== n)
        ns.popups = ns.popups.filter(x => x !== n)
      })
    }
  }

  function hide(n) { popups = popups.filter(x => x !== n) }
  function clearAll() { history.slice().forEach(n => n.dismiss()) }

  function ago(t) {
    const s = Math.floor((Date.now() - t) / 1000)
    if (s < 60) return "now"
    if (s < 3600) return Math.floor(s / 60) + "m ago"
    if (s < 86400) return Math.floor(s / 3600) + "h ago"
    return Qt.formatDateTime(new Date(t), "MMM d")
  }
}
