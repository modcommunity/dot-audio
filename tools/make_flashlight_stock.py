#!/usr/bin/env python3
"""Builds dot-audio's stock flashlight clicks (stock/flashlight/flashlight_{on,off}.ogg).

    python3 -I tools/make_flashlight_stock.py

Synthesised from fixed seeds (filtered noise bursts and damped resonances), no recordings and no
third-party samples; dedicated to the public domain under CC0 1.0 by the dot-audio authors.
A slide switch is two events: the plunger hitting its stop, then a smaller rattle. "On" is the
brighter, tighter one; "off" is lower and a little longer, so the two are told apart by ear.
"""
import os
import subprocess

import numpy as np
from scipy import signal

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock", "flashlight")


def burst(rng, n, centre, q, decay_ms):
    t = np.arange(n) / RATE
    noise = rng.standard_normal(n)
    b, a = signal.iirpeak(centre / (RATE / 2), q)
    return signal.lfilter(b, a, noise) * np.exp(-t / (decay_ms / 1000.0))


def ring(n, freq, decay_ms):
    t = np.arange(n) / RATE
    return np.sin(2 * np.pi * freq * t) * np.exp(-t / (decay_ms / 1000.0))


def click(seed, centre, freq, gap_ms, second_gain, decay_ms):
    rng = np.random.default_rng(seed)
    n = int(0.12 * RATE)
    out = np.zeros(n)
    first = 0.8 * burst(rng, n, centre, 4.0, decay_ms) + 0.5 * ring(n, freq, decay_ms * 1.4)
    out += first
    off = int(gap_ms / 1000.0 * RATE)
    second = second_gain * (0.8 * burst(rng, n - off, centre * 1.25, 5.0, decay_ms * 0.7) + 0.4 * ring(n - off, freq * 1.3, decay_ms))
    out[off:] += second
    out *= np.minimum(1.0, np.arange(n) / 8.0)  # 8 samples in: no DC pop at the first sample
    out /= np.max(np.abs(out))
    return out * 0.8


def write(name, data):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".ogg")
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "5", path],
        input=data.astype("<f4").tobytes(), check=True)


write("flashlight_on", click(11, 3200, 2100, 14, 0.45, 4.0))
write("flashlight_off", click(23, 2100, 1300, 19, 0.6, 5.5))
