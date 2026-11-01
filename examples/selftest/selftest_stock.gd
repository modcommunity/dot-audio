extends "selftest_ambience.gd"

## The stock-sound sections of audio_selftest.gd: footsteps, slides, landings, weapon sounds, the raw fallback.


# --- 10 ---------------------------------------------------------------------

class LandingCvar extends RefCounted:
	signal changed(old: Variant, new_value: Variant)

	func get_string() -> String:
		return "0.6"


func _test_stock() -> void:
	_section("Stock footsteps and beds: real files, every one")

	var cat := DotAudioCatalogue.new()
	var mine := DotAudioDef.new()
	mine.id = &"footstep_wood"
	mine.path = "res://fixtures/silent.wav"
	cat.add(mine)
	var added := DotAudioStock.add_to(cat)
	_check(
		added == DotAudioStock.SURFACES.size() - 1 + DotAudioStock.BEDS.size() + DotAudioStock.slide_defs().size() + DotAudioStock.surf_defs().size() + DotAudioStock.FLASHLIGHT_IDS.size() + DotAudioStock.LANDING_IDS.size() + DotAudioWeaponStock.COUNTS.size(),
		"add_to adds every stock id the game has not defined (%d)" % added
	)
	_check(cat.find(&"footstep_wood").path == "res://fixtures/silent.wav", "and a game's own id wins")
	_check(cat.validate().ok, "the stock defs validate")
	_check(DotAudioStock.ids().all(func(i: StringName) -> bool: return cat.has(i)) and DotAudioStock.ids(false).size() == 28 and DotAudioStock.ids().size() == 28 + DotAudioWeaponStock.COUNTS.size(), "ids() names every one")

	# The armed half: a def naming a file nobody shipped passes validate() and is silent for
	# ever. Every path and every variant must exist on disk.
	var missing := PackedStringArray()
	for d in DotAudioStock.footstep_defs() + DotAudioStock.slide_defs() + DotAudioStock.ambience_defs() + DotAudioStock.flashlight_defs() + DotAudioStock.landing_defs():
		for p in d.variants if not d.variants.is_empty() else PackedStringArray([d.path]):
			if not ResourceLoader.exists(p):
				missing.append(p)
	_check(missing.is_empty(), "every stock file is there (%s)" % ", ".join(missing))

	var fl_on := load(DotAudioStock.flashlight_defs()[0].path) as AudioStream
	_check(fl_on != null and fl_on.get_length() < 0.3 and cat.find(&"flashlight_off").gain_db < cat.find(&"footstep_concrete").gain_db, "the flashlight clicks are short and quieter than a footstep")

	_check(DotAudioStock.landing_id(3.0) == &"landing_light" and DotAudioStock.landing_id(10.0) == &"landing_medium" and DotAudioStock.landing_id(20.0) == &"landing_hard", "a landing picks a thump by impact")
	var lrules := DotAudioLandingRules.new()
	_check(lrules.volume_for(2.0) == 0.0 and lrules.volume_for(20.0) > lrules.volume_for(6.0) and lrules.volume_for(20.0) < 1.0, "a soft landing is silent, a harder one louder, and the default is mild")
	lrules.volume = 0.0
	_check(lrules.volume_for(20.0) == 0.0, "volume 0 mutes landings")
	var lcv := LandingCvar.new()
	var made := lrules.bind_cvars(func(_n: String, _v: String, _d: String, _f: int) -> Object: return lcv)
	lcv.changed.emit("0", "0.9")
	_check(made.size() == 1 and is_equal_approx(lrules.volume, 0.9), "cl_landing_volume follows its cvar live")

	var bed := load(DotAudioStock.ambience_defs()[0].path) as AudioStream
	_check(bed != null and bed.get_length() > 20.0, "a bed loads and is a long loop, not a one-shot")
	_check(
		DotAudioStock.ambience_defs().all(func(d: DotAudioDef) -> bool: return d.looping and d.bus == &"Ambience"),
		"every bed loops on the Ambience bus"
	)

	_check(DotAudioStock.surface_of("Floor_Wood_02") == &"wood", "a node name with a surface word names it")
	_check(DotAudioStock.surface_of("asphalt") == &"concrete", "an alias folds onto a surface with files")
	_check(DotAudioStock.surface_of("snowbank") == &"snow", "a longer word containing one too")
	_check(DotAudioStock.surface_of("lava") == &"", "and an unknown one says nothing")
	_check(DotAudioStock.footstep_id(&"lava") == &"footstep_concrete", "so a step on it is concrete")

	_stock_weapons()


