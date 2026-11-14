Game audio for Godot 4.7+ that decides what is heard, how loud, how many sounds at once, and what happens when there is no sound card. Part of the [dot-*](https://github.com/modcommunity) family. It needs only [dot-core](https://github.com/modcommunity/dot-core).

## Install

1. Copy `addons/dot_audio/` and `addons/dot_core/` into your project.
2. Enable dot-audio in *Project > Project Settings > Plugins*.

## Quick start

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

Give it a seeded stream and a shot's pitch and variant match on the server and every client:

```gdscript
audio.roll_source = rng.stream(&"audio")
```

## Sounds are paths, not streams

A sound is an id plus a path, never a loaded `AudioStream`. A dedicated server can then validate the whole catalogue with no sound card and no files, and a game delivered as a content pack can mount its files at runtime. `DotAudioCatalogue.validate()` checks everything except whether the file exists. `missing_files()` answers that separately, on the client that needs them.

Without any files a game can still make noise. `DotAudioSynth` bakes short sounds deterministically (sine sweep, hash grit, envelope) and `DotAudioSinkGodot.bank` holds them behind the filesystem. As soon as a real file exists at the path a definition names, that file wins.

```gdscript
var bank := DotAudioSynth.bank(catalogue, {
    &"fire_rifle": DotAudioSynth.Voice.SHOT,
    &"hit_marker": DotAudioSynth.Voice.BLIP,
})
(audio.sink as DotAudioSinkGodot).bank = bank
```

## Headless and sinks

In a headless run Godot reports a 44100 Hz mix rate and a "Default" device, as if a sound card existed. Only `AudioServer.get_driver_name()` says `"Dummy"`. dot-audio therefore picks its sink by driver name. `DotAudioSinkNull` runs the real catalogue, culling, cooldowns, concurrency limits and music state machine, and replaces only the code that would create an `AudioStreamPlayer`. A dedicated server can use it to decide what clients should play.

## Volume

`DotAudioMixer` sliders carry a linear amplitude from 0 to 1, and `linear_to_db` converts it. Zero means a muted bus. It is a `DotConfig`, so dot-ui can generate a settings screen and dot-settings can save it.

## Limits per sound

These are per-sound settings on `DotAudioDef`. The defaults are shown; every one is configurable.

| Setting | Default | Purpose |
| --- | --- | --- |
| `max_concurrent` | 4 | Stops many identical sounds stacking into one very loud one. |
| `cooldown_ms` | 0 (off) | Drops a repeat that arrives too soon, such as a double footstep in one frame. |
| `max_distance` | 200 (0 = no cull) | Culls a sound that is too far away to hear before it costs a voice. |
| `voices` (on the manager) | 32 | Size of the player pool. Players are created once and reused. |

When the pool is full the lowest-priority voice is stolen. If nothing has lower priority, the new sound is refused.

## Features

| Feature | What it does |
| --- | --- |
| `DotAudioFootsteps` | One step per stride for the player, other players and bots, by surface (a collider's `surface` meta, a `surface_wood` group, or a name like `Floor_Wood`). Silent when creeping. |
| `DotAudioSlide` | A looping scrape by surface, louder and higher with speed. One positional voice per sliding body. |
| `DotAudioSurf` / `DotAudioSurfRules` | A glide loop on ramps too steep to stand on, and silenced steps there. Every value is an `sv_surf_*` cvar. |
| `DotAudioAmbience` | A crossfaded ambience bed per map, with zones that swap it. |
| `DotAmbience` | A mood layer of looping beds and sparse one-shots from random directions. See [docs/ambience.md](docs/ambience.md). Ships no sounds; a game supplies a `moods.json`. |
| `DotShotDef` / `DotShotPlayer` | Shots played as layers (attack, body, tail, far, suppressed), crossfaded and delayed by distance. |
| `DotAudioEnclosure` | Casts rays to estimate room size and openness, picks a tail class and drives one reverb bus. |
| `DotShotRules` | The `snd_shot_*` cvars for the shot system. |
| Loudness | Target of -17 LUFS integrated and -1 dBTP with a master limiter on by default. `addons/dot_audio/tools/loudness.sh` measures a game. See [docs/loudness.md](docs/loudness.md). |

## Stock sounds

`DotAudioStock.add_to(catalogue)` adds the bundled sounds as ordinary definitions. A game's own definition with the same id wins. Weapon sounds are added with `DotAudioWeaponStock.add_to(catalogue)`; see [docs/weapons.md](docs/weapons.md).

Full per-file credits are in [addons/dot_audio/stock/CREDITS.md](addons/dot_audio/stock/CREDITS.md). Everything in `stock/` is CC0.

| Sounds | Source | Licence |
| --- | --- | --- |
| Footsteps | [Kenney](https://www.kenney.nl), Impact Sounds | CC0 |
| Wind and birdsong beds | Thimras, park recordings | CC0 |
| Other ambience beds, surf glide | Synthesised by `tools/make_ambience.py` | CC0 |
| Weapon sounds | CC0 recordings cut and layered by `tools/make_weapon_stock.py` | CC0 |
| Shot sources | The Free Firearm Sound Library; Gunshots by kurt and Eldritch Grim (OpenGameArt) | CC0 |

## Test

```bash
godot --headless --path . --import
godot --headless --path . res://examples/audio_selftest.tscn
```

## Status

Built and maintained with Claude Code. The test suites pass, but little of this has been in front of real players yet. Please report rough edges by opening an issue.

## Licence

MIT. See [LICENSE](LICENSE). Only the TMC back-end web infrastructure is not open source.
