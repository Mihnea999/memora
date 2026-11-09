#!/usr/bin/env python3
"""Play touch gestures in the test VM (run there with sudo; needs python-evdev).

    sudo python3 touch.py GESTURE [GESTURE…]   (copy it to test/share to reach it at /mnt/share)
    gestures: tap X Y · hold X Y · drag X1 Y1 X2 Y2 · edge-bottom · edge-bottom-long ·
              edge-top-left · edge-top-right · edge-left · edge-right ·
              three-up · three-down · three-left · three-right · pinch-in · pinch-out
Coordinates are fractions of the screen (0..1). A virtual touch screen appears
for as long as this runs; Hyprland maps it to the focused screen.
"""
import sys
import time

from evdev import AbsInfo, UInput, ecodes as e

MAX = 4095
cap = {
    e.EV_KEY: [e.BTN_TOUCH],
    e.EV_ABS: [
        (e.ABS_X, AbsInfo(0, 0, MAX, 0, 0, 0)), (e.ABS_Y, AbsInfo(0, 0, MAX, 0, 0, 0)),
        (e.ABS_MT_SLOT, AbsInfo(0, 0, 9, 0, 0, 0)), (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0)),
        (e.ABS_MT_POSITION_X, AbsInfo(0, 0, MAX, 0, 0, 0)), (e.ABS_MT_POSITION_Y, AbsInfo(0, 0, MAX, 0, 0, 0)),
    ],
}
ui = UInput(cap, name="Memora test touchscreen", input_props=[e.INPUT_PROP_DIRECT])
time.sleep(1.0)   # let the compositor find it
tid = [100]


def frame(fingers, down):
    """fingers: list of (x, y) fractions, one per slot."""
    for slot, (x, y) in enumerate(fingers):
        ui.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
        if down == "start":
            tid[0] += 1
            ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, tid[0])
        if down == "end":
            ui.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
        else:
            ui.write(e.EV_ABS, e.ABS_MT_POSITION_X, int(x * MAX))
            ui.write(e.EV_ABS, e.ABS_MT_POSITION_Y, int(y * MAX))
    if down == "start":
        ui.write(e.EV_KEY, e.BTN_TOUCH, 1)
    if down == "end":
        ui.write(e.EV_KEY, e.BTN_TOUCH, 0)
    if fingers and down != "end":
        ui.write(e.EV_ABS, e.ABS_X, int(fingers[0][0] * MAX))
        ui.write(e.EV_ABS, e.ABS_Y, int(fingers[0][1] * MAX))
    ui.syn()


def move(a, b, steps=20, hold=0.0):
    frame(a, "start")
    time.sleep(hold or 0.02)
    for i in range(1, steps + 1):
        t = i / steps
        frame([(p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t) for p, q in zip(a, b)], "move")
        time.sleep(0.012)
    frame(b, "end")
    time.sleep(0.4)


def fingers(n, cx, cy, r=0.05):
    return [(cx + r * (i - (n - 1) / 2), cy) for i in range(n)]


G = {
    "edge-bottom": lambda: move([(0.5, 0.999)], [(0.5, 0.9)]),
    "edge-bottom-long": lambda: move([(0.5, 0.999)], [(0.5, 0.5)]),
    "edge-top-left": lambda: move([(0.2, 0.001)], [(0.2, 0.3)]),
    "edge-top-right": lambda: move([(0.8, 0.001)], [(0.8, 0.3)]),
    "edge-left": lambda: move([(0.001, 0.5)], [(0.3, 0.5)]),
    "edge-right": lambda: move([(0.999, 0.5)], [(0.7, 0.5)]),
    "three-up": lambda: move(fingers(3, 0.5, 0.7), fingers(3, 0.5, 0.4)),
    "three-down": lambda: move(fingers(3, 0.5, 0.3), fingers(3, 0.5, 0.6)),
    "three-left": lambda: move(fingers(3, 0.7, 0.5), fingers(3, 0.3, 0.5)),
    "three-right": lambda: move(fingers(3, 0.3, 0.5), fingers(3, 0.7, 0.5)),
    "pinch-in": lambda: move(fingers(4, 0.5, 0.5, 0.12), fingers(4, 0.5, 0.5, 0.03)),
    "pinch-out": lambda: move(fingers(4, 0.5, 0.5, 0.03), fingers(4, 0.5, 0.5, 0.12)),
}

args = sys.argv[1:]
if not args:
    print(__doc__)
    sys.exit(1)
while args:
    g = args.pop(0)
    if g == "tap":
        x, y = float(args.pop(0)), float(args.pop(0)); move([(x, y)], [(x, y)], steps=1)
    elif g == "hold":
        x, y = float(args.pop(0)), float(args.pop(0)); move([(x, y)], [(x, y)], steps=1, hold=0.9)
    elif g == "drag":
        x1, y1, x2, y2 = (float(args.pop(0)) for _ in range(4)); move([(x1, y1)], [(x2, y2)], steps=40)
    elif g in G:
        G[g]()
    else:
        print("unknown gesture:", g)
ui.close()
