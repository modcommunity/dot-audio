#!/usr/bin/env python3
"""Derives the suppressed pistol report from the stock's own light_fire files.

    python3 -I tools/make_suppressed.py

Run after make_weapon_stock.py (it reads light_fire_0..3.ogg beside the output). A suppressor
removes the crack and most of the top: low-pass the report, soften the attack, shorten it,
and add the action's own small mechanical clack that is left once the muzzle is quiet. It is
a derivation of CC0 files, so it adds no source to stock/CREDITS.md. Nobody has listened.
"""
import os
import subprocess

import numpy as np
from scipy import signal

RATE = 44100
DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock", "weapons")
PEAK_DB = -9.0


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def make(x, i):
    b, a = signal.butter(2, 1700.0 / (RATE / 2), "low")
    y = signal.lfilter(b, a, x)
    n = int(0.0035 * RATE)
    y = np.convolve(y, np.ones(n) / n, "same")
    y = y[: int(0.22 * RATE)]
    y *= np.exp(-np.arange(len(y)) / (0.05 * RATE))
    rng = np.random.default_rng(100 + i)
    bb, ba = signal.butter(2, [900 / (RATE / 2), 3500 / (RATE / 2)], "band")
    clack = signal.lfilter(bb, ba, rng.standard_normal(int(0.02 * RATE)))
    clack *= np.exp(-np.arange(len(clack)) / (0.004 * RATE)) * 0.5 * np.max(np.abs(y)) / max(np.max(np.abs(clack)), 1e-9)
    y[int(0.012 * RATE): int(0.012 * RATE) + len(clack)] += clack[: len(y) - int(0.012 * RATE)]
    f = int(0.05 * RATE)
    y[-f:] *= np.linspace(1, 0, f) ** 2
    y -= np.mean(y)
    return y * (10 ** (PEAK_DB / 20) / (np.max(np.abs(y)) + 1e-9))


for i in range(4):
    y = make(load(os.path.join(DIR, "light_fire_%d.ogg" % i)), i)
    raw = (y * 32767).astype("<i2").tobytes()
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", os.path.join(DIR, "suppressed_fire_%d.ogg" % i)],
                   input=raw, check=True)
    print("suppressed_fire_%d" % i)
