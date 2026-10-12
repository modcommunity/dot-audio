#!/usr/bin/env python3
"""Generates dot-audio's stock ambience beds: seamless stereo loops made of arithmetic.

    python3 -I tools/make_ambience.py [name ...]      # all of them by default

Every bed is synthesised here from a fixed seed, so the source of each .ogg is this file and
the output is ours to license (CC0, like the Kenney footsteps beside it). No recording, no
third-party sample. Each bed is normalised to BED_LUFS integrated with ffmpeg's EBU R128 meter,
which is what lets a game play any bed at one level (docs/loudness.md).

Why synthesised: Kenney's CC0 audio packs have no ambience at all, and a bed is mostly
filtered noise with sparse events, which is exactly what arithmetic does well.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal

RATE = 44100
SECONDS = 32.0
# Under a game's mix by about seven loudness units at the family target (-17 LUFS).
BED_LUFS = -24.0
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock", "ambience")
XFADE = 2.0


def n(sec):
    return int(sec * RATE)


TOTAL = n(SECONDS + XFADE)


def noise(rng, kind="white", length=TOTAL):
    w = rng.standard_normal(length)
    if kind == "white":
        return w
    spec = np.fft.rfft(w)
    f = np.fft.rfftfreq(length, 1.0 / RATE)
    f[0] = f[1]
    if kind == "pink":
        spec /= np.sqrt(f)
    elif kind == "brown":
        spec /= f
    out = np.fft.irfft(spec, length)
    return out / (np.std(out) + 1e-12)


def lp(x, hz, order=2):
    b, a = signal.butter(order, hz / (RATE / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, hz, order=2):
    b, a = signal.butter(order, hz / (RATE / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (RATE / 2), hi / (RATE / 2)], "band")
    return signal.lfilter(b, a, x)


def smooth_lfo(rng, rate_hz, length=TOTAL, lo=0.0, hi=1.0):
    """A random curve that wanders at about rate_hz, between lo and hi."""
    points = max(4, int(length / RATE * rate_hz) + 4)
    knots = rng.uniform(0.0, 1.0, points)
    xs = np.linspace(0, length, points)
    from scipy.interpolate import CubicSpline
    curve = CubicSpline(xs, knots)(np.arange(length))
    curve = np.clip(curve, 0.0, 1.0)
    return lo + (hi - lo) * curve


def env(length, attack, release):
    a = max(1, n(attack))
    r = max(1, n(release))
    e = np.ones(length)
    e[:a] = np.linspace(0, 1, a) if a <= length else np.linspace(0, 1, length)
    if r < length:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def place(bed, ev, at, pan=0.0):
    """Adds a mono event to a stereo bed at sample `at`, wrapping round the loop."""
    gl = np.cos((pan + 1) * np.pi / 4)
    gr = np.sin((pan + 1) * np.pi / 4)
    idx = (np.arange(len(ev)) + at) % TOTAL
    np.add.at(bed[0], idx, ev * gl)
    np.add.at(bed[1], idx, ev * gr)


def stereo(rng, kind, lo=None, hi=None, width=0.6):
    """A noise bed with some width: a shared part and a decorrelated part per side."""
    mid = noise(rng, kind)
    sides = [noise(rng, kind), noise(rng, kind)]
    out = []
    for s in sides:
        x = (1 - width) * mid + width * s
        if lo:
            x = hp(x, lo)
        if hi:
            x = lp(x, hi)
        out.append(x)
    return np.array(out)


def chirp(rng):
    """One small bird call: a few fast FM sweeps."""
    parts = []
    base = rng.uniform(2600, 4800)
    for _ in range(rng.integers(2, 6)):
        d = rng.uniform(0.04, 0.12)
        t = np.arange(n(d)) / RATE
        f0 = base * rng.uniform(0.8, 1.25)
        f1 = f0 * rng.uniform(0.6, 1.6)
        f = np.linspace(f0, f1, len(t)) + 180 * np.sin(2 * np.pi * rng.uniform(25, 60) * t)
        ph = 2 * np.pi * np.cumsum(f) / RATE
        parts.append(np.sin(ph) * np.hanning(len(t)))
        parts.append(np.zeros(n(rng.uniform(0.02, 0.08))))
    return np.concatenate(parts)


def cricket(rng):
    """A cricket's phrase: a carrier gated in short bursts."""
    f = rng.uniform(4200, 5200)
    pulses = rng.integers(3, 7)
    rate = rng.uniform(22, 32)
    d = pulses / rate + 0.05
    t = np.arange(n(d)) / RATE
    gate = (np.sin(2 * np.pi * rate * t) > 0.3).astype(float)
    gate = lp(gate, 300)
    return np.sin(2 * np.pi * f * t) * gate * np.hanning(len(t)) ** 0.3


