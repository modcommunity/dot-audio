extends "selftest_base.gd"

## The ambience sections of audio_selftest.gd: beds and zones, the creepy-ambience layer, the director.


func _test_ambience_and_loudness() -> void:
	_section("A world is never silent, and never clips")

	var cat := DotAudioCatalogue.new()
	DotAudioStock.add_to(cat)
	var m := _manager(cat, 16)
	var sink := m.sink as DotAudioSinkNull
	var amb := DotAudioAmbience.new()
	amb.manager = m
	amb.fade_seconds = 1.0
	add_child(amb)
	amb.set_process(false)

	amb.set_map_bed(&"")
	_check(amb.current_bed() == &"amb_wind", "a map that names no bed still gets one, without birds")
	amb.set_map_bed(&"amb_outdoor")
	_check(amb.current_bed() == &"amb_wind" and amb.level <= 0.4, "the birdsong bed is not played unless a map asks, and the bed level is low")
	amb.set_map_profile(1.5, true)
	_check(amb.current_bed() == &"amb_outdoor" and is_equal_approx(amb._gain(), amb.level * 1.5), "a map document's profile (a forest) brings the birds and a louder bed")
	amb.set_map_profile(1.0, false)
	_check(amb.current_bed() == &"amb_wind", "and a map without the profile loses them again")
	amb.set_map_bed(&"amb_outdoor", 2.0, true)
	_check(amb.current_bed() == &"amb_outdoor" and is_equal_approx(amb._gain(), amb.level * 2.0), "set_map_bed can carry the profile itself")
	amb.set_map_bed(&"amb_night")
	_check(amb.current_bed() == &"amb_night" and sink.count_of(&"amb_night") == 1, "a map's own bed plays")
	amb.add_zone(AABB(Vector3(0, 0, 0), Vector3(10, 5, 10)), &"amb_indoor")
	m.listener_position = Vector3(5, 1, 5)
	amb._choose()
	_check(amb.current_bed() == &"amb_indoor", "walking into a zone swaps the bed")
	for i in 90:
		amb._ease(1.0 / 60.0)
	_check(
		sink.count_of(&"amb_night") == 1 and m.describe()["playing"] == 1,
		"the old bed fades out and stops, the new one stays (%s playing)" % str(m.describe()["playing"])
	)
	m.listener_position = Vector3(50, 1, 50)
	amb._choose()
	_check(amb.current_bed() == &"amb_night", "and walking out brings the map's back")
	amb._choose()
	_check(sink.count_of(&"amb_night") == 2, "once: choosing again with nothing changed starts nothing")
	m.stop_all()
	amb._choose()
	_check(sink.count_of(&"amb_night") == 3, "a bed that was stopped under it is started again")
	amb.stop(0.0)
	_check(amb.current_bed() == &"", "stop() is quiet until the next map")

	var before := AudioServer.get_bus_effect_count(0)
	var lim := DotAudioLoudness.install_limiter(-2.0)
	var again := DotAudioLoudness.install_limiter(1.5)
	_check(
		lim != null and lim == again and AudioServer.get_bus_effect_count(0) == before + 1,
		"one limiter on Master however often a manager is set up"
	)
	_check(
		is_equal_approx(again.ceiling_db, DotAudioLoudness.LIMITER_CEILING_DB)
		and is_equal_approx(again.pre_gain_db, 1.5),
		"at the family ceiling, with the game's trim as its pre-gain"
	)
	_check(
		DotAudioLoudness.LIMITER_CEILING_DB < DotAudioLoudness.TRUE_PEAK_CEILING,
		"the sample ceiling sits under the true-peak ceiling"
	)
	_check(
		DotAudioLoudness.band_of(-17.0) == 0 and DotAudioLoudness.band_of(-25.0) == -1
		and DotAudioLoudness.band_of(-12.0) == 1,
		"and a measurement reads against the band"
	)
	AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)

	var trimmed := _manager(cat, 4)
	trimmed.loudness_trim_db = 4.0
	var th := trimmed.play(&"footstep_wood", 0.5)
	_check(
		is_equal_approx(float(trimmed.voice(th).get("volume_db", 99.0)),
			DotAudioStock.footstep_defs()[1].gain_db + 4.0 + linear_to_db(0.5)),
		"the trim is on every voice, so a browser without bus effects hears it too"
	)
	trimmed.queue_free()

	amb.queue_free()
	m.queue_free()



func _write_wav(path: String) -> void:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 8000
	var bytes := PackedByteArray()
	bytes.resize(1600)
	for i in 800:
		bytes.encode_s16(i * 2, int(sin(i * 0.2) * 8000.0))
	w.data = bytes
	w.save_to_wav(path)




