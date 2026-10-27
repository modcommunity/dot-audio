# The creepy-ambience layer (`DotAmbience`)

A mood is a named set of looping **beds** (they play together) and sparse random **one-shots** (a creak, a moan, a far door). The layer plays one mood, crossfades to the next when the game or the settings change it, and stays quiet: the default level is nominal for files normalised to a quiet bed (-30 LUFS beds, about -26 LUFS one-shots), so it is felt rather than listened to. It is separate from [`DotAudioAmbience`](loudness.md), the per-map bed and indoor zones; use either or both.

```gdscript
var amb := DotAmbience.new()
amb.manager = audio_manager            # or leave empty: the registered DotAudioManager service
add_child(amb)
amb.add_set_dir("res://sounds/ambience")   # moods.json + files; a game ships this
amb.load_custom()                          # config.sound_dir: the owner's own set, wins by mood name
amb.set_mood(&"cave_tunnel")               # DotResult; refused for an unknown mood
amb.duck(&"fight", 0.3); amb.unduck(&"fight")   # holders, reference-counted like the manager's duck
amb.hush(&"x") / amb.pause(&"menu")        # no new one-shots / everything fades out
print(amb.describe())
```

## Settings (`DotAmbienceConfig`, a `DotConfig`)

Defaults < JSON file < environment (`DOT_AMBIENCE_*`) < command line (`--ambience-*`). All are read live each step.

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | true | off fades everything out |
| `volume` | 0.25 | linear; 0.5 is the files' own level (the factor is 2 x volume), so the default is 6 dB under it; a map document's `"ambient": {"volume": n}` multiplies it (0 to 4) |
| `frequency` | 0.5 | one-shot rate: intervals are divided by it; 0 none |
| `mood` | empty | forces a mood over the game's request (ignored if it names no mood) |
| `allowed_moods` | empty | comma list; a request outside it gives way to the default or the first allowed mood |
| `sound_dir` | empty | extra sound set; its moods replace built-in ones of the same name |
| `crossfade_seconds` | 6 | a mood change, equal power |
| `follow_indoors` | true | `set_indoors(true)` switches to `indoor_mood`; off ignores it |

## A sound set

`moods.json` beside its files (paths relative to it; `.import` markers count as present, so it works exported and from a mounted pack):

```json
{"format": 1, "moods": {"cave_tunnel": {
  "volume": 1.0,
  "beds": [{"file": "cave/drone.ogg", "volume": 0.8}],
  "oneshots": [{"files": ["cave/drip.ogg", "cave/drip2.ogg"], "interval": [20, 60],
                "volume": 0.5, "pitch": [0.9, 1.1], "distance": [4, 25]}]}}}
```

`moods.json` is exported by a preset with `export_filter="all_resources"` (checked with `--export-pack` on 4.7.2: `.json` is packed, `.txt` is not), so no `include_filter` entry is needed. With no `moods.json`, each subfolder is a mood: files named `bed*` or `loop*` are beds, the rest one-shots (30 to 90 s apart, volume 0.6). A file a mood names and the disk lacks is dropped with one WARN; a mood left empty is dropped. Each one-shot has its own timer, is placed on a circle round the listener at a random angle and `distance`, and is played through the manager (pool, cull, null sink all apply). Make beds seamless before shipping (crossfade the end into the start) and match their loudness; a loop that clicks is the first thing a player hears.

## Map to mood

`DotAmbienceMoods.vote(names, fallback)` counts keyword hits (soundscape names, ambient sound file names and stand-ins from a converted map's `sounds` block, via `names_in`) for eight moods: `outdoor_night`, `indoor_hall`, `industrial`, `cave_tunnel`, `snow_wind`, `swamp`, `city_ruins`, `interior_horror`. A tie goes to the earlier row (horror first). A game lets its own per-map field win over the vote.

## Indoors and outdoors

A game sets `ambience.indoor_mood` (the mood to use under a roof) and calls `set_indoors(bool)`; `effective_mood` then prefers `indoor_mood` while indoors, if `DotAmbienceConfig.follow_indoors` is on and the mood is allowed, and the usual crossfade does the rest. `indoors()` and `mood_def(id)` read the state back, and `describe()` shows both. `DotAmbienceRoof` finds the roof: `step(delta, at, space)` casts one reused upward ray (`height` 8 m, every `interval` 0.25 s) and returns true when `roofed` flips; it needs 2 hits in a row to go indoors and 4 misses to leave, so a doorway or a lamp post does not flap the mood. `DotAmbienceMood.with_oneshots_of(other, name)` builds a mood that adds another's one-shots to its own.

## The director (`DotAmbienceDirector`): what every game repeats

A game adopts the layer in a few lines: the stock set (`stock/moods/`, eight moods, CC0, `moods/CREDITS.md`) loads by itself, and the director does the map to mood choice (document `"ambient"`, then `map_moods`, then `prefix_moods`, then the name vote, then `default_mood`), the `extra` merge, the roof, and the multiplication of the server's `DotAmbienceRules` (cvars `<prefix>_ambient*`, `bind_cvars`/`follow_cvars`) with the player's `ambient`, `ambient_volume` and `ambient_frequency` settings. The layer plays on the `Ambience` bus, so the master and ambience sliders and a mute reach it. See the class comment for the call sequence; game-arena and game-zombie-zone are the two users.
