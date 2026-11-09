#!/usr/bin/env python3
"""Synthesises the stock files that replace DotAudioSynth's sine-sweep stand-ins for the voices a game hears most:
shot (rifle, heavy, tight/energy), impact, hit-marker blip, hurt, die, boom. Self-synthesised from tools/foley.py, no recordings.

    python3 -I tools/make_voice_stock.py [--out addons/dot_audio/stock/voices]

Writes <voice>_<i>.ogg (3 variants each), mono Ogg Vorbis, ceiling -2 dB, levelled by K-weighted active loudness so
a hit tick is not louder than a shot. DotAudioSynth.bank(..., stock = true) uses them in place of the sweeps.
"""
import argparse, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import foley as F
from audit_weapon_audio import measure

VARIANTS = 3
CEIL_DB = -2.0


def decay_noise(r, dur, lo, hi, tau, sweep_to=None):
    """Noise whose band closes over time (a blast cooling): crossfaded bands from [lo,hi] toward sweep_to."""
    n = F.n_samples(dur)
    x = r.standard_normal(n)
    out = np.zeros(n)
    steps = 7
    u = np.linspace(0, 1, n)
    for i in range(steps):
        k = i / (steps - 1)
        h = hi * (sweep_to / hi) ** k if sweep_to else hi
        out += F.lowpass(F.highpass(x, lo), h) * np.exp(-0.5 * ((u - k) / (0.55 / steps)) ** 2)
    return out / max(np.max(np.abs(out)), 1e-9) * F.env_exp(n, tau, 0.0005)


def shot(r, heavy=False):
    crack = F.noise_burst(r, 0.03, 1500, 12000, 0.006 if not heavy else 0.01)
    body = F.thud(r, 190 if not heavy else 120, 60 if not heavy else 45, 0.2 if not heavy else 0.32, 0.06 if not heavy else 0.11, 1.0, 0.5)
    tail = decay_noise(r, 0.5 if not heavy else 0.9, 150, 6000, 0.16 if not heavy else 0.3, 500)
    return F.mix([(0, crack, 0), (0, body, -3), (0.01, tail, -9 if not heavy else -7)], 1.0 if heavy else 0.6)


def tight(r):
    n = F.n_samples(0.3)
    t = np.arange(n) / F.RATE
    f = 2400 * np.exp(-t / 0.05) + 360
    ph = 2 * np.pi * np.cumsum(f) / F.RATE
    z = (np.sin(ph) + 0.35 * np.sin(2.01 * ph)) * F.env_exp(n, 0.09, 0.0008)
    z /= max(np.max(np.abs(z)), 1e-9)
    return F.mix([(0, F.noise_burst(r, 0.015, 3000, 14000, 0.003), -3), (0, z, 0),
                  (0.0, F.thud(r, 130, 60, 0.18, 0.05, 0.7, 0.2), -6), (0.02, decay_noise(r, 0.35, 400, 7000, 0.1, 900), -14)], 0.45)


def impact(r):
    return F.mix([(0, F.noise_burst(r, 0.02, 1800, 9000, 0.005), -2), (0, F.thud(r, 220, 80, 0.14, 0.035, 1.0, 0.7), 0),
                  (0.01, F.strike(r, "wood", 700 * r.uniform(0.9, 1.2), 0.1, 0.5, 0.6, 0.5), -8)], 0.2)


def blip(r):
    """Hit marker: a dull wooden tick, round rather than bright, so it confirms without piercing (the old aluminium
    ping at 2.7 kHz was too high and thin). Body near 1.1 kHz, a low knock under it, everything lowpassed at 3.5 kHz."""
    x = F.mix([(0, F.strike(r, "wood", 1100 * r.uniform(0.97, 1.04), 0.08, 1.0, 1.3, 0.15), 0),
               (0, F.thud(r, 380, 210, 0.06, 0.018, 0.8, 0.15), -3)], 0.1)
    return F.lowpass(x, 3500)


