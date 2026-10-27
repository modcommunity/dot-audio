class_name DotAudioAmbience
extends Node

## The ambience layer: one bed for the map, and zones that swap it where the listener is.
##
## [codeblock]
## var amb := DotAudioAmbience.new()
## amb.manager = audio_manager
## add_child(amb)
## amb.set_map_bed(&"amb_outdoor")                                  # on every map load
## amb.add_zone(AABB(Vector3(10, 0, 10), Vector3(20, 6, 15)), &"amb_indoor")   # a house
## [/codeblock]
##
## [b]Never silent.[/b] A world with no bed is digital silence between events, which reads
## as broken rather than as quiet (the first play test's complaint). A map that names no bed
## gets [member fallback_bed].
##
## [b]Crossfaded through [method DotAudioManager.shape].[/b] The manager's own fade is a
## subclass point that does nothing by default, so the bed's level is eased here, per frame,
## in play()'s units; a stolen or ended bed is started again on the next check.
##
## [b]Zones are data, not nodes:[/b] a box and a bed, which a map document can carry and a
## server never needs. The highest [param priority] containing the listener wins.

const CHANNEL := "audio.ambience"

signal bed_changed(from_id: StringName, to_id: StringName)

var manager: DotAudioManager = null

## Whose position picks the zone. Empty uses the manager's listener_position.
var listener: Node3D = null

## Played when a map names no bed.
var fallback_bed: StringName = &"amb_wind"

## A linear scale on every bed. Low by default: a bed is felt, never listened to. A map that
## wants more says so through [method set_map_bed]'s `map_level`.
var level: float = 0.35

## The birdsong bed. Constant birds are what players found annoying, so [constant BIRD_BED] plays
## as [constant CALM_BED] unless this is on or the map asks for it ([method set_map_bed] `lively`).
var birds: bool = false

const BIRD_BED := &"amb_outdoor"
const CALM_BED := &"amb_wind"

@export_range(0.0, 20.0, 0.1) var fade_seconds: float = 2.5
@export_range(0.05, 5.0, 0.05) var check_seconds: float = 0.25

var _map_bed: StringName = &""
var _map_level := 1.0
var _map_lively := false
var _zones: Array[Dictionary] = []
var _current: StringName = &""
# Every voice this node started: handle -> {id, gain, target}.
var _voices: Dictionary = {}
var _since_check := 0.0
var _stopped := false


## The map's bed. Called on every map load; an empty id plays [member fallback_bed]. [param map_level]
## scales [member level] for this map (a forest or a swamp asks for more); [param lively] lets
## the birdsong bed play on it.
func set_map_bed(id: StringName, map_level: float = 1.0, lively: bool = false) -> void:
	_map_bed = id
	_map_level = maxf(map_level, 0.0)
	_map_lively = lively
	_stopped = false
	_choose()


func map_bed() -> StringName:
	return _map_bed


func add_zone(box: AABB, bed: StringName, priority: int = 0) -> void:
	_zones.append({"box": box, "bed": bed, "priority": priority})
	_choose()


func clear_zones() -> void:
	_zones.clear()
	_choose()


func zone_count() -> int:
	return _zones.size()


## The bed playing now (fading in, or full).
func current_bed() -> StringName:
	return _current


## Fades everything out and stays quiet until the next [method set_map_bed].
func stop(fade: float = -1.0) -> void:
	_stopped = true
	_switch(&"", fade)


## The bed that should be playing at a point: the best zone containing it, else the map's.
func bed_at(point: Vector3) -> StringName:
	var best: Dictionary = {}
	for z in _zones:
		if (z["box"] as AABB).has_point(point):
			if best.is_empty() or int(z["priority"]) > int(best["priority"]):
				best = z
	if not best.is_empty():
		return best["bed"]
	var bed := _map_bed if _map_bed != &"" else fallback_bed
	if bed == BIRD_BED and not (birds or _map_lively):
		return CALM_BED
	return bed


func _gain() -> float:
	return level * _map_level


func _process(delta: float) -> void:
	if manager == null:
		manager = DotRegistry.get_node_service(DotAudioManager.SERVICE) as DotAudioManager
		if manager == null:
			return
	_since_check += delta
	if _since_check >= check_seconds:
		_since_check = 0.0
		_choose()
	_ease(delta)


func _choose() -> void:
	if _stopped:
		return
	var at := manager.listener_position if manager != null else Vector3.ZERO
	if listener != null and is_instance_valid(listener) and listener.is_inside_tree():
		at = listener.global_position
	var want := bed_at(at)
	if want != _current:
		_switch(want, fade_seconds)
		return
	# Still the same bed: make sure it is actually playing (stolen, or a sink that came up late).
	if _current != &"" and manager != null and _handle_of(_current) == 0:
		_start(_current, fade_seconds)


func _switch(to: StringName, fade: float) -> void:
	var from := _current
	_current = to
	for h: int in _voices.keys():
		_voices[h]["target"] = 0.0
	if to != &"":
		_start(to, fade if fade >= 0.0 else fade_seconds)
	if from != to:
		bed_changed.emit(from, to)
		DotLog.debug(CHANNEL, "ambience", {"from": String(from), "to": String(to)})


func _start(id: StringName, fade: float) -> void:
	if manager == null:
		return
	var existing := _handle_of(id)
	if existing != 0:
		_voices[existing]["target"] = 1.0
		return
	var start := 0.0 if fade > 0.0 else 1.0
	var h := manager.play(id, maxf(start, 0.001) * _gain())
	if h == 0:
		return
	_voices[h] = {"id": id, "gain": start, "target": 1.0}


func _handle_of(id: StringName) -> int:
	for h: int in _voices.keys():
		if _voices[h]["id"] == id and float(_voices[h]["target"]) > 0.0 and manager.is_playing(h):
			return h
	return 0


func _ease(delta: float) -> void:
	if _voices.is_empty() or manager == null:
		return
	var step := delta / maxf(fade_seconds, 0.01)
	for h: int in _voices.keys():
		var v: Dictionary = _voices[h]
		var g := move_toward(float(v["gain"]), float(v["target"]), step)
		v["gain"] = g
		if g <= 0.0 and float(v["target"]) <= 0.0:
			manager.stop(h)
			_voices.erase(h)
			continue
		# An equal-power curve, so a crossfade does not dip in the middle.
		if not manager.shape(h, maxf(sin(g * PI * 0.5), 0.001) * _gain()):
			_voices.erase(h)


func describe() -> Dictionary:
	return {"map_bed": String(_map_bed), "current": String(_current), "zones": _zones.size(), "voices": _voices.size()}


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"dot-audio ambience  %s (map %s, %d zones, %d voices)" % [
			_current, _map_bed if _map_bed != &"" else &"-", _zones.size(), _voices.size()],
	])
