#!/usr/bin/env python3
"""Synthesises the reload/handling cues the arena reload sequence plays at its phase boundaries
(arena-weapons view/aw_reload_cues.gd maps phase names to these). Self-synthesised from tools/foley.py: no recordings.

    python3 -I tools/make_reload_cues.py [--out addons/dot_audio/stock/weapons] [--previews DIR]

Writes cue_<name>_<i>.ogg (VARIANTS each), every one levelled to the same K-weighted active loudness so a quiet
rustle and a loud slide-lock sit where a person would put them, then prints the COUNTS line for dot_audio_shot_stock.gd.
"""
import argparse, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import foley as F
from audit_weapon_audio import measure

VARIANTS = 3
# Active loudness target per level class (LUFS, ungated K-weighted over the audible part) and a true-peak ceiling.
LEVEL = {"loud": -21.0, "mid": -24.0, "soft": -29.0}
CEIL_DB = -2.0


def ev(*items):
    return list(items)


# ---- the cues: f(rng) -> (array, level class) ------------------------------------------------------------------

def mag_release(r):
    return F.mix([(0, F.strike(r, "plastic", 2400, 0.05, 0.9, hardness=0.9), 0), (0.004, F.strike(r, "steel", 3200, 0.06, 0.5, 0.5), -6)], 0.1), "mid"


def mag_out(r):
    s = F.slide(r, 0.16, 700, 3800, 0.8, rough=140, sweep=(1.0, 0.8), shape="ramp_down")
    return F.mix([(0, s, 0), (0.15, F.strike(r, "plastic", 1500, 0.06, 0.5, 0.4), -7)], 0.24), "mid"


def mag_drop(r):
    return F.mix([(0, F.thud(r, 170, 70, 0.16, 0.04, 1.0, 0.5), 0), (0.0, F.strike(r, "plastic", 1900, 0.07, 0.6, 0.6), -6),
                  (0.07, F.strike(r, "plastic", 1500, 0.05, 0.35, 0.5), -9)], 0.22), "mid"


def pouch(r):
    return F.mix([(0, F.cloth(r, 0.22, 1.0), 0), (0.17, F.strike(r, "plastic", 1300, 0.05, 0.3, 0.3), -14)], 0.3), "soft"


def mag_slide_in(r):
    return F.slide(r, 0.13, 800, 4200, 0.8, rough=160, sweep=(0.8, 1.15), shape="ramp_up"), "soft"


def mag_seat(r):
    return F.mix([(0, F.strike(r, "steel", 2200, 0.1, 1.0, 0.7, 0.9), 0), (0, F.thud(r, 260, 140, 0.07, 0.015, 0.6, 0.3), -4),
                  (0.006, F.noise_burst(r, 0.01, 2500, 9000, 0.002), -8)], 0.14), "loud"


def rack_back(r):
    s = F.slide(r, 0.14, 1200, 6000, 0.9, rough=210, sweep=(1.0, 1.0), shape="hump")
    return F.mix([(0, s, 0), (0.0, F.strike(r, "steel", 1800, 0.05, 0.5, 0.4), -9), (0.13, F.strike(r, "steel", 2600, 0.06, 0.45, 0.4), -9)], 0.22), "mid"


def rack_fwd(r):
    s = F.slide(r, 0.09, 1500, 6500, 0.9, rough=240, shape="ramp_up")
    return F.mix([(0, s, -4), (0.085, F.strike(r, "steel", 1700, 0.14, 1.0, 0.8, 1.0), 0), (0.085, F.thud(r, 220, 110, 0.08, 0.02, 0.5, 0.3), -5)], 0.24), "loud"


def charge_back(r):
    s = F.slide(r, 0.16, 900, 4800, 0.9, rough=130, shape="hump")
    return F.mix([(0, s, 0), (0.15, F.strike(r, "steel", 1400, 0.1, 0.8, 0.6), -5)], 0.26), "mid"


def charge_fwd(r):
    s = F.slide(r, 0.08, 900, 4800, 0.9, rough=170, shape="ramp_up")
    return F.mix([(0, s, -5), (0.075, F.strike(r, "steel", 1250, 0.16, 1.0, 0.9, 0.9), 0), (0.075, F.thud(r, 200, 90, 0.09, 0.025, 0.6, 0.3), -4)], 0.28), "loud"


