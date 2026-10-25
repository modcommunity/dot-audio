class_name DotAmbienceMood
extends RefCounted

## One mood: looping beds that play together, and one-shots that come at random.
##
## A bed is [code]{file, volume}[/code]. A one-shot is [code]{files, interval: [min, max],
## volume, pitch: [min, max], distance: [min, max]}[/code]: one file of [code]files[/code] is
## heard every [code]interval[/code] seconds (divided by the frequency setting), from a random
## direction and distance. Paths are absolute by the time a mood is used.

var name: StringName = &""
var volume: float = 1.0
var beds: Array[Dictionary] = []
var oneshots: Array[Dictionary] = []
## Catalogue ids of the beds and one-shots, built once by [method assign_ids] so playing never formats a string.
var bed_ids: Array[StringName] = []
var shot_ids: Array[StringName] = []
var _ids_key := ""


## A mood from its JSON form; [param base] is prepended to every relative file. Entries whose
## files are all missing are dropped and named in [param dropped].
static func from_dictionary(id: String, doc: Dictionary, base: String, dropped: PackedStringArray) -> DotAmbienceMood:
	var m := DotAmbienceMood.new()
	m.name = StringName(id)
	m.volume = clampf(float(doc.get("volume", 1.0)), 0.0, 2.0)
	for raw: Variant in doc.get("beds", []):
		if not (raw is Dictionary):
			continue
		var path := _join(base, str((raw as Dictionary).get("file", "")))
		if not _exists(path):
			dropped.append(path)
			continue
		m.beds.append({"file": path, "volume": clampf(float((raw as Dictionary).get("volume", 1.0)), 0.0, 2.0)})
	for raw: Variant in doc.get("oneshots", []):
		if not (raw is Dictionary):
			continue
		var d := raw as Dictionary
		var raw_files: Variant = d.get("files", d.get("file", ""))
		var names: Array = raw_files if raw_files is Array else [raw_files]
		var files := PackedStringArray()
		for n: Variant in names:
			var path := _join(base, str(n))
			if _exists(path):
				files.append(path)
			else:
				dropped.append(path)
		if files.is_empty():
			continue
		var interval := _pair(d.get("interval", [30.0, 90.0]), 30.0, 90.0)
		var dist := _pair(d.get("distance", [6.0, 30.0]), 6.0, 30.0)
		var pitch := _pair(d.get("pitch", [0.95, 1.05]), 0.95, 1.05)
		m.oneshots.append({
			"files": files, "min_interval": maxf(interval.x, 1.0), "max_interval": maxf(interval.y, interval.x),
			"volume": clampf(float(d.get("volume", 0.6)), 0.0, 2.0),
			"min_distance": maxf(dist.x, 0.5), "max_distance": maxf(dist.y, dist.x),
			"min_pitch": pitch.x, "max_pitch": maxf(pitch.y, pitch.x),
		})
	return m


## A mood from a directory of files by naming: names starting `bed` or `loop` are beds, the
## rest one-shots at the default cadence.
static func from_folder(id: String, dir: String) -> DotAmbienceMood:
	var m := DotAmbienceMood.new()
	m.name = StringName(id)
	var shots := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		var file := f.trim_suffix(".import").trim_suffix(".remap")
		if not (file.get_extension().to_lower() in ["ogg", "wav", "mp3"]):
			continue
		var stem := file.get_basename().to_lower()
		var path := dir.path_join(file)
		if stem.begins_with("bed") or stem.begins_with("loop"):
			if not m.beds.any(func(b: Dictionary) -> bool: return b["file"] == path):
				m.beds.append({"file": path, "volume": 1.0})
		elif not path in shots:
			shots.append(path)
	if not shots.is_empty():
		m.oneshots.append({
			"files": shots, "min_interval": 30.0, "max_interval": 90.0, "volume": 0.6,
			"min_distance": 6.0, "max_distance": 30.0, "min_pitch": 0.95, "max_pitch": 1.05,
		})
	return m


## A copy of this mood named [param new_name] whose one-shots also include [param other]'s: a map that
## wants a few sounds from a second mood.
func with_oneshots_of(other: DotAmbienceMood, new_name: StringName) -> DotAmbienceMood:
	var m := DotAmbienceMood.new()
	m.name = new_name
	m.volume = volume
	m.beds = beds.duplicate()
	m.oneshots = oneshots.duplicate()
	m.oneshots.append_array(other.oneshots)
	return m


## Names the beds and one-shots [code]prefix + mood/bedN[/code]; a repeat call with the same arguments does nothing.
func assign_ids(prefix: String, mood_id: StringName) -> void:
	var key := prefix + String(mood_id)
	if key == _ids_key:
		return
	_ids_key = key
	bed_ids.clear()
	shot_ids.clear()
	for i in beds.size():
		bed_ids.append(StringName("%s/bed%d" % [key, i]))
	for i in oneshots.size():
		shot_ids.append(StringName("%s/shot%d" % [key, i]))


func is_empty() -> bool:
	return beds.is_empty() and oneshots.is_empty()


static func _join(base: String, file: String) -> String:
	if file == "" or file.contains("://") or file.is_absolute_path():
		return file
	return base.path_join(file)


static func _pair(v: Variant, a: float, b: float) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float((v as Array)[0]), float((v as Array)[1]))
	return Vector2(a, b)


# An exported game ships the .import marker, not the source file.
static func _exists(path: String) -> bool:
	return path != "" and (FileAccess.file_exists(path) or FileAccess.file_exists(path + ".import") or ResourceLoader.exists(path))
