#!/usr/bin/env python3
"""Memora AI: an assistant that can use the computer it runs on.

  agent.py serve            JSON lines on stdin/stdout, for the Memora AI window
  agent.py ask QUESTION     answer in the terminal (stdin is attached if piped)

With Claude (the Anthropic API) it has tools: run commands, read and write
files, open apps, change settings, manage windows, look at the screen and
click/type, search the web. Anything risky waits for the person's OK; the
gravest actions (erasing disks, deleting the system) show a stronger warning.
Other providers (Claude Code, Ollama, OpenAI-compatible) answer without tools.
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
from pathlib import Path

HOME = Path.home()
CONF = HOME / ".config/memora"
DATA = HOME / ".local/share/memora/ai"
MEMORY = DATA / "memory.md"
MEMORA_PATH = os.environ.get("MEMORA_PATH", "/usr/share/memora")
DEFAULT_MODEL = "claude-opus-5-5"
OUT_LIMIT = 20000


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


def system_prompt():
    f = system_facts()
    memory = MEMORY.read_text() if MEMORY.exists() else "(empty)"
    return f"""You are Memora AI, the assistant built into Memora, a desktop operating system based on Arch Linux with the Hyprland compositor. You run on the person's own computer and can act on it with your tools.

The computer: user {f['user']} (home {f['home']}), host {f['hostname']}, Memora {f['memora']}, kernel {f['kernel']}, CPU {f['cpu']}, memory {f['memory']}, graphics {f['gpu']}, disk (free/size) {f['disk']}, appearance {f['theme']}. Now: {f['time']}.

How Memora works: packages come from pacman (official Arch repositories); there is no AUR helper unless the person installed one. Settings live in System Settings (memora-settings PANE, panes: wifi, bluetooth, network, notifications, sound, appearance, wallpaper, dock, displays, keyboard, mouse, battery, datetime, users, ai, update, about). Light/dark: memora-theme set light|dark. Updates: memora-update. Snapshots: snapper (one is taken before every pacman transaction). Hyprland is configured in Lua (~/.config/hypr/user.lua for personal changes). The shell (menu bar, Dock, Launchpad) is memora-shell. Developer toolkits: memora-dev.

Working style:
- Do what is asked with your tools rather than telling the person how to do it, unless they asked for instructions.
- Prefer the dedicated tools (open, system_setting, windows) over shell commands when one fits; use the screen tools (screenshot, click, type_text, press_keys, scroll) to work inside apps that have no command line. Take a screenshot first, act, then check with another screenshot.
- Commands that need administrator rights: write them with sudo; Memora shows its own password dialog.
- Risky actions are confirmed by the person before they run; if one is declined, accept it and offer an alternative. Never try to get around a declined action.
- Keep answers short and plain. Answer in the language the person writes in. Use Markdown only where it helps (code blocks for commands and files).

