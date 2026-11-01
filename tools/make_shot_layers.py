#!/usr/bin/env python3
"""Builds the layered shot sets in addons/dot_audio/stock/shots/ from CC0 recordings.

    python3 -I tools/make_shot_layers.py [--extra DIR]   (DIR holds the downloads named in EXTRA)

Per weapon class: `attack_N` (the crack), `body_N` (the report), `tail_<size>_N` for small, medium, large and hall (the
same shot's late energy convolved with a synthetic room, so no impulse response of unclear licence is involved),
`tail_outdoor_N` (the recording's own late part) and `far_N` (the shot as heard from far off). The three near layers are
a complementary split of one recording (they sum back to it), which is why one tail replaces another instead of adding.
Sources: the stock `<class>_fire_N` files (The Free Firearm Sound Library, CC0) plus the extra downloads in EXTRA.
"""
import argparse
import os
import subprocess

import numpy as np
from scipy import signal

RATE = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock")
WEAPONS = os.path.join(ROOT, "weapons")
OUT = os.path.join(ROOT, "shots")

# class -> extra close-mic recordings (downloaded file names), after the stock fire files
EXTRA = {
    "light": ["kurt/22%20Pistol.wav", "eld/Impacts/Pistol 1.wav", "eld/Impacts/Pistol 3.wav"],
    "magnum": ["kurt/22%20Magnum.wav", "eld/Impacts/Pistol 2.wav"],
    "shotgun": ["eld/Impacts/Shotgun 1.wav", "eld/Impacts/Shotgun 2.wav", "eld/Impacts/Shotgun 3.wav"],
    "sniper": ["kurt/Unkown.wav"],
}
CLASSES = ["light", "smg", "magnum", "rifle", "heavy", "sniper", "shotgun"]
MAX_VARIANTS = 6
# tail class -> (RT60 s, damping low-pass Hz, level relative to the source's tail peak, pre-delay ms)
ROOMS = {
    "small": (0.22, 5500.0, 0.55, 3.0),
    "medium": (0.55, 4200.0, 0.50, 9.0),
    "large": (1.30, 3400.0, 0.45, 22.0),
    "hall": (2.80, 2600.0, 0.42, 48.0),
}
ATTACK_MS, BODY_MS = 45.0, 420.0


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32).astype(np.float64).copy()
    x -= np.mean(x)
    return x


def trim(x):
    """Starts the recording at the shot, and keeps at most 1.6 s of it."""
    peak = np.max(np.abs(x))
    on = int(np.argmax(np.abs(x) > 0.12 * peak))
    on = max(on - int(0.002 * RATE), 0)
    x = x[on: on + int(1.6 * RATE)]
    f = int(0.2 * RATE)
    x[-f:] *= np.linspace(1, 0, f) ** 2
    return x


def ramp(n, start, end):
    t = np.clip((np.arange(n) - start) / max(end - start, 1), 0.0, 1.0)
    return 0.5 - 0.5 * np.cos(np.pi * t)  # 0 -> 1


