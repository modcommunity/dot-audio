#!/usr/bin/env bash
# Builds amb_wind.ogg and amb_outdoor.ogg from the CC0 park recordings by Thimras
# (https://opengameart.org/content/park-ambiences). Usage: make_real_beds.sh <dir with park_ambience_{wind,birds}.wav>
set -euo pipefail
src=${1:?directory with park_ambience_wind.wav and park_ambience_birds.wav}
out="$(dirname "$0")/../addons/dot_audio/stock/ambience"
bed() { # name file start seconds
  local tmp; tmp=$(mktemp -d)
  ffmpeg -v error -y -ss "$3" -t "$4" -i "$src/$2" -ac 1 -ar 44100 "$tmp/seg.wav"
  # Tail crossfaded into the head, so the file loops with no seam.
  ffmpeg -v error -y -ss 3 -i "$tmp/seg.wav" -c copy "$tmp/a.wav"
  ffmpeg -v error -y -t 3 -i "$tmp/seg.wav" -c copy "$tmp/b.wav"
  ffmpeg -v error -y -i "$tmp/a.wav" -i "$tmp/b.wav" -filter_complex "acrossfade=d=3:c1=qsin:c2=qsin" "$tmp/loop.wav"
  local lufs; lufs=$(ffmpeg -nostats -i "$tmp/loop.wav" -af ebur128 -f null - 2>&1 | awk '/I:/{v=$2} END{print v}')
  local gain; gain=$(python3 -c "print(-24.0 - ($lufs))")
  ffmpeg -v error -y -i "$tmp/loop.wav" -af "volume=${gain}dB,alimiter=limit=0.7:level=disabled" -c:a libvorbis -q:a 2 "$out/$1.ogg"
  rm -rf "$tmp"
}
bed amb_wind park_ambience_wind.wav 100 36
bed amb_outdoor park_ambience_birds.wav 40 36
