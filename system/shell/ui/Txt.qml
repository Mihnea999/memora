import QtQuick
import qs.core

// Text in the system face and ink. Plain text: names that come from outside
// (windows, files, notifications, devices, songs) are shown as they are, never
// read as HTML. A place that wants formatting sets textFormat itself.
Text {
  textFormat: Text.PlainText
  color: Theme.text
  font.family: Theme.font
  font.pixelSize: Theme.fontSize
  renderType: Text.NativeRendering
  verticalAlignment: Text.AlignVCenter
  elide: Text.ElideRight
}
