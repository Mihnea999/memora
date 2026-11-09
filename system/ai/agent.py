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
Other providers (Ollama, OpenAI-compatible) answer without tools.

  agent.py tools            Memora's tools, with their inputs (for Claude Code)
  agent.py tool NAME JSON   run one of them
"""
import base64
import json
import os
import queue
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time
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
MODELS = [("claude-fable-5-1", "Fable 5.1"), ("claude-opus-5-5", "Opus 5.5"), ("claude-sonnet-5-5", "Sonnet 5.5"), ("claude-haiku-5-5", "Haiku 5.5")]
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
                os.environ.setdefault(k.strip(), v.strip())
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


def system_prompt(claude_code=False):
    f = system_facts()
    guides = "\n".join(f"  - {n}: {w}" for n, (w, _) in skills().items()) or "  (none installed)"
    memory = MEMORY.read_text() if MEMORY.exists() else "(empty)"
    screen = on_screen()
    if claude_code:
        style = CLAUDE_CODE_NOTES.format(skills_dir=SKILLS, guides=guides)
        memory_note = "add to it with: memora-ai remember FACT"
    else:
        style = None
        memory_note = "add to it with the remember tool when they tell you something worth keeping"
    text = f"""You are Memora AI, the assistant built into Memora, a desktop operating system based on Arch Linux with the Hyprland compositor. You run on the person's own computer and can act on it with your tools.

The computer: user {f['user']} (home {f['home']}), host {f['hostname']}, Memora {f['memora']}, kernel {f['kernel']}, CPU {f['cpu']}, memory {f['memory']}, graphics {f['gpu']}, disk (free/size) {f['disk']}, appearance {f['theme']}. Now: {f['time']}.
On the screen: {screen}

How Memora works: packages come from pacman (official Arch repositories); there is no AUR helper unless the person installed one. Settings live in System Settings (memora-settings PANE, panes: wifi, bluetooth, network, notifications, sound, appearance, wallpaper, dock, animations, displays, keyboard, mouse, battery, datetime, users, privacy, ai, update, about). Light/dark: memora-theme set light|dark. Updates: memora-update. Snapshots: snapper (one is taken before every pacman transaction). Hyprland is configured in Lua (~/.config/hypr/user.lua for personal changes). The shell (menu bar, Dock, Launchpad) is memora-shell. Developer toolkits: memora-dev.

