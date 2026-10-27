#!/usr/bin/env python3
"""Builds dot-audio's stock weapon sounds from the CC0 recordings listed in stock/CREDITS.md.

    python3 -I tools/make_weapon_stock.py SOURCES_DIR [class ...]

SOURCES_DIR holds the downloads, one directory per source (names in SOURCES below; the URLs
are in CREDITS.md). Nothing is shipped from here but the .ogg files: each is a slice of one
recording (a shot, a click, a swing) cut at its onset, optionally pitched or layered with a
synthesised sub-bass thump, faded, peak-normalised to its class's level and written as mono
Ogg Vorbis. The level of a class against the others is its PEAK_DB, so a sniper stays above a
pistol and a minigun round stays under both; docs/weapons.md prints the measured LUFS.
"""
import glob
import os
import subprocess
import sys

import numpy as np
from scipy import signal

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "dot_audio", "stock", "weapons")
MAX_VARIANTS = 5
FAR_VARIANTS = 2

FF = "Free Firearm Sound Library"  # directory name under SOURCES_DIR/firearms/Prepared SFX Library


def load(path):
    """Any file as mono float32 at RATE, through ffmpeg."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
        check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()


def onsets(x, rel=0.25, gap=0.2):
    """Sample indices where the 5 ms RMS envelope crosses rel * max upward, at least gap s apart."""
    w = int(RATE * 0.005)
    e = np.sqrt(np.convolve(x * x, np.ones(w) / w, "same"))
    above = e > e.max() * rel
    idx = np.flatnonzero(above[1:] & ~above[:-1])
    out, last = [], -10 * RATE
    for j in idx:
        if j - last > gap * RATE:
            out.append(int(j))
            last = j
    return out


def lp(x, hz, order=2):
    b, a = signal.butter(order, hz / (RATE / 2), "low")
    return signal.lfilter(b, a, x)


def pitch(x, semitones):
    """Resample so the sound is shorter and higher (or longer and lower): tape-style."""
    if semitones == 0:
        return x
    ratio = 2.0 ** (semitones / 12.0)
    n = 1000
    up, down = int(round(n)), int(round(n * ratio))
    return signal.resample_poly(x, up, down).astype(np.float32)


def sub(length, hz0=95.0, hz1=38.0, decay=0.07):
    """A synthesised thump the recordings lack: an exponential sine sweep. The chest, not the ear."""
    t = np.arange(int(length * RATE)) / RATE
    f = hz0 * (hz1 / hz0) ** np.minimum(1.0, t / (decay * 3))
    return (np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / decay)).astype(np.float32)


def finish(x, peak_db, fade=0.06):
    """Fade the end to exact zero, remove DC, then peak-normalise."""
    x = x - np.mean(x)
    n = min(len(x), int(fade * RATE))
    x[-n:] *= np.linspace(1, 0, n) ** 2
    a = int(0.0015 * RATE)
    x[:a] *= np.linspace(0, 1, a)
    return x * (10 ** (peak_db / 20) / (np.max(np.abs(x)) + 1e-9))


def trim_ends(x, floor=0.02):
    """Drop leading and trailing quiet (below floor * peak)."""
    m = np.flatnonzero(np.abs(x) > floor * np.max(np.abs(x)))
    if len(m) == 0:
        return x
    return x[max(0, m[0] - int(0.004 * RATE)):m[-1] + 1]


def shots(path, length, picks=None, rel=0.25, gap=0.2):
    """Each onset in the file, cut to length s (or the next onset), as separate arrays."""
    x = load(path)
    on = onsets(x, rel, gap)
    out = []
    for i, o in enumerate(on):
        if picks is not None and i not in picks:
            continue
        start = max(0, o - int(0.008 * RATE))
        end = min(len(x), o + int(length * RATE))
        if i + 1 < len(on):
            end = min(end, on[i + 1] - int(0.02 * RATE))
        if end - start > int(0.05 * RATE):
            out.append(x[start:end].copy())
    return out


def whole(path, length, floor=0.02):
    x = trim_ends(load(path), floor)
    return [x[:int(length * RATE)].copy()]


def firearm(folder, file, length, picks=None, semis=0):
    p = os.path.join("firearms", "Prepared SFX Library", folder, file)
    return lambda src: [pitch(s, semis) for s in shots(os.path.join(src, p), length, picks)]


def oga(*rel, length=1.5, semis=0, mode="whole", picks=None, floor=0.02):
    def go(src):
        out = []
        for pattern in rel:
            for p in sorted(glob.glob(os.path.join(src, pattern))):
                if mode == "whole":
                    parts = whole(p, length, floor)
                elif mode == "events":
                    parts = shots(p, length, picks, rel=0.2, gap=0.12)
                else:
                    parts = shots(p, length, picks, rel=0.2, gap=0.12)
                out += [pitch(s, semis) for s in parts]
        return out
    return go


def layered(base, thump):
    """base(src) shots plus a synthesised thump under each (hz0, hz1, decay, amount)."""
    hz0, hz1, decay, amount = thump

    def go(src):
        out = []
        for s in base(src):
            t = sub(min(len(s) / RATE, 0.6), hz0, hz1, decay)
            mix = s.copy()
            mix[:len(t)] += t * amount * (np.max(np.abs(s)) + 1e-9)
            out.append(mix)
        return out
    return go


def chain(*makers):
    def go(src):
        out = []
        for m in makers:
            out += m(src)
        return out
    return go


def mix_layers(a, b, gain_b):
    """a(src)[i] with b(src)[0] added at gain_b of a's peak: an explosion made of two recordings."""
    def go(src):
        bb = b(src)
        out = []
        for i, s in enumerate(a(src)):
            o = bb[i % len(bb)]
            m = s.copy()
            n = min(len(m), len(o))
            m[:n] += o[:n] * gain_b * (np.max(np.abs(s)) / (np.max(np.abs(o)) + 1e-9))
            out.append(m)
        return out
    return go