func _stock_weapons() -> void:
	var wcat := DotAudioCatalogue.new()
	_check(DotAudioWeaponStock.add_to(wcat) == DotAudioWeaponStock.COUNTS.size(), "weapon stock adds one def per sound")
	var far_def: DotAudioDef = wcat.find(&"weapon_magnum_far")
	_check(far_def != null and far_def.max_distance >= 500.0, "a distant report is audible from far, not culled like a click")
	_check(wcat.validate().ok, "the weapon defs validate")
	var plain := DotAudioCatalogue.new()
	DotAudioStock.add_to(plain, false)
	var both := DotAudioCatalogue.new()
	DotAudioStock.add_to(both)
	_check(not plain.has(&"weapon_light_fire") and both.has(&"weapon_light_fire"), "DotAudioStock.add_to brings the weapon sounds unless told not to")
	var own := DotAudioDef.new()
	own.id = &"weapon_swing"
	own.path = "res://own.ogg"
	both.add(own)
	_check(both.validate().ok and both.find(&"weapon_swing") == own, "a game's own def for a stock id replaces the stock one")
	var wmissing := PackedStringArray()
	for d in DotAudioWeaponStock.defs():
		for p in d.variants:
			if not ResourceLoader.exists(p):
				wmissing.append(p)
	_check(wmissing.is_empty(), "every weapon file is there (%s)" % ", ".join(wmissing))
	var on_disk := 0
	for f in DirAccess.get_files_at(DotAudioWeaponStock.directory()):
		if f.ends_with(".ogg"):
			on_disk += 1
	var listed := 0
	for n: StringName in DotAudioWeaponStock.COUNTS:
		listed += int(DotAudioWeaponStock.COUNTS[n])
	_check(on_disk == listed, "COUNTS names every file on disk (%d of %d)" % [listed, on_disk])
	var shot := load(DotAudioWeaponStock.defs()[0].path) as AudioStream
	_check(shot != null and shot.get_length() > 0.05, "a weapon sound loads")

# --- 11 ---------------------------------------------------------------------

func _test_footsteps() -> void:
	_section("A step is distance travelled, and slow is silent")

	var cat := DotAudioCatalogue.new()
	DotAudioStock.add_to(cat)
	var m := _manager(cat, 32)
	var sink := m.sink as DotAudioSinkNull
	var steps := DotAudioFootsteps.new()
	steps.manager = m
	steps.default_surface = &"grass"
	add_child(steps)
	steps.set_physics_process(false)

	var body := Node3D.new()
	add_child(body)
	var on_ground := [true]
	steps.track(body, {"grounded": func() -> bool: return on_ground[0]})
	var heard: Array = []
	steps.stepped.connect(func(_b: Node3D, s: StringName, l: float) -> void: heard.append([s, l]))

	# Walking at 4 m/s for 3 s on a map whose ground says nothing: grass.
	for i in 180:
		body.global_position += Vector3(4.0 / 60.0, 0, 0)
		steps.advance(body, 1.0 / 60.0)
	var walked := heard.size()
	_check(walked >= 5 and walked <= 9, "twelve metres at a walk is about six steps (%d)" % walked)
	_check(sink.count_of(&"footstep_grass") == walked, "each one a grass step, on the map's ground")

	heard.clear()
	for i in 180:
		body.global_position += Vector3(1.0 / 60.0, 0, 0)
		steps.advance(body, 1.0 / 60.0)
	_check(heard.is_empty(), "creeping at 1 m/s makes no sound at all")

	heard.clear()
	for i in 60:
		body.global_position += Vector3(8.0 / 60.0, 0, 0)
		steps.advance(body, 1.0 / 60.0)
	_check(
		not heard.is_empty() and is_equal_approx(float(heard[0][1]), 1.0),
		"a run is full loudness"
	)

	heard.clear()
	on_ground[0] = false
	for i in 30:
		body.global_position += Vector3(4.0 / 60.0, 0, 0)
		steps.advance(body, 1.0 / 60.0)
	_check(heard.is_empty(), "nothing in the air")
	on_ground[0] = true
	steps.advance(body, 1.0 / 60.0)
	_check(heard.size() == 1 and is_equal_approx(float(heard[0][1]), 1.0), "and a landing is one full step")

	heard.clear()
	body.global_position += Vector3(50, 0, 0)
	steps.advance(body, 1.0 / 60.0)
	_check(heard.is_empty(), "a teleport is not a walk")

	_check_surface_lookup(steps, body)
	body.queue_free()
	steps.queue_free()
	m.queue_free()

