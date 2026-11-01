class_name DotAudioShotStock
extends RefCounted

## The stock layered shots in stock/shots/ (CC0, see stock/CREDITS.md) as [DotShotDef]s: one per weapon class, ids
## `shot_<class>`. [constant COUNTS] must match the disk (the suite checks). A pack assigns its own files instead.

const PREFIX := "shot_"
## Weapon classes with a stock shot, and how many variant files each layer has.
const COUNTS := {&"light": 6, &"smg": 4, &"magnum": 6, &"rifle": 5, &"heavy": 5, &"sniper": 6, &"shotgun": 6}
## Variants of the suppressed set, which has a body and a far layer only.
const SUPPRESSED_COUNT := 4


static func directory() -> String:
	return DotAudioStock.directory().path_join("shots")


static func id_of(weapon_class: StringName) -> StringName:
	return StringName(PREFIX + String(weapon_class))


## The stock shot for [param weapon_class], or null for an unknown class. Its suppressed layers are the shared pistol set.
static func shot(weapon_class: StringName) -> DotShotDef:
	if not COUNTS.has(weapon_class):
		return null
	var d := DotShotDef.new()
	d.id = id_of(weapon_class)
	var base := directory().path_join(String(weapon_class))
	d.attack = _files(base, "attack", int(COUNTS[weapon_class]))
	d.body = _files(base, "body", int(COUNTS[weapon_class]))
	d.tail_small = _files(base, "tail_small", int(COUNTS[weapon_class]))
	d.tail_medium = _files(base, "tail_medium", int(COUNTS[weapon_class]))
	d.tail_large = _files(base, "tail_large", int(COUNTS[weapon_class]))
	d.tail_hall = _files(base, "tail_hall", int(COUNTS[weapon_class]))
	d.tail_outdoor = _files(base, "tail_outdoor", int(COUNTS[weapon_class]))
	d.far = _files(base, "far", int(COUNTS[weapon_class]))
	var quiet := directory().path_join("suppressed")
	d.suppressed_body = _files(quiet, "body", SUPPRESSED_COUNT)
	d.suppressed_far = _files(quiet, "far", SUPPRESSED_COUNT)
	if weapon_class == &"sniper" or weapon_class == &"shotgun" or weapon_class == &"heavy":
		d.gain_db = 1.0
	return d


## Every stock shot.
static func shots() -> Array[DotShotDef]:
	var out: Array[DotShotDef] = []
	for weapon_class: StringName in COUNTS:
		out.append(shot(weapon_class))
	return out


static func _files(folder: String, layer: String, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in count:
		out.append(folder.path_join("%s_%d.ogg" % [layer, i]))
	return out