What you know about this person (their memory file; add to it with the remember tool when they tell you something worth keeping):
{memory}
"""


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
    tool("system_setting", "Change a setting. volume/brightness: 0-100 or +N/-N. wifi/bluetooth/focus/night_shift: on|off. appearance: light|dark. wallpaper: image path, or 'default'. settings_pane: open System Settings at a pane (wifi, bluetooth, sound, displays, ...).",
         {"setting": {"type": "string", "enum": ["volume", "brightness", "wifi", "bluetooth", "appearance", "wallpaper", "focus", "night_shift", "settings_pane"]}, "value": S},
         ["setting", "value"]),
    tool("windows", "List open windows, or focus, close, minimize, maximize or restore one. `window` is an address from the list or an app class.",
         {"action": {"type": "string", "enum": ["list", "focus", "close", "minimize", "maximize", "restore"]}, "window": S}, ["action"]),
    tool("screenshot", "Take a screenshot of the screen to see what is on it. Coordinates for click/scroll are in this image's pixels.", {}),
    tool("click", "Click at a point of the last screenshot.",
         {"x": I, "y": I, "button": {"type": "string", "enum": ["left", "right", "middle"]}, "double": {"type": "boolean"}}, ["x", "y"]),
    tool("type_text", "Type text into the focused app, as if on the keyboard.", {"text": S}, ["text"]),
    tool("press_keys", "Press a key or shortcut, e.g. 'Return', 'Escape', 'ctrl+s', 'ctrl+shift+t', 'alt+F4', 'super'.", {"keys": S}, ["keys"]),
    tool("scroll", "Scroll at a point of the last screenshot.",
         {"x": I, "y": I, "direction": {"type": "string", "enum": ["up", "down", "left", "right"]}, "amount": I}, ["x", "y", "direction"]),
    tool("notify", "Show a desktop notification.", {"title": S, "body": S}, ["title"]),
    tool("remember", "Save a fact about the person or their preferences to the memory file, for later conversations.", {"fact": S}, ["fact"]),
]
SERVER_TOOLS = [
    {"type": "web_search_20260209", "name": "web_search"},
    {"type": "web_fetch_20260209", "name": "web_fetch"},
]


def check_input(name, data):
    """Validate a tool input against its schema (eager streaming skips server checks)."""
    spec = next((t for t in TOOLS if t["name"] == name), None)
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


class Tools:
    def __init__(self, ui):
        self.ui = ui

    def run(self, name, data):
        """Returns (content, is_error). content: str or list of blocks."""
        return getattr(self, "t_" + name)(**data)

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
        return f"Opened {app}.", False

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
        elif setting == "focus":
            return "Use the Control Center to turn Focus on or off; it is not reachable from here yet.", True
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

    def t_type_text(self, text):
        r = sh(["wtype", "--", text], timeout=60)
        return ("Typed." if r.returncode == 0 else f"Failed: {r.stderr.strip()}"), r.returncode != 0

    def t_press_keys(self, keys):
        press_keys(keys)
        return f"Pressed {keys}.", False

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
        "web_search": lambda d: "Searching the web: " + str(d.get("query", "")),
        "web_fetch": lambda d: "Reading " + str(d.get("url", "")),
    }.get(name, lambda d: name)(data or {})


# ------------------------------------------------------------- providers ----
class Agent:
    def __init__(self, ui):
        self.ui = ui
        self.cfg = load_config()
        self.messages = []
        self.tools = Tools(ui)

    def reset(self):
        self.messages = []

    def turn(self, text):
        self.cfg = load_config()
        provider = self.cfg.get("provider") or "anthropic"
        self.messages.append({"role": "user", "content": text})
        try:
            if provider == "anthropic":
                self.claude_turn()
            elif provider == "claude-code":
                self.claude_code_turn(text)
            else:
                self.openai_turn(provider)
        except Exception as e:  # shown in the window, not a crash
            self.ui.error(friendly_error(e))

    # Claude, with tools. A manual streaming loop: text appears as it is
    # written, and each tool call can stop for the person's OK.
    def claude_turn(self):
        import anthropic
        key = os.environ.get("ANTHROPIC_API_KEY")
        if not key:
            raise RuntimeError("No Anthropic API key yet. Add one in System Settings > Memora AI.")
        client = anthropic.Anthropic(api_key=key)
        model = self.cfg.get("model") or DEFAULT_MODEL
        retries = 0
        while not self.ui.stopped():
            try:
                with client.messages.stream(
                    model=model,
                    max_tokens=32000,
                    system=system_prompt(),
                    thinking={"type": "adaptive"},
                    tools=TOOLS + SERVER_TOOLS,
                    messages=self.messages,
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
                    content, err = self.tools.run(b.name, b.input)
                except Exception as e:
                    content, err = f"{type(e).__name__}: {e}", True
                self.ui.tool_end(tid, not err)
                results.append({"type": "tool_result", "tool_use_id": b.id, "content": content, "is_error": bool(err)})
            self.messages.append({"role": "user", "content": results})

    # Claude Code answers with its own tools, in its own session.
    def claude_code_turn(self, text):
        if not shutil.which("claude"):
            raise RuntimeError("Claude Code is not installed. Install it with: memora-dev install claude")
        p = subprocess.Popen(["claude", "-p", "--output-format", "stream-json", "--verbose",
                              "--append-system-prompt", system_prompt(), text],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=HOME)
        answer = ""
        for line in p.stdout:
            if self.ui.stopped():
                p.terminate()
                return
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if ev.get("type") == "assistant":
                for c in ev.get("message", {}).get("content", []):
                    if c.get("type") == "text":
                        self.ui.text(c["text"])
                        answer += c["text"]
                    elif c.get("type") == "tool_use":
                        tid = self.ui.tool_start(c.get("name", ""), describe(c.get("name", ""), c.get("input", {})))
                        self.ui.tool_end(tid, True)
        p.wait()
        self.messages.append({"role": "assistant", "content": answer or "(no answer)"})
        self.save()

    # Ollama and OpenAI-compatible servers: plain chat.
    def openai_turn(self, provider):
        base = (self.cfg.get("baseUrl") or ("http://localhost:11434/v1" if provider == "ollama" else "")).rstrip("/")
        if not base:
            raise RuntimeError("Set the server address in System Settings > Memora AI.")
        msgs = [{"role": "system", "content": system_prompt()}] + [
            {"role": m["role"], "content": m["content"] if isinstance(m["content"], str) else json.dumps(m["content"])}
            for m in self.messages]
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
        ui.send(type="ready", provider=agent.cfg.get("provider"), model=agent.cfg.get("model") or DEFAULT_MODEL)
        while True:
            m = ui.inbox.get()
            if m.get("type") == "quit":
                break
            if m.get("type") == "new":
                agent.reset()
                continue
            if m.get("type") == "user":
                ui.stop.clear()
                agent.turn(m.get("text", ""))
                ui.send(type="done")
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
