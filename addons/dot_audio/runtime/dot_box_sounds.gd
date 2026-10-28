class_name DotBoxSounds
extends RefCounted

## Per-event sounds for a box (spawn, approach, open, reward, deny, effect end).
## A `sounds` profile key maps an event to a slot `{sound, volume, pitch_jitter, max_distance, unit_size, mode, enabled}`;
## an empty slot plays the stock sound. Every fired event emits [signal event_fired], heard or not.

const EVENTS: Array[StringName] = [&"spawn", &"approach", &"open", &"reward", &"deny", &"effect_end"]
const MODES: Array[String] = ["3d", "ui"]
const STOCK_PREFIX := "boxev_"
const AUDIO_EXTENSIONS: Array[String] = [".ogg", ".wav", ".mp3"]

## [param sound_id] is "" when nothing played (no manager, a silent slot, out of range).
signal event_fired(box_id: StringName, event: StringName, position: Vector3, sound_id: StringName, handle: int)

var manager: DotAudioManager = null
var _slots: Dictionary = {}
var _installed: Dictionary = {}
var _ended: Dictionary = {}
var _near: Dictionary = {}
var _rng := RandomNumberGenerator.new()


static func stock_id(event: StringName) -> StringName:
	return StringName(STOCK_PREFIX + String(event))


## The six stock sounds, generated (no files), one per event.
static func stock_defs() -> Array[DotAudioDef]:
	var out: Array[DotAudioDef] = []
	for event in EVENTS:
		var d := DotAudioDef.new()
		d.id = stock_id(event)
		d.generated = true
		d.bus = &"SFX"
		d.kind = DotAudioDef.Kind.POSITIONAL_3D
		d.max_concurrent = 4
		d.unit_size = 8.0
		d.max_distance = 60.0
		d.gain_db = -4.0 if event == &"spawn" or event == &"approach" else 0.0
		out.append(d)
	return out


## Stock id to [enum DotAudioSynth.Voice], for a game's synthesised bank.
static func stock_recipes() -> Dictionary:
	return {
		stock_id(&"spawn"): DotAudioSynth.Voice.SPAWN,
		stock_id(&"approach"): DotAudioSynth.Voice.BLIP,
		stock_id(&"open"): DotAudioSynth.Voice.CLICK,
		stock_id(&"reward"): DotAudioSynth.Voice.PICKUP,
		stock_id(&"deny"): DotAudioSynth.Voice.DENY,
		stock_id(&"effect_end"): DotAudioSynth.Voice.IMPACT,
	}


## A slot with every key present and clamped. An empty `sound` means the stock sound.
static func normalise_slot(slot: Variant, event: StringName = &"") -> Dictionary:
	var s: Dictionary = slot if slot is Dictionary else {}
	# The end of an effect is news for everyone, wherever the box was, so it defaults to flat.
	var mode := str(s.get("mode", "ui" if event == &"effect_end" else "3d"))
	return {
		"sound": str(s.get("sound", "")),
		"volume": clampf(float(s.get("volume", 1.0)), 0.0, 4.0),
		"pitch_jitter": clampf(float(s.get("pitch_jitter", 0.0)), 0.0, 0.5),
		"max_distance": clampf(float(s.get("max_distance", 60.0)), 1.0, 10000.0),
		"unit_size": clampf(float(s.get("unit_size", 8.0)), 0.1, 1000.0),
		"mode": mode if mode in MODES else "3d",
		"enabled": bool(s.get("enabled", true)),
	}


static func is_asset(sound: String) -> bool:
	if sound.contains("://") or sound.begins_with("/"):
		return true
	var low := sound.to_lower()
	for ext in AUDIO_EXTENSIONS:
		if low.ends_with(ext):
			return true
	return false


## Adds the stock defs to [param catalogue] and returns their synth recipes.
func install(catalogue: DotAudioCatalogue) -> Dictionary:
	for d in stock_defs():
		if catalogue.find(d.id) == null:
			catalogue.add(d)
	return stock_recipes()


