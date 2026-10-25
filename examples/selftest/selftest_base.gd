extends Node

## The counters, the section/check harness and the manager builder every selftest section uses.

var _passed := 0
var _failed := 0
var _section_count := 0


func _manager(cat: DotAudioCatalogue, voice_count: int = 8) -> DotAudioManager:
	var m := DotAudioManager.new()
	m.catalogue = cat
	m.voices = voice_count
	m.apply_mixer_to_buses = false
	m.register_as_service = false
	m.sink = DotAudioSinkNull.new(voice_count)
	add_child(m)
	m.setup()
	return m



func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)

