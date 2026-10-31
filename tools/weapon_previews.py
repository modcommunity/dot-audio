#!/usr/bin/env python3
"""One preview wav and waveform png per weapon: fire x3, reload out and in, dry click, equip.

Reads the same tables the game reads (DotWeaponSound.FIRE/RELOAD_CLASS/FEEL, ZeeWeaponSound.WEAPONS,
AwWeaponPack.SOUND_CLASSES), so a preview is what a player hears. Needs ffmpeg.

  python3 tools/weapon_previews.py [out_dir]     (default ~/docs/weapon-sound-previews)
"""
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
GODOT = os.path.abspath(os.path.join(ROOT, ".."))
STOCK = os.path.join(ROOT, "addons/dot_audio/stock/weapons")
SOUND = os.path.join(GODOT, "dot-weapon/addons/dot_weapon/core/dot_weapon_sound.gd")
ZEE = os.path.join(GODOT, "zee-dot-weapons/addons/zee_weapons/view/zee_weapon_sound.gd")
AW = os.path.join(GODOT, "arena-weapons/addons/arena_weapons/aw_weapon_pack.gd")
ZEE_IDS = os.path.join(GODOT, "zee-dot-weapons/addons/zee_weapons/content/zee_weapon_ids.gd")


def table(path, name):
    """The `&"a": &"b"` pairs of one const dictionary."""
    text = open(path).read()
    m = re.search(r"const %s\s*:?=\s*\{(.*?)\n\}" % name, text, re.S)
    return dict(re.findall(r'&"(\w+)"\s*:\s*&"(\w+)"', m.group(1))) if m else {}


def stock(name):
    return os.path.join(STOCK, name + "_0.ogg")


def have(name):
    return os.path.exists(stock(name))


def zee_classes():
    """ZeeWeaponSound.WEAPONS keys are ZeeWeaponIds constants; resolve them to their string ids."""
    ids = dict(re.findall(r"const (\w+)\s*:?=\s*&\"(\w+)\"", open(ZEE_IDS).read()))
    text = open(ZEE).read()
    m = re.search(r"const WEAPONS\s*:?=\s*\{(.*?)\n\}", text, re.S)
    out = {}
    for key, cls in re.findall(r"ZeeWeaponIds\.(\w+)\s*:\s*(\w+)", m.group(1)):
        out[ids.get(key, key.lower())] = cls.lower()
    return out


def plan(cls, fire, reload_class, feel):
    parts = []
    if cls in fire:
        parts += [fire[cls]] * 3
    for stage in ("out", "in"):
        n = "reload_shell" if cls == "shotgun" else "reload_%s_%s" % (stage, reload_class.get(cls, ""))
        parts.append(n if have(n) else "reload_" + stage)
    for kind in ("dry", "equip"):
        n = "%s_%s" % (kind, feel.get(cls, ""))
        parts.append(n if cls in feel and have(n) else kind)
    return [p for p in parts if have(p)]


def render(name, parts, out):
    gap = "anullsrc=r=44100:cl=mono:d=0.45"
    cmd = ["ffmpeg", "-v", "error", "-y"]
    for i, p in enumerate(parts):
        cmd += ["-i", stock(p)]
        cmd += ["-f", "lavfi", "-t", "0.45", "-i", gap]
    chain = "".join("[%d:a]aresample=44100,aformat=sample_fmts=s16:channel_layouts=mono[a%d];" % (i, i) for i in range(len(parts) * 2))
    chain += "".join("[a%d]" % i for i in range(len(parts) * 2)) + "concat=n=%d:v=0:a=1[o]" % (len(parts) * 2)
    wav = os.path.join(out, name + ".wav")
    subprocess.run(cmd + ["-filter_complex", chain, "-map", "[o]", wav], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-filter_complex",
                    "showwavespic=s=1400x180:colors=0x3aa0ff", "-frames:v", "1", os.path.join(out, name + ".png")], check=True)


def main():
    out = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/docs/weapon-sound-previews")
    os.makedirs(out, exist_ok=True)
    fire, reload_class, feel = table(SOUND, "FIRE"), table(SOUND, "RELOAD_CLASS"), table(SOUND, "FEEL")
    weapons = {k: v for k, v in zee_classes().items()}
    weapons.update({"aw_" + k: v for k, v in table(AW, "SOUND_CLASSES").items()})
    for name, cls in sorted(weapons.items()):
        parts = plan(cls, fire, reload_class, feel)
        if parts:
            render(name, parts, out)
            print("%-28s %-10s %s" % (name, cls, " ".join(parts)))
    print("%d previews in %s" % (len(weapons), out))


if __name__ == "__main__":
    main()