def split(x):
    n = len(x)
    a_end = int(ATTACK_MS / 1000 * RATE)
    b_end = int(BODY_MS / 1000 * RATE)
    leave_a = ramp(n, a_end // 2, a_end)  # 0 -> 1 as the attack ends
    leave_b = ramp(n, b_end // 2, b_end)
    attack = x * (1.0 - leave_a)
    body = x * leave_a * (1.0 - leave_b)
    late = x * leave_b
    return attack[: a_end + 1], body[: b_end + 1], late[b_end // 2:]


def room_ir(rt60, damp, seed, pre_ms):
    rng = np.random.default_rng(seed)
    n = int(min(rt60 * 1.1, 3.2) * RATE)
    t = np.arange(n) / RATE
    ir = rng.standard_normal(n) * 10 ** (-3.0 * t / rt60)  # -60 dB at rt60
    b, a = signal.butter(2, damp / (RATE / 2), "low")
    ir = signal.lfilter(b, a, ir)
    ir[0:] *= ramp(n, 0, int(0.004 * RATE))
    ir = np.concatenate([np.zeros(int(pre_ms / 1000 * RATE)), ir])
    return ir / np.sqrt(np.sum(ir ** 2))


def tail_for(room, late, body, seed):
    rt60, damp, rel, pre = ROOMS[room]
    drive = np.concatenate([body[int(0.05 * RATE):], late])
    y = signal.fftconvolve(drive, room_ir(rt60, damp, seed, pre))
    y = y[: int((rt60 * 1.1 + 0.2) * RATE)]
    ref = np.max(np.abs(late)) if np.max(np.abs(late)) > 0 else np.max(np.abs(body)) * 0.2
    y *= rel * max(ref, 0.04) / (np.max(np.abs(y)) + 1e-9)
    f = int(0.08 * RATE)
    y[-f:] *= np.linspace(1, 0, f) ** 2
    return y


def far_for(x, seed):
    """A shot heard from far off: no crack, the top gone, smeared by the air and the ground."""
    b, a = signal.butter(3, 2200.0 / (RATE / 2), "low")
    y = signal.lfilter(b, a, x)
    rng = np.random.default_rng(seed)
    smear = rng.standard_normal(int(0.03 * RATE)) * np.exp(-np.arange(int(0.03 * RATE)) / (0.008 * RATE))
    smear[0] += 2.0
    y = signal.fftconvolve(y, smear / np.sqrt(np.sum(smear ** 2)))[: len(x)]
    y *= ramp(len(y), 0, int(0.012 * RATE))
    return y


def write(path, y, peak_db):
    y = y - np.mean(y)
    y *= 10 ** (peak_db / 20) / (np.max(np.abs(y)) + 1e-9)
    raw = (np.clip(y, -1, 1) * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "3", path], input=raw, check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--extra", default="/tmp/claude-1000/dl")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for cls in CLASSES:
        sources = []
        i = 0
        while os.path.exists(os.path.join(WEAPONS, "%s_fire_%d.ogg" % (cls, i))):
            sources.append(os.path.join(WEAPONS, "%s_fire_%d.ogg" % (cls, i)))
            i += 1
        for extra in EXTRA.get(cls, []):
            p = os.path.join(args.extra, extra)
            if os.path.exists(p):
                sources.append(p)
        extras = [os.path.join(args.extra, e) for e in EXTRA.get(cls, []) if os.path.exists(os.path.join(args.extra, e))]
        stock = [p for p in sources if p not in extras]
        sources = (extras + stock)[:MAX_VARIANTS]
        folder = os.path.join(OUT, cls)
        os.makedirs(folder, exist_ok=True)
        # the recordings were levelled per class by make_weapon_stock.py; keep that level for the sum of the layers
        for n, src in enumerate(sources):
            x = trim(load(src))
            x /= np.max(np.abs(x)) + 1e-9
            peak = 20 * np.log10(0.89)
            attack, body, late = split(x)
            gain = 10 ** (peak / 20)
            write(os.path.join(folder, "attack_%d.ogg" % n), attack * gain, peak)
            write(os.path.join(folder, "body_%d.ogg" % n), body * gain, peak)
            write(os.path.join(folder, "tail_outdoor_%d.ogg" % n), late * gain, peak - 14.0)
            for room in ROOMS:
                write(os.path.join(folder, "tail_%s_%d.ogg" % (room, n)), tail_for(room, late, body, 1000 + n) * gain,
                      peak - 12.0)
            write(os.path.join(folder, "far_%d.ogg" % n), far_for(x, 7 + n) * gain, peak - 6.0)
        print(cls, len(sources), "variants")
    # the suppressed pistol: the stock's derived report is the body; no crack, no tail
    folder = os.path.join(OUT, "suppressed")
    os.makedirs(folder, exist_ok=True)
    for n in range(4):
        y = load(os.path.join(WEAPONS, "suppressed_fire_%d.ogg" % n))
        write(os.path.join(folder, "body_%d.ogg" % n), y, -9.0)
        write(os.path.join(folder, "far_%d.ogg" % n), far_for(y, 31 + n), -18.0)
    print("suppressed 4 variants")


main()
