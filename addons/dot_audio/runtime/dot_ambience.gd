class_name DotAmbience
extends Node

## A creepy-ambience layer: a mood is a set of looping beds plus sparse random one-shots, and the
## layer crossfades when the mood changes. Quiet by default; it never starts music-like.
##
## [codeblock]
## var amb := DotAmbience.new()
## amb.manager = audio_manager
## add_child(amb)
## amb.add_set_dir("res://sounds/ambience")     # moods.json and its files
## amb.set_mood(&"cave_tunnel")                 # on every map load
## amb.duck(&"fight", 0.3)                      # quieter while something is happening
## [/codeblock]
##
## [b]Driven by [method advance].[/b] [method _process] only calls it, so a test steps time without
## frames. [b]Placed through the manager[/b], so the pool, the cull and the null sink all apply.
## [b]Settings are live:[/b] [member config] is read each step, nothing needs a reload.

const CHANNEL := "audio.ambience"
const ID_PREFIX := "ambience/"
const RETRY_SECONDS := 2.0

signal mood_changed(from_id: StringName, to_id: StringName)
signal oneshot_played(mood_id: StringName, file: String, position: Vector3)

var manager: DotAudioManager = null
var config: DotAmbienceConfig = DotAmbienceConfig.new()

## Whose position the one-shots are placed round. Empty uses the manager's listener_position.
var listener: Node3D = null

## Mood played when the game asks for none, or for one that is not allowed.
var default_mood: StringName = &""

## Bus the layer plays on.
var bus: StringName = &"Ambience"

## Mood that plays while [method set_indoors] is true; empty keeps the requested mood indoors too.
var indoor_mood: StringName = &""

var _moods: Dictionary = {}
var _indoors := false
var _requested: StringName = &""
var _current: StringName = &""
var _rng := RandomNumberGenerator.new()
# Bed voices: handle -> {id, gain, target, volume}.
var _voices: Dictionary = {}
var _timers: Array[Dictionary] = []
var _level := 0.0
var _clock := 0.0
var _holders := {"pause": {}, "duck": {}, "hush": {}}
var _played := 0
var _last_shot := {}
var _registered := {}
# When a mood whose beds all failed to start may try again, so a missing catalogue is not retried every frame.
var _retry_at := 0.0


func _init() -> void:
	_rng.randomize()


## Fixes the random stream, for a reproducible run.
func seed_random(value: int) -> void:
	_rng.seed = value


## Adds the moods of [param dir]; a mood of the same name replaces the earlier one.
func add_set_dir(dir: String) -> DotResult:
	var loaded := DotAmbienceSet.load_dir(dir)
	if not loaded.ok:
		return loaded.wrap("ambience set")
	var set: DotAmbienceSet = loaded.value
	for id: StringName in set.moods:
		add_mood(set.moods[id])
	return DotResult.success(set.moods.size())


func add_mood(m: DotAmbienceMood) -> void:
	_moods[m.name] = m
	_registered.erase(m.name)
	if m.name == _current:
		_start_mood(m.name)


## Reads [member DotAmbienceConfig.sound_dir] (the owner's own sounds) over the built-in moods.
func load_custom() -> DotResult:
	if config.sound_dir == "":
		return DotResult.success(0)
	return add_set_dir(config.sound_dir)


## The mood named [param id], or null.
func mood_def(id: StringName) -> DotAmbienceMood:
	return _moods.get(id) as DotAmbienceMood


## Tells the layer the listener is under a roof (see [DotAmbienceRoof]); it crosses over to
## [member indoor_mood] at the config's crossfade, and back. Ignored when [member DotAmbienceConfig.follow_indoors] is off.
func set_indoors(inside: bool) -> void:
	_indoors = inside


func indoors() -> bool:
	return _indoors


func mood_names() -> PackedStringArray:
	var out := PackedStringArray()
	for k: StringName in _moods:
		out.append(String(k))
	out.sort()
	return out


## What the game wants playing. Refused (state unchanged) for an unknown mood; the config can still
## put another in its place ([method effective_mood]).
func set_mood(id: StringName) -> DotResult:
	if id != &"" and not _moods.has(id):
		return DotResult.fail(DotError.CODE_INVALID, "no ambience mood '%s'" % id)
	_requested = id
	_apply_mood()
	return DotResult.success(effective_mood())


## The mood the config lets play: its override, else the request if allowed, else the default.
func effective_mood() -> StringName:
	var forced := StringName(config.mood)
	if forced != &"" and _moods.has(forced):
		return forced
	var allowed := config.allowed()
	if _indoors and config.follow_indoors and indoor_mood != &"" and _moods.has(indoor_mood) and (allowed.is_empty() or String(indoor_mood) in allowed):
		return indoor_mood
	if _requested != &"" and (allowed.is_empty() or String(_requested) in allowed):
		return _requested
	if default_mood != &"" and _moods.has(default_mood) and (allowed.is_empty() or String(default_mood) in allowed):
		return default_mood
	for a in allowed:
		if _moods.has(StringName(a)):
			return StringName(a)
	return &""


