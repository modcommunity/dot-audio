# dot-audio

Audio as a catalogue of ids, with the whole path runnable on a machine that has no speakers.

**The distributable is `addons/dot_audio/`.** It requires [dot-core](../dot-core), a separate repository, and nothing else.

```bash
ln -s ../../dot-core/addons/dot_core addons/dot_core
```

## Why this exists

Four of the five games in this family make no sound at all — game-hungario is the only one that names an `AudioStream` anywhere, and it generates what it plays rather than shipping any. game-arena is the sharpest case: it has a camera rig, input sampling, a renderer, a HUD and menus, and firing produces no audio whatsoever.

The reason nobody added it was not difficulty. It is that the obvious implementation — `AudioStreamPlayer.new()`, `play()`, `queue_free()` on finished — works perfectly for one sound and falls apart at twenty, and the parts that make it not fall apart (a pool, priorities, concurrency caps, cooldowns, a cull distance, a real crossfade) are all the same work in every game. This is that work, once.

## The one idea: the sink is a seam, and it exists because the engine lies

**`AudioServer` reports a working sound card when there is none.** In a headless run `get_mix_rate()` is 44100, `get_input_device_list()` is `["Default"]` and `get_output_latency()` is 0.0. Only `get_driver_name()` says `"Dummy"`. dot-voice found that, and it is asserted here in the suite's first section so this addon cannot regress into believing any of the plausible answers.

`DotAudioSink.device_present()` is the only honest question, asked once in `setup()`. Below it:

- `DotAudioSinkGodot` — a fixed pool, priority stealing, real players.
- `DotAudioSinkNull` — writes down what it would have played.

**The null sink is not a mock.** The catalogue, the distance cull, the cooldowns, the concurrency caps, the reaping and the music state machine are the real ones in both cases. That is what makes `audio_selftest` a test of this system and not of a stand-in — the same reasoning that gave dot-voice its only headless suite.

## What building it found

**`_process` does not run while the tree is paused.** The concurrency counts are decremented when the sink reports a sound has finished, which was originally done only in `_process` — so a game that opened a pause menu came back with every count stuck at its cap and was silent for the rest of the session, with nothing erroring anywhere. The counts are now reaped at the point of refusal as well, which is the only place they are actually consulted. The suite asserts a finished sound frees its slot **with no frame in between**, so the fix cannot be reverted quietly.

A smaller one, from the same run: `SceneTree.process_frame` is emitted **before** `Node._process`, not after. A test that awaits one frame and expects a node's `_process` to have run is a test that will pass or fail on scheduling. There is no await in that section at all now.

**`looping` was in every request and no sink read it** (found 2026-09-25, by a game). `DotAudioManager` has always put `def.looping` in the play request, and `DotAudioSinkGodot.play()` never looked — so a looping def, an engine hum or an ambience bed, played once and stopped, and the null sink recorded a request that looked right. mg-buses-from-hell built its bus engine as a repeating pulse rather than wait. The sink now loops natively where the stream can — an `AudioStreamWAV` by its loop points (every synth voice is one), anything with a `loop` property (Ogg, MP3) — and otherwise restarts the player on `finished` under the same handle. **It loops a copy, never the stream:** `load()` returns the cached resource every caller of that path shares and a bank entry is shared by every play of its id, so setting `loop_mode` in place would make the next one-shot of that sound loop for ever. One copy per source stream, kept. The suite asserts the loop points, that the bank's own stream is untouched, and the restart fallback.

## The pieces

| | |
| --- | --- |
| `DotAudioDef` | One sound, as a document. Names a file by path and never loads one. |
| `DotAudioCatalogue` | All of them. `validate()` asks about the document; `missing_files()` asks about the disk. |
| `DotAudioSink` | Where a sound goes, and the honest device check. |
| `DotAudioSinkGodot` | A fixed pool with priority stealing. |
| `DotAudioSinkNull` | Records what it would have played. The server's sink and the suite's. |
| `DotAudioMixer` | The sliders, and the `linear_to_db` curve. A `DotConfig`. |
| `DotAudioManager` | Ids in, limits applied, requests out. |
| `DotAudioSynth` | Sound made of arithmetic, for a deployment that has no audio files yet. |

## Decisions

### 1. A path, not a stream

`DotAudioDef.path` is a `String`. A **mounted pack's `class_name` globals are not registered in the host** — measured in this family, and the reason dot-props names a prop's script by PATH — so a catalogue that `preload`s cannot describe delivered content. It also means a server validates a catalogue for files it does not have, which is most servers.

