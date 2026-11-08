#!/usr/bin/env python3
"""Fixes what tools/audit_weapon_audio.py flags in the stock weapon sounds, and levels stock/weapons by category.

    python3 -I tools/polish_weapon_stock.py [--dry-run] [--report out.json]

Per file: remove DC, trim leading silence (weapons/ only; shot layers keep their reverb pre-delay), fade a cut-off tail,
soft-limit true peaks over -1.5 dBFS. stock/weapons/ is then levelled to a per-category K-weighted active loudness
(TARGETS), so a pistol and a rifle differ by what a person would expect, not by 25 LU of accident. stock/shots/ layers
keep their balance (DotShotPlayer mixes them) and are only repaired. Only files that change are re-encoded (Ogg Vorbis q4).
"""
import argparse, json, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import foley as F
from audit_weapon_audio import ROOT, decode, measure

CEIL_DB = -1.5
# name prefix (first match) -> active LUFS. Tuned so the loudest report is about 6 LU over the quietest foley.
TARGETS = [
    ("cue_", None),  # synthesised and levelled by make_reload_cues.py already
    ("suppressed", -27), ("bow_fire", -25), ("crossbow_fire", -25), ("derringer", -23), ("minigun", -24), ("beam", -22),
    ("charge", -21), ("light", -23), ("smg", -23), ("mpistol", -23), ("magnum", -21), ("rifle", -21), ("carbine", -21),
    ("battle", -21), ("marksman", -20), ("lmg", -21), ("autoshot", -20), ("heavy_fire", -19), ("heavy_far", -27),
    ("sniper", -19), ("shotgun", -19), ("rail", -20), ("launcher", -20), ("grenade", -21), ("explosion", -18),
    ("impact_flesh", -23), ("impact", -25), ("melee", -22), ("bash", -25), ("swing", -27), ("throw", -27), ("arrow_pass", -29),
    ("dry", -27), ("equip", -26), ("rack", -23), ("casing", -31), ("pin_pull", -25), ("draw_blade", -27), ("bow_draw", -29),
    ("crossbow_load", -29), ("reload", -25),
]
FAR_OFFSET = -6.0  # a *_far recording sits this far under its close report


def target_for(name):
    for prefix, t in TARGETS:
        if name.startswith(prefix):
            if t is None:
                return None
            return t + (FAR_OFFSET if "_far" in name and not name.startswith("heavy_far") else 0.0)
    return None


def soft_limit(x, ceil_db):
    th = 10 ** ((ceil_db - 3.0) / 20)
    top = 10 ** (ceil_db / 20)
    a = np.abs(x)
    over = a > th
    y = x.copy()
    y[over] = np.sign(x[over]) * (th + (top - th) * np.tanh((a[over] - th) / (top - th)))
    return y


def polish(path, kind):
    x = decode(path)
    orig = x.copy()
    x = x - np.mean(x)
    pk = np.max(np.abs(x))
    if pk <= 1e-6:
        return None, ["silent"]
    notes = []
    if kind == "weapons":
        onset = int(np.argmax(np.abs(x) > pk * 10 ** (-42 / 20)))
        keep = max(0, onset - int(0.0015 * F.RATE))
        if keep > int(0.004 * F.RATE):
            x = x[keep:]
            notes.append("trim %.0f ms" % (keep / F.RATE * 1000))
    tail = x[-int(0.005 * F.RATE):]
    if len(x) > 4410 and 20 * np.log10(max(np.sqrt(np.mean(tail ** 2)), 1e-9) / pk) > -45:
        f = min(len(x) // 3, int(0.025 * F.RATE))
        x = x.copy()
        x[-f:] *= 0.5 * (1 + np.cos(np.linspace(0, np.pi, f)))
        notes.append("tail fade")
    if abs(float(np.mean(orig))) > 0.003:
        notes.append("dc")
    if kind == "weapons":
        t = target_for(path.stem.rsplit("_", 1)[0])
        if t is not None:
            m = measure(x)
            g = float(np.clip(t - m["lufs_active"], -12.0, 12.0))
            if abs(g) >= 1.0:
                x = x * 10 ** (g / 20)
                notes.append("gain %+.1f dB" % g)
    tp = np.max(np.abs(x))
    if tp > 10 ** ((CEIL_DB + 0.4) / 20):
        x = soft_limit(x, CEIL_DB)
        notes.append("limit")
    return (x if notes else None), notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--report")
    a = ap.parse_args()
    report = {}
    for kind in ("weapons", "shots"):
        for p in sorted((ROOT / "stock" / kind).rglob("*.ogg")):
            x, notes = polish(p, kind)
            if x is None:
                continue
            report[str(p.relative_to(ROOT))] = notes
            if not a.dry_run:
                F.to_ogg(x, p, quality=4)
    for k, v in report.items():
        print("%-48s %s" % (k, ", ".join(v)))
    print("changed %d" % len(report))
    if a.report:
        Path(a.report).write_text(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