K = "kenney-impact-sounds/Audio"
S = "kenney-sci-fi-sounds/Audio"
M1 = "medieval-1"
M2 = "medieval-2"
BANG = "bang-sfx"

# name -> (peak dBFS, maker). Near fire (the shot as the shooter hears it).
SPECS = {
    # pistols: the 1911, a 9 mm and a .380
    "light_fire": (-4.0, chain(firearm("1911", "A_42P.wav", 0.7), firearm("Walther PPQ", "X_39P.wav", 0.7),
                               firearm("Bersa", "F_47P.wav", 0.7))),
    "light_far": (-8.0, chain(firearm("1911", "A_34P.wav", 0.9), firearm("Walther PPQ", "X_31P.wav", 0.9))),
    # revolvers: .38 and a .45 pitched down, with a thump
    "magnum_fire": (-2.5, layered(chain(firearm("Smith & Wesson 642", "V_27P.wav", 0.9),
                                        firearm("1911", "A_42P.wav", 0.9, semis=-4)),
                                  (110, 45, 0.06, 0.45))),
    "magnum_far": (-7.0, chain(firearm("Smith & Wesson 642", "V_22P.wav", 1.1),
                               firearm("1911", "A_34P.wav", 1.1, semis=-4))),
    # sub machine guns: single rounds of 9 mm and 7.62x25, short so a rate of fire does not smear
    "smg_fire": (-5.0, chain(firearm("Carl Gustav M45", "G_31P.wav", 0.32), firearm("PPSh", "P_30P.wav", 0.32),
                             firearm("Carl Gustav M45", "G_33P.wav", 0.25))),
    "smg_far": (-9.0, chain(firearm("Carl Gustav M45", "G_20P.wav", 0.45), firearm("PPSh", "P_16P.wav", 0.45))),
    # rifles: AR-15, SKS, AK-47
    "rifle_fire": (-2.5, chain(firearm("AR-15", "D_32P.wav", 0.8), firearm("SKS", "U_14P.wav", 0.8),
                               firearm("AK-47", "C_28P.wav", 0.8))),
    "rifle_far": (-7.0, chain(firearm("AR-15", "D_24P.wav", 1.0), firearm("AK-47", "C_31P.wav", 1.0))),
    # battle rifles and marksman rifles: lever actions and the .300 blackout, with a thump
    "heavy_fire": (-1.5, layered(chain(firearm("Model 1894", "L_23P.wav", 1.0), firearm("Marlin 336", "I_22P.wav", 1.0),
                                       firearm("Savage 10 .300 Blackout", "T_27P.wav", 1.0)),
                                 (95, 40, 0.07, 0.35))),
    "heavy_far": (-6.0, chain(firearm("Model 1894", "L_17P.wav", 1.2), firearm("Savage 10 .300 Blackout", "T_17P.wav", 1.2))),
    # bolt-action rifles, a long tail
    "sniper_fire": (-1.5, layered(chain(firearm("Mosin Nagant", "M_21P.wav", 1.6), firearm("Tikka", "W_29P.wav", 1.6),
                                        firearm("Arisaka", "E_25P.wav", 1.6), firearm("1917", "B_24P.wav", 1.6)),
                                  (80, 34, 0.1, 0.4))),
    "sniper_far": (-5.0, chain(firearm("Mosin Nagant", "M_26P.wav", 2.0), firearm("Tikka", "W_24P.wav", 2.0))),
    # shotguns: pump and bolt 12 gauge
    "shotgun_fire": (-1.5, layered(chain(firearm("CD", "H_21P.wav", 1.1), firearm("Model 12", "K_22P.wav", 1.1),
                                         firearm("Nova", "O_21P.wav", 1.1), firearm("Mossberg", "N_30P.wav", 1.1)),
                                   (100, 38, 0.09, 0.45))),
    "shotgun_far": (-5.0, chain(firearm("CD", "H_16P.wav", 1.3), firearm("Model 12", "K_17P.wav", 1.3))),
    # a spinning gun's round: very short, pitched up, quiet
    "minigun_fire": (-8.0, chain(firearm("PPSh", "P_34P.wav", 0.16, semis=2), firearm("AK-47", "C_27P.wav", 0.16, semis=3),
                                 firearm("Carl Gustav M45", "G_35P.wav", 0.16, semis=3))),
    # launchers: the report of a cannon pitched up toward a tube, and the blast of what it launched
    "launcher_fire": (-2.0, layered(oga(BANG + "/cannon_0[1-5].ogg", length=1.4, semis=4), (90, 34, 0.12, 0.4))),
    "explosion": (-1.5, mix_layers(
        oga(BANG + "/cannon_0[1-5].ogg", length=1.8, semis=-3),
        oga(S + "/lowFrequency_explosion_00[01].ogg", S + "/explosionCrunch_00[0-4].ogg", length=1.8, floor=0.01), 0.7)),
    # energy weapons
    "beam_fire": (-6.0, oga(S + "/laserSmall_00[0-4].ogg", length=0.45)),
    "charge_fire": (-3.0, oga(S + "/laserLarge_00[0-4].ogg", length=1.0)),
    # melee: blades and axes swung, the heavy and the light
    "swing": (-6.0, chain(oga(M2 + "/Dagger Swing.wav", M2 + "/Seax Swing.wav", M2 + "/Sabre Swing.wav",
                              M1 + "/Katana Swing.wav", length=0.7, mode="events"))),
    "swing_heavy": (-4.0, oga(M2 + "/Axe Swing.wav", M2 + "/Spear Swing.wav", length=0.9, mode="events", semis=-1)),
    "throw": (-9.0, oga(M2 + "/Dagger Swing.wav", M2 + "/Spear Swing.wav", length=0.6, mode="events", semis=-5)),
    "bash": (-3.0, oga(K + "/impactPunch_heavy_00[0-4].ogg", K + "/impactWood_heavy_00[0-1].ogg", length=0.5)),
    # what a hit sounds like
    "impact": (-8.0, oga(K + "/impactGeneric_light_00[0-4].ogg", K + "/impactPlate_light_00[0-1].ogg", length=0.3)),
    "impact_flesh": (-6.0, oga(K + "/impactSoft_medium_00[0-4].ogg", length=0.3)),
    "impact_metal": (-6.0, oga(K + "/impactMetal_medium_00[0-4].ogg", length=0.6)),
    "impact_wood": (-6.0, oga(K + "/impactWood_medium_00[0-4].ogg", length=0.4)),
    "melee_flesh": (-3.0, oga(K + "/impactPunch_medium_00[0-4].ogg", K + "/impactSoft_heavy_00[0-1].ogg", length=0.4)),
    "melee_metal": (-3.0, oga(K + "/impactMetal_heavy_00[0-4].ogg", length=0.8)),
    # a spent case hitting the floor: a small piece of metal, high and short, quiet
    "casing": (-14.0, oga(K + "/impactMetal_light_00[0-4].ogg", length=0.25, semis=9)),
    # bows
    "bow_fire": (-3.0, oga(M1 + "/English Longbow Shoot.wav", M1 + "/Scythian Recurve Shoot.wav", length=1.0, mode="events")),
    "bow_draw": (-9.0, oga(M1 + "/English Longbow Draw.wav", M1 + "/Scythian Recurve Draw.wav", length=1.6)),
    "crossbow_fire": (-3.0, oga(M1 + "/Crossbow Shoot.wav", length=1.0, mode="events")),
    "crossbow_load": (-9.0, oga(M1 + "/Crossbow Lever Trigger.wav", M1 + "/Crossbow Place Bolt.wav",
                                M1 + "/Crossbow Set Nut Against Sear.wav", length=1.0, mode="events")),
    "arrow_pass": (-9.0, oga(M1 + "/Scythian Recurve Arrow Pass.wav", M1 + "/Crossbow Bolt Pass.wav", length=1.2)),
    # drawing a blade
    "draw_blade": (-8.0, oga(M2 + "/Dagger Draw Fast.wav", M2 + "/Seax Draw Fast.wav", M2 + "/Sabre Draw Fast.wav",
                             M2 + "/Katana Draw Fast.wav", length=0.9)),
}

