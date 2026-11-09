import QtQuick

// Two fingers sideways on the touchpad, as on a Mac: fingers moving right go
// back, moving left go forward. Once per swipe; mouse wheels don't count.
WheelHandler {
  id: sw
  signal back()
  signal forward()
  acceptedDevices: PointerDevice.TouchPad
  target: null
  property real acc: 0
  property bool fired: false
  // How far the fingers travel before it counts (pixels of scrolling).
  property real distance: 140

  onWheel: ev => {
    const dx = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : ev.angleDelta.x / 4
    const dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y / 4
    if (Math.abs(dy) > Math.abs(dx)) return          // scrolling up or down, not a swipe
    idle.restart()
    if (fired) return
    // With natural scrolling the deltas follow the fingers (inverted); without, they're opposite.
    acc += ev.inverted ? dx : -dx
    if (acc > distance) { fired = true; sw.back() }
    else if (acc < -distance) { fired = true; sw.forward() }
  }
  property Timer idle: Timer { interval: 260; onTriggered: { sw.acc = 0; sw.fired = false } }
}
