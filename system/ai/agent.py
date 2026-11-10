#!/usr/bin/env python3
"""Memora AI: an assistant that can use the computer it runs on.

  agent.py serve            JSON lines on stdin/stdout, for the Memora AI window
  agent.py ask QUESTION     answer in the terminal (stdin is attached if piped)

With Claude (the Anthropic API) it has tools: run commands, read and write
files, open apps, change settings, manage windows, look at the screen and
click/type, search the web. Anything risky waits for the person's OK; the
gravest actions (erasing disks, deleting the system) show a stronger warning.
With DeepSeek (its Anthropic-compatible API) it has the same tools, minus web search.
With Claude Code it uses Claude Code's own tools, plus Memora's through
`memora-ai tool NAME JSON`; its permission prompts come to the window
(permit.py) and the conversation carries on from message to message.
Ollama and OpenAI-compatible servers get the same tools too (function calling),
minus web search and pictures; a model that can't use tools answers as a plain chat.

  agent.py tools            Memora's tools, with their inputs (for Claude Code)
  agent.py tool NAME JSON   run one of them
"""
import base64
import contextlib
from datetime import datetime, timedelta
import json
import os
import queue
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

HOME = Path.home()
CONF = HOME / ".config/memora"
DATA = HOME / ".local/share/memora/ai"
MEMORY = DATA / "memory.md"
MEMORA_PATH = os.environ.get("MEMORA_PATH", "/usr/share/memora")
DEFAULT_MODEL = "claude-opus-5-5"
# The choice offered in the window and in System Settings > Memora AI.
MODELS = [("claude-fable-5-2", "Fable 5.2"), ("claude-opus-5-5", "Opus 5.5"), ("claude-sonnet-5-5", "Sonnet 5.5"), ("claude-haiku-5-5", "Haiku 5.5")]
EFFORTS = ["low", "medium", "high", "xhigh", "max"]
DEFAULT_EFFORT = "high"
OUT_LIMIT = 20000


# Tools installed per user (Claude Code, npm/uv tools) live outside the
# session's PATH when the desktop was started before they were installed.
for _d in (HOME / ".local/share/mise/shims", HOME / ".local/bin"):
    if str(_d) not in os.environ.get("PATH", "").split(":"):
        os.environ["PATH"] = f"{_d}:{os.environ.get('PATH', '/usr/bin')}"


# ---------------------------------------------------------------- config ----
def load_config():
    cfg = {"provider": "anthropic", "model": "", "baseUrl": ""}
    try:
        cfg.update(json.loads((CONF / "ai.json").read_text()))
    except (OSError, ValueError):
        pass
    try:
        for line in (CONF / "ai.secret").read_text().splitlines():
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                if re.fullmatch(r"[A-Z][A-Z0-9_]*_(API_KEY|BASE_URL)", k.strip()):
                    os.environ[k.strip()] = v.strip()   # a key saved again in Settings counts at once
    except OSError:
        pass
    return cfg


def system_facts():
    def sh(cmd):
        try:
            return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=5).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            return ""
    return {
        "user": os.environ.get("USER", ""),
        "home": str(HOME),
        "hostname": sh("cat /etc/hostname"),
        "kernel": sh("uname -r"),
        "memora": sh(f"cat {MEMORA_PATH}/version"),
        "cpu": sh("grep -m1 'model name' /proc/cpuinfo | cut -d: -f2-"),
        "memory": sh("free -h | awk '/Mem/ {print $2\" total, \"$7\" available\"}'"),
        "gpu": sh("lspci | grep -Ei 'vga|3d' | cut -d: -f3- | head -2"),
        "disk": sh("df -h --output=avail,size / | tail -1"),
        "theme": sh("cat ~/.config/memora/theme"),
        "time": time.strftime("%A %d %B %Y, %H:%M %Z"),
    }


def on_screen():
    """What the person has open right now, so "this window", "the browser" make sense."""
    cs = sorted(clients(), key=lambda c: c.get("focusHistoryID", 99))
    if not cs:
        return "no windows open (the desktop)."
    def name(c):
        t = (c.get("title") or "").strip()
        return f"{c.get('class') or '?'}" + (f" \u2014 \"{t[:80]}\"" if t else "")
    out = f"in front: {name(cs[0])}"
    if len(cs) > 1:
        out += "; also open: " + "; ".join(name(c) for c in cs[1:12])
    return out + "."


CLAUDE_CODE_NOTES = """You run inside Claude Code on this computer, so your tools are Claude Code's (Bash, Read, Edit, Write, WebSearch, WebFetch...). Memora's own tools work through Bash:
  memora-ai tool NAME 'JSON'      e.g. memora-ai tool browse '{{"search": "animals"}}'
  memora-ai tools                 lists all of them with their inputs
Use them for anything on the desktop: opening apps and web pages (browse, open), settings (system_setting), windows (windows, arrange_window), reminders, notes, media, weather, apps (install/uninstall), the screen (screenshot saves a picture you can Read; click, type_text, press_keys).
- Questions for the person: write them in your answer and end your turn; they answer in the chat (do not use AskUserQuestion).
- Commands that need administrator rights: write them with sudo; Memora shows its own password dialog.
- Anything that changes the system waits for the person's OK in the chat; if they decline, accept it and offer an alternative.
- Guides for common tasks are in {skills_dir}: read the one that fits before such a task:
{guides}"""


def now_context():
    """What changes from one message to the next (the time, what is on the screen).
    It goes with each message, not in the system prompt, so that stays the same
    and is read from the cache: answers start sooner and cost less."""
    return f"[Now: {time.strftime('%A %d %B %Y, %H:%M %Z')}. On the screen: {on_screen()}]"


def system_prompt(claude_code=False, with_now=True):
    f = system_facts()
    guides = "\n".join(f"  - {n}: {w}" for n, (w, _) in skills().items()) or "  (none installed)"
    memory = MEMORY.read_text() if MEMORY.exists() else "(empty)"
    when = f" Now: {f['time']}." if with_now else " The time and what is on the screen come with each message, in [Now: …]."
    screen = f"\nOn the screen: {on_screen()}" if with_now else ""
    if claude_code:
        style = CLAUDE_CODE_NOTES.format(skills_dir=SKILLS, guides=guides)
        memory_note = "add to it with: memora-ai remember FACT"
    else:
        style = None
        memory_note = "add to it with the remember tool when they tell you something worth keeping"
    text = f"""You are Memora AI, the assistant built into Memora, a desktop operating system based on Arch Linux with the Hyprland compositor. You run on the person's own computer and can act on it with your tools.

The computer: user {f['user']} (home {f['home']}), host {f['hostname']}, Memora {f['memora']}, kernel {f['kernel']}, CPU {f['cpu']}, memory {f['memory']}, graphics {f['gpu']}, disk (free/size) {f['disk']}, appearance {f['theme']}.{when}{screen}

How Memora works: packages come from pacman (official Arch repositories); there is no AUR helper unless the person installed one. Settings live in System Settings (memora-settings PANE, panes: wifi, bluetooth, network, notifications, sound, appearance, wallpaper, dock, animations, displays, keyboard, mouse, battery, datetime, users, privacy, ai, update, about). Light/dark: memora-theme set light|dark. Updates: memora-update. Snapshots: snapper (one is taken before every pacman transaction). Hyprland is configured in Lua (~/.config/hypr/user.lua for personal changes). The shell (menu bar, Dock, Launchpad) is memora-shell. Developer toolkits: memora-dev.

Working style:
{{STYLE}}- Do what is asked with your tools rather than telling the person how to do it, unless they asked for instructions.
- Pick the most direct tool: a dedicated one (browse, open, system_setting, media, calendar, reminder, notes, apps, find_files, windows, arrange_window, weather, system_info…) beats a shell command, and a shell command beats clicking on the screen. Use the screen tools (screenshot, click, type_text, press_keys, scroll) only for work inside apps that has no other way.
- Searching or showing something online: browse(search=…) or browse(url=…) opens the Browser right on it. Never open the Browser and type the search, and never type into this chat: you are the notch at the top of the screen, and keys you send go to the window you name with `window`.
- Working in an app: open it, wait_for_window, screenshot, then click/type_text/press_keys with window=…, and check with a screenshot. While you do this the chat folds out of the way by itself.
- Guides: before a task one of these covers, read it with skill(name) and follow it (once per conversation is enough):
{guides}
- Commands that need administrator rights: write them with sudo; Memora shows its own password dialog.
- Risky actions are confirmed by the person before they run; if one is declined, accept it and offer an alternative. Never try to get around a declined action.
- Finish the job: when a request has several steps, do all of them; after an action, check that it worked (a quick look with a tool) before saying it is done. If something fails, try another way before giving up, and say plainly what didn't work.
- When a detail is missing but a sensible choice is obvious and easy to undo, make it and say which; ask only when a wrong guess would cost the person something.
- Files: read_file also reads PDFs, Word/LibreOffice documents and pictures; change part of a file with edit_file (not by writing it all again); delete with trash (it can be restored), not rm.
- Earlier conversations: when the person refers to one ("what we talked about yesterday", "that command from before"), look with past_chats.
- Memory: when the person tells you something lasting about themselves or how they like things done (their name, city, language, preferred apps, people they mention often), save it with remember without asking; if something saved is wrong or they ask you to forget it, use forget.
- Selected text: "this"/"the selected text" with nothing attached usually means what they selected: clipboard(action=selection).
- Keep answers short and plain. Answer in the language the person writes in. Use Markdown only where it helps (code blocks for commands and files).

What you know about this person (their memory file; {memory_note}):
{memory}
"""
    if style is None:
        return text.replace("{STYLE}", "")
    # Claude Code: its own notes instead of the ones about this agent's tools.
    head, rest = text.split("{STYLE}", 1)
    cut = rest.index("\nWhat you know")
    bullets = ("\n" + rest[:cut]).split("\n- ")
    keep = [b.strip() for b in bullets if b.startswith(("Keep answers short", "Do what is asked", "Finish the job", "When a detail", "Earlier conversations", "Memory:"))]
    return head + style + "\n- " + "\n- ".join(keep) + "\n" + rest[cut:]


# ------------------------------------------------------------------ risk ----
# Gravest first. These can destroy the system or data beyond repair; they still
# run, but only after a confirmation that says so plainly.
CRITICAL = [
    (r"\brm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+(--no-preserve-root\s+)?(/|/\*|~|~/|\$HOME|/home|/usr|/etc|/boot|/var|/bin|/lib|/opt|/root)(\s|/?$|/\*)", "deletes the system or your home folder"),
    (r"\bmkfs(\.\w+)?\b|\bmke2fs\b|\bmkswap\s+/dev", "formats a disk"),
    (r"\bdd\b.*\bof=/dev/(sd|nvme|vd|mmcblk|hd)", "writes directly over a disk"),
    (r"\b(wipefs|sgdisk\s+-[zZo]|sfdisk|parted|fdisk|gdisk|blkdiscard)\b", "changes or erases disk partitions"),
    (r"\bcryptsetup\s+(luksFormat|erase|luksKillSlot)", "erases encryption keys or a disk"),
    (r">\s*/dev/(sd|nvme|vd|mmcblk)", "writes directly over a disk"),
    (r"\bshred\b", "destroys files beyond recovery"),
    (r"\b(chmod|chown)\s+(-[a-zA-Z]*R[a-zA-Z]*\s+)\S*\s+/(\s|$|usr|etc|boot|bin|lib)", "changes permissions across the whole system"),
    (r"\bpacman\s+-R\w*\s+.*\b(base|linux|glibc|systemd|pacman|hyprland|sudo|grub|systemd-boot|filesystem)\b", "removes a package the system needs to start"),
    (r":\(\)\s*\{\s*:\|:&\s*\};:", "freezes the computer (fork bomb)"),
    (r"\b(userdel|deluser)\b|\bpasswd\s+-d\b", "deletes a user or their password"),
    (r"\bsnapper\b.*\b(delete|rollback)\b", "deletes or rolls back system snapshots"),
    (r"\bsystemctl\s+(disable|mask|stop)\s+(greetd|NetworkManager|systemd-logind|dbus)\b", "stops a service needed to log in or connect"),
]
RISKY = [
    (r"(^|[;&|]\s*|\s)(sudo|pkexec|doas)\s", "runs as administrator"),
    (r"\brm\b", "deletes files"),
    (r"\bmv\b", "moves or renames files"),
    (r"\b(chmod|chown|chattr)\b", "changes permissions"),
    (r"\b(kill|pkill|killall)\b", "stops programs"),
    (r"\bsystemctl\s+(start|stop|restart|enable|disable|mask|isolate|reboot|poweroff|suspend|hibernate)", "changes system services"),
    (r"\b(reboot|poweroff|shutdown|halt)\b", "restarts or turns off the computer"),
    (r"\bpacman\s+-(S|R|U)", "installs or removes software"),
    (r"\b(pip|pipx|npm|cargo|gem|go)\s+(install|uninstall|remove)\b", "installs or removes software"),
    (r"(curl|wget)\b.*\|\s*(sudo\s+)?(ba|z)?sh\b", "runs a script from the internet"),
    (r"\bgit\s+(push\s+.*(-f|--force)|reset\s+--hard|clean\s+-\w*f)", "rewrites or discards git history"),
    (r"\bcrontab\s+-r\b|\btruncate\b", "erases data"),
    (r"(^|\s)>\s*/(etc|usr|boot|var)/", "overwrites a system file"),
    (r"\bnmcli\s+(con(nection)?\s+delete|radio\s+all\s+off)", "removes network connections"),
    (r"\bdd\b", "copies raw data"),
    (r"\bfind\b.*\s-delete\b|\bfind\b.*-exec\s+rm\b", "deletes files"),
    (r"\|\s*(sudo\s+)?(env\s+)?(python[0-9.]*|perl|ruby|node|php|lua|fish|dash|ksh)\b|\b(ba|z|da)?sh\s+<\(|\b(eval|source)\s+[\"'$<(]|\bbase64\s+(-d|--decode)\b.*\|",
     "runs code it builds or downloads on the way"),
    (r"\bcurl\b.*\s(-d|--data\S*|-F|--form|-T|--upload-file)\b|\bwget\b.*--post|\b(scp|sftp|rsync)\b.*\S+:|\b(nc|ncat|netcat|socat)\b",
     "sends data from this computer to another one"),
    (r"(\.ssh/|\.gnupg/|ai\.secret|\.netrc|\.aws/|\.kube/|\.docker/config|keyrings/|Login Data|Cookies|logins\.json|key4\.db|/etc/shadow)",
     "touches passwords or keys"),
    (r"(>>?|\btee\b(\s+-a)?)\s*[\"']?(~|\$HOME|/home/[^/\s]+)/(\.bash\w*|\.profile|\.zsh\w*|\.config/(autostart|systemd|hypr|environment\.d|memora)|\.local/(bin|share/applications))",
     "changes what runs when you log in"),
    (r"\bsed\s+(-\w+\s+)*-i|\bsystemd-run\b|\bcrontab\b|\bat\s+now\b", "changes files in place or schedules a command"),
]

# Places in the home folder that decide what runs at login or in every
# terminal, and the ones that hold passwords and keys.
STARTUP = [".bashrc", ".bash_profile", ".bash_login", ".profile", ".zshrc", ".zprofile", ".pam_environment", ".xprofile",
           ".config/autostart", ".config/systemd", ".config/hypr", ".config/environment.d", ".config/memora",
           ".config/uwsm", ".local/bin", ".local/share/applications", ".local/share/mise/shims"]
SECRETS = [".ssh", ".gnupg", ".config/memora/ai.secret", ".netrc", ".aws", ".kube", ".docker/config.json", ".local/share/keyrings",
           ".password-store", ".config/chromium", ".mozilla", ".config/gh/hosts.yml", ".git-credentials", ".claude/.credentials.json"]


def _under(p, names):
    try:
        rel = p.relative_to(HOME).as_posix()
    except ValueError:
        return False
    return any(rel == n or rel.startswith(n + "/") for n in names)


def classify_path_read(path):
    p = Path(path).expanduser().resolve()
    if _under(p, SECRETS) or str(p) in ("/etc/shadow", "/etc/gshadow") or str(p).startswith("/etc/NetworkManager/system-connections"):
        return "risky", "holds passwords or keys"
    return "safe", ""


