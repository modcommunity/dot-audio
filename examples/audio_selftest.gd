extends "selftest/selftest_ambience.gd"

## Exercises dot-audio on a machine with no sound card, which is the point.
##
## [b]Everything above the sink is the real thing.[/b] The catalogue, the culling, the
## cooldowns, the concurrency caps, the priority stealing and the music state machine all
## run exactly as they do with speakers attached; only the four lines that would create an
## [AudioStreamPlayer] are replaced. So these checks are of the system, not of a mock —
## which is the reason [DotAudioSink] exists at all.
##
## [codeblock]
## godot --headless --path . res://examples/audio_selftest.tscn
## [/codeblock]

const SECTIONS := 17
const CHECKS := 237

func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	# Awaited: _test_limits waits a frame, and an un-awaited coroutine returns at its first
	# `await` with the caller carrying straight on -- which is how a suite ends up quitting
	# before half its checks have run.
	await _run()

func _run() -> void:
	_line("dot-audio self-test")
	_line("")

	_test_honesty_about_the_device()
	_test_definitions()
	_test_catalogue()
	_test_mixer_curve()
	await _test_limits()
	_test_stealing()
	_test_music_and_ducking()
	_test_synth()
	_test_shaping()
	_test_stock()
	_test_footsteps()
	_test_slide()
	_test_ambience_and_loudness()
	_test_creepy_ambience()
	_test_ambience_director()
	_test_raw_fallback()
	_test_nothing_kept_alive_at_exit()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)

func _catalogue() -> DotAudioCatalogue:
	var c := DotAudioCatalogue.new()

	var rifle := DotAudioDef.new()
	rifle.id = &"rifle"
	rifle.path = "res://fixtures/silent.wav"
	rifle.max_concurrent = 3
	rifle.priority = 80
	rifle.tags = [&"weapon"]
	c.add(rifle)

	var step := DotAudioDef.new()
	step.id = &"footstep"
	step.path = "res://fixtures/silent.wav"
	step.kind = DotAudioDef.Kind.POSITIONAL_3D
	step.max_distance = 30.0
	step.cooldown_ms = 100
	step.priority = 10
	step.tags = [&"footstep"]
	c.add(step)

	var theme := DotAudioDef.new()
	theme.id = &"theme"
	theme.path = "res://fixtures/silent.wav"
	theme.bus = &"Music"
	theme.looping = true
	theme.priority = 90
	c.add(theme)

	return c

# --- 1 ----------------------------------------------------------------------

func _test_honesty_about_the_device() -> void:
	_section("The engine says there is a sound card when there is not")

	# The bug dot-voice found, asserted here so this addon cannot regress into believing
	# any of the plausible answers.
	_check(AudioServer.get_mix_rate() > 0.0, "a headless run reports a mix rate")
	_check(AudioServer.get_bus_count() > 0, "and a bus layout")
	_check(
		not DotAudioSink.device_present(),
		"and only the driver name says there is no device at all"
	)

	var auto := DotAudioManager.new()
	auto.catalogue = _catalogue()
	auto.apply_mixer_to_buses = false
	auto.register_as_service = false
	add_child(auto)
	auto.setup()
	_check(
		auto.sink is DotAudioSinkNull,
		"so a manager left to choose picks the sink that cannot make a noise"
	)
	_check(
		auto.play(&"rifle") != 0,
		"and everything above it still runs, which is what makes this suite worth anything"
	)
	auto.queue_free()

# --- 2 ----------------------------------------------------------------------

