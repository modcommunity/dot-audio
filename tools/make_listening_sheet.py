#!/usr/bin/env python3
"""Renders the weapon stock into a listening sheet: one self-contained HTML page with an mp3 and a spectrogram per item.

    python3 -I tools/make_listening_sheet.py --plans plans.json --out sheet.html

Sections: layered shots per class (outdoor, indoor, hall, distant), reload timelines (cues placed where fc-weapons'
AwReloadCues puts them; `plans.json` is the `PLAN` lines of `aw_selftest --plans`, one JSON object per line), the
handling-cue gallery, dry/equip, impacts and explosions. Needs numpy, scipy, matplotlib and ffmpeg.
"""
import argparse, base64, io, json, subprocess, sys
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

RATE = 44100
ROOT = Path(__file__).resolve().parent.parent / "addons/dot_audio/stock"
DURATION = {"magazine": 2.4, "pistol": 1.8, "cell": 2.2, "revolver": 3.0, "launcher": 3.0, "tube": 1.8, "bolt": 3.4, "belt": 5.5}
TAIL_DB = -6.0


def load(p):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(p), "-f", "f32le", "-ac", "1", "-ar", str(RATE), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def lay(total, parts):
    out = np.zeros(int(total * RATE))
    for t, x, db in parts:
        a = int(t * RATE)
        seg = x[:max(0, len(out) - a)] * 10 ** (db / 20)
        out[a:a + len(seg)] += seg
    return out


def mp3_b64(x):
    pk = np.max(np.abs(x))
    if pk > 0.89:
        x = x * 0.89 / pk
    raw = x.astype("<f4").tobytes()
    mp3 = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-", "-b:a", "56k",
                          "-f", "mp3", "-"], input=raw, capture_output=True, check=True).stdout
    return base64.b64encode(mp3).decode()


def png_b64(x, marks=()):
    fig, ax = plt.subplots(2, 1, figsize=(6.4, 2.6), dpi=80, gridspec_kw={"height_ratios": [1, 2]}, sharex=True)
    t = np.arange(len(x)) / RATE
    ax[0].plot(t, x, lw=0.4, color="#2a6fdb")
    ax[0].set_ylim(-1, 1)
    ax[0].set_yticks([])
    ax[1].specgram(x, NFFT=512, Fs=RATE, noverlap=384, cmap="magma", vmin=-110, vmax=-30)
    ax[1].set_ylim(0, 12000)
    ax[1].set_ylabel("Hz")
    for m, name in marks:
        ax[1].axvline(m, color="#6cf", lw=0.5)
        ax[1].text(m, 11500, name, fontsize=5, color="#cfe", rotation=90, va="top")
    fig.tight_layout(pad=0.3)
    b = io.BytesIO()
    fig.savefig(b, format="png")
    plt.close(fig)
    return base64.b64encode(b.getvalue()).decode()


def item(title, x, note="", marks=()):
    return {"title": title, "note": note, "mp3": mp3_b64(x), "png": png_b64(x, marks), "secs": round(len(x) / RATE, 2)}


def pick(d, name, i=0):
    p = d / ("%s%d.ogg" % (name, i))
    return load(p) if p.exists() else None


def shots():
    out = []
    for d in sorted((ROOT / "shots").iterdir()):
        if not d.is_dir():
            continue
        a, b = pick(d, "attack_"), pick(d, "body_")
        if a is None and b is None:
            continue
        core = lay(0.6, [(0, a if a is not None else b, 0), (0, b if b is not None else a, -3)])
        for env, tail in (("outdoor", "tail_outdoor_"), ("indoor", "tail_medium_"), ("hall", "tail_hall_")):
            t = pick(d, tail)
            total = 0.6 + (len(t) / RATE if t is not None else 0)
            x = lay(total + 0.1, [(0, core, 0)] + ([(0.03, t, TAIL_DB)] if t is not None else []))
            out.append(item("%s, %s" % (d.name, env), x, "attack + body + %s tail" % tail.strip("_")))
        f = pick(d, "far_")
        if f is not None:
            out.append(item("%s, distant" % d.name, f, "far layer"))
    return out


def reloads(plans):
    out = []
    cues = {}
    for line in plans:
        style = line["style"]
        total = DURATION.get(style, 2.5)
        parts, marks = [], []
        for c in line["plan"]:
            if c["cue"] not in cues:
                cues[c["cue"]] = pick(ROOT / "weapons", "cue_%s_" % c["cue"])
            x = cues[c["cue"]]
            if x is None:
                continue
            parts.append((0.15 + c["t"] * total, x, c["db"] - 4))
            marks.append((0.15 + c["t"] * total, c["cue"]))
        out.append(item("%s (%s)" % (line["role"], style), lay(total + 0.7, parts),
                        "%d cues over a %.1f s reload" % (len(parts), total), marks))
    return out


