class_name DotShotPlayer
extends Node

## Plays a [DotShotDef] as layers: attack, body and the room's tail from the close set, the far set crossfaded in by
## distance, all delayed by the speed of sound, with small pitch and gain jitter and never the same variant twice in a
## row. The tail is a crossfade of the classes by [member enclosure]'s measured room. Call [method fire]; layers are played from [method advance].

const CHANNEL := "audio.shot"

var rules: DotShotRules = DotShotRules.new()
## Optional: its [member DotAudioEnclosure.tail_class] picks the tail; without one the tail is outdoor.
var enclosure: DotAudioEnclosure = null
var manager: DotAudioManager = null
## Pitch varies by plus or minus this fraction, gain by this many dB.
@export_range(0.0, 0.2, 0.001) var pitch_jitter := 0.03
@export_range(0.0, 6.0, 0.1) var gain_jitter_db := 1.5
## Layers lighter than this are not played.
@export_range(0.0, 0.5, 0.01) var floor_weight := 0.03

var _shots: Dictionary = {}
var _last: Dictionary = {}
var _queue: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0


## Seeds the jitter and variant choice, for a reproducible mix.
func seed_rolls(value: int) -> void:
	_rng.seed = value


## Adds [param shot]'s files to the manager's catalogue. The reverb bus is created when an enclosure is set.
func register(shot: DotShotDef) -> DotResult:
	if manager == null or manager.catalogue == null:
		return DotResult.fail(DotError.CODE_STATE, "the shot player has no manager with a catalogue")
	var ok := shot.validate()
	if not ok.ok:
		return ok.wrap("registering shot '%s'" % shot.id)
	var tail_bus := DotAudioEnclosure.BUS if enclosure != null else &"SFX"
	if enclosure != null:
		var made := enclosure.ensure_bus()
		if not made.ok:
			return made
	for d in shot.defs(tail_bus):
		var _added := manager.catalogue.add(d)
	_shots[shot.id] = shot
	return DotResult.success(shot.id)


func has_shot(id: StringName) -> bool:
	return _shots.has(id)


## What [method fire] would play for a shot from [param at] heard at [member DotAudioManager.listener_position]:
## `{layer, def_id, delay, volume, pitch}` per layer. Picks (and so remembers) the variants.
func plan(id: StringName, at: Vector3, suppressed := false, volume_scale := 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var shot: DotShotDef = _shots.get(id)
	if shot == null:
		return out
	var metres := (manager.listener_position if manager != null else Vector3.ZERO).distance_to(at)
	var w := rules.weights(metres)
	var near_w := w.x
	var far_w := w.y
	var in_room := enclosure != null and rules.enclosure
	var tail_w: Dictionary = enclosure.weights() if in_room else {&"outdoor": 1.0}
	var tight := enclosure.tight() if in_room else 0.0
	# A shooter in a tight space hears it louder, with the body lower in the mid range and the tail up against the attack.
	var loud := volume_scale * db_to_linear(DotAudioEnclosure.TIGHT_LOUD_DB * tight)
	var body_pitch := lerpf(1.0, DotAudioEnclosure.TIGHT_BODY_PITCH, tight)
	var tail_gain := 1.0 + DotAudioEnclosure.TIGHT_TAIL_GAIN * tight
	var delay := rules.delay_for(metres)
	var near_layers: Array[Array] = []
	if suppressed and not shot.suppressed_body.is_empty():
		near_layers = [[DotShotDef.SUPPRESSED_BODY, near_w, body_pitch]]
		for cls: StringName in tail_w:
			near_layers.append([StringName("tail_%s" % cls), near_w * 0.35 * float(tail_w[cls]) * tail_gain, 1.0])
	else:
		near_layers = [[DotShotDef.ATTACK, near_w * near_w, 1.0], [DotShotDef.BODY, near_w, body_pitch]]
		for cls: StringName in tail_w:
			near_layers.append([StringName("tail_%s" % cls), near_w * float(tail_w[cls]) * tail_gain, 1.0])
	for entry in near_layers:
		_add(out, shot, entry[0], entry[1], delay, loud, entry[2])
	var far_layer := DotShotDef.SUPPRESSED_FAR if suppressed and not shot.suppressed_far.is_empty() else DotShotDef.FAR
	_add(out, shot, far_layer, far_w, delay, loud)
	return out


## Plays a shot: returns the number of layers started or queued, failing when layers are off or the shot unknown.
func fire(id: StringName, at: Vector3, suppressed := false, volume_scale := 1.0) -> DotResult:
	if not rules.layers:
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "layered shots are off", "snd_shot_layers 0")
	if not _shots.has(id) or manager == null:
		return DotResult.fail(DotError.CODE_INVALID, "unknown shot '%s'" % id)
	var items := plan(id, at, suppressed, volume_scale)
	for item in items:
		item["at"] = at
		if float(item["delay"]) <= 0.001:
			_play(item)
		else:
			item["due"] = _clock + float(item["delay"])
			_queue.append(item)
	return DotResult.success(items.size())


## Plays the layers whose delay is up.
func advance(delta: float) -> void:
	_clock += delta
	var i := 0
	while i < _queue.size():
		if float(_queue[i]["due"]) <= _clock:
			_play(_queue[i])
			_queue.remove_at(i)
		else:
			i += 1


func _process(delta: float) -> void:
	advance(delta)


func queued() -> int:
	return _queue.size()


func describe() -> Dictionary:
	return {"shots": _shots.size(), "queued": _queue.size(), "layers": rules.layers,
			"tail": enclosure.tail_class if enclosure != null else &"outdoor"}


func _add(out: Array[Dictionary], shot: DotShotDef, layer: StringName, weight: float, delay: float, volume_scale: float, pitch_scale := 1.0) -> void:
	var paths := shot.layer(layer)
	if paths.is_empty() or weight < floor_weight:
		return
	var index := _pick(shot.id, layer, paths.size())
	var jitter_db := _rng.randf_range(-gain_jitter_db, gain_jitter_db)
	out.append({
		"layer": layer,
		"def_id": shot.def_id(layer, index),
		"delay": delay,
		"volume": weight * volume_scale * db_to_linear(jitter_db),
		"pitch": pitch_scale * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)),
	})


## A variant index that differs from the last one picked for this layer, when there is a choice.
func _pick(id: StringName, layer: StringName, count: int) -> int:
	if count <= 1:
		return 0
	var key := "%s/%s" % [id, layer]
	var last := int(_last.get(key, -1))
	var index := _rng.randi_range(0, count - 1) if last < 0 else _rng.randi_range(0, count - 2)
	if last >= 0 and index >= last:
		index += 1
	_last[key] = index
	return index


func _play(item: Dictionary) -> void:
	var _handle := manager.play_at(item["def_id"], item["at"], item["volume"], item["pitch"])

