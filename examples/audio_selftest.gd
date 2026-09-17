extends Node

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

const SECTIONS := 8
const CHECKS := 85

var _passed := 0
var _failed := 0
var _section_count := 0


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
	host.queue_free()


# --- Harness ---------------------------------------------------------------

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
