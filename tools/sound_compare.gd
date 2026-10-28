extends Control

## Ear-check for the stock `slide_*` loops: `godot --path . res://tools/sound_compare.tscn` shows a row per loop
## and a button per speed. With `-- --levels` (headless) it prints each loop's peak and RMS, then quits; exit 1 if a loop is missing.

const SPEEDS: Array[float] = [2.0, 5.0, 9.0, 14.0]
const SECONDS_PER_STEP := 2.5

var _player := AudioStreamPlayer.new()
var _queue: Array = []
var _timer := Timer.new()


func _ready() -> void:
	add_child(_player)
	add_child(_timer)
	_timer.one_shot = true
	_timer.timeout.connect(_next)
	if "--levels" in OS.get_cmdline_user_args():
		get_tree().quit(_print_levels())
		return
	_build_ui()


func _defs() -> Array[DotAudioDef]:
	return DotAudioStock.slide_defs()


## Pitch and linear volume exactly as DotAudioSlide.advance computes them.
static func shape_at(speed: float) -> Vector2:
	var slide := DotAudioSlide.new()
	var t := clampf((speed - slide.quiet_speed) / maxf(slide.full_speed - slide.quiet_speed, 0.01), 0.0, 1.0)
	var pitch := lerpf(1.0 - slide.min_pitch_drop, 1.0, t) + 0.1 * maxf(speed / slide.full_speed - 1.0, 0.0)
	slide.free()
	return Vector2(pitch, t)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var all := Button.new()
	all.text = "Play all (each loop at every speed)"
	all.pressed.connect(_play_all)
	top.add_child(all)
	var stop := Button.new()
	stop.text = "Stop"
	stop.pressed.connect(_stop)
	top.add_child(stop)
	for d in _defs():
		var row := HFlowContainer.new()
		var label := Label.new()
		label.text = String(d.id)
		label.custom_minimum_size.x = 160
		row.add_child(label)
		for sp in SPEEDS:
			var b := Button.new()
			b.text = "%.0f m/s" % sp
			b.pressed.connect(_play.bind(d, sp))
			row.add_child(b)
		box.add_child(row)


func _play(d: DotAudioDef, speed: float) -> void:
	var stream := load(d.path) as AudioStream
	if stream == null:
		push_error("sound_compare: cannot load %s" % d.path)
		return
	var s := shape_at(speed)
	_player.stream = stream
	_player.pitch_scale = s.x
	_player.volume_db = linear_to_db(maxf(s.y, 0.001))
	_player.play()


func _play_all() -> void:
	_queue.clear()
	for d in _defs():
		for sp in SPEEDS:
			_queue.append([d, sp])
	_next()


func _next() -> void:
	if _queue.is_empty():
		_player.stop()
		return
	var item: Array = _queue.pop_front()
	print("%s at %.0f m/s" % [(item[0] as DotAudioDef).id, item[1]])
	_play(item[0], item[1])
	_timer.start(SECONDS_PER_STEP)


func _stop() -> void:
	_queue.clear()
	_timer.stop()
	_player.stop()


## Peak and RMS in dBFS of a loop's file, or an empty dictionary when it cannot be decoded.
func measure(path: String) -> Dictionary:
	var tmp := OS.get_cache_dir().path_join("dot_audio_sound_compare.f32")
	var out: Array = []
	var code := OS.execute("ffmpeg", ["-v", "error", "-y", "-i", ProjectSettings.globalize_path(path),
		"-ac", "1", "-ar", "44100", "-f", "f32le", tmp], out)
	var f := FileAccess.open(tmp, FileAccess.READ)
	if code != 0 or f == null:
		return {}
	var data := f.get_buffer(f.get_length()).to_float32_array()
	f.close()
	DirAccess.remove_absolute(tmp)
	if data.is_empty():
		return {}
	var peak := 0.0
	var sum := 0.0
	for v in data:
		peak = maxf(peak, absf(v))
		sum += v * v
	return {"peak_db": linear_to_db(maxf(peak, 1e-9)), "rms_db": linear_to_db(maxf(sqrt(sum / data.size()), 1e-9)), "seconds": data.size() / 44100.0}


func _print_levels() -> int:
	var bad := 0
	print("%-16s %8s %8s %6s   RMS dBFS at %s m/s" % ["loop", "peak", "rms", "sec", "/".join(SPEEDS.map(func(s: float) -> String: return "%.0f" % s))])
	for d in _defs():
		var m := measure(d.path)
		if m.is_empty():
			print("%-16s MISSING or undecodable: %s" % [d.id, d.path])
			bad += 1
			continue
		var at: PackedStringArray = []
		for sp in SPEEDS:
			at.append("%.1f" % (float(m["rms_db"]) + linear_to_db(maxf(shape_at(sp).y, 0.001))))
		print("%-16s %8.1f %8.1f %6.1f   %s" % [d.id, m["peak_db"], m["rms_db"], m["seconds"], " / ".join(at)])
	return 1 if bad > 0 else 0