## Surface lookup and track()/keep() bookkeeping, split out of _test_footsteps.
func _check_surface_lookup(steps: DotAudioFootsteps, body: Node3D) -> void:
	var floor := StaticBody3D.new()
	floor.name = "Ground"
	floor.set_meta(&"surface", "plank")
	var tile := Node3D.new()
	tile.name = "KitchenTiles"
	tile.add_to_group(&"surface_tile")
	var child := StaticBody3D.new()
	child.name = "Slab"
	tile.add_child(child)
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	box.set_meta(&"surface", "parquet")
	floor.add_child(box)
	add_child(floor)
	add_child(tile)
	_check(DotAudioFootsteps.surface_of_collider(floor) == &"wood", "a collider's surface meta names it")
	var fps_floor := StaticBody3D.new()
	fps_floor.name = "Box"
	fps_floor.set_meta(&"dot_fps_surface", &"ice")
	_check(DotAudioFootsteps.surface_of_collider(fps_floor) == &"snow", "so does dot-player-controller's dot_fps_surface")
	fps_floor.free()
	_check(DotAudioFootsteps.surface_of_collider(child) == &"concrete", "a parent's surface group does too")
	_check(
		DotAudioFootsteps.surface_of_collider(floor, 0) == &"wood" and DotAudioStock.surface_of("sidewalk") == &"concrete",
		"and the hit shape's own meta comes first, for a body built of many boxes"
	)
	steps.track(floor, {"surface": &"metal"})
	_check(steps.tracked_count() == 2, "any number of bodies, each with its own options")
	steps.untrack(floor)
	steps.keep([body, floor])
	steps.keep([floor])
	_check(steps.is_tracking(floor) and not steps.is_tracking(body), "keep() tracks exactly the bodies it is handed")

	floor.queue_free()
	tile.queue_free()

# --- 12 ---------------------------------------------------------------------

