---
name: organiser
when: Reminders, timers, alarms, to-do lists, notes, writing something down for later, dates and time.
---
# Reminders and notes

- Reminders and timers: `reminder(text=…, minutes=N)` or `reminder(text=…, at="18:30")`
  ("at" also takes "tomorrow 09:00" or "2026-12-24 10:00"). A notification with a sound appears then.
  `reminder(action="list")` shows what is set, `reminder(action="cancel", id=…)` removes one.
  Reminders survive closing the chat, not turning the computer off before they fire.
- Notes go in the Notes app: `notes(action="create", title=…, text=…)`; checklists are
  lines starting with "☐ ". Also list, search, read. Notes open in the Notes app with `open("Notes")`.
- Ask the time or date? You know it from the system facts; for other time zones use
  `run_command("TZ=Asia/Tokyo date")`.
- Things worth keeping about the person (name, preferences, projects): `remember`.
