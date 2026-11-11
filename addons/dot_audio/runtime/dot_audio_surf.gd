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


func _sound_for(_surface: StringName) -> StringName:
	return DotAudioStock.SURF_GLIDE_ID


func _shape(speed: float, loudness: float) -> Vector2:
	var s := rules.shape(speed)
	return Vector2(s.x * volume * loudness, s.y)


## Surf has one surface; the ray is skipped.
func surface_under(_body: Node3D) -> StringName:
	return &"surf"