func _test_slide() -> void:
	_section("A slide scrapes the surface under it, once per slide")

	var cat := DotAudioCatalogue.new()
	DotAudioStock.add_to(cat)
	var m := _manager(cat, 32)
	var sink := m.sink as DotAudioSinkNull
	var slide := DotAudioSlide.new()
	slide.manager = m
	add_child(slide)
	slide.set_physics_process(false)

	_check(DotAudioStock.slide_id(&"Floor_Wood_02") == &"slide_wood", "a surface word picks its loop")
	_check(DotAudioStock.slide_id(&"asphalt") == &"slide_concrete", "an alias folds onto one")
	_check(DotAudioStock.slide_id(&"lava") == &"slide_generic" and DotAudioStock.slide_id(&"") == &"slide_generic", "anything else is the generic ground scrape")
	_check(DotAudioStock.slide_defs().all(func(d: DotAudioDef) -> bool: return d.looping), "every slide def loops")

	var body := Node3D.new()
	add_child(body)
	var on := [false]
	var started: Array = []
	var stopped: Array = []
	slide.slide_started.connect(func(_b: Node3D, s: StringName) -> void: started.append(s))
	slide.slide_stopped.connect(func(_b: Node3D) -> void: stopped.append(true))
	slide.track(body, func() -> bool: return on[0], {"surface": &"metal"})

	for i in 30:
		body.global_position += Vector3(8.0 / 60.0, 0, 0)
		slide.advance(body, 1.0 / 60.0)
	_check(started.is_empty() and sink.count_of(&"slide_metal") == 0, "walking without a slide is silent")

	on[0] = true
	for i in 90:
		body.global_position += Vector3(8.0 / 60.0, 0, 0)
		slide.advance(body, 1.0 / 60.0)
	_check(started.size() == 1 and started[0] == &"metal", "start fires once, with the surface")
	_check(sink.count_of(&"slide_metal") == 1, "and one loop plays on it, not one a frame")

	for i in 90:
		body.global_position += Vector3(2.0 / 60.0, 0, 0)
		slide.advance(body, 1.0 / 60.0)
	_check(sink.count_of(&"slide_metal") == 1, "slowing down shapes the same loop")

	on[0] = false
	slide.advance(body, 1.0 / 60.0)
	slide.advance(body, 1.0 / 60.0)
	_check(stopped.size() == 1 and not slide.is_sliding(body), "stop fires once when the slide ends")

	slide.enabled = false
	on[0] = true
	for i in 10:
		body.global_position += Vector3(8.0 / 60.0, 0, 0)
		slide.advance(body, 1.0 / 60.0)
	_check(started.size() == 1, "the server's switch silences it")
	slide.enabled = true
	slide.untrack(body)
	slide.track(body, func() -> bool: return true)
	for i in 5:
		body.global_position += Vector3(8.0 / 60.0, 0, 0)
		slide.advance(body, 1.0 / 60.0)
	_check(started.size() == 2 and started[1] == &"", "no surface named plays the generic loop")
	_check(sink.count_of(&"slide_generic") == 1, "slide_generic is the one that played")
	slide.untrack(body)

	var gone := Node3D.new()
	add_child(gone)
	slide.track(gone, func() -> bool: return true)
	gone.free()
	slide.keep([], func(_b: Node3D) -> bool: return false)
	_check(slide.describe()["bodies"] == 0, "keep drops a body freed since the last frame")
	_check_freed_slide(m, slide)


func _check_freed_slide(m: DotAudioManager, slide: DotAudioSlide) -> void:
	var doomed := Node3D.new()
	add_child(doomed)
	slide.track(doomed, func() -> bool: return true, {"surface": &"metal"})
	for i in 5:
		doomed.global_position += Vector3(8.0 / 60.0, 0, 0)
		slide.advance(doomed, 1.0 / 60.0)
	var handle := int(slide._bodies[doomed]["handle"])
	var catcher := _ErrorCatcher.new()
	OS.add_logger(catcher)
	doomed.free()
	slide._physics_process(1.0 / 60.0)
	OS.remove_logger(catcher)
	_check(handle != 0 and not m.is_playing(handle), "a body freed mid-slide stops its loop")
	_check(slide.describe()["bodies"] == 0 and catcher.errors.is_empty(), "and drops silently, no engine error " + str(catcher.errors))


class FakeSurf extends DotAudioSurfRules:
	var on: bool = true

	func is_surfing(_body: Node3D) -> bool:
		return on


