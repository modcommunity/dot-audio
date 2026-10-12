# Design

Why dot-audio is shaped the way it is. The one-line rules are in [CLAUDE.md](../CLAUDE.md).

## Why it exists

The obvious implementation (`AudioStreamPlayer.new()`, `play()`, `queue_free()` on finished) works for one sound and falls apart at twenty, and the parts that stop it falling apart (a pool, priorities, concurrency caps, cooldowns, a cull distance, a real crossfade) are the same work in every game. This is that work, once.

## The sink is a seam, because the engine lies

**`AudioServer` reports a working sound card when there is none.** Headless, `get_mix_rate()` is 44100, `get_input_device_list()` is `["Default"]` and `get_output_latency()` is 0.0; only `get_driver_name()` says `"Dummy"`. dot-voice found that ([its design](../../dot-voice/docs/design.md#audioserver-lies-about-having-a-sound-card)), and the suite's first section asserts it so this addon cannot regress into believing a plausible answer.

`DotAudioSink.device_present()` is the only honest question, asked once in `DotAudioManager.setup()`. Below it:

- `DotAudioSinkGodot`: a fixed pool, priority stealing, real players.
- `DotAudioSinkNull`: writes down what it would have played. The server's sink and the suite's.

**The null sink is not a mock.** The catalogue, the distance cull, the cooldowns, the concurrency caps, the reaping and the music state machine are the real ones in both cases, which is what makes `audio_selftest` a test of this system and not of a stand-in.

## The pieces

| | |
| --- | --- |
| `DotAudioDef` | One sound, as a document. Names a file by path and never loads one. |
| `DotAudioCatalogue` | All of them. `validate()` asks about the document; `missing_files()` asks about the disk. |
| `DotAudioSink` | Where a sound goes, and the honest device check. |
| `DotAudioSinkGodot` | A fixed pool with priority stealing, looping, the synth `bank`. |
| `DotAudioSinkNull` | Records what it would have played. |
| `DotAudioMixer` | The sliders, and the `linear_to_db` curve. A `DotConfig`. |
| `DotAudioManager` | Ids in, limits applied, requests out; `move`, `shape` and `stop` a playing voice by handle. |
| `DotAudioSynth` | Sound made of arithmetic, for a deployment with no audio files yet. |

## Decisions

### A path, not a stream

`DotAudioDef.path` is a `String`. A mounted pack's `class_name` globals are not registered in the host (the reason dot-props names a prop's script by path), so a catalogue that `preload`s cannot describe delivered content. It also lets a server validate a catalogue for files it does not have, which is most servers. A def with no file at all must set `generated`: the sink makes the sound (game-hungario's `HungrySoundSink` is why it exists).

### Culling is in the manager, not the sink

A sound refused for distance costs one vector subtraction. A sound accepted costs a stream load, a voice and a position update every frame for as long as it lasts; on a sixty-four-player server that is most of the pool spent on things nobody can hear. So the manager needs `listener_position`, which a game sets once a frame.

### Stealing goes downwards only

When the pool is full, the lowest-priority voice below the incoming one is stopped. If nothing is lower, the new sound is **refused**. Stealing the oldest is what every naive pool does, and it means a gunshot loses to a footstep that started first.

### Ducking is reference-counted

`duck(&"radio")` and `duck(&"cutscene")` both hold it, and it lifts when the last one releases. A boolean is the commonest ducking bug: two holders, the second releases first, and the music stays quiet for the rest of the session.

### Variation belongs in the document

`variants` is on the def rather than in the caller, because a caller that picks the variant has to hold the list, and then the list is in two places. Both the variant and the pitch come from a roll, so setting `roll_source` to dot-core's `DotRandomStream` (anything with `unit_at(index)`) makes them reproducible: the same shot sounds the same on the server and every client, and an audio bug that cannot be reproduced is one nobody fixes.

### A missing sound is silence, not an error

An unknown id, a file that is not there, a pack still downloading: all refusals, logged at debug, none of them errors. **Audio never changes the simulation**, which is what makes dropping it safe (dot-fx's rule too). A red line per shot on a client whose content is still arriving is how a real error stops being read.

### Looping copies the stream

`DotAudioManager` puts `def.looping` in every request, and the sink loops natively where the stream can (an `AudioStreamWAV` by its loop points, which every synth voice is; anything with a `loop` property such as Ogg or MP3), and otherwise restarts the player on `finished` under the same handle. **It loops a copy, never the stream** (`_looped`): `load()` returns the cached resource every caller of that path shares, and a bank entry is shared by every play of its id, so setting `loop_mode` in place would make the next one-shot of that sound loop for ever. One copy per source stream, kept.

### Reaping happens at the point of refusal

Concurrency counts drop when the sink reports a sound finished. `_process` does not run while the tree is paused, so reaping only there left a game silent after its pause menu ([history](history.md#a-pause-menu-silenced-the-game)). `_reap()` runs in `_process` and again where a count is consulted.

### The synthesiser is consulted after the filesystem, never before

`DotAudioSynth` bakes an `AudioStreamWAV` from a handful of numbers, and `DotAudioSinkGodot.bank` holds the result keyed by path and by id. The sink loads the def's path first and only falls through to the bank when there is no file. A stand-in that outranked a shipped asset would be a placeholder somebody has to remember to remove, which is how placeholders ship.

It does not break "ships no audio": that rule is about what a `DotAudioDef` may hold, and a synthesiser holds nothing. It is in the addon because it was about to be written in every game; the numbers worth arguing about (a shot against a footstep) are the same everywhere, so `Voice` names roles rather than sounds. Which voice stands in for which id stays with the **game**, in its own `sound_recipes()`, for the same reason the cull distances are the game's: an addon that inferred "rail sounds tonal" from an id called `fire_rail` would be guessing at vocabulary it does not own.

### A playing voice is shaped in play()'s units

`DotAudioManager.shape(handle, volume_scale, pitch_scale)` changes a playing voice's loudness and pitch without restarting it, for a sound whose level is information every frame (an engine following speed and throttle). The scales mean what they mean to `play()`: a linear scale on the def's `gain_db` and a multiplier on the pitch the def rolled at the start, both remembered per handle, so `play(id, v, p)` then `shape(h, v, p)` changes nothing. A pass-through of raw decibels to the sink would make every caller re-add the catalogue's gain and drop its variation each frame. It returns false for a voice that has ended or been stolen, so a caller keeping a loop alive starts it again, and it reaps the ended one on the spot for the reason refusal does. The sink side is `DotAudioSink.shape(handle, volume_db, pitch)`, a no-op on the base class so a sink written before API level 2 still loads; `voice(handle)` reads a voice back (from the engine's own player on the Godot sink, which is what a probe under xvfb wants). Added after mg-dangerous-delivery had to subclass the Godot sink and read its private pool to do this.

## Deliberately not here

- **Game audio.** A game's own sounds are the game's. The exceptions are the stock footsteps and ambience beds in `stock/`, which are the same files in every game ([loudness.md](loudness.md#the-stock-set)); `DotAudioSynth` is arithmetic and a stand-in, not an asset library: thirteen voices and no way to author a fourteenth from data, on purpose.
- **DSP and effect design.** Reverb zones, filters and sends are the engine's buses.
- **Per-voice fades.** The shipped fade goes through the bus, which is what almost every game wants and costs nothing per voice. A game that eases a voice itself calls `shape()` each frame; `_ramp` is the subclass point for sample-accurate stem control.
- **A music stem player.** Layered stems in phase need one stream and a mix, which is a different class. `play_music` crossfades whole tracks.
- **Voice chat.** dot-voice: capture, codecs, jitter buffers and routing are a different problem.
