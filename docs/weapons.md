# Weapon sounds

The stock weapon sounds in `addons/dot_audio/stock/weapons/` (42 sounds, 177 files), what each weapon pack played before, and what it plays now. Sources, authors and licences are in [stock/CREDITS.md](../addons/dot_audio/stock/CREDITS.md). Built by `tools/make_weapon_stock.py` from the downloads listed there; never edit an `.ogg` by hand.

## Audit (2026-10-27, before this change)

83 weapons: zee-dot-weapons 27, zed-dot-weapons 16, zz-modern-weapons 28, zz-medieval-weapons 10, game-g2gfast's own deagle and knife 2.

| Pack | Weapons | What played | Silent | Shared |
| --- | --- | --- | --- | --- |
| zz-modern-weapons | 28 | nothing: `ZzWeaponSound.TABLE` empty, fire/reload/draw/dry all null | 28 of 28, every kind | n/a |
| zz-medieval-weapons | 10 | nothing: `ZzWeaponAnim.cue` names, no player | 10 of 10 | n/a |
| game-g2gfast own weapons | 2 | nothing (its `audio/` has landing and jump only) | 2 of 2 | n/a |
| zee-dot-weapons | 27 | one synthesised stream per class (`ZeeWeaponSound`), pitch jitter only | none, but no dry, no equip, no casing, no shell reload | one reload_out and one reload_in for every gun; one impact for every surface; 9 melee and throws on 3 swing/bash/throw streams |
| zed-dot-weapons | 16 | zee's synth by class; uzi and tactical SMG on the pistol class, flamethrower on the minigun's, 3 throwables on the default | none | silenced pistol is the same stream as the service pistol |

Games that use a pack (arena, playground, zombie-zone and the mg- games through `ZeeShotFx` or `ZzViewModel`) have exactly their pack's sounds. dot-weapon itself plays nothing and says so (`used` signals only).

Ranked by how many weapons share a class (the order fixed): rifle 9, melee swing 17 (zee 7, zz-modern 3, medieval 7), shotgun 7, SMG 7, heavy/battle rifle 6, pistol 5, sniper 5, launcher 5, thrown 5, magnum 4, minigun/flamethrower 2, beam 1, charge 1, bow and crossbow 2.

## Now

Every class below has 2 to 5 real variants, picked at random per shot, with a pitch roll on top; guns also have 2 recordings from further away (`*_far`, mid-distance microphones) for a distant-shot path. Fire sounds are layers: a recorded shot, and for the heavy classes (magnum, heavy, sniper, shotgun, launcher) a synthesised sub-bass thump under it, because the recordings have no chest. Levels are set by peak per class so a sniper stays above a pistol (the PEAK_DB column); integrated loudness of a single shot is not a meaningful number (under 400 ms a meter reads nothing, and a long quiet tail drags a shot to about -26 LUFS), so the check is true peak: every file is at or under -1.5 dBFS, and the game's catalogue `gain_db` and the master limiter do the rest ([loudness](loudness.md)).

| Sound (`weapon_<name>`) | Variants | Peak dBFS | Used by |
| --- | --- | --- | --- |
| light_fire / light_far | 5 / 2 | -4 / -8 | pistols (zee pistol, zed service/silenced pistol, zz glock/pistol) |
| smg_fire / smg_far | 5 / 2 | -5 / -9 | zee smg and machine pistol, zed uzi/tactical SMG, zz mp5/p90/smg |
| magnum_fire / magnum_far | 4 / 2 | -2.5 / -7 | revolvers, derringer, deagle |
| rifle_fire / rifle_far | 5 / 2 | -2.5 / -7 | rifles, carbines, bullpups |
| heavy_fire / heavy_far | 5 / 2 | -1.5 / -6 | battle rifles, marksman, machine guns |
| sniper_fire / sniper_far | 5 / 2 | -1.5 / -5 | bolt rifles |
| shotgun_fire / shotgun_far | 5 / 2 | -1.5 / -5 | pumps, drums, sawed-off |
| minigun_fire | 5 | -8 | minigun, flamethrower |
| suppressed_fire | 4 | -9 | zed's silenced pistol and tactical SMG; derived from `light_fire` by `tools/make_suppressed.py` |
| launcher_fire, explosion | 5, 5 | -2, -1.5 | launchers; the blast (for the game's projectile) |
| beam_fire, charge_fire | 5, 5 | -6, -3 | energy weapons |
| swing, swing_heavy, throw, bash | 5, 5, 5, 5 | -6, -4, -9, -3 | blades, axes and spears; thrown items; blunt |
| melee_flesh, melee_metal, impact, impact_flesh, impact_metal, impact_wood | 5 each | -3 to -8 | what a hit sounds like, by surface |
| reload_out, reload_in, reload_shell, rack, equip, dry, casing | 4, 4, 4, 2, 3, 5, 5 | -7 to -14 | the handling of a gun |
| bow_fire, bow_draw, crossbow_fire, crossbow_load, arrow_pass, draw_blade | 5, 2, 5, 5, 2, 4 | -3 to -9 | medieval weapons |

## Wiring

- `DotAudioWeaponStock` (dot-audio): the sounds as `weapon_<name>` defs for a game's `DotAudioManager` catalogue (`add_to`). `COUNTS` is compared with the disk by the suite.
- `DotWeaponSound` (dot-weapon): reads the same files by path with no dependency on dot-audio, so packs that do not link it fall back to their own stand-in (or silence).
- zee-dot-weapons: `ZeeWeaponSound.stream` prefers the stock for every class, the synth is the fallback. A new `smg` class (zee machine pistol and SMG, zed uzi and tactical SMG).
- zz-modern-weapons: `ZzWeaponSound.CLASSES` maps all 28 ids; fire, reload, draw and dry come from the stock.
- zz-medieval-weapons: `ZzMedievalSound` maps each `ZzWeaponAnim.cue` name; `ZzMedievalHeld` plays it (`play_builtin_sounds`).

## Hooks (2026-10-27)

- `DotAudioStock.add_to(catalogue)` now adds the weapon stock too (`weapons := false` leaves it out), so every game that already takes the footsteps and beds has `weapon_*` ids with no per-game code.
- `ZeeShotFx` plays dry (throttled), equip, the case landing (0.38 s after the eject), a shell per round for tube magazines, and the `_far` recording past 60 m; the rig wires the arsenal's `dry_used` and the equip change. `ZeeShotFx.heard(stream)` is emitted for every sound handed to a voice.
- game-g2gfast: `G2GCombat.weapon_used/weapon_dry/weapon_equipped` and `G2GPresentation.on_weapon_*` play the deagle (magnum report, far past 60 m) and the knife (swing).

## Not done

- Nothing was heard by a person: slices were chosen by onset detection and checked by peak, length and the suite, not by ear. Spot-check `dry` (cut from a sheet of equipment clicks), `impact_*` and the derived `suppressed_fire`.
- Indoor and outdoor tails (a reverb choice at the shot) are not separate files.
- g2gfast plays its weapon sounds where the combat layer runs (offline, listen server); a remote client online is not told of other players' shots by any message, so it hears none.
