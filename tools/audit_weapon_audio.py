#!/usr/bin/env python3
"""Objective audit of the stock weapon sounds (no ears needed): peak, true peak, K-weighted loudness,
clipping, DC offset, head silence, tail cut-off, spectral centroid, duplicates.

    python3 -I tools/audit_weapon_audio.py [--json out.json] [--dirs stock/weapons stock/shots]

Needs numpy, scipy and ffmpeg. Flags (things to fix) are printed per file; exit 1 when any file has one.
"""
import argparse, json, subprocess, sys
from pathlib import Path
import numpy as np
from scipy import signal

RATE = 44100
ROOT = Path(__file__).resolve().parent.parent / "addons/dot_audio"


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def k_weight(x):
    """BS.1770 K-weighting at 44.1 kHz (high shelf, then the revised low-cut)."""
    f0, g, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    k = np.tan(np.pi * f0 / RATE); vh = 10 ** (g / 20); vb = vh ** 0.4996667741545416
    a0 = 1 + k / q + k * k
    b = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0]
    a = [1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
    y = signal.lfilter(b, a, x)
    f0, q = 38.13547087602444, 0.5003270373238773
    k = np.tan(np.pi * f0 / RATE)
    d = 1 + k / q + k * k
    return signal.lfilter([1, -2, 1], [1, 2 * (k * k - 1) / d, (1 - k / q + k * k) / d], y)


def db(v):
    return 20 * np.log10(max(v, 1e-9))


def measure(x):
    n = len(x)
    peak = float(np.max(np.abs(x))) if n else 0.0
    tp = float(np.max(np.abs(signal.resample_poly(x, 4, 1)))) if n else 0.0
    kw = k_weight(x)
    # Loudness over the active part (within 50 dB of peak), ungated: a shot has no 400 ms block to gate on.
    active = np.abs(x) > peak * 10 ** (-50 / 20)
    ms = float(np.mean(kw[active] ** 2)) if active.any() else 1e-12
    lufs = -0.691 + 10 * np.log10(max(ms, 1e-12))
    rms = float(np.sqrt(np.mean(x ** 2))) if n else 0.0
    nz = np.nonzero(np.abs(x) > peak * 10 ** (-40 / 20))[0]
    tail = x[-int(0.005 * RATE):] if n > 300 else x
    spec = np.abs(np.fft.rfft(x * np.hanning(n))) if n else np.zeros(1)
    fr = np.fft.rfftfreq(n, 1 / RATE) if n else np.zeros(1)
    return {"dur": round(n / RATE, 3), "peak_db": round(db(peak), 2), "tp_db": round(db(tp), 2),
            "lufs_active": round(lufs, 1), "crest_db": round(db(peak) - db(rms), 1),
            "clipped": int(np.sum(np.abs(x) >= 0.999)), "dc": round(float(np.mean(x)) if n else 0.0, 5),
            "head_s": round(float(nz[0] / RATE) if len(nz) else 0.0, 4),
            "tail_end_db": round(db(float(np.sqrt(np.mean(tail ** 2)))) - db(peak), 1),
            "centroid_hz": round(float(np.sum(fr * spec) / max(np.sum(spec), 1e-12)))}


def flags(m, name=""):
    f = []
    if m["tp_db"] > -0.3: f.append("true peak %.1f dBFS" % m["tp_db"])
    if m["clipped"] > 2: f.append("clipped samples %d" % m["clipped"])
    if abs(m["dc"]) > 0.005: f.append("DC offset %.4f" % m["dc"])
    if m["head_s"] > 0.03 and "tail_" not in name and "_far" not in name: f.append("late onset %.0f ms" % (m["head_s"] * 1000))
    if m["tail_end_db"] > -40 and m["dur"] > 0.1: f.append("cut off: last 5 ms only %.0f dB under peak" % m["tail_end_db"])
    if m["peak_db"] < -24: f.append("very quiet, peak %.0f" % m["peak_db"])
    return f


def audit(dirs):
    rows, sigs = {}, {}
    for d in dirs:
        for p in sorted((ROOT / d).rglob("*.ogg")):
            x = decode(p)
            m = measure(x)
            m["flags"] = flags(m, p.name)
            rel = str(p.relative_to(ROOT))
            rows[rel] = m
            sigs[rel] = x
    keys, dup = list(sigs), []
    for i, a in enumerate(keys):
        for b in keys[i + 1:]:
            if len(sigs[a]) == len(sigs[b]) > 2000 and np.sqrt(np.mean(sigs[a] ** 2)) > 0.005 \
                    and np.max(np.abs(sigs[a] - sigs[b])) < 2e-3:
                dup.append((a, b))
    return rows, dup


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    ap.add_argument("--dirs", nargs="*", default=["stock/weapons", "stock/shots"])
    args = ap.parse_args()
    rows, dup = audit(args.dirs)
    bad = 0
    for rel, m in rows.items():
        if m["flags"]:
            bad += 1
            print("%-52s %s" % (rel, "; ".join(m["flags"])))
    for a, b in dup:
        print("DUPLICATE", a, b)
    print("files %d, flagged %d, duplicates %d" % (len(rows), bad, len(dup)))
    if args.json:
        Path(args.json).write_text(json.dumps({"files": rows, "duplicates": dup}, indent=1))
    sys.exit(1 if bad or dup else 0)


if __name__ == "__main__":
    main()