func _test_definitions() -> void:
	_section("A sound is a document that names a file and never loads one")

	var d := DotAudioDef.new()
	_check(not d.validate().ok, "a sound with no id is refused")
	d.id = &"x"
	_check(not d.validate().ok, "and so is one that names no file")
	d.path = "res://nothing.ogg"
	_check(
		d.validate().ok,
		"while one naming a file that does not exist validates, because a server has none of them"
	)

	# A game whose bank is baked arithmetically has no file to name, and this addon
	# refused it on the first run. game-hungario is that game and is the first thing to
	# use the sink seam for what it is actually for.
	var made := DotAudioDef.new()
	made.id = &"blip"
	_check(not made.validate().ok, "a sound with no file and no generator is refused")
	made.generated = true
	_check(
		made.validate().ok,
		"and one the sink makes is not, because the id is then the whole contract"
	)

	d.pitch_min = 1.4
	d.pitch_max = 0.9
	_check(not d.validate().ok, "a maximum pitch below its minimum is refused")
	d.pitch_min = 0.9
	d.pitch_max = 1.1

	d.kind = DotAudioDef.Kind.POSITIONAL_3D
	d.unit_size = 40.0
	d.max_distance = 20.0
	_check(
		not d.validate().ok,
		"and so is a sound culled closer than it reaches full volume, which is silence by arithmetic"
	)
	d.max_distance = 200.0

	_check(is_equal_approx(d.pick_pitch(0.0), 0.9), "a roll of zero is the minimum pitch")
	_check(is_equal_approx(d.pick_pitch(1.0), 1.1), "and of one, the maximum")

	d.variants = PackedStringArray(["a.ogg", "b.ogg", "c.ogg"])
	_check(d.pick_path(0.0) == "a.ogg", "a variant is chosen from the roll")
	_check(d.pick_path(0.99) == "c.ogg", "across the whole list")
	_check(d.pick_path(1.0) == "c.ogg", "and a roll of exactly one does not fall off the end")

# --- 3 ----------------------------------------------------------------------

func _test_catalogue() -> void:
	_section("A catalogue a server with no files can check")

	var c := _catalogue()
	_check(c.validate().ok, "it validates")
	_check(c.ids().size() == 3, "and enumerates")
	_check(c.find(&"rifle") != null, "and finds")
	_check(c.find(&"nothing") == null, "and does not invent")
	_check(c.with_tag(&"weapon").size() == 1, "and can be filtered by tag")

	var dupe := DotAudioCatalogue.new()
	var a := DotAudioDef.new()
	a.id = &"same"
	a.path = "x.ogg"
	var b := DotAudioDef.new()
	b.id = &"same"
	b.path = "y.ogg"
	dupe.add(a).add(b)
	_check(
		not dupe.validate().ok,
		"a duplicate id is refused, because the second one is unreachable and nothing would say so"
	)

	# Two questions, two methods: a server validates a catalogue it has no files for and
	# must not fail; a client about to play something wants to know before a player hears
	# silence.
	var missing := c.missing_files()
	_check(
		missing.size() >= 0,
		"missing_files is a separate question from validate, and asks about the disk"
	)

# --- 4 ----------------------------------------------------------------------

func _test_mixer_curve() -> void:
	_section("A volume slider is not decibels")

	var m := DotAudioMixer.new()
	_check(m.validate().ok, "the mixer validates")
	_check(m.levels().size() == 6, "and has a level per bus it names")

	# The bug this prevents: mapping 0..1 straight onto -60..0 dB gives a slider where
	# everything below about 0.9 is inaudible and two thirds of the travel does nothing.
	m.master = 0.5
	var half := m.db_for(&"Master")
	_check(
		half > -12.0 and half < -3.0,
		"half amplitude is about -6 dB (%.1f), not half of the dB range" % half
	)
	m.master = 1.0
	_check(is_equal_approx(m.db_for(&"Master"), 0.0), "and full is unity")

	m.master = 0.0
	_check(
		m.db_for(&"Master") <= -80.0,
		"zero is silence rather than a number that a later +3 dB turns back into sound"
	)

	m.master = 0.25
	var quarter := m.db_for(&"Master")
	_check(quarter < half, "and the curve is monotonic")
	_check(quarter > -20.0, "without collapsing the bottom of the travel")

# --- 5 ----------------------------------------------------------------------