def creak(rng):
    """Old wood under weight: a resonant filtered click train gliding in pitch."""
    d = rng.uniform(0.5, 1.4)
    t = np.arange(n(d)) / RATE
    rate = np.linspace(rng.uniform(25, 60), rng.uniform(10, 40), len(t))
    clicks = (np.diff(np.floor(np.cumsum(rate) / RATE), prepend=0) > 0).astype(float)
    tone = bp(clicks * 4.0, 300, 1400, 2)
    return tone * env(len(t), 0.1, 0.3)


def knock(rng, lo=120, hi=400):
    d = 0.25
    t = np.arange(n(d)) / RATE
    f = rng.uniform(lo, hi)
    return np.sin(2 * np.pi * f * t) * np.exp(-t * 28) + 0.3 * bp(rng.standard_normal(len(t)), 200, 2000) * np.exp(-t * 60)


def drip(rng):
    d = 0.18
    t = np.arange(n(d)) / RATE
    f0 = rng.uniform(900, 1800)
    f = f0 * (1 + 0.8 * np.exp(-t * 40))
    return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 35)


def clank(rng):
    d = 1.2
    t = np.arange(n(d)) / RATE
    out = np.zeros(len(t))
    for f in rng.uniform(300, 2400, 5):
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * np.exp(-t * rng.uniform(3, 9))
    return out * 0.3


def car_pass(rng):
    d = rng.uniform(4, 8)
    length = n(d)
    x = lp(noise(rng, "pink", length), rng.uniform(500, 900))
    hum = np.sin(2 * np.pi * np.cumsum(np.linspace(rng.uniform(70, 110), rng.uniform(55, 80), length)) / RATE)
    e = np.hanning(length) ** 2
    return (x + 0.5 * hum) * e


def horn(rng):
    d = rng.uniform(0.3, 0.7)
    t = np.arange(n(d)) / RATE
    f = rng.uniform(330, 440)
    x = signal.sawtooth(2 * np.pi * f * t) + signal.sawtooth(2 * np.pi * f * 1.26 * t)
    return lp(x, 1500) * env(len(t), 0.02, 0.1)


def scatter(rng, bed, make, count, gain, pan=0.8):
    for _ in range(count):
        ev = make(rng) * gain
        place(bed, ev, int(rng.integers(0, TOTAL)), float(rng.uniform(-pan, pan)))


# --- the beds ---------------------------------------------------------------

def bed_wind(rng):
    """Open and high: gusting wind with a moving whistle. Snow, mountains, rooftops."""
    b = stereo(rng, "brown", 40, 900, 0.7)
    gust = smooth_lfo(rng, 0.25, lo=0.25, hi=1.0)
    b *= gust
    whistle = stereo(rng, "white", None, None, 0.5)
    centre = smooth_lfo(rng, 0.15, lo=500, hi=1100)
    w = np.zeros_like(whistle)
    # A slowly moving resonance, filtered in blocks (a filter per sample is too slow).
    block = 4096
    for i in range(0, TOTAL, block):
        c = float(centre[i])
        b2, a2 = signal.iirpeak(c / (RATE / 2), 18)
        w[:, i:i + block] = signal.lfilter(b2, a2, whistle[:, i:i + block])
    b += 0.5 * w * gust ** 2
    return b