def classify_command(cmd):
    for pat, why in CRITICAL:
        if re.search(pat, cmd):
            return "critical", why
    for pat, why in RISKY:
        if re.search(pat, cmd):
            return "risky", why
    return "safe", ""


def classify_path_write(path, exists):
    p = Path(path).expanduser().resolve()
    system = ["/usr", "/etc", "/boot", "/bin", "/lib", "/lib64", "/sbin", "/opt", "/var", "/root", "/srv"]
    if any(str(p) == s or str(p).startswith(s + "/") for s in system):
        return "risky", "changes a system file"
    if not (p == HOME or HOME in p.parents or Path("/tmp") in p.parents):
        return "risky", "writes outside your home folder"
    if _under(p, SECRETS):
        return "risky", "changes where passwords or keys are kept"
    if _under(p, STARTUP):
        return "risky", "changes what runs when you log in or open a terminal"
    if exists:
        return "risky", "replaces an existing file"
    return "safe", ""


# ----------------------------------------------------------------- tools ----
def tool(name, description, props, required=()):
    return {
        "name": name,
        "description": description,
        "eager_input_streaming": True,
        "input_schema": {"type": "object", "properties": props, "required": list(required)},
    }


S = {"type": "string"}
I = {"type": "integer"}
TOOLS = [
    tool("run_command", "Run a bash command on this computer and get its output (stdout, stderr, exit code). Use sudo for administrator commands. Times out after `timeout` seconds (default 120, max 900). Do not use it to open GUI apps (use open).",
         {"command": S, "reason": {"type": "string", "description": "One short sentence on why, shown to the person when it needs their OK."}, "timeout": I},
         ["command", "reason"]),
    tool("read_file", "Read a file: text (up to max_bytes, default 60000, from offset), PDFs and Word/LibreOffice/RTF documents (their text), pictures (you see them).",
         {"path": S, "offset": I, "max_bytes": I}, ["path"]),
    tool("write_file", "Create a text file, or replace one entirely, with the given content. Folders are created as needed. To change part of an existing file use edit_file.",
         {"path": S, "content": S}, ["path", "content"]),
    tool("edit_file", "Change part of a text file: replace `old_text` (copied exactly from the file, unique in it unless replace_all) with `new_text`. Empty new_text deletes it.",
         {"path": S, "old_text": S, "new_text": S, "replace_all": {"type": "boolean"}}, ["path", "old_text", "new_text"]),
    tool("trash", "The Trash: move files or folders there (`paths`; they can be restored, unlike rm), list what is in it, restore one by its original path, or empty it.",
         {"action": {"type": "string", "enum": ["move", "list", "restore", "empty"]}, "paths": {"type": "array", "items": S}, "path": S}, ["action"]),
    tool("list_directory", "List a folder: names, kinds and sizes.", {"path": S}, ["path"]),
    tool("open", "Open an app (by name, e.g. 'Files', 'Browser', 'Terminal', 'Text Editor', or a desktop id), a file or folder (path), or a web address (URL).",
         {"target": S}, ["target"]),
    tool("system_setting", "Change a setting. volume/brightness: 0-100 or +N/-N. wifi/bluetooth/do_not_disturb/night_shift/dock_autohide: on|off. keep_awake (screen stays on, no lock or sleep): off, on, or minutes. appearance: light|dark. wallpaper: image path, or 'default'. dock_size: 36-72. settings_pane: open System Settings at a pane (wifi, bluetooth, sound, displays, battery, dock, ...).",
         {"setting": {"type": "string", "enum": ["volume", "brightness", "wifi", "bluetooth", "appearance", "wallpaper", "do_not_disturb", "focus", "night_shift", "keep_awake", "dock_autohide", "dock_position", "dock_size", "settings_pane"]}, "value": S},
         ["setting", "value"]),
    tool("windows", "List open windows, or focus, close, minimize, maximize or restore one. `window` is an address from the list or an app class.",
         {"action": {"type": "string", "enum": ["list", "focus", "close", "minimize", "maximize", "restore"]}, "window": S}, ["action"]),
    tool("screenshot", "Take a screenshot of the screen to see what is on it. Coordinates for click/scroll are in this image's pixels.", {}),
    tool("click", "Click at a point of the last screenshot.",
         {"x": I, "y": I, "button": {"type": "string", "enum": ["left", "right", "middle"]}, "double": {"type": "boolean"}}, ["x", "y"]),
    tool("type_text", "Type text into an app, as if on the keyboard. Always pass `window` (an address from windows/wait_for_window, or the app's name or class, e.g. 'chromium'): that window is brought to the front first, so the text never lands in the chat. enter=true presses Return after.",
         {"text": S, "window": S, "enter": {"type": "boolean"}}, ["text"]),
    tool("press_keys", "Press a key or shortcut, e.g. 'Return', 'Escape', 'ctrl+s', 'ctrl+l', 'alt+F4', 'super'. Pass `window` to send it to that app (brought to the front first).",
         {"keys": S, "window": S}, ["keys"]),
    tool("scroll", "Scroll at a point of the last screenshot.",
         {"x": I, "y": I, "direction": {"type": "string", "enum": ["up", "down", "left", "right"]}, "amount": I}, ["x", "y", "direction"]),
    tool("notify", "Show a desktop notification.", {"title": S, "body": S}, ["title"]),
    tool("browse", "Open the Browser at a web address or straight on search results, and bring it to the front. Use this whenever the person wants to SEE something online (\"open the browser and search X\", \"show me X on YouTube\"): give `search` (Google results) or `url` (any address, e.g. a YouTube or Maps search URL). Never open the browser and then type the search.",
         {"url": S, "search": S}),
    tool("wait_for_window", "Wait until an app's window is open (after open/browse), bring it to the front and return its address. `app` is a name or class ('chromium', 'Text Editor', 'org.gnome.Nautilus').",
         {"app": S, "timeout": I}, ["app"]),
    tool("arrange_window", "Place a window on its screen: left, right, top, bottom, fill, center, top-left, top-right, bottom-left, bottom-right, left-third, center-third, right-third, left-two-thirds, right-two-thirds, or restore. `window`: address or app; default the focused one.",
         {"zone": {"type": "string", "enum": ["left", "right", "top", "bottom", "fill", "center", "top-left", "top-right", "bottom-left", "bottom-right", "left-third", "center-third", "right-third", "left-two-thirds", "right-two-thirds", "restore"]}, "window": S}, ["zone"]),
    tool("desktops", "Desktops (workspaces): go to desktop `number`, or move the focused window (or `window`) to it.",
         {"action": {"type": "string", "enum": ["go", "move_window"]}, "number": I, "window": S}, ["action", "number"]),
    tool("clipboard", "Read the clipboard (get), the text selected right now in any app (selection), or put text on the clipboard (set; then paste in an app with press_keys ctrl+v).",
         {"action": {"type": "string", "enum": ["get", "selection", "set"]}, "text": S}, ["action"]),
    tool("media", "Music and video playing in any app (Player, Browser, Spotify…): status shows what is playing; play, pause, toggle, next, previous control it.",
         {"action": {"type": "string", "enum": ["status", "play", "pause", "toggle", "next", "previous"]}}, ["action"]),
    tool("apps", "Apps on this computer and in the App Store: list (installed apps), running (open apps), search (the App Store / Flathub), install or uninstall an App Store app by its id.",
         {"action": {"type": "string", "enum": ["list", "running", "search", "install", "uninstall"]}, "query": S, "id": S}, ["action"]),
    tool("find_files", "Find files: by `name` (wildcards allowed, e.g. '*.pdf', 'invoice*') and/or by `text` inside them. Searches `folder` (default the home folder), newest first, up to 50.",
         {"name": S, "text": S, "folder": S}),
    tool("reminder", "Reminders and timers: set one in `minutes` or `at` a time ('18:30', 'tomorrow 9:00', '2026-12-24 10:00') with `text`; list them; cancel one by id.",
         {"action": {"type": "string", "enum": ["set", "list", "cancel"]}, "text": S, "minutes": I, "at": S, "id": S}, ["action"]),
    tool("calendar", "The Calendar app: list events (and public holidays are not included) from today for `days` days (default 7); add an event (title, start 'YYYY-MM-DD HH:MM' or 'YYYY-MM-DD' for all day, optional end, calendar name, location, notes, repeat none/daily/weekly/monthly/yearly, alert minutes before, -1 for none); remove one by id; list the calendars. The person gets a notification at the alert time.",
         {"action": {"type": "string", "enum": ["list", "add", "remove", "calendars"]}, "days": I, "title": S, "start": S, "end": S, "calendar": S,
          "location": S, "notes": S, "repeat": {"type": "string", "enum": ["none", "daily", "weekly", "monthly", "yearly"]}, "alert": I, "id": S}, ["action"]),
    tool("notes", "The Notes app: create a note (title and text; lines starting with '☐ ' are checklist items), list recent notes, search them, read one by id, append text to one by id (e.g. add to a shopping list), or delete one by id (it goes to Recently Deleted).",
         {"action": {"type": "string", "enum": ["create", "list", "search", "read", "append", "delete"]}, "title": S, "text": S, "query": S, "id": S}, ["action"]),
    tool("widget", "Desktop widgets of your own: small glass cards on the desktop picture. create (or update) one from QML you write (read the widgets guide first: skill('widgets')), remove one, list them, show one's QML, or check one. After create it says whether it loaded, then describes how it looks once its data is in (each text and where it is, overlaps, things cut off, QML errors while running): keep fixing and creating again until it reports no problems.",
         {"action": {"type": "string", "enum": ["create", "remove", "list", "show", "check"]}, "name": S,
          "size": {"type": "string", "enum": ["small", "medium", "large"]}, "qml": S}, ["action"]),
    tool("power", "Lock the screen, sleep, restart, shut down or log out. Restart, shut down and log out show their own question on screen.",
         {"action": {"type": "string", "enum": ["lock", "sleep", "restart", "shutdown", "logout"]}}, ["action"]),
    tool("system_info", "Facts about the computer now: battery, network, storage, memory, cpu, processes (the busiest), displays, audio, or all.",
         {"what": {"type": "string", "enum": ["all", "battery", "network", "storage", "memory", "cpu", "processes", "displays", "audio"]}}, ["what"]),
    tool("download", "Download a file from the internet into Downloads (or `folder`) and return its path.",
         {"url": S, "folder": S}, ["url"]),
    tool("weather", "Current weather and the next days, for `place` (a city) or where the computer is.", {"place": S}),
    tool("skill", "Read a how-to guide before a task it covers (the list is in the system prompt). Follow it.", {"name": S}, ["name"]),
    tool("remember", "Save a fact about the person or their preferences to the memory file, for later conversations.", {"fact": S}, ["fact"]),
    tool("forget", "Remove from the memory file every saved fact that contains `text`.", {"text": S}, ["text"]),
    tool("past_chats", "Earlier conversations with the person: list the recent ones (date and first message), search them for `query`, or read one by `id`.",
         {"action": {"type": "string", "enum": ["list", "search", "read"]}, "query": S, "id": S}, ["action"]),
]
SCREEN_TOOLS = {"screenshot", "click", "type_text", "press_keys", "scroll"}
# Tools that put an app in front of the person or work in one: the chat folds into
# its pill and lets go of the keyboard while they run.
HANDS_TOOLS = {"click", "type_text", "press_keys", "scroll", "browse", "open", "wait_for_window", "arrange_window", "desktops"}
# Read web pages without server tools (DeepSeek).
FETCH_TOOL = tool("fetch_url", "Read a web page as plain text (for answering from it). Give a full URL.", {"url": S}, ["url"])
SERVER_TOOLS = [
    {"type": "web_search_20260209", "name": "web_search"},
    {"type": "web_fetch_20260209", "name": "web_fetch"},
]


def check_input(name, data):
    """Validate a tool input against its schema (eager streaming skips server checks)."""
    spec = next((t for t in TOOLS + [FETCH_TOOL] if t["name"] == name), None)
    if spec is None or not isinstance(data, dict):
        return "unknown tool or input is not an object"
    props = spec["input_schema"]["properties"]
    for req in spec["input_schema"]["required"]:
        if req not in data:
            return f"missing required field '{req}'"
    for k, v in data.items():
        t = props.get(k, {}).get("type")
        ok = {"string": isinstance(v, str), "integer": isinstance(v, int) and not isinstance(v, bool),
              "boolean": isinstance(v, bool),
              "array": isinstance(v, list) and all(isinstance(x, str) for x in v)}.get(t, True)
        if not ok:
            return f"field '{k}' should be {t}"
        enum = props.get(k, {}).get("enum")
        if enum and v not in enum:
            return f"field '{k}' must be one of {enum}"
    return None


def clip(s, n=OUT_LIMIT):
    return s if len(s) <= n else s[: n // 2] + f"\n… [{len(s) - n} characters cut] …\n" + s[-n // 2:]


def sh(args, timeout=30, **kw):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout, **kw)


class Screen:
    """Screenshots of the focused monitor, scaled to fit the model; clicks are mapped back."""
    max_side = 1600

    def __init__(self):
        self.scale = 1.0
        self.ox = 0
        self.oy = 0

    def grab(self):
        mons = json.loads(sh(["hyprctl", "-j", "monitors"]).stdout or "[]")
        m = next((x for x in mons if x.get("focused")), mons[0] if mons else None)
        if not m:
            raise RuntimeError("no monitor")
        w, h = m["width"] / m.get("scale", 1), m["height"] / m.get("scale", 1)
        self.ox, self.oy = m["x"], m["y"]
        self.scale = min(1.0, self.max_side / max(w, h))
        out = subprocess.run(["grim", "-o", m["name"], "-s", f"{self.scale * m.get('scale', 1):.4f}", "-t", "png", "-"],
                             capture_output=True, timeout=15)
        if out.returncode != 0:
            raise RuntimeError(out.stderr.decode() or "grim failed")
        return base64.b64encode(out.stdout).decode()

    def to_screen(self, x, y):
        return int(self.ox + x / self.scale), int(self.oy + y / self.scale)


SCREEN = Screen()
YDO = {"YDOTOOL_SOCKET": os.environ.get("YDOTOOL_SOCKET", "/run/memora-ydotool.sock")}

KEYCODES = {  # Linux input event codes for ydotool key
    "esc": 1, "escape": 1, "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9, "9": 10, "0": 11,
    "minus": 12, "-": 12, "equal": 13, "=": 13, "backspace": 14, "tab": 15, "q": 16, "w": 17, "e": 18, "r": 19,
    "t": 20, "y": 21, "u": 22, "i": 23, "o": 24, "p": 25, "[": 26, "]": 27, "return": 28, "enter": 28,
    "ctrl": 29, "control": 29, "a": 30, "s": 31, "d": 32, "f": 33, "g": 34, "h": 35, "j": 36, "k": 37, "l": 38,
    ";": 39, "'": 40, "`": 41, "shift": 42, "\\": 43, "z": 44, "x": 45, "c": 46, "v": 47, "b": 48, "n": 49,
    "m": 50, ",": 51, "comma": 51, ".": 52, "period": 52, "/": 53, "slash": 53, "alt": 56, "space": 57,
    "capslock": 58, "f1": 59, "f2": 60, "f3": 61, "f4": 62, "f5": 63, "f6": 64, "f7": 65, "f8": 66, "f9": 67,
    "f10": 68, "f11": 87, "f12": 88, "home": 102, "up": 103, "pageup": 104, "page_up": 104, "left": 105,
    "right": 106, "end": 107, "down": 108, "pagedown": 109, "page_down": 109, "insert": 110, "delete": 111,
    "super": 125, "meta": 125, "win": 125, "cmd": 125, "print": 99,
}


def press_keys(combo):
    names = [k.strip().lower() for k in re.split(r"\+(?!$)", combo) if k.strip()]
    codes = []
    for n in names:
        if n not in KEYCODES:
            raise ValueError(f"unknown key '{n}'")
        codes.append(KEYCODES[n])
    seq = [f"{c}:1" for c in codes] + [f"{c}:0" for c in reversed(codes)]
    r = sh(["ydotool", "key", *seq], env={**os.environ, **YDO})
    if r.returncode:
        raise RuntimeError(r.stderr.strip() or "ydotool failed")


