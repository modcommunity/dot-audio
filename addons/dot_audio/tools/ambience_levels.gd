extends SceneTree

## Headless level table for the Ambience bus at a game's defaults: every stock bed through
## [DotAudioAmbience], every stock mood through [DotAmbience], each with the mixer's slider.
##
## [codeblock]
## godot --headless --path . --script res://addons/dot_audio/tools/ambience_levels.gd -- [--bed-level=0.3] [--map-level=1.5] [--lively] [--detail]
## [/codeblock]
## Run from a game's root: its `res://game/*_ambience.gd` `make_rules()` supplies the server's
## level and rate. File levels are decoded by ffmpeg (the engine's headless driver mixes nothing),
## then the gain chain is applied, so a row is the bus level that chain gives, not a capture.
## Exit 1 when a default layer is louder than [constant CEILING_RMS_DB] or a one-shot set fires
## more than [constant CEILING_SHOTS_PER_MIN] times a minute.

## Quietest a game's mix may push ambience: 13 dB under the -17 LUFS game standard.
const CEILING_RMS_DB := -30.0
## The busiest a mood's one-shots may be at defaults, all sets together.
const CEILING_SHOTS_PER_MIN := 3.0
const SHOT_UNIT_SIZE := 8.0

var _cache: Dictionary = {}


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var probe := DotAudioAmbience.new()
	var bed_level := probe.level
	var map_level := 1.0
	var lively := "--lively" in args
	var detail := "--detail" in args
	for a in args:
		if a.begins_with("--bed-level="):
			bed_level = a.get_slice("=", 1).to_float()
		elif a.begins_with("--map-level="):
			map_level = a.get_slice("=", 1).to_float()
	var mixer := DotAudioMixer.new()
	var bus := float(mixer.levels().get(&"Ambience", 1.0)) * mixer.master
	var rules := _game_rules()
	var cfg_volume := clampf(rules.volume * map_level, 0.0, 1.0)
	print("ambience levels  %s  bus %.2f (%.1f dB)  bed level %.2f x map %.2f%s  mood volume %.2f  frequency %.2f  (rules from %s)" % [
		ProjectSettings.get_setting("application/config/name", "?"), bus, linear_to_db(bus), bed_level, map_level,
		" lively" if lively else "", cfg_volume, rules.frequency, rules.get_meta(&"from", "dot-audio defaults")])

	var bad := 0
	var worst_bed := {"rms": -INF}
	var dir := DotAudioStock.directory().path_join("ambience")
	probe.birds = lively
	for id: StringName in DotAudioStock.BEDS:
		probe.set_map_bed(id)
		var plays := probe.bed_at(Vector3.ZERO)
		var m := _measure(dir.path_join(String(plays) + ".ogg"))
		if m.is_empty():
			print("  bed %-15s MISSING or undecodable" % id)
			bad += 1
			continue
		var g := linear_to_db(maxf(bed_level * map_level * bus, 1e-6))
		var row := {"id": "%s%s" % [id, "" if plays == id else "->" + String(plays)], "rms": m["rms"] + g, "peak": m["peak"] + g}
		if detail:
			print("  bed %-26s rms %6.1f  peak %6.1f dBFS" % [row["id"], row["rms"], row["peak"]])
		if row["rms"] > worst_bed["rms"]:
			worst_bed = row
	probe.free()

	var made := DotAmbienceSet.load_dir(DotAudioStock.moods_directory())
	if not made.ok:
		print("  no stock mood set: %s" % made.error.message)
		return 1
	var moodset: DotAmbienceSet = made.value
	var worst_mood := {"rms": -INF}
	var busiest := {"per_min": -1.0}
	for mood_name: String in moodset.names():
		var mood: DotAmbienceMood = moodset.moods[mood_name]
		var power := 0.0
		for bed: Dictionary in mood.beds:
			var m := _measure(bed["file"])
			if m.is_empty():
				bad += 1
				continue
			var lin := float(bed["volume"]) * mood.volume * cfg_volume * 2.0 * bus
			power += db_to_linear(m["rms"] + linear_to_db(maxf(lin, 1e-6))) ** 2
		var per_min := 0.0
		var shot_peak := -INF
		for shot: Dictionary in mood.oneshots:
			var mean_gap := (float(shot["min_interval"]) + float(shot["max_interval"])) * 0.5
			per_min += 0.0 if rules.frequency <= 0.0 else 60.0 * rules.frequency / mean_gap
			var dist := (float(shot["min_distance"]) + float(shot["max_distance"])) * 0.5
			var lin := float(shot["volume"]) * mood.volume * cfg_volume * 2.0 * bus * minf(SHOT_UNIT_SIZE / dist, 1.41)
			for f: String in shot["files"]:
				var m := _measure(f)
				if not m.is_empty():
					shot_peak = maxf(shot_peak, m["peak"] + linear_to_db(maxf(lin, 1e-6)))
		var row := {"id": mood_name, "rms": linear_to_db(maxf(sqrt(power), 1e-9)), "shot_peak": shot_peak, "per_min": per_min}
		if detail:
			print("  mood %-25s beds rms %6.1f  one-shot peak %6.1f dBFS  %.2f one-shots/min" % [mood_name, row["rms"], shot_peak, per_min])
		if row["rms"] > worst_mood["rms"]:
			worst_mood = row
		if per_min > busiest["per_min"]:
			busiest = row

	print("  loudest bed   %-24s rms %6.1f  peak %6.1f dBFS" % [worst_bed.get("id", "-"), worst_bed["rms"], worst_bed.get("peak", -INF)])
	print("  loudest mood  %-24s rms %6.1f  one-shot peak %6.1f dBFS" % [worst_mood.get("id", "-"), worst_mood["rms"], worst_mood.get("shot_peak", -INF)])
	print("  busiest mood  %-24s %.2f one-shots/min (one every %.0f s)" % [busiest.get("id", "-"), busiest["per_min"], 60.0 / maxf(busiest["per_min"], 0.001)])
	var over := PackedStringArray()
	if worst_bed["rms"] > CEILING_RMS_DB:
		over.append("bed rms over %.0f" % CEILING_RMS_DB)
	if worst_mood["rms"] > CEILING_RMS_DB:
		over.append("mood rms over %.0f" % CEILING_RMS_DB)
	if busiest["per_min"] > CEILING_SHOTS_PER_MIN:
		over.append("one-shots over %.0f/min" % CEILING_SHOTS_PER_MIN)
	print("  verdict: %s" % ("QUIET" if over.is_empty() and bad == 0 else ", ".join(over) + (" (%d files missing)" % bad if bad > 0 else "")))
	return 0 if over.is_empty() and bad == 0 else 1