def bed_outdoor(rng):
    """Daytime outside: a soft breeze, leaves, and birds at a distance. Parks, fields, courses."""
    b = 0.6 * stereo(rng, "brown", 60, 700, 0.6) * smooth_lfo(rng, 0.2, lo=0.4, hi=1.0)
    leaves = stereo(rng, "white", 2500, 9000, 0.9) * smooth_lfo(rng, 0.4, lo=0.0, hi=1.0) ** 3
    b += 0.025 * leaves
    scatter(rng, b, chirp, 26, 0.18)
    return b


def bed_night(rng):
    """Outside after dark: crickets, a low breeze, the odd far-off bird."""
    b = 0.4 * stereo(rng, "brown", 50, 500, 0.6) * smooth_lfo(rng, 0.15, lo=0.4, hi=1.0)
    for _ in range(3):
        f_rng = np.random.default_rng(rng.integers(1 << 30))
        pan = float(rng.uniform(-0.9, 0.9))
        t = 0
        while t < TOTAL:
            ev = cricket(f_rng) * 0.12
            place(b, ev, t, pan)
            t += n(f_rng.uniform(0.35, 0.9))
    scatter(rng, b, chirp, 3, 0.05)
    return b


def bed_city(rng):
    """Streets: traffic rumble, cars passing, a distant horn."""
    b = stereo(rng, "pink", 30, 400, 0.4)
    b += 0.25 * stereo(rng, "pink", 400, 3000, 0.8) * smooth_lfo(rng, 0.3, lo=0.3, hi=1.0)
    scatter(rng, b, car_pass, 9, 1.2)
    scatter(rng, b, horn, 2, 0.08)
    return b


def bed_indoor(rng):
    """Inside a building: room tone, ventilation and mains hum. Halls, houses, shops."""
    b = 0.5 * stereo(rng, "brown", 60, 900, 0.5)
    t = np.arange(TOTAL) / RATE
    hum = 0.08 * (np.sin(2 * np.pi * 50 * t) + 0.5 * np.sin(2 * np.pi * 100 * t) + 0.25 * np.sin(2 * np.pi * 150 * t))
    hum *= smooth_lfo(rng, 0.1, lo=0.8, hi=1.0)
    b += hum
    b += 0.02 * stereo(rng, "pink", 800, 3000, 0.9)
    scatter(rng, b, lambda r: knock(r, 150, 300), 2, 0.05)
    return b


def bed_eerie(rng):
    """Something is wrong in this house: a beating drone, breath-like swells, creaks, a far knock."""
    t = np.arange(TOTAL) / RATE
    drone = (np.sin(2 * np.pi * 55.0 * t) + np.sin(2 * np.pi * 55.7 * t)
             + 0.6 * np.sin(2 * np.pi * 82.4 * t + 0.5 * np.sin(2 * np.pi * 0.07 * t))
             + 0.25 * np.sin(2 * np.pi * 116.5 * t))
    drone *= smooth_lfo(rng, 0.08, lo=0.5, hi=1.0)
    b = np.array([drone, np.roll(drone, n(0.013))]) * 0.4
    breath = stereo(rng, "pink", 200, 1200, 0.8) * smooth_lfo(rng, 0.18, lo=0.0, hi=1.0) ** 4
    b += 0.9 * breath
    # A dissonant high pair that swells now and then: the minor second nobody likes.
    swell = smooth_lfo(rng, 0.05, lo=0.0, hi=1.0) ** 6
    high = (np.sin(2 * np.pi * 740 * t) + np.sin(2 * np.pi * 784 * t)) * 0.05 * swell
    b += np.array([high, np.roll(high, n(0.021))])
    scatter(rng, b, creak, 6, 0.35, 0.9)
    scatter(rng, b, lambda r: knock(r, 70, 140), 3, 0.25, 0.9)
    return b


