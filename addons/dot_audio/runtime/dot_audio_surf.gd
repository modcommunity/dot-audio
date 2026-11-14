class_name DotAudioSurf
extends DotAudioSlide

## The glide of a body surfing a ramp: one quiet looping voice per surfer, louder and higher the
## faster it goes (curve and switches in [member rules]). Call [method keep_surfers] each frame. Never on a server.

var rules: DotAudioSurfRules = DotAudioSurfRules.new()


## Follows exactly these bodies, each surfing by [method DotAudioSurfRules.is_surfing].
func keep_surfers(bodies: Array) -> void:
	keep(bodies, _is_surfer)


func _is_surfer(b: Node3D) -> bool:
	return rules.enabled and rules.is_surfing(b)


## A body not yet gliding and slower than the quiet speed would play nothing (volume 0), so its ray is saved; it is asked
## again the tick it passes that speed, and a gliding body is asked every tick.
func _worth_asking(playing: bool, speed: float) -> bool:
	return playing or speed >= rules.quiet_speed


func _native_ok() -> bool:
	return get_script() == DotAudioSurf


func _native_quiet() -> float:
	return rules.quiet_speed


func _native_probe() -> Object:
	var probe := rules.native_probe()
	if probe != null:
		_native_args = rules.native_args(_native_args)
	return probe


func _native_surfer(body: Node3D, sliding: Callable) -> bool:
	return sliding.get_object() == self and sliding.get_method() == &"_is_surfer" \
		and sliding.get_bound_arguments() == [body]


func _native_surfing_on() -> bool:
	return rules.enabled


var _glide_ids: Array[StringName] = [DotAudioStock.SURF_GLIDE_ID]


func _sound_ids() -> Array[StringName]:
	return _glide_ids


func _sound_for(_surface: StringName) -> StringName:
	return DotAudioStock.SURF_GLIDE_ID


func _shape(speed: float, loudness: float) -> Vector2:
	var s := rules.shape(speed)
	return Vector2(s.x * volume * loudness, s.y)


## Surf has one surface; the ray is skipped.
func surface_under(_body: Node3D) -> StringName:
	return &"surf"
