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
##
## [b]A game whose player the stand-in cannot move brings a pilot.[/b] Blind W-and-turn walks
## into the first wall and stays there, and a pointer-steered game never hears a key at all,
## so a recording of either is the bots and the bed, and a level trimmed from it is wrong.
## [code]--pilot=res://tools/loudness_pilot.gd[/code] (loudness.sh passes the game's own
## when it has one) is a script with [code]drive(capture, ms) -> bool[/code], called every
## frame; it still plays through the game's own inputs, with [method key], [method turn],
## [method click] and [method point] below, so the sampler, the bindings and the cues are the
## ones a player meets. Returning true replaces the stand-in for that frame. Its
## [code]describe() -> String[/code] is printed as [code]capture pilot:[/code], which is
## where a run says how far the local player went and what it did: a recording with no
## such line is not one of the player.

var _args: Dictionary = {}
var _record: AudioEffectRecord = null
var _phase := 0
var _phase_ms := 0
var _warmup_ms := 4000
var _record_ms := 40000
var _walk := true
var _fire := false
var _held: Dictionary = {}
var _pilot: Object = null
var _camera_at := Vector3.INF
var _camera_travel := 0.0
var _stuck_at := Vector3.INF
var _stuck_ms := 0
var _unstick_frames := 0
var _unstick_dx := 0.0
var _unsticks := 0


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
	var pilot_path := str(_args.get("pilot", ""))
	if not pilot_path.is_empty():
		var script := load(pilot_path) as Script
		if script == null:
			printerr("capture: cannot load the pilot %s" % pilot_path)
		else:
			_pilot = script.new()


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
			_follow_camera()
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


## How far the view went while recording: in every game here the camera rides the local
## player (or its monster, or its truck), so a camera that stayed put is a recording of
## somebody standing still, whatever the stand-in pressed. A jump of over ten units in a
## frame is a respawn or a teleport and is not counted.
func _follow_camera() -> void:
	var at := Vector3.INF
	var cam3 := root.get_camera_3d()
	if cam3 != null:
		at = cam3.global_position
	else:
		var cam2 := root.get_camera_2d()
		if cam2 != null:
			var p := cam2.get_screen_center_position()
			at = Vector3(p.x, 0.0, p.y)
	if at == Vector3.INF:
		return
	if _camera_at != Vector3.INF:
		var step := at.distance_to(_camera_at)
		if step < 10.0 or (cam3 == null and step < 400.0):
			_camera_travel += step
	_camera_at = at


func _move_record_last() -> void:
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) == _record:
			AudioServer.remove_bus_effect(0, i)
			break
	AudioServer.add_bus_effect(0, _record)


# A six-second cycle: four seconds forward (sprinting every third cycle), a jump, then a turn
# standing still. Long enough between turns that a step cadence settles.
func _drive() -> void:
	if _pilot != null and bool(_pilot.call(&"drive", self, Time.get_ticks_msec())):
		return
	if not _walk:
		return
	var t := float(Time.get_ticks_msec() % 6000) / 1000.0
	var cycle := Time.get_ticks_msec() / 6000
	_unstick(t < 4.0)
	key(KEY_W, t < 4.0)
	key(KEY_SHIFT, t < 4.0 and cycle % 3 == 2)
	key(KEY_SPACE, t >= 4.0 and t < 4.15)
	if t >= 4.5 and t < 5.0:
		turn(14.0)
	if _fire:
		click(fmod(t, 1.5) < 0.1)


# [b]Blind, but not stuck.[/b] Holding W into the first wall was most of what the stand-in
# recorded in several games. When the camera (which rides the player) has gone under half a
# metre in 0.6 s of walking, it turns a wide, random amount over the next frames.
func _unstick(walking: bool) -> void:
	if _unstick_frames > 0:
		_unstick_frames -= 1
		turn(_unstick_dx)
		return
	var cam := root.get_camera_3d()
	if cam == null or not walking:
		_stuck_at = Vector3.INF
		return
	var now := Time.get_ticks_msec()
	if _stuck_at == Vector3.INF:
		_stuck_at = cam.global_position
		_stuck_ms = now
		return
	if now - _stuck_ms < 600:
		return
	if Vector2(cam.global_position.x - _stuck_at.x, cam.global_position.z - _stuck_at.z).length() < 0.5:
		_unstick_frames = 12
		_unstick_dx = randf_range(25.0, 60.0) * (1.0 if randf() < 0.5 else -1.0)
		_unsticks += 1
	_stuck_at = cam.global_position
	_stuck_ms = now


# --- What a pilot plays with: the same events a player's hands make ---------------------

## Holds or releases a key; a repeat of the same state sends nothing.
func key(code: Key, down: bool) -> void:
	if bool(_held.get(code, false)) == down:
		return
	_held[code] = down
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


## A relative mouse move, as a captured pointer turning the view sees it.
func turn(dx: float, dy: float = 0.0) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	ev.screen_relative = ev.relative
	Input.parse_input_event(ev)


## Presses or releases a mouse button (left by default); a repeat sends nothing.
func click(down: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	if bool(_held.get(button, false)) == down:
		return
	_held[button] = down
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = down
	ev.position = root.get_mouse_position()
	ev.global_position = ev.position
	Input.parse_input_event(ev)


## Puts the pointer at a point of the window, for a game steered by where it is: the real
## pointer is warped (xvfb has one) and a motion event says so.
func point(at: Vector2) -> void:
	Input.warp_mouse(at)
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
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
	print("capture camera: travelled %.0f %s while recording; the stand-in turned off a wall %d times" % [
		_camera_travel, "units" if root.get_camera_3d() == null else "m", _unsticks])
	if _pilot != null and _pilot.has_method(&"describe"):
		print("capture pilot: %s" % str(_pilot.call(&"describe")))
	print("capture buses: %s" % "; ".join(buses))
	quit(0 if saved == OK else 1)