def gallery():
    out = []
    for p in sorted((ROOT / "weapons").glob("cue_*_0.ogg")):
        out.append(item(p.name[4:-6], load(p)))
    return out


def feel():
    out = []
    for n in ["dry", "dry_light", "dry_heavy", "dry_energy", "equip", "equip_light", "equip_heavy", "equip_energy", "rack", "casing", "reload_shell"]:
        x = pick(ROOT / "weapons", n + "_")
        if x is not None:
            out.append(item(n, x))
    return out


def impacts():
    out = []
    for n in ["impact", "impact_flesh", "impact_metal", "impact_wood", "melee_flesh", "melee_metal", "explosion", "grenade_fire"]:
        x = pick(ROOT / "weapons", n + "_")
        if x is not None:
            out.append(item(n, x))
    return out


CSS = """
:root{--bg:#f6f7f9;--fg:#15181d;--mut:#5b6573;--card:#fff;--bd:#d9dee5;--acc:#2a6fdb}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#0f1216;--fg:#e8ebef;--mut:#9aa5b3;--card:#171b21;--bd:#2a313b;--acc:#6aa5ff}}
:root[data-theme="dark"]{--bg:#0f1216;--fg:#e8ebef;--mut:#9aa5b3;--card:#171b21;--bd:#2a313b;--acc:#6aa5ff}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 64px}h1{font-size:26px;margin:0 0 4px}h2{font-size:19px;margin:36px 0 4px;border-bottom:1px solid var(--bd);padding-bottom:6px}
p.lede{color:var(--mut);margin:4px 0 12px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:12px;margin-top:12px}
.card{background:var(--card);border:1px solid var(--bd);border-radius:10px;padding:10px}.card h3{font-size:14px;margin:0}.card .n{color:var(--mut);font-size:12px;margin-bottom:6px}
.card img{width:100%;height:auto;display:block;border-radius:6px}audio{width:100%;height:34px;margin-top:6px}
nav a{color:var(--acc);margin-right:12px}
"""


def html(sections, intro):
    h = ['<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">',
         "<title>Weapon Listening Sheet</title><style>%s</style></head><body><main>" % CSS,
         "<h1>Weapon listening sheet</h1><p class='lede'>%s</p><nav>%s</nav>" % (intro, "".join('<a href="#%s">%s</a>' % (k, t) for k, t, _, _ in sections))]
    for k, t, d, items in sections:
        h.append('<h2 id="%s">%s</h2><p class="lede">%s</p><div class="grid">' % (k, t, d))
        for it in items:
            h.append('<div class="card"><h3>%s</h3><div class="n">%s %.2f s</div><img alt="waveform and spectrogram of %s" src="data:image/png;base64,%s">'
                     '<audio controls preload="none" src="data:audio/mpeg;base64,%s"></audio></div>' % (it["title"], it["note"] + " · " if it["note"] else "", it["secs"], it["title"], it["png"], it["mp3"]))
        h.append("</div>")
    h.append("</main></body></html>")
    return "".join(h)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plans")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    plans = []
    if a.plans:
        for line in Path(a.plans).read_text().splitlines():
            if line.startswith("PLAN "):
                plans.append(json.loads(line[5:]))
    secs = [("shots", "Layered shots", "Per weapon class: transient + body + room tail, as the game layers them, outdoors, indoors (medium room), in a hall, and the distant layer.", shots())]
    if plans:
        secs.append(("reloads", "Reload timelines", "Each gun's reload with its handling cues placed at the animation phase that makes them (blue lines in the spectrogram). Cue timing is the plan fc-weapons plays from.", reloads(plans)))
    secs += [("cues", "Handling cues", "The 37 synthesised cues, first variant of three.", gallery()),
             ("feel", "Dry fire, equip, casings", "", feel()), ("impacts", "Impacts and explosions", "Stock impact, flesh, melee and explosion sounds (the game's own synthesised hit-marker, kill and headshot voices are listed on the game-fatal-contact branch).", impacts())]
    Path(a.out).write_text(html(secs, "Self-synthesised or CC0. Every clip is the exact stock file or a mix of stock files; nothing here is licensed."))
    print("wrote", a.out, Path(a.out).stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