## [b]The creepy-ambience layer[/b]: moods read from a directory, crossfaded, one-shots on a
## schedule, and the settings (off, volume, frequency, override, allowed list) all live.
func _test_creepy_ambience() -> void:
	_section("Creepy ambience: moods, one-shots, settings")
	var dir := "user://amb_selftest"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in ["a_bed.wav", "a_shot1.wav", "a_shot2.wav", "b_bed.wav", "b_shot.wav"]:
		_write_wav(dir.path_join(f))
	var doc := {"format": 1, "moods": {
		"alpha": {"volume": 1.0, "beds": [{"file": "a_bed.wav", "volume": 0.8}],
			"oneshots": [{"files": ["a_shot1.wav", "a_shot2.wav", "gone.wav"], "interval": [10, 20], "volume": 0.5, "distance": [5, 20]}]},
		"beta": {"beds": [{"file": "b_bed.wav"}, {"file": "missing.wav"}],
			"oneshots": [{"file": "b_shot.wav", "interval": [30, 40]}]},
		"empty": {"beds": [{"file": "nothing.wav"}]},
	}}
	var f := FileAccess.open(dir.path_join("moods.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()

	_creepy_set_checks(dir, doc)

	var cat := DotAudioCatalogue.new()
	var m := _manager(cat, 16)
	var sink := m.sink as DotAudioSinkNull
	var amb := DotAmbience.new()
	amb.manager = m
	amb.seed_random(7)
	amb.config.crossfade_seconds = 2.0
	add_child(amb)
	amb.set_process(false)
	_check(amb.add_set_dir(dir).ok and amb.mood_names() == PackedStringArray(["alpha", "beta"]), "a set joins the layer")
	_check(not amb.set_mood(&"nope").ok and amb.mood() == &"", "an unknown mood is refused and nothing plays")

	m.listener_position = Vector3(100, 0, 100)
	var heard := []
	amb.oneshot_played.connect(func(mood_id: StringName, file: String, pos: Vector3) -> void: heard.append([mood_id, file, pos]))
	_check(amb.set_mood(&"alpha").ok and amb.mood() == &"alpha", "a mood is chosen")
	amb.advance(0.1)
	_check(amb.describe()["beds"] == 1 and sink.count_of(&"ambience/alpha/bed0") == 1, "its bed starts")
	var first: int = int(amb.describe()["beds"])

	_creepy_oneshots(amb, m, heard)
	_creepy_crossfade(amb, sink, first)
	_creepy_overrides(amb)
	_creepy_holders(amb, heard)
	_creepy_config_and_votes(amb)
	_creepy_indoors(amb)
	_creepy_lifecycle(amb, m, dir)

	amb.queue_free()
	m.queue_free()
	for fn in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(fn))
	DirAccess.remove_absolute(dir.path_join("folk/bed_low.wav"))
	DirAccess.remove_absolute(dir.path_join("folk/knock.wav"))
	DirAccess.remove_absolute(dir.path_join("folk"))
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute("user://amb_selftest_bad/moods.json")
	DirAccess.remove_absolute("user://amb_selftest_bad")



func _creepy_set_checks(dir: String, doc: Dictionary) -> void:
	var loaded := DotAmbienceSet.load_dir(dir)
	var set: DotAmbienceSet = loaded.value if loaded.ok else null
	_check(loaded.ok and set != null and set.names() == PackedStringArray(["alpha", "beta"]), "a set reads its moods and drops the one with no file")
	_check(set != null and set.dropped.size() == 3, "and names the files it lacked (%d)" % (set.dropped.size() if set != null else -1))
	_check(set != null and (set.moods[&"alpha"] as DotAmbienceMood).oneshots[0]["files"].size() == 2, "a one-shot keeps the files that exist")
	_check(not DotAmbienceSet.load_dir("user://amb_nowhere").ok, "a directory that is not there is a DotResult failure, not a crash")
	DirAccess.make_dir_recursive_absolute("user://amb_selftest_bad")
	var badf := FileAccess.open("user://amb_selftest_bad/moods.json", FileAccess.WRITE)
	badf.store_string("[1,2")
	badf.close()
	var bad_res := DotAmbienceSet.load_dir("user://amb_selftest_bad")
	_check(not bad_res.ok and bad_res.error.code == DotError.CODE_PARSE, "a malformed document is a parse failure")

	DirAccess.make_dir_recursive_absolute(dir.path_join("folk"))
	_write_wav(dir.path_join("folk/bed_low.wav"))
	_write_wav(dir.path_join("folk/knock.wav"))
	DirAccess.remove_absolute(dir.path_join("moods.json"))
	var folk := DotAmbienceSet.load_dir(dir)
	var fm: DotAmbienceMood = folk.value.moods.get(&"folk") if folk.ok else null
	_check(fm != null and fm.beds.size() == 1 and fm.oneshots.size() == 1, "with no document a folder is a mood: bed* is a bed, the rest one-shots")
	var jf := FileAccess.open(dir.path_join("moods.json"), FileAccess.WRITE)
	jf.store_string(JSON.stringify(doc))
	jf.close()


func _creepy_oneshots(amb: DotAmbience, m: DotAudioManager, heard: Array) -> void:
	for i in 20:
		amb.advance(1.0)
	var db := -99.0
	for h: int in amb._voices.keys():
		db = float(m.voice(h).get("volume_db", 0.0))
	_check(is_equal_approx(db, linear_to_db(0.8 * 2.0 * amb.config.volume)) and amb.target_level() == amb.config.volume and amb.config.volume <= 0.25, "the default level is nominal for the file, which is a quiet bed (%.1f dB re file)" % db)

	for i in 12:
		amb.advance(5.0)
		m.stop_id(&"ambience/alpha/shot0")
	_check(heard.size() >= 2 and heard.size() <= 8, "one-shots are sparse: %d in 80 s at 10 to 20 s" % heard.size())
	var spread := true
	for h in heard:
		var d: float = (h[2] as Vector3).distance_to(Vector3(100, 0, 100))
		spread = spread and d >= 5.0 - 0.01 and d <= 20.0 + 0.01
	_check(spread, "each from 5 to 20 m of the listener")
	var dirs := {}
	for h in heard:
		dirs[snappedf(((h[2] as Vector3) - Vector3(100, 0, 100)).normalized().x, 0.1)] = true
	_check(dirs.size() >= 2, "and not always from the same direction")

	amb.config.frequency = 0.0
	var n := heard.size()
	for i in 20:
		amb.advance(10.0)
	_check(heard.size() == n, "frequency 0 turns the one-shots off")
	amb.config.frequency = 4.0
	for i in 20:
		amb.advance(5.0)
		m.stop_id(&"ambience/alpha/shot0")
	var fast := heard.size() - n
	_check(fast >= 10, "frequency 4 quadruples them (%d in 100 s)" % fast)
	amb.config.frequency = 1.0


func _creepy_crossfade(amb: DotAmbience, sink: DotAudioSinkNull, first: int) -> void:
	_check(amb.set_mood(&"beta").ok and amb.mood() == &"beta", "the mood changes")
	amb.advance(0.5)
	_check(sink.count_of(&"ambience/beta/bed0") == 1 and amb.describe()["beds"] == 2, "the new bed starts while the old one is still audible (a crossfade)")
	for i in 5:
		amb.advance(1.0)
	_check(amb.describe()["beds"] == 1, "then the old bed is stopped (%s beds)" % str(amb.describe()["beds"]))
	_check(first == 1, "one bed per mood bed")


func _creepy_overrides(amb: DotAmbience) -> void:
	amb.config.mood = "alpha"
	amb.advance(0.1)
	_check(amb.mood() == &"alpha", "the override wins over the game's request")
	amb.config.mood = "ghost"
	amb.advance(0.1)
	_check(amb.mood() == &"beta", "an override naming no mood is ignored")
	amb.config.mood = ""
	amb.config.allowed_moods = "alpha"
	amb.advance(0.1)
	_check(amb.mood() == &"alpha", "a mood outside the allowed list gives way to one in it")
	amb.config.allowed_moods = "alpha, beta"
	amb.advance(0.1)
	_check(amb.mood() == &"beta", "and returns once allowed")
	amb.config.allowed_moods = ""


func _creepy_holders(amb: DotAmbience, heard: Array) -> void:
	amb.duck(&"fight", 0.3)
	amb.duck(&"other", 0.6)
	_check(is_equal_approx(amb.target_level(), amb.config.volume * 0.3), "ducking takes the lowest scale")
	var count := heard.size()
	for i in 30:
		amb.advance(5.0)
	_check(heard.size() == count, "a ducked layer plays no one-shots")
	amb.unduck(&"fight")
	_check(is_equal_approx(amb.target_level(), amb.config.volume * 0.6), "holders release one at a time")
	amb.unduck(&"other")
	amb.hush(&"talk")
	for i in 30:
		amb.advance(5.0)
	_check(heard.size() == count and amb.target_level() == amb.config.volume, "hush stops one-shots but not beds")
	amb.unhush(&"talk")
	amb.pause(&"menu")
	_check(amb.target_level() == 0.0, "pause takes the level to nothing")
	for i in 60:
		amb.advance(1.0)
	_check(is_equal_approx(amb._level, 0.0) and heard.size() == count, "and it fades there without one-shots")
	amb.resume(&"menu")
	for i in 80:
		amb.advance(1.0)
	_check(is_equal_approx(amb._level, amb.config.volume), "resume brings it back")

	amb.config.enabled = false
	for i in 80:
		amb.advance(1.0)
	_check(is_equal_approx(amb._level, 0.0) and amb.describe()["enabled"] == false, "ambient off silences the layer")
	amb.config.enabled = true
	amb.config.volume = 0.25
	for i in 80:
		amb.advance(1.0)
	_check(is_equal_approx(amb._level, 0.25), "volume is live")


func _creepy_config_and_votes(amb: DotAmbience) -> void:
	var d := amb.describe()
	_check(d["mood"] == "beta" and d["beds"] >= 1 and d.has("next_oneshot_in") and d["oneshots_played"] > 0, "describe() says what is playing and what is next")
	_check(amb.describe_lines()[0].contains("beta"), "and describe_lines() reads it")

	var cfg := DotAmbienceConfig.new()
	var applied := cfg.apply_dictionary({"enabled": false, "volume": 0.2, "frequency": 2.0, "mood": "swamp", "allowed_moods": "swamp,cave_tunnel", "sound_dir": "/x"})
	_check(not cfg.enabled and is_equal_approx(cfg.volume, 0.2) and cfg.allowed() == PackedStringArray(["swamp", "cave_tunnel"]) and cfg.sound_dir == "/x", "the config is a DotConfig: a dictionary layer sets every field (%s)" % str(applied))
	_check(cfg.env_prefix() == "DOT_AMBIENCE_" and cfg.cli_prefix() == "--ambience-", "with its own environment and command-line prefixes")

	_check(DotAmbienceMoods.vote(["d1_town.Street", "canals_slime_outside", "storm_rain"]) == DotAmbienceMoods.CITY_RUINS, "soundscape names vote for a mood")
	_check(DotAmbienceMoods.vote(["prison.general_dripping_tunnel", "coast.util_windgusts"]) == DotAmbienceMoods.INTERIOR_HORROR, "the first table row breaks a tie")
	_check(DotAmbienceMoods.vote(["xyzzy"], &"indoor_hall") == &"indoor_hall", "and a name that matches nothing gives the fallback")
	_check(DotAmbienceMoods.vote(DotAmbienceMoods.names_in({"soundscapes": [{"soundscape": "bedroom_rain"}], "ambient": [{"message": "ambient/wind/windgust.wav", "stand_in": "wind"}]})) != &"", "a map's sounds block is read for names")


func _creepy_indoors(amb: DotAmbience) -> void:
	amb.set_mood(&"alpha")
	amb.indoor_mood = &"beta"
	amb.advance(0.1)
	_check(amb.mood() == &"alpha", "outdoors the requested mood plays")
	amb.set_indoors(true)
	amb.advance(0.1)
	_check(amb.mood() == &"beta" and amb.describe()["indoors"], "under a roof the indoor mood takes over")
	amb.config.follow_indoors = false
	amb.advance(0.1)
	_check(amb.mood() == &"alpha", "and the config can keep it outdoors")
	amb.config.follow_indoors = true
	amb.set_indoors(false)
	amb.advance(0.1)
	_check(amb.mood() == &"alpha", "stepping out brings the outdoor mood back")
	amb.indoor_mood = &""
	var merged := amb.mood_def(&"alpha").with_oneshots_of(amb.mood_def(&"beta"), &"alpha+beta")
	_check(merged.oneshots.size() == amb.mood_def(&"alpha").oneshots.size() + amb.mood_def(&"beta").oneshots.size() and merged.beds.size() == amb.mood_def(&"alpha").beds.size(), "a mood can borrow another's one-shots")
	var roof := DotAmbienceRoof.new()
	var flips := 0
	for hit in [true, false, true, true, true, false, false, false, true, false, false, false, false]:
		if roof.feed(hit):
			flips += 1
	_check(roof.roofed == false and flips == 2, "the roof probe needs agreeing rays to flip (%d flips)" % flips)


func _creepy_lifecycle(amb: DotAmbience, m: DotAudioManager, dir: String) -> void:
	var live: Array = amb._voices.keys()
	var was_playing := live.any(func(h: int) -> bool: return m.is_playing(h))
	remove_child(amb)
	_check(was_playing and not live.any(func(h: int) -> bool: return m.is_playing(h)), "leaving the tree stops its beds")
	add_child(amb)

	# No catalogue: no bed can start; the one-shot timers must survive the retries, not be re-rolled.
	var m2 := _manager(null, 4)
	var amb2 := DotAmbience.new()
	amb2.manager = m2
	amb2.seed_random(3)
	add_child(amb2)
	amb2.set_process(false)
	amb2.add_set_dir(dir)
	amb2.set_mood(&"alpha")
	amb2.advance(0.1)
	var nexts: Array = amb2._timers.map(func(t: Dictionary) -> float: return float(t["next"]))
	amb2.advance(1.0)
	amb2.advance(1.0)
	amb2.advance(1.0)
	_check(not nexts.is_empty() and nexts == amb2._timers.map(func(t: Dictionary) -> float: return float(t["next"])), "a mood that cannot start its beds does not re-roll its one-shot timers every step")
	amb2.queue_free()
	m2.queue_free()

	var sm := DotAmbienceMood.from_dictionary("s", {"oneshots": [{"files": "a_shot1.wav"}]}, dir, PackedStringArray())
	_check(sm.oneshots.size() == 1 and sm.oneshots[0]["files"].size() == 1, "a one-shot's files may be a single string")


## [b]The glue a game used to write itself.[/b] The stock set loads, a map picks its mood by document,
## table, prefix and name vote, the rules and the player's sliders multiply, and a player's mute wins.
func _test_ambience_director() -> void:
	_section("Ambience director: stock moods, map to mood, settings")
	var m := _manager(DotAudioCatalogue.new(), 16)
	var d := DotAmbienceDirector.new()
	d.manager = m
	d.default_mood = &"industrial"
	d.prefix_moods = {"surf_": &"snow_wind"}
	d.map_moods = {&"hall_a": &"indoor_hall"}
	add_child(d)
	var made := d.setup()
	d.ambient.set_process(false)
	_check(made.ok and d.has_moods() and d.ambient.mood_names().size() == 8, "the stock set loads all eight moods")
	_check(DotAudioStock.moods_directory().ends_with("stock/moods") and FileAccess.file_exists(DotAudioStock.moods_directory() + "/CREDITS.md"), "the stock set is credited beside its files")
	d.on_map(&"unknown_1")
	_check(d.mood_for_map()["mood"] == &"industrial" and d.mood_for_map()["why"] == "default", "an unknown map gets the default")
	d.on_map(&"surf_ski")
	_check(d.mood_for_map()["why"] == "name prefix" and d.ambient.effective_mood() == &"snow_wind", "a prefix picks the mood")
	d.on_map(&"hall_a", {"ambient": {"mood": "swamp", "volume": 9.0}})
	_check(d.mood_for_map()["mood"] == &"swamp" and d.mood_for_map()["why"] == "map document", "the document's field wins over the tables")
	_check(is_equal_approx(d.ambient.config.volume, 1.0), "and its volume scale is clamped")
	d.on_map(&"zz_x", {}, ["spooky_chapel"])
	_check(d.mood_for_map()["mood"] == &"interior_horror" and d.mood_for_map()["why"] == "sound names", "sound names vote when nothing else decides")
	d.on_map(&"hall_a")
	_check(d.mood_for_map()["why"] == "game table", "the game's table names its hand-made maps")
	_check(d.indoor_mood_for_map() == &"indoor_hall", "an indoor map stays indoors")

	var rules := DotAmbienceRules.new()
	rules.prefix = "tt"
	var store := _FakeStore.new()
	d.follow_settings(store, rules)
	_check(rules.set_cvar("tt_ambient_volume", "0.4") and is_equal_approx(d.ambient.config.volume, 0.4), "the server's level reaches the layer under the game's own prefix")
	store.values[&"ambient_volume"] = 0.5
	store.changed.emit(&"ambient_volume", 0.5, &"set")
	_check(is_equal_approx(d.ambient.config.volume, 0.2), "a player's slider multiplies and can only turn it down")
	store.values[&"ambient"] = false
	store.changed.emit(&"ambient", false, &"set")
	_check(not d.ambient.config.enabled, "a player's off switch silences the layer")
	_check(not rules.set_cvar("zz_ambient", "0") and d.describe().has("mood_from"), "another prefix is not this game's cvar; describe says why a mood")
	d.free()
	m.free()


class _FakeStore extends RefCounted:
	signal changed(key: StringName, value: Variant, why: StringName)
	var values := {}

	func get_bool(key: StringName, fallback: bool) -> bool:
		return bool(values.get(key, fallback))

	func get_float(key: StringName, fallback: float) -> float:
		return float(values.get(key, fallback))