def cyl_open(r):
    return F.mix([(0, F.strike(r, "steel", 2800, 0.05, 0.7, 0.4, 0.9), 0), (0.03, F.slide(r, 0.12, 900, 3800, 0.6, 180, shape="hump"), -6),
                  (0.15, F.strike(r, "steel", 1900, 0.08, 0.8, 0.5, 0.7), -2)], 0.26), "mid"


def cyl_dump(r):
    return F.mix([(0, F.rattle(r, 6, 0.22, "brass", 3300, 1.0), 0), (0.0, F.slide(r, 0.06, 1800, 5000, 0.4, 200), -9)], 0.4), "mid"


def speedloader_in(r):
    return F.mix([(0, F.slide(r, 0.07, 1000, 4000, 0.6, 200, shape="ramp_up"), -3), (0.07, F.strike(r, "brass", 2500, 0.1, 0.9, 0.5, 0.9), 0),
                  (0.07, F.rattle(r, 3, 0.03, "brass", 3800, 0.5), -8)], 0.2), "mid"


def cyl_twist(r):
    t = []
    for i in range(5):
        t.append((i * 0.022, F.strike(r, "steel", 3400 + 120 * i, 0.03, 0.45, 0.25, 1.0), -3 * (i / 4.0)))
    return F.mix(t, 0.16), "soft"


def cyl_close(r):
    return F.mix([(0, F.slide(r, 0.08, 1000, 3800, 0.5, 190, shape="ramp_up"), -6), (0.08, F.strike(r, "steel", 1850, 0.12, 1.0, 0.8, 1.0), 0),
                  (0.08, F.thud(r, 240, 120, 0.07, 0.02, 0.5, 0.3), -5), (0.1, F.strike(r, "steel", 3600, 0.04, 0.4, 0.3), -9)], 0.24), "loud"


def round_tick(r):
    return F.mix([(0, F.strike(r, "brass", 3000, 0.07, 0.8, 0.3, 0.9), 0), (0.015, F.strike(r, "steel", 2300, 0.05, 0.4, 0.3), -9)], 0.12), "mid"


def break_open(r):
    return F.mix([(0, F.strike(r, "steel", 1500, 0.06, 0.8, 0.6, 1.0), 0), (0.025, F.slide(r, 0.22, 500, 3000, 0.7, 90, shape="hump"), -5),
                  (0.26, F.strike(r, "steel", 900, 0.18, 0.9, 0.9, 0.5), -2), (0.26, F.thud(r, 150, 70, 0.12, 0.04, 0.5, 0.3), -5)], 0.5), "loud"


def case_eject(r):
    return F.mix([(0, F.strike(r, "brass", 1100, 0.2, 0.9, 1.0, 0.7), -2), (0.0, F.thud(r, 130, 80, 0.1, 0.03, 0.5, 0.3), -7),
                  (0.11, F.strike(r, "brass", 1200, 0.15, 0.5, 0.8), -7)], 0.4), "mid"


def shell_load(r):
    return F.mix([(0, F.slide(r, 0.06, 700, 3000, 0.5, 160, shape="ramp_up"), -5), (0.06, F.strike(r, "brass", 900, 0.16, 1.0, 0.7, 0.6), 0),
                  (0.06, F.thud(r, 170, 90, 0.09, 0.03, 0.7, 0.3), -3)], 0.28), "mid"


def break_close(r):
    return F.mix([(0, F.slide(r, 0.12, 600, 3200, 0.6, 100, shape="ramp_up"), -5), (0.12, F.strike(r, "steel", 1100, 0.2, 1.0, 0.9, 1.0), 0),
                  (0.12, F.thud(r, 200, 90, 0.12, 0.035, 0.8, 0.4), -3), (0.125, F.noise_burst(r, 0.02, 2000, 9000, 0.004), -9)], 0.4), "loud"


def pump_back(r):
    return F.mix([(0, F.slide(r, 0.17, 600, 3600, 0.9, 85, shape="hump"), 0), (0.0, F.strike(r, "steel", 1000, 0.06, 0.5, 0.4), -8),
                  (0.17, F.strike(r, "steel", 1300, 0.1, 0.7, 0.6), -5)], 0.3), "mid"