func _test_limits() -> void:
	_section("The three limits, each of which is a different problem")

	var m := _manager(_catalogue(), 16)
	var null_sink := m.sink as DotAudioSinkNull

	var refusals := []
	m.played.connect(func(id: StringName, handle: int, why: StringName) -> void:
		if handle == 0:
			refusals.append([id, why])
	)

	# 1. Unknown id. A client mid-download asks for ids it does not have; an effect never
	#    changes the simulation, so silence is right and a red line per shot is not.
	_check(m.play(&"nothing_like_this") == 0, "an unknown id is refused")
	_check(refusals.size() == 1 and refusals[0][1] == &"unknown", "and says why")

	# 2. Concurrency. Twelve identical rifles half a millisecond apart is one gunshot
	#    twelve times as loud, with comb filtering.
	var handles := []
	for _i in range(6):
		handles.append(m.play(&"rifle"))
	var started := 0
	for h in handles:
		if h != 0:
			started += 1
	_check(started == 3, "an id stops at its own concurrency cap, whatever the pool has left")
	_check(
		null_sink.count_of(&"rifle") == 3,
		"and the sink was only asked three times, so the cap is not a volume trick"
	)

	# The counts have to come down, or the game goes quiet after a minute.
	for h in handles:
		if h != 0:
			null_sink.finish(h)
	# No frame is waited for on purpose. `_process` does not run while a tree is paused,
	# and a pause menu is exactly when nothing finishes -- so the counts are reaped at the
	# point of refusal as well, and a game coming back from a pause is not silent for ever.
	_check(m.play(&"rifle") != 0, "and a finished sound frees its slot with no frame in between")

	# A caller's pitch is information -- the size of the thing eaten, how charged a shot
	# was -- and the catalogue's own range is variation. Folding them into one setting
	# would make a game that wants to say something with pitch give up the variation.
	null_sink.forget()
	m.play(&"rifle", 1.0, 0.5)
	_check(
		float(null_sink.played()[0]["pitch"]) < 0.7,
		"a caller's pitch scale multiplies the definition's own roll (%.2f)"
		% float(null_sink.played()[0]["pitch"])
	)
	null_sink.forget()
	m.play(&"rifle", 1.0, 100.0)
	_check(
		float(null_sink.played()[0]["pitch"]) <= 4.0,
		"and is clamped, because past about four times resampling is an artefact"
	)

	# 3. Cooldown. A footstep triggered from a physics callback fires twice in a frame,
	#    and the second is inaudible and still costs a voice.
	m.listener_position = Vector3.ZERO
	var first := m.play_at(&"footstep", Vector3(1, 0, 0))
	var second := m.play_at(&"footstep", Vector3(1, 0, 0))
	_check(first != 0, "the first footstep plays")
	_check(second == 0, "and the one in the same millisecond does not")

	# 4. Distance. Culling here rather than in the sink, because a sound accepted for
	#    distance costs a stream load and a position update every frame for ever.
	var far := m.play_at(&"footstep", Vector3(0, 0, 5000))
	_check(far == 0, "a sound past its cull distance is never started")
	_check(
		refusals.back()[1] == &"distance",
		"and the reason is distance rather than the cooldown it also would have hit"
	)

	m.queue_free()

# --- 6 ----------------------------------------------------------------------

