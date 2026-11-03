#!/usr/bin/env python3
"""Builds the layered shot sets in addons/dot_audio/stock/shots/ from CC0 recordings.

    python3 -I tools/make_shot_layers.py [--extra DIR]   (DIR holds the downloads named in EXTRA)

Per weapon class: `attack_N` (the crack), `body_N` (the report), `tail_<size>_N` for small, medium, large and hall (the
same shot convolved with a synthetic room, so no impulse response of unclear licence is involved),
`tail_outdoor_N` (almost no tail, a distant slap-back instead) and `far_N` (the shot as heard from far off). The three near layers are
a complementary split of one recording (they sum back to it), which is why the tails crossfade (equal power) rather than add.
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
CLASSES = ["light", "smg", "magnum", "rifle", "heavy", "sniper", "shotgun", "launcher", "minigun", "beam"]
MAX_VARIANTS = 6
# tail class -> (RT60 s, damping low-pass Hz, pre-delay ms, drive ms (how much of the shot excites the room), peak dB)
# A tight room rings off fast so its drive is short and its tail close to the attack; a hall rings on the shot's own
# long tail at lower levels, and an open field has almost none (its energy is the slap-back below).
ROOMS = {
    "small": (0.13, 7000.0, 1.0, 110.0, -4.0),
    "medium": (0.45, 5200.0, 7.0, 260.0, -9.0),
    "large": (1.20, 3600.0, 22.0, 520.0, -11.0),
    "hall": (2.70, 2600.0, 48.0, 1600.0, -12.5),
}
# class -> (reflection spacing range ms, reflection count, comb delay ms, comb feedback): flutter and colouration
FLUTTER = {
    "small": ((2.2, 5.5), 22, 3.4, 0.62),
    "medium": ((6.0, 16.0), 9, 8.5, 0.28),
    "large": ((14.0, 34.0), 5, 0.0, 0.0),
    "hall": ((30.0, 70.0), 4, 0.0, 0.0),
}
OUTDOOR_DB = -17.0
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
    f = min(int(0.2 * RATE), len(x) // 2)
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


def room_ir(room, seed):
    rt60, damp, pre_ms, _drive, _db = ROOMS[room]
    spacing, count, comb_ms, comb_g = FLUTTER[room]
    rng = np.random.default_rng(seed)
    n = int(min(rt60 * 1.15, 3.2) * RATE)
    t = np.arange(n) / RATE
    dense = rng.standard_normal(n) * 10 ** (-3.0 * t / rt60)  # -60 dB at rt60
    dense *= ramp(n, int(0.5 * spacing[1] / 1000 * RATE), int(2.5 * spacing[1] / 1000 * RATE))  # the field builds up
    ir = dense * (0.35 if room == "small" else 0.6)
    # early reflections: discrete, decaying with the room, alternating in sign; the flutter of a small space
    at = 0.0
    for _ in range(count):
        at += rng.uniform(*spacing) / 1000.0
        k = int(at * RATE)
        if k < n:
            ir[k] += rng.choice([-1.0, 1.0]) * rng.uniform(0.7, 1.0) * 10 ** (-3.0 * at / rt60) * 1.6
    if comb_ms > 0.0:
        d = int(comb_ms / 1000 * RATE)
        den = np.zeros(d + 1)
        den[0], den[d] = 1.0, -comb_g
        ir = signal.lfilter([1.0], den, ir)
        ir = signal.lfilter([1.0], np.concatenate([[1.0], np.zeros(int(d * 1.37) - 1), [-comb_g * 0.7]]), ir)
    b, a = signal.butter(2, damp / (RATE / 2), "low")
    ir = signal.lfilter(b, a, ir)
    ir[0:] *= ramp(n, 0, int(0.0008 * RATE))
    ir = np.concatenate([np.zeros(int(pre_ms / 1000 * RATE)), ir])
    return ir / np.sqrt(np.sum(ir ** 2))


def tail_for(room, x, seed):
    rt60, _damp, _pre, drive_ms, _db = ROOMS[room]
    a0 = int(0.003 * RATE)
    drive = x[a0: a0 + int(drive_ms / 1000 * RATE)].copy()
    f = min(int(0.03 * RATE), len(drive) // 2)
    drive[-f:] *= np.linspace(1, 0, f)
    y = signal.fftconvolve(drive, room_ir(room, seed))
    y = y[: int((rt60 * 1.1 + 0.2) * RATE)]
    f = int(0.08 * RATE)
    y[-f:] *= np.linspace(1, 0, f) ** 2
    return y



def outdoor_for(x, late, seed):
    """Open air: almost no reverb, the recording's own late part low, and the distant slap-back off a far surface."""
    b, a = signal.butter(2, 2300.0 / (RATE / 2), "low")
    src = signal.lfilter(b, a, x[int(0.004 * RATE): int(0.45 * RATE)])
    y = np.zeros(int(1.5 * RATE))
    rng = np.random.default_rng(seed)
    for delay, gain in ((0.27, 0.8), (0.61, 0.38)):
        smear = rng.standard_normal(int(0.02 * RATE)) * np.exp(-np.arange(int(0.02 * RATE)) / (0.006 * RATE))
        smear[0] += 1.5
        echo = signal.fftconvolve(src, smear / np.sqrt(np.sum(smear ** 2)))
        k = int(delay * RATE)
        y[k: k + len(echo)] += (gain * echo)[: len(y) - k]
        src = signal.lfilter(b, a, src)  # each bounce loses more of the top
    y[: len(late)] += 0.25 * late[: len(y)]
    f = int(0.2 * RATE)
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
    ap.add_argument("--only", nargs="*", help="build just these classes (the others need their EXTRA downloads)")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for cls in args.only or CLASSES:
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
            write(os.path.join(folder, "tail_outdoor_%d.ogg" % n), outdoor_for(x, late, 500 + n) * gain, OUTDOOR_DB)
            for room in ROOMS:
                write(os.path.join(folder, "tail_%s_%d.ogg" % (room, n)), tail_for(room, x, 1000 + n) * gain,
                      ROOMS[room][4])
            write(os.path.join(folder, "far_%d.ogg" % n), far_for(x, 7 + n) * gain, peak - 6.0)
        print(cls, len(sources), "variants")
    if args.only:
        return
    # the suppressed pistol: the stock's derived report is the body; no crack, no tail
    folder = os.path.join(OUT, "suppressed")
    os.makedirs(folder, exist_ok=True)
    for n in range(4):
        y = load(os.path.join(WEAPONS, "suppressed_fire_%d.ogg" % n))
        write(os.path.join(folder, "body_%d.ogg" % n), y, -9.0)
        write(os.path.join(folder, "far_%d.ogg" % n), far_for(y, 31 + n), -18.0)
    print("suppressed 4 variants")


main()
