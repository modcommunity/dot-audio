class_name DotAudioWeaponStock
extends RefCounted

## The family's stock weapon sounds as [DotAudioDef]s: every file in stock/weapons/ (CC0 slices, see
## stock/CREDITS.md), ids `weapon_<name>` with variants. Packs that do not link dot-audio read the
## same files by path (dot-weapon's DotWeaponSound); keep [constant COUNTS] and its probing in step.

const PREFIX := "weapon_"

## name -> number of variant files. A suite compares this with the disk.
const COUNTS := {
	&"arrow_pass": 2, &"bash": 5, &"beam_fire": 5, &"bow_draw": 2, &"bow_fire": 5, &"casing": 5,
	&"charge_fire": 5, &"crossbow_fire": 5, &"crossbow_load": 5, &"draw_blade": 4, &"dry": 5, &"equip": 3,
	&"explosion": 5, &"heavy_far": 2, &"heavy_fire": 5, &"impact": 5, &"impact_flesh": 5,
	&"impact_metal": 5, &"impact_wood": 5, &"launcher_fire": 5, &"light_far": 1, &"light_fire": 5,
	&"magnum_far": 2, &"magnum_fire": 4, &"melee_flesh": 5, &"melee_metal": 5, &"minigun_fire": 5,
	&"rack": 2, &"reload_in": 4, &"reload_out": 4, &"reload_shell": 4, &"rifle_far": 2, &"rifle_fire": 5,
	&"shotgun_far": 1, &"shotgun_fire": 5, &"smg_far": 2, &"smg_fire": 4, &"sniper_far": 2,
	&"sniper_fire": 5, &"pin_pull": 3, &"suppressed_fire": 4, &"swing": 5, &"swing_heavy": 5, &"throw": 5,
}

## Mix level in dB for the sounds that are not at 0: files are peak-levelled per class, this
## trims the quiet ones under the shots.
const _GAIN := {&"casing": -6.0, &"dry": -4.0, &"reload_in": -2.0, &"reload_out": -2.0, &"throw": -3.0}


static func directory() -> String:
	return DotAudioStock.directory().path_join("weapons")


static func id_of(sound: StringName) -> StringName:
	return StringName(PREFIX + String(sound))


static func defs() -> Array[DotAudioDef]:
	var out: Array[DotAudioDef] = []
	var dir := directory()
	for sound: StringName in COUNTS:
		var d := DotAudioDef.new()
		d.id = id_of(sound)
		d.kind = DotAudioDef.Kind.POSITIONAL_3D
		d.bus = &"SFX"
		var variants := PackedStringArray()
		for i in int(COUNTS[sound]):
			variants.append(dir.path_join("%s_%d.ogg" % [sound, i]))
		d.path = variants[0]
		d.variants = variants
		d.gain_db = float(_GAIN.get(sound, 0.0))
		d.pitch_min = 0.96
		d.pitch_max = 1.04
		var s := String(sound)
		var far := s.ends_with("_far")
		var shot := s.ends_with("_fire") or s == &"explosion" or far
		d.priority = 70 if shot else 50
		d.max_concurrent = 6 if shot else 4
		# A report carries across a map; a click or a reload is for whoever is close.
		d.unit_size = 12.0 if shot else 3.0
		# A distant report is the one meant to be heard from far away.
		d.max_distance = 600.0 if far else 260.0 if shot else 40.0
		d.tags = [&"weapon", DotAudioCatalogue.STOCK_TAG]
		out.append(d)
	return out


## Adds every weapon def the catalogue does not already have. Returns how many.
static func add_to(catalogue: DotAudioCatalogue) -> int:
	var added := 0
	for d in defs():
		if catalogue.has(d.id):
			continue
		catalogue.add(d)
		added += 1
	return added
