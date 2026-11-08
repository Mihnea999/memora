#!/usr/bin/env python3
"""Synthesises Memora's system sounds into system/sounds/*.oga.

Everything is made here from sine partials, filtered noise and a small room
reverb (no samples), in the spirit of a Mac's sounds: short, soft, glassy.
Run: python3 tools/sounds.py   (needs ffmpeg for the Ogg Vorbis files)
"""
import math, os, random, struct, subprocess, sys, tempfile, wave

SR = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "system", "sounds")
random.seed(7)


def silence(sec):
    return [0.0] * int(sec * SR)


def mix(dst, src, at=0.0, gain=1.0):
    o = int(at * SR)
    if len(dst) < o + len(src):
        dst.extend([0.0] * (o + len(src) - len(dst)))
    for i, v in enumerate(src):
        dst[o + i] += v * gain
    return dst


def bell(freq, dur, partials, attack=0.002, glide=0.0):
    """Sum of decaying sine partials: (ratio, amplitude, decay seconds)."""
    n = int(dur * SR)
    out = [0.0] * n
    for ratio, amp, decay in partials:
        f = freq * ratio
        if f > SR / 2.2:
            continue
        ph = 0.0
        for i in range(n):
            t = i / SR
            ff = f * (1 + glide * math.exp(-t / 0.03)) if glide else f
            ph += 2 * math.pi * ff / SR
            env = min(1.0, t / attack) * math.exp(-t / decay)
            out[i] += amp * env * math.sin(ph)
    return out


def sweep(f0, f1, dur, decay, attack=0.002, curve=0.02):
    """A sine whose pitch slides from f0 to f1 (exponentially, time constant curve)."""
    n = int(dur * SR)
    out, ph = [0.0] * n, 0.0
    for i in range(n):
        t = i / SR
        f = f1 + (f0 - f1) * math.exp(-t / curve)
        ph += 2 * math.pi * f / SR
        out[i] = min(1.0, t / attack) * math.exp(-t / decay) * math.sin(ph)
    return out


def noise(dur, decay, attack=0.001):
    n = int(dur * SR)
    return [min(1.0, (i / SR) / attack) * math.exp(-(i / SR) / decay) * (random.random() * 2 - 1) for i in range(n)]


def lowpass(x, fc):
    a = 1 - math.exp(-2 * math.pi * fc / SR)
    y, s = [], 0.0
    for v in x:
        s += a * (v - s)
        y.append(s)
    return y


def highpass(x, fc):
    lp = lowpass(x, fc)
    return [a - b for a, b in zip(x, lp)]


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def pluck(freq, dur, bright=0.5):
    """Karplus-Strong string."""
    p = int(SR / freq)
    buf = [random.random() * 2 - 1 for _ in range(p)]
    buf = lowpass(buf, 2000 + 8000 * bright)
    out = []
    for i in range(int(dur * SR)):
        v = buf[i % p]
        nxt = buf[(i + 1) % p]
        buf[i % p] = 0.996 * 0.5 * (v + nxt)
        out.append(v)
    return out


def reverb(x, wet=0.25, room=0.82, tail=1.2):
    """A small Schroeder room: four combs into two allpasses."""
    x = x + [0.0] * int(tail * SR)
    combs = [int(d * SR / 44100) for d in (1557, 1617, 1491, 1422)]
    wetsig = [0.0] * len(x)
    for d in combs:
        buf = [0.0] * d
        lp, j = 0.0, 0
        for i, v in enumerate(x):
            o = buf[j]
            lp = o * 0.6 + lp * 0.4
            buf[j] = v + lp * room
            wetsig[i] += o
            j = (j + 1) % d
    for d in (int(556 * SR / 44100), int(225 * SR / 44100)):
        buf = [0.0] * d
        j = 0
        for i, v in enumerate(wetsig):
            o = buf[j]
            buf[j] = v + o * 0.5
            wetsig[i] = o - v
            j = (j + 1) % d
    return [a + b * wet / 4 for a, b in zip(x, wetsig)]


def finish(x, peak=0.7, fade=0.02):
    # trim the silent tail, fade the end, normalise
    m = max(abs(v) for v in x) or 1
    end = len(x)
    while end > 0 and abs(x[end - 1]) < m * 0.001:
        end -= 1
    x = x[:end]
    nf = int(fade * SR)
    for i in range(min(nf, len(x))):
        x[len(x) - 1 - i] *= i / nf
    return [v * peak / m for v in x]


def save(name, x, peak=0.7):
    x = finish(x, peak)
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        tmp = f.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in x))
    dst = os.path.join(OUT, name + ".oga")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "6", dst], check=True)
    os.unlink(tmp)
    print(f"{name}.oga  {len(x) / SR:.2f}s")


GLASS = [(1, 1, 0.5), (2.76, 0.35, 0.18), (5.40, 0.15, 0.08), (8.93, 0.06, 0.04)]
BELL = [(0.5, 0.25, 1.4), (1, 1, 1.1), (2.0, 0.45, 0.6), (2.4, 0.3, 0.5), (3.0, 0.2, 0.35), (4.5, 0.12, 0.2), (5.33, 0.08, 0.15)]
CHIME = [(1, 1, 0.7), (3.0, 0.25, 0.25), (4.1, 0.12, 0.12)]