func _test_surf() -> void:
	_section("Surfing glides quietly, and makes no steps or landings")

	var cat := DotAudioCatalogue.new()
	DotAudioStock.add_to(cat)
	var m := _manager(cat, 32)
	var sink := m.sink as DotAudioSinkNull
	var rules := FakeSurf.new()
	var stock_def := DotAudioStock.surf_defs()
	_check(stock_def.size() == 1 and stock_def[0].looping and DotAudioStock.ids().has(DotAudioStock.SURF_GLIDE_ID), "the glide is a stock looping def")
	var stream := load(stock_def[0].path) as AudioStream
	_check(stream != null and stream.get_length() > 1.0, "and its file loads")

	_check(rules.apply_cvar("sv_surf_volume", "9") and is_equal_approx(rules.volume, 2.0), "a cvar sets its field, clamped to its range")
	_check(not rules.apply_cvar("sv_surf_nope", "1") and not rules.apply_cvar("sv_surf_volume", "loud"), "an unknown or non-numeric cvar is refused")
	_check(rules.apply_values({"quiet_speed": 6, "sv_surf_mute_steps": false, "pitch_high": "1.5"}) == 3 and rules.quiet_speed == 6.0 and not rules.mute_steps and rules.pitch_high == 1.5, "a profile hands over field names, cvar names, bools and strings")
	rules = FakeSurf.new()
	_check(rules.shape(rules.quiet_speed - 1.0).x == 0.0 and is_equal_approx(rules.shape(rules.full_speed).x, rules.volume) and rules.shape(30.0).y > rules.shape(10.0).y, "volume and pitch rise with speed, silent below the quiet speed")
	_check(rules.is_ramp_normal(Vector3(0.7, 0.5, 0).normalized()) and not rules.is_ramp_normal(Vector3.UP) and not rules.is_ramp_normal(Vector3.RIGHT), "a ramp is steeper than walkable and not a wall")

	var steps := DotAudioFootsteps.new()
	steps.manager = m
	steps.default_surface = &"grass"
	add_child(steps)
	steps.set_physics_process(false)
	var glide := DotAudioSurf.new()
	glide.manager = m
	glide.rules = rules
	add_child(glide)
	glide.set_physics_process(false)
	var body := Node3D.new()
	add_child(body)
	steps.track(body, {"grounded": func() -> bool: return true})
	glide.keep_surfers([body])
	glide.advance(body, 1.0 / 60.0)
	steps.advance(body, 1.0 / 60.0)

	steps.surf_rules = rules
	for i in 120:
		body.global_position += Vector3(14.0 / 60.0, 0, 0)
		steps.advance(body, 1.0 / 60.0)
		glide.advance(body, 1.0 / 60.0)
	_check(sink.count_of(&"footstep_grass") == 0, "no step is heard on a ramp")
	_check(sink.count_of(&"surf_glide") == 1 and glide.is_sliding(body), "one glide loop plays, not one a frame")
	var h := int(glide._bodies[body]["handle"])
	var mid := float(sink.voice(h).get("pitch", 0.0))
	for i in 60:
		body.global_position += Vector3(26.0 / 60.0, 0, 0)
		glide.advance(body, 1.0 / 60.0)
	_check(float(sink.voice(h).get("pitch", 0.0)) > mid and sink.count_of(&"surf_glide") == 1, "going faster raises the same loop's pitch")

	rules.on = false
	glide.advance(body, 1.0 / 60.0)
	_check(not glide.is_sliding(body) and not m.is_playing(h), "leaving the ramp ends the glide")
	body.global_position = Vector3.ZERO
	steps.advance(body, 1.0 / 60.0)
	for i in 60:
		body.global_position += Vector3(4.0 / 60.0, 0, 0)
		steps.advance(body, 1.0 / 60.0)
	_check(sink.count_of(&"footstep_grass") > 0, "and walking steps again")

	rules.on = true
	rules.mute_steps = false
	var before := sink.count_of(&"footstep_grass")
	body.global_position = Vector3.ZERO
	steps.advance(body, 1.0 / 60.0)
	for i in 60:
		body.global_position += Vector3(4.0 / 60.0, 0, 0)
		steps.advance(body, 1.0 / 60.0)
	_check(sink.count_of(&"footstep_grass") > before, "sv_surf_mute_steps 0 leaves the steps alone")
	rules.enabled = false
	glide.keep_surfers([body])
	glide.advance(body, 1.0 / 60.0)
	_check(not glide.is_sliding(body), "sv_surf_sounds 0 silences the glide")

	body.queue_free()
	glide.queue_free()
	steps.queue_free()
	m.queue_free()


