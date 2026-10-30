#!/usr/bin/env python3
"""Builds dot-audio's surf glide loop (stock/surf/surf_glide.ogg): a quiet, slick hiss.

    python3 -I tools/make_surf_stock.py

Synthesised from a fixed seed, no recordings: noise shaped in the frequency domain (so the loop
is periodic and has no seam), a soft band around 1.5-6 kHz with a rolled-off low end so there is
no thump, and a slow shimmer. Dedicated to the public domain under CC0 1.0 by the dot-audio authors.
"""
import os
import subprocess

import numpy as np

RATE = 44100
SECONDS = 4.0
TARGET_RMS_DB = -27.0
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock", "surf")


def shaped_noise(rng, n):
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / RATE)
    gain = np.zeros_like(f)
    band = (f > 200) & (f < 12000)
    # Rises to a broad hump near 3 kHz, falls off gently above: ice under a board, not a scrape.
    gain[band] = np.exp(-0.5 * ((np.log2(f[band] / 3000.0)) / 1.3) ** 2)
    gain[f < 200] = 0.0
    return np.fft.irfft(spec * gain, n)


def main():
    rng = np.random.default_rng(20261030)
    n = int(SECONDS * RATE)
    x = shaped_noise(rng, n)
    t = np.arange(n) / RATE
    # Whole cycles of the shimmer fit the loop, so it joins without a click.
    shimmer = 1.0 + 0.12 * np.sin(2 * np.pi * (3 / SECONDS) * t) + 0.07 * np.sin(2 * np.pi * (7 / SECONDS) * t + 1.3)
    x = x * shimmer
    x *= 10 ** (TARGET_RMS_DB / 20.0) / (np.sqrt(np.mean(x ** 2)) + 1e-9)
    x = np.clip(x, -0.9, 0.9)
    os.makedirs(OUT, exist_ok=True)
    pcm = x.astype("<f4").tobytes()
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, "surf_glide.ogg")], input=pcm, check=True)
    print("surf_glide  %.2f s  peak %.2f" % (SECONDS, np.max(np.abs(x))))


if __name__ == "__main__":
    main()
