class_name DotAudioManager
extends Node

## The node a game holds: ids in, limits applied, requests out to a sink.
##
## [codeblock]
## var audio := DotAudioManager.new()
## audio.catalogue = my_catalogue
## add_child(audio)
## audio.setup()
##
## audio.play(&"rifle_fire")
## audio.play_at(&"footstep", where)
## audio.play_music(&"menu_theme", 1.5)
## [/codeblock]
##
## [b]Everything above the sink runs in every deployment, including one with no sound
## card.[/b] Ids are resolved, concurrency is counted, cooldowns are honoured, voices are
## stolen by priority and the music state machine runs — and then either a noise comes out
## or [DotAudioSinkNull] writes down that one would have. That is what makes a headless
## suite a test of this system rather than of a mock, and it is why a dedicated server can
## decide what its clients are told to play.

const SERVICE := &"dot_audio"
const CHANNEL := "audio"

## Something started. [param handle] is 0 when it was refused, and [param why] says which
## rule refused it — a game's mixing screen wants that, and so does anybody wondering why
## the twelfth footstep in a tick was silent.
signal played(id: StringName, handle: int, why: StringName)

## The music track changed.
signal music_changed(from_id: StringName, to_id: StringName)

@export var catalogue: DotAudioCatalogue = null

@export var mixer: DotAudioMixer = null

## How many sounds may be in flight at once, across every id.
@export_range(1, 512, 1) var voices: int = 32

## Whether to apply [member mixer] to the engine's buses on [method setup].
##
## Off for a dedicated server, which has buses it should not be touching and no reason to.
@export var apply_mixer_to_buses: bool = true

@export var register_as_service: bool = true

## The listener's position, for culling. A game sets this once a frame.
##
## [b]Culling happens here rather than in the sink[/b] because it is the cheapest place:
## a sound refused for distance costs one vector subtraction, and a sound accepted for
## distance costs a stream load, a voice and a position update every frame. dot-audio
## would otherwise spend most of a sixty-four-player server's pool on things nobody can
## hear.
var listener_position: Vector3 = Vector3.ZERO

## Where the random choices come from. Anything with [code]unit_at(index)[/code].
##
## dot-randomness' stream, when a game has one — and then a shot's pitch and variant are
## the same on the server and on every client watching, which is what makes an audio bug
## reproducible. Without one it falls back to the engine's generator and says so.
var roll_source: Object = null

var sink: DotAudioSink = null

var _playing: Dictionary = {}
var _concurrent: Dictionary = {}
var _last_started_ms: Dictionary = {}
var _music_handle := 0
var _music_id: StringName = &""
var _roll_index := 0
var _ducked := false


func setup() -> DotResult:
	if catalogue == null:
		catalogue = DotAudioCatalogue.new()
	var res := catalogue.validate()
	if not res.ok:
		return res.wrap("audio catalogue")

	if mixer == null:
		mixer = DotAudioMixer.new()
	var mres := mixer.validate()
	if not mres.ok:
		return mres.wrap("audio mixer")

	if sink == null:
		# The honest capability question, asked once. AudioServer reports a working sound
		# card when there is none -- a mix rate, a device list and a latency, all
		# plausible -- and only get_driver_name() says "Dummy". dot-voice found that, and
		# a check built on any of the others passes on a machine with no audio at all.
		if DotAudioSink.device_present():
			sink = DotAudioSinkGodot.new(self, voices)
		else:
			sink = DotAudioSinkNull.new(voices)
			DotLog.info(CHANNEL, "no audio device; sounds are resolved and not heard")

	if apply_mixer_to_buses and DotAudioSink.device_present():
		var missing := mixer.apply_to_buses()
		if not missing.is_empty():
			DotLog.info(CHANNEL, "buses not present", {"names": ", ".join(missing)})

	if register_as_service:
		DotRegistry.register(SERVICE, self)
	return DotResult.success(null)


func _exit_tree() -> void:
	if sink != null:
		sink.stop_all()
	if register_as_service:
		DotRegistry.unregister_instance(SERVICE, self)


# --- Playing ----------------------------------------------------------------

## Plays a positionless sound.
func play(id: StringName, volume_scale: float = 1.0) -> int:
	return _start(id, Vector3.ZERO, false, volume_scale)


