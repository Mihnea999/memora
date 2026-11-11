#!/usr/bin/env python3
"""Synthesises Memora's system sounds into system/sounds/*.oga.

No samples: every sound is built here from modelled instruments (a struck
glass, a singing bowl, vibraphone and marimba bars, a kalimba tine, an electric
piano, a plucked string, air) played in one key (D major), in stereo, in a
smooth room. What keeps them from sounding like a synthesiser:
  - partials at the ratios of the real object, the high ones dying first;
  - a soft attack and the small knock of the mallet or finger;
  - two copies of each partial a hair apart, so the tone shimmers instead of
    standing still;
  - a room made of decaying noise (dense, no metallic ring), darker as it fades;
  - nothing above about 9 kHz, nothing shrill: the notes sit between D4 and E6.
Run: python3 tools/sounds.py [alerts] [system]   (needs numpy and ffmpeg)
"""
import os, re, shutil, subprocess, sys, tempfile, wave
import numpy as np

SR = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "system", "sounds")
rng = np.random.default_rng(7)

# D major, the notes used.
D3, A3 = 146.83, 220.00
D4, E4, FS4, A4, B4 = 293.66, 329.63, 369.99, 440.00, 493.88
D5, E5, FS5, A5, B5 = 587.33, 659.25, 739.99, 880.00, 987.77
D6, E6 = 1174.66, 1318.51


# ------------------------------------------------------------------ basics
def t_(dur):
    return np.arange(int(dur * SR)) / SR


def rise(t, attack):
    """A soft start: half a cosine over `attack` seconds (no click)."""
    return np.where(t < attack, 0.5 - 0.5 * np.cos(np.pi * np.minimum(t / attack, 1.0)), 1.0)


def shape(x, lo=None, hi=None, slope=2.0):
    """Zero-phase filter: gently removes what is under lo and over hi (Hz)."""
    X = np.fft.rfft(x, axis=0)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-6)) ** (2 * slope))
    if hi:
        g *= 1 / np.sqrt(1 + (f / hi) ** (2 * slope))
    if x.ndim == 2:
        g = g[:, None]
    return np.fft.irfft(X * g, n=len(x), axis=0)


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def stereo(x, pan=0.0):
    """Mono to stereo, pan -1 (left) … 1 (right), equal power."""
    a = (pan + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1) * np.sqrt(2)


def mix(*parts):
    """mix((signal, at_seconds, gain, pan), …) -> stereo."""
    n = max(int(at * SR) + len(x) for x, at, *_ in parts)
    out = np.zeros((n, 2))
    for x, at, *rest in parts:
        gain = rest[0] if rest else 1.0
        pan = rest[1] if len(rest) > 1 else 0.0
        s = (x if x.ndim == 2 else stereo(x, pan)).copy()
        k = min(int(0.08 * SR), len(s) // 2)       # every part ends in a fade, never a cut
        s[-k:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, k)))[:, None]
        o = int(at * SR)
        out[o:o + len(s)] += s * gain
    return out


# ------------------------------------------------------------- instruments
def modal(f, dur, partials, attack=0.004, shimmer=0.0012):
    """A struck object: partials (ratio, level, seconds to fade), each sounded
    twice a hair apart (one copy quieter) so it shimmers, as real glass and
    metal do, without ever pulsing down to silence."""
    t = t_(dur)
    out = np.zeros_like(t)
    for k, (ratio, amp, decay) in enumerate(partials):
        fp = f * ratio
        if fp > 9500:
            continue
        ph = rng.uniform(0, 2 * np.pi)
        d = shimmer * (1 + 0.3 * k)
        out += amp * np.exp(-t / decay) * (0.74 * np.sin(2 * np.pi * fp * (1 - d) * t + ph) + 0.26 * np.sin(2 * np.pi * fp * (1 + d) * t + ph * 1.3))
    return out * rise(t, attack)


def knock(f, level=0.3, length=0.012):
    """The contact itself: a few milliseconds of soft noise around the note."""
    n = noise(0.05)
    t = t_(0.05)
    return shape(n * np.exp(-t / length) * rise(t, 0.001), lo=f * 0.8, hi=min(f * 5, 7000)) * level


def glass(f, dur=1.6, ring=0.7):
    """A wine glass tapped with a fingernail."""
    p = [(1, 1.0, ring), (2.32, 0.42, ring * 0.55), (4.25, 0.16, ring * 0.3), (6.63, 0.06, ring * 0.16)]
    return mix((modal(f, dur, p, attack=0.003), 0), (knock(f * 2, 0.12, 0.004), 0))[:, 0]


def bowl(f, dur=3.2, ring=1.6):
    """A small singing bowl: wide slow beating, a long calm ring."""
    p = [(1, 1.0, ring), (2.71, 0.5, ring * 0.6), (5.15, 0.2, ring * 0.33), (8.1, 0.06, ring * 0.18)]
    return modal(f, dur, p, attack=0.006, shimmer=0.0022)


