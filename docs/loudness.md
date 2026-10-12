# Loudness, footsteps and ambience

Why every game in the family sounds about as loud as every other, why none of them goes silent, and how that is measured. The one-line rules are in [CLAUDE.md](../CLAUDE.md).

## The standard

| | Target | Why |
| --- | --- | --- |
| Integrated loudness of a captured stretch of play | **−17 LUFS**, band −18 to −16 | A player sets their volume once. In the first play test one game sat at −5 dBFS RMS and the others near −25: the player turned the loud one down and then could not hear the next. −16 to −18 is where game mixes for speakers and headphones usually land, loud enough for a laptop, with room for a gunshot to stand out. |
| True peak | **at or under −1 dBTP** | A lossy encoder (the web build's audio, a stream, a recording) and a cheap DAC clip a signal whose peaks between samples go over 0 dBFS even when every sample is under it. |
| 3 s windows of digital silence (RMS under −60 dBFS) | **none** | Silence between events reads as broken, not as quiet. Two games were mostly digital silence in the play test. |

The tool's verdict says `quiet` under −20 LUFS and `loud` over −14, which is the band with a tolerance for what a stand-in player happens to do in forty seconds; a game is tuned toward −17.

## How it is held

- **Levels are set in the catalogue.** `gain_db` per def is the mix. A game that is out of band is mixed again, not limited harder.
- **The master limiter is a backstop.** `DotAudioManager.limit_master` (on by default) puts an `AudioEffectHardLimiter` at the end of Master with its ceiling at −2 dBFS: a decibel under the true-peak ceiling because the peaks between samples of a limited signal land above its sample peaks (at −1.5 a game measured −0.9 dBTP). It catches ten things at once; a mix that leans on it sounds squashed.
- **`DotAudioManager.loudness_trim_db`** is the whole-game nudge, added to every voice's gain (so it reaches the browser too), set from a measurement and never by ear.
- **The web build's limiter is the page's.** A web export in sample playback mode does not run bus effects, so the Master limiter does nothing there; the catalogue levels and the trim, which are per voice, still apply, and `addons/dot_audio/web/dot_audio_ceiling.js`, loaded before the engine, puts a limiter in front of the page's speakers. See [the browser's ceiling](#the-browsers-ceiling).

## Measuring: `addons/dot_audio/tools/loudness.sh`

Run from any game's root (the addon is linked into every game):

```bash
addons/dot_audio/tools/loudness.sh --seconds=40 --warmup=6 --fire [--scene=res://x.tscn] [--keep=mix.wav] [-- game args]
```

It plays the game under `xvfb-run` with `dot_audio_capture.gd` as the main loop: the main scene (or `--scene`), a stand-in player that walks, sprints, jumps and turns through `Input.parse_input_event` (so every game's own bindings see it), and an `AudioEffectRecord` on Master. It prints one line: integrated loudness, true peak, loudness range, the minimum, median and maximum RMS of 3 s windows, how many windows were digital silence, and a verdict.

Before that line it prints how far the camera went while recording (`capture camera:`). In every game here the camera rides the local player, so a camera that stayed put is a recording of somebody standing still, whatever the stand-in pressed: the bots' steps, their guns and the bed, and a trim set from it is set against the wrong mix. That is how the levels of three games were wrong on 2026-10-12. `--web` takes the limiter off Master before recording: what a browser's engine puts out before the page's ceiling.

Four things about it are decisions:

- **xvfb, never headless and never Movie Maker.** Both run the Dummy audio driver, where `DotAudioSink.device_present()` is false and dot-audio plays nothing. A recording of either is silence that proves nothing.
- **The recorder is moved to the end of Master when recording starts.** A game's setup adds the limiter after the script adds anything, and a meter in front of the limiter measures a mix nobody hears.
- **Wall-clock time, not `--fixed-fps`.** Audio is mixed in real time; a game stepped at a fixed rate on a slow software renderer plays its events sparser than they happen.
- **The local player is driven through its own inputs, by a pilot where blind keys are not enough.** The stand-in holds W, sprints, jumps and turns, and turns wide when the camera has not moved for 0.6 s (it walked into a wall). A game it still cannot play brings `tools/loudness_pilot.gd`, which `loudness.sh` passes as `--pilot`: `drive(capture, ms)` every frame, playing through the capture's `key`, `turn`, `click` and `point` (input events and a warped pointer, so the game's sampler and bindings read them as they read a player), and `describe()`, printed as `capture pilot:`, says what the player did. game-arena (walks off walls, fires bursts), game-playground (spawns and punts props) and game-hungario (a pointer-steered monster that eats and flees) have one. Nothing in a pilot moves a body directly.

A game whose main scene is a menu or a lobby that waits for a click records the menu: pass `--scene` or the game's own arguments.

## The browser's ceiling

A web build in sample playback runs no bus effects, so nothing held the ceiling there. Measured 2026-10-12 in headless Chromium on a web export of game-arena (its offline match, the recording tapped between the engine and the speakers): **+3.4 dBFS in float, 187 clipped samples in 40 s.** The same game on desktop, recorded with `loudness.sh --web` (the limiter taken off Master), reads +0.7 dBTP and 1.5 LU louder than with it: the desktop limiter was doing real work at the family level, and the browser had none.

`addons/dot_audio/web/dot_audio_ceiling.js` is the browser's limiter. The engine's Web Audio graph cannot be reached from a script once it exists, so the file wraps the page's `AudioContext` before the engine makes one and hands it a `destination` that is a chain: a `DynamicsCompressorNode` above -3 dBFS (ratio 20, 2 ms attack, 100 ms release), a gain that takes off the makeup gain the Web Audio spec adds to every compressor (otherwise a browser would be about 1.7 dB louder than a desktop), and a `WaveShaperNode` soft clip, oversampled 4x, whose curve never passes -1.5 dBFS. A page loads it before `index.js` (dot-server-deploy's `export-web` copies it beside the build and puts it in both pages).

