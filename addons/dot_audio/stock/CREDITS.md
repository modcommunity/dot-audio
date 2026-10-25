# Stock sounds

Every file here is CC0 1.0 (public domain dedication). Nothing here needs attribution; it is recorded so anybody can trace a file to its source.

## footsteps/

From **Impact Sounds** (1.0) by [Kenney](https://www.kenney.nl), CC0 1.0 ([licence](http://creativecommons.org/publicdomain/zero/1.0/)). Converted to mono Ogg Vorbis, otherwise unchanged except where noted.

| File | Original |
| --- | --- |
| `footstep_carpet_0..4.ogg` | `footstep_carpet_000..004.ogg` |
| `footstep_concrete_0..4.ogg` | `footstep_concrete_000..004.ogg` |
| `footstep_grass_0..4.ogg` | `footstep_grass_000..004.ogg` |
| `footstep_snow_0..4.ogg` | `footstep_snow_000..004.ogg` |
| `footstep_wood_0..4.ogg` | `footstep_wood_000..004.ogg` |
| `footstep_metal_0..4.ogg` | `impactMetal_light_000..004.ogg`, 6 dB quieter |

## ambience/

`amb_wind.ogg` and `amb_outdoor.ogg` are real field recordings; the other seven beds are synthesised by dot-audio's own `tools/make_ambience.py` (in the repository, not the addon) from fixed seeds: filtered noise, oscillators and scattered synthesised events, no recordings and no third-party samples. Dedicated to the public domain under CC0 1.0 by the dot-audio authors. Each bed is a 32 s seamless stereo loop normalised to −24 LUFS integrated.

| File | What it is |
| --- | --- |
| `amb_wind.ogg` | steady open-air wind (recording) |
| `amb_outdoor.ogg` | daytime birdsong in a park (recording) |
| `amb_night.ogg` | crickets and a low breeze |
| `amb_city.ogg` | traffic rumble, passing cars, a far horn |
| `amb_indoor.ogg` | room tone, ventilation, mains hum |
| `amb_eerie.ogg` | beating drone, breath-like swells, creaks, knocks |
| `amb_industrial.ogg` | machinery hum, air, metal settling |
| `amb_cave.ogg` | deep rumble, dripping water with echoes |
| `amb_rain.ogg` | steady rain |

### Recorded beds

`amb_wind.ogg` and `amb_outdoor.ogg` are cut from the park field recordings `park_ambience_wind.wav` and `park_ambience_birds.wav` by **Thimras**, [OpenGameArt "Park Ambiences"](https://opengameart.org/content/park-ambiences), CC0 1.0. A 36 s excerpt of each, mono, tail crossfaded into the head for a seamless loop, normalised to about -24 LUFS and encoded as Ogg Vorbis by `tools/make_real_beds.sh`.

## moods/

The ambience mood set (`moods.json`): CC0 recordings from OpenGameArt, converted and normalised. Per-file sources and authors are in `moods/CREDITS.md`.
