class_name DotAudioFootsteps
extends Node

## Footsteps for every body that walks: the player, other players, bots. One node per game.
##
## [codeblock]
## var steps := DotAudioFootsteps.new()
## steps.manager = audio_manager            # or found through DotRegistry
## steps.default_surface = &"grass"         # the map's ground, for colliders that say nothing
## add_child(steps)
## steps.track(player_body)                 # a CharacterBody3D, or any Node3D
## [/codeblock]
##
## [b]A step is distance, not time.[/b] A step plays every [member stride_walk] to
## [member stride_run] metres travelled on the ground, so a body pushed by netcode
## interpolation, a bot steered by a navigation agent and a player all step at the rate
## they really move, and nothing needs an animation event.
##
## [b]Slow is silent.[/b] Under [member quiet_speed] nothing plays. Sneaking is a mechanic
## in a hiding game, and a footstep system with no quiet speed makes it impossible.
##
## [b]The surface comes from what is underfoot.[/b] A ray down from the body finds the
## collider; its `surface` or `dot_fps_surface` meta (or a parent's, three levels up), a `surface_<name>` group,
## or its node name ("Floor_Wood") names it, folded through [method DotAudioStock.surface_of];
## anything else is [member default_surface], which a game sets per map.
##
## [b]Never on a server.[/b] It only plays; [signal stepped] tells a game what was heard,
## which is how a bot that listens hears without a second footstep system.

## A step, with the surface and how loud it was (0..1 of a run).
signal stepped(body: Node3D, surface: StringName, loudness: float)

var manager: DotAudioManager = null

## The ground of the current map, for colliders that name no surface.
var default_surface: StringName = &"concrete"

## Below this speed (m/s) a body makes no sound.
@export_range(0.0, 10.0, 0.05) var quiet_speed: float = 1.4
## At and above this speed a step is at full loudness.
@export_range(0.5, 30.0, 0.1) var run_speed: float = 6.0
@export_range(0.3, 5.0, 0.05) var stride_walk: float = 1.5
@export_range(0.3, 5.0, 0.05) var stride_run: float = 2.3
## Loudness of a step at [member quiet_speed]; a run is 1.0.
@export_range(0.0, 1.0, 0.01) var walk_loudness: float = 0.45
## How far below a body's origin the ground can be and still count as underfoot.
@export_range(0.05, 5.0, 0.05) var ground_probe: float = 0.6
## Seconds in the air before touching down makes a landing.
@export_range(0.0, 2.0, 0.01) var landing_air_time: float = 0.3
## Meta keys a collider (or the hit shape) may name its surface under, first match wins.
## `dot_fps_surface` is dot-player-controller's own, so a map that already tells the movement
## what it is made of tells the footsteps too.
var surface_metas: Array[StringName] = [&"surface", &"dot_fps_surface"]

## Metres from the manager's listener past which a body is not stepped at all: no ground
## ray, no [signal stepped], no play. 0 steps every body. Set it a little past the loudest
## step's `max_distance` in a game whose steps are only ever heard, never read by rules.
@export_range(0.0, 500.0, 0.5) var hear_distance: float = 0.0

## Physics layers the ground ray sees.
@export_flags_3d_physics var ground_mask: int = 0xFFFFFFFF

# body -> {last: Vector3, travelled: float, air: float, grounded: bool, surface: StringName, opts}
## When set, a body on a surf ramp makes no steps or landings ([DotAudioSurf] plays its glide).
var surf_rules: DotAudioSurfRules = null

var _bodies: Dictionary = {}