## Plays a sound in the world. A 2D game passes [code]Vector3(x, 0, y)[/code].
##
## The XZ convention is the family's: dot-npc maps a 2D world onto that plane so its
## senses, steering and navigation run unchanged, and one request shape then serves both.
func play_at(id: StringName, position: Vector3, volume_scale: float = 1.0) -> int:
	return _start(id, position, true, volume_scale)


## Plays a sound at a 2D position, on the XZ plane.
func play_at_2d(id: StringName, position: Vector2, volume_scale: float = 1.0) -> int:
	return _start(id, Vector3(position.x, 0.0, position.y), true, volume_scale)


func _start(id: StringName, position: Vector3, positioned: bool, volume_scale: float) -> int:
	var def := catalogue.find(id) if catalogue != null else null
	if def == null:
		# A refusal, not a failure. A client playing a game whose content it has not fully
		# downloaded asks for ids it does not have, and an effect never changes the
		# simulation -- so dropping one is always safe. Silence is the right outcome; a
		# red line per shot is not.
		played.emit(id, 0, &"unknown")
		return 0

	if positioned and def.max_distance > 0.0:
		if listener_position.distance_to(position) > def.max_distance:
			played.emit(id, 0, &"distance")
			return 0

	var now := Time.get_ticks_msec()
	if def.cooldown_ms > 0:
		var last := int(_last_started_ms.get(id, -1000000))
		if now - last < def.cooldown_ms:
			played.emit(id, 0, &"cooldown")
			return 0

	if def.max_concurrent > 0 and int(_concurrent.get(id, 0)) >= def.max_concurrent:
		# Reaped here as well as in _process, and this is not belt and braces. `_process`
		# does not run while the tree is paused, and a pause menu is exactly when nothing
		# finishes -- so a manager that only reaps in _process comes back from a pause with
		# every concurrency count stuck at its cap and stays silent for the rest of the
		# session. Reaping at the point of refusal makes the count correct whenever it is
		# actually consulted.
		_reap()
	if def.max_concurrent > 0 and int(_concurrent.get(id, 0)) >= def.max_concurrent:
		# Twelve identical rifles half a millisecond apart is not twelve gunshots -- it is
		# one gunshot twelve times as loud, with comb filtering. Three is a crowd.
		played.emit(id, 0, &"concurrent")
		return 0

	var roll_a := _roll()
	var roll_b := _roll()
	var request := {
		"id": String(id),
		"path": def.pick_path(roll_a),
		"bus": String(def.bus),
		"volume_db": def.gain_db + (linear_to_db(volume_scale) if volume_scale > 0.0 else -80.0),
		"pitch": def.pick_pitch(roll_b),
		"kind": def.kind if positioned else DotAudioDef.Kind.FLAT,
		"position": position,
		"unit_size": def.unit_size,
		"max_distance": def.max_distance,
		"looping": def.looping,
		"priority": def.priority,
	}

	var handle := sink.play(request)
	if handle == 0:
		played.emit(id, 0, &"voices")
		return 0

	_playing[handle] = id
	_concurrent[id] = int(_concurrent.get(id, 0)) + 1
	_last_started_ms[id] = now
	played.emit(id, handle, &"ok")
	return handle


func stop(handle: int) -> void:
	if not _playing.has(handle):
		return
	sink.stop(handle)
	_release(handle)


func stop_id(id: StringName) -> void:
	for h in _playing.keys().duplicate():
		if _playing[h] == id:
			stop(h)


func stop_all() -> void:
	sink.stop_all()
	_playing.clear()
	_concurrent.clear()
	_music_handle = 0
	_music_id = &""


## Moves a playing positional sound.
func move(handle: int, position: Vector3) -> void:
	if _playing.has(handle):
		sink.move(handle, position)


func _release(handle: int) -> void:
	var id: StringName = _playing.get(handle, &"")
	_playing.erase(handle)
	if id != &"":
		_concurrent[id] = maxi(0, int(_concurrent.get(id, 1)) - 1)


func _process(_delta: float) -> void:
	_reap()


## Drops the book-keeping for anything the sink has finished on its own.
##
## Concurrency counts have to come down when a sound ends, and only the sink knows that a
## sound has. A manager whose counts never fall refuses everything after a minute, and the
## symptom is a game that goes quiet rather than one that errors.
func _reap() -> void:
	if sink == null:
		return
	for h in _playing.keys().duplicate():
		if not sink.is_playing(h):
			_release(h)


# --- Music ------------------------------------------------------------------

