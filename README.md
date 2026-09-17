This is the **audio** asset for TMC's **Dot** collection. It adds the part of a game that decides what is heard, how loud, how many at once, and what happens when there is no sound card at all.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

## It ships no audio

A sound is an id and a **path**, never a loaded `AudioStream`. Two reasons, and the second is the harder one:

- A dedicated server validates the whole catalogue without a sound card and without the files.
- A game delivered as a content pack is mounted at runtime, and a catalogue that `preload`s cannot describe delivered content at all.

So `DotAudioCatalogue.validate()` checks everything except whether the file exists, and `missing_files()` is a separate question, asked by the client that is about to need them.

It still ships no audio, and a game with no files can still make a noise. `DotAudioSynth` bakes short sounds out of a sine sweep, a deterministic hash and an attack-decay envelope, and `DotAudioSinkGodot.bank` holds them — **behind** the filesystem, so the moment a real file exists at the path a def already names, that file wins and nobody edits a line:

```gdscript
var bank := DotAudioSynth.bank(catalogue, {
    &"fire_rifle": DotAudioSynth.Voice.SHOT,
    &"hit_marker": DotAudioSynth.Voice.BLIP,
})
(audio.sink as DotAudioSinkGodot).bank = bank
```

Nothing about it is random: the grit comes from a hash rather than `randf()`, so the bank is byte-identical on every machine and every run. That is what makes it something a test can assert about rather than listen to.

## The engine reports a working sound card when there is none

In a headless run `AudioServer.get_mix_rate()` is 44100, the device list is `["Default"]` and the output latency is 0.0. **Only `get_driver_name()` says `"Dummy"`.** A capability check built on any of the others passes on a machine with no audio at all, and the symptom is silence for ever with nothing reporting a problem.

That is why there is a `DotAudioSink` interface. `DotAudioSinkNull` is not a mock. The real catalogue, the real culling, the real cooldowns, the real concurrency caps and the real music state machine all run above it, and only the four lines that would create an `AudioStreamPlayer` are replaced. A headless suite is then a test of the system rather than of a stand-in, and a dedicated server can decide what its clients are told to play.

## A volume slider is not decibels

Mapping a 0..1 slider straight onto `volume_db`, even scaled to -60..0, gives a control where everything below about 0.9 is inaudible and two thirds of the travel does nothing. Hearing is roughly logarithmic, so the slider carries a **linear amplitude** and `linear_to_db` converts. Zero is a muted bus rather than -60 dB, because a slider dragged to the bottom should be silence and not a number that a later `+3 dB` turns back into sound.

`DotAudioMixer` is a `DotConfig`, so dot-ui generates the screen and dot-settings persists it, with nothing here knowing either exists.

## Three limits, which are three different problems

| | |
| --- | --- |
| `max_concurrent` | Twelve identical rifles half a millisecond apart is not twelve gunshots. It is one gunshot twelve times as loud, with comb filtering. Three sounds like a crowd. |
| `cooldown_ms` | A footstep triggered from a physics callback fires twice in a frame, and the second one is inaudible and still costs a voice. |
| `max_distance` | A cull, not a curve. A sound at 400 metres attenuated to inaudible still costs a stream load, a voice and a position update every frame. |

And the pool: `DotAudioSinkGodot` creates `voices` players once and never frees them. The obvious spelling, which is to create, play and `queue_free` on finished, has no ceiling, and a firefight is a hundred nodes created and destroyed per second, which on the web is a visible hitch every time anything happens. When the pool is full the **lowest-priority** voice is stolen, and if nothing is lower the new sound is refused: a gunshot losing to a footstep because the footstep started first is the failure mode of every fixed pool with no priority.

## Using it

```gdscript
var audio := DotAudioManager.new()
audio.catalogue = my_catalogue
add_child(audio)
audio.setup()                        # picks a sink by asking the driver's name

audio.listener_position = camera.global_position   # once a frame; culling needs it
audio.play(&"ui_click")
audio.play_at(&"rifle", muzzle.global_position)
audio.play_music(&"combat", 1.5)     # crossfade; asking for what is playing does nothing
audio.duck(&"radio")                 # reference-counted, so two ducks do not fight
```

Hand it dot-randomness' stream and a shot's pitch and variant are the same on the server and on every client watching, which is what makes an audio bug reproducible:

```gdscript
audio.roll_source = rng.stream(&"audio")
```

## Installing

Copy `addons/dot_audio/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-audio in **Project → Project Settings → Plugins**.

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core). Nothing else.

## License

MIT.
