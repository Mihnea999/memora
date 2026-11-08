---
name: apps
when: Working inside an app on screen: clicking, typing, menus, filling things in, or any task in an app that has no command for it.
---
# Using apps on the screen

The chat (the notch at the top) steps aside by itself while you click and type, so keys go
to the app. Still, always say which window gets the keys.

1. Open or find the app: `open("Text Editor")` (or `browse` for web pages), then
   `wait_for_window(app=…)`. It returns the window's address and brings it to the front.
2. `screenshot` before acting: know what is on the screen.
3. Act with the window named: `type_text(text, window=ADDRESS_OR_APP)`,
   `press_keys("ctrl+s", window=…)`, `click(x, y)` on what you saw.
4. `screenshot` again to check it worked; if not, try another way (keyboard shortcut, menu).

Memora details:
- Super works like Command on a Mac in Memora's own apps; GTK apps use Ctrl (Ctrl+S save,
  Ctrl+O open, Ctrl+N new, Ctrl+W close tab, Ctrl+Q quit).
- The menu bar at the top shows the focused app's menus (File, Edit, View, Window, Help).
- Window buttons are top left: red close, yellow minimize (to the Dock), green zoom.
- Prefer commands and dedicated tools when they exist (files, settings, notes, media): they are
  faster and surer than clicking.
- Text longer than a few lines: put it on the clipboard (`clipboard(action="set")`) and paste
  with ctrl+v instead of typing it.
