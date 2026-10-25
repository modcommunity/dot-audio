extends Node

## The Ambience bus follows the Effects slider: wind and birdsong are effects to a player.
##
## [codeblock]
## godot --headless --path . res://examples/ambience_bus_selftest.tscn
## [/codeblock]

const CHECKS := 9

var _passed := 0
var _failed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var m := DotAudioMixer.new()
	m.master = 1.0
	m.sfx = 0.5
	m.ambience = 0.8
	var missing := m.apply_to_buses()
	_check(missing.is_empty(), "every bus exists after apply_to_buses")
	var idx := AudioServer.get_bus_index("Ambience")
	_check(idx > 0, "the Ambience bus exists")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(idx), linear_to_db(0.4)),
		"Ambience bus is ambience * Effects (0.8 * 0.5)")

	m.sfx = 1.0
	var _a := m.apply_to_buses()
	_check(is_equal_approx(AudioServer.get_bus_volume_db(idx), linear_to_db(0.8)),
		"raising Effects raises the Ambience bus")

	m.sfx = 0.0
	var _b := m.apply_to_buses()
	_check(AudioServer.is_bus_mute(idx), "Effects at zero silences the Ambience bus")

	m.sfx = 0.5
	m.ambience = 0.0
	var _c := m.apply_to_buses()
	_check(AudioServer.is_bus_mute(idx), "Ambience at zero silences it whatever Effects says")

	m.ambience_follows_sfx = false
	m.ambience = 0.8
	var _d := m.apply_to_buses()
	_check(is_equal_approx(AudioServer.get_bus_volume_db(idx), linear_to_db(0.8)),
		"a mixer that opts out keeps the Ambience slider independent")

	var beds_on_ambience := true
	var found := 0
	for d in DotAudioStock.ambience_defs():
		found += 1
		if d.bus != &"Ambience":
			beds_on_ambience = false
	_check(found > 0 and beds_on_ambience, "every stock bed plays on the Ambience bus")
	_check(m.db_for(&"Ambience") <= 0.0, "db_for reports the Ambience level")

	print("%d passed, %d failed" % [_passed, _failed])
	if _passed + _failed != CHECKS:
		print("ERROR: %d of %d checks ran" % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(0 if _failed == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  " + what)
