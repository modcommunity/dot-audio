class_name DotAudioEnclosure
extends Node

## Measures the room around the listener with a few rays a frame (a fibonacci sphere of 16-32): the mean hit distance
## is the room's size, the miss fraction its openness. Both are smoothed; they pick the tail class a shot plays and
## drive one reverb bus. The game calls [method step] each frame (or [method feed] with its own rays).

const CHANNEL := "audio.enclosure"
## The reverb bus the tail layers play on; sends to [member send_bus].
const BUS := &"ShotReverb"
## Where the reverb bus sends its output.
@export var send_bus: StringName = &"SFX"
var rules: DotShotRules = DotShotRules.new()
## A ray that reaches nothing within this many metres is a miss.
@export_range(5.0, 200.0, 1.0) var max_range := 40.0
@export_range(1, 16, 1) var rays_per_step := 4
## Physics layers the rays test.
@export var mask := 1
## How fast the measured room is followed, per second.
@export_range(0.1, 20.0, 0.1) var smoothing := 2.5

signal class_changed(from: StringName, to: StringName)

## The tail class to play now: small, medium, large, hall or outdoor.
var tail_class: StringName = &"outdoor"
## Smoothed mean hit distance in metres, and the smoothed miss fraction (0 closed, 1 open).
var size := 20.0
var openness := 1.0
var exclude: Array[RID] = []

var _dirs := PackedVector3Array()
var _cursor := 0
var _sum := 0.0
var _hits := 0
var _misses := 0
var _target_size := 20.0
var _target_open := 1.0
var _swept := false
var _query := PhysicsRayQueryParameters3D.new()
var _reverb: AudioEffectReverb = null
var _bus_index := -1


## The unit directions of an n-point fibonacci sphere.
static func fibonacci(n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var golden := PI * (3.0 - sqrt(5.0))
	for i in n:
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(n)
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		out.append(Vector3(cos(golden * i) * r, y, sin(golden * i) * r))
	return out


## The tail class for a room of [param room_size] metres and [param open] (0-1); no hysteresis.
static func classify(room_size: float, open: float) -> StringName:
	if open >= 0.4:
		return &"outdoor"
	if room_size < 3.5:
		return &"small"
	if room_size < 8.0:
		return &"medium"
	if room_size < 18.0:
		return &"large"
	return &"hall"


## Creates the reverb bus when missing. Safe to call twice.
func ensure_bus() -> DotResult:
	_bus_index = AudioServer.get_bus_index(BUS)
	if _bus_index < 0:
		AudioServer.add_bus()
		_bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus_index, BUS)
		AudioServer.set_bus_send(_bus_index, send_bus if AudioServer.get_bus_index(send_bus) >= 0 else &"Master")
	for i in AudioServer.get_bus_effect_count(_bus_index):
		var existing := AudioServer.get_bus_effect(_bus_index, i) as AudioEffectReverb
		if existing != null:
			_reverb = existing
			break
	if _reverb == null:
		_reverb = AudioEffectReverb.new()
		_reverb.dry = 1.0
		AudioServer.add_bus_effect(_bus_index, _reverb)
	_apply_reverb()
	return DotResult.success(_bus_index)


## Casts [member rays_per_step] rays from [param at] and moves the smoothing on by [param delta].
func step(delta: float, at: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	if not rules.enclosure or space == null:
		_to_outdoor(delta)
		return
	if _dirs.size() != rules.rays:
		_dirs = fibonacci(rules.rays)
		_cursor = 0
	_query.from = at
	_query.collision_mask = mask
	_query.exclude = exclude
	for _i in rays_per_step:
		_query.to = at + _dirs[_cursor] * max_range
		var hit := space.intersect_ray(_query)
		feed(at.distance_to(hit["position"]) if not hit.is_empty() else -1.0)
	advance(delta)


## One ray's answer: the hit distance in metres, or negative for a miss. A sweep ends after [member DotShotRules.rays] rays.
func feed(distance: float) -> void:
	if distance < 0.0 or distance >= max_range:
		_misses += 1
	else:
		_hits += 1
		_sum += distance
	_cursor += 1
	if _cursor >= maxi(rules.rays, 1):
		_cursor = 0
		_target_size = _sum / float(_hits) if _hits > 0 else max_range
		_target_open = float(_misses) / float(_hits + _misses)
		_sum = 0.0
		_hits = 0
		_misses = 0
		_swept = true


## Eases the measured room towards the last finished sweep and re-picks the class and reverb.
func advance(delta: float) -> void:
	if not _swept:
		return
	var k := 1.0 - exp(-smoothing * maxf(delta, 0.0))
	size = lerpf(size, _target_size, k)
	openness = lerpf(openness, _target_open, k)
	_pick_class()
	_apply_reverb()


## Reverb parameters for the current room: room_size 0-1, damping 0-1, wet 0-1 (before [member DotShotRules.reverb]).
func reverb_params() -> Dictionary:
	return {
		"room_size": clampf(size / 30.0, 0.1, 1.0),
		"damping": clampf(0.35 + 0.4 * openness, 0.0, 1.0),
		"wet": clampf((0.30 - 0.26 * openness) * rules.reverb, 0.0, 1.0),
	}


func describe() -> Dictionary:
	var out := reverb_params()
	out["tail_class"] = tail_class
	out["size"] = size
	out["openness"] = openness
	return out


func _to_outdoor(delta: float) -> void:
	_target_size = max_range
	_target_open = 1.0
	_swept = true
	advance(delta)


func _pick_class() -> void:
	var low := classify(size * 0.88, openness - 0.04)
	var high := classify(size * 1.12, openness + 0.04)
	var raw := classify(size, openness)
	# Near a boundary the two disagree and the current class stands: a doorway does not flap the tail.
	var next: StringName = raw if low == high else tail_class
	if not rules.enclosure:
		next = &"outdoor"
	if next != tail_class:
		var from := tail_class
		tail_class = next
		DotLog.debug(CHANNEL, "room class changed", {"from": String(from), "to": String(next), "size": size, "open": openness})
		class_changed.emit(from, next)


func _apply_reverb() -> void:
	if _reverb == null:
		return
	var p := reverb_params()
	_reverb.room_size = p["room_size"]
	_reverb.damping = p["damping"]
	_reverb.wet = p["wet"]
