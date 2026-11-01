#!/usr/bin/env python3
"""Renders what a shot's tail sounds like in five rooms and measures it.

    python3 -I tools/measure_tails.py CLASS OUTDIR < scenarios.txt

scenarios.txt is the output of `--script res://tools/tail_scenarios.gd`. For each scenario the enclosure code's weights
mix the stock tail files (equal power, with the tightness gain) with the attack and body, and the result is written as
a WAV and a spectrogram PNG in OUTDIR. Printed per scenario: RT60 of the tail alone (5 ms energy envelope,
-20 dB time x3), tail energy relative to attack+body, and the share of tail energy in the first 60 ms.
"""
import json
import os
import subprocess
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

RATE = 44100
SHOTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock", "shots")


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def rt60(y):
    """RT60 in seconds from the 5 ms energy envelope: the time from the peak until it first falls 20 dB, times three.
    (Schroeder integration is not used: a lossy-coded tail's noise floor stops its integral short.)"""
    w = int(0.005 * RATE)
    env = np.convolve(y ** 2, np.ones(w) / w, "same")
    pk = int(np.argmax(env))
    below = np.nonzero(env[pk:] < env[pk] * 0.01)[0]
    return None if len(below) == 0 else 3.0 * below[0] / RATE


def main():
    cls, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    line = [l for l in sys.stdin.read().splitlines() if l.startswith("JSON:")][0]
    scen = json.loads(line[5:])
    base = os.path.join(SHOTS, cls)
    attack, body = load(base + "/attack_0.ogg"), load(base + "/body_0.ogg")
    tails = {c: load(base + "/tail_%s_0.ogg" % c) for c in ("small", "medium", "large", "hall", "outdoor")}
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(len(scen), 1, figsize=(9, 2.2 * len(scen)), sharex=True)
    print("%-10s %6s %6s %8s %12s %10s" % ("room", "size", "open", "RT60 s", "tail-att dB", "tail<60ms"))
    for ax, (name, s) in zip(axes, scen.items()):
        n = int(3.2 * RATE)
        tail = np.zeros(n)
        for c, w in s["weights"].items():
            if w > 0.0:
                tail[: len(tails[c])] += w * s["tail_gain"] * tails[c][:n]
        near = np.zeros(n)
        near[: len(attack)] += attack
        near[: len(body)] += body
        mix = (near + tail) * 10 ** (s["loud_db"] / 20)
        e_tail = np.sum(tail ** 2)
        rt = rt60(tail)
        early = np.sum(tail[: int(0.06 * RATE)] ** 2) / max(e_tail, 1e-12)
        print("%-10s %6.1f %6.2f %8s %12.1f %9.0f%%" % (name, s["size"], s["open"],
              ("%.2f" % rt) if rt else ">len", 10 * np.log10(max(e_tail, 1e-12) / np.sum(near ** 2)), 100 * early))
        wavfile.write(os.path.join(outdir, "%s_%s.wav" % (cls, name.replace(" ", "_"))), RATE,
                      (np.clip(mix / max(np.max(np.abs(mix)), 1.0), -1, 1) * 32767).astype(np.int16))
        f, t, sxx = signal.spectrogram(mix, RATE, nperseg=1024, noverlap=896)
        ax.pcolormesh(t, f, 10 * np.log10(sxx + 1e-12), vmin=-120, vmax=-30, shading="auto")
        ax.set_ylim(0, 12000)
        ax.set_xlim(0, 3.0)
        ax.set_ylabel(name)
    axes[-1].set_xlabel("s")
    fig.tight_layout()
    fig.savefig(os.path.join(outdir, "%s_rooms.png" % cls), dpi=80)


main()
