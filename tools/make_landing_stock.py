#!/usr/bin/env python3
"""Builds dot-audio's stock landing thumps (stock/landing/landing_{light,medium,hard}.ogg).

    python3 -I tools/make_landing_stock.py

Synthesised from fixed seeds (a falling sine body thump plus low-passed noise for the scuff),
no recordings and no third-party samples; dedicated to the public domain under CC0 1.0 by the
dot-audio authors. Three grades so a stumble and a bone-jarring drop differ by more than volume:
heavier is lower, longer and has a late crunch.
"""
import os
import subprocess

import numpy as np
from scipy import signal

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock", "landing")


def thump(seed, f0, f1, body_ms, scuff_ms, scuff_cut, crunch, length_ms):
    rng = np.random.default_rng(seed)
    n = int(length_ms / 1000.0 * RATE)
    t = np.arange(n) / RATE
    freq = f1 + (f0 - f1) * np.exp(-t / 0.035)
    body = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.exp(-t / (body_ms / 1000.0))
    b, a = signal.butter(2, scuff_cut / (RATE / 2), "low")
    scuff = signal.lfilter(b, a, rng.standard_normal(n)) * np.exp(-t / (scuff_ms / 1000.0))
    out = body + 0.7 * scuff
    if crunch > 0.0:
        off = int(0.045 * RATE)
        c = signal.lfilter(b, a, rng.standard_normal(n - off)) * np.exp(-t[: n - off] / 0.05)
        out[off:] += crunch * c
    out *= np.minimum(1.0, np.arange(n) / 12.0)
    out /= np.max(np.abs(out))
    return out * 0.8


def write(name, data):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".ogg")
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "5", path],
        input=data.astype("<f4").tobytes(), check=True)


write("landing_light", thump(5, 150, 90, 45, 30, 1800, 0.0, 220))
write("landing_medium", thump(9, 110, 60, 80, 55, 1200, 0.3, 320))
write("landing_hard", thump(13, 80, 38, 140, 90, 800, 0.8, 500))
