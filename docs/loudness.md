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
- **The web build has no limiter.** A web export in sample playback mode does not run bus effects, so the backstop does nothing there; the catalogue levels and the trim, which are per voice, still apply. That is why levels belong in the catalogue and never lean on the limiter.

## Measuring: `addons/dot_audio/tools/loudness.sh`

Run from any game's root (the addon is linked into every game):

```bash
addons/dot_audio/tools/loudness.sh --seconds=40 --warmup=6 --fire [--scene=res://x.tscn] [--keep=mix.wav] [-- game args]
```

It plays the game under `xvfb-run` with `dot_audio_capture.gd` as the main loop: the main scene (or `--scene`), a stand-in player that walks, sprints, jumps and turns through `Input.parse_input_event` (so every game's own bindings see it), and an `AudioEffectRecord` on Master. It prints one line: integrated loudness, true peak, loudness range, the minimum, median and maximum RMS of 3 s windows, how many windows were digital silence, and a verdict.

Three things about it are decisions:

- **xvfb, never headless and never Movie Maker.** Both run the Dummy audio driver, where `DotAudioSink.device_present()` is false and dot-audio plays nothing. A recording of either is silence that proves nothing.
- **The recorder is moved to the end of Master when recording starts.** A game's setup adds the limiter after the script adds anything, and a meter in front of the limiter measures a mix nobody hears.
- **Wall-clock time, not `--fixed-fps`.** Audio is mixed in real time; a game stepped at a fixed rate on a slow software renderer plays its events sparser than they happen.

A game whose main scene is a menu or a lobby that waits for a click records the menu: pass `--scene` or the game's own arguments.

## Footsteps: `DotAudioFootsteps`

One node per game; `track(body)` for the player, other players and bots.

- **A step is distance, not time or animation.** Every 1.5 m at a walk to 2.3 m at a run, measured on the ground plane, so a body moved by netcode interpolation or a navigation agent steps at the rate it really moves.
- **Slow is silent.** Under `quiet_speed` (1.4 m/s) nothing plays; sneaking is a mechanic in a hiding game.
- **A landing after `landing_air_time` in the air is one full step**, a teleport (over 4 m in a frame) is nothing.
- **The surface comes from the ground collider**: its `surface` meta or a parent's, a `surface_<name>` group, or a surface word in the node name, folded through `DotAudioStock.surface_of` (so `stone`, `asphalt` and `Floor_Tile` are concrete). Anything else is `default_surface`, which a game sets per map.
- **`stepped(body, surface, loudness)`** is what a listening bot hears, so a game needs no second footstep system for its AI.

## Ambience: `DotAudioAmbience`

`set_map_bed(id)` on every map load, `add_zone(aabb, bed, priority)` for a building, a tunnel or a cave inside it. Beds crossfade with an equal-power curve through `DotAudioManager.shape()`, because the manager's own fade is a subclass point that does nothing by default. A map that names no bed gets `fallback_bed`; a bed that was stolen or stopped is started again at the next check. Zones are boxes in data, not `Area3D` nodes, so a map document carries them and a server never builds them.

## The stock set

`addons/dot_audio/stock/`, every file CC0 (`stock/CREDITS.md`), as defs from `DotAudioStock`:

- **Footsteps**: Kenney's Impact Sounds, five each of concrete, wood, grass, snow and carpet, and five light metal impacts for metal; mono, levelled against each other in `_FOOTSTEP_GAIN`.
- **Beds**: nine 32 s seamless stereo loops synthesised by `tools/make_ambience.py` from fixed seeds (wind, outdoor, night, city, indoor, eerie, industrial, cave, rain), each normalised to −24 LUFS, about seven units under the target so a bed sits under the action at mixer level 1.0. Kenney's packs have no ambience; a bed is filtered noise and sparse events, which arithmetic does well, and a generated file is ours to license.

**Why an addon that ships no audio ships these**: the rule is about the catalogue (a def names a path, never holds a stream), and it still holds. These are the same thirty-nine files in every game, and thirteen vendored copies would be thirteen places to fix one level. A game that wants its own defines the same id before `DotAudioStock.add_to` and wins.
