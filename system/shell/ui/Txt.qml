import QtQuick
import qs.core

// Text in the system face and ink.
Text {
  color: Theme.text
  font.family: Theme.font
  font.pixelSize: Theme.fontSize
  renderType: Text.NativeRendering
  verticalAlignment: Text.AlignVCenter
  elide: Text.ElideRight
}