func mood() -> StringName:
	return _current


## Everything fades out and one-shots stop while any holder pauses. Reference-counted per holder.
func pause(holder: StringName) -> void:
	_holders["pause"][holder] = 0.0


func resume(holder: StringName) -> void:
	_holders["pause"].erase(holder)


## Beds drop to [param scale] of their level while any holder ducks (the lowest scale wins); one-shots
## are hushed below 0.35.
func duck(holder: StringName, scale: float = 0.3) -> void:
	_holders["duck"][holder] = clampf(scale, 0.0, 1.0)


func unduck(holder: StringName) -> void:
	_holders["duck"].erase(holder)


## No new one-shot starts while any holder hushes; beds carry on.
func hush(holder: StringName) -> void:
	_holders["hush"][holder] = 0.0


func unhush(holder: StringName) -> void:
	_holders["hush"].erase(holder)


## The level beds are heading for: config volume times the duck, zero if off or paused.
func target_level() -> float:
	if not config.enabled or not _holders["pause"].is_empty():
		return 0.0
	var scale := 1.0
	for s: float in _holders["duck"].values():
		scale = minf(scale, s)
	return config.volume * scale


func _exit_tree() -> void:
	if manager != null and is_instance_valid(manager):
		for h: int in _voices.keys():
			manager.stop(h)
	_voices.clear()
	_timers.clear()


func _process(delta: float) -> void:
	advance(delta)


## Steps the layer by [param delta] seconds.
func advance(delta: float) -> void:
	if manager == null:
		manager = DotRegistry.get_node_service(DotAudioManager.SERVICE) as DotAudioManager
		if manager == null:
			return
	_clock += delta
	_apply_mood()
	var want := target_level()
	_level = move_toward(_level, want, delta * 0.5) if want < _level else move_toward(_level, want, delta * 0.25)
	_ease(delta)
	if _current != &"" and want > 0.0 and _holders["hush"].is_empty() and _duck_scale() >= 0.35:
		_tick_oneshots()


func _duck_scale() -> float:
	var scale := 1.0
	for s: float in _holders["duck"].values():
		scale = minf(scale, s)
	return scale


func _apply_mood() -> void:
	var want := effective_mood()
	if want == _current:
		if _current != &"" and manager != null and _voices.is_empty() and not _moods[_current].beds.is_empty() and _clock >= _retry_at:
			_retry_at = _clock + RETRY_SECONDS
			_start_mood(_current, true)
		return
	var from := _current
	_current = want
	for h: int in _voices.keys():
		_voices[h]["target"] = 0.0
	if want != &"":
		_start_mood(want)
	else:
		_timers.clear()
	mood_changed.emit(from, want)
	DotLog.debug(CHANNEL, "ambience mood", {"from": String(from), "to": String(want)})


func _start_mood(id: StringName, retry: bool = false) -> void:
	if manager == null or not _moods.has(id):
		return
	_register(id)
	var m: DotAmbienceMood = _moods[id]
	m.assign_ids(ID_PREFIX, id)
	var fade := config.crossfade_seconds
	var i := 0
	for bed: Dictionary in m.beds:
		var def_id := m.bed_ids[i]
		i += 1
		if _has_live_voice(def_id):
			continue
		var h := manager.play(def_id, 0.001)
		if h != 0:
			_voices[h] = {"id": def_id, "gain": 0.0 if fade > 0.0 else 1.0, "target": 1.0, "volume": float(bed["volume"]) * m.volume}
	if retry and not _timers.is_empty():
		return
	_timers.clear()
	i = 0
	for shot: Dictionary in m.oneshots:
		_timers.append({"index": i, "next": _clock + _rng.randf_range(float(shot["min_interval"]) * 0.5, float(shot["max_interval"]))})
		i += 1


func _has_live_voice(def_id: StringName) -> bool:
	for h: int in _voices.keys():
		if _voices[h]["id"] == def_id and float(_voices[h]["target"]) > 0.0:
			return true
	return false


