class_name DotShotRules
extends RefCounted

## What the layered shot sound does, as server and client cvars (default on): [signal changed] on any change. Presentation only.

signal changed

const CVAR_LAYERS := "snd_shot_layers"
const CVAR_ENCLOSURE := "snd_shot_enclosure"
const CVAR_RAYS := "snd_shot_rays"
const CVAR_DELAY := "snd_shot_delay"
const CVAR_NEAR := "snd_shot_near"
const CVAR_FAR := "snd_shot_far"
const CVAR_REVERB := "snd_shot_reverb"
const CVAR_TAIL_VOICES := "snd_shot_tail_voices"
## Seconds each tail class sounds, from the stock files; the player's voice count uses them.
const TAIL_SECONDS := {&"small": 0.27, &"medium": 0.66, &"large": 1.52, &"hall": 3.17, &"outdoor": 1.5}

## Layered shots at all; off leaves the game's single stock sound.
var layers := true:
	set(v):
		if v != layers:
			layers = v
			changed.emit()
## The enclosure probe picks the tail and the reverb; off is always the outdoor tail.
var enclosure := true:
	set(v):
		if v != enclosure:
			enclosure = v
			changed.emit()
## Rays in one enclosure sweep (16-32).
var rays := 24:
	set(v):
		v = clampi(v, 16, 32)
		if v != rays:
			rays = v
			changed.emit()
## Speed-of-sound delay on a shot heard from afar.
var delay := true:
	set(v):
		if v != delay:
			delay = v
			changed.emit()
## Metres inside which only the close set plays, and beyond which only the far set does (crossfaded between).
var near_metres := 25.0:
	set(v):
		v = clampf(v, 1.0, 500.0)
		if not is_equal_approx(v, near_metres):
			near_metres = v
			changed.emit()
var far_metres := 130.0:
	set(v):
		v = clampf(v, 2.0, 2000.0)
		if not is_equal_approx(v, far_metres):
			far_metres = v
			changed.emit()
## Scales the enclosure reverb's wet level, 0 none to 2 double.
var reverb := 1.0:
	set(v):
		v = clampf(v, 0.0, 2.0)
		if not is_equal_approx(v, reverb):
			reverb = v
			changed.emit()

## Most room tails sounding at once from one player, 0 for no limit: a rapid-fire weapon would stack a hall's 3 s tail
## on every round.
var tail_voices := 4:
	set(v):
		v = clampi(v, 0, 16)
		if v != tail_voices:
			tail_voices = v
			changed.emit()

## Metres per second; the delay of a shot heard from [param metres].
const SPEED_OF_SOUND := 343.0


## Seconds before a shot [param metres] away is heard; 0 when [member delay] is off. Capped at 2.5 s.
func delay_for(metres: float) -> float:
	return minf(metres / SPEED_OF_SOUND, 2.5) if delay else 0.0


## The close-set and far-set weights at [param metres]: equal power, so the crossfade holds its loudness.
func weights(metres: float) -> Vector2:
	var span := maxf(far_metres - near_metres, 0.001)
	var t := clampf((metres - near_metres) / span, 0.0, 1.0)
	return Vector2(cos(t * PI * 0.5), sin(t * PI * 0.5))


func cvar_specs() -> Array[Dictionary]:
	return [
		{"name": CVAR_LAYERS, "value": "1" if layers else "0", "min": 0.0, "max": 1.0,
			"description": "Layered weapon shots (attack, body, tail; close and far sets): 1 on, 0 the single stock sound"},
		{"name": CVAR_ENCLOSURE, "value": "1" if enclosure else "0", "min": 0.0, "max": 1.0,
			"description": "Shots sound different in tight spaces: rays measure the room and pick the tail and reverb"},
		{"name": CVAR_RAYS, "value": str(rays), "min": 16.0, "max": 32.0,
			"description": "Rays in one room-measuring sweep, 16 to 32"},
		{"name": CVAR_DELAY, "value": "1" if delay else "0", "min": 0.0, "max": 1.0,
			"description": "Delay a distant shot by the speed of sound"},
		{"name": CVAR_NEAR, "value": str(near_metres), "min": 1.0, "max": 500.0,
			"description": "Metres inside which only the close shot set plays"},
		{"name": CVAR_FAR, "value": str(far_metres), "min": 2.0, "max": 2000.0,
			"description": "Metres beyond which only the far shot set plays"},
		{"name": CVAR_REVERB, "value": str(reverb), "min": 0.0, "max": 2.0,
			"description": "Scale of the room reverb on shots: 0 none, 1 normal, 2 double"},
		{"name": CVAR_TAIL_VOICES, "value": str(tail_voices), "min": 0.0, "max": 16.0,
			"description": "Most room tails sounding at once from one player, 0 for no limit (a rapid-fire weapon in a hall)"},
	]


## Registers the cvars through [param add] (a server module's `add_cvar`, `(name, default, description, flags) -> cvar`)
## and follows them. Duck-typed; a value already held is read back.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in cvar_specs():
		var cvar_name: String = spec["name"]
		var made_cvar: Variant = add.call(cvar_name, String(spec["value"]), String(spec["description"]), flags)
		if not (made_cvar is Object) or made_cvar == null:
			continue
		var cv := made_cvar as Object
		if cv.has_method(&"with_range"):
			cv.call(&"with_range", float(spec["min"]), float(spec["max"]))
		if cv.has_signal(&"changed"):
			var on_change := _on_cvar_changed.bind(cvar_name)
			if not cv.is_connected(&"changed", on_change):
				cv.connect(&"changed", on_change)
		if cv.has_method(&"get_string"):
			var _applied := set_cvar(cvar_name, String(cv.call(&"get_string")))
		made.append(cv)
	return made


## Follows a server's replicated values through [param source] (`replicated_cvar`, `replicated_cvar_changed`).
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for spec in cvar_specs():
		var held := String(source.call(&"replicated_cvar", spec["name"], ""))
		if held != "":
			var _applied := set_cvar(spec["name"], held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated_cvar):
		source.connect(&"replicated_cvar_changed", _on_replicated_cvar)
	return true


## Applies one cvar by name. False for another name or a value out of range.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	match cvar_name:
		CVAR_LAYERS, CVAR_ENCLOSURE, CVAR_DELAY:
			if text != "0" and text != "1":
				return false
			var on := text == "1"
			if cvar_name == CVAR_LAYERS: layers = on
			elif cvar_name == CVAR_ENCLOSURE: enclosure = on
			else: delay = on
			return true
		CVAR_RAYS, CVAR_TAIL_VOICES:
			if not text.is_valid_int():
				return false
			if cvar_name == CVAR_RAYS: rays = text.to_int()
			else: tail_voices = text.to_int()
			return true
		CVAR_NEAR, CVAR_FAR, CVAR_REVERB:
			if not text.is_valid_float():
				return false
			if cvar_name == CVAR_NEAR: near_metres = text.to_float()
			elif cvar_name == CVAR_FAR: far_metres = text.to_float()
			else: reverb = text.to_float()
			return true
	return false


func _on_cvar_changed(_old: Variant, new_value: Variant, cvar_name: String) -> void:
	var _applied := set_cvar(cvar_name, str(new_value))


func _on_replicated_cvar(cvar_name: String, value: String) -> void:
	var _applied := set_cvar(cvar_name, value)