def hurt(r):
    """A short, low, breathy 'uh': a male-range voice (about 175 falling to 80 Hz) through two soft formants near 550 and
    1.1 kHz, a 14 ms attack so it does not bark, a little breath and a dull chest thump. Not a scream: it is heard often."""
    n = F.n_samples(0.3)
    t = np.arange(n) / F.RATE
    f0 = 95 * np.exp(-t / 0.2) + 82
    ph = 2 * np.pi * np.cumsum(f0) / F.RATE
    voiced = sum(np.sin(k * ph) / k ** 1.3 for k in range(1, 15))
    vowel = F.bandpass(voiced, 420, 700) + 0.5 * F.bandpass(voiced, 900, 1300)
    vowel = F.lowpass(vowel, 2200) * F.env_exp(n, 0.1, 0.014)
    vowel /= max(np.max(np.abs(vowel)), 1e-9)
    breath = F.bandpass(r.standard_normal(n), 250, 1500) * F.env_exp(n, 0.07, 0.02)
    breath /= max(np.max(np.abs(breath)), 1e-9)
    return F.mix([(0, vowel, 0), (0, breath, -20), (0, F.thud(r, 130, 55, 0.12, 0.04, 0.9, 0.4), -4)], 0.32)


def die(r):
    n = F.n_samples(0.7)
    t = np.arange(n) / F.RATE
    f0 = 190 * np.exp(-t / 0.45) + 60
    ph = 2 * np.pi * np.cumsum(f0) / F.RATE
    voiced = sum(np.sin(k * ph) / k for k in range(1, 12))
    vowel = (F.bandpass(voiced, 400, 800) + 0.6 * F.bandpass(voiced, 1000, 1700)) * F.env_exp(n, 0.3, 0.01)
    vowel /= max(np.max(np.abs(vowel)), 1e-9)
    return F.mix([(0, vowel, 0), (0, F.thud(r, 140, 50, 0.2, 0.07, 1.0, 0.6), -2),
                  (0.25, F.thud(r, 100, 45, 0.3, 0.1, 0.8, 0.8), -5), (0.3, F.cloth(r, 0.3, 0.5), -14)], 0.8)


def boom(r):
    n = F.n_samples(1.7)
    t = np.arange(n) / F.RATE
    sub = np.sin(2 * np.pi * np.cumsum(32 + 80 * np.exp(-t / 0.12)) / F.RATE) * F.env_exp(n, 0.5, 0.002)
    body = decay_noise(r, 1.6, 40, 5000, 0.45, 180)
    return F.mix([(0, F.noise_burst(r, 0.05, 800, 12000, 0.01), -4), (0, sub, 0), (0, body, -2),
                  (0.35, F.rattle(r, 12, 1.0, "steel", 1800, 0.4), -16)], 1.7)


VOICES = {"shot": (lambda r: shot(r), -18.0), "shot_heavy": (lambda r: shot(r, True), -17.0), "shot_tight": (tight, -19.0),
          "impact": (impact, -22.0), "blip": (blip, -25.0), "hurt": (hurt, -27.0), "die": (die, -22.0), "boom": (boom, -16.0)}


def level(x, target):
    x = F.finish(x, peak_db=-3.0, fade_ms=18.0)
    for _ in range(3):
        m = measure(x)
        x = x * 10 ** ((target - m["lufs_active"]) / 20)
        pk = np.max(np.abs(x))
        lim = 10 ** (CEIL_DB / 20)
        if pk > lim:
            x = x * lim / pk
    return x


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "addons/dot_audio/stock/voices"))
    a = ap.parse_args()
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for name, (fn, target) in VOICES.items():
        for i in range(VARIANTS):
            r = np.random.default_rng(sum(map(ord, name)) * 131 + i * 7919)
            F.to_ogg(level(fn(r), target), out / ("%s_%d.ogg" % (name, i)))
    print("wrote", len(VOICES) * VARIANTS, "files to", out)


if __name__ == "__main__":
    main()