## Sets the sounds of one box type; returns the synth recipes of any slot def added, for a game that bakes a bank.
func set_slots(box_id: StringName, sounds: Dictionary) -> Dictionary:
	var norm := {}
	for event in EVENTS:
		norm[event] = normalise_slot(sounds.get(String(event), sounds.get(event, {})), event)
	_slots[box_id] = norm
	return _define(box_id)


func has_box(box_id: StringName) -> bool:
	return _slots.has(box_id)


## The slot of [param event] with its defaults, for a box with none set too.
func slot_of(box_id: StringName, event: StringName) -> Dictionary:
	return (_slots.get(box_id, {}) as Dictionary).get(event, normalise_slot({}, event))


## The id that would play for a slot: its own def, or the stock one.
func sound_id_of(box_id: StringName, event: StringName) -> StringName:
	var slot := slot_of(box_id, event)
	if not bool(slot["enabled"]):
		return &""
	return StringName("boxslot_%s_%s" % [box_id, event])


func _define(box_id: StringName) -> Dictionary:
	var recipes := {}
	if manager == null or manager.catalogue == null:
		return recipes
	var cat := manager.catalogue
	var stock := stock_recipes()
	for event in EVENTS:
		var slot := slot_of(box_id, event)
		var sound := str(slot["sound"])
		var source_id := stock_id(event) if sound == "" else StringName(sound)
		var id := StringName("boxslot_%s_%s" % [box_id, event])
		var def: DotAudioDef = null
		if is_asset(sound):
			def = DotAudioDef.new()
			def.path = sound
		else:
			var base := cat.find(source_id)
			if base == null:
				base = cat.find(stock_id(event))
				source_id = stock_id(event)
			if base == null:
				continue
			def = base.duplicate() as DotAudioDef
			if stock.has(source_id):
				recipes[id] = stock[source_id]
		def.id = id
		def.kind = DotAudioDef.Kind.FLAT if slot["mode"] == "ui" else DotAudioDef.Kind.POSITIONAL_3D
		if slot["mode"] == "ui":
			def.bus = &"UI"
		def.max_distance = float(slot["max_distance"])
		def.unit_size = float(slot["unit_size"])
		def.max_concurrent = 4
		def.generated = def.generated or def.path == ""
		cat.add(def)
		_installed[id] = true
	return recipes


## Fires [param event] of [param box_id]. Returns the playing handle, 0 when nothing played; the signal fires regardless.
func fire(box_id: StringName, event: StringName, position: Vector3 = Vector3.ZERO) -> int:
	var slot := slot_of(box_id, event)
	var id := sound_id_of(box_id, event)
	var handle := 0
	if manager != null and id != &"" and _installed.has(id):
		var pitch := 1.0 + _rng.randf_range(-1.0, 1.0) * float(slot["pitch_jitter"])
		if slot["mode"] == "ui":
			handle = manager.play(id, float(slot["volume"]), pitch)
		else:
			handle = manager.play_at(id, position, float(slot["volume"]), pitch)
	event_fired.emit(box_id, event, position, id, handle)
	return handle


## The end of a timed effect, once per [param effect_key]: a second call for the same key does nothing and returns false.
func effect_end(box_id: StringName, effect_key: Variant, position: Vector3 = Vector3.ZERO) -> bool:
	var k := "%s/%s" % [box_id, str(effect_key)]
	if _ended.has(k):
		return false
	_ended[k] = true
	var _h := fire(box_id, &"effect_end", position)
	return true


## A listener at [param distance] from a box: fires `approach` once on entering [param radius], again only after leaving 25% beyond it.
func approach(box_id: StringName, key: Variant, distance: float, radius: float, position: Vector3 = Vector3.ZERO) -> bool:
	var k := "%s/%s" % [box_id, str(key)]
	if distance <= radius:
		if _near.get(k, false):
			return false
		_near[k] = true
		var _h := fire(box_id, &"approach", position)
		return true
	if distance > radius * 1.25:
		_near.erase(k)
	return false


## Forgets what ended and who was near, for a new map.
func reset() -> void:
	_ended.clear()
	_near.clear()