## The game's server defaults: the first `res://game/*_ambience.gd` with a static `make_rules()`.
func _game_rules() -> DotAmbienceRules:
	var d := DirAccess.open("res://game")
	if d != null:
		for f in d.get_files():
			if not f.ends_with("_ambience.gd"):
				continue
			var s: Variant = load("res://game".path_join(f))
			if s is GDScript and (s as GDScript).get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "make_rules"):
				var r: Variant = (s as GDScript).call(&"make_rules")
				if r is DotAmbienceRules:
					(r as DotAmbienceRules).set_meta(&"from", f)
					return r
	return DotAmbienceRules.new()


## Peak and RMS in dBFS of a file, decoded by ffmpeg; empty when it cannot be.
func _measure(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var out: Array = []
	var code := OS.execute("ffmpeg", ["-hide_banner", "-nostats", "-i", ProjectSettings.globalize_path(path),
		"-ac", "1", "-af", "astats=measure_perchannel=none", "-f", "null", "-"], out, true)
	var m := {}
	if code == 0:
		for line in "\n".join(out).split("\n"):
			if "Peak level dB:" in line:
				m["peak"] = line.get_slice(":", 1).to_float()
			elif "RMS level dB:" in line:
				m["rms"] = line.get_slice(":", 1).to_float()
	if not (m.has("peak") and m.has("rms")):
		m = {}
	_cache[path] = m
	return m