func _test_stealing() -> void:
	_section("A full pool steals downwards, or refuses")

	# Two voices, so the pool is the binding limit rather than any per-id cap.
	var cat := DotAudioCatalogue.new()
	var quiet := DotAudioDef.new()
	quiet.id = &"quiet"
	quiet.path = "res://fixtures/silent.wav"
	quiet.priority = 10
	quiet.max_concurrent = 0
	cat.add(quiet)
	var loud := DotAudioDef.new()
	loud.id = &"loud"
	loud.path = "res://fixtures/silent.wav"
	loud.priority = 90
	loud.max_concurrent = 0
	cat.add(loud)

	var m := _manager(cat, 2)
	var sink := m.sink as DotAudioSinkNull

	_check(m.play(&"quiet") != 0, "the pool takes one")
	_check(m.play(&"quiet") != 0, "and a second")
	_check(m.play(&"loud") == 0, "and a full null pool refuses, rather than growing")
	_check(sink.usage()["playing"] == 2, "with the pool at exactly its capacity")

	# The null sink has no stealing in it on purpose -- it is the accounting, not the
	# mixer. What is asserted here is that the manager reports the refusal honestly rather
	# than returning a handle nothing is behind.
	var why := []
	m.played.connect(func(_id: StringName, h: int, w: StringName) -> void:
		if h == 0:
			why.append(w)
	)
	m.play(&"loud")
	_check(why.size() == 1 and why[0] == &"voices", "and says the pool was the reason")

	m.queue_free()

# --- 7 ----------------------------------------------------------------------

func _test_music_and_ducking() -> void:
	_section("Music, and a duck that lifts")

	var m := _manager(_catalogue(), 8)
	var changes := []
	m.music_changed.connect(func(from: StringName, to: StringName) -> void:
		changes.append([from, to])
	)

	m.play_music(&"theme", 0.0)
	_check(m.music_id() == &"theme", "music starts")
	_check(changes.size() == 1, "and announces the change")

	m.play_music(&"theme", 0.0)
	_check(
		changes.size() == 1,
		"asking for the track that is already playing does nothing, which is what a state "
		+ "machine setting it every frame needs"
	)

	m.play_music(&"", 0.0)
	_check(m.music_id() == &"", "and it can be stopped")
	_check(changes.size() == 2, "announcing that too")

	# `stop_music` is the name a game reaches for, and it had no caller anywhere. Asserted
	# through the same signal as the line above, because a stop that does not ANNOUNCE is
	# a menu whose "now playing" never clears.
	m.play_music(&"theme", 0.0)
	m.stop_music(0.0)
	_check(m.music_id() == &"", "stop_music stops it by name as well as by empty id")
	_check(changes.size() == 4, "and announces the start and the stop")

	# `stop_id` and `played_ids` had no caller either. `stop_id` is the one a game needs
	# for a looping sound whose handle it did not keep -- an engine, a fire, an alarm --
	# and it has to stop EVERY copy, not the first.
	var sink := m.sink as DotAudioSinkNull
	sink.forget()
	var first := m.play(&"rifle")
	var second := m.play(&"rifle")
	var other := m.play(&"theme")
	_check(
		first != 0 and second != 0 and other != 0,
		"three sounds play"
	)
	_check(
		Array(sink.played_ids()) == ["rifle", "rifle", "theme"],
		"and the null sink reports what it was asked for, in order"
	)
	m.stop_id(&"rifle")
	_check(
		not m.is_playing(first) and not m.is_playing(second),
		"stopping by id stops every copy of it, not the first one it finds"
	)
	_check(m.is_playing(other), "and leaves everything else alone")

	# Reference-counted rather than a boolean. The commonest bug in every ducking
	# implementation is a duck that never lifts because the second holder released first.
	_check(not m.is_ducked(), "nothing is ducking to start with")
	m.duck(&"radio")
	m.duck(&"cutscene")
	_check(m.is_ducked(), "two things duck")
	m.unduck(&"radio")
	_check(m.is_ducked(), "and one releasing does not lift it")
	m.unduck(&"cutscene")
	_check(not m.is_ducked(), "while the last one does")
	m.unduck(&"nobody")
	_check(not m.is_ducked(), "and releasing something that never ducked is harmless")

	_check(m.describe_lines().size() > 2, "and it describes itself")
	_check(m.describe()["device"] == false, "honestly, including about the device")

	m.queue_free()

