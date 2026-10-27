extends "selftest/selftest_base.gd"

## DotBoxSounds: every slot plays, stock fallback, effect end once, approach edge, silent slot, asset slot, signal.

const SECTIONS := 5
const CHECKS := 23

var _events: Array = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var cat := DotAudioCatalogue.new()
	var m := _manager(cat, 16)
	var bs := DotBoxSounds.new()
	bs.manager = m
	var recipes := bs.install(cat)
	bs.event_fired.connect(func(b: StringName, e: StringName, _p: Vector3, s: StringName, h: int) -> void: _events.append([b, e, s, h]))
	var sink := m.sink as DotAudioSinkNull

	_section("The stock set")
	_check(recipes.size() == DotBoxSounds.EVENTS.size() and cat.validate().ok, "a stock sound per event, a valid catalogue")
	var _r := bs.set_slots(&"plain", {})
	for e in DotBoxSounds.EVENTS:
		var h := bs.fire(&"plain", e, Vector3(1, 0, 1))
		_check(h != 0, "empty slot %s plays the stock sound" % e)
	_check(_events.size() == 6, "one signal per event (%d)" % _events.size())

	_section("Slots")
	var _r2 := bs.set_slots(&"loud", {"open": {"sound": "res://x/open.ogg", "volume": 2.0, "mode": "ui"}, "deny": {"enabled": false}, "reward": {"sound": "boxev_deny", "pitch_jitter": 0.2}})
	var s := bs.slot_of(&"loud", &"open")
	_check(s["volume"] == 2.0 and s["mode"] == "ui", "a slot keeps its volume and mode")
	_events.clear()
	_check(bs.fire(&"loud", &"deny") == 0 and _events.size() == 1 and _events[0][2] == &"", "a disabled slot is silent and still signals")
	_check(bs.fire(&"loud", &"reward", Vector3.ZERO) != 0, "a slot naming a stock id plays it")
	_check(sink.count_of(&"boxslot_loud_reward") == 1, "through its own def")
	_check(DotBoxSounds.is_asset("res://a.ogg") and DotBoxSounds.is_asset("pack/x.wav") and not DotBoxSounds.is_asset("boxev_deny"), "an asset path is told from an id")
	_check(bs.slot_of(&"nope", &"open")["sound"] == "", "an unknown box reads as stock")

	_section("Distance")
	m.listener_position = Vector3(500, 0, 0)
	var _r3 := bs.set_slots(&"far", {"spawn": {"max_distance": 10.0}})
	_check(bs.fire(&"far", &"spawn", Vector3.ZERO) == 0, "a 3D slot beyond its max_distance is culled")
	var _r4 := bs.set_slots(&"far", {"spawn": {"max_distance": 10.0, "mode": "ui"}})
	_check(bs.fire(&"far", &"spawn", Vector3.ZERO) != 0, "a UI slot is flat and always heard")

	_section("Effect end fires exactly once")
	_events.clear()
	_check(bs.effect_end(&"plain", 7) and not bs.effect_end(&"plain", 7), "the second end of one effect is refused")
	var ends := _events.filter(func(e: Array) -> bool: return e[1] == &"effect_end")
	_check(ends.size() == 1 and sink.count_of(&"boxslot_plain_effect_end") == 2, "one signal and one more sound (the first was section 1's)")
	_check(bs.effect_end(&"plain", 8), "another effect ends on its own")
	bs.reset()
	_check(bs.effect_end(&"plain", 7), "reset forgets (a new map)")

	_section("Approach")
	_events.clear()
	_check(bs.approach(&"plain", 1, 3.0, 5.0) and not bs.approach(&"plain", 1, 2.0, 5.0), "approach fires once while inside")
	var _x := bs.approach(&"plain", 1, 6.0, 5.0)
	_check(not bs.approach(&"plain", 1, 4.0, 5.0), "jitter at the edge does not refire")
	var _y := bs.approach(&"plain", 1, 9.0, 5.0)
	_check(bs.approach(&"plain", 1, 4.0, 5.0), "and it fires again after leaving")

	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])
	var bad := _failed > 0 or _section_count != SECTIONS or _passed + _failed != CHECKS
	if bad:
		_line("ERROR: expected %d sections %d checks" % [SECTIONS, CHECKS])
	get_tree().quit(1 if bad else 0)