def whole_at(rel, length):
    return lambda src: whole(os.path.join(src, rel), length)


def seg(rel, a, b, semis=0):
    """Seconds a..b of one file."""
    def go(src):
        x = load(os.path.join(src, rel))
        return [pitch(x[int(a * RATE):int(b * RATE)].copy(), semis)]
    return go


# The sound sets whose files are not slices of one gun: reloads, racks and clicks.
EXTRA = {
    "reload_out": (-8.0, chain(seg("reloads/assaultriflereload1_0.wav", 0.0, 0.95), seg("reloads/gunreload1.wav", 0.0, 1.2),
                               seg("reloads/gun_reload.2.ogg", 0.0, 0.6), seg("reloads/gun_reload.1.ogg", 0.0, 0.45)), 4),
    "reload_in": (-7.0, chain(seg("reloads/assaultriflereload1_0.wav", 0.95, 1.56), seg("reloads/gunreload1.wav", 1.2, 1.58),
                              seg("reloads/gun_reload.2.ogg", 0.6, 1.36), seg("reloads/gun_reload.1.ogg", 0.45, 0.96)), 4),
    "reload_shell": (-9.0, chain(seg("shotgun/First Shell.mp3", 0.3, 0.8), seg("shotgun/Subsequent Shells.mp3", 0.6, 1.2),
                                 seg("shotgun/Subsequent Shells.mp3", 1.0, 1.6), seg("shotgun/5 Shell Reload.mp3", 1.95, 2.6)), 4),
    "rack": (-6.0, chain(whole_at("shotgun/Rack.mp3", 1.2), whole_at("shotgun/Shell in Chamber.mp3", 1.2)), 2),
    "equip": (-8.0, chain(whole_at("reloads/shotguncock_0.wav", 0.5), seg("reloads/gunreload1.wav", 1.2, 1.58),
                          seg("reloads/assaultriflereload1_0.wav", 0.95, 1.56)), 3),
    "dry": (-10.0, lambda src: shots(os.path.join(src, "reloads/equipment_clicks3.wav"), 0.12, {1, 4, 8, 11, 14}, rel=0.15, gap=0.08), 5),
}