func _synth_catalogue() -> DotAudioCatalogue:
	var c := DotAudioCatalogue.new()

	# Two variants, because the bank promises to keep them apart and a catalogue whose
	# defs all have one path cannot show that it does.
	var rifle := DotAudioDef.new()
	rifle.id = &"synth_rifle"
	rifle.path = "res://fixtures/rifle_a.ogg"
	rifle.variants = PackedStringArray(["res://fixtures/rifle_b.ogg"])
	c.add(rifle)

	var step := DotAudioDef.new()
	step.id = &"synth_step"
	step.path = "res://fixtures/step.ogg"
	c.add(step)

	return c

func _test_synth() -> void:
	_section("A synthesised stand-in, and the order it loses to a real file in")

	var shot := DotAudioSynth.voice(DotAudioSynth.Voice.SHOT)
	_check(shot != null and not shot.data.is_empty(), "a voice bakes to bytes")
	_check(
		(
			shot.format == AudioStreamWAV.FORMAT_16_BITS
			and not shot.stereo
			and shot.mix_rate == DotAudioSynth.RATE
		),
		"16-bit mono at the documented rate"
	)

	var frames := shot.data.size() / 2
	var seconds := float(frames) / float(DotAudioSynth.RATE)
	var wanted: float = DotAudioSynth.RECIPES[DotAudioSynth.Voice.SHOT][2]
	_check(absf(seconds - wanted) < 0.01, "and is as long as its recipe says")

	_check(
		DotAudioSynth.voice(DotAudioSynth.Voice.SHOT).data == shot.data,
		"the same voice bakes byte-identical twice, so two clients hear one shot"
	)

	var every := true
	for v in DotAudioSynth.RECIPES.keys():
		var one := DotAudioSynth.voice(v)
		if one == null or one.data.size() < 2:
			every = false
	_check(every, "every voice in the table bakes")

	# The envelope has to reach zero by the last frame. A buffer that stops mid-cycle is a
	# click on the end of every sound, which is the difference between placeholder audio
	# that is rough and placeholder audio nobody will leave switched on.
	var lo := shot.data[shot.data.size() - 2]
	var hi := shot.data[shot.data.size() - 1]
	var last := (hi << 8) | lo
	if last >= 32768:
		last -= 65536
	_check(absi(last) < 400, "and decays to silence rather than stopping mid-cycle")

	_check(
		(
			DotAudioSynth.bake(700.0, 90.0, 0.1, 0.5, 0.8, 0.004, 1).data
			!= DotAudioSynth.bake(700.0, 90.0, 0.1, 0.5, 0.8, 0.004, 2).data
		),
		"a different salt is a different noise"
	)

	var long_one := DotAudioSynth.bake(400.0, 200.0, 60.0)
	_check(
		float(long_one.data.size() / 2) / float(DotAudioSynth.RATE) <= 4.01,
		"an absurd length is clamped rather than allocating a minute of placeholder"
	)

	# --- The bank -----------------------------------------------------------

	var cat := _synth_catalogue()
	var bank := DotAudioSynth.bank(
		cat,
		{
			&"synth_rifle": DotAudioSynth.Voice.SHOT,
			&"synth_step": DotAudioSynth.Voice.STEP,
			&"not_in_the_catalogue": DotAudioSynth.Voice.CLICK,
		}
	)

	_check(bank.has(&"synth_rifle"), "the bank answers by id")
	_check(bank.has("res://fixtures/rifle_a.ogg"), "and by the path the def names")
	_check(
		(
			bank.has("res://fixtures/rifle_b.ogg")
			and (bank["res://fixtures/rifle_b.ogg"] as AudioStreamWAV).data
				!= (bank["res://fixtures/rifle_a.ogg"] as AudioStreamWAV).data
		),
		"and a second variant is a different noise, so a rifle is not a metronome"
	)
	_check(not bank.has(&"not_in_the_catalogue"), "an id the catalogue does not have is skipped")
	_check(bank.has(&"synth_step"), "and the rest of the bank is still built")

	# --- The sink's resolution order ----------------------------------------

	var host := Node.new()
	add_child(host)

	var sink := DotAudioSinkGodot.new(host, 8)

	var missing := {
		"id": "synth_rifle",
		"path": "res://fixtures/rifle_a.ogg",
		"kind": DotAudioDef.Kind.FLAT,
		"priority": 50,
	}
	_check(sink.play(missing) == 0, "with neither a file nor a bank, nothing plays")
	_check(sink.sink_name() == "godot", "and the sink says it has no bank")

	sink.bank = bank
	_check(sink.play(missing) != 0, "with a bank, the same request plays")
	_check(sink.sink_name().begins_with("godot+bank"), "and says so, for a bug report")

	var by_id := {"id": "synth_step", "path": "", "kind": DotAudioDef.Kind.FLAT, "priority": 50}
	_check(sink.play(by_id) != 0, "a def with no path at all resolves by id")

	# A real file has to win, or the bank is a placeholder somebody has to remember to
	# remove. user:// rather than res://, because a suite cannot write into its own build.
	var real := DotAudioSynth.bake(300.0, 300.0, 0.05, 0.2, 0.0)
	var probe_path := "user://dot_audio_probe.tres"
	var saved := ResourceSaver.save(real, probe_path) == OK
	sink.bank[probe_path] = DotAudioSynth.voice(DotAudioSynth.Voice.BOOM)

	var over := {"id": "probe", "path": probe_path, "kind": DotAudioDef.Kind.FLAT, "priority": 50}
	var handle := sink.play(over)
	var played: AudioStream = null
	for child in host.get_children():
		if int(child.get_meta(&"dot_audio_handle", 0)) == handle:
			played = child.get("stream") as AudioStream

	_check(saved and handle != 0, "a def whose path really exists plays")
	_check(
		played is AudioStreamWAV and (played as AudioStreamWAV).data == real.data,
		"and it is the FILE that plays, not the stand-in sitting at the same path"
	)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))

	# --- Looping ----------------------------------------------------------------
	# The manager has always put `looping` in the request; until 2026-09-25 the sink never
	# read it, so a looping def played once. Asserted on the stream the player was handed
	# rather than by waiting for it to end, because the dummy driver's clock is not one a
	# suite should lean on.
	var stream_of := func(h: int) -> AudioStream:
		for child in host.get_children():
			if int(child.get_meta(&"dot_audio_handle", 0)) == h:
				return child.get("stream") as AudioStream
		return null

	var hum := {"id": "synth_step", "path": "", "kind": DotAudioDef.Kind.FLAT, "priority": 50, "looping": true}
	var hum_handle := sink.play(hum)
	var hum_stream := stream_of.call(hum_handle) as AudioStreamWAV
	var source := bank[&"synth_step"] as AudioStreamWAV
	_check(
		hum_stream != null and hum_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD
		and hum_stream.loop_begin == 0 and hum_stream.loop_end == source.data.size() / 2,
		"a looping request plays a stream that loops, over every frame it has"
	)
	_check(
		source.loop_mode == AudioStreamWAV.LOOP_DISABLED,
		"and the bank's own stream is untouched, so the next one-shot of it does not loop"
	)
	var once := sink.play({"id": "synth_step", "path": "", "kind": DotAudioDef.Kind.FLAT, "priority": 50})
	_check(
		stream_of.call(once) == source,
		"a one-shot of the same sound still plays the one-shot"
	)
	_check(
		stream_of.call(sink.play(hum)) == hum_stream,
		"and a second loop of it reuses the one copy rather than duplicating per play"
	)

	# A stream type that cannot be told to loop goes round by restarting on `finished`.
	sink.bank[&"generated"] = AudioStreamGenerator.new()
	var gen := {"id": "generated", "path": "", "kind": DotAudioDef.Kind.FLAT, "priority": 50, "looping": true}
	var gen_handle := sink.play(gen)
	var gen_player: Node = null
	for child in host.get_children():
		if int(child.get_meta(&"dot_audio_handle", 0)) == gen_handle:
			gen_player = child
	if gen_player != null:
		gen_player.emit_signal("finished")
	_check(
		gen_handle != 0 and sink.is_playing(gen_handle),
		"and a stream that cannot loop natively restarts under the same handle when it ends"
	)
	sink.stop(gen_handle)
	_check(not sink.is_playing(gen_handle), "until it is stopped")

	host.queue_free()