def bed_industrial(rng):
    """Machinery: a big hum, air, and metal settling somewhere. Arenas, works, courses of steel."""
    t = np.arange(TOTAL) / RATE
    hum = sum(np.sin(2 * np.pi * f * t) / k for k, f in enumerate([60, 120, 180, 241, 300], start=1))
    hum = hum * 0.25 * smooth_lfo(rng, 0.1, lo=0.8, hi=1.0)
    b = np.array([hum, hum]) + 0.6 * stereo(rng, "brown", 50, 1200, 0.6)
    b += 0.03 * stereo(rng, "pink", 2000, 7000, 0.9) * smooth_lfo(rng, 0.2, lo=0.2, hi=1.0)
    scatter(rng, b, clank, 7, 0.25)
    return b


def bed_cave(rng):
    """Under the ground: a deep rumble, water dripping, a long space. Sewers, tunnels, basements."""
    b = 0.8 * stereo(rng, "brown", 25, 200, 0.5) * smooth_lfo(rng, 0.1, lo=0.5, hi=1.0)
    for _ in range(40):
        ev = drip(rng) * 0.25
        # A drip in a big space comes back: three late copies.
        tail = np.zeros(len(ev) + n(0.6))
        tail[:len(ev)] += ev
        for k, delay in enumerate([0.11, 0.23, 0.41], start=1):
            tail[n(delay):n(delay) + len(ev)] += ev * (0.35 / k)
        place(b, tail, int(rng.integers(0, TOTAL)), float(rng.uniform(-0.8, 0.8)))
    return b


def bed_rain(rng):
    """Steady rain: dense small impacts over a hiss, and water running off something."""
    b = 0.7 * stereo(rng, "pink", 300, 9000, 0.9)
    drops = (rng.random((2, TOTAL)) < 0.0012).astype(float) * rng.uniform(0.2, 1.0, (2, TOTAL))
    b += 1.5 * np.array([bp(d, 1500, 7000) for d in drops])
    b += 0.3 * stereo(rng, "brown", 80, 600, 0.6)
    return b


BEDS = {
    "amb_wind": bed_wind,
    "amb_outdoor": bed_outdoor,
    "amb_night": bed_night,
    "amb_city": bed_city,
    "amb_indoor": bed_indoor,
    "amb_eerie": bed_eerie,
    "amb_industrial": bed_industrial,
    "amb_cave": bed_cave,
    "amb_rain": bed_rain,
}


def loop(b):
    """Folds the extra seconds over the start with an equal-power crossfade: a seamless loop."""
    L = n(SECONDS)
    x = n(XFADE)
    head = b[:, :x]
    tail = b[:, L:L + x]
    ramp = np.linspace(0, np.pi / 2, x)
    out = b[:, :L].copy()
    out[:, :x] = head * np.sin(ramp) + tail * np.cos(ramp)
    return out


def lufs(path):
    r = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    s = r[r.rfind("Summary:"):]
    for line in s.splitlines():
        line = line.strip()
        if line.startswith("I:"):
            return float(line.split()[1])
    raise RuntimeError("no loudness for " + path)


def write(name, b):
    from scipy.io import wavfile
    os.makedirs(OUT, exist_ok=True)
    b = b / (np.max(np.abs(b)) + 1e-12) * 0.5
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "raw.wav")
        wavfile.write(raw, RATE, (b.T * 32767).astype(np.int16))
        gain = BED_LUFS - lufs(raw)
        dst = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-af", "volume=%.2fdB" % gain,
                        "-c:a", "libvorbis", "-q:a", "0", dst], check=True)
        print("%-16s %6.1f LUFS  %s" % (name, lufs(dst), os.path.relpath(dst)))


def main():
    names = sys.argv[1:] or list(BEDS)
    for i, name in enumerate(sorted(BEDS)):
        if name not in names:
            continue
        rng = np.random.default_rng(1009 + i)
        write(name, loop(BEDS[name](rng)))


if __name__ == "__main__":
    main()