def write(name, arrays, peak_db, max_variants):
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, name + "_*.ogg")):
        os.remove(old)
    arrays = [a for a in arrays if len(a) > int(0.03 * RATE)]
    if not arrays:
        print("  %-14s NO SOURCE" % name)
        return 0
    # Spread the choice over the list so a class draws from every gun rather than the first.
    step = max(1, len(arrays) // max_variants)
    picked = arrays[::step][:max_variants] if len(arrays) > max_variants else arrays
    for i, a in enumerate(picked):
        y = finish(a.astype(np.float32), peak_db)
        raw = (y * 32767).astype("<i2").tobytes()
        dst = os.path.join(OUT, "%s_%d.ogg" % (name, i))
        subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                        "-c:a", "libvorbis", "-q:a", "4", dst], input=raw, check=True)
    return len(picked)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    want = set(sys.argv[2:])
    for name, (peak, maker) in SPECS.items():
        if want and name not in want:
            continue
        cap = FAR_VARIANTS if name.endswith("_far") else MAX_VARIANTS
        n = write(name, maker(src), peak, cap)
        print("  %-14s %d variants" % (name, n))
    for name, (peak, maker, cap) in EXTRA.items():
        if want and name not in want:
            continue
        print("  %-14s %d variants" % (name, write(name, maker(src), peak, cap)))


if __name__ == "__main__":
    main()