def pump_fwd(r):
    return F.mix([(0, F.slide(r, 0.09, 600, 3400, 0.8, 90, shape="ramp_up"), -5), (0.09, F.strike(r, "steel", 1050, 0.2, 1.0, 1.0, 1.0), 0),
                  (0.09, F.thud(r, 190, 80, 0.13, 0.045, 0.8, 0.4), -3), (0.095, F.rattle(r, 2, 0.02, "steel", 2800, 0.3), -9)], 0.36), "loud"


def bolt_lift(r):
    return F.mix([(0, F.strike(r, "steel", 2300, 0.06, 0.8, 0.4, 0.9), 0), (0.01, F.slide(r, 0.05, 1200, 4000, 0.4, 200), -9)], 0.12), "mid"


def bolt_back(r):
    return F.mix([(0, F.slide(r, 0.14, 800, 4200, 0.9, 110, shape="hump"), 0), (0.14, F.strike(r, "steel", 1450, 0.12, 0.9, 0.7, 0.9), -2),
                  (0.14, F.thud(r, 180, 90, 0.07, 0.02, 0.4, 0.3), -6)], 0.28), "mid"


def bolt_fwd(r):
    return F.mix([(0, F.slide(r, 0.1, 800, 4200, 0.9, 120, shape="ramp_up"), -3), (0.1, F.strike(r, "steel", 1350, 0.14, 1.0, 0.8, 1.0), 0),
                  (0.1, F.thud(r, 210, 90, 0.09, 0.03, 0.6, 0.3), -4)], 0.28), "loud"


def bolt_down(r):
    return F.mix([(0, F.strike(r, "steel", 2000, 0.1, 1.0, 0.6, 1.0), 0), (0, F.thud(r, 250, 120, 0.06, 0.015, 0.5, 0.3), -6),
                  (0.012, F.noise_burst(r, 0.01, 3000, 10000, 0.002), -9)], 0.14), "loud"


def clip_in(r):
    return F.mix([(0, F.slide(r, 0.06, 1400, 5000, 0.5, 230, shape="ramp_up"), -5), (0.06, F.strike(r, "steel", 2500, 0.1, 0.9, 0.5, 0.9), 0),
                  (0.06, F.rattle(r, 4, 0.04, "brass", 3600, 0.5), -9)], 0.22), "mid"


def clip_press(r):
    return F.mix([(0, F.strike(r, "brass", 2200, 0.08, 0.8, 0.4, 0.6), -3), (0, F.thud(r, 200, 100, 0.07, 0.02, 0.8, 0.4), -1),
                  (0.04, F.rattle(r, 4, 0.05, "brass", 3000, 0.5), -8)], 0.2), "mid"


def cover_open(r):
    return F.mix([(0, F.strike(r, "steel", 1700, 0.05, 0.7, 0.4, 1.0), 0), (0.04, F.slide(r, 0.1, 500, 2800, 0.5, 80, shape="hump"), -6),
                  (0.13, F.strike(r, "steel", 750, 0.22, 1.0, 1.2, 0.7), -2), (0.13, F.thud(r, 140, 60, 0.16, 0.06, 0.7, 0.4), -4)], 0.5), "loud"


def box_out(r):
    return F.mix([(0, F.slide(r, 0.14, 500, 2800, 0.7, 90, shape="ramp_down"), -2), (0.14, F.strike(r, "alu", 800, 0.12, 0.5, 0.6, 0.5), -6)], 0.3), "mid"


def box_in(r):
    return F.mix([(0, F.slide(r, 0.1, 500, 2800, 0.6, 100, shape="ramp_up"), -5), (0.1, F.strike(r, "alu", 700, 0.22, 1.0, 1.1, 0.9), 0),
                  (0.1, F.thud(r, 130, 60, 0.16, 0.06, 0.9, 0.5), -2)], 0.42), "loud"


def belt_lay(r):
    return F.mix([(0, F.rattle(r, 10, 0.2, "steel", 2600, 0.9), 0), (0, F.slide(r, 0.2, 1000, 5000, 0.4, 260, shape="hump"), -8)], 0.36), "mid"


