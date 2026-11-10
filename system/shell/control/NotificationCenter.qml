import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.ui
import qs.notify

// Opened from the clock: this month's calendar and the notifications you missed.
PanelWindow {
  id: nc
  required property var modelData
  screen: modelData
  readonly property bool open: Shell.open === "calendar" && (Shell.menuScreen === modelData.name || !Shell.menuScreen)

  // A day (or the month's name): Calendar, on that day.
  function openCalendar(d) {
    Shell.close()
    const day = Qt.formatDate(d, "yyyy-MM-dd")
    Quickshell.execDetached(["bash", "-c", "memora-app calendar & for i in $(seq 20); do sleep 0.2; qs -p \"${MEMORA_PATH:-/usr/share/memora}/shell/calendar.qml\" ipc call calendar show \"$1\" 2>/dev/null && break; done", "_", day])
  }
  visible: open || anim.running
  anchors { top: true; right: true; bottom: true }
  margins { top: 6; right: 8; bottom: 90 }
  implicitWidth: 400
  exclusiveZone: 0
  color: "transparent"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "memora-panel"
  WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

  property real shown: open ? 1 : 0
  Behavior on shown { NumberAnimation { id: anim; duration: Theme.normal; easing.type: Theme.easing } }

  OutsideClick { when: nc.open; windows: [nc]; onOutside: if (nc.open) Shell.close() }

  SystemClock { id: clock; precision: SystemClock.Minutes }
  property date month: new Date()
  property bool picking: false           // the list of countries is open
  onOpenChanged: if (open) month = new Date(); else picking = false

  ColumnLayout {
    x: 20; y: 0
    width: 360
    spacing: 10
    opacity: nc.shown
    transform: Translate { x: 30 * (1 - nc.shown) }

    // Calendar
    Glass {
      Layout.fillWidth: true
      Layout.preferredHeight: cal.implicitHeight + 28
      radius: 18
      fill: Theme.glassStrong
      ColumnLayout {
        id: cal
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
        spacing: 8
        RowLayout {
          Layout.fillWidth: true
          Txt {
            text: Qt.formatDate(nc.month, "MMMM yyyy"); font.weight: Font.Bold; font.pixelSize: Theme.large; Layout.fillWidth: true
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: nc.openCalendar(new Date(nc.month)) }
            Tip { text: "Open Calendar" }
          }
          Sym { name: "chevron"; width: 14; height: 14; rotation: 180; TapHandler { onTapped: nc.month = new Date(nc.month.getFullYear(), nc.month.getMonth() - 1, 1) } }
          Item { width: 8 }
          Sym { name: "chevron"; width: 14; height: 14; TapHandler { onTapped: nc.month = new Date(nc.month.getFullYear(), nc.month.getMonth() + 1, 1) } }
        }
        Grid {
          columns: 7
          Layout.fillWidth: true
          readonly property real cell: (cal.width) / 7
          Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            delegate: Txt { required property string modelData; width: parent.cell; height: 22; horizontalAlignment: Text.AlignHCenter; text: modelData; color: Theme.textDim; font.pixelSize: Theme.small - 1 }
          }
          Repeater {
            model: 42
            delegate: Item {
              id: dc
              required property int index
              readonly property var first: new Date(nc.month.getFullYear(), nc.month.getMonth(), 1)
              readonly property int lead: (first.getDay() + 6) % 7
              readonly property var day: new Date(nc.month.getFullYear(), nc.month.getMonth(), index - lead + 1)
              readonly property bool inMonth: day.getMonth() === nc.month.getMonth()
              readonly property bool today: day.toDateString() === clock.date.toDateString()
              // What is on it, as in Calendar: a red dot for a public holiday,
              // one in the calendar's colour for events (three at most).
              readonly property var hol: nc.open || nc.shown > 0 ? CalData.holidaysOn(day.getTime()) : []
              readonly property var evs: nc.open || nc.shown > 0 ? CalData.eventsOn(day.getTime()) : []
              readonly property var dots: (hol.length ? [CalData.holidayColor] : []).concat(evs.map(e => e.color).filter((c, i, a) => a.indexOf(c) === i)).slice(0, 3)
              width: parent.cell; height: 36
              Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 2 }
                width: 26; height: 26; radius: 13
                color: dc.today ? Theme.accent : (dh.hovered ? Theme.hover : "transparent")
              }
              Txt {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 2 }
                height: 26
                text: dc.day.getDate()
                color: dc.today ? "#ffffff" : (dc.hol.length && dc.inMonth ? CalData.holidayColor : (dc.inMonth ? Theme.text : Theme.textFaint))
                font.weight: dc.today || dc.hol.length ? Font.Bold : Font.Normal
              }
              Row {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 2 }
                spacing: 2.5
                opacity: dc.inMonth ? 1 : 0.4
                Repeater {
                  model: dc.dots
                  delegate: Rectangle { required property var modelData; width: 4.5; height: 4.5; radius: 2.25; color: modelData }
                }
              }
              HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: nc.openCalendar(dc.day) }
              Tip {
                delay: 300
                text: dc.hol.concat(dc.evs.map(e => (e.allDay ? "" : Qt.formatTime(new Date(e.start), Prefs.clock24 ? "HH:mm" : "h:mm AP") + "  ") + e.title)).join("\n")
              }
            }
          }
        }

        // Whose public holidays: shown as in Calendar, and changed here too.
        Rectangle { Layout.fillWidth: true; Layout.topMargin: 2; implicitHeight: 1; color: Theme.separator }
        Item {
          Layout.fillWidth: true
          implicitHeight: 30
          Sym { anchors.verticalCenter: parent.verticalCenter; name: "globe"; width: 14; height: 14; color: Theme.textDim }
          Txt {
            anchors { left: parent.left; leftMargin: 22; right: hc.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: CalData.showHolidays ? "Holidays in " + CalData.countryName(CalData.cc) + (CalData.country ? "" : " (automatic)") : "Holidays hidden"
            color: Theme.text
          }
          Sym { id: hc; anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter } name: "chevron"; width: 11; height: 11; color: Theme.textDim; rotation: nc.picking ? -90 : 90
            Behavior on rotation { NumberAnimation { duration: Theme.fast } } }
          HoverHandler { cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: nc.picking = !nc.picking }
        }
        ColumnLayout {
          visible: nc.picking
          Layout.fillWidth: true
          spacing: 4
          Item {
            Layout.fillWidth: true
            implicitHeight: 30
            Txt { anchors.verticalCenter: parent.verticalCenter; text: "Show public holidays" }
            Rectangle {
              anchors { right: parent.right; verticalCenter: parent.verticalCenter }
              width: 38; height: 22; radius: 11
              color: CalData.showHolidays ? Theme.green : Theme.pressed
              Rectangle { width: 18; height: 18; radius: 9; y: 2; x: CalData.showHolidays ? 18 : 2; color: "#ffffff"; Behavior on x { NumberAnimation { duration: Theme.fast } } }
              HoverHandler { cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: CalData.setShowHolidays(!CalData.showHolidays) }
            }
          }
          ListView {
            id: cl
            Layout.fillWidth: true
            Layout.preferredHeight: 190
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: [["", "Automatic (" + (CalData.autoCountry || "US") + ")"]].concat(CalData.countries)
            onVisibleChanged: if (visible) positionViewAtIndex(Math.max(0, model.findIndex(c => c[0] === CalData.country)), ListView.Center)
            delegate: Rectangle {
              required property var modelData
              readonly property bool on: CalData.country === modelData[0]
              width: cl.width; height: 28; radius: 7
              color: ch2.hovered ? Theme.hover : "transparent"
              Sym { visible: parent.on; x: 8; anchors.verticalCenter: parent.verticalCenter; name: "check"; width: 11; height: 11; color: Theme.accent; stroke: 2 }
              Txt { x: 26; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 34; text: modelData[1]; font.weight: parent.on ? Font.DemiBold : Font.Normal }
              HoverHandler { id: ch2; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: { CalData.setCountry(modelData[0]); if (!CalData.showHolidays) CalData.setShowHolidays(true) } }
            }
          }
        }
      }
    }

    // The heading and the empty note sit on glass of their own: straight on the
    // desktop picture their text would be lost on a dark or a busy one.
    Glass {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      visible: Notifs.history.length > 0
      radius: 14
      fill: Theme.glassStrong
      Txt { x: 14; anchors.verticalCenter: parent.verticalCenter; text: "Notifications"; font.weight: Font.Bold }
      Rectangle {
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        width: ct.implicitWidth + 18; height: 24; radius: 12
        color: ch.hovered ? Theme.pressed : Theme.hover
        Txt { id: ct; anchors.centerIn: parent; text: "Clear All"; font.pixelSize: Theme.small }
        HoverHandler { id: ch }
        TapHandler { onTapped: Notifs.clearAll() }
      }
    }

    Glass {
      visible: Notifs.history.length === 0
      Layout.alignment: Qt.AlignHCenter
      Layout.topMargin: 6
      Layout.preferredWidth: none.implicitWidth + 36
      Layout.preferredHeight: 34
      radius: 17
      fill: Theme.glassStrong
      Txt { id: none; anchors.centerIn: parent; text: "No Notifications"; color: Theme.textDim }
    }

    Repeater {
      model: Notifs.history.slice(0, 8)
      delegate: NotificationCard {
        required property var modelData
        notif: modelData
        banner: false
        Layout.fillWidth: true
      }
    }
  }
}