## dot-sim's native tick ([code]DotSimAudioSteps[/code]): the same steps to the bit (dot-audio's examples/steps_native_parity),
## used when the extension is loaded, [member native_enabled] and [member use_native] are on and this node is a
## plain [DotAudioFootsteps] (a subclass may change any part of a step). On the web, or with no library, the script runs.
const NATIVE_CLASS := &"DotSimAudioSteps"
## Whether the native tick is used when present. On by default: the packed native passes hold the bodies' state
## and make about four engine calls a body, measured about twice as fast as this script for footsteps and surf
## (examples/steps_native_parity prints both).
static var native_enabled: bool = true
## This node's own switch beside [member native_enabled].
var use_native: bool = true
static var _native_known: int = -1
var _native: Object = null
var _native_tun := PackedFloat64Array()
var _native_surf_args := PackedFloat64Array()
# Whether the native tick holds the bodies' state (last, travelled, air, grounded) instead of [member _bodies]:
# loaded once ([method _native_load]) and kept there until the tracked set changes ([method _native_release]).
var _native_owns: bool = false
var _native_keys: Array = []


## Whether dot-sim's native audio tick is loaded and enabled.
static func native_available() -> bool:
	if _native_known < 0:
		_native_known = 1 if ClassDB.class_exists(NATIVE_CLASS) else 0
	return native_enabled and _native_known == 1


## Starts stepping for a body. [param opts]: `surface` (fixed surface for this body),
## `loudness` (scale), `grounded` (a Callable returning bool, for a body that is not a
## CharacterBody3D and knows better than a ray).
func track(body: Node3D, opts: Dictionary = {}) -> void:
	if body == null:
		return
	_native_release()
	_bodies[body] = {
		"last": body.global_position if body.is_inside_tree() else Vector3.ZERO,
		"travelled": 0.0, "air": 0.0, "grounded": true, "opts": opts,
	}


## Tracks exactly these bodies: starts the new ones and drops the rest. For a game that
## holds its players in a dictionary and calls this once a frame with its values.
func keep(bodies: Array, opts: Dictionary = {}) -> void:
	var seen := {}
	for b: Variant in bodies:
		if b is Node3D and is_instance_valid(b):
			seen[b] = true
			if not _bodies.has(b):
				track(b, opts)
	for b: Variant in _bodies.keys():
		if not seen.has(b):
			_native_release()
			_bodies.erase(b)


func untrack(body: Node3D) -> void:
	_native_release()
	_bodies.erase(body)


func is_tracking(body: Node3D) -> bool:
	return _bodies.has(body)


func tracked_count() -> int:
	return _bodies.size()


func _physics_process(delta: float) -> void:
	if _bodies.is_empty():
		return
	if manager == null:
		manager = DotRegistry.get_node_service(DotAudioManager.SERVICE) as DotAudioManager
	if use_native and native_available() and get_script() == DotAudioFootsteps:
		_native_pass(delta)
		return
	_native_release()
	for body: Variant in _bodies.keys():
		if not is_instance_valid(body) or not (body as Node3D).is_inside_tree():
			_bodies.erase(body)
			continue
		advance(body, delta)


## [method _physics_process] natively: the same advance over the bodies the native tick holds, the steps played here.
func _native_pass(delta: float) -> void:
	if _native == null:
		_native = ClassDB.instantiate(NATIVE_CLASS)
	if not _native_owns:
		_native_load()
	_native_tun.resize(6)
	_native_tun[0] = quiet_speed
	_native_tun[1] = run_speed
	_native_tun[2] = stride_walk
	_native_tun[3] = stride_run
	_native_tun[4] = walk_loudness
	_native_tun[5] = landing_air_time
	var surf: Variant = null
	if surf_rules != null and surf_rules.mute_steps:
		surf = surf_rules.native_probe()
		if surf == null:
			surf = surf_rules.is_surfing
		else:
			_native_surf_args = surf_rules.native_args(_native_surf_args)
	var hear := hear_distance if manager != null else 0.0
	var ear := manager.listener_position if manager != null else Vector3.ZERO
	var steps: Array = _native.call(&"steps_tick", delta, _native_tun, ear, hear, surf,
		_native_surf_args, ground_probe, ground_mask)
	for i in range(0, steps.size(), 2):
		var body: Variant = steps[i]
		var loudness := float(steps[i + 1])
		if loudness < 0.0:
			# Freed or out of the tree: the native tick dropped it already.
			_bodies.erase(body)
			var at := _native_keys.find(body)
			if at >= 0:
				_native_keys.remove_at(at)
			continue
		var st: Dictionary = _bodies.get(body, {})
		if not st.is_empty() and is_instance_valid(body):
			_step(body, st, loudness)


