class_name DotAmbienceDirector
extends Node

## The glue every game repeats around [DotAmbience]: build it over the family's stock mood set,
## pick a map's mood (its document's `"ambient"`, the game's table, a name-prefix table, a vote
## over its sound names, else the default), follow the roof, and follow the server's
## [DotAmbienceRules] and the player's settings. A game sets the tables and calls the hooks.
##
## [codeblock]
## var amb := DotAmbienceDirector.new()
## amb.manager = audio
## amb.default_mood = &"industrial"
## amb.prefix_moods = {"surf_": &"snow_wind"}
## add_child(amb)
## amb.setup()                            # the stock moods, plus add_set_dir() of your own
## amb.on_map(map_id, map_doc)            # each map; on_world_sounds() when its sounds arrive
## amb.follow_roof(delta, eye, space, mask)   # each frame, optional
## amb.follow_settings(settings, rules)   # keys `ambient`, `ambient_volume`, `ambient_frequency`
## [/codeblock]

const CHANNEL := "audio.ambience.director"

## What plays under a roof when a map names no indoor mood: the open moods give way to a room tone.
const DEFAULT_INDOOR_OF := {
	&"outdoor_night": &"indoor_hall", &"snow_wind": &"indoor_hall", &"swamp": &"indoor_hall", &"city_ruins": &"indoor_hall",
}

var manager: DotAudioManager = null
var default_mood: StringName = &"outdoor_night"

## The layer itself; built by [method setup].
var ambient: DotAmbience = null

## Map id to mood, for hand-made maps.
var map_moods: Dictionary = {}

## Map id prefix (lower case) to mood, for maps that arrive by the hundred.
var prefix_moods: Dictionary = {}

## Outdoor mood to the one under a roof.
var indoor_of: Dictionary = DEFAULT_INDOOR_OF

## Whether the family's stock moods ([method DotAudioStock.moods_directory]) are loaded.
var use_stock := true

var rules: DotAmbienceRules = DotAmbienceRules.new()

var _store: Object = null
var _user_on := true
var _user_volume := 1.0
var _user_frequency := 1.0
var _map_id: StringName = &""
var _doc_mood: StringName = &""
var _doc_indoor: StringName = &""
var _doc_extra: StringName = &""
## The bed layer a map document's `ambient.level` / `ambient.lively` reach (optional; the game assigns it).
var beds: DotAudioAmbience = null
var _doc_volume := 1.0
var _doc_frequency := 1.0
var _roof := DotAmbienceRoof.new()
var _map_names: Array = []


## Builds the layer and loads the stock moods. Call once, after adding this node.
func setup() -> DotResult:
	ambient = DotAmbience.new()
	ambient.name = "Ambient"
	ambient.manager = manager
	ambient.default_mood = default_mood
	add_child(ambient)
	var made := DotResult.success(0)
	if use_stock:
		made = ambient.add_set_dir(DotAudioStock.moods_directory())
		if not made.ok:
			DotLog.warn(CHANNEL, "no stock ambience set", {"why": made.error.message})
	_apply()
	return made


## True once at least one mood loaded; a game can fall back to a plain bed otherwise.
func has_moods() -> bool:
	return ambient != null and not ambient.mood_names().is_empty()


## Adds a game's own set over the stock one (same mood names replace).
func add_set_dir(dir: String) -> DotResult:
	return ambient.add_set_dir(dir)


## A map arrived. [param doc] may carry `"ambient"`: a mood name or `{mood, indoor, volume, frequency, extra, level, lively}`; `level` scales the bed layer and `lively` lets the birdsong bed play (a forest, a swamp, a park; every other map stays birdless).
func on_map(id: StringName, doc: Dictionary = {}, names: Array = []) -> void:
	_map_id = id
	_read_doc(doc.get("ambient", ""))
	_roof.roofed = false
	if ambient != null:
		ambient.set_indoors(false)
	_map_names = [String(id), str(doc.get("name", ""))] + names
	_choose_mood()


## A converted map's `sounds` block arrived with its world; its names vote unless the document or a table decided.
func on_world_sounds(sounds: Dictionary) -> void:
	_map_names = [String(_map_id)] + DotAmbienceMoods.names_in(sounds)
	_choose_mood()


## The mood of the map playing now, and why.
func mood_for_map() -> Dictionary:
	if _doc_mood != &"":
		return {"mood": _doc_mood, "why": "map document"}
	if map_moods.has(_map_id):
		return {"mood": map_moods[_map_id], "why": "game table"}
	var lower := String(_map_id).to_lower()
	for prefix: Variant in prefix_moods:
		if lower.begins_with(str(prefix)):
			return {"mood": prefix_moods[prefix], "why": "name prefix"}
	var voted := DotAmbienceMoods.vote(_map_names)
	if voted != &"":
		return {"mood": voted, "why": "sound names"}
	return {"mood": default_mood, "why": "default"}


