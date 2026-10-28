class_name DotAudioLandingRules
extends RefCounted
## The client's landing-sound settings: one volume cvar, mild by default.

const CVAR_VOLUME := "cl_landing_volume"

## 0 mutes landings; 1 is the stock def's level (cl_landing_volume).
var volume: float = 0.6:
	set(value):
		volume = clampf(value, 0.0, 2.0)

## Landings softer than this (m/s downward) are silent: a step off a kerb is not a thump.
var min_impact: float = 4.0


## The [code]volume_scale[/code] for [method DotAudioManager.play] at [param impact] m/s; 0 means do not play.
func volume_for(impact: float) -> float:
	if volume <= 0.0 or impact < min_impact:
		return 0.0

	return volume * clampf(0.35 + impact / 20.0, 0.35, 1.2)


## Registers [constant CVAR_VOLUME] through [param add] (a module's `add_cvar`, duck-typed) and follows it.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var cv: Variant = add.call(CVAR_VOLUME, str(volume), "Landing thump volume: 0 off, 1 stock level", flags)

	if not (cv is Object) or cv == null:
		return []

	var obj := cv as Object

	if obj.has_method(&"with_range"):
		obj.call(&"with_range", 0.0, 2.0)

	if obj.has_signal(&"changed"):
		obj.connect(&"changed", func(_old: Variant, new_value: Variant) -> void:
			if str(new_value).is_valid_float():
				volume = str(new_value).to_float())

	if obj.has_method(&"get_string") and String(obj.call(&"get_string")).is_valid_float():
		volume = String(obj.call(&"get_string")).to_float()

	return [obj]