| Run (arena, 2026-10-12) | Integrated | Peak |
| --- | --- | --- |
| Chromium, no ceiling | -20.0 LUFS | +3.4 dBFS float, clipped |
| Chromium, the ceiling | -20.9 LUFS | -2.0 dBTP, nothing clipped |
| The desktop mix without its limiter, through the chain offline (Chromium `OfflineAudioContext`) | -15.6 -> -16.3 LUFS | +0.3 -> -2.2 dBTP |
| The same 3 dB hotter | -12.8 -> -14.1 LUFS | +1.1 -> -1.9 dBTP |
| The same 10 dB quieter | -25.6 -> -25.6 LUFS | -9.4 -> -9.4 dBFS (unity below the threshold) |

The two live runs are different stretches of play (the local player does not move under Chromium's software renderer), so compare their peaks, not their loudness; the offline rows are the same signal both ways. A script-side guard was tried first and dropped: summing what each voice dot-audio starts could reach (file peak, gain, bus chain, distance) cut 150 voices a run by up to 12 dB and still let +0.1 dBTP through, because the estimate is the worst case for every voice at once and the loudest sounds in two games (zee-dot-weapons' reports) never pass through dot-audio at all. The page sees everything the engine plays.

## Footsteps: `DotAudioFootsteps`

One node per game; `track(body)` for the player, other players and bots.

- **A step is distance, not time or animation.** Every 1.5 m at a walk to 2.3 m at a run, measured on the ground plane, so a body moved by netcode interpolation or a navigation agent steps at the rate it really moves.
- **Slow is silent.** Under `quiet_speed` (1.4 m/s) nothing plays; sneaking is a mechanic in a hiding game.
- **A landing after `landing_air_time` in the air is one full step**, a teleport (over 4 m in a frame) is nothing.
- **The surface comes from the ground collider**: the hit shape's or its `surface` meta (or dot-player-controller's `dot_fps_surface`), or a parent's, a `surface_<name>` group, or a surface word in the node name, folded through `DotAudioStock.surface_of` (so `stone`, `asphalt` and `Floor_Tile` are concrete). Anything else is `default_surface`, which a game sets per map.
- **`stepped(body, surface, loudness)`** is what a listening bot hears, so a game needs no second footstep system for its AI.

## Ambience: `DotAudioAmbience`

`set_map_bed(id)` on every map load, `add_zone(aabb, bed, priority)` for a building, a tunnel or a cave inside it. Beds crossfade with an equal-power curve through `DotAudioManager.shape()`, because the manager's own fade is a subclass point that does nothing by default. A map that names no bed gets `fallback_bed`; a bed that was stolen or stopped is started again at the next check. Zones are boxes in data, not `Area3D` nodes, so a map document carries them and a server never builds them.

## The stock set

`addons/dot_audio/stock/`, every file CC0 (`stock/CREDITS.md`), as defs from `DotAudioStock`:

- **Footsteps**: Kenney's Impact Sounds, five each of concrete, wood, grass, snow and carpet, and five light metal impacts for metal; mono, levelled against each other in `_FOOTSTEP_GAIN`.
- **Beds**: nine 32 s seamless stereo loops synthesised by `tools/make_ambience.py` from fixed seeds (wind, outdoor, night, city, indoor, eerie, industrial, cave, rain), each normalised to −24 LUFS, about seven units under the target so a bed sits under the action at mixer level 1.0. Kenney's packs have no ambience; a bed is filtered noise and sparse events, which arithmetic does well, and a generated file is ours to license.

**Why an addon that ships no audio ships these**: the rule is about the catalogue (a def names a path, never holds a stream), and it still holds. These are the same thirty-nine files in every game, and thirteen vendored copies would be thirteen places to fix one level. A game that wants its own defines the same id before `DotAudioStock.add_to` and wins.

**And why they still play when they arrive in an addon pack.** An addon release reaches players as an overlay over the build's `res://addons/dot_audio/` (dot-cloud's addon packs), made from the release zip: tracked files only, so `x.ogg` and `x.ogg.import` with no `.godot/imported/` output behind the marker. On a shell exported before the stock set existed, the importer follows the marker to nothing. `DotAudioSinkGodot.stream_at` reads the marker first and, when its output is missing and the source file is there, decodes the file from its own bytes (Ogg Vorbis, WAV, MP3) once per path. A shell exported with the stock set carries all 39 imported outputs and markers (checked in the Linux and Web exports, 2026-10-12) and never takes that path.