## The mood under a roof here: the document's, else [member indoor_of] of the outdoor one.
func indoor_mood_for_map() -> StringName:
	if _doc_indoor != &"":
		return _doc_indoor
	var outdoor: StringName = mood_for_map()["mood"]
	return indoor_of.get(outdoor, outdoor)


## Once a frame with the listener's eye: under a roof the layer crosses to the indoor mood and back.
func follow_roof(delta: float, eye: Vector3, space: PhysicsDirectSpaceState3D, world_mask: int) -> void:
	if ambient == null:
		return
	if not rules.follows_indoors():
		if _roof.roofed:
			_roof.roofed = false
			ambient.set_indoors(false)
		return
	_roof.mask = world_mask
	if _roof.step(delta, eye, space):
		ambient.set_indoors(_roof.roofed)


## The server's rules and the player's own sliders, multiplied: a player can only turn the server's
## level down. [param store] is a settings store with `get_bool`, `get_float` and `changed`.
func follow_settings(store: Object, new_rules: DotAmbienceRules = null) -> void:
	if new_rules != null:
		rules = new_rules
	if not rules.changed.is_connected(_apply):
		rules.changed.connect(_apply)
	if store != null:
		_store = store
		_read_user(store)
		if not store.changed.is_connected(_on_setting):
			store.changed.connect(_on_setting)
	_apply()
	if ambient != null and rules.dir != "":
		DotLog.result(CHANNEL, "ambience set from the dir cvar", ambient.add_set_dir(rules.dir))
		_choose_mood()


func describe() -> Dictionary:
	var out: Dictionary = ambient.describe() if ambient != null else {}
	out["mood_from"] = mood_for_map()
	return out


func _on_setting(key: StringName, _value: Variant, _why: StringName) -> void:
	if _store != null and key in [&"ambient", &"ambient_volume", &"ambient_frequency"]:
		_read_user(_store)
		_apply()


func _read_user(store: Object) -> void:
	_user_on = bool(store.call(&"get_bool", &"ambient", true))
	_user_volume = float(store.call(&"get_float", &"ambient_volume", 1.0))
	_user_frequency = float(store.call(&"get_float", &"ambient_frequency", 1.0))


func _apply() -> void:
	if ambient == null:
		return
	var c := ambient.config
	c.enabled = rules.is_on() and _user_on
	c.volume = clampf(rules.volume * _user_volume * _doc_volume, 0.0, 1.0)
	c.frequency = rules.frequency * _user_frequency * _doc_frequency
	c.mood = rules.mood
	c.allowed_moods = rules.allowed
	c.sound_dir = rules.dir


func _read_doc(raw: Variant) -> void:
	_doc_mood = &""
	_doc_indoor = &""
	_doc_extra = &""
	_doc_volume = 1.0
	_doc_frequency = 1.0
	var bed_level := 1.0
	var bed_lively := false
	if raw is Dictionary:
		bed_level = float((raw as Dictionary).get("level", 1.0))
		bed_lively = bool((raw as Dictionary).get("lively", false))
	if beds != null and is_instance_valid(beds):
		beds.set_map_profile(bed_level, bed_lively)
	if raw is String:
		_doc_mood = StringName(raw)
	elif raw is Dictionary:
		var d := raw as Dictionary
		_doc_mood = StringName(str(d.get("mood", "")))
		_doc_indoor = StringName(str(d.get("indoor", "")))
		_doc_extra = StringName(str(d.get("extra", "")))
		_doc_volume = clampf(float(d.get("volume", 1.0)), 0.0, 4.0)
		_doc_frequency = clampf(float(d.get("frequency", 1.0)), 0.0, 4.0)
	_apply()


func _choose_mood() -> void:
	if not has_moods():
		return
	var got := mood_for_map()
	var made := ambient.set_mood(_with_extra(got["mood"]))
	if not made.ok:
		DotLog.debug(CHANNEL, "ambience mood not available", {"mood": String(got["mood"]), "why": made.error.message})
		var _fallback := ambient.set_mood(default_mood)
	else:
		DotLog.debug(CHANNEL, "ambience mood", {"map": String(_map_id), "mood": String(got["mood"]), "why": got["why"]})
	ambient.indoor_mood = _with_extra(indoor_mood_for_map())


## [param id] with the map's `extra` mood's one-shots added as a mood of its own; [param id] when
## there is none, it is unknown, or the server restricts the moods.
func _with_extra(id: StringName) -> StringName:
	if _doc_extra == &"" or _doc_extra == id or ambient.config.allowed_moods != "":
		return id
	var base := ambient.mood_def(id)
	var more := ambient.mood_def(_doc_extra)
	if base == null or more == null:
		return id
	var merged_name := StringName("%s+%s" % [id, _doc_extra])
	if ambient.mood_def(merged_name) == null:
		ambient.add_mood(base.with_oneshots_of(more, merged_name))
	return merged_name
