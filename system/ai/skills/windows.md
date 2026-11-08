---
name: windows
when: Arranging, focusing, closing or minimizing windows; side-by-side layouts; desktops (workspaces); the Dock.
---
# Windows and desktops

- `windows(action="list")` shows every window with its address; focus, close, minimize,
  maximize, restore one by address or app.
- Layouts: `arrange_window(zone=…, window=…)`: left, right, top, bottom, fill, center,
  top-left, top-right, bottom-left, bottom-right, left-third, center-third, right-third,
  left-two-thirds, right-two-thirds. Two apps side by side: one left, the other right.
- Desktops: `desktops(action="go", number=N)`, `desktops(action="move_window", number=N)`
  to carry the focused window there. Ctrl+Super+Up shows all desktops and windows (Mission Control).
- Shortcuts the person can use: Super+Left/Right docks a window to a half, Super+Q quits,
  Super+M minimizes, Super+D shows the desktop, Super+Tab switches apps, Super+Alt+D hides the Dock.
