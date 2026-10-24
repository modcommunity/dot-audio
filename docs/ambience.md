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
| `volume` | 0.5 | linear; 0.5 is the files' own level (the factor is 2 x volume) |
| `frequency` | 1.0 | one-shot rate: intervals are divided by it; 0 none |
| `mood` | empty | forces a mood over the game's request (ignored if it names no mood) |
| `allowed_moods` | empty | comma list; a request outside it gives way to the default or the first allowed mood |
| `sound_dir` | empty | extra sound set; its moods replace built-in ones of the same name |
| `crossfade_seconds` | 6 | a mood change, equal power |

## A sound set

`moods.json` beside its files (paths relative to it; `.import` markers count as present, so it works exported and from a mounted pack):

```json
{"format": 1, "moods": {"cave_tunnel": {
  "volume": 1.0,
  "beds": [{"file": "cave/drone.ogg", "volume": 0.8}],
  "oneshots": [{"files": ["cave/drip.ogg", "cave/drip2.ogg"], "interval": [20, 60],
                "volume": 0.5, "pitch": [0.9, 1.1], "distance": [4, 25]}]}}}
```

With no `moods.json`, each subfolder is a mood: files named `bed*` or `loop*` are beds, the rest one-shots (30 to 90 s apart, volume 0.6). A file a mood names and the disk lacks is dropped with one WARN; a mood left empty is dropped. Each one-shot has its own timer, is placed on a circle round the listener at a random angle and `distance`, and is played through the manager (pool, cull, null sink all apply). Make beds seamless before shipping (crossfade the end into the start) and match their loudness; a loop that clicks is the first thing a player hears.

## Map to mood

`DotAmbienceMoods.vote(names, fallback)` counts keyword hits (soundscape names, ambient sound file names and stand-ins from a converted map's `sounds` block, via `names_in`) for eight moods: `outdoor_night`, `indoor_hall`, `industrial`, `cave_tunnel`, `snow_wind`, `swamp`, `city_ruins`, `interior_horror`. A tie goes to the earlier row (horror first). A game lets its own per-map field win over the vote.