## Hands every body's state to the native tick (the `grounded` option is read here, once).
func _native_load() -> void:
	_native_keys = _bodies.keys()
	var state := PackedFloat64Array()
	state.resize(_native_keys.size() * 6)
	var grounded: Array = []
	grounded.resize(_native_keys.size())
	for i in _native_keys.size():
		var st: Dictionary = _bodies[_native_keys[i]]
		var last: Vector3 = st["last"]
		state[i * 6] = last.x
		state[i * 6 + 1] = last.y
		state[i * 6 + 2] = last.z
		state[i * 6 + 3] = float(st["travelled"])
		state[i * 6 + 4] = float(st["air"])
		state[i * 6 + 5] = 1.0 if bool(st["grounded"]) else 0.0
		var g: Variant = (st["opts"] as Dictionary).get("grounded")
		grounded[i] = g if g is Callable else null
	_native.call(&"steps_load", _native_keys, state, grounded)
	_native_owns = true


## Writes the native tick's state back into [member _bodies] (it keeps holding it). A suite calls this before
## reading [member _bodies].
func native_sync() -> void:
	if not _native_owns or _native == null:
		return
	var state: PackedFloat64Array = _native.call(&"steps_state")
	for i in mini(_native_keys.size(), state.size() / 6):
		var st: Dictionary = _bodies.get(_native_keys[i], {})
		if st.is_empty():
			continue
		st["last"] = Vector3(state[i * 6], state[i * 6 + 1], state[i * 6 + 2])
		st["travelled"] = state[i * 6 + 3]
		st["air"] = state[i * 6 + 4]
		st["grounded"] = state[i * 6 + 5] != 0.0


## Takes the state back from the native tick before [member _bodies] changes; the next native pass loads it again.
func _native_release() -> void:
	if not _native_owns:
		return
	native_sync()
	_native_owns = false
	_native_keys = []


## One body, one physics frame. Public so a suite can step it with no physics running.
func advance(body: Node3D, delta: float) -> void:
	_native_release()
	var st: Dictionary = _bodies.get(body, {})
	if st.is_empty():
		return
	var pos := body.global_position
	var last: Vector3 = st["last"]
	st["last"] = pos
	var moved := Vector2(pos.x - last.x, pos.z - last.z).length()
	# A respawn or a correction is not a walk.
	if moved > 4.0 or delta <= 0.0:
		st["travelled"] = 0.0
		return
	var out_of_earshot := hear_distance > 0.0 and manager != null \
		and manager.listener_position.distance_squared_to(pos) > hear_distance * hear_distance
	if out_of_earshot:
		st["travelled"] = 0.0
		st["air"] = 0.0
		st["grounded"] = true
		return
	if surf_rules != null and surf_rules.mute_steps and surf_rules.is_surfing(body):
		st["travelled"] = 0.0
		st["air"] = 0.0
		st["grounded"] = true
		return
	var grounded := _grounded(body, st)
	if not grounded:
		st["air"] = float(st["air"]) + delta
		st["grounded"] = false
		return
	if not bool(st["grounded"]):
		st["grounded"] = true
		if float(st["air"]) >= landing_air_time:
			_step(body, st, 1.0)
			st["travelled"] = 0.0
		st["air"] = 0.0
	var speed := moved / delta
	if speed < quiet_speed:
		st["travelled"] = 0.0
		return
	var t := clampf((speed - quiet_speed) / maxf(run_speed - quiet_speed, 0.01), 0.0, 1.0)
	st["travelled"] = float(st["travelled"]) + moved
	if float(st["travelled"]) >= lerpf(stride_walk, stride_run, t):
		st["travelled"] = 0.0
		_step(body, st, lerpf(walk_loudness, 1.0, t))


