# dot-audio

Audio as a catalogue of ids: a pool with priorities, concurrency caps, cooldowns, a distance cull, music crossfades and ducking, and a synthesiser for games with no audio files yet. The whole path runs on a machine with no speakers.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to audio.

**The distributable is `addons/dot_audio/`.** It requires [dot-core](../dot-core) and nothing else (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: the sink seam, the pieces, paths not streams, culling, stealing, ducking, variation, silence on failure, looping, reaping, the synthesiser, what is not here |
| [docs/history.md](docs/history.md) | touching reaping, looping or the suite's frame waits: the pause-menu silence, the unread `looping` |

## Layout

| Path | What |
| --- | --- |
| `core/dot_audio_def.gd` | `DotAudioDef`: one sound; a path, variants, pitch range, limits, `looping`, `generated` |
| `core/dot_audio_catalogue.gd` | `DotAudioCatalogue`: `validate()` (the document), `missing_files()` (the disk) |
| `core/dot_audio_mixer.gd` | `DotAudioMixer`: sliders and the `linear_to_db` curve, a `DotConfig` |
| `core/dot_audio_synth.gd` | `DotAudioSynth`: thirteen role voices baked to `AudioStreamWAV` |
| `sink/` | `DotAudioSink` (`device_present()`), `DotAudioSinkGodot` (pool, stealing, `bank`), `DotAudioSinkNull` |
| `runtime/dot_audio_manager.gd` | `DotAudioManager`: ids in, limits, `listener_position`, `roll_source`, `play_music`, `duck` |
| `examples/audio_selftest.tscn` | the suite; needs no sound card |

Paths except `examples/` are in `addons/dot_audio/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/audio_selftest.tscn`. `CHECKS` is a total as well as a section count, because a script error aborts one test, not the run.

A green run prints "ObjectDB instances were leaked at exit" and "resources still in use": `--verbose` names them as `AudioStreamPlaybackWAV` / `AudioStreamGeneratorPlayback` objects, one per `play()` the synth section makes, which the dummy driver creates and never mixes. Stopping every voice and freeing the host does not change it. A count that grows without new `play()` calls in the suite is a real leak.

## Rules that bite

- Only `DotAudioSink.device_present()` (the driver name) says whether there is a device; never the mix rate or device list. [design](docs/design.md#the-sink-is-a-seam-because-the-engine-lies)
- The null sink runs the real limits; keep logic in the manager, not the Godot sink. [design](docs/design.md#the-sink-is-a-seam-because-the-engine-lies)
- A def names a file by path and never loads or preloads it; a def with no file sets `generated`. [design](docs/design.md#a-path-not-a-stream)
- Cull by distance in the manager; the game sets `listener_position` every frame. [design](docs/design.md#culling-is-in-the-manager-not-the-sink)
- A full pool steals only lower priority, else refuses. [design](docs/design.md#stealing-goes-downwards-only)
- Ducking is reference-counted per holder, never a boolean. [design](docs/design.md#ducking-is-reference-counted)
- Variants and pitch come from a roll; give `roll_source` a `DotRandomStream` for reproducible sound. [design](docs/design.md#variation-belongs-in-the-document)
- A missing sound is a debug-logged refusal, never an error. [design](docs/design.md#a-missing-sound-is-silence-not-an-error)
- Loop a copy of the stream, never the shared one. [design](docs/design.md#looping-copies-the-stream)
- Reap where a count is consulted, not only in `_process` (which stops while paused). [design](docs/design.md#reaping-happens-at-the-point-of-refusal)
- A real file always outranks the synth bank; which voice stands in for which id is the game's `sound_recipes()`. [design](docs/design.md#the-synthesiser-is-consulted-after-the-filesystem-never-before)
- `SceneTree.process_frame` fires before `Node._process`; a test must not await a frame to see `_process` run. [history](docs/history.md#a-pause-menu-silenced-the-game)

Deliberately not here: any audio files, DSP, per-voice fades (`_ramp` is the subclass point), a stem player, voice chat. [design](docs/design.md#deliberately-not-here)