func _test_raw_fallback() -> void:
	_section("An addon pack's sound with no imported output still plays")
	var stock := DotAudioStock.directory().path_join("footsteps/footstep_wood_0.ogg")
	var imported := DotAudioSinkGodot.stream_at(stock)
	_check(imported is AudioStreamOggVorbis, "a stock file in this build loads through its import")
	_check(not DotAudioSinkGodot._RAW.streams.has(stock), "and is not decoded a second way")

	# The shape an overlay pack has: the release zip's .ogg and .ogg.import, and no
	# .godot/imported output behind the marker.
	var source := ProjectSettings.globalize_path(stock)
	var marker := "user://dot_audio_probe_step.ogg.import"
	var w := FileAccess.open(marker, FileAccess.WRITE)
	w.store_string('[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\npath="res://.godot/imported/dot_audio_probe_step.ogg-0000.oggvorbisstr"\n')
	w.close()
	var pck := "user://dot_audio_probe.pck"
	var packer := PCKPacker.new()
	packer.pck_start(pck)
	packer.add_file("res://dot_audio_probe/step.ogg", source)
	packer.add_file("res://dot_audio_probe/step.ogg.import", ProjectSettings.globalize_path(marker))
	packer.flush()
	_check(ProjectSettings.load_resource_pack(pck), "a pack shaped like an addon overlay mounts")
	var path := "res://dot_audio_probe/step.ogg"
	_check(not DotAudioSinkGodot._import_output_present(path), "its marker names an output the build does not have")
	var raw := DotAudioSinkGodot.stream_at(path)
	_check(raw is AudioStreamOggVorbis and raw.get_length() > 0.05, "so the sound is decoded from its own bytes (%.2f s)" % (raw.get_length() if raw != null else 0.0))
	_check(DotAudioSinkGodot.stream_at(path) == raw, "once: the next play reuses it")
	_check(DotAudioSinkGodot.stream_at("res://dot_audio_probe/none.ogg") == null, "and a file that is not there is still silence")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
	DotAudioSinkGodot.clear_streams()
	_check(DotAudioSinkGodot._RAW.streams.is_empty(), "clear_streams() drops the cache so a process can exit with no stream in use")

# --- 14 ---------------------------------------------------------------------

## Loading dot-audio must not keep a game alive at exit (a static var once held preloaded scripts). Only a
## process's own exit shows it, so a child loads dot-audio in the order that did it and this reads its stderr.
func _test_nothing_kept_alive_at_exit() -> void:
	_section("Nothing kept alive at exit")
	var output: Array = []
	var args := PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://examples/exit_leak_probe.tscn",
	])
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	var text := "\n".join(output)
	_check(code == 0 and text.contains("exit probe: 2 scripts named"),
		"a process that loads dot-audio as a game's suite does runs and quits (exit %d)" % code)
	var kept := text.contains("still in use at exit") or text.contains("were leaked at exit")
	_check(not kept, "and leaves nothing in use at exit%s" % (
		"" if not kept else ": " + " | ".join(Array(text.split("\n")).filter(
			func(l: String) -> bool: return l.contains("at exit")))))


## An unguarded freed instance can return plausible values, so only the engine error shows it.
class _ErrorCatcher extends Logger:
	var errors: Array[String] = []

	func _log_error(function: String, _file: String, _line: int, code: String,
			rationale: String, _editor_notify: bool, _error_type: int,
			_script_backtraces: Array) -> void:
		errors.append("%s %s %s" % [code, rationale, function])


func _sweep(e: DotAudioEnclosure, distance: float, miss_every: int = 0) -> void:
	for i in 3:
		for r in e.rules.rays:
			e.feed(-1.0 if miss_every > 0 and r % miss_every == 0 else distance)
		e.advance(10.0)