func _grounded(body: Node3D, st: Dictionary) -> bool:
	var opts: Dictionary = st["opts"]
	if opts.get("grounded") is Callable:
		return bool((opts["grounded"] as Callable).call())
	# A CharacterBody3D that is not simulated here (a remote player placed from snapshots)
	# keeps a stale is_on_floor(), so a false one is asked again of the ground itself.
	if body is CharacterBody3D and (body as CharacterBody3D).is_on_floor():
		return true
	return _ground_hit(body).size() > 0


func _step(body: Node3D, st: Dictionary, loudness: float) -> void:
	var opts: Dictionary = st["opts"]
	loudness *= float(opts.get("loudness", 1.0))
	var surface: StringName = opts.get("surface", &"")
	if surface == &"":
		surface = surface_under(body)
	stepped.emit(body, surface, loudness)
	if manager != null:
		manager.play_at(DotAudioStock.footstep_id(surface), body.global_position, loudness)


## The surface under a body: what the ground collider says, else [member default_surface].
func surface_under(body: Node3D) -> StringName:
	var hit := _ground_hit(body)
	if not hit.is_empty():
		var s := surface_of_collider(hit.get("collider"), int(hit.get("shape", -1)), surface_metas)
		if s != &"":
			return s
	return DotAudioStock.surface_of(String(default_surface))


## What a collider says it is made of: the hit shape's `surface` meta, then `surface` meta on
## it or up to three parents, a
## `surface_<name>` group, or a surface word in its or a parent's node name. Empty if none.
##
## [param shape_index] is the hit's shape: one static body built of many boxes (a map built
## from a document) names each box's surface on its [CollisionShape3D], which is asked first.
static func surface_of_collider(
	collider: Object, shape_index: int = -1, metas: Array[StringName] = [&"surface", &"dot_fps_surface"]
) -> StringName:
	if shape_index >= 0 and collider is CollisionObject3D:
		var body := collider as CollisionObject3D
		var owner_id := body.shape_find_owner(shape_index)
		var shape_node := body.shape_owner_get_owner(owner_id) as Node if owner_id >= 0 else null
		if shape_node != null:
			for key in metas:
				if shape_node.has_meta(key):
					var from_shape := DotAudioStock.surface_of(str(shape_node.get_meta(key)))
					if from_shape != &"":
						return from_shape
	var node := collider as Node
	var depth := 0
	while node != null and depth < 4:
		for key in metas:
			if node.has_meta(key):
				var s := DotAudioStock.surface_of(str(node.get_meta(key)))
				if s != &"":
					return s
		for g in node.get_groups():
			var gs := String(g)
			if gs.begins_with("surface_"):
				var s := DotAudioStock.surface_of(gs.trim_prefix("surface_"))
				if s != &"":
					return s
		var by_name := DotAudioStock.surface_of(String(node.name))
		if by_name != &"":
			return by_name
		node = node.get_parent()
		depth += 1
	return &""


func _ground_hit(body: Node3D) -> Dictionary:
	var world := body.get_world_3d()
	if world == null:
		return {}
	var from := body.global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, body.global_position + Vector3.DOWN * ground_probe, ground_mask)
	if body is CollisionObject3D:
		q.exclude = [(body as CollisionObject3D).get_rid()]
	return world.direct_space_state.intersect_ray(q)


func describe() -> Dictionary:
	return {"bodies": _bodies.size(), "default_surface": String(default_surface)}


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"dot-audio footsteps  %d bodies, ground %s, quiet under %.1f m/s" % [
			_bodies.size(), default_surface, quiet_speed],
	])
