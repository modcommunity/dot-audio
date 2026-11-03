extends "selftest_stock.gd"

## The layered-shot sections of audio_selftest.gd: layers by distance, tail by enclosure.


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
	_test_tail_weights()
	_test_shot_closet(shot, p, enc)
	_test_shot_playback(shot, p)


func _test_tail_weights() -> void:
	var W := DotAudioEnclosure.tail_weights
	var norm_ok := true
	var mono_ok := true
	var prev_small := 2.0
	for sz in [0.5, 1.0, 1.8, 3.0, 4.5, 7.0, 10.0, 17.0, 24.0, 60.0]:
		for op in [0.0, 0.1, 0.3, 0.5, 0.8, 1.0]:
			var ww: Dictionary = W.call(sz, op)
			var sq := 0.0
			for k in ww:
				sq += float(ww[k]) * float(ww[k])
			norm_ok = norm_ok and absf(sq - 1.0) < 0.001
		var small_w: float = W.call(sz, 0.0)[&"small"]
		mono_ok = mono_ok and small_w <= prev_small + 0.0001
		prev_small = small_w
	_check(norm_ok, "tail weights are equal power: squares sum to 1 over size and openness")
	_check(mono_ok, "the small tail only fades as the room grows")
	var closet: Dictionary = W.call(1.2, 0.0)
	var corridor: Dictionary = W.call(3.2, 0.03)
	var field: Dictionary = W.call(40.0, 0.9)
	var openroom: Dictionary = W.call(12.0, 0.33)
	var hall_w: Dictionary = W.call(30.0, 0.0)
	_check(closet[&"small"] > 0.99 and field[&"outdoor"] > 0.99 and hall_w[&"hall"] > 0.99, "a closet is all small, a field all outdoor, a hall all hall")
	_check(corridor[&"small"] > 0.3 and corridor[&"medium"] > 0.3 and corridor[&"hall"] == 0.0 and corridor[&"outdoor"] < 0.05, "a corridor crossfades small and medium")
	_check(openroom[&"outdoor"] > 0.2 and openroom[&"outdoor"] < 0.8 and openroom[&"large"] > 0.3, "an open room is a blend of its class and outdoor")
	var near_edge: Dictionary = W.call(DotAudioEnclosure.CLASS_CENTRES[&"small"] * 1.05, 0.0)
	_check(near_edge[&"small"] > 0.95 and near_edge[&"medium"] < 0.3, "a small step in size gives a small step in weights (no snap)")
	var tight_closet := DotAudioEnclosure.tightness(1.2, 0.0)
	_check(tight_closet == 1.0 and DotAudioEnclosure.tightness(12.0, 0.0) == 0.0 and DotAudioEnclosure.tightness(1.2, 0.9) == 0.0 and DotAudioEnclosure.tightness(5.0, 0.0) > 0.0 and DotAudioEnclosure.tightness(5.0, 0.0) < 1.0, "tightness is 1 in a closet and 0 in a hall or outdoors")


func _test_shot_closet(shot: DotShotDef, p: DotShotPlayer, enc: DotAudioEnclosure) -> void:
	p.pitch_jitter = 0.0
	p.gain_jitter_db = 0.0
	_sweep(enc, 1.5)
	var in_closet := p.plan(shot.id, Vector3(5, 0, 0))
	_sweep(enc, 40.0, 2)
	var in_field := p.plan(shot.id, Vector3(5, 0, 0))
	var body_closet: Dictionary = in_closet.filter(func(e: Dictionary) -> bool: return e.layer == &"body")[0]
	var body_field: Dictionary = in_field.filter(func(e: Dictionary) -> bool: return e.layer == &"body")[0]
	_check(body_closet.volume > body_field.volume * 1.1 and body_closet.pitch < body_field.pitch * 0.95, "in a closet the shot is louder and the body sits lower")
	var tail_closet := 0.0
	for e in in_closet:
		if String(e.layer).begins_with("tail_"):
			tail_closet += e.volume
	var tail_field := 0.0
	for e in in_field:
		if String(e.layer).begins_with("tail_"):
			tail_field += e.volume
	_check(tail_closet > 1.2 and tail_field < tail_closet * 0.8, "the tail layer is heavier in a closet than outdoors (%.2f vs %.2f)" % [tail_closet, tail_field])
	p.pitch_jitter = 0.03
	p.gain_jitter_db = 1.5
	_sweep(enc, 2.0)
	_check(absf(enc.comb_delay_ms() - 2.0 * 2.0 / 343.0 * 1000.0) < 0.5, "the comb delay follows the measured size (a 2 m room is %.1f ms)" % enc.comb_delay_ms())
	var h := DotAudioEnclosure.fibonacci(24)
	_check(h.size() == 24 and absf(h[0].length() - 1.0) < 0.001 and absf(h[10].length() - 1.0) < 0.001, "the rays are unit directions")


func _test_shot_playback(shot: DotShotDef, p: DotShotPlayer) -> void:
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


func _test_shot_tail_cap() -> void:
	_section("Layered shots: a rapid-fire weapon keeps a bounded number of room tails")
	var m := _manager(DotAudioCatalogue.new(), 32)
	var enc := DotAudioEnclosure.new()
	enc.send_bus = &"Master"
	add_child(enc)
	_sweep(enc, 30.0)
	var p := DotShotPlayer.new()
	p.manager = m
	p.enclosure = enc
	add_child(p)
	p.seed_rolls(3)
	var gun := DotAudioShotStock.shot(&"minigun")
	var registered := p.register(gun).ok
	_check(registered and enc.tail_class == &"hall", "a minigun in a hall registers with the hall tail")
	var rounds := 0
	var peak := 0
	for i in 150:
		var fired := p.fire(gun.id, Vector3(3, 0, 0))
		rounds += 1 if fired.ok else 0
		peak = maxi(peak, p.tail_voices())
		p.advance(0.04)
	_check(rounds == 150 and peak <= p.rules.tail_voices and peak > 1, "25 rounds a second for 6 s: at most %d hall tails at once, saw %d" % [p.rules.tail_voices, peak])
	var plain := DotShotPlayer.new()
	plain.manager = m
	plain.enclosure = enc
	plain.rules.tail_voices = 0
	add_child(plain)
	var unlimited := 0
	for i in 150:
		var _r := plain.fire(gun.id, Vector3(3, 0, 0))
		unlimited = maxi(unlimited, plain.tail_voices())
		plain.advance(0.04)
	_check(unlimited == 0 or unlimited > peak, "with the cap off the same fire stacks more (%d) than with it (%d)" % [unlimited, peak])
	var crack := p.fire(gun.id, Vector3(3, 0, 0))
	_check(crack.ok and int(crack.value) >= 2, "a capped round still plays its crack and body")
	_check(p.rules.set_cvar("snd_shot_tail_voices", "99") and p.rules.tail_voices == 16 and not p.rules.set_cvar("snd_shot_tail_voices", "x"), "the cap cvar is clamped to 0-16")