def cover_close(r):
    return F.mix([(0, F.slide(r, 0.09, 500, 2800, 0.4, 85, shape="ramp_up"), -7), (0.09, F.strike(r, "steel", 700, 0.28, 1.0, 1.3, 1.0), 0),
                  (0.09, F.thud(r, 170, 70, 0.18, 0.06, 0.9, 0.5), -2), (0.095, F.noise_burst(r, 0.03, 1500, 8000, 0.006), -8)], 0.5), "loud"


def cover_slap(r):
    return F.mix([(0, F.noise_burst(r, 0.05, 400, 4000, 0.012), -2), (0, F.thud(r, 180, 90, 0.1, 0.03, 0.8, 0.5), 0)], 0.14), "mid"


def cell_out(r):
    return F.mix([(0, F.strike(r, "plastic", 2000, 0.05, 0.8, 0.5, 0.9), 0), (0.02, F.whine(r, 0.3, 900, 220, 0.7, 0.2), -9),
                  (0.04, F.slide(r, 0.12, 700, 3000, 0.5, 120, shape="ramp_down"), -6)], 0.4), "mid"


def cell_in(r):
    return F.mix([(0, F.slide(r, 0.1, 700, 3200, 0.5, 130, shape="ramp_up"), -5), (0.1, F.strike(r, "plastic", 1700, 0.1, 1.0, 0.6, 1.0), 0),
                  (0.1, F.thud(r, 230, 110, 0.06, 0.02, 0.5, 0.3), -5), (0.11, F.whine(r, 0.14, 300, 520, 0.4), -10)], 0.3), "loud"


def cell_charge(r):
    return F.mix([(0, F.whine(r, 0.42, 280, 1900, 1.0, 0.35), 0), (0.4, F.strike(r, "plastic", 3600, 0.05, 0.5, 0.3), -9)], 0.5), "soft"


CUES = {f.__name__: f for f in [
    mag_release, mag_out, mag_drop, pouch, mag_slide_in, mag_seat, rack_back, rack_fwd, charge_back, charge_fwd,
    cyl_open, cyl_dump, speedloader_in, cyl_twist, cyl_close, round_tick,
    break_open, case_eject, shell_load, break_close, pump_back, pump_fwd,
    bolt_lift, bolt_back, bolt_fwd, bolt_down, clip_in, clip_press,
    cover_open, box_out, box_in, belt_lay, cover_close, cover_slap,
    cell_out, cell_in, cell_charge]}


def render(name, i):
    seed = (sum(map(ord, name)) * 131 + i * 7919) & 0xFFFFFFFF
    r = np.random.default_rng(seed)
    x, level = CUES[name](r)
    # variation: a little pitch (resample) and level, so repeats are not stamps
    k = 1.0 + (i - 1) * 0.035
    if abs(k - 1.0) > 1e-6:
        from scipy import signal
        x = signal.resample(x, int(len(x) / k))
    x = F.lowpass(x, 9000, 1)  # rounds off the synthetic fizz above the last partials
    x = F.finish(x, peak_db=-3.0, fade_ms=10.0)
    m = measure(x)
    gain = LEVEL[level] - m["lufs_active"]
    peak_after = m["peak_db"] + gain
    if peak_after > CEIL_DB:
        gain -= peak_after - CEIL_DB
    return x * 10 ** (gain / 20)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "addons/dot_audio/stock/weapons"))
    ap.add_argument("--previews", help="also write a wav per cue here")
    a = ap.parse_args()
    out = Path(a.out)
    for name in CUES:
        for i in range(VARIANTS):
            x = render(name, i)
            F.to_ogg(x, out / ("cue_%s_%d.ogg" % (name, i)))
            if a.previews:
                import wave
                p = Path(a.previews); p.mkdir(parents=True, exist_ok=True)
                with wave.open(str(p / ("cue_%s_%d.wav" % (name, i))), "wb") as w:
                    w.setnchannels(1); w.setsampwidth(2); w.setframerate(F.RATE)
                    w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    print("cues:", ", ".join(CUES))
    print('COUNTS += {%s}' % ", ".join('&"cue_%s": %d' % (n, VARIANTS) for n in CUES))


if __name__ == "__main__":
    main()
