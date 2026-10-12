#!/usr/bin/env bash
# Plays a game under xvfb, records its master mix and measures it against the family's
# loudness standard (docs/loudness.md in dot-audio): integrated loudness, true peak, loudness
# range, and the RMS of every 3 s window, so a stretch of digital silence shows as well as a
# mix that clips.
#
#   addons/dot_audio/tools/loudness.sh [--seconds=40] [--scene=res://x.tscn] [--no-walk]
#                                      [--fire] [--pilot=res://x.gd] [--keep=out.wav]
#                                      [--label=name] [--web] [-- game args]
#
# --web records the mix with the Master limiter taken off, which is what a web build in
# sample playback (no bus effects) puts out before the page's own limiter.
#
# A game's own tools/loudness_pilot.gd is used when there is one and no --pilot is given
# (--pilot= with nothing turns it off): it drives the local player through the game's inputs
# where the blind stand-in cannot (dot_audio_capture.gd says why).
#
# Run from the game's root. One line out:
#   loudness <label>: I -17.2 LUFS  TP -1.3 dBTP  LRA 6.1 LU  rms3 min/med/max -41/-24/-15 dBFS
#            silent 0/13  verdict ok
set -euo pipefail
GODOT="${GODOT:-godot}"
seconds=40; keep=""; label="$(basename "$PWD")"; pass=(); game=(); pilot=""
while [ $# -gt 0 ]; do
    case "$1" in
        --seconds=*) seconds="${1#*=}"; pass+=("$1") ;;
        --keep=*) keep="${1#*=}" ;;
        --label=*) label="${1#*=}" ;;
        --pilot=*) pilot="${1#*=}"; [ -n "$pilot" ] || pilot="none" ;;
        --) shift; game=("$@"); break ;;
        *) pass+=("$1") ;;
    esac
    shift
done
[ -f project.godot ] || { echo "loudness: run from a Godot project's root" >&2; exit 2; }
[ -z "$pilot" ] && [ -f tools/loudness_pilot.gd ] && pilot="res://tools/loudness_pilot.gd"
[ -n "$pilot" ] && [ "$pilot" != "none" ] && pass+=("--pilot=$pilot")
out="$(mktemp --suffix=.wav)"
log="$(mktemp)"
trap 'rm -f "$out" "$log"' EXIT
limit=$(( ${seconds%.*} + 90 ))
timeout "$limit" xvfb-run -a "$GODOT" --path . --resolution 640x360 \
    --script res://addons/dot_audio/tools/dot_audio_capture.gd -- "--out=$out" "${pass[@]}" "${game[@]}" \
    >"$log" 2>&1 || true
if [ ! -s "$out" ]; then
    echo "loudness $label: no recording"; grep -E "^capture|SCRIPT ERROR|ERROR" "$log" | head -5; exit 1
fi
[ -n "$keep" ] && cp "$out" "$keep"
grep -E "^capture (buses|pilot|camera|web)" "$log" | cut -c1-300 || true
python3 - "$out" "$label" <<'PY'
import re, subprocess, sys, statistics
wav, label = sys.argv[1], sys.argv[2]
r = subprocess.run(["ffmpeg", "-nostats", "-i", wav, "-af", "ebur128=peak=true", "-f", "null", "-"],
                   capture_output=True, text=True).stderr
summary = r[r.rfind("Summary:"):]
def grab(key):
    m = re.search(key + r":\s+(-?[\d.]+|-inf)", summary)
    return float(m.group(1)) if m and m.group(1) != "-inf" else float("-inf")
I, LRA, TP = grab("I"), grab("LRA"), grab("Peak")
# RMS per 3 s window (the play test's measure), from ffmpeg's astats.
r = subprocess.run(["ffmpeg", "-nostats", "-i", wav, "-af",
                    "asetnsamples=n=132300:p=0,astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level",
                    "-f", "null", "-"], capture_output=True, text=True).stderr
rms = []
for m in re.finditer(r"RMS_level=(-?[\d.]+|-inf)", r):
    v = m.group(1)
    rms.append(-120.0 if v == "-inf" else float(v))
rms = rms[:-1] if len(rms) > 1 else rms  # the last window is partial
silent = sum(1 for v in rms if v < -60.0)
med = statistics.median(rms) if rms else float("-inf")
verdict = []
if I < -20.0: verdict.append("quiet")
if I > -14.0: verdict.append("loud")
if TP > -1.0: verdict.append("peaks")
if silent: verdict.append("silences")
print("loudness %s: I %.1f LUFS  TP %.1f dBTP  LRA %.1f LU  rms3 min/med/max %.0f/%.0f/%.0f dBFS  silent %d/%d  verdict %s" % (
    label, I, TP, LRA, min(rms or [0]), med, max(rms or [0]), silent, len(rms), ",".join(verdict) or "ok"))
PY