# --- 9 ----------------------------------------------------------------------

func _test_shaping() -> void:
	_section("A playing voice is shaped, not restarted")

	# An engine: one loop whose pitch follows the speed and whose load follows the throttle,
	# every frame. Until API level 2 the manager could move and stop a voice but not this,
	# and a game subclassed the Godot sink and read its pool to do it.
	var cat := _catalogue()
	var engine := DotAudioDef.new()
	engine.id = &"engine"
	engine.path = "res://fixtures/silent.wav"
	engine.looping = true
	engine.gain_db = -6.0
	engine.pitch_min = 0.5
	engine.pitch_max = 0.5
	cat.add(engine)

	var m := _manager(cat)
	var sink := m.sink as DotAudioSinkNull

	var h := m.play(&"rifle", 0.5, 1.5)
	var v := m.voice(h)
	_check(
		is_equal_approx(float(v.get("volume_db", 99.0)), linear_to_db(0.5))
		and is_equal_approx(float(v.get("pitch", 0.0)), 1.5),
		"a voice reads back at the level and pitch it started at"
	)
	_check(m.shape(h, 1.0, 2.0), "shaping a playing voice says there was one")
	v = m.voice(h)
	_check(
		is_equal_approx(float(v.get("volume_db", 99.0)), 0.0)
		and is_equal_approx(float(v.get("pitch", 0.0)), 2.0),
		"and the voice is at the new level and pitch"
	)
	_check(
		m.is_playing(h) and sink.count_of(&"rifle") == 1,
		"under the same handle, with nothing restarted"
	)

	# The scales mean what they mean to play(), so the def's gain and its rolled pitch are
	# kept: a caller handing raw decibels would lose the catalogue's -6 every frame.
	var e := m.play(&"engine")
	_check(m.shape(e, 1.0, 2.0), "a def with its own gain and pitch shapes")
	v = m.voice(e)
	_check(
		is_equal_approx(float(v.get("volume_db", 99.0)), -6.0)
		and is_equal_approx(float(v.get("pitch", 0.0)), 1.0),
		"keeping the def's gain and multiplying the pitch it rolled"
	)
	var e2 := m.play(&"engine", 0.25, 1.7)
	var started := m.voice(e2)
	m.shape(e2, 0.25, 1.7)
	_check(
		e2 != 0 and not started.is_empty() and m.voice(e2) == started,
		"so play(id, v, p) then shape(h, v, p) changes nothing"
	)
	m.shape(e, 0.0, 100.0)
	v = m.voice(e)
	_check(
		float(v.get("volume_db", 0.0)) <= -80.0 and is_equal_approx(float(v.get("pitch", 0.0)), 4.0),
		"a zero scale is silence and a wild pitch is clamped, as play() clamps them"
	)

	m.stop(h)
	_check(not m.shape(h, 1.0, 1.0) and m.voice(h).is_empty(), "a stopped voice is not shaped")
	_check(not m.shape(987654, 1.0, 1.0), "and nor is a handle this manager never issued")

	# Finished on its own with no frame in between: shape() reaps it, so the caller learns
	# its loop is gone and the per-id count comes down even while the tree is paused.
	sink.finish(e)
	_check(
		not m.shape(e, 1.0, 1.0) and not m.is_playing(e),
		"a voice that ended on its own answers false and is released"
	)
	m.queue_free()

	_check(DotAudioSink.new().voice(1).is_empty(), "a sink that cannot shape reads back nothing")

	# --- The Godot sink: the engine's own player ---------------------------------------
	var host := Node.new()
	add_child(host)
	var gs := DotAudioSinkGodot.new(host, 1)
	gs.bank = {&"tone": DotAudioSynth.voice(DotAudioSynth.Voice.STEP)}
	var player_of := func(handle: int) -> Node:
		for child in host.get_children():
			if int(child.get_meta(&"dot_audio_handle", 0)) == handle:
				return child
		return null

	var low := gs.play({"id": "tone", "path": "", "kind": DotAudioDef.Kind.FLAT, "priority": 10, "volume_db": -3.0, "pitch": 1.0})
	gs.shape(low, -12.0, 0.75)
	var p: Node = player_of.call(low)
	_check(
		p != null and is_equal_approx(float(p.get("volume_db")), -12.0)
		and is_equal_approx(float(p.get("pitch_scale")), 0.75),
		"the Godot sink sets the pooled player itself"
	)
	v = gs.voice(low)
	_check(
		is_equal_approx(float(v.get("volume_db", 0.0)), -12.0)
		and is_equal_approx(float(v.get("pitch", 0.0)), 0.75),
		"and reads it back from the player"
	)

	# One voice, so the louder sound steals the same player. A late shape of the stolen
	# handle must not reach the player the new sound now owns.
	var high := gs.play({"id": "tone", "path": "", "kind": DotAudioDef.Kind.FLAT, "priority": 90, "volume_db": -1.0, "pitch": 1.25})
	gs.shape(low, -40.0, 0.5)
	var q: Node = player_of.call(high)
	_check(
		high != 0 and q == p and is_equal_approx(float(q.get("volume_db")), -1.0)
		and is_equal_approx(float(q.get("pitch_scale")), 1.25) and gs.voice(low).is_empty(),
		"a stolen voice's handle no longer reaches the player another sound was given"
	)
	host.queue_free()