def vibes(f, dur=2.0, ring=1.0):
    """A vibraphone bar under a soft mallet."""
    p = [(1, 1.0, ring), (4.0, 0.20, ring * 0.28), (10.0, 0.04, ring * 0.1)]
    return mix((modal(f, dur, p, attack=0.005, shimmer=0.0006), 0), (knock(f, 0.10), 0))[:, 0]


def marimba(f, dur=0.6, ring=0.16, hard=0.5):
    """A rosewood bar: a round, short, woody note."""
    p = [(1, 1.0, ring), (3.93, 0.22 * hard * 2, ring * 0.3), (9.2, 0.06 * hard * 2, ring * 0.12)]
    return mix((modal(f, dur, p, attack=0.002, shimmer=0.0003), 0), (knock(f, 0.25 * hard * 2, 0.006), 0))[:, 0]


def kalimba(f, dur=1.2, ring=0.45):
    """A thumb piano tine: a clear note with a tiny metallic tick in front."""
    p = [(1, 1.0, ring), (2.0, 0.10, ring * 0.5), (5.42, 0.22, 0.035), (8.93, 0.07, 0.018)]
    return mix((modal(f, dur, p, attack=0.002, shimmer=0.0005), 0), (knock(f * 1.5, 0.14, 0.004), 0))[:, 0]


def epiano(f, dur=2.2, ring=1.0):
    """An electric piano tine: warm, slightly bell-like at the start (FM)."""
    t = t_(dur)
    index = 1.1 * np.exp(-t / 0.22) + 0.12
    body = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * f * t))
    tine = 0.07 * np.sin(2 * np.pi * f * 13.9 * t) * np.exp(-t / 0.02) if f * 13.9 < 9500 else 0
    return (body * np.exp(-t / ring) + tine) * rise(t, 0.004)


def pad(f, dur, attack=0.7, release=1.2):
    """Held warmth: a few voices slightly apart, swelling in and letting go."""
    t = t_(dur)
    out = np.zeros_like(t)
    for cents in (-7, -2, 3, 8):
        ff = f * 2 ** (cents / 1200)
        ph = rng.uniform(0, 2 * np.pi)
        out += np.sin(2 * np.pi * ff * t + ph) + 0.28 * np.sin(2 * np.pi * 2 * ff * t + ph * 1.7) + 0.09 * np.sin(2 * np.pi * 3 * ff * t + ph * 0.6)
    env = rise(t, attack) * np.where(t > dur - release, 0.5 + 0.5 * np.cos(np.pi * np.clip((t - (dur - release)) / release, 0, 1)), 1.0)
    return out / 4 * env


def string(f, dur=1.4, bright=0.45):
    """A plucked nylon string (Karplus-Strong, the loop darkening as it rings)."""
    p = int(round(SR / f))
    buf = shape(rng.uniform(-1, 1, p * 8), hi=1500 + 6000 * bright)[p * 3:p * 4].copy()
    buf -= buf.mean()
    n = int(dur * SR)
    out = np.empty(n)
    keep = 0.9965
    for i in range(0, n, p):
        m = min(p, n - i)
        out[i:i + m] = buf[:m]
        buf = keep * (0.5 * buf + 0.5 * np.roll(buf, -1))
    t = t_(dur)
    return out * rise(t, 0.0015)


def bubble(f, dur=0.16, ring=0.035, lift=5.0):
    """A drop meeting water: a note that climbs as it fades."""
    t = t_(dur)
    ph = 2 * np.pi * f * (t + 0.5 * lift * t * t)
    return np.sin(ph) * np.exp(-t / ring) * rise(t, 0.004)


def air(dur, lo, hi):
    """A breath: noise let through a window that opens and closes."""
    t = t_(dur)
    return shape(noise(dur), lo=lo, hi=hi) * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2


# -------------------------------------------------------------------- room
def room(x, t60=1.3, wet=0.25, predelay=0.012, dark=3500.0):
    """A smooth room: the sound convolved with stereo noise that fades out,
    its highs fading soonest. Dense from the first instant, so nothing rings."""
    x = x if x.ndim == 2 else stereo(x)
    n = int((t60 * 1.15) * SR)
    t = np.arange(n) / SR
    ir = np.zeros((n, 2))
    for ch in range(2):
        w = rng.standard_normal(n)
        low = shape(w, lo=180, hi=dark)                      # body: full length
        high = w - shape(w, hi=dark)                         # air: gone in a third of the time
        ir[:, ch] = low * 10 ** (-3 * t / t60) + 0.5 * high * 10 ** (-3 * t / (t60 * 0.35))
    ir *= rise(t, 0.006)[:, None]
    ir /= np.sqrt((ir ** 2).sum(axis=0)).mean()
    pd = int(predelay * SR)
    m = len(x) + n + pd
    size = 1 << (m - 1).bit_length()
    out = np.zeros((m, 2))
    out[:len(x)] += x
    for ch in range(2):
        tail = np.fft.irfft(np.fft.rfft(x[:, ch], size) * np.fft.rfft(ir[:, ch], size), size)[:len(x) + n]
        out[pd:pd + len(tail), ch] += tail * wet
    return out


