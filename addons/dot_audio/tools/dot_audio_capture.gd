extends SceneTree

## Plays a game for a while and records what it sounds like, for a loudness meter.
##
## [codeblock]
## xvfb-run -a godot --path . --script res://addons/dot_audio/tools/dot_audio_capture.gd \
##     -- --out=/tmp/mix.wav --seconds=40 [--scene=res://main.tscn] [--no-walk] [--fire]
## [/codeblock]
##
## [b]Under xvfb, never headless and never Movie Maker.[/b] Both run the Dummy audio driver,
## where [method DotAudioSink.device_present] is false and dot-audio plays nothing at all, so a
## recording of either is silence that proves nothing. xvfb gives a real driver.
##
## [b]Recorded off the Master bus, after everything on it.[/b] An [AudioEffectRecord] is
## moved to the end of Master's chain when recording starts, because a game's setup adds the
## master limiter later than this script adds anything, and a meter in front of the limiter
## measures a mix nobody hears.
##
## [b]Wall-clock time, not --fixed-fps.[/b] Audio is mixed in real time; a game stepped at a
## fixed rate on a slow software renderer plays its events sparser than they happen, and the
## recording is quieter and emptier than the game.
##
## [b]A stand-in player walks.[/b] Key and mouse events go through [method Input.parse_input_event],
## so every game's own bindings see W, Shift, Space, a mouse turn and (with --fire) a click,
## and footsteps are in the recording. --no-walk records a player standing still.
## `addons/dot_audio/tools/loudness.sh` runs this and measures the result.

var _args: Dictionary = {}
var _record: AudioEffectRecord = null
var _phase := 0
var _phase_ms := 0
var _warmup_ms := 4000
var _record_ms := 40000
var _walk := true
var _fire := false
var _held: Dictionary = {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var eq := arg.find("=")
			if eq > 0:
				_args[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
			else:
				_args[arg.substr(2)] = "1"
	_warmup_ms = int(float(_args.get("warmup", "4")) * 1000.0)
	_record_ms = int(float(_args.get("seconds", "40")) * 1000.0)
	_walk = not _args.has("no-walk")
	_fire = _args.has("fire")


func _process(_delta: float) -> bool:
	match _phase:
		0:
			# Built here rather than in _initialize: before the root viewport is live a player
			# is not inside the tree and silently refuses to play.
			_record = AudioEffectRecord.new()
			AudioServer.add_bus_effect(0, _record)
			var scene := str(_args.get("scene", ProjectSettings.get_setting("application/run/main_scene", "")))
			var err := change_scene_to_file(scene)
			if err != OK:
				printerr("capture: cannot open %s (%s)" % [scene, error_string(err)])
				quit(2)
				return true
			_next(1)
		1:
			_drive()
			if _elapsed() >= _warmup_ms:
				_move_record_last()
				_record.set_recording_active(true)
				_next(2)
		2:
			_drive()
			if _elapsed() >= _record_ms:
				_record.set_recording_active(false)
				_finish()
				_next(3)
				return true
	return false


func _next(phase: int) -> void:
	_phase = phase
	_phase_ms = Time.get_ticks_msec()


func _elapsed() -> int:
	return Time.get_ticks_msec() - _phase_ms


func _move_record_last() -> void:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _record:
			AudioServer.remove_bus_effect(0, i)
			break
	AudioServer.add_bus_effect(0, _record)


# A six-second cycle: four seconds forward (sprinting every third cycle), a jump, then a turn
# standing still. Long enough between turns that a step cadence settles.
func _drive() -> void:
	if not _walk:
		return
	var t := float(Time.get_ticks_msec() % 6000) / 1000.0
	var cycle := Time.get_ticks_msec() / 6000
	_key(KEY_W, t < 4.0)
	_key(KEY_SHIFT, t < 4.0 and cycle % 3 == 2)
	_key(KEY_SPACE, t >= 4.0 and t < 4.15)
	if t >= 4.5 and t < 5.0:
		var turn := InputEventMouseMotion.new()
		turn.relative = Vector2(14.0, 0.0)
		turn.screen_relative = turn.relative
		Input.parse_input_event(turn)
	if _fire:
		var down := fmod(t, 1.5) < 0.1
		if bool(_held.get(MOUSE_BUTTON_LEFT, false)) != down:
			_held[MOUSE_BUTTON_LEFT] = down
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = down
			Input.parse_input_event(click)


func _key(code: Key, down: bool) -> void:
	if bool(_held.get(code, false)) == down:
		return
	_held[code] = down
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _finish() -> void:
	var out := str(_args.get("out", "user://dot_audio_capture.wav"))
	var wav := _record.get_recording()
	var saved := wav.save_to_wav(out) if wav != null else ERR_UNAVAILABLE
	var buses := PackedStringArray()
	for b in AudioServer.bus_count:
		var fx := PackedStringArray()
		for i in AudioServer.get_bus_effect_count(b):
			var e := AudioServer.get_bus_effect(b, i)
			if e != _record:
				fx.append(e.get_class().trim_prefix("AudioEffect"))
		buses.append("%s %.1f dB%s" % [
			AudioServer.get_bus_name(b), AudioServer.get_bus_volume_db(b),
			" [%s]" % ", ".join(fx) if not fx.is_empty() else "",
		])
	print("capture driver=%s saved=%s" % [AudioServer.get_driver_name(), error_string(saved)])
	print("capture buses: %s" % "; ".join(buses))
	quit(0 if saved == OK else 1)