Working style:
{{STYLE}}- Do what is asked with your tools rather than telling the person how to do it, unless they asked for instructions.
- Pick the most direct tool: a dedicated one (browse, open, system_setting, media, reminder, notes, apps, find_files, windows, arrange_window, weather, system_info…) beats a shell command, and a shell command beats clicking on the screen. Use the screen tools (screenshot, click, type_text, press_keys, scroll) only for work inside apps that has no other way.
- Searching or showing something online: browse(search=…) or browse(url=…) opens the Browser right on it. Never open the Browser and type the search, and never type into this chat: you are the notch at the top of the screen, and keys you send go to the window you name with `window`.
- Working in an app: open it, wait_for_window, screenshot, then click/type_text/press_keys with window=…, and check with a screenshot. While you do this the chat folds out of the way by itself.
- Guides: before a task one of these covers, read it with skill(name) and follow it (once per conversation is enough):
{guides}
- Commands that need administrator rights: write them with sudo; Memora shows its own password dialog.
- Risky actions are confirmed by the person before they run; if one is declined, accept it and offer an alternative. Never try to get around a declined action.
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
    keep = [b.strip() for b in bullets if b.startswith(("Keep answers short", "Do what is asked"))]
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
]


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
    if not (str(p).startswith(str(HOME)) or str(p).startswith("/tmp")):
        return "risky", "writes outside your home folder"
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
    tool("read_file", "Read a text file. Returns up to max_bytes (default 60000) starting at offset.",
         {"path": S, "offset": I, "max_bytes": I}, ["path"]),
    tool("write_file", "Create or replace a text file with the given content. Folders are created as needed.",
         {"path": S, "content": S}, ["path", "content"]),
    tool("list_directory", "List a folder: names, kinds and sizes.", {"path": S}, ["path"]),
    tool("open", "Open an app (by name, e.g. 'Files', 'Browser', 'Terminal', 'Text Editor', or a desktop id), a file or folder (path), or a web address (URL).",
         {"target": S}, ["target"]),
    tool("system_setting", "Change a setting. volume/brightness: 0-100 or +N/-N. wifi/bluetooth/do_not_disturb/night_shift/dock_autohide: on|off. keep_awake (screen stays on, no lock or sleep): off, on, or minutes. appearance: light|dark. wallpaper: image path, or 'default'. dock_size: 36-72. settings_pane: open System Settings at a pane (wifi, bluetooth, sound, displays, battery, dock, ...).",
         {"setting": {"type": "string", "enum": ["volume", "brightness", "wifi", "bluetooth", "appearance", "wallpaper", "do_not_disturb", "focus", "night_shift", "keep_awake", "dock_autohide", "dock_size", "settings_pane"]}, "value": S},
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
    tool("clipboard", "Read the clipboard, or put text on it (then paste in an app with press_keys ctrl+v).",
         {"action": {"type": "string", "enum": ["get", "set"]}, "text": S}, ["action"]),
    tool("media", "Music and video playing in any app (Player, Browser, Spotify…): status shows what is playing; play, pause, toggle, next, previous control it.",
         {"action": {"type": "string", "enum": ["status", "play", "pause", "toggle", "next", "previous"]}}, ["action"]),
    tool("apps", "Apps on this computer and in the App Store: list (installed apps), running (open apps), search (the App Store / Flathub), install or uninstall an App Store app by its id.",
         {"action": {"type": "string", "enum": ["list", "running", "search", "install", "uninstall"]}, "query": S, "id": S}, ["action"]),
    tool("find_files", "Find files: by `name` (wildcards allowed, e.g. '*.pdf', 'invoice*') and/or by `text` inside them. Searches `folder` (default the home folder), newest first, up to 50.",
         {"name": S, "text": S, "folder": S}),
    tool("reminder", "Reminders and timers: set one in `minutes` or `at` a time ('18:30', 'tomorrow 9:00', '2026-12-24 10:00') with `text`; list them; cancel one by id.",
         {"action": {"type": "string", "enum": ["set", "list", "cancel"]}, "text": S, "minutes": I, "at": S, "id": S}, ["action"]),
    tool("notes", "The Notes app: create a note (title and text; lines starting with '☐ ' are checklist items), list recent notes, search them, or read one by id.",
         {"action": {"type": "string", "enum": ["create", "list", "search", "read"]}, "title": S, "text": S, "query": S, "id": S}, ["action"]),
    tool("widget", "Desktop widgets of your own: small glass cards on the desktop picture. create (or update) one from QML you write (read the widgets guide first: skill('widgets')), remove one, list them, or show one's QML. After create it says whether it loaded or the error to fix.",
         {"action": {"type": "string", "enum": ["create", "remove", "list", "show"]}, "name": S,
          "size": {"type": "string", "enum": ["small", "medium"]}, "qml": S}, ["action"]),
    tool("power", "Lock the screen, sleep, restart, shut down or log out. Restart, shut down and log out show their own question on screen.",
         {"action": {"type": "string", "enum": ["lock", "sleep", "restart", "shutdown", "logout"]}}, ["action"]),
    tool("system_info", "Facts about the computer now: battery, network, storage, memory, cpu, processes (the busiest), displays, audio, or all.",
         {"what": {"type": "string", "enum": ["all", "battery", "network", "storage", "memory", "cpu", "processes", "displays", "audio"]}}, ["what"]),
    tool("download", "Download a file from the internet into Downloads (or `folder`) and return its path.",
         {"url": S, "folder": S}, ["url"]),
    tool("weather", "Current weather and the next days, for `place` (a city) or where the computer is.", {"place": S}),
    tool("skill", "Read a how-to guide before a task it covers (the list is in the system prompt). Follow it.", {"name": S}, ["name"]),
    tool("remember", "Save a fact about the person or their preferences to the memory file, for later conversations.", {"fact": S}, ["fact"]),
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
              "boolean": isinstance(v, bool)}.get(t, True)
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
    aliases = {"browser": "chromium", "terminal": "com.mitchellh.ghostty", "files": "org.gnome.nautilus",
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
        run = command
        if re.search(r"(^|[;&|(]\s*)sudo\s", command):
            # Administrator commands go through polkit, which shows Memora's password dialog.
            run = "pkexec bash -c " + shlex.quote(re.sub(r"(^|(?<=[;&|(]))\s*sudo\s+(-\S+\s+)*", r"\1 ", command))
        try:
            r = subprocess.run(["bash", "-lc", run], capture_output=True, text=True, timeout=timeout, cwd=HOME)
            out = (r.stdout or "") + (("\n[stderr]\n" + r.stderr) if r.stderr else "")
            return clip(f"exit code {r.returncode}\n{out}".strip()), r.returncode != 0
        except subprocess.TimeoutExpired as e:
            return clip(f"timed out after {timeout}s\n{e.stdout or ''}"), True

    def t_read_file(self, path, offset=0, max_bytes=60000):
        p = Path(path).expanduser()
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
            shell_prefs(dockAutohide=on)
            return f"The Dock {'hides until the pointer reaches the bottom' if on else 'stays on screen'}.", False
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
            r = sh(["flatpak", "search", "--columns=application,name,description", query], timeout=60)
            rows = [l for l in r.stdout.splitlines() if l.strip() and not re.search(r"\.(Plugin|Extension|Locale|Debug|Manual|Docs)\b", l)]
            return clip("\n".join(rows[:25]) or "Nothing found in the App Store."), False
        if not id:
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
        root = Path(folder or "~").expanduser()
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
        d = Path(folder or "~/Downloads").expanduser()
        d.mkdir(parents=True, exist_ok=True)
        r = sh(["curl", "-fsSL", "--max-time", "600", "-OJ", "--output-dir", str(d), "-w", "%{filename_effective}", url], timeout=620)
        return (f"Saved {r.stdout.strip()}." if r.returncode == 0 else f"Download failed: {r.stderr.strip()}"), r.returncode != 0

    def t_fetch_url(self, url):
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) MemoraAI"})
        with urllib.request.urlopen(req, timeout=20) as r:
            body = r.read(3_000_000).decode(r.headers.get_content_charset() or "utf-8", errors="replace")
        return clip(html_text(body) if "<" in body[:2000] else body), False

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
        body = [l for l in text.splitlines()]
        para = lambda l: (f"<p><span style='font-size:22px; color:#9a9aa2;'>☐</span>&nbsp;{h.escape(l[2:])}</p>" if l.startswith("☐ ")
                          else f"<p>{h.escape(l) or '<br>'}</p>")
        now = int(time.time() * 1000)
        n = {"id": f"n{now}", "folder": (j.get("folders") or ["Notes"])[0], "pinned": False, "deleted": False,
             "created": now, "modified": now, "text": (title + "\n" if title else "") + text,
             "html": (f"<h1>{h.escape(title)}</h1>" if title else "") + "".join(para(l) for l in body)}
        j.setdefault("notes", []).append(n)
        NOTES.parent.mkdir(parents=True, exist_ok=True)
        NOTES.write_text(json.dumps(j))
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
        if action == "remove":
            if layout is not None:
                layout_file.write_text(json.dumps([o for o in layout if not (o.get("type") == "custom" and o.get("file") == name)], indent=1) + "\n")
            for p in (f, wdir / f"{name}.status"):
                p.unlink(missing_ok=True)
            return f"Removed the {name} widget.", False
        if not qml.strip():
            return "Write the widget's QML in `qml`.", True
        wdir.mkdir(parents=True, exist_ok=True)
        st = wdir / f"{name}.status"
        before = st.stat().st_mtime if st.exists() else 0
        f.write_text(qml)
        size = size if size in ("small", "medium") else "small"
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
            return f"Saved {f}. The desktop has not reported back yet (is the desktop running?); look with a screenshot.", False
        result = st.read_text().strip()
        if result.startswith("error"):
            return f"The widget did not load. Fix the QML and create it again:\n{result.partition(chr(10))[2].strip()}", True
        return f"The {name} widget is on the desktop ({size}). Take a screenshot to check how it looks.", False

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
            loc = get("https://ipapi.co/json/")
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
        with open(MEMORY, "a") as f:
            f.write(f"- {fact.strip()} ({time.strftime('%Y-%m-%d')})\n")
        return "Saved to memory.", False


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
        "clipboard": lambda d: "Reading the clipboard" if d.get("action") == "get" else "Copying to the clipboard",
        "media": lambda d: "Media: " + d.get("action", ""),
        "apps": lambda d: f"Apps: {d.get('action', '')} {d.get('query') or d.get('id') or ''}".strip(),
        "find_files": lambda d: "Looking for " + (d.get("name") or d.get("text") or "files"),
        "reminder": lambda d: "Reminder: " + (d.get("text") or d.get("action", "")),
        "notes": lambda d: "Notes: " + (d.get("title") or d.get("query") or d.get("action", "")),
        "widget": lambda d: {"create": "Making the widget ", "remove": "Removing the widget ", "list": "Looking at widgets", "show": "Reading the widget "}.get(d.get("action"), "Widget ") + (d.get("name") or ""),
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
        self.sock.bind(self.path)
        os.chmod(self.path, 0o600)
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
        self.cc_session = None
        self.cc_started = False

    def turn(self, text, files=()):
        self.cfg = load_config()
        self.tools.hands_on = False
        provider = self.cfg.get("provider") or "anthropic"
        files = [f for f in files if isinstance(f, str) and os.path.isfile(f)]
        # Attached files: Claude sees pictures and PDFs; the others get the text
        # of text files and the paths of the rest (they can open them with tools).
        blocks, note = attachments(files, images=provider == "anthropic")
        if blocks:
            self.messages.append({"role": "user", "content": blocks + [{"type": "text", "text": (text or "What is this?") + note}]})
        else:
            self.messages.append({"role": "user", "content": (text or ("What is this?" if files else "")) + note})
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
            client = anthropic.Anthropic(api_key=key, base_url=os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com/anthropic"))
            model = self.cfg.get("model") or "deepseek-chat"
            tools = [{k: v for k, v in t.items() if k != "eager_input_streaming"} for t in self.tool_specs() + [FETCH_TOOL]]
            extra = {"max_tokens": 8000}
        else:
            key = os.environ.get("ANTHROPIC_API_KEY")
            if not key:
                raise RuntimeError("No Anthropic API key yet. Add one in System Settings > Memora AI.")
            client = anthropic.Anthropic(api_key=key)
            model = self.cfg.get("model") or DEFAULT_MODEL
            tools = self.tool_specs() + SERVER_TOOLS
            extra = {"max_tokens": 32000, "thinking": {"type": "adaptive"},
                     "output_config": {"effort": effort_of(self.cfg)}}
        retries = 0
        while not self.ui.stopped():
            try:
                with client.messages.stream(
                    model=model,
                    system=system_prompt(),
                    tools=tools,
                    messages=self.messages,
                    **extra,
                ) as stream:
                    for event in stream:
                        if self.ui.stopped():
                            break
                        if event.type == "text":
                            self.ui.text(event.text)
                        elif event.type == "content_block_start":
                            b = event.content_block
                            if b.type == "thinking":
                                self.ui.status("Thinking…")
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
                             env={**os.environ, "MEMORA_AI_PERMIT": self.permit.path})
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
            if re.search(r"(^|[;&|(]\s*)sudo\s", cmd):
                # Administrator commands go through polkit: Memora's password dialog.
                inp = dict(inp, command="pkexec bash -c " + shlex.quote(re.sub(r"(^|(?<=[;&|(]))\s*sudo\s+(-\S+\s+)*", r"\1 ", cmd)))
                level, why = (level if level == "critical" else "risky"), (why if level != "safe" else "runs as administrator")
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
        if name in ("Read", "Glob", "Grep", "LS", "WebSearch", "WebFetch", "TodoWrite", "Task", "Agent", "ExitPlanMode", "ToolSearch", "Skill"):
            return allow(inp)
        ok = self.ui.confirm("risky", f"Allow {name}?", clip(json.dumps(inp, ensure_ascii=False, indent=1), 1200), "Memora AI wants to use this tool.")
        return allow(inp) if ok else deny("The person declined.")

    # Ollama and OpenAI-compatible servers: plain chat.
    def openai_turn(self, provider):
        base = (self.cfg.get("baseUrl") or ("http://localhost:11434/v1" if provider == "ollama" else "")).rstrip("/")
        if not base:
            raise RuntimeError("Set the server address in System Settings > Memora AI.")
        def plain(c):
            if isinstance(c, str):
                return c
            return "\n".join(b.get("text", "") if isinstance(b, dict) and b.get("type") == "text" else
                             ("[a picture]" if isinstance(b, dict) and b.get("type") == "image" else json.dumps(b, default=str)) for b in c)
        msgs = [{"role": "system", "content": system_prompt()}] + [
            {"role": m["role"], "content": plain(m["content"])} for m in self.messages]
        body = json.dumps({"model": self.cfg.get("model") or "qwen3:8b", "stream": True, "messages": msgs}).encode()
        req = urllib.request.Request(base + "/chat/completions", data=body, headers={
            "Content-Type": "application/json", "Authorization": "Bearer " + os.environ.get("OPENAI_API_KEY", "none")})
        answer = ""
        with urllib.request.urlopen(req, timeout=300) as r:
            for raw in r:
                if self.ui.stopped():
                    return
                line = raw.decode().strip()
                if not line.startswith("data: ") or line == "data: [DONE]":
                    continue
                try:
                    delta = json.loads(line[6:])["choices"][0]["delta"].get("content") or ""
                except (ValueError, KeyError, IndexError):
                    continue
                answer += delta
                self.ui.text(delta)
        self.messages.append({"role": "assistant", "content": answer})
        self.save()

    def save(self):
        DATA.mkdir(parents=True, exist_ok=True)
        try:
            plain = [{"role": m["role"], "content": m["content"] if isinstance(m["content"], str) else
                      [b.model_dump() if hasattr(b, "model_dump") else b for b in m["content"]]} for m in self.messages]
            (DATA / "last-session.json").write_text(json.dumps(plain, default=str)[:5_000_000])
        except OSError:
            pass


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
        if not sys.stdin.isatty():
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
