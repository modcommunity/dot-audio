# dot-audio

Audio as a catalogue of ids: a pool with priorities, concurrency caps, cooldowns, a distance cull, music crossfades and ducking, and a synthesiser for games with no audio files yet; plus the family's footsteps by surface, ambience beds per map and zone, the loudness standard (−17 LUFS, −1 dBTP) with its master limiter, and the tool that measures a game against it. The whole path runs on a machine with no speakers.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to audio.

**The distributable is `addons/dot_audio/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: the sink seam, the pieces, paths not streams, culling, stealing, ducking, variation, silence on failure, looping, reaping, the synthesiser, what is not here |
| [docs/loudness.md](docs/loudness.md) | footsteps, ambience, a level, the limiter, or measuring a game: the standard and why, the capture tool, the stock set |
| [docs/weapons.md](docs/weapons.md) | a weapon sound: the audit of what every pack played, the stock table, how packs read it |
| [docs/ambience.md](docs/ambience.md) | the creepy-ambience layer: moods, sound-set format, settings, map to mood |
| [docs/history.md](docs/history.md) | touching reaping, looping or the suite's frame waits: the pause-menu silence, the unread `looping` |

## Layout

| Path | What |
| --- | --- |
| `core/dot_audio_def.gd` | `DotAudioDef`: one sound; a path, variants, pitch range, limits, `looping`, `generated` |
| `core/dot_audio_catalogue.gd` | `DotAudioCatalogue`: `validate()` (the document), `missing_files()` (the disk) |
| `core/dot_audio_mixer.gd` | `DotAudioMixer`: sliders and the `linear_to_db` curve, a `DotConfig` |
| `core/dot_audio_synth.gd` | `DotAudioSynth`: thirteen role voices baked to `AudioStreamWAV` |
| `sink/` | `DotAudioSink` (`device_present()`), `DotAudioSinkGodot` (pool, stealing, `bank`), `DotAudioSinkNull`, `dot_audio_raw_streams.gd` (`stream_at`'s cache, by path) |
| `core/dot_audio_stock.gd` | `DotAudioStock`: the stock footsteps and beds as defs, `add_to`, surface names and aliases |
| `core/dot_audio_loudness.gd` | `DotAudioLoudness`: the standard's numbers, `install_limiter` |
| `runtime/dot_audio_footsteps.gd` | `DotAudioFootsteps`: steps by distance and surface for any number of bodies; `stepped` |
| `runtime/dot_audio_ambience.gd` | `DotAudioAmbience`: a bed per map, zones by box, equal-power crossfades |
| `runtime/dot_ambience.gd` | `DotAmbience`: moods (looping beds plus sparse random one-shots), crossfade on a change, `pause`/`duck`/`hush` holders, `describe()`; `runtime/dot_ambience_roof.gd` (`DotAmbienceRoof`: upward ray with hysteresis; the game feeds `set_indoors`), `core/dot_ambience_{config,set,mood,moods}.gd` are its settings, sound-set reader and map-to-mood table |
| `runtime/dot_ambience_director.gd`, `core/dot_ambience_rules.gd` | `DotAmbienceDirector`: map to mood, roof, settings and the server's rules, over `stock/moods/` (the shared eight-mood set) |
| `core/dot_audio_weapon_stock.gd` | `DotAudioWeaponStock`: the 41 stock weapon sounds as `weapon_<name>` defs; `COUNTS` must match `stock/weapons/` |
| `stock/` | CC0 footsteps (Kenney) and generated beds; `CREDITS.md` |
| `web/dot_audio_ceiling.js` | the browser's limiter, loaded by a page before the engine |
| `tools/loudness.sh`, `tools/dot_audio_capture.gd` | record a game under xvfb and measure it; run from a game's root; a game's `tools/loudness_pilot.gd` drives its player |
| `runtime/dot_audio_manager.gd` | `DotAudioManager`: ids in, limits, `listener_position`, `roll_source`, `play_music`, `duck`, `shape`/`voice` a playing handle |
| `dot_audio_api.gd` | the API level (`DotAddonApi`); bump `LEVEL` for anything a game can newly call |
| `examples/audio_selftest.tscn` | the suite; needs no sound card |
| `examples/exit_leak_probe.tscn` | loads dot-audio as a game's suite does and quits; the suite runs it as a child and reads its stderr |

Paths except `examples/` and the repository's `tools/make_ambience.py` (regenerates the beds) are in `addons/dot_audio/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/audio_selftest.tscn`. `CHECKS` is a total as well as a section count, because a script error aborts one test, not the run.

A green run prints "3 ObjectDB instances were leaked at exit": `--verbose` names them as `AudioStreamPlaybackWAV` / `AudioStreamGeneratorPlayback` objects from the synth section's `play()` calls, which the dummy driver creates and never mixes. Stopping every voice and freeing the host does not change it. A count that grows without new `play()` calls in the suite is a real leak, and any "resources still in use" line is one (section 14 runs `examples/exit_leak_probe.tscn` in a child process and fails on it). [history](docs/history.md#a-static-cache-kept-a-games-whole-run-alive-at-exit-2026-10-12)

## Rules that bite

- Only `DotAudioSink.device_present()` (the driver name) says whether there is a device; never the mix rate or device list. [design](docs/design.md#the-sink-is-a-seam-because-the-engine-lies)
- The null sink runs the real limits; keep logic in the manager, not the Godot sink. [design](docs/design.md#the-sink-is-a-seam-because-the-engine-lies)
- A def names a file by path and never loads or preloads it; a def with no file sets `generated`. [design](docs/design.md#a-path-not-a-stream)
- Cull by distance in the manager; the game sets `listener_position` every frame. [design](docs/design.md#culling-is-in-the-manager-not-the-sink)
- A full pool steals only lower priority, else refuses. [design](docs/design.md#stealing-goes-downwards-only)
- Ducking is reference-counted per holder, never a boolean. [design](docs/design.md#ducking-is-reference-counted)
- Variants and pitch come from a roll; give `roll_source` a `DotRandomStream` for reproducible sound. [design](docs/design.md#variation-belongs-in-the-document)
- A missing sound is a debug-logged refusal, never an error. [design](docs/design.md#a-missing-sound-is-silence-not-an-error)
- Change a playing voice with `manager.shape(h, volume_scale, pitch_scale)` (play()'s units, def gain and rolled pitch kept), never by restarting it or subclassing the Godot sink. [design](docs/design.md#a-playing-voice-is-shaped-in-plays-units)
- No `static var` written by its own static function in a script that extends another (the sinks): the engine's 4.7.2 exit teardown then kept a game's whole run alive at exit. Such a cache is a script of its own (`sink/dot_audio_raw_streams.gd`). [history](docs/history.md#a-static-cache-kept-a-games-whole-run-alive-at-exit-2026-10-12)
- A process that ran `stream_at` calls `DotAudioSinkGodot.clear_streams()` before `quit()` (after the last manager left the tree), or the cached streams are "resources still in use" at exit. [history](docs/history.md#a-static-cache-kept-a-games-whole-run-alive-at-exit-2026-10-12)
- Loop a copy of the stream, never the shared one. [design](docs/design.md#looping-copies-the-stream)
- Reap where a count is consulted, not only in `_process` (which stops while paused). [design](docs/design.md#reaping-happens-at-the-point-of-refusal)
- A real file always outranks the synth bank; which voice stands in for which id is the game's `sound_recipes()`. [design](docs/design.md#the-synthesiser-is-consulted-after-the-filesystem-never-before)
- `SceneTree.process_frame` fires before `Node._process`; a test must not await a frame to see `_process` run. [history](docs/history.md#a-pause-menu-silenced-the-game)

- Measure a level with `addons/dot_audio/tools/loudness.sh` under xvfb, never headless or Movie Maker (Dummy driver, null sink, silence). [loudness](docs/loudness.md#measuring-addonsdot_audiotoolsloudnesssh)
- Trust a level only from a run whose `capture camera:` line shows the local player moving; a game the stand-in cannot play brings `tools/loudness_pilot.gd` (`drive(capture, ms)` through the capture's `key`/`turn`/`click`/`point`, never moving a body). [loudness](docs/loudness.md#measuring-addonsdot_audiotoolsloudnesssh)
- Set a game's level in its catalogue; `limit_master` is a backstop (not on the web: sample playback runs no bus effects) and `loudness_trim_db` a measured nudge added to every voice's gain. [loudness](docs/loudness.md#how-it-is-held)
- A web page loads `web/dot_audio_ceiling.js` before the engine: the browser's limiter, since the engine's does not run there. [loudness](docs/loudness.md#the-browsers-ceiling)
- A sound path resolves through `DotAudioSinkGodot.stream_at` (the import, else the file's own bytes when an addon pack brought no imported output); never `load()` a def's path directly. [loudness](docs/loudness.md#the-stock-set)
- A footstep is distance on the ground, silent under `quiet_speed`; a surface comes from the collider (`surface` meta, `surface_<name>` group, node name) else the map's `default_surface`. [loudness](docs/loudness.md#footsteps-dotaudiofootsteps)
- Every map sets a bed (`set_map_bed`); nothing may be digital silence. Beds are −24 LUFS; regenerate with `tools/make_ambience.py`, never edit an `.ogg` by hand. [loudness](docs/loudness.md#the-stock-set)

- `DotAmbience` is stepped by `advance(delta)`; `_process` only calls it. Its content is a sound set (`moods.json`) a game ships and a server owner may add to (`sound_dir`); the addon ships none. [ambience](docs/ambience.md)

Deliberately not here: game audio beyond the stock set, DSP, per-voice fades (`_ramp` is the subclass point), a stem player, voice chat. [design](docs/design.md#deliberately-not-here)