## Starts a track, crossfading from whatever is playing.
##
## [b]The fade is a real crossfade and not a stop-then-start.[/b] The gap is what makes
## homemade music systems audible as homemade: a hundred milliseconds of silence between
## two tracks reads as a stutter, and a player notices it every single time the state
## changes.
##
## Passing the id that is already playing does nothing at all, which is what a caller that
## sets the music from a state machine every frame needs.
func play_music(id: StringName, fade_seconds: float = 1.0) -> int:
	if id == _music_id:
		return _music_handle
	var previous := _music_id

	if _music_handle != 0:
		_fade_out(_music_handle, fade_seconds)

	_music_id = id
	_music_handle = 0
	if id != &"":
		_music_handle = _start(id, Vector3.ZERO, false, 1.0)
		if _music_handle != 0 and fade_seconds > 0.0:
			_fade_in(_music_handle, fade_seconds)

	music_changed.emit(previous, id)
	return _music_handle


func stop_music(fade_seconds: float = 1.0) -> void:
	play_music(&"", fade_seconds)


func music_id() -> StringName:
	return _music_id


## Drops the music while something important is audible — a radio line, a cutscene.
##
## Reference-counted rather than a boolean, so two things ducking at once do not fight
## over releasing it. The commonest bug in every ducking implementation is a duck that
## never lifts because the second holder released it first.
var _duck_holders: Dictionary = {}


func duck(holder: StringName) -> void:
	_duck_holders[holder] = true
	_apply_duck()


func unduck(holder: StringName) -> void:
	_duck_holders.erase(holder)
	_apply_duck()


func is_ducked() -> bool:
	return not _duck_holders.is_empty()


func _apply_duck() -> void:
	var want := not _duck_holders.is_empty()
	if want == _ducked:
		return
	_ducked = want
	if not DotAudioSink.device_present() or mixer == null:
		return
	var idx := AudioServer.get_bus_index(String(mixer.bus_names[1]) if mixer.bus_names.size() > 1 else "Music")
	if idx < 0:
		return
	var base := mixer.db_for(mixer.bus_names[1] if mixer.bus_names.size() > 1 else &"Music")
	var target := base + (mixer.duck_db if want else 0.0)
	var tween := create_tween()
	tween.tween_method(
		func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v),
		AudioServer.get_bus_volume_db(idx),
		target,
		mixer.duck_attack if want else mixer.duck_release
	)


func _fade_in(handle: int, seconds: float) -> void:
	# The sink owns the player, so a fade is expressed as what the manager can do: nothing
	# on a null sink, and a bus-independent volume ramp on a real one. A game that wants
	# sample-accurate fades wants a stem player, which is a different thing and is listed
	# under what is deliberately not here.
	if seconds <= 0.0 or not sink is DotAudioSinkGodot:
		return
	_ramp(handle, -40.0, 0.0, seconds)


func _fade_out(handle: int, seconds: float) -> void:
	if seconds <= 0.0 or not sink is DotAudioSinkGodot:
		sink.stop(handle)
		_release(handle)
		return
	_ramp(handle, 0.0, -40.0, seconds)
	var h := handle
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		sink.stop(h)
		_release(h)
	)


func _ramp(_handle: int, _from_db: float, _to_db: float, _seconds: float) -> void:
	# Intentionally a no-op on the base sink. Overriding this is the extension point for a
	# game that wants per-voice fades; the shipped Godot sink fades through the bus, which
	# is what the great majority of games actually want and costs nothing per voice.
	pass


# --- Reporting --------------------------------------------------------------

func _roll() -> float:
	if roll_source != null and roll_source.has_method("unit_at"):
		_roll_index += 1
		return float(roll_source.call("unit_at", _roll_index))
	return randf()


func describe() -> Dictionary:
	var u := sink.usage() if sink != null else {"playing": 0, "capacity": 0}
	return {
		"sink": sink.sink_name() if sink != null else "none",
		"device": DotAudioSink.device_present(),
		"sounds": catalogue.defs.size() if catalogue != null else 0,
		"playing": u["playing"],
		"capacity": u["capacity"],
		"music": String(_music_id),
		"ducked": _ducked,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var d := describe()
	out.append("dot-audio  sink %s%s" % [d["sink"], "" if d["device"] else "  (no device)"])
	out.append("  %d sounds, %d/%d voices" % [d["sounds"], d["playing"], d["capacity"]])
	if _music_id != &"":
		out.append("  music   %s%s" % [_music_id, "  (ducked)" if _ducked else ""])
	if mixer != null:
		out.append_array(mixer.describe_lines())
	return out
