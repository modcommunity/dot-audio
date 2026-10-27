#!/usr/bin/env python3
"""Builds dot-audio's stock slide loops (stock/slides/slide_<surface>.ogg) from CC0 scrapes.

    python3 -I tools/make_slide_stock.py SCRAPES_DIR

SCRAPES_DIR holds scrape-1..8.wav from https://opengameart.org/content/scrapes (AntumDeluge,
CC0). Each loop is a few scrapes joined with equal-power crossfades, the last one fading into
the first so the loop has no seam, then filtered to its surface and levelled to one loudness.
"""
import os
import subprocess
import sys

import numpy as np
from scipy import signal

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock", "slides")
XFADE = int(0.18 * RATE)
TARGET_RMS_DB = -24.0

# surface: (scrapes, filter kind, cutoff Hz, extra gain dB)
RECIPES = {
    "generic": ([1, 2, 5, 8], "lp", 5500, 0.0),
    "concrete": ([4, 5, 8, 7], "lp", 7000, 0.0),
    "metal": ([3, 6, 7], "hp", 1800, -2.0),
    "wood": ([1, 2, 7, 5], "lp", 3200, 0.0),
    "grass": ([1, 2, 8], "lp", 1900, 1.0),
    "snow": ([2, 1, 5], "lp", 1300, 1.0),
    "carpet": ([1, 2, 4], "lp", 900, 3.0),
}


def load(path):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
        check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def levelled(x):
    return x / (np.sqrt(np.mean(x ** 2)) + 1e-9)


def join(parts):
    """Equal-power crossfade of each part into the next, and the last into the first."""
    t = np.linspace(0.0, np.pi / 2.0, XFADE)
    fin, fout = np.sin(t), np.cos(t)
    body = parts[0].copy()
    for p in parts[1:]:
        body[-XFADE:] = body[-XFADE:] * fout + p[:XFADE] * fin
        body = np.concatenate([body, p[XFADE:]])
    # Wrap: the tail fades into the head and the head's first XFADE is dropped.
    body[-XFADE:] = body[-XFADE:] * fout + body[:XFADE] * fin
    return body[XFADE:]


def write(x, path):
    pcm = np.clip(x, -1.0, 1.0).astype("<f4").tobytes()
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
         "-c:a", "libvorbis", "-q:a", "4", path], input=pcm, check=True)


def main():
    src = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    for name, (nums, kind, hz, extra) in RECIPES.items():
        parts = [levelled(load(os.path.join(src, "scrape-%d.wav" % n))) for n in nums]
        x = join(parts)
        sos = signal.butter(4, hz, btype="low" if kind == "lp" else "high", fs=RATE, output="sos")
        x = signal.sosfilt(sos, x)
        x = levelled(x) * 10 ** ((TARGET_RMS_DB + extra) / 20.0)
        peak = np.max(np.abs(x))
        if peak > 0.9:
            x *= 0.9 / peak
        write(x, os.path.join(OUT, "slide_%s.ogg" % name))
        print("%s  %.2f s  peak %.2f" % (name, len(x) / RATE, np.max(np.abs(x))))


if __name__ == "__main__":
    main()