def find_app(name):
    """Desktop entry id for an app name like 'Files' or 'org.gnome.Nautilus'."""
    dirs = [HOME / ".local/share/applications", Path("/usr/local/share/applications"), Path("/usr/share/applications")]
    want = name.lower().removesuffix(".desktop")
    best = None
    for d in dirs:
        for f in sorted(d.glob("*.desktop")) if d.exists() else []:
            fid = f.stem
            try:
                text = f.read_text(errors="ignore")
            except OSError:
                continue
            m = re.search(r"^Name=(.*)$", text, re.M)
            nm = (m.group(1) if m else "").lower()
            if fid.lower() == want or nm == want:
                return fid
            if best is None and (want in nm or want in fid.lower()):
                best = fid
    return best


def clients():
    try:
        return [c for c in json.loads(sh(["hyprctl", "-j", "clients"]).stdout or "[]") if c.get("mapped")]
    except ValueError:
        return []


def find_window(spec):
    """A window by address, class, app name or title words; the most recently used first."""
    spec = (spec or "").strip()
    cs = sorted(clients(), key=lambda c: c.get("focusHistoryID", 99))
    if not spec:
        return cs[0] if cs else None
    if spec.startswith("0x"):
        return next((c for c in cs if c["address"] == spec), None)
    want = spec.lower().removesuffix(".desktop")
    app = find_app(spec)
    aliases = {"browser": "chromium", "terminal": "com.mitchellh.ghostty", "files": "memora-files",
               "text editor": "org.gnome.texteditor", "settings": "memora-settings", "system settings": "memora-settings"}
    want = aliases.get(want, want)
    for test in (lambda c: c["class"].lower() == want or c.get("initialClass", "").lower() == want,
                 lambda c: bool(app) and c["class"].lower() == app.lower(),
                 lambda c: want in c["class"].lower(),
                 lambda c: want in c.get("title", "").lower()):
        hit = next((c for c in cs if test(c)), None)
        if hit:
            return hit
    return None


def focus_window(c):
    a = c["address"]
    if c.get("workspace", {}).get("name") == "special:minimized":
        sh(["hyprctl", "dispatch", f'hl.dsp.window.move({{ workspace = "{active_ws()}", follow = true, window = "address:{a}" }})'])
    sh(["hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{a}" }})'])
    sh(["hyprctl", "dispatch", f'hl.dsp.window.alter_zorder({{ mode = "top", window = "address:{a}" }})'])
    time.sleep(0.15)


def shell_prefs(**kw):
    """Change the shell's preferences (~/.config/memora/shell.json); the shell follows the file."""
    prefs = CONF / "shell.json"
    try:
        j = json.loads(prefs.read_text())
    except (OSError, ValueError):
        j = {}
    j.update(kw)
    prefs.write_text(json.dumps(j, indent=2) + "\n")


def html_text(html):
    html = re.sub(r"(?is)<(script|style|noscript|svg)[^>]*>.*?</\1>", " ", html)
    html = re.sub(r"(?i)<br\s*/?>|</(p|div|h[1-6]|li|tr|section|article)>", "\n", html)
    text = re.sub(r"<[^>]+>", " ", html)
    import html as h
    text = h.unescape(text)
    return re.sub(r"\n\s*\n+", "\n\n", re.sub(r"[ \t]+", " ", text)).strip()


SKILLS = Path(MEMORA_PATH) / "ai" / "skills"
SHIMS = Path(__file__).with_name("shims")


def with_sudo():
    """The environment for commands the assistant runs: its own sudo first."""
    return {**os.environ, "PATH": f"{SHIMS}:{os.environ.get('PATH', '/usr/bin')}"}


def skills():
    """{name: (when, body)} from ai/skills/*.md (front matter: name, when)."""
    out = {}
    for f in sorted(SKILLS.glob("*.md")) if SKILLS.exists() else []:
        t = f.read_text()
        m = re.match(r"---\n(.*?)\n---\n(.*)", t, re.S)
        if not m:
            continue
        meta = dict(l.split(":", 1) for l in m.group(1).splitlines() if ":" in l)
        out[meta.get("name", f.stem).strip()] = (meta.get("when", "").strip(), m.group(2).strip())
    return out


NOTES = HOME / ".local/share/memora/notes.json"