# ----------------------------------------------------------------- output
def write_wav(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).round().astype("<i2").tobytes())


def momentary_max(path):
    """The loudest momentary loudness (EBU R128, 400 ms), as ffmpeg measures it."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-loglevel", "verbose", "-i", path,
                        "-af", "apad=pad_dur=0.5,ebur128", "-f", "null", "-"], capture_output=True, text=True)
    vals = [float(v) for v in re.findall(r"\bM:\s*(-?[0-9.]+)", r.stderr)]
    return max(vals) if vals else -70.0


# Sounds the shell plays itself (QtMultimedia SoundEffect, which needs WAV):
# the volume pop must sound the moment a key is pressed.
WAV = {"volume"}


def save(name, x, level=-18.0, ceiling=0.84, top=9000.0):
    """Tidy the ends, soften the very top, then bring the sound to its loudness
    (`level`: its loudest moment, LUFS) without peaks over about -1.5 dBFS."""
    x = shape(x, lo=45, hi=top, slope=1.5)
    peak = np.abs(x).max()
    live = np.nonzero(np.abs(x).max(axis=1) > peak * 0.0015)[0]
    x = x[:live[-1] + 1]
    fi, fo = int(0.002 * SR), min(int(0.12 * SR), len(x) // 3)
    x[:fi] *= np.linspace(0, 1, fi)[:, None]
    x[-fo:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fo)))[:, None]
    x = x / np.abs(x).max() * 0.5
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    for _ in range(4):
        write_wav(tmp, x)
        err = level - momentary_max(tmp)
        if abs(err) < 0.3:
            break
        x = x * 10 ** (err / 20)
        if np.abs(x).max() > ceiling:      # a sharp sound: round its tips off, gently
            x = ceiling * np.tanh(x / ceiling)
    write_wav(tmp, x)
    got = momentary_max(tmp)
    dst = os.path.join(OUT, name + ".oga")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "7", dst], check=True)
    if name in WAV:   # also kept as WAV, for the shell to hold decoded (it plays at once)
        shutil.copyfile(tmp, os.path.join(OUT, name + ".wav"))
    os.unlink(tmp)
    print(f"{name}.oga  {len(x) / SR:.2f}s  {got:.1f} LUFS (target {level})  peak {np.abs(x).max():.2f}")


# ------------------------------------------------------------------ sounds
def alerts():
    # Glint: one tap on a glass, with the bar of a vibraphone under it for body.
    save("alert-glint", room(mix((glass(E6, 1.4, 0.55), 0, 0.8, 0.15), (vibes(E5, 1.4, 0.7), 0, 0.5, -0.15)), 1.2, 0.26))
    # Drop: a drop in still water, and its small echo.
    save("alert-drop", room(mix((bubble(540, lift=5.5), 0, 1.0, -0.1), (bubble(790, 0.12, 0.025, 6.5), 0.11, 0.35, 0.25),
                                (shape(marimba(D4, 0.3, 0.05, 0.2), hi=900), 0, 0.22)), 0.9, 0.3), top=6000)
    # Chime: two vibraphone notes, up a fifth, left to ring together.
    save("alert-chime", room(mix((vibes(D5, 2.0, 1.0), 0, 1.0, -0.25), (vibes(A5, 2.0, 1.1), 0.14, 0.85, 0.25)), 1.6, 0.28))
    # Bell: a small singing bowl.
    save("alert-bell", room(mix((bowl(A4), 0, 1.0), (knock(A4, 0.2, 0.01), 0, 1.0)), 1.8, 0.22))
    # Pebble: a rosewood bar, one round knock.
    save("alert-pebble", room(mix((marimba(A5, 0.4, 0.07, 0.7), 0, 1.0, 0.1), (marimba(A4, 0.4, 0.09, 0.3), 0, 0.5, -0.1)), 0.6, 0.2))
    # Bubble: two bubbles, the second higher.
    save("alert-bubble", room(mix((bubble(430, 0.15, 0.032, 6.0), 0, 1.0, -0.2), (bubble(640, 0.17, 0.038, 6.0), 0.095, 0.9, 0.2)), 0.8, 0.28), top=6000)
    # Breeze: a breath of air carrying a soft fifth.
    b = mix((air(0.9, 500, 2600), 0, 0.22, -0.3), (air(0.9, 900, 4200), 0.08, 0.14, 0.3),
            (pad(D5, 1.0, 0.3, 0.6), 0.05, 0.5, -0.2), (pad(A5, 1.0, 0.35, 0.6), 0.1, 0.32, 0.2))
    save("alert-breeze", room(b, 1.6, 0.35), top=7000)
    # Pluck: a harp string, and the octave above answering quietly.
    save("alert-pluck", room(mix((string(D5, 1.4, 0.5), 0, 1.0, -0.15), (string(D6, 1.0, 0.35), 0.006, 0.3, 0.2)), 1.3, 0.26))


def system():
    # Startup: a warm D major chord that swells, three electric-piano notes
    # climbing through it, and a little glass on top as it opens up.
    dur = 3.6
    parts = []
    for k, (f, g) in enumerate([(D3, 0.34), (A3, 0.44), (D4, 0.5), (FS4, 0.42), (A4, 0.36), (E5, 0.22)]):
        parts.append((pad(f, dur, 0.5 + 0.08 * k, 1.8), 0, g, (-1) ** k * 0.35))
    for f, at, g, pan in [(D4, 0.0, 0.5, -0.25), (A4, 0.17, 0.46, 0.0), (FS5, 0.34, 0.42, 0.25)]:
        parts.append((epiano(f, 3.0, 1.3), at, g, pan))
    parts.append((glass(A5, 2.0, 0.9), 0.52, 0.16, 0.3))
    parts.append((glass(E6, 2.0, 0.8), 0.60, 0.10, -0.3))
    save("startup", room(shape(mix(*parts), hi=5200), 2.4, 0.34, 0.02), level=-19, top=7000)

    # Volume: the lightest tick of a wooden bar.
    save("volume", room(marimba(A5, 0.2, 0.028, 0.35), 0.35, 0.1), level=-23, top=6500)

    # Screenshot: a camera shutter, open and shut.
    def blade(lo, hi, body, length):
        t = t_(0.06)
        return shape(noise(0.06) * np.exp(-t / length), lo=lo, hi=hi) + 0.12 * np.sin(2 * np.pi * body * t) * np.exp(-t / (length * 2.5)) * rise(t, 0.0008)
    sh = mix((blade(1400, 6500, 310, 0.005), 0, 1.0, -0.1), (blade(900, 4800, 240, 0.008), 0.078, 0.85, 0.1))
    save("screenshot", room(sh, 0.4, 0.12), level=-20, top=8000)

    # Trash: a soft sweep down, and something light landing.
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    w = noise(0.34)
    sweep = np.zeros(n)
    bands = [(2600, 5200), (1500, 3000), (800, 1700), (420, 950)]
    for k, (lo, hi) in enumerate(bands):           # the window slides down band by band
        c = (k + 0.5) / len(bands) * 0.30
        sweep += shape(w, lo=lo, hi=hi) * np.exp(-((t - c) / 0.075) ** 2)
    tt = t_(0.25)
    thud = np.sin(2 * np.pi * (96 * tt + 40 * 0.05 * (1 - np.exp(-tt / 0.05)))) * np.exp(-tt / 0.06) * rise(tt, 0.004)
    tr = mix((sweep, 0, 0.5, 0.0), (thud, 0.27, 1.0), (shape(marimba(D4, 0.2, 0.04, 0.3), hi=1200), 0.27, 0.5))
    save("trash", room(tr, 0.5, 0.14), level=-20, top=7000)

    # Power: two warm notes rising a fifth as the charger goes in.
    save("power", room(mix((epiano(A4, 1.6, 0.7), 0, 1.0, -0.2), (epiano(E5, 1.8, 0.8), 0.12, 0.9, 0.2)), 1.3, 0.26), level=-20, top=7000)

    # Error: two low, muted knocks stepping down. Clear, never harsh.
    e = mix((marimba(FS4, 0.35, 0.10, 0.25), 0, 1.0, -0.1), (marimba(D4, 0.4, 0.13, 0.25), 0.13, 1.0, 0.1))
    save("error", room(shape(e, hi=2600), 0.5, 0.14), level=-20, top=5000)

    # Done: three kalimba notes going up the chord, the last one left to ring.
    dn = mix((kalimba(D5, 0.8, 0.28), 0, 0.85, -0.25), (kalimba(FS5, 0.8, 0.32), 0.085, 0.9, 0.0), (kalimba(A5, 1.3, 0.55), 0.17, 1.0, 0.25))
    save("done", room(dn, 1.2, 0.26), level=-20)


if __name__ == "__main__":
    which = sys.argv[1:] or ["alerts", "system"]
    if "alerts" in which:
        alerts()
    if "system" in which:
        system()
