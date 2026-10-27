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

## weapons/

Slices of CC0 recordings, cut, pitched, layered with a synthesised sub-bass thump (heavy classes) and peak-levelled by `tools/make_weapon_stock.py`, written as mono Ogg Vorbis. Every source is CC0 1.0; attribution is not required and is given here.

| Source | Author | URL | Used for |
| --- | --- | --- | --- |
| The Free Firearm Sound Library (Prepared SFX Library) | Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney (Still North Media; uploaded by bart) | https://opengameart.org/content/the-free-firearm-sound-library | `*_fire`, `*_far`, `minigun_fire` (1911, Walther PPQ, Bersa, S&W 642, Carl Gustav M45, PPSh, AR-15, SKS, AK-47, Model 1894, Marlin 336, Savage 10, Mosin Nagant, Tikka T3, Arisaka, Springfield 1917, CD, Model 12, Nova, Mossberg) |
| Medieval sound effects - Weapon Textures (parts 1 and 2) | Ben Jaszczak and Brian Nelson (uploaded by MedicineStorm) | https://opengameart.org/content/medieval-sound-effects-weapon-textures | `swing*`, `throw`, `draw_blade`, `bow_*`, `crossbow_*`, `arrow_pass` |
| 25 CC0 bang / firework SFX | rubberduck | https://opengameart.org/content/25-cc0-bang-firework-sfx | `launcher_fire`, `explosion` (cannon shots) |
| Gun reload sounds | Joaken, SpringySpringo | https://opengameart.org/content/gun-reload-sounds | `reload_*`, `equip` |
| 2 Gun Reloads | StarNinjas | https://opengameart.org/content/2-gun-reloads | `reload_*` |
| Shotgun Reload Sound effects | zer0sol | https://opengameart.org/content/shotgun-reload-sound-effects | `reload_shell`, `rack` |
| equipment clicks III | LFA | https://opengameart.org/content/equipment-clicks-iii | `dry` |
| Impact Sounds 1.0 | Kenney | https://kenney.nl/assets/impact-sounds | `bash`, `impact*`, `melee_*`, `casing` |
| Sci-fi Sounds 1.0 | Kenney | https://kenney.nl/assets/sci-fi-sounds | `beam_fire`, `charge_fire`, `explosion` layer |

`suppressed_fire` is derived from the stock's own `light_fire` files by `tools/make_suppressed.py` (low-passed, softened, shortened, with a synthesised action clack), so it adds no source.

## slides/

Seven looping slide scrapes (`slide_generic`, `slide_concrete`, `slide_metal`, `slide_wood`, `slide_grass`, `slide_snow`, `slide_carpet`), built by `tools/make_slide_stock.py`: scrapes joined with equal-power crossfades into a seamless loop, filtered per surface and levelled. Source is CC0 1.0; attribution is not required and is given here.

| Source | Author | URL | Used for |
| --- | --- | --- | --- |
| Scrapes (scrape-1 to scrape-8) | AntumDeluge | https://opengameart.org/content/scrapes | every `slide_*` loop |