func _test_shots() -> void:
	_section("Layered shots: layers by distance, tail by enclosure, no immediate repeat")

	var cat := DotAudioCatalogue.new()
	var m := _manager(cat, 32)
	var enc := DotAudioEnclosure.new()
	enc.send_bus = &"Master"
	add_child(enc)
	var p := DotShotPlayer.new()
	p.manager = m
	p.enclosure = enc
	add_child(p)
	p.seed_rolls(7)
	var shot := DotAudioShotStock.shot(&"rifle")
	_check(shot.validate().ok and p.register(shot).ok and p.has_shot(shot.id), "a stock shot validates and registers")
	_check(p.register(DotShotDef.new()).ok == false, "a shot with no id or layers is refused")

	var missing := 0
	for weapon_class: StringName in DotAudioShotStock.COUNTS:
		var s := DotAudioShotStock.shot(weapon_class)
		for layer in s.layer_names():
			for path in s.layer(layer):
				if not FileAccess.file_exists(path):
					missing += 1
	_check(missing == 0, "every stock shot file exists (COUNTS matches the disk), %d missing" % missing)

	m.listener_position = Vector3.ZERO
	var near := p.plan(shot.id, Vector3(5, 0, 0))
	var layers_near := near.map(func(e: Dictionary) -> StringName: return e.layer)
	_check(layers_near.has(&"attack") and layers_near.has(&"body") and layers_near.has(&"tail_outdoor") and not layers_near.has(&"far"), "a close shot plays attack, body and tail, no far layer")
	var far := p.plan(shot.id, Vector3(200, 0, 0))
	var layers_far := far.map(func(e: Dictionary) -> StringName: return e.layer)
	_check(layers_far == [&"far"], "a distant shot plays only the far set")
	var mid := p.plan(shot.id, Vector3(75, 0, 0))
	var layers_mid := mid.map(func(e: Dictionary) -> StringName: return e.layer)
	_check(layers_mid.has(&"far") and layers_mid.has(&"body"), "a mid-range shot crossfades near and far")
	_check(absf(near[0].delay - 5.0 / 343.0) < 0.001 and absf(far[0].delay - 200.0 / 343.0) < 0.01, "arrival is delayed by distance over the speed of sound")
	_check(p.rules.weights(10.0).x == 1.0 and p.rules.weights(500.0).x < 0.001 and absf(p.rules.weights(75.0).length() - 1.0) < 0.001, "the crossfade is equal power")

	_sweep(enc, 2.0)
	var tight := enc.tail_class
	_sweep(enc, 40.0, 2)
	var open := enc.tail_class
	_sweep(enc, 12.0)
	var big := enc.tail_class
	_sweep(enc, 30.0)
	var hall := enc.tail_class
	_check(tight == &"small" and open == &"outdoor" and big == &"large" and hall == &"hall", "the tail class follows the room: %s, %s, %s, %s" % [tight, open, big, hall])
	_sweep(enc, 2.0)
	var in_small := p.plan(shot.id, Vector3(5, 0, 0)).map(func(e: Dictionary) -> StringName: return e.layer)
	_check(in_small.has(&"tail_small") and not in_small.has(&"tail_outdoor"), "a shot in a tight room plays the small tail instead of the outdoor one")
	_check(enc.reverb_params().room_size < 0.2 and AudioServer.get_bus_index(DotAudioEnclosure.BUS) >= 0, "the reverb bus exists and a tight room has a small room size")
	var h := DotAudioEnclosure.fibonacci(24)
	_check(h.size() == 24 and absf(h[0].length() - 1.0) < 0.001 and absf(h[10].length() - 1.0) < 0.001, "the rays are unit directions")

	var repeats := 0
	var last := -1
	for i in 200:
		var pick := p.plan(shot.id, Vector3(5, 0, 0))
		var idx := int(String(pick[0].def_id).get_slice("/", 2))
		if idx == last:
			repeats += 1
		last = idx
	_check(repeats == 0, "a layer never repeats the previous variant, %d repeats in 200" % repeats)

	var fired := p.fire(shot.id, Vector3(100, 0, 0))
	_check(fired.ok and p.queued() > 0, "a shot 100 m away is queued for its travel time")
	p.advance(1.0)
	_check(p.queued() == 0, "and played once it has arrived")

	var quiet := p.plan(shot.id, Vector3(5, 0, 0), true).map(func(e: Dictionary) -> StringName: return e.layer)
	_check(quiet.has(&"suppressed_body") and not quiet.has(&"attack"), "a suppressed shot has no crack")

	var r := DotShotRules.new()
	_check(r.layers and r.enclosure and r.delay, "the cvars default on")
	_check(r.set_cvar("snd_shot_rays", "99") and r.rays == 32 and r.set_cvar("snd_shot_rays", "2") and r.rays == 16, "the ray count is clamped to 16-32")
	_check(not r.set_cvar("snd_shot_nope", "1"), "an unknown cvar is refused")
	r.layers = false
	p.rules = r
	_check(not p.fire(shot.id, Vector3(5, 0, 0)).ok, "with layers off the player declines so the caller keeps its own sound")