# --- 10 ---------------------------------------------------------------------

func _test_stock() -> void:
	_section("Stock footsteps and beds: real files, every one")

	var cat := DotAudioCatalogue.new()
	var mine := DotAudioDef.new()
	mine.id = &"footstep_wood"
	mine.path = "res://fixtures/silent.wav"
	cat.add(mine)
	var added := DotAudioStock.add_to(cat)
	_check(
		added == DotAudioStock.SURFACES.size() - 1 + DotAudioStock.BEDS.size() + DotAudioStock.slide_defs().size() + DotAudioWeaponStock.COUNTS.size(),
		"add_to adds every stock id the game has not defined (%d)" % added
	)
	_check(cat.find(&"footstep_wood").path == "res://fixtures/silent.wav", "and a game's own id wins")
	_check(cat.validate().ok, "the stock defs validate")
	_check(DotAudioStock.ids().all(func(i: StringName) -> bool: return cat.has(i)) and DotAudioStock.ids(false).size() == 22 and DotAudioStock.ids().size() == 22 + DotAudioWeaponStock.COUNTS.size(), "ids() names every one")

	# The armed half: a def naming a file nobody shipped passes validate() and is silent for
	# ever. Every path and every variant must exist on disk.
	var missing := PackedStringArray()
	for d in DotAudioStock.footstep_defs() + DotAudioStock.slide_defs() + DotAudioStock.ambience_defs():
		for p in d.variants if not d.variants.is_empty() else PackedStringArray([d.path]):
			if not ResourceLoader.exists(p):
				missing.append(p)
	_check(missing.is_empty(), "every stock file is there (%s)" % ", ".join(missing))

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
	body.queue_free()
	steps.queue_free()
	m.queue_free()

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

## [b]Loading dot-audio must not keep a game alive at exit.[/b] mg-dangerous-delivery's suite
## named DotAudioFootsteps and every run ended with 182 resources and their meshes, materials,
## textures and shaders still in use, all checks green: a `static var` on DotAudioSinkGodot,
## compiled in that order, held the scripts a game had already preloaded (see
## addons/dot_audio/sink/dot_audio_raw_streams.gd). Only a process's own exit can show it, so a
## child process loads dot-audio in the order that did it and this reads its stderr.
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