def alerts():
    # Glint: a struck glass, high and bright
    save("alert-glint", reverb(bell(1568, 1.2, GLASS), 0.3))
    # Drop: a drop of water
    d = sweep(520, 1450, 0.25, 0.06, curve=0.025)
    save("alert-drop", reverb(d, 0.35))
    # Chime: two glassy notes going up a fifth
    c = mix(bell(1318.5, 1.0, CHIME), bell(1975.5, 1.2, CHIME), 0.11, 0.8)
    save("alert-chime", reverb(c, 0.3))
    # Bell: a small bell, longer ring
    save("alert-bell", reverb(bell(880, 2.2, BELL), 0.25, tail=1.5))
    # Pebble: a short wooden tock
    t = mix(bell(740, 0.25, [(1, 1, 0.045), (2.3, 0.4, 0.02), (4.1, 0.2, 0.01)]), bandpass(noise(0.03, 0.004), 1500, 6000), 0, 0.5)
    save("alert-pebble", reverb(t, 0.18, tail=0.5))
    # Bubble: two rising blips
    b = mix(sweep(380, 760, 0.12, 0.04, curve=0.03), sweep(560, 1100, 0.14, 0.05, curve=0.03), 0.085, 0.8)
    save("alert-bubble", reverb(b, 0.3))
    # Breeze: a soft breath of air with a hint of tone
    n = int(0.9 * SR)
    air = bandpass([random.random() * 2 - 1 for _ in range(n)], 500, 2400)
    for i in range(n):
        t = i / SR
        air[i] *= math.sin(math.pi * min(1.0, t / 0.9)) ** 2
    air = mix(air, bell(660, 0.9, [(1, 0.25, 0.4)], attack=0.25))
    save("alert-breeze", reverb(air, 0.3))
    # Pluck: a plucked string
    save("alert-pluck", reverb(pluck(784, 1.0, 0.6), 0.25))


def system():
    # Startup: a warm, wide major chord that swells and rings out
    chord = [82.41, 123.47, 164.81, 207.65, 246.94, 329.63, 369.99, 415.30]  # E major add 9, spread
    s = silence(4.5)
    for k, f in enumerate(chord):
        for det in (-0.6, 0.6):
            harm = [(h, 1 / h ** 1.3, 3.6 / (1 + 0.35 * h)) for h in range(1, 9)]
            mix(s, bell(f * (1 + det / 1200), 4.5, harm, attack=0.06), 0.004 * k, 0.5 / (1 + 0.15 * k))
    s = lowpass(s, 3200)
    save("startup", reverb(s, 0.35, room=0.86, tail=1.8), peak=0.6)

    # Volume: a short, soft pop
    v = mix(sweep(1500, 950, 0.07, 0.018, attack=0.0008, curve=0.008), bandpass(noise(0.01, 0.002), 2000, 8000), 0, 0.15)
    save("volume", reverb(v, 0.12, tail=0.25), peak=0.55)

    # Screenshot: a camera shutter (click, clack)
    def click(lo, hi, dec):
        return mix(bandpass(noise(0.05, dec), lo, hi), bell(lo * 1.6, 0.05, [(1, 0.4, dec)]))
    sh = mix(click(1800, 7000, 0.006), click(1200, 5000, 0.009), 0.085, 0.8)
    save("screenshot", reverb(sh, 0.15, tail=0.3))

    # Trash: paper being crumpled and dropped in
    tr = silence(0.55)
    t = 0.0
    while t < 0.42:
        dec = random.uniform(0.003, 0.012)
        mix(tr, bandpass(noise(0.04, dec), random.uniform(800, 2500), random.uniform(4000, 9000)), t, random.uniform(0.3, 1.0) * (1 - t))
        t += random.uniform(0.012, 0.04)
    mix(tr, lowpass(noise(0.12, 0.03), 900), 0.42, 0.8)
    save("trash", reverb(tr, 0.15, tail=0.4))

    # Power: plugged into a charger, a soft glassy rise
    pw = mix(bell(1046.5, 0.8, CHIME, attack=0.004), bell(1568, 1.0, CHIME, attack=0.004), 0.09, 0.85)
    save("power", reverb(pw, 0.3), peak=0.55)

    # Error: a low, muted knock (wrong password, something not allowed)
    e = mix(bell(196, 0.4, [(1, 1, 0.09), (1.5, 0.5, 0.06), (2.02, 0.3, 0.04)], attack=0.003), lowpass(noise(0.02, 0.004), 1200), 0, 0.3)
    save("error", reverb(e, 0.15, tail=0.3))

    # Done: something finished (a download, an update), two quick ascending notes
    dn = mix(bell(1174.7, 0.6, CHIME), bell(1760, 0.8, CHIME), 0.07, 0.8)
    save("done", reverb(dn, 0.25), peak=0.55)


if __name__ == "__main__":
    which = sys.argv[1:] or ["alerts", "system"]
    if "alerts" in which:
        alerts()
    if "system" in which:
        system()
