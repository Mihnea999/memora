---
name: software
when: Installing, updating or removing apps and programs, or the person asks for an app that does something.
---
# Software

1. Apps with windows: the App Store (Flathub). `apps(action="search", query=…)` then
   `apps(action="install", id=…)`; they install for the person only, no password, and show up in
   Launchpad. Remove with `apps(action="uninstall", id=…)`.
2. Command-line tools and system parts: pacman, `sudo pacman -S name` (Memora asks for the
   password). Search first: `pacman -Ss name`.
3. Already installed? `apps(action="list")` or `command -v name`.
4. Updates: `memora-update` (everything, with a snapshot first), or open
   System Settings > Software Update (`system_setting(settings_pane, update)`).
5. AUR: none by default. Don't add one without asking.
6. Recommend well-known, maintained apps. Say what you installed and where to find it
   (Launchpad, or its name in Spotlight with Super+Space).
