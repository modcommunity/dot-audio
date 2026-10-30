class_name DotAudioSurfRules
extends RefCounted

## What surfing sounds like and when a body counts as surfing. A body on a ramp too steep to
## stand on is gliding, not walking: footsteps and landings there are one constant noise, so they
## are silenced and [DotAudioSurf] plays a quiet glide whose volume and pitch follow speed.
## Every number is a `sv_surf_*` cvar (a game replicates them) and settable from a profile.

const CVAR_PREFIX := "sv_surf_"

## The glide loop's switch (`sv_surf_sounds`).
var enabled: bool = true
## Level of the glide, 0..2; 1 is the stock level (`sv_surf_volume`).
var volume: float = 0.6
## Slower than this (m/s) the glide is silent (`sv_surf_quiet_speed`).
var quiet_speed: float = 4.0
## At and above this speed (m/s) the glide is at full level and top pitch (`sv_surf_full_speed`).
var full_speed: float = 22.0
## Pitch at [member quiet_speed] (`sv_surf_pitch_low`).
var pitch_low: float = 0.75
## Pitch at [member full_speed] (`sv_surf_pitch_high`).
var pitch_high: float = 1.35
## Whether footsteps and landings stop while surfing (`sv_surf_mute_steps`).
var mute_steps: bool = true
## Metres below the origin a ramp still counts as underfoot.
var probe: float = 1.2
## The ground normal's up component must be under this to be too steep to walk (45 degrees).
var max_normal_y: float = 0.707
## Under this a face is a wall, not a ramp.
var min_normal_y: float = 0.02
## Physics layers the ramp probe sees.
var mask: int = 0xFFFFFFFF

var _seen: Dictionary = {}


## Name, field, default, description and range of each cvar.
static func cvar_specs() -> Array[Dictionary]:
	return [
		{"name": "sv_surf_sounds", "field": "enabled", "value": "1", "min": 0.0, "max": 1.0,
			"description": "Whether surfing plays a quiet glide (1) or nothing (0)"},
		{"name": "sv_surf_volume", "field": "volume", "value": "0.6", "min": 0.0, "max": 2.0,
			"description": "Surf glide level: 0 off, 1 stock level"},
		{"name": "sv_surf_quiet_speed", "field": "quiet_speed", "value": "4", "min": 0.0, "max": 60.0,
			"description": "Speed in m/s under which the surf glide is silent"},
		{"name": "sv_surf_full_speed", "field": "full_speed", "value": "22", "min": 1.0, "max": 200.0,
			"description": "Speed in m/s at which the surf glide is loudest and highest"},
		{"name": "sv_surf_pitch_low", "field": "pitch_low", "value": "0.75", "min": 0.25, "max": 2.0,
			"description": "Surf glide pitch at the quiet speed"},
		{"name": "sv_surf_pitch_high", "field": "pitch_high", "value": "1.35", "min": 0.25, "max": 3.0,
			"description": "Surf glide pitch at the full speed"},
		{"name": "sv_surf_mute_steps", "field": "mute_steps", "value": "1", "min": 0.0, "max": 1.0,
			"description": "Whether footsteps and landings stop while surfing (1) or play as usual (0)"},
	]


## Sets the field behind [param cvar_name] from its text; false for a name that is not one of ours.
func apply_cvar(cvar_name: String, value: String) -> bool:
	for spec: Dictionary in cvar_specs():
		if spec["name"] != cvar_name or not value.is_valid_float():
			continue
		var v := clampf(value.to_float(), float(spec["min"]), float(spec["max"]))
		var field := String(spec["field"])
		if field == "enabled" or field == "mute_steps":
			set(field, v >= 0.5)
		else:
			set(field, v)
		return true
	return false


## Sets every field in [param values] (cvar name or field name to value), as a profile hands them over. Returns how many applied.
func apply_values(values: Dictionary) -> int:
	var n := 0
	for k: Variant in values:
		var key := String(k)
		var cvar := key if key.begins_with(CVAR_PREFIX) else CVAR_PREFIX + key
		var text := str(values[k])
		if text == "true" or text == "false":
			text = "1" if text == "true" else "0"
		if apply_cvar(cvar, text):
			n += 1
	return n


## Registers every cvar through [param add] (a module's `add_cvar`, duck-typed) and follows each.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var out: Array = []
	for spec: Dictionary in cvar_specs():
		var cv: Variant = add.call(String(spec["name"]), String(spec["value"]), String(spec["description"]), flags)
		if not (cv is Object) or cv == null:
			continue
		var obj := cv as Object
		if obj.has_method(&"with_range"):
			obj.call(&"with_range", float(spec["min"]), float(spec["max"]))
		var cvar_name := String(spec["name"])
		if obj.has_signal(&"changed"):
			obj.connect(&"changed", func(_old: Variant, new_value: Variant) -> void:
				var _ok := apply_cvar(cvar_name, str(new_value)))
		out.append(obj)
	return out


## (volume, pitch) of the glide at [param speed] m/s.
func shape(speed: float) -> Vector2:
	var t := clampf((speed - quiet_speed) / maxf(full_speed - quiet_speed, 0.01), 0.0, 1.0)
	return Vector2(t * volume, lerpf(pitch_low, pitch_high, t) + 0.05 * maxf(speed / maxf(full_speed, 0.01) - 1.0, 0.0))


## Whether [param normal] is a face too steep to stand on and not a wall.
func is_ramp_normal(normal: Vector3) -> bool:
	return normal.y > min_normal_y and normal.y < max_normal_y


## Whether [param body] is on a surf ramp now (a ray down; cached for the physics frame).
func is_surfing(body: Node3D) -> bool:
	var frame := Engine.get_physics_frames()
	var id := body.get_instance_id()
	var cached: Variant = _seen.get(id)
	if cached != null and int(cached[0]) == frame:
		return bool(cached[1])
	var yes := false
	var world := body.get_world_3d()
	if world != null:
		var from := body.global_position + Vector3.UP * 0.3
		var q := PhysicsRayQueryParameters3D.create(from, body.global_position + Vector3.DOWN * probe, mask)
		if body is CollisionObject3D:
			q.exclude = [(body as CollisionObject3D).get_rid()]
		var hit := world.direct_space_state.intersect_ray(q)
		yes = not hit.is_empty() and is_ramp_normal(hit.get("normal", Vector3.UP))
	if _seen.size() > 256:
		_seen.clear()
	_seen[id] = [frame, yes]
	return yes


func describe() -> Dictionary:
	return {"enabled": enabled, "volume": volume, "quiet": quiet_speed, "full": full_speed,
		"pitch": [pitch_low, pitch_high], "mute_steps": mute_steps}
