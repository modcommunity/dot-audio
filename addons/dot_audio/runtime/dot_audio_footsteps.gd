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
## collider; its `surface` meta (or a parent's, three levels up), a `surface_<name>` group,
## or its node name ("Floor_Wood") names it, folded through [method DotAudioStock.surface_of];
## anything else is [member default_surface], which a game sets per map.
##
## [b]Never on a server.[/b] It only plays; [signal stepped] tells a game what was heard,
## which is how a bot that listens hears without a second footstep system.

const CHANNEL := "audio.steps"

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
## Physics layers the ground ray sees.
@export_flags_3d_physics var ground_mask: int = 0xFFFFFFFF

# body -> {last: Vector3, travelled: float, air: float, grounded: bool, surface: StringName, opts}
var _bodies: Dictionary = {}


## Starts stepping for a body. [param opts]: `surface` (fixed surface for this body),
## `loudness` (scale), `grounded` (a Callable returning bool, for a body that is not a
## CharacterBody3D and knows better than a ray).
func track(body: Node3D, opts: Dictionary = {}) -> void:
	if body == null:
		return
	_bodies[body] = {
		"last": body.global_position if body.is_inside_tree() else Vector3.ZERO,
		"travelled": 0.0, "air": 0.0, "grounded": true, "opts": opts,
	}


func untrack(body: Node3D) -> void:
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
	for body: Variant in _bodies.keys():
		if not is_instance_valid(body) or not (body as Node3D).is_inside_tree():
			_bodies.erase(body)
			continue
		advance(body, delta)


## One body, one physics frame. Public so a suite can step it with no physics running.
func advance(body: Node3D, delta: float) -> void:
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
	if body is CharacterBody3D:
		return (body as CharacterBody3D).is_on_floor()
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
		var s := surface_of_collider(hit.get("collider"))
		if s != &"":
			return s
	return DotAudioStock.surface_of(String(default_surface))


## What a collider says it is made of: `surface` meta on it or up to three parents, a
## `surface_<name>` group, or a surface word in its or a parent's node name. Empty if none.
static func surface_of_collider(collider: Object) -> StringName:
	var node := collider as Node
	var depth := 0
	while node != null and depth < 4:
		if node.has_meta(&"surface"):
			var s := DotAudioStock.surface_of(str(node.get_meta(&"surface")))
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