# Defs are made once per mood, so a custom set that replaces a mood gets fresh ones.
func _register(id: StringName) -> void:
	if _registered.has(id) or manager == null or manager.catalogue == null:
		return
	_registered[id] = true
	var m: DotAmbienceMood = _moods[id]
	m.assign_ids(ID_PREFIX, id)
	var cat := manager.catalogue
	var i := 0
	for bed: Dictionary in m.beds:
		var d := DotAudioDef.new()
		d.id = m.bed_ids[i]
		d.path = bed["file"]
		d.kind = DotAudioDef.Kind.FLAT
		d.bus = bus
		d.looping = true
		d.priority = 90
		d.max_concurrent = 2
		d.max_distance = 0.0
		d.tags = [&"ambience_mood"]
		_replace(cat, d)
		i += 1
	i = 0
	for shot: Dictionary in m.oneshots:
		var d := DotAudioDef.new()
		d.id = m.shot_ids[i]
		d.path = (shot["files"] as PackedStringArray)[0]
		d.variants = shot["files"]
		d.kind = DotAudioDef.Kind.POSITIONAL_3D
		d.bus = bus
		d.priority = 25
		d.max_concurrent = 2
		d.unit_size = 8.0
		d.max_distance = float(shot["max_distance"]) * 2.0 + 10.0
		d.tags = [&"ambience_mood"]
		_replace(cat, d)
		i += 1


static func _replace(cat: DotAudioCatalogue, d: DotAudioDef) -> void:
	if cat.has(d.id):
		var old := cat.find(d.id)
		old.path = d.path
		old.variants = d.variants
	else:
		cat.add(d)


func _tick_oneshots() -> void:
	var m: DotAmbienceMood = _moods[_current]
	for t: Dictionary in _timers:
		if _clock < float(t["next"]):
			continue
		var shot: Dictionary = m.oneshots[int(t["index"])]
		var freq := config.frequency
		if freq <= 0.0:
			t["next"] = _clock + 10.0
			continue
		t["next"] = _clock + _rng.randf_range(float(shot["min_interval"]), float(shot["max_interval"])) / freq
		_play_shot(m, int(t["index"]), shot)


func _play_shot(m: DotAmbienceMood, index: int, shot: Dictionary) -> void:
	var at := manager.listener_position
	if listener != null and is_instance_valid(listener) and listener.is_inside_tree():
		at = listener.global_position
	var angle := _rng.randf() * TAU
	var dist := _rng.randf_range(float(shot["min_distance"]), float(shot["max_distance"]))
	var pos := at + Vector3(cos(angle), 0.0, sin(angle)) * dist
	var vol := float(shot["volume"]) * m.volume * maxf(_level, 0.0) * 2.0
	var h := manager.play_at(m.shot_ids[index], pos, vol,
		_rng.randf_range(float(shot["min_pitch"]), float(shot["max_pitch"])))
	if h == 0:
		return
	_played += 1
	var files: PackedStringArray = shot["files"]
	_last_shot = {"mood": String(m.name), "index": index, "distance": snappedf(dist, 0.1), "at": snappedf(_clock, 0.1)}
	oneshot_played.emit(m.name, files[0], pos)
	DotLog.trace(CHANNEL, "ambience one-shot", _last_shot)


func _ease(delta: float) -> void:
	if _voices.is_empty() or manager == null:
		return
	var step := delta / maxf(config.crossfade_seconds, 0.05)
	for h: int in _voices.keys():
		var v: Dictionary = _voices[h]
		var g := move_toward(float(v["gain"]), float(v["target"]), step)
		v["gain"] = g
		if g <= 0.0 and float(v["target"]) <= 0.0:
			manager.stop(h)
			_voices.erase(h)
			continue
		# Equal power, so a crossfade does not dip in the middle. The Ambience bus has its own slider.
		var scale := sin(g * PI * 0.5) * float(v["volume"]) * _level * 2.0
		if not manager.shape(h, maxf(scale, 0.0005)):
			_voices.erase(h)


func describe() -> Dictionary:
	var shots := []
	for t: Dictionary in _timers:
		shots.append(snappedf(float(t["next"]) - _clock, 0.1))
	return {
		"enabled": config.enabled, "mood": String(_current), "requested": String(_requested),
		"override": config.mood, "indoors": _indoors, "indoor_mood": String(indoor_mood), "allowed": config.allowed_moods, "moods": mood_names(),
		"volume": config.volume, "level": snappedf(_level, 0.001), "frequency": config.frequency,
		"beds": _voices.size(), "paused": _holders["pause"].keys(), "ducked": _holders["duck"].keys(),
		"hushed": _holders["hush"].keys(), "oneshots_played": _played, "next_oneshot_in": shots, "last": _last_shot,
	}


func describe_lines() -> PackedStringArray:
	var d := describe()
	return PackedStringArray([
		"dot-audio ambience  %s%s, %d beds, level %s (volume %s, frequency %s), %d one-shots heard, next in %s" % [
			d["mood"] if d["mood"] != "" else "-", " (override)" if config.mood != "" else "", d["beds"],
			d["level"], d["volume"], d["frequency"], d["oneshots_played"], d["next_oneshot_in"]],
	])
