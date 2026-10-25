class_name DotAmbienceSet
extends RefCounted

## A sound set: moods read from a directory. `moods.json` is the document; a directory with
## none is read by folder (each subfolder a mood, see [method DotAmbienceMood.from_folder]).
##
## [codeblock]
## {"format": 1, "moods": {"cave_tunnel": {
##   "volume": 1.0,
##   "beds": [{"file": "cave/drone.ogg", "volume": 0.8}],
##   "oneshots": [{"files": ["cave/drip.ogg"], "interval": [20, 60], "volume": 0.5,
##                 "pitch": [0.9, 1.1], "distance": [4, 25]}]}}}
## [/codeblock]

const CHANNEL := "audio.ambience"
const FILE := "moods.json"

## Mood name -> [DotAmbienceMood].
var moods: Dictionary = {}

## Files a mood named and the disk lacked (silence, not an error).
var dropped: PackedStringArray = PackedStringArray()


## Reads [param dir]. The result's value is the set.
static func load_dir(dir: String) -> DotResult:
	var set := DotAmbienceSet.new()
	var file := dir.path_join(FILE)
	if FileAccess.file_exists(file):
		var json := JSON.new()
		var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(file)) == OK else null
		if parsed == null:
			return DotResult.fail(DotError.CODE_PARSE, "%s is not JSON: %s" % [file, json.get_error_message()])
		if not (parsed is Dictionary) or not ((parsed as Dictionary).get("moods", {}) is Dictionary):
			return DotResult.fail(DotError.CODE_PARSE, "%s is not an ambience document" % file)
		var table: Dictionary = (parsed as Dictionary).get("moods", {})
		for id: String in table:
			if table[id] is Dictionary:
				set._add(DotAmbienceMood.from_dictionary(id, table[id], dir, set.dropped))
	elif DirAccess.dir_exists_absolute(dir) or DirAccess.open(dir) != null:
		if OS.has_feature("template"):
			DotLog.warn(CHANNEL, "no moods.json in an exported build; check the preset exports .json (all_resources does in 4.7)", {"dir": dir})
		for sub in DirAccess.get_directories_at(dir):
			set._add(DotAmbienceMood.from_folder(sub, dir.path_join(sub)))
	else:
		return DotResult.fail(DotError.CODE_IO, "no sound set at %s" % dir)
	if not set.dropped.is_empty():
		DotLog.warn(CHANNEL, "a sound set names files it lacks", {"dir": dir, "missing": set.dropped.size(), "first": set.dropped[0]})
	return DotResult.success(set)


func _add(m: DotAmbienceMood) -> void:
	if not m.is_empty():
		moods[m.name] = m


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for k: StringName in moods:
		out.append(String(k))
	out.sort()
	return out