### 2. Culling is in the manager, not the sink

A sound refused for distance costs one vector subtraction. A sound accepted for distance costs a stream load, a voice and a position update every frame for as long as it lasts. On a sixty-four-player server the difference is most of the pool spent on things nobody can hear. The manager therefore needs `listener_position`, which a game sets once a frame.

### 3. Stealing goes downwards only

When the pool is full the lowest-priority voice below the incoming one is stopped. If nothing is lower, the new sound is **refused**. Stealing the oldest instead is what every naive pool does, and it means a gunshot loses to a footstep that started first.

### 4. Ducking is reference-counted

`duck(&"radio")` and `duck(&"cutscene")` both hold it, and it lifts when the last one releases. A boolean is the commonest bug in every ducking implementation: two holders, the second releases first, and the music stays quiet for the rest of the session.

### 5. Variation belongs in the document

`variants` is on the def rather than in the caller, because a caller that picks the variant has to hold the list — and then the list is in two places, which is this tree's most repeated bug. Both the variant and the pitch come from a **roll**, so handing the manager dot-randomness' stream makes them reproducible: the same shot sounds the same on the server and on every client watching, and an audio bug that cannot be reproduced is one nobody fixes.

### 6. A missing sound is silence, not an error

An unknown id, a file that is not there, a pack still downloading: all refusals, all logged at debug, none of them errors. **Audio never changes the simulation**, which is exactly the property that makes dropping it safe — the same rule dot-fx runs on. A red line per shot on a client whose content is still arriving is how a real error stops being read.

### 7. The synthesiser is consulted after the filesystem, never before

`DotAudioSynth` bakes an `AudioStreamWAV` from a handful of numbers and `DotAudioSinkGodot.bank` holds the result, keyed by path and by id. The order matters more than anything else about it: the sink loads the def's path first and only falls through to the bank when there is no file there. A stand-in that outranked a shipped asset would be a placeholder somebody has to remember to remove, which is how placeholders ship.

It does not break "ships no audio". That rule is about what a `DotAudioDef` may hold — a catalogue that carries streams cannot describe delivered content and cannot be validated on a server that does not have the files — and a synthesiser holds nothing. What ships is the arithmetic.

**It is in the addon because it was about to be written twice.** game-hungario had a sine-sweep-plus-noise baker of its own, and four other games had complete catalogues pointing at files nobody had produced. The numbers worth arguing about — what a shot sounds like against what a footstep sounds like — are the same numbers in all of them, so `Voice` names roles rather than sounds: a game says "this is the shot" and gets whatever this addon currently thinks a shot is.

Which voice stands in for which id stays with the **game**, in its own `sound_recipes()`, for the same reason the cull distances are the game's. An addon that inferred "rail sounds tonal" from an id called `fire_rail` would be an addon guessing at vocabulary it does not own.

## Things deliberately not here

- **Any audio.** dot-ui's rule. `DotAudioSynth` is arithmetic, not a bank, and it is a stand-in rather than an asset library — it has thirteen voices and no way to author a fourteenth from data, on purpose.
- **DSP and effect design.** Reverb zones, filters and sends are the engine's buses, and a game that wants them configures the bus layout the engine already has.
- **Per-voice fades.** The shipped fade goes through the bus, which is what almost every game wants and costs nothing per voice. `_ramp` is the subclass point for a game that genuinely needs sample-accurate stem control.
- **A music stem player.** Layered stems that stay in phase need one stream and a mix, not several players, and that is a different class. `play_music` crossfades between whole tracks.
- **Voice chat.** dot-voice, and it is a completely different problem: capture, codecs, jitter buffers and routing.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
timeout 120 godot --headless --path . res://examples/audio_selftest.tscn
```

8 sections, 91 checks, none of which needs a sound card. It prints "N ObjectDB instances were leaked at exit" and "1 resources still in use" on every green run, and both predate the looping checks: `--verbose` names them as `AudioStreamPlaybackWAV` / `AudioStreamGeneratorPlayback` objects — one per `play()` the synth section makes — which the engine's dummy driver creates and never mixes, so nothing releases them. Stopping every voice and freeing the host before exit does not change the count. It was 6 before the looping section and is 12 with it, because that section plays six more sounds. `CHECKS` is a total as well as a section count: a script error inside a test aborts *that test*, not the run, and the section counter cannot see it because the section has already announced itself.
