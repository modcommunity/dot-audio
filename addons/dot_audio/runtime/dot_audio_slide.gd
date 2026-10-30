class_name DotAudioSlide
extends Node

## The scrape of a body sliding along the ground: one looping voice per sliding body, chosen by its
## surface (found as [DotAudioFootsteps] does; none set plays the generic scrape), louder and higher
## the faster it goes. Use `slide.keep(players, is_sliding_callable)`. Never on a server.

## A slide started or ended, with the surface it scrapes.
signal slide_started(body: Node3D, surface: StringName)
signal slide_stopped(body: Node3D)

var manager: DotAudioManager = null
## The map's ground for colliders that name no surface; empty plays the generic scrape.
var default_surface: StringName = &""
## The server's switch (a game binds its cvar to this).
var enabled: bool = true
## The player's slider (0..1), multiplied into every loop.
var volume: float = 1.0
## Speed (m/s) at which the loop is at full volume and unchanged pitch.
@export_range(1.0, 30.0, 0.5) var full_speed: float = 9.0
## Slower than this the scrape fades out to nothing.
@export_range(0.0, 10.0, 0.1) var quiet_speed: float = 1.0
@export_range(0.0, 1.0, 0.01) var min_pitch_drop: float = 0.25
@export_range(0.05, 5.0, 0.05) var ground_probe: float = 0.6
@export_flags_3d_physics var ground_mask: int = 0xFFFFFFFF
var surface_metas: Array[StringName] = [&"surface", &"dot_fps_surface"]

# body -> {last, handle, surface, sliding: Callable, opts}
var _bodies: Dictionary = {}


## Starts following a body. [param sliding] returns whether it slides now.
func track(body: Node3D, sliding: Callable, opts: Dictionary = {}) -> void:
	if body == null or _bodies.has(body):
		return
	_bodies[body] = {
		"last": body.global_position if body.is_inside_tree() else Vector3.ZERO,
		"handle": 0, "surface": &"", "sliding": sliding, "opts": opts,
	}


## Follows exactly these bodies (dropping the rest), once a frame, like [method DotAudioFootsteps.keep].
func keep(bodies: Array, sliding_of: Callable) -> void:
	var seen := {}
	for b: Variant in bodies:
		if b is Node3D and is_instance_valid(b):
			seen[b] = true
			if not _bodies.has(b):
				track(b, sliding_of.bind(b))
	for b: Variant in _bodies.keys():
		if seen.has(b):
			continue
		if is_instance_valid(b):
			untrack(b)
		else:
			_drop_freed(b)


## A freed owner can't ride the typed [signal slide_stopped], so its loop stops and no signal fires.
func _drop_freed(body: Variant) -> void:
	var st: Dictionary = _bodies.get(body, {})
	if manager != null and int(st.get("handle", 0)) != 0:
		manager.stop(int(st["handle"]))
	_bodies.erase(body)


func untrack(body: Node3D) -> void:
	_stop(body)
	_bodies.erase(body)


func is_sliding(body: Node3D) -> bool:
	return bool(_bodies.get(body, {}).get("on", false))


func _physics_process(delta: float) -> void:
	if _bodies.is_empty():
		return
	if manager == null:
		manager = DotRegistry.get_node_service(DotAudioManager.SERVICE) as DotAudioManager
	for body: Variant in _bodies.keys():
		if not is_instance_valid(body):
			_drop_freed(body)
			continue
		if not (body as Node3D).is_inside_tree():
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
	var speed := Vector2(pos.x - last.x, pos.z - last.z).length() / maxf(delta, 0.0001)
	# A respawn or a correction is not a slide.
	if speed > 60.0:
		speed = 0.0
	var want: bool = enabled and bool((st["sliding"] as Callable).call())
	var on: bool = st.get("on", false)
	if not want:
		if on:
			_stop(body)
		return
	var opts: Dictionary = st["opts"]
	var surface: StringName = opts.get("surface", &"")
	if surface == &"":
		surface = surface_under(body)
	if not on or surface != st["surface"]:
		var restart := on
		if restart and manager != null:
			manager.stop(int(st["handle"]))
		st["on"] = true
		st["surface"] = surface
		st["handle"] = 0
		if not restart:
			slide_started.emit(body, surface)
	var shaped := _shape(speed, float(opts.get("loudness", 1.0)))
	var vol: float = shaped.x
	var pitch: float = shaped.y
	if manager == null:
		return
	var h: int = int(st["handle"])
	if h != 0 and manager.shape(h, vol, pitch):
		manager.move(h, pos)
		return
	if vol <= 0.0:
		return
	st["handle"] = manager.play_at(_sound_for(surface), pos, vol, pitch)


## The loop to play on [param surface]; a subclass swaps it.
func _sound_for(surface: StringName) -> StringName:
	return DotAudioStock.slide_id(surface)


## (volume, pitch) at [param speed] m/s; a subclass swaps the curve.
func _shape(speed: float, loudness: float) -> Vector2:
	var t := clampf((speed - quiet_speed) / maxf(full_speed - quiet_speed, 0.01), 0.0, 1.0)
	return Vector2(t * volume * loudness, lerpf(1.0 - min_pitch_drop, 1.0, t) + 0.1 * maxf(speed / full_speed - 1.0, 0.0))


func _stop(body: Node3D) -> void:
	var st: Dictionary = _bodies.get(body, {})
	if st.is_empty() or not bool(st.get("on", false)):
		return
	if manager != null and int(st["handle"]) != 0:
		manager.stop(int(st["handle"]))
	st["handle"] = 0
	st["on"] = false
	slide_stopped.emit(body)


## The surface under a body: what the ground collider says, else [member default_surface].
func surface_under(body: Node3D) -> StringName:
	var world := body.get_world_3d()
	if world != null:
		var q := PhysicsRayQueryParameters3D.create(
			body.global_position + Vector3.UP * 0.3, body.global_position + Vector3.DOWN * ground_probe, ground_mask)
		if body is CollisionObject3D:
			q.exclude = [(body as CollisionObject3D).get_rid()]
		var hit := world.direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var s := DotAudioFootsteps.surface_of_collider(hit.get("collider"), int(hit.get("shape", -1)), surface_metas)
			if s != &"":
				return s
	return DotAudioStock.surface_of(String(default_surface))


func describe() -> Dictionary:
	var n := 0
	for b: Variant in _bodies:
		if bool(_bodies[b].get("on", false)):
			n += 1
	return {"bodies": _bodies.size(), "sliding": n, "enabled": enabled, "volume": volume}