class Tools:
    vision = True    # the model can look at pictures (screenshots); DeepSeek and the others can't

    def __init__(self, ui):
        self.ui = ui
        self.hands_on = False

    def run(self, name, data):
        """Returns (content, is_error). content: str or list of blocks."""
        if name in HANDS_TOOLS and not self.hands_on:
            # Fold the chat so the app is visible and gets the keyboard.
            self.hands_on = True
            getattr(self.ui, "hands", lambda on: None)(True)
            time.sleep(0.35)
        return getattr(self, "t_" + name)(**data)

    def target(self, window):
        """Bring `window` to the front before keys go to it."""
        if not window:
            return None
        c = find_window(window)
        if not c:
            raise RuntimeError(f"No open window matches '{window}'. Use windows(list) to see them.")
        focus_window(c)
        return c

    def t_run_command(self, command, reason, timeout=120):
        timeout = max(5, min(int(timeout or 120), 900))
        level, why = classify_command(command)
        if level != "safe" and not self.ui.confirm(level, "Run this command?", command, f"{reason.strip()} It {why}."):
            return "The person declined to run this command.", True
        # Administrator commands: "sudo" here is ai/shims/sudo, which goes through
        # polkit (Memora's password dialog) for that one command only.
        # Stop (in the window) ends the command too, not only the answer.
        p = subprocess.Popen(["bash", "-lc", command], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=HOME,
                             start_new_session=True, env=with_sudo())
        end = time.time() + timeout
        while True:
            try:
                so, se = p.communicate(timeout=0.3)
                break
            except subprocess.TimeoutExpired:
                if self.ui.stopped() or time.time() > end:
                    try:
                        os.killpg(p.pid, 15)
                    except OSError:
                        pass
                    so, se = p.communicate()
                    why = "stopped by the person" if self.ui.stopped() else f"timed out after {timeout}s"
                    return clip(f"{why}\n{so or ''}"), True
        out = (so or "") + (("\n[stderr]\n" + se) if se else "")
        return clip(f"exit code {p.returncode}\n{out}".strip()), p.returncode != 0

    def t_read_file(self, path, offset=0, max_bytes=60000):
        p = Path(path).expanduser()
        level, why = classify_path_read(str(p))
        if level != "safe" and not self.ui.confirm(level, f"Read {p}?", "", f"This file {why}."):
            return "The person declined to share this file.", True
        if p.is_dir():
            return f"{p} is a folder: use list_directory.", True
        ext = p.suffix.lower()
        if ext in IMAGE_TYPES or ext in (".bmp", ".tif", ".tiff", ".heic", ".avif"):
            if not self.vision:
                return f"{p} is a picture ({p.stat().st_size:,} bytes); this model can't look at pictures.", True
            data, media = picture(str(p), ext)
            if not data:
                return f"Couldn't open the picture {p}.", True
            return [{"type": "text", "text": f"The picture {p}:"}, {"type": "image", "source": {"type": "base64", "media_type": media, "data": data}}], False
        doc = document_text(p)
        if doc is not None:
            start = max(0, offset)
            part = doc[start:start + max(1, min(max_bytes, 200000))]
            tail = f"\n[characters {start}-{start + len(part)} of {len(doc)}; read more with offset]" if len(doc) > start + len(part) else ""
            return (part or "(no text in this document: it may be scanned pictures)") + tail, False
        with open(p, "rb") as f:
            f.seek(max(0, offset))
            data = f.read(max(1, min(max_bytes, 200000)))
        size = p.stat().st_size
        text = data.decode("utf-8", errors="replace")
        tail = f"\n[bytes {offset}-{offset + len(data)} of {size}]" if size > len(data) else ""
        return text + tail, False

    def t_write_file(self, path, content):
        p = Path(path).expanduser()
        level, why = classify_path_write(str(p), p.exists())
        if level != "safe":
            preview = content if len(content) < 1500 else content[:1500] + "\n…"
            if not self.ui.confirm(level, f"Write {p}?", preview, f"This {why}."):
                return "The person declined this change.", True
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        return f"Wrote {len(content)} characters to {p}.", False

    def t_edit_file(self, path, old_text, new_text, replace_all=False):
        p = Path(path).expanduser()
        if not p.is_file():
            return f"No file {p}. To make a new one use write_file.", True
        text = p.read_text(errors="strict")
        n = text.count(old_text) if old_text else 0
        if n == 0:
            return "old_text is not in the file (it must match exactly, spaces and line breaks too). Read the file again and copy it.", True
        if n > 1 and not replace_all:
            return f"old_text is in the file {n} times: give more of the text around it, or replace_all=true.", True
        level, why = classify_path_write(str(p), True)
        # A plain edit of one's own document is shown, not asked about; startup
        # files, keys and system files still wait for the person's OK.
        if level != "safe" and why != "replaces an existing file":
            preview = "\n".join(f"- {l}" for l in old_text[:700].splitlines()) + "\n" + "\n".join(f"+ {l}" for l in new_text[:700].splitlines())
            if not self.ui.confirm(level, f"Change {p}?", preview, f"This {why}."):
                return "The person declined this change.", True
        p.write_text(text.replace(old_text, new_text) if replace_all else text.replace(old_text, new_text, 1))
        return f"Changed {p} ({n if replace_all else 1} place{'s' if replace_all and n > 1 else ''}).", False

    def t_trash(self, action, paths=None, path=""):
        if action == "list":
            r = sh(["gio", "trash", "--list"])
            rows = [l.split("\t", 1)[-1] for l in r.stdout.splitlines() if l.strip()]
            return ("In the Trash:\n" + "\n".join(rows[:100]) + (f"\n… and {len(rows) - 100} more" if len(rows) > 100 else "")) if rows else "The Trash is empty.", False
        if action == "restore":
            want = str(Path(path or "").expanduser())
            r = sh(["gio", "trash", "--list"])
            hit = next((l.split("\t", 1)[0] for l in r.stdout.splitlines() if l.split("\t", 1)[-1] == want), None)
            if not hit:
                return f"Nothing from {want} is in the Trash (see trash list).", True
            r = sh(["gio", "trash", "--restore", hit])
            return (f"Restored {want}." if r.returncode == 0 else f"Couldn't restore it: {r.stderr.strip()}"), r.returncode != 0
        if action == "empty":
            if not self.ui.confirm("risky", "Empty the Trash?", "", "Everything in it is deleted for good."):
                return "The person declined.", True
            r = sh(["gio", "trash", "--empty"])
            return ("The Trash is empty." if r.returncode == 0 else f"Failed: {r.stderr.strip()}"), r.returncode != 0
        items = [Path(x).expanduser() for x in (paths or ([path] if path else []))]
        if not items:
            return "Give the paths to move to the Trash.", True
        missing = [str(x) for x in items if not x.exists() and not x.is_symlink()]
        if missing:
            return "These don't exist: " + ", ".join(missing), True
        # Things in the home folder can come back from the Trash: no question.
        # Startup files, keys, the home folder itself and anything outside it: asked.
        grave = [x for x in items if x.resolve() == HOME or HOME not in x.resolve().parents or _under(x.resolve(), STARTUP + SECRETS)]
        if grave and not self.ui.confirm("risky", "Move to the Trash?", "\n".join(map(str, items)),
                                         "Some of these are outside your home folder, or hold settings or keys."):
            return "The person declined.", True
        r = sh(["gio", "trash", "--", *map(str, items)], timeout=120)
        if r.returncode:
            return f"Couldn't move to the Trash: {r.stderr.strip()}", True
        return f"Moved {len(items)} item{'s' if len(items) > 1 else ''} to the Trash (restore with trash action=restore).", False

    def t_list_directory(self, path):
        p = Path(path).expanduser()
        rows = []
        for e in sorted(p.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))[:500]:
            try:
                kind = "dir" if e.is_dir() else ("link" if e.is_symlink() else "file")
                size = "" if e.is_dir() else f"{e.stat().st_size} B"
            except OSError:
                kind, size = "?", ""
            rows.append(f"{kind:4} {size:>12}  {e.name}")
        return "\n".join(rows) or "(empty)", False

    def t_open(self, target):
        t = target.strip()
        if re.match(r"^[a-z]+://", t) or Path(t).expanduser().exists():
            subprocess.Popen(["xdg-open", str(Path(t).expanduser()) if not re.match(r"^[a-z]+://", t) else t],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            return f"Opened {t}.", False
        app = find_app(t)
        if not app:
            return f"No app called '{t}' is installed.", True
        subprocess.Popen(["uwsm", "app", "--", app + ".desktop"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        return f"Opening {app}. Use wait_for_window before typing or clicking in it.", False

    def t_system_setting(self, setting, value):
        v = value.strip().lower()
        on = v in ("on", "true", "1", "yes", "enable", "enabled")
        if setting == "volume":
            arg = (v.lstrip("+-") + "%" + ("+" if v.startswith("+") else "-")) if v[:1] in "+-" else v.rstrip("%") + "%"
            r = sh(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", arg])
        elif setting == "brightness":
            arg = (v.lstrip("+-") + "%" + ("+" if v.startswith("+") else "-")) if v[:1] in "+-" else v.rstrip("%") + "%"
            r = sh(["brightnessctl", "-q", "set", arg])
        elif setting == "wifi":
            r = sh(["nmcli", "radio", "wifi", "on" if on else "off"])
        elif setting == "bluetooth":
            r = sh(["bluetoothctl", "power", "on" if on else "off"])
        elif setting == "appearance":
            r = sh(["memora-theme", "set", "light" if "light" in v else "dark"])
        elif setting == "wallpaper":
            prefs = CONF / "shell.json"
            try:
                j = json.loads(prefs.read_text())
            except (OSError, ValueError):
                j = {}
            j["wallpaper"] = "" if v == "default" else str(Path(value.strip()).expanduser())
            prefs.write_text(json.dumps(j, indent=2) + "\n")
            return "Wallpaper changed.", False
        elif setting in ("focus", "do_not_disturb"):
            r = sh(["memora-shell", "setFocusMode", "on" if on else "off"])
        elif setting == "keep_awake":
            if v in ("off", "false", "0", "no"):
                until = 0
            elif v.isdigit():
                until = int((time.time() + int(v) * 60) * 1000)
            else:
                until = -1
            shell_prefs(awakeUntil=until)
            return ("Keep Awake is off." if until == 0 else "Keep Awake is on: the screen stays on and won't lock or sleep" + (f" for {v} minutes." if v.isdigit() else " until it is turned off.")), False
        elif setting == "dock_autohide":
            shell_prefs(dockAutohide=on, dockHiding="always" if on else "never")
            return f"The Dock {'hides until the pointer reaches the edge of the screen' if on else 'stays on screen'}.", False
        elif setting == "dock_position":
            pos = v if v in ("left", "bottom", "right") else "bottom"
            shell_prefs(dockPosition=pos)
            return f"The Dock is now at the {pos} of the screen.", False
        elif setting == "dock_size":
            shell_prefs(dockSize=max(36, min(72, int(re.sub(r"\D", "", v) or 58))))
            return "Dock size changed.", False
        elif setting == "night_shift":
            r = sh(["bash", "-c", "setsid hyprsunset -t 4200 >/dev/null 2>&1 &" if on else "pkill -x hyprsunset; true"])
        elif setting == "settings_pane":
            subprocess.Popen(["memora-settings", v], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return f"Opened System Settings at {v}.", False
        else:
            return "Unknown setting.", True
        return (f"{setting} set to {value}." if r.returncode == 0 else f"Failed: {r.stderr.strip()}"), r.returncode != 0

    def t_windows(self, action, window=""):
        clients = json.loads(sh(["hyprctl", "-j", "clients"]).stdout or "[]")
        if action == "list":
            rows = [f"{c['address']}  {c['class']}  ws={c['workspace']['name']}  \"{c['title'][:60]}\"" for c in clients if c.get("mapped")]
            return "\n".join(rows) or "No windows.", False
        if not window:
            return "Say which window (address or app class).", True
        if window.startswith("0x") and not re.fullmatch(r"0x[0-9a-fA-F]+", window):
            return "That is not a window address. Use windows(list) to see them.", True
        sel = f"address:{window}" if window.startswith("0x") else f"class:{re.escape(window)}"
        lua = {
            "focus": f'hl.dsp.focus({{ window = "{sel}" }})',
            "close": f'hl.dsp.window.close({{ window = "{sel}" }})',
            "minimize": f'hl.dsp.window.move({{ workspace = "special:minimized", follow = false, window = "{sel}" }})',
            "restore": f'hl.dsp.window.move({{ workspace = "{active_ws()}", follow = true, window = "{sel}" }})',
            "maximize": None,
        }[action]
        if action == "maximize":
            sh(["hyprctl", "dispatch", f'hl.dsp.focus({{ window = "{sel}" }})'])
            lua = 'hl.dsp.window.fullscreen({ mode = "maximized" })'
        r = sh(["hyprctl", "dispatch", lua])
        return (r.stdout.strip() or "ok"), "ok" not in r.stdout

    def t_screenshot(self):
        if not self.vision:
            return ("This model can't look at pictures. To see what is on the screen use windows(list); "
                    "for a desktop widget use widget(action=\"check\"), which describes it in words."), True
        data = SCREEN.grab()
        return [{"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": data}}], False

    def t_click(self, x, y, button="left", double=False):
        sx, sy = SCREEN.to_screen(x, y)
        sh(["hyprctl", "dispatch", f"hl.dsp.cursor.move({{ x = {sx}, y = {sy} }})"])
        time.sleep(0.08)
        code = {"left": "0xC0", "right": "0xC1", "middle": "0xC2"}[button or "left"]
        args = ["ydotool", "click", code] + (["--repeat", "2", "--next-delay", "80"] if double else [])
        r = sh(args, env={**os.environ, **YDO})
        if r.returncode:
            return f"Could not click: {r.stderr.strip()}", True
        return f"Clicked {button} at {x},{y}.", False

    def t_type_text(self, text, window="", enter=False):
        c = self.target(window)
        r = sh(["wtype", "--", text], timeout=60)
        if r.returncode:
            return f"Failed: {r.stderr.strip()}", True
        if enter:
            time.sleep(0.05)
            press_keys("return")
        where = f" into {c['class']} (\"{c['title'][:40]}\")" if c else ""
        return f"Typed{where}{' and pressed Return' if enter else ''}.", False

    def t_press_keys(self, keys, window=""):
        c = self.target(window)
        press_keys(keys)
        return f"Pressed {keys}{' in ' + c['class'] if c else ''}.", False

    # ---- the web, apps, windows
    def t_browse(self, url="", search=""):
        import urllib.parse
        if not url and not search:
            return "Give a url or a search.", True
        if not url:
            url = "https://www.google.com/search?q=" + urllib.parse.quote_plus(search)
        elif not re.match(r"^[a-z]+://", url):
            url = "https://" + url
        before = {c["address"] for c in clients() if c["class"] == "chromium"}
        subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(60):
            time.sleep(0.25)
            cs = [c for c in clients() if c["class"] in ("chromium", "firefox", "brave-browser", "google-chrome")]
            new = [c for c in cs if c["address"] not in before]
            if new or (cs and _ > 6):
                focus_window(new[0] if new else sorted(cs, key=lambda c: c.get("focusHistoryID", 99))[0])
                return f"The Browser is open on {url} and in front.", False
        return f"Asked the Browser to open {url}; its window hasn't appeared yet.", False

    def t_wait_for_window(self, app, timeout=10):
        end = time.time() + max(1, min(int(timeout or 10), 60))
        while time.time() < end:
            c = find_window(app)
            if c:
                focus_window(c)
                return f"{c['class']} is open and in front: address {c['address']}, title \"{c['title'][:60]}\", at {c['at']} size {c['size']}.", False
            time.sleep(0.3)
        return f"No window for '{app}' after {timeout}s.", True

    def t_arrange_window(self, zone, window=""):
        c = find_window(window)
        if not c:
            return "No window to arrange.", True
        r = sh(["memora-window", zone, c["address"]])
        return (f"{c['class']} placed: {zone}." if r.returncode == 0 else f"Failed: {r.stderr.strip()}"), r.returncode != 0

    def t_desktops(self, action, number, window=""):
        n = max(1, min(int(number), 10))
        if action == "go":
            r = sh(["memora-shell", "desktop", "go", str(n)])
        else:
            if window:
                self.target(window)
            r = sh(["memora-shell", "desktop", "carry", str(n)])
        return ("Done." if r.returncode == 0 else f"Failed: {r.stderr.strip()}"), r.returncode != 0

    def t_clipboard(self, action, text=""):
        if action == "set":
            # wl-copy stays behind to serve the clipboard: don't wait on its output.
            r = subprocess.run(["wl-copy"], input=text, text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
            return ("On the clipboard." if r.returncode == 0 else "Couldn't set the clipboard."), r.returncode != 0
        if action == "selection":
            r = sh(["wl-paste", "-p", "-n"], timeout=10)
            return (clip(r.stdout) or "(nothing is selected right now)"), False
        r = sh(["wl-paste", "-n"], timeout=10)
        return (clip(r.stdout) or "(the clipboard is empty or holds an image)"), False

    def t_media(self, action):
        if action == "status":
            r = sh(["playerctl", "metadata", "--format", "{{playerName}}: {{status}} · {{artist}} – {{title}} ({{duration(position)}}/{{duration(mpris:length)}})"])
            return (r.stdout.strip() or "Nothing is playing."), False
        r = sh(["playerctl", {"toggle": "play-pause"}.get(action, action)])
        return ("Done." if r.returncode == 0 else "No player is running."), r.returncode != 0

    def t_apps(self, action, query="", id=""):
        if action == "list":
            names = set()
            for d in [HOME / ".local/share/applications", HOME / ".local/share/flatpak/exports/share/applications",
                      Path("/var/lib/flatpak/exports/share/applications"), Path("/usr/share/applications")]:
                for f in d.glob("*.desktop") if d.exists() else []:
                    t = f.read_text(errors="ignore")
                    if re.search(r"^NoDisplay=true", t, re.M):
                        continue
                    m = re.search(r"^Name=(.*)$", t, re.M)
                    if m:
                        names.add(f"{m.group(1)} ({f.stem})")
            return "\n".join(sorted(names, key=str.lower)), False
        if action == "running":
            return "\n".join(sorted({f"{c['class']}: {c['title'][:50]}" for c in clients()})) or "No apps are open.", False
        if action == "search":
            r = sh(["flatpak", "search", "--columns=application,name,description", "--", query], timeout=60)
            rows = [l for l in r.stdout.splitlines() if l.strip() and not re.search(r"\.(Plugin|Extension|Locale|Debug|Manual|Docs)\b", l)]
            return clip("\n".join(rows[:25]) or "Nothing found in the App Store."), False
        if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9._-]*", id or ""):
            return "Give the app's id (from search or list).", True
        if action == "install":
            if not self.ui.confirm("risky", f"Install {id}?", f"flatpak install --user flathub {id}", "It installs an app from the App Store (Flathub) for you."):
                return "The person declined.", True
            r = sh(["flatpak", "install", "--user", "-y", "--noninteractive", "flathub", id], timeout=1800)
        else:
            if not self.ui.confirm("risky", f"Uninstall {id}?", f"flatpak uninstall --user {id}", "It removes this app; your documents stay."):
                return "The person declined.", True
            r = sh(["flatpak", "uninstall", "--user", "-y", "--noninteractive", id], timeout=600)
        return clip(r.stdout[-2000:] + r.stderr[-2000:]).strip() or "Done.", r.returncode != 0

    # ---- files
    def t_find_files(self, name="", text="", folder="~"):
        root = Path(folder or "~").expanduser().resolve()
        if not root.exists():
            return f"No folder {root}.", True
        skip = ["-path", "*/.cache", "-prune", "-o", "-path", "*/.local/share/flatpak", "-prune", "-o", "-path", "*/node_modules", "-prune", "-o", "-path", "*/.git", "-prune", "-o"]
        if text:
            r = sh(["grep", "-rIil", "--exclude-dir=.cache", "--exclude-dir=.git", "--exclude-dir=node_modules", "--exclude-dir=.local",
                    *(["--include", name] if name else []), "--", text, str(root)], timeout=60)
            files = r.stdout.splitlines()
        else:
            r = sh(["find", str(root), *skip, "-iname", name or "*", "-type", "f", "-printf", "%T@ %p\n"], timeout=60)
            files = [l.split(" ", 1)[1] for l in sorted(r.stdout.splitlines(), reverse=True) if " " in l]
        return ("\n".join(files[:50]) + (f"\n… and {len(files) - 50} more" if len(files) > 50 else "")) or "No files found.", False

    def t_download(self, url, folder="~/Downloads"):
        if not re.match(r"^https?://", url):
            return "Give a full web address (https://…).", True
        d = Path(folder or "~/Downloads").expanduser()
        level, why = classify_path_write(str(d / "download"), False)
        if level != "safe" and not self.ui.confirm(level, f"Download into {d}?", url, f"This {why}."):
            return "The person declined this download.", True
        d.mkdir(parents=True, exist_ok=True)
        r = sh(["curl", "-fsSL", "--proto", "=http,https", "--max-time", "600", "--no-clobber", "-OJ", "--output-dir", str(d),
                "-w", "%{filename_effective}", "--", url], timeout=620)
        return (f"Saved {r.stdout.strip()}." if r.returncode == 0 else f"Download failed: {r.stderr.strip()}"), r.returncode != 0

    def t_fetch_url(self, url):
        if not re.match(r"^https?://", url):      # not file:// and the like
            return "Give a full web address (https://…).", True
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) MemoraAI"})
        with urllib.request.urlopen(req, timeout=20) as r:
            body = r.read(3_000_000).decode(r.headers.get_content_charset() or "utf-8", errors="replace")
        return clip(html_text(body) if "<" in body[:2000] else body), False

    # ---- the Calendar app (shell/calendar.qml): ~/.local/share/memora/calendar.json
    def t_calendar(self, action, days=7, title="", start="", end="", calendar="", location="", notes="", repeat="none", alert=10, id=""):
        f = HOME / ".local/share/memora/calendar.json"
        try:
            j = json.loads(f.read_text())
        except (OSError, ValueError):
            j = {"version": 1, "calendars": [{"id": "personal", "name": "Personal", "color": "#3d8bff", "on": True},
                                             {"id": "work", "name": "Work", "color": "#ff9f0a", "on": True},
                                             {"id": "family", "name": "Family", "color": "#30d158", "on": True}], "events": []}
        cals, evs = j.setdefault("calendars", []), j.setdefault("events", [])
        name_of = {c["id"]: c["name"] for c in cals}
        fmt = lambda ms, all_day: datetime.fromtimestamp(ms / 1000).strftime("%a %d %b %Y" if all_day else "%a %d %b %Y %H:%M")
        if action == "calendars":
            return "\n".join(f"{c['name']}" + ("" if c.get("on", True) else " (hidden)") for c in cals), False
        if action == "list":
            t0 = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
            a, b = t0.timestamp() * 1000, (t0 + timedelta(days=max(1, int(days or 7)))).timestamp() * 1000
            occ = []
            for e in evs:
                s0, ln, rule = e["start"], e["end"] - e["start"], e.get("repeat", "none")
                for n in range(0, 800 if rule != "none" else 1):
                    d = datetime.fromtimestamp(s0 / 1000)
                    if rule == "daily": d += timedelta(days=n)
                    elif rule == "weekly": d += timedelta(weeks=n)
                    elif rule in ("monthly", "yearly"):
                        m = d.month - 1 + n * (1 if rule == "monthly" else 12)
                        y, m = d.year + m // 12, m % 12 + 1
                        try:
                            d = d.replace(year=y, month=m)
                        except ValueError:
                            continue
                    t = d.timestamp() * 1000
                    if t >= b:
                        break
                    if t + ln + (86400000 if e.get("allDay") else 0) > a and t not in (e.get("skip") or []):
                        occ.append((t, e))
            occ.sort(key=lambda x: x[0])
            if not occ:
                return f"Nothing in the calendar for the next {days} days.", False
            return "\n".join(f"{fmt(t, e.get('allDay'))} · {e['title']} ({name_of.get(e.get('cal'), '?')}" + (f", {e['location']}" if e.get("location") else "")
                             + (f", every {e['repeat'][:-2] if e['repeat'] != 'daily' else 'day'}" if e.get("repeat", "none") != "none" else "") + f") id {e['id']}" for t, e in occ[:60]), False
        if action == "remove":
            keep = [e for e in evs if e["id"] != id]
            if len(keep) == len(evs):
                return f"No event with id {id}.", True
            j["events"] = keep
        elif action == "add":
            if not title or not start:
                return "Give the event a title and a start ('YYYY-MM-DD HH:MM', or 'YYYY-MM-DD' for all day).", True
            def parse(v):
                for fm in ("%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M", "%Y-%m-%d"):
                    try:
                        return datetime.strptime(v.strip(), fm), fm == "%Y-%m-%d"
                    except ValueError:
                        pass
                raise ValueError(f"Can't read the date '{v}'. Use 'YYYY-MM-DD HH:MM' or 'YYYY-MM-DD'.")
            try:
                s_dt, all_day = parse(start)
                e_dt = parse(end)[0] if end else (s_dt if all_day else s_dt + timedelta(hours=1))
            except ValueError as err:
                return str(err), True
            cal = next((c for c in cals if c["name"].lower() == (calendar or "").lower()), None) or next((c for c in cals if c.get("on", True)), cals[0])
            ev = {"id": f"e{time.time_ns() // 1_000_000}", "title": title, "cal": cal["id"], "start": int(s_dt.timestamp() * 1000), "end": int(e_dt.timestamp() * 1000),
                  "allDay": all_day, "location": location, "notes": notes, "repeat": repeat or "none", "until": 0, "alert": -1 if all_day and alert == 10 else alert, "skip": []}
            evs.append(ev)
        else:
            return "Unknown action.", True
        f.parent.mkdir(parents=True, exist_ok=True)
        tmp = f.with_suffix(".tmp")
        tmp.write_text(json.dumps(j, indent=1))
        tmp.replace(f)
        if action == "remove":
            return f"Removed the event {id}.", False
        return f"Added “{title}” on {fmt(ev['start'], ev['allDay'])} to {cal['name']}" + (f", alert {alert} min before" if ev["alert"] >= 0 else "") + ". It shows in Calendar.", False

    # ---- organiser
    def t_reminder(self, action, text="", minutes=0, at="", id=""):
        if action == "list":
            r = sh(["systemctl", "--user", "list-timers", "memora-reminder-*", "--all", "--no-pager", "--output=json"])
            try:
                rows = json.loads(r.stdout or "[]")
            except ValueError:
                rows = []
            out = []
            for t in rows:
                unit = t.get("unit", "").removesuffix(".timer")
                desc = sh(["systemctl", "--user", "show", "-p", "Description", "--value", unit + ".service"]).stdout.strip()
                when = time.strftime("%a %d %b %H:%M", time.localtime(int(t.get("next", 0)) / 1e6)) if t.get("next") else "?"
                out.append(f"{unit}: {when} — {desc}")
            return "\n".join(out) or "No reminders.", False
        if action == "cancel":
            if not id:
                return "Give the reminder's id (from list).", True
            if not re.fullmatch(r"memora-reminder-\d+(\.timer)?", id):
                return "That is not a reminder id (see list).", True
            r = sh(["systemctl", "--user", "stop", id.removesuffix(".timer") + ".timer"])
            return ("Cancelled." if r.returncode == 0 else f"Failed: {r.stderr.strip()}"), r.returncode != 0
        if not text:
            return "What should the reminder say?", True
        if at:
            r = sh(["date", "-d", at, "+%s"])
            if r.returncode:
                return f"Can't read the time '{at}'.", True
            secs = int(r.stdout) - int(time.time())
            if secs < 0:
                secs += 86400   # a time earlier today means tomorrow
        else:
            secs = int(minutes or 0) * 60
        if secs < 5:
            return "Give minutes or a time in the future.", True
        unit = f"memora-reminder-{time.time_ns() // 1_000_000}"
        # The banner plays the alert sound chosen in System Settings > Sound.
        cmd = f"notify-send -u critical -a Reminders -i alarm-symbolic 'Reminder' {shlex.quote(text)}; true"
        r = sh(["systemd-run", "--user", f"--unit={unit}", f"--description={text[:120]}", f"--on-active={secs}s",
                "--timer-property=AccuracySec=1s", "bash", "-c", cmd])
        when = time.strftime("%a %d %b %H:%M", time.localtime(time.time() + secs))
        return (f"Reminder set for {when} (id {unit})." if r.returncode == 0 else f"Failed: {r.stderr.strip()}"), r.returncode != 0

    def t_notes(self, action, title="", text="", query="", id=""):
        try:
            j = json.loads(NOTES.read_text())
        except (OSError, ValueError):
            j = {"version": 1, "folders": ["Notes"], "notes": []}
        notes = [n for n in j.get("notes", []) if not n.get("deleted")]
        notes.sort(key=lambda n: n.get("modified", 0), reverse=True)
        line = lambda n: f"{n['id']}  {time.strftime('%d %b %H:%M', time.localtime(n.get('modified', 0) / 1000))}  {n.get('text', '').splitlines()[0][:60] if n.get('text') else '(empty)'}"
        if action == "list":
            return "\n".join(line(n) for n in notes[:30]) or "No notes.", False
        if action == "search":
            q = query.lower()
            return "\n".join(line(n) for n in notes if q in n.get("text", "").lower()) or "No note matches.", False
        if action == "read":
            n = next((n for n in notes if n["id"] == id), None)
            return (n["text"] if n else "No note with that id."), not n
        import html as h
        para = lambda l: (f"<p><span style='font-size:22px; color:#9a9aa2;'>☐</span>&nbsp;{h.escape(l[2:])}</p>" if l.startswith("☐ ")
                          else f"<p>{h.escape(l) or '<br>'}</p>")
        now = int(time.time() * 1000)

        def save():
            NOTES.parent.mkdir(parents=True, exist_ok=True)
            tmp = NOTES.with_suffix(".tmp")
            tmp.write_text(json.dumps(j))
            tmp.replace(NOTES)
        if action in ("append", "delete"):
            n = next((n for n in notes if n["id"] == id), None)
            if not n:
                return "No note with that id (see list or search).", True
            if action == "delete":
                n["deleted"], n["modified"] = True, now
                save()
                return "The note is in Recently Deleted (in Notes).", False
            if not text.strip():
                return "What should be added?", True
            n["text"] = n.get("text", "").rstrip("\n") + "\n" + text
            n["html"] = n.get("html", "") + "".join(para(l) for l in text.splitlines())
            n["modified"] = now
            save()
            return "Added to the note.", False
        body = [l for l in text.splitlines()]
        n = {"id": f"n{now}", "folder": (j.get("folders") or ["Notes"])[0], "pinned": False, "deleted": False,
             "created": now, "modified": now, "text": (title + "\n" if title else "") + text,
             "html": (f"<h1>{h.escape(title)}</h1>" if title else "") + "".join(para(l) for l in body)}
        j.setdefault("notes", []).append(n)
        save()
        return f"Note \"{title or text[:30]}\" saved in Notes.", False

    # ---- desktop widgets (shell/widgets/Widgets.qml shows them)
    def t_widget(self, action, name="", size="small", qml=""):
        wdir = CONF / "widgets"
        layout_file = CONF / "widgets.json"
        try:
            layout = json.loads(layout_file.read_text())
        except (OSError, ValueError):
            layout = None   # the shell writes its defaults on first start
        mine = [o for o in (layout or []) if o.get("type") == "custom"]
        if action == "list":
            return "\n".join(f"{o.get('file')} ({o.get('size', 'small')})" for o in mine) or "No widgets of your own yet.", False
        name = re.sub(r"[^a-z0-9-]+", "-", (name or "").lower()).strip("-")[:40]
        if not name:
            return "Give the widget a name (letters, digits, dashes).", True
        f = wdir / f"{name}.qml"
        if action == "show":
            return (f.read_text() if f.exists() else f"No widget called {name}."), not f.exists()
        if action == "check":
            if not f.exists():
                return f"No widget called {name}.", True
            entry = next((o for o in (layout or []) if o.get("type") == "custom" and o.get("file") == name), {})
            return self.widget_check(f, entry.get("size", size))
        if action == "remove":
            if layout is not None:
                layout_file.write_text(json.dumps([o for o in layout if not (o.get("type") == "custom" and o.get("file") == name)], indent=1) + "\n")
            for p in (f, wdir / f"{name}.status"):
                p.unlink(missing_ok=True)
            return f"Removed the {name} widget.", False
        if not qml.strip():
            return "Write the widget's QML in `qml`.", True
        # A widget that runs commands does so by itself at every login: the
        # person sees them first (the same widget again, unchanged, isn't asked twice).
        if re.search(r"\b(Process|execDetached|FileView|XMLHttpRequest|openUrlExternally|Socket)\b", qml) and not (f.exists() and f.read_text() == qml):
            cmds = [" ".join(c.split())[:300] for c in re.findall(r"command\s*:\s*(\[.*?\])", qml, re.S) + re.findall(r"execDetached\s*\((.*?)\)", qml, re.S)]
            level = "critical" if any(classify_command(c)[0] == "critical" for c in cmds) else "risky"
            if not self.ui.confirm(level, f"Put the {name} widget on the desktop?", "\n".join(cmds) or "(it builds its commands while it runs)",
                                   "It runs these by itself whenever the desktop is on."):
                return "The person declined this widget.", True
        wdir.mkdir(parents=True, exist_ok=True)
        st = wdir / f"{name}.status"
        before = st.stat().st_mtime if st.exists() else 0
        f.write_text(qml)
        size = size if size in ("small", "medium", "large") else "small"
        if layout is None:
            layout = [{"type": "weather", "size": "medium", "x": 24, "y": 48}, {"type": "clock", "size": "small", "x": 24, "y": 232},
                      {"type": "calendar", "size": "small", "x": 208, "y": 232}, {"type": "music", "size": "medium", "x": 24, "y": 416}]
        entry = next((o for o in layout if o.get("type") == "custom" and o.get("file") == name), None)
        if entry is None:
            layout.append({"type": "custom", "file": name, "size": size})   # the desktop finds it a free spot
        elif entry.get("size") != size:
            entry["size"] = size
        layout_file.write_text(json.dumps(layout, indent=1) + "\n")
        # The desktop loads it and writes NAME.status: "ok", or "error" and why.
        for _ in range(30):
            time.sleep(0.2)
            if st.exists() and st.stat().st_mtime > before:
                break
        if not (st.exists() and st.stat().st_mtime > before):
            return f"Saved {f}. The desktop has not reported back yet; it is probably there already. Do not debug it with commands: tell the person.", False
        result = st.read_text().strip()
        # "No such file" / "case mismatch": the desktop looked at its copy while it was
        # still being made. Not the widget's fault: write it once more and look again.
        if result.startswith("error") and re.search(r"No such file|case mismatch", result):
            before = st.stat().st_mtime
            time.sleep(1.0)
            f.write_text(qml + "\n")
            for _ in range(30):
                time.sleep(0.2)
                if st.stat().st_mtime > before:
                    break
            result = st.read_text().strip()
        if result.startswith("error"):
            return f"The widget did not load. Fix the QML and create it again:\n{result.partition(chr(10))[2].strip()}", True
        # Loaded: now how it actually looks once its data is in.
        report, bad = self.widget_check(f, size)
        if isinstance(report, list):
            report[0]["text"] = f"The {name} widget is on the desktop ({size}).\n" + report[0]["text"]
            return report, bad
        return f"The {name} widget is on the desktop ({size}).\n{report}", bad

    # A widget drawn off screen (ai/widget-check.qml), given a few seconds for its
    # data, then described: every text and where it is, overlaps, things cut off
    # or outside the card, pictures that didn't load, and the QML warnings
    # (TypeError on line 12…). Works for models that can't see pictures; the
    # picture goes along for those that can.
    def widget_check(self, f, size="small"):
        check = Path(__file__).with_name("widget-check.qml")
        if not check.exists() or not shutil.which("qs"):
            return "Couldn't check it here; look at it with a screenshot.", False
        tmp = Path(tempfile.mkdtemp(prefix="memora-widget-"))
        try:
            w = tmp / "widget.qml"
            w.write_text(f.read_text())
            out = CONF.parent.parent / ".cache/memora/widgets" / f"{f.stem}-check.png"
            out.parent.mkdir(parents=True, exist_ok=True)
            dark = "1"
            try:
                dark = "0" if (CONF / "theme").read_text().strip() == "light" else "1"
            except OSError:
                pass
            accent = {"blue": "#3d8bff", "purple": "#a565f5", "pink": "#f2609e", "red": "#ff5f57", "orange": "#ff9f0a", "green": "#30d158", "graphite": "#8e8e93"}
            try:
                accent = accent.get(json.loads((CONF / "shell.json").read_text()).get("accent", "blue"), "#3d8bff")
            except (OSError, ValueError, AttributeError):
                accent = "#3d8bff"
            env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "W": str(w), "SIZE": size if size in ("small", "medium", "large") else "small",
                   "DARK": dark, "ACCENT": accent, "OUT": str(out), "WAIT": "7000", "QT_QUICK_BACKEND": "software"}
            try:
                r = subprocess.run(["qs", "-p", str(check)], capture_output=True, text=True, timeout=30, env=env, cwd=str(tmp))
                log = (r.stdout or "") + (r.stderr or "")
            except subprocess.TimeoutExpired as e:
                log = (e.stdout or "") + (e.stderr or "") if isinstance(e.stdout, str) else ""
        finally:
            pass
        log = re.sub(r"\x1b\[[0-9;]*m", "", log)
        lines, warns = [], []
        for l in log.splitlines():
            if "@" in l and "qml:" in l:
                lines.append(l.split("qml:", 1)[1].strip().lstrip("@"))
            elif str(w) in l:
                m = re.search(re.escape(str(w)) + r"\[(\d+):?(-?\d+)?\]:?\s*(.*)", l)
                warns.append(f"line {m.group(1)}: {m.group(3)}" if m else l.split(str(w))[-1].strip(": "))
        shutil.rmtree(tmp, ignore_errors=True)
        # The check itself didn't run (it never reached "done"): that says nothing
        # about the widget, which already loaded on the desktop. Say so plainly, so
        # the model finishes instead of trying to build its own checker.
        if not any(l.startswith("done") or l.startswith("error") for l in lines):
            return ("The off-screen check could not run on this computer, so the widget could not be inspected. "
                    "That is not a problem with the widget: it loaded on the desktop without errors. "
                    "Finish now and tell the person it is on their desktop. Do not run commands, write test files "
                    "or try to check it another way."), False
        problems = [l for l in lines if re.search(r"CUT OFF|OUTSIDE|BROKEN|STILL WAITING|DID NOT LOAD|overlap |^empty|^error|no size|invisible", l)]
        text = "How it looks after 7 seconds (positions inside the card's content area):\n" + "\n".join("- " + l for l in lines if l != "done")
        if warns:
            text += "\n\nQML warnings (errors while it runs; fix these first):\n" + "\n".join("- " + w_ for w_ in dict.fromkeys(warns))
        if problems or warns:
            text += "\n\nNot right yet: fix the problems above and create it again."
        else:
            text += "\n\nNo problems found."
        bad = bool(problems or warns)
        # Don't let it chase the checker in circles: after a few rounds the widget
        # is on the desktop as it is, and the person is told what is left.
        tries = self.widget_tries = getattr(self, "widget_tries", {})
        tries[f.stem] = tries.get(f.stem, 0) + 1
        if bad and tries[f.stem] >= 4:
            text += ("\n\nSTOP fixing this. The widget is already on the desktop. Do not run commands, edit widgets.json, "
                     "write test files or start qs yourself: only the widget tool changes widgets. Tell the person it is there "
                     "and, in one short sentence, what is still not perfect.")
            bad = False
        if self.vision and out.exists():
            import base64 as b64
            return [{"type": "text", "text": text}, {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": b64.b64encode(out.read_bytes()).decode()}}], bad
        return text, bad

    # ---- the computer
    def t_power(self, action):
        if action == "lock":
            r = sh(["memora-lock"])
        elif action == "sleep":
            r = sh(["systemctl", "suspend"])
        else:
            r = sh(["memora-power", action])
        return ("Done." if r.returncode == 0 else f"Failed: {r.stderr.strip()}"), r.returncode != 0

    def t_system_info(self, what):
        parts = {
            "battery": "upower -i $(upower -e | grep -m1 BAT) 2>/dev/null | grep -E 'state|percentage|time to|energy-full:|capacity' || echo 'No battery (mains power).'",
            "network": "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device; echo; nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi 2>/dev/null | grep '^yes' ; ip -brief addr | grep -v '^lo'",
            "storage": "df -h -x tmpfs -x devtmpfs -x efivarfs --output=target,size,used,avail,pcent",
            "memory": "free -h",
            "cpu": "lscpu | grep -E 'Model name|^CPU\\(s\\)|MHz'; uptime; cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -3 | awk '{printf \"temp %.0f°C\\n\", $1/1000}'",
            "processes": "ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -12",
            "displays": "hyprctl -j monitors | jq -r '.[] | \"\\(.name): \\(.width)x\\(.height)@\\(.refreshRate|floor)Hz scale \\(.scale)\"'",
            "audio": "wpctl status | sed -n '/Audio/,/Video/p' | head -40",
        }
        keys = list(parts) if what == "all" else [what]
        out = []
        for k in keys:
            r = sh(["bash", "-c", parts[k]], timeout=15)
            out.append(f"## {k}\n{r.stdout.strip()}")
        return clip("\n\n".join(out)), False

    def t_weather(self, place=""):
        def get(u):
            with urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "MemoraAI"}), timeout=10) as r:
                return json.loads(r.read())
        import urllib.parse
        if place:
            g = get("https://geocoding-api.open-meteo.com/v1/search?count=1&name=" + urllib.parse.quote(place)).get("results") or []
            if not g:
                return f"Don't know a place called {place}.", True
            lat, lon, name = g[0]["latitude"], g[0]["longitude"], f"{g[0]['name']}, {g[0].get('country', '')}"
        else:
            r = sh(["memora-location"], timeout=25)
            loc = json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else get("https://ipapi.co/json/")
            lat, lon, name = loc["latitude"], loc["longitude"], loc.get("city", "here")
        f = get(f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,precipitation"
                "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code&timezone=auto&forecast_days=4")
        codes = {0: "clear", 1: "mostly clear", 2: "partly cloudy", 3: "cloudy", 45: "fog", 48: "fog", 51: "drizzle", 53: "drizzle", 55: "drizzle",
                 61: "light rain", 63: "rain", 65: "heavy rain", 71: "light snow", 73: "snow", 75: "heavy snow", 80: "showers", 81: "showers",
                 82: "heavy showers", 95: "thunderstorm", 96: "thunderstorm", 99: "thunderstorm"}
        c, d = f["current"], f["daily"]
        out = [f"{name}: now {c['temperature_2m']}°C (feels {c['apparent_temperature']}°C), {codes.get(c['weather_code'], 'code ' + str(c['weather_code']))}, wind {c['wind_speed_10m']} km/h"]
        for i in range(len(d["time"])):
            out.append(f"{d['time'][i]}: {d['temperature_2m_min'][i]}–{d['temperature_2m_max'][i]}°C, {codes.get(d['weather_code'][i], '?')}, rain chance {d['precipitation_probability_max'][i]}%")
        return "\n".join(out), False

    def t_skill(self, name):
        sk = skills()
        if name not in sk:
            return f"No guide called '{name}'. Guides: {', '.join(sk)}.", True
        return sk[name][1], False

    def t_scroll(self, x, y, direction, amount=3):
        sx, sy = SCREEN.to_screen(x, y)
        sh(["hyprctl", "dispatch", f"hl.dsp.cursor.move({{ x = {sx}, y = {sy} }})"])
        n = max(1, min(int(amount or 3), 30))
        dx, dy = {"up": (0, n), "down": (0, -n), "left": (-n, 0), "right": (n, 0)}[direction]
        r = sh(["ydotool", "mousemove", "--wheel", "-x", str(dx), "-y", str(dy)], env={**os.environ, **YDO})
        return ("Scrolled." if r.returncode == 0 else f"Failed: {r.stderr.strip()}"), r.returncode != 0

    def t_notify(self, title, body=""):
        sh(["notify-send", "-a", "Memora AI", title, body])
        return "Shown.", False

    def t_remember(self, fact):
        DATA.mkdir(parents=True, exist_ok=True)
        fact = " ".join(fact.split())
        old = MEMORY.read_text() if MEMORY.exists() else ""
        if fact.lower() in old.lower():
            return "Already in memory.", False
        with open(MEMORY, "a") as f:
            f.write(f"- {fact} ({time.strftime('%Y-%m-%d')})\n")
        return "Saved to memory.", False

    def t_forget(self, text):
        if not MEMORY.exists() or not text.strip():
            return "Nothing like that is saved.", True
        lines = MEMORY.read_text().splitlines(keepends=True)
        keep = [l for l in lines if text.lower() not in l.lower()]
        if len(keep) == len(lines):
            return "Nothing like that is saved.", True
        MEMORY.write_text("".join(keep))
        return f"Forgot {len(lines) - len(keep)} saved fact{'s' if len(lines) - len(keep) > 1 else ''}.", False

    def t_past_chats(self, action, query="", id=""):
        chats = DATA / "chats"
        files = sorted(chats.glob("*.json"), reverse=True) if chats.exists() else []

        def turns(f):
            """(role, text) of the words said, without tool results and pictures."""
            try:
                msgs = json.loads(f.read_text())
            except (OSError, ValueError):
                return []
            out = []
            for m in msgs:
                c = m.get("content")
                if isinstance(c, list):
                    c = "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
                c = re.sub(r"\n*\[Now: [^\]]*\]\s*$", "", c or "").strip()
                if c:
                    out.append((m.get("role"), c))
            return out

        def when(f):
            try:
                return datetime.strptime(f.stem, "%Y-%m-%d-%H%M%S").strftime("%a %d %b %Y %H:%M")
            except ValueError:
                return f.stem
        current = getattr(self, "chat_id", None)
        files = [f for f in files if f.stem != current]
        if action == "read":
            f = chats / f"{re.sub(r'[^0-9-]', '', id)}.json"
            t = turns(f) if f.exists() else []
            if not t:
                return "No conversation with that id (see list).", True
            return clip("\n\n".join(f"{'Person' if r == 'user' else 'You'}: {c}" for r, c in t), 30000), False
        rows = []
        for f in files:
            t = turns(f)
            if not t:
                continue
            first = next((c for r, c in t if r == "user"), "")
            if action == "search":
                hits = [c for r, c in t if query.lower() in c.lower()]
                if not hits:
                    continue
                i = hits[0].lower().index(query.lower())
                first = "…" + hits[0][max(0, i - 80):i + 120].replace("\n", " ") + "…"
            rows.append(f"{f.stem}  {when(f)}  {first[:200].replace(chr(10), ' ')}")
            if len(rows) >= 25:
                break
        return "\n".join(rows) or ("Nothing found in earlier conversations." if action == "search" else "No earlier conversations."), False


def active_ws():
    try:
        return json.loads(sh(["hyprctl", "-j", "activeworkspace"]).stdout)["id"]
    except (ValueError, KeyError, OSError):
        return 1


def describe(name, data):
    """One short line about a tool call, for the window."""
    return {
        "run_command": lambda d: d.get("command", ""),
        "read_file": lambda d: "Reading " + d.get("path", ""),
        "write_file": lambda d: "Writing " + d.get("path", ""),
        "edit_file": lambda d: "Editing " + d.get("path", ""),
        "trash": lambda d: {"move": "Moving to the Trash: " + ", ".join(Path(x).name for x in (d.get("paths") or [d.get("path", "")])),
                            "list": "Looking in the Trash", "restore": "Restoring " + d.get("path", ""), "empty": "Emptying the Trash"}.get(d.get("action"), "Trash"),
        "forget": lambda d: "Forgetting: " + d.get("text", "")[:60],
        "past_chats": lambda d: {"search": "Looking through earlier chats for " + d.get("query", ""), "read": "Reading an earlier chat"}.get(d.get("action"), "Looking at earlier chats"),
        "list_directory": lambda d: "Looking in " + d.get("path", ""),
        "open": lambda d: "Opening " + d.get("target", ""),
        "system_setting": lambda d: f"{d.get('setting', '').replace('_', ' ').capitalize()}: {d.get('value', '')}",
        "windows": lambda d: f"Windows: {d.get('action', '')} {d.get('window', '')}".strip(),
        "screenshot": lambda d: "Looking at the screen",
        "click": lambda d: f"Clicking at {d.get('x')},{d.get('y')}",
        "type_text": lambda d: "Typing " + d.get("text", "")[:40],
        "press_keys": lambda d: "Pressing " + d.get("keys", ""),
        "scroll": lambda d: "Scrolling " + d.get("direction", ""),
        "notify": lambda d: "Notification: " + d.get("title", ""),
        "remember": lambda d: "Remembering: " + d.get("fact", "")[:60],
        "browse": lambda d: "Opening " + (d.get("url") or "a search for " + d.get("search", "")),
        "wait_for_window": lambda d: "Waiting for " + d.get("app", ""),
        "arrange_window": lambda d: f"Placing {d.get('window') or 'the window'}: {d.get('zone', '')}",
        "desktops": lambda d: f"Desktop {d.get('number')}",
        "clipboard": lambda d: {"get": "Reading the clipboard", "selection": "Reading the selected text"}.get(d.get("action"), "Copying to the clipboard"),
        "media": lambda d: "Media: " + d.get("action", ""),
        "apps": lambda d: f"Apps: {d.get('action', '')} {d.get('query') or d.get('id') or ''}".strip(),
        "find_files": lambda d: "Looking for " + (d.get("name") or d.get("text") or "files"),
        "reminder": lambda d: "Reminder: " + (d.get("text") or d.get("action", "")),
        "calendar": lambda d: {"add": "Adding to Calendar: ", "remove": "Removing from Calendar", "list": "Looking at the calendar", "calendars": "Looking at the calendars"}.get(d.get("action"), "Calendar") + (d.get("title") or ""),
        "notes": lambda d: "Notes: " + (d.get("title") or d.get("query") or d.get("action", "")),
        "widget": lambda d: {"create": "Making the widget ", "remove": "Removing the widget ", "list": "Looking at widgets", "show": "Reading the widget ", "check": "Checking the widget "}.get(d.get("action"), "Widget ") + (d.get("name") or ""),
        "power": lambda d: d.get("action", "").capitalize(),
        "system_info": lambda d: "Checking " + d.get("what", "the computer"),
        "download": lambda d: "Downloading " + d.get("url", ""),
        "fetch_url": lambda d: "Reading " + d.get("url", ""),
        "weather": lambda d: "Weather " + (d.get("place") or "here"),
        "skill": lambda d: "Reading the guide: " + d.get("name", ""),
        "web_search": lambda d: "Searching the web: " + str(d.get("query", "")),
        "web_fetch": lambda d: "Reading " + str(d.get("url", "")),
    }.get(name, lambda d: name)(data or {})


def effort_of(cfg):
    e = (cfg.get("effort") or DEFAULT_EFFORT).lower()
    return e if e in EFFORTS else DEFAULT_EFFORT


def describe_cc(name, data):
    """A line for a Claude Code tool call in the chat."""
    if name == "Bash":
        cmd = data.get("command", "")
        m = re.match(r"\s*memora-ai\s+tool\s+(\w+)\s+'(.*)'\s*$", cmd, re.S)
        if m:
            try:
                return describe(m.group(1), json.loads(m.group(2)))
            except ValueError:
                pass
        return data.get("description") or ("Running " + cmd[:70])
    path = (data.get("file_path") or data.get("path") or "").replace(str(HOME), "~")
    return {"Read": f"Reading {path}", "Write": f"Writing {path}", "Edit": f"Editing {path}", "MultiEdit": f"Editing {path}",
            "Glob": f"Looking for {data.get('pattern', 'files')}", "Grep": f"Searching for {data.get('pattern', '')}",
            "WebSearch": f"Searching the web for {data.get('query', '')}", "WebFetch": f"Reading {data.get('url', 'a page')}",
            "TodoWrite": "Planning"}.get(name, name)


class PermitServer:
    """A Unix socket for permit.py (Claude Code's permission prompts) and for
    `memora-ai tool` run by Claude Code (its confirmations and hands)."""

    def __init__(self, agent):
        import socket
        self.agent = agent
        run = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
        self.path = os.path.join(run, f"memora-ai-{os.getpid()}.sock")
        try:
            os.unlink(self.path)
        except OSError:
            pass
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        old = os.umask(0o177)
        try:
            self.sock.bind(self.path)
        finally:
            os.umask(old)
        self.sock.listen(8)
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        while True:
            conn, _ = self.sock.accept()
            threading.Thread(target=self.handle, args=(conn,), daemon=True).start()

    def handle(self, conn):
        with conn:
            data = b""
            while not data.endswith(b"\n"):
                chunk = conn.recv(65536)
                if not chunk:
                    break
                data += chunk
            try:
                req = json.loads(data or b"{}")
            except ValueError:
                return
            ui = self.agent.ui
            try:
                if req.get("kind") == "confirm":
                    out = {"ok": bool(ui.confirm(req.get("level", "risky"), req.get("title", ""), req.get("detail", ""), req.get("why", "")))}
                elif req.get("kind") == "hands":
                    getattr(ui, "hands", lambda on: None)(bool(req.get("on")))
                    out = {}
                else:
                    out = self.agent.cc_permit(req)
            except Exception as e:  # never leave Claude Code waiting
                out = {"behavior": "deny", "message": f"{type(e).__name__}: {e}"} if "kind" not in req else {"ok": False}
            try:
                conn.sendall((json.dumps(out) + "\n").encode())
            except OSError:
                pass


class BridgeUI:
    """For `memora-ai tool` run by Claude Code: confirmations and folding the
    chat go to the Memora AI window through its socket; the rest is quiet."""

    def __init__(self):
        self.path = os.environ.get("MEMORA_AI_PERMIT", "")

    def ask(self, req):
        import socket
        if not self.path:
            return {}
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.connect(self.path)
                s.sendall((json.dumps(req) + "\n").encode())
                data = b""
                while not data.endswith(b"\n"):
                    chunk = s.recv(65536)
                    if not chunk:
                        break
                    data += chunk
            return json.loads(data or b"{}")
        except (OSError, ValueError):
            return {}

    def confirm(self, level, title, detail, why):
        if not self.path:
            return TerminalUI().confirm(level, title, detail, why)
        return bool(self.ask({"kind": "confirm", "level": level, "title": title, "detail": detail, "why": why}).get("ok"))

    def hands(self, on):
        self.ask({"kind": "hands", "on": on})

    def stopped(self):
        return False

    def text(self, t):
        pass

    def status(self, s):
        pass

    def tool_start(self, name, summary):
        return 0

    def tool_end(self, tid, ok):
        pass

    def error(self, msg):
        sys.stderr.write(msg + "\n")


# ------------------------------------------------------------- providers ----
class Agent:
    def __init__(self, ui):
        self.ui = ui
        self.cfg = load_config()
        self.messages = []
        self.started = time.strftime("%Y-%m-%d-%H%M%S")
        self.tools = Tools(ui)
        self.cc_session = None     # Claude Code: this conversation's session (resumed every turn)
        self.cc_started = False
        self.permit = None         # the socket Claude Code's permission prompts come through

    def tool_specs(self):
        """Screen tools only when the person allows it (System Settings > Privacy & Security)."""
        try:
            self.cfg.update(json.loads((CONF / "ai.json").read_text()))
        except Exception:
            pass
        if self.cfg.get("screenControl", True):
            return TOOLS
        return [t for t in TOOLS if t["name"] not in SCREEN_TOOLS]

    def reset(self):
        self.messages = []
        self.started = time.strftime("%Y-%m-%d-%H%M%S")
        self.cc_session = None
        self.cc_started = False

    def turn(self, text, files=()):
        self.cfg = load_config()
        self.tools.hands_on = False
        provider = self.cfg.get("provider") or "anthropic"
        self.tools.vision = provider in ("anthropic", "claude-code")
        files = [f for f in files if isinstance(f, str) and os.path.isfile(f)]
        # Attached files: Claude sees pictures and PDFs; the others get the text
        # of text files and the paths of the rest (they can open them with tools).
        blocks, note = attachments(files, images=provider == "anthropic")
        self.tools.chat_id = self.started
        # The time and the screen as the message is sent (kept with it, so the
        # conversation before it never changes and stays cached).
        now = "" if provider == "claude-code" else "\n\n" + now_context()
        if blocks:
            self.messages.append({"role": "user", "content": blocks + [{"type": "text", "text": (text or "What is this?") + note + now}]})
        else:
            self.messages.append({"role": "user", "content": (text or ("What is this?" if files else "")) + note + now})
        try:
            if provider == "anthropic":
                self.claude_turn()
            elif provider == "deepseek":
                self.claude_turn(deepseek=True)
            elif provider == "claude-code":
                # Claude Code reads them itself (its Read tool sees pictures and PDFs).
                paths = "".join(f"\n- {f}" for f in files)
                self.claude_code_turn((text or "What is this?") + (f"\n\nAttached files (read them):{paths}" if files else ""))
            else:
                self.openai_turn(provider)
        except Exception as e:  # shown in the window, not a crash
            self.ui.error(friendly_error(e))

    # Claude, with tools. A manual streaming loop: text appears as it is
    # written, and each tool call can stop for the person's OK.
    # DeepSeek speaks the same protocol (its Anthropic-compatible endpoint), so
    # it gets the same tools and confirmations; it has no server tools (web
    # search) and no adaptive thinking.
    def claude_turn(self, deepseek=False):
        import anthropic
        if deepseek:
            key = os.environ.get("DEEPSEEK_API_KEY")
            if not key:
                raise RuntimeError("No DeepSeek API key yet. Add one in System Settings > Memora AI.")
            client = anthropic.Anthropic(api_key=key, base_url=os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com/anthropic"),
                                         timeout=180, max_retries=2)
            # A Claude model left over from before the switch isn't DeepSeek's.
            model = self.cfg.get("model") or "deepseek-chat"
            if not model.startswith("deepseek"):
                model = "deepseek-chat"
            tools = [{k: v for k, v in t.items() if k != "eager_input_streaming"} for t in self.tool_specs() + [FETCH_TOOL]]
            extra = {"max_tokens": 8000}
        else:
            key = os.environ.get("ANTHROPIC_API_KEY")
            if not key:
                raise RuntimeError("No Anthropic API key yet. Add one in System Settings > Memora AI.")
            client = anthropic.Anthropic(api_key=key, timeout=600, max_retries=2)
            model = self.cfg.get("model") or DEFAULT_MODEL
            if not model.startswith("claude"):
                model = DEFAULT_MODEL
            tools = self.tool_specs() + SERVER_TOOLS
            extra = {"max_tokens": 32000, "thinking": {"type": "adaptive"},
                     "output_config": {"effort": effort_of(self.cfg)}}
        # The system prompt stays the same for the whole chat (the time and the
        # screen come with each message), so it and the conversation so far are
        # read from the cache: the answer starts sooner and costs a tenth.
        system = system_prompt(with_now=False)
        if not deepseek:
            system = [{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}]
        betas, body = [], {}
        if not deepseek and not getattr(self, "lean", False):
            body["cache_control"] = {"type": "ephemeral"}            # the newest message too
            # A long chat (many screenshots, long files) is summarised by the
            # server instead of stopping when it no longer fits.
            betas.append("compact-2026-01-12")
            body["context_management"] = {"edits": [{"type": "compact_20260112"}]}
            # A request a model declines is answered by another one, not dropped.
            if model in ("claude-fable-5-2", "claude-opus-5-5", "claude-sonnet-5-5"):
                betas.append("server-side-fallback-2026-07-01")
                body["fallbacks"] = "default"
        retries = 0
        while not self.ui.stopped():
            api = client.beta.messages if betas else client.messages
            more = {"betas": betas, "extra_body": body} if betas else ({"extra_body": body} if body else {})
            try:
                with api.stream(
                    model=model,
                    system=system,
                    tools=tools,
                    messages=recent_pictures(self.messages),
                    **extra, **more,
                ) as stream, self.closing_on_stop(stream):
                    for event in stream:
                        if self.ui.stopped():
                            break
                        if event.type == "text":
                            self.ui.text(event.text)
                        elif event.type == "content_block_start":
                            b = event.content_block
                            if b.type == "thinking":
                                self.ui.status("Thinking…")
                            elif b.type == "compaction":
                                self.ui.status("Summing up the conversation so far…")
                            elif b.type == "server_tool_use":
                                self.ui.status(describe(b.name, getattr(b, "input", {}) or {}))
                    if self.ui.stopped():
                        return
                    msg = stream.get_final_message()
                retries = 0
            except ValueError:
                retries += 1
                if retries > 2:
                    raise
                continue
            except Exception as e:
                # The connection closed by Stop: not an error.
                if self.ui.stopped():
                    return
                # An account or SDK that doesn't take the newer options (compaction,
                # fallbacks): ask again the plain way, and keep to it from now on.
                if type(e).__name__ in ("BadRequestError", "TypeError") and betas and re.search(r"context_management|compact|fallback|beta|cache_control", str(e)):
                    self.lean, betas, body = True, [], {}
                    continue
                raise

            self.messages.append({"role": "assistant", "content": msg.content})
            if msg.stop_reason == "pause_turn":
                continue
            uses = [b for b in msg.content if b.type == "tool_use"]
            if msg.stop_reason == "refusal" or not uses:
                self.save()
                return
            if msg.stop_reason == "max_tokens":
                self.messages.pop()
                raise RuntimeError("The answer was too long and got cut off. Try asking for less at once.")

            results = []
            for b in uses:
                problem = check_input(b.name, b.input)
                if problem:
                    results.append({"type": "tool_result", "tool_use_id": b.id, "is_error": True,
                                    "content": json.dumps({"INVALID_INPUT": problem})})
                    continue
                tid = self.ui.tool_start(b.name, describe(b.name, b.input))
                try:
                    if b.name in SCREEN_TOOLS and not self.cfg.get("screenControl", True):
                        content, err = "The person turned off screen control (System Settings > Privacy & Security).", True
                    else:
                        content, err = self.tools.run(b.name, b.input)
                except Exception as e:
                    content, err = f"{type(e).__name__}: {e}", True
                self.ui.tool_end(tid, not err)
                results.append({"type": "tool_result", "tool_use_id": b.id, "content": content, "is_error": bool(err)})
            self.messages.append({"role": "user", "content": results})
            self.save()   # after every round, so a chat that gets stuck is on disk too

    # Stop, pressed while an answer is streaming in: close the connection, so it
    # ends now instead of when the next piece arrives (or a long think is over).
    @contextlib.contextmanager
    def closing_on_stop(self, stream):
        done = threading.Event()

        def watch():
            while not done.wait(0.2):
                if self.ui.stopped():
                    try:
                        stream.close()
                    except Exception:
                        pass
                    return
        threading.Thread(target=watch, daemon=True).start()
        try:
            yield
        finally:
            done.set()

    # Claude Code answers with its own tools. One Claude Code session per
    # conversation (--session-id, then --resume), so it remembers what was said;
    # what would need permission comes to the window (permit.py -> PermitServer).
    def claude_code_turn(self, text):
        if not shutil.which("claude"):
            raise RuntimeError("Claude Code is not installed. Get it from the App Store (AI section).")
        if not self.permit:
            self.permit = PermitServer(self)
        if not self.cc_session:
            self.cc_session, self.cc_started = str(uuid.uuid4()), False
        mcp = {"mcpServers": {"memora": {"command": sys.executable, "args": [str(Path(__file__).with_name("permit.py"))],
                                         "env": {"MEMORA_AI_PERMIT": self.permit.path}}}}
        args = ["claude", "-p", "--output-format", "stream-json", "--verbose",
                "--append-system-prompt", system_prompt(claude_code=True),
                "--mcp-config", json.dumps(mcp),
                "--permission-prompt-tool", "mcp__memora__approve",
                "--disallowedTools", "AskUserQuestion",
                "--effort", effort_of(self.cfg)]
        if self.cfg.get("model"):
            args += ["--model", self.cfg["model"]]
        args += ["--resume", self.cc_session] if self.cc_started else ["--session-id", self.cc_session]
        p = subprocess.Popen(args + ["--", text], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=HOME,
                             env={**with_sudo(), "MEMORA_AI_PERMIT": self.permit.path})
        answer, tids = "", {}
        for line in p.stdout:
            if self.ui.stopped():
                p.terminate()
                return
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            kind = ev.get("type")
            if kind == "system" and ev.get("session_id"):
                self.cc_session, self.cc_started = ev["session_id"], True
            elif kind == "assistant":
                for c in ev.get("message", {}).get("content", []):
                    if c.get("type") == "text":
                        if c["text"].strip().lower().startswith("not logged in"):
                            p.terminate()
                            raise RuntimeError("Claude Code isn't signed in yet. Open System Settings > Memora AI and click Sign In.")
                        if answer and not answer.endswith("\n"):
                            self.ui.text("\n\n")
                            answer += "\n\n"
                        self.ui.text(c["text"])
                        answer += c["text"]
                    elif c.get("type") == "tool_use":
                        name = c.get("name", "")
                        tids[c.get("id")] = self.ui.tool_start(name, describe_cc(name, c.get("input", {})))
                    elif c.get("type") == "thinking":
                        self.ui.status("Thinking…")
            elif kind == "user":
                # Tool results: mark the tool done (or failed).
                for c in ev.get("message", {}).get("content", []) if isinstance(ev.get("message", {}).get("content"), list) else []:
                    if c.get("type") == "tool_result" and c.get("tool_use_id") in tids:
                        self.ui.tool_end(tids.pop(c["tool_use_id"]), not c.get("is_error"))
        for tid in tids.values():
            self.ui.tool_end(tid, True)
        p.wait()
        err = (p.stderr.read() or "").strip()
        if p.returncode != 0 and not answer:
            if self.cc_started and "No conversation found" in err:
                # The session is gone (Claude Code cleaned it up): start a new one.
                self.cc_session = None
                return self.claude_code_turn(text)
            lines = err.splitlines()
            msg = lines[-1] if lines else f"Claude Code stopped (code {p.returncode})."
            if "login" in msg.lower() or "auth" in msg.lower() or "api key" in msg.lower():
                msg = "Claude Code isn't signed in yet. Open System Settings > Memora AI and click Sign In."
            raise RuntimeError(msg)
        self.cc_started = True
        self.messages.append({"role": "assistant", "content": answer or "(no answer)"})
        self.save()

    def cc_permit(self, req):
        """Claude Code asks whether a tool may run. Answers like this agent's own
        tools: safe things run, risky ones wait for the person's OK."""
        name, inp = req.get("tool_name", ""), req.get("input") or {}
        allow = lambda i=inp: {"behavior": "allow", "updatedInput": i}
        deny = lambda why: {"behavior": "deny", "message": why}
        if name == "AskUserQuestion":
            qs = inp.get("questions") or []
            lines = []
            for q in qs:
                lines.append(f"**{q.get('question', '')}**")
                for o in q.get("options") or []:
                    lines.append(f"- {o.get('label', '')}" + (f" \u2014 {o['description']}" if o.get("description") else ""))
            if lines:
                self.ui.text("\n\n" + "\n".join(lines) + "\n")
            return deny("The questions are now shown to the person in the chat. End your turn without doing anything else; they will answer in their next message.")
        if name == "Bash":
            cmd = inp.get("command", "")
            level, why = classify_command(cmd)
            if level == "safe":
                return allow(inp)
            reason = (req.get("input") or {}).get("description", "").strip()
            if reason and reason[-1] not in ".!?":
                reason += "."
            ok = self.ui.confirm(level, "Run this command?", cmd, (reason + " " if reason else "") + f"It {why}.")
            return allow(inp) if ok else deny("The person declined to run this command.")
        if name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
            path = inp.get("file_path") or inp.get("notebook_path") or ""
            exists = os.path.exists(path)
            level, why = classify_path_write(path, exists)
            if level == "safe":        # a new file in the home folder
                return allow(inp)
            if name == "Write":
                preview = (inp.get("content") or "")[:600]
            else:
                edits = inp.get("edits") or [inp]
                preview = "\n".join(f"- {e.get('old_string', '')[:200]}\n+ {e.get('new_string', '')[:200]}" for e in edits[:3])
            title = ("Change " if exists else "Create ") + (path.replace(str(HOME), "~") or "a file") + "?"
            ok = self.ui.confirm("critical" if level == "critical" else "risky", title, preview, why if why else "")
            return allow(inp) if ok else deny("The person declined this change.")
        if name == "Read":
            path = inp.get("file_path") or ""
            level, why = classify_path_read(path)
            if level != "safe" and not self.ui.confirm(level, f"Read {path.replace(str(HOME), '~')}?", "", f"This file {why}."):
                return deny("The person declined to share this file.")
            return allow(inp)
        if name in ("Glob", "Grep", "LS", "WebSearch", "WebFetch", "TodoWrite", "Task", "Agent", "ExitPlanMode", "ToolSearch", "Skill"):
            return allow(inp)
        ok = self.ui.confirm("risky", f"Allow {name}?", clip(json.dumps(inp, ensure_ascii=False, indent=1), 1200), "Memora AI wants to use this tool.")
        return allow(inp) if ok else deny("The person declined.")

    # Ollama and OpenAI-compatible servers, with the same tools and confirmations.
    # Ollama through its own API (/api/chat), which lets the context be big enough
    # for the tools; the others through /v1/chat/completions (function calling).
    # A model that can't use tools still answers, as a plain chat.
    def openai_turn(self, provider):
        native = provider == "ollama"
        base = (self.cfg.get("baseUrl") or ("http://localhost:11434" if native else "")).rstrip("/")
        if not base:
            raise RuntimeError("Set the server address in System Settings > Memora AI.")
        if native:
            base = re.sub(r"/v1$", "", base)
        model = self.cfg.get("model") or "qwen3:8b"
        no_tools = self.__dict__.setdefault("no_tools", set())
        specs = self.tool_specs() + [FETCH_TOOL]
        fns = [{"type": "function", "function": {"name": t["name"], "description": t["description"], "parameters": t["input_schema"]}} for t in specs]
        for _ in range(40):     # small models can go round in circles: a limit
            if self.ui.stopped():
                return
            msgs = [{"role": "system", "content": system_prompt(with_now=False)}] + chat_messages(self.messages, native)
            tools = None if model in no_tools else fns
            try:
                text, calls = (self.ollama_stream if native else self.oa_stream)(base, model, msgs, tools)
            except urllib.error.HTTPError as e:
                detail = e.read().decode("utf-8", "replace")[:500]
                if tools and e.code in (400, 404, 422, 500) and re.search(r"tool|function", detail, re.I):
                    no_tools.add(model)     # this model can't use tools: answer without them
                    continue
                if e.code == 404 and native and "not found" in detail:
                    raise RuntimeError(f"Ollama doesn't have the model {model} yet. Get it with: ollama pull {model}")
                if e.code in (401, 403):
                    raise RuntimeError("The server didn't accept the API key. Check it in System Settings > Memora AI.")
                raise RuntimeError(f"The AI server answered {e.code}: {detail.strip() or e.reason}")
            if self.ui.stopped():
                return
            content = ([{"type": "text", "text": text}] if text else []) + \
                      [{"type": "tool_use", "id": c["id"], "name": c["name"], "input": c["input"] if isinstance(c["input"], dict) else {}} for c in calls]
            self.messages.append({"role": "assistant", "content": content or ""})
            if not calls:
                self.save()
                return
            results = []
            for c in calls:
                problem = c["input"] if isinstance(c["input"], str) else check_input(c["name"], c["input"])
                if problem:
                    results.append({"type": "tool_result", "tool_use_id": c["id"], "is_error": True,
                                    "content": f"Invalid input for {c['name']}: {problem}. Call it again with valid JSON arguments."})
                    continue
                tid = self.ui.tool_start(c["name"], describe(c["name"], c["input"]))
                try:
                    if c["name"] in SCREEN_TOOLS and not self.cfg.get("screenControl", True):
                        out, err = "The person turned off screen control (System Settings > Privacy & Security).", True
                    else:
                        out, err = self.tools.run(c["name"], c["input"])
                except Exception as e:
                    out, err = f"{type(e).__name__}: {e}", True
                self.ui.tool_end(tid, not err)
                if isinstance(out, list):
                    out = "\n".join(b.get("text", "") for b in out if b.get("type") == "text")
                results.append({"type": "tool_result", "tool_use_id": c["id"], "content": out, "is_error": bool(err)})
            self.messages.append({"role": "user", "content": results})
            self.save()
            if text and not text.endswith("\n"):
                self.ui.text("\n\n")
        self.save()
        raise RuntimeError("Stopped after many steps without finishing. Ask again, maybe in smaller parts.")

    def oa_stream(self, base, model, msgs, tools):
        """/v1/chat/completions, streamed: (text, [{id, name, input}])."""
        body = {"model": model, "stream": True, "messages": msgs}
        if tools:
            body["tools"] = tools
        req = urllib.request.Request(base + "/chat/completions", data=json.dumps(body).encode(), headers={
            "Content-Type": "application/json", "Authorization": "Bearer " + os.environ.get("OPENAI_API_KEY", "none")})
        text, parts = "", {}
        with urllib.request.urlopen(req, timeout=300) as r:
            for raw in r:
                if self.ui.stopped():
                    break
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data: ") or line == "data: [DONE]":
                    continue
                try:
                    delta = json.loads(line[6:])["choices"][0].get("delta") or {}
                except (ValueError, KeyError, IndexError, TypeError):
                    continue
                if delta.get("reasoning_content") or delta.get("reasoning"):
                    self.ui.status("Thinking…")
                if delta.get("content"):
                    text += delta["content"]
                    self.ui.text(delta["content"])
                for tc in delta.get("tool_calls") or []:
                    p = parts.setdefault(tc.get("index", len(parts)), {"id": "", "name": "", "args": ""})
                    p["id"] = tc.get("id") or p["id"]
                    fn = tc.get("function") or {}
                    p["name"] += fn.get("name") or ""
                    p["args"] += fn.get("arguments") or ""
        calls = []
        for i in sorted(parts):
            p = parts[i]
            try:
                args = json.loads(p["args"] or "{}")
                if not isinstance(args, dict):
                    args = "the arguments are not a JSON object"
            except ValueError:
                args = "the arguments are not valid JSON"
            calls.append({"id": p["id"] or f"call_{uuid.uuid4().hex[:12]}", "name": p["name"], "input": args})
        return text, calls

    def ollama_stream(self, base, model, msgs, tools):
        """Ollama's /api/chat, streamed: (text, [{id, name, input}])."""
        body = {"model": model, "stream": True, "messages": msgs,
                # The tools and the system prompt alone are several thousand tokens:
                # Ollama's small default context would cut them off.
                "options": {"num_ctx": int(self.cfg.get("contextLength") or 16384)}}
        if tools:
            body["tools"] = tools
        req = urllib.request.Request(base + "/api/chat", data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
        text, calls = "", []
        self.ui.status("Loading the model…")
        with urllib.request.urlopen(req, timeout=600) as r:
            for raw in r:
                if self.ui.stopped():
                    break
                try:
                    j = json.loads(raw)
                except ValueError:
                    continue
                if j.get("error"):
                    raise RuntimeError(f"Ollama: {j['error']}")
                m = j.get("message") or {}
                if m.get("thinking"):
                    self.ui.status("Thinking…")
                if m.get("content"):
                    text += m["content"]
                    self.ui.text(m["content"])
                for tc in m.get("tool_calls") or []:
                    fn = tc.get("function") or {}
                    args = fn.get("arguments")
                    if isinstance(args, str):
                        try:
                            args = json.loads(args or "{}")
                        except ValueError:
                            args = "the arguments are not valid JSON"
                    calls.append({"id": tc.get("id") or f"call_{uuid.uuid4().hex[:12]}", "name": fn.get("name", ""),
                                  "input": args if args is not None else {}})
                if j.get("done"):
                    break
        return text, calls

    def save(self):
        """The conversation on disk after every round: last-session.json, and one file
        per chat in ~/.local/share/memora/ai/chats (the newest 30 are kept). Pictures
        are left out of the files (they are huge)."""
        def plain(b):
            b = b.model_dump() if hasattr(b, "model_dump") else b
            if isinstance(b, dict):
                if b.get("type") == "image":
                    return {"type": "image", "omitted": True}
                if isinstance(b.get("content"), list):
                    b = {**b, "content": [plain(x) for x in b["content"]]}
            return b
        try:
            DATA.mkdir(parents=True, exist_ok=True)
            out = [{"role": m["role"], "content": m["content"] if isinstance(m["content"], str) else
                    [plain(b) for b in m["content"]]} for m in self.messages]
            text = json.dumps(out, default=str, ensure_ascii=False, indent=1)[:5_000_000]
            (DATA / "last-session.json").write_text(text)
            chats = DATA / "chats"
            chats.mkdir(exist_ok=True)
            (chats / f"{getattr(self, 'started', 'chat')}.json").write_text(text)
            for old in sorted(chats.glob("*.json"))[:-30]:
                old.unlink(missing_ok=True)
        except OSError:
            pass


def chat_messages(messages, native=False):
    """The conversation (kept in Claude's shape) for Ollama or an OpenAI-compatible
    server: tool calls and results become theirs; pictures, PDFs and Claude's own
    thinking and web searches are left out."""
    out, names = [], {}
    for m in messages:
        c = m.get("content")
        if isinstance(c, str):
            out.append({"role": m["role"], "content": c})
            continue
        blocks = [b.model_dump() if hasattr(b, "model_dump") else b for b in c or []]
        blocks = [b for b in blocks if isinstance(b, dict)]
        if m["role"] == "assistant":
            text = "".join(b.get("text", "") for b in blocks if b.get("type") == "text")
            calls = []
            for b in blocks:
                if b.get("type") != "tool_use":
                    continue
                names[b["id"]] = b["name"]
                fn = {"name": b["name"], "arguments": b.get("input") or {}}
                calls.append({"function": fn} if native else
                             {"id": b["id"], "type": "function", "function": {**fn, "arguments": json.dumps(fn["arguments"], ensure_ascii=False)}})
            msg = {"role": "assistant", "content": text}
            if calls:
                msg["tool_calls"] = calls
            out.append(msg)
            continue
        said = []
        for b in blocks:
            t = b.get("type")
            if t == "tool_result":
                r = b.get("content")
                if isinstance(r, list):
                    r = "\n".join(x.get("text", "[a picture]" if x.get("type") == "image" else "") for x in r if isinstance(x, dict))
                r = str(r or "")
                if b.get("tool_use_id") not in names:
                    continue    # a result of one of Claude's own server tools
                out.append({"role": "tool", "tool_name": names[b["tool_use_id"]], "content": r} if native else
                           {"role": "tool", "tool_call_id": b["tool_use_id"], "content": r})
            elif t == "text":
                said.append(b.get("text", ""))
            elif t == "image":
                said.append("[a picture]")
            elif t == "document":
                said.append("[a PDF]")
        if said:
            out.append({"role": "user", "content": "\n".join(said)})
    return out


def recent_pictures(messages, keep=3):
    """The conversation with only the newest `keep` tool pictures (screenshots,
    widget checks): each is large, and an old one no longer shows the screen."""
    left, out = keep, []
    for m in reversed(messages):
        c = m.get("content")
        if m.get("role") == "user" and isinstance(c, list):
            blocks = []
            for b in reversed(c):
                if isinstance(b, dict) and b.get("type") == "tool_result" and isinstance(b.get("content"), list):
                    inner = []
                    for x in reversed(b["content"]):
                        if isinstance(x, dict) and x.get("type") == "image":
                            if left > 0:
                                left -= 1
                            else:
                                x = {"type": "text", "text": "[an earlier picture, no longer kept]"}
                        inner.append(x)
                    b = {**b, "content": inner[::-1]}
                blocks.append(b)
            m = {**m, "content": blocks[::-1]}
        out.append(m)
    return out[::-1]


IMAGE_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp"}
TEXT_LIMIT = 200_000


def attachments(files, images=True):
    """Content blocks for attached files (pictures, PDFs) and a note to add
    to the message (text files' contents, the paths of everything else)."""
    blocks, notes = [], []
    for f in files:
        ext = os.path.splitext(f)[1].lower()
        size = os.path.getsize(f)
        name = os.path.basename(f)
        if images and (ext in IMAGE_TYPES or ext in (".bmp", ".tif", ".tiff", ".heic", ".avif")):
            data, media = picture(f, ext)
            if data:
                blocks.append({"type": "image", "source": {"type": "base64", "media_type": media, "data": data}})
                notes.append(f"(picture above: {f})")
                continue
        if images and ext == ".pdf" and size <= 20_000_000:
            blocks.append({"type": "document", "source": {"type": "base64", "media_type": "application/pdf",
                                                          "data": base64.b64encode(Path(f).read_bytes()).decode()}, "title": name})
            notes.append(f"(PDF above: {f})")
            continue
        text = None
        if size <= TEXT_LIMIT:
            try:
                raw = Path(f).read_bytes()
                if b"\0" not in raw[:4096]:
                    text = raw.decode("utf-8")
            except (OSError, UnicodeDecodeError):
                text = None
        if text is not None:
            notes.append(f"Attached file {f}:\n```\n{text}\n```")
        else:
            kind = "picture" if ext in IMAGE_TYPES else "file"
            notes.append(f"Attached {kind}: {f} ({size:,} bytes). Use your tools to look at it if needed.")
    return blocks, ("\n\n" + "\n\n".join(notes)) if notes else ""


def document_text(p):
    """The text of a PDF or an office document, or None for anything else."""
    import zipfile
    import html as h
    ext = p.suffix.lower()
    try:
        if ext == ".pdf":
            r = subprocess.run(["pdftotext", "-layout", "-enc", "UTF-8", str(p), "-"], capture_output=True, text=True, timeout=60)
            return r.stdout if r.returncode == 0 else None
        xml = {".docx": "word/document.xml", ".odt": "content.xml", ".ods": "content.xml", ".odp": "content.xml",
               ".pptx": None, ".xlsx": "xl/sharedStrings.xml"}
        if ext in xml:
            with zipfile.ZipFile(p) as z:
                names = [xml[ext]] if xml[ext] else sorted((n for n in z.namelist() if re.match(r"ppt/slides/slide\d+\.xml$", n)),
                                                           key=lambda n: int(re.search(r"\d+", n.rsplit("/", 1)[1]).group()))
                raw = "\n".join(z.read(n).decode("utf-8", "replace") for n in names if n in z.namelist())
            raw = re.sub(r"</(w:p|text:p|text:h|a:p|si|table:table-row)>", "\n", raw)
            raw = re.sub(r"<(w:tab|text:tab|table:table-cell)\b[^>]*/?>", "\t", raw)
            return re.sub(r"\n{3,}", "\n\n", h.unescape(re.sub(r"<[^>]+>", "", raw))).strip()
        if ext in (".rtf", ".epub") and shutil.which("pandoc"):
            r = subprocess.run(["pandoc", "-t", "plain", str(p)], capture_output=True, text=True, timeout=60)
            return r.stdout if r.returncode == 0 else None
    except (OSError, zipfile.BadZipFile, subprocess.SubprocessError):
        return None
    return None


def picture(f, ext):
    """(base64, media type) for the API: as it is when it's small, else made
    smaller (longest side 1568 px, which is what Claude looks at anyway)."""
    try:
        if ext in IMAGE_TYPES and os.path.getsize(f) <= 3_500_000:
            dims = subprocess.run(["magick", "identify", "-format", "%w %h", f + "[0]"], capture_output=True, text=True, timeout=10).stdout.split()
            if len(dims) == 2 and max(int(dims[0]), int(dims[1])) <= 1568:
                return base64.b64encode(Path(f).read_bytes()).decode(), IMAGE_TYPES[ext]
        out = subprocess.run(["magick", f + "[0]", "-auto-orient", "-resize", "1568x1568>", "-quality", "85", "jpeg:-"],
                             capture_output=True, timeout=30)
        if out.returncode == 0 and out.stdout:
            return base64.b64encode(out.stdout).decode(), "image/jpeg"
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    return None, None


def friendly_error(e):
    name = type(e).__name__
    msg = str(e)
    if name == "AuthenticationError":
        return "The API key was not accepted. Check it in System Settings > Memora AI."
    if name == "RateLimitError":
        return "Too many requests right now. Wait a moment and try again."
    if name in ("APIConnectionError", "URLError", "ConnectionRefusedError"):
        return "Could not reach the AI service. Check the internet connection (or that Ollama is running)."
    if name == "PermissionDeniedError":
        return "This API key is not allowed to use that model."
    return msg or name


# -------------------------------------------------------------- frontends ----
class WindowUI:
    """JSON lines to and from the Memora AI window."""

    def __init__(self):
        self.inbox = queue.Queue()
        self.confirms = {}
        self.stop = threading.Event()
        self.n = 0
        self.lock = threading.Lock()
        threading.Thread(target=self.reader, daemon=True).start()

    def send(self, **kw):
        with self.lock:
            sys.stdout.write(json.dumps(kw) + "\n")
            sys.stdout.flush()

    def reader(self):
        for line in sys.stdin:
            try:
                m = json.loads(line)
            except ValueError:
                continue
            if m.get("type") == "confirm":
                q = self.confirms.get(m.get("id"))
                if q:
                    q.put(bool(m.get("ok")))
            elif m.get("type") == "stop":
                self.stop.set()
            else:
                self.inbox.put(m)
        self.inbox.put({"type": "quit"})

    def stopped(self):
        return self.stop.is_set()

    def text(self, t):
        self.send(type="text", delta=t)

    def status(self, s):
        self.send(type="status", text=s)

    def tool_start(self, name, summary):
        self.n += 1
        self.send(type="tool", id=self.n, name=name, summary=summary)
        return self.n

    def tool_end(self, tid, ok):
        self.send(type="tool_done", id=tid, ok=ok)

    def hands(self, on):
        """The chat folds into its pill (and lets go of the keyboard) while apps are used."""
        self.send(type="hands", on=on)

    def confirm(self, level, title, detail, why):
        self.n += 1
        q = queue.Queue()
        self.confirms[self.n] = q
        self.send(type="confirm", id=self.n, level=level, title=title, detail=detail, why=why)
        while True:
            try:
                return q.get(timeout=0.5)
            except queue.Empty:
                if self.stopped():
                    return False

    def error(self, msg):
        self.send(type="error", message=msg)


class TerminalUI:
    def __init__(self):
        self.tty = None
        try:
            self.tty = open("/dev/tty", "r+")
        except OSError:
            pass

    def stopped(self):
        return False

    def text(self, t):
        sys.stdout.write(t)
        sys.stdout.flush()

    def status(self, s):
        pass

    def tool_start(self, name, summary):
        sys.stderr.write(f"\n\033[2m· {summary}\033[0m\n")
        return 0

    def tool_end(self, tid, ok):
        pass

    def confirm(self, level, title, detail, why):
        if not self.tty:
            return False
        warn = "\033[1;31mDANGER\033[0m " if level == "critical" else ""
        self.tty.write(f"\n{warn}\033[1m{title}\033[0m\n  {detail}\n  {why}\nAllow? [y/N] ")
        self.tty.flush()
        return self.tty.readline().strip().lower() in ("y", "yes", "da", "d")

    def error(self, msg):
        sys.stderr.write(f"\n[memora-ai] {msg}\n")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "serve"
    if mode == "serve":
        ui = WindowUI()
        agent = Agent(ui)
        p = agent.cfg.get("provider")
        def ready():
            c, p = agent.cfg, agent.cfg.get("provider") or "anthropic"
            ui.send(type="ready", provider=p, model=c.get("model") or ("deepseek-chat" if p == "deepseek" else ("" if p == "claude-code" else DEFAULT_MODEL)),
                    effort=effort_of(c), models=[{"id": i, "name": n} for i, n in MODELS], efforts=EFFORTS,
                    canEffort=p in ("anthropic", "claude-code"), canModel=p in ("anthropic", "claude-code"))
        ready()
        while True:
            m = ui.inbox.get()
            if m.get("type") == "quit":
                break
            if m.get("type") == "new":
                agent.reset()
                continue
            if m.get("type") == "refresh":
                agent.cfg = load_config()
                ready()
                continue
            if m.get("type") == "settings":
                # Model and effort, chosen in the window: kept in ai.json.
                try:
                    c = json.loads((CONF / "ai.json").read_text())
                except (OSError, ValueError):
                    c = {"provider": "anthropic"}
                for k in ("model", "effort"):
                    if k in m:
                        c[k] = m[k]
                try:
                    CONF.mkdir(parents=True, exist_ok=True)
                    (CONF / "ai.json").write_text(json.dumps(c, indent=2) + "\n")
                except OSError:
                    pass
                agent.cfg = load_config()
                ready()
                continue
            if m.get("type") == "user":
                ui.stop.clear()
                agent.cfg = load_config()
                ready()
                agent.turn(m.get("text", ""), m.get("files") or [])
                ui.send(type="done")
    elif mode == "tools":
        for t in TOOLS:
            props = t["input_schema"]["properties"]
            req = set(t["input_schema"].get("required", []))
            args = ", ".join(f"{k}{'' if k in req else '?'}: {v.get('type', 'any')}" + (f" {v['enum']}" if v.get("enum") else "") for k, v in props.items())
            print(f"{t['name']}({args})\n    {t['description']}")
    elif mode == "tool":
        if len(sys.argv) < 3:
            sys.exit("usage: memora-ai tool NAME 'JSON'")
        name = sys.argv[2]
        try:
            data = json.loads(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].strip() else {}
        except ValueError as e:
            sys.exit(f"The input is not valid JSON: {e}")
        if not any(t["name"] == name for t in TOOLS):
            sys.exit(f"No tool called {name}. See: memora-ai tools")
        problem = check_input(name, data)
        if problem:
            sys.exit(problem)
        tools = Tools(BridgeUI())
        tools.hands_on = False
        try:
            if name in SCREEN_TOOLS and not load_config().get("screenControl", True):
                content, err = "The person turned off screen control (System Settings > Privacy & Security).", True
            else:
                content, err = tools.run(name, data)
        except Exception as e:
            content, err = f"{type(e).__name__}: {e}", True
        if isinstance(content, list):
            # Pictures (a screenshot) go to a file Claude Code can Read.
            out = []
            for b in content:
                if b.get("type") == "image":
                    f = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp") / f"memora-ai-{int(time.time() * 1000)}.png"
                    f.write_bytes(base64.b64decode(b["source"]["data"]))
                    out.append(f"Screenshot saved: {f} (Read it to see the screen)")
                elif b.get("type") == "text":
                    out.append(b.get("text", ""))
            content = "\n".join(out)
        print(content if isinstance(content, str) else json.dumps(content, ensure_ascii=False))
        sys.exit(1 if err else 0)
    elif mode == "ask":
        q = " ".join(sys.argv[2:])
        # Piped input is attached; a stdin that's open but silent (another
        # program running this one) isn't waited for.
        import select
        if not sys.stdin.isatty() and (not q.strip() or select.select([sys.stdin], [], [], 0.3)[0]):
            piped = sys.stdin.read()
            if piped.strip():
                q = f"{q}\n\n```\n{clip(piped, 30000)}\n```"
        if not q.strip():
            sys.exit("usage: memora-ai ask QUESTION")
        ui = TerminalUI()
        Agent(ui).turn(q)
        sys.stdout.write("\n")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
