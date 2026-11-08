---
name: troubleshoot
when: Something doesn't work: an error, no internet, no sound, an app crashes, the computer is slow, the disk is full, after an update.
---
# Fixing problems

Look before changing anything; change one thing at a time; say what you found in plain words.

- Overview: `system_info(what="all")`.
- No internet: `nmcli general status`, `nmcli device`, `ping -c2 1.1.1.1` vs `ping -c2 archlinux.org` (DNS).
- No sound: `wpctl status` (default output, muted?), `system_setting(volume, 50)`.
- Slow: `system_info(what="processes")`; heavy apps can be quit with `windows(close)` or
  `run_command("pkill NAME")` (asks first).
- Disk full: `df -h /`, `du -sh ~/.cache ~/Downloads`, `sudo pacman -Sc` cleans old packages,
  `flatpak uninstall --unused`.
- Errors in logs: `journalctl -b -p err --no-pager | tail -50`, a service: `systemctl status NAME`,
  `systemctl --failed`. App crash reports: `coredumpctl list | tail`.
- After a bad update: snapshots are taken before every update; `snapper list`. Going back is a
  big step (rollback): explain it and let the person decide.
- Never disable security or delete system files to "fix" something.
