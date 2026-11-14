extends "selftest/selftest_base.gd"

## The native footstep, slide and surf probes against the script, to the bit.
##
## One seeded world (a floor, a gap, a walkable slope, a surf ramp, a near-wall, a floor whose shapes name their
## surfaces) and one set of seeded bodies (plain, CharacterBody3D, with a `grounded` callable, with a fixed surface)
## walking, running, jumping, teleporting, leaving the tree and being freed, ticked twice a frame: rig A by the script
## ([code]use_native = false[/code]), rig B through dot-sim's [code]DotSimAudioSteps[/code] and
## [code]DotSimSurfProbe[/code]. Every [signal DotAudioFootsteps.stepped], slide and surf start and stop, every sound
## the two sinks were asked for and every body's state must be equal after every tick; then [method
## DotAudioSurfRules.is_surfing] is asked directly of both over random bodies and rules.
## With no library it says the native half was skipped; with [code]DOT_SIM_REQUIRE_NATIVE=1[/code] that fails.
##
## [codeblock]
## godot --headless --path . res://examples/steps_native_parity.tscn
## [/codeblock]

const TICKS := 420
const BODIES := 32
const PROBES := 300
const PROBE_FRAMES := 8
const SEED := 20261113
const DELTAS: Array[float] = [1.0 / 66.0, 1.0 / 33.0, 1.0 / 22.0, 1.0 / 60.0]
const SPEEDS: Array[float] = [0.0, 0.8, 1.3, 2.0, 4.0, 7.0, 12.0, 20.0, 30.0]
const HEIGHTS: Array[float] = [0.05, 0.05, 0.05, 0.3, 0.7, 1.0, 3.0, 6.0, -1.0]


## The manager's variation, the same in both rigs.
class Rolls extends RefCounted:
	func unit_at(i: int) -> float:
		return fmod(float(i) * 0.6180339887498949, 1.0)


var _rng := RandomNumberGenerator.new()
var _tick := 0
var _phase := 0
var _probe_frame := 0
var _native := false
var _rigs: Array[Dictionary] = []
var _bodies: Array = []  # one per index; null once freed
var _plan: Array[Dictionary] = []
var _probes: Array[Node3D] = []
var _diffs: Dictionary = {}
var _counts := {"step": 0, "slide": 0, "surf": 0, "play": 0, "surfing": 0, "flat": 0}
var _usec := [[0, 0, 0], [0, 0, 0]]  # per rig: footsteps, slide, surf
var _probe_answers: Array = [[], []]


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_line("dot-audio native step, slide and surf parity")
	# The native path is off by default (slower than the script); this suite is what it is kept honest by.
	DotAudioFootsteps.native_enabled = true
	DotAudioSlide.native_enabled = true
	DotAudioSurfRules.native_enabled = true
	_native = ClassDB.class_exists(&"DotSimAudioSteps") and ClassDB.class_exists(&"DotSimSurfProbe")
	if not _native:
		var required := OS.get_environment("DOT_SIM_REQUIRE_NATIVE") == "1"
		_line("dot-sim's library is not loaded: the native half is skipped")
		_check(not required, "DOT_SIM_REQUIRE_NATIVE=1 needs the library")
		_check(not DotAudioFootsteps.native_available(), "and the script says so (native_available false)")
		_finish()
		return
	_rng.seed = SEED
	_build_world()
	for r in 2:
		_rigs.append(_rig(r == 1))
	for i in BODIES:
		_spawn()
	_section("%d ticks, %d bodies, script rig against native rig" % [TICKS, BODIES])


func _physics_process(_delta: float) -> void:
	if _phase == 0:
		_step_world()
		_tick += 1
		if _tick >= TICKS:
			_report_run()
			_phase = 1
	elif _phase == 1:
		_probe_round()
		_probe_frame += 1
		if _probe_frame >= PROBE_FRAMES:
			_report_probes()
			_phase = 2
			_finish()


func _finish() -> void:
	_line("")
	_line("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- The world ----------------------------------------------------------------

func _static(at: Vector3, size: Vector3, rot: Vector3, node_name: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = node_name
	var s := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	s.shape = box
	b.add_child(s)
	add_child(b)
	b.global_position = at
	b.rotation_degrees = rot
	return b


func _build_world() -> void:
	var floor_body := _static(Vector3(0, -0.5, 0), Vector3(60, 1, 60), Vector3.ZERO, "Ground")
	floor_body.set_meta(&"surface", "wood")
	# x 30..40 is a gap.
	_static(Vector3(52, 5, 0), Vector3(22, 0.5, 30), Vector3(0, 0, 50), "Ramp_Metal")
	var slope := _static(Vector3(-48, 2, 0), Vector3(22, 0.5, 30), Vector3(0, 0, -25), "Slope")
	slope.add_to_group(&"surface_snow")
	_static(Vector3(0, 5, -45), Vector3(30, 0.5, 14), Vector3(85, 0, 0), "Wall")
	# One body of two boxes, each naming its own surface on the shape.
	var tiles := StaticBody3D.new()
	tiles.name = "Tiles"
	for k in 2:
		var s := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(15, 1, 20)
		s.shape = box
		s.position = Vector3(-7.5 + 15.0 * k, -0.5, 0)
		s.set_meta(&"surface", "grass" if k == 0 else "carpet")
		tiles.add_child(s)
	add_child(tiles)
	tiles.global_position = Vector3(0, 0, 45)


func _manager_for_rig() -> DotAudioManager:
	var cat := DotAudioCatalogue.new()
	DotAudioStock.add_to(cat, false)
	for id: StringName in cat.ids():
		cat.find(id).cooldown_ms = 0  # time-based; the two rigs run a few microseconds apart
	var m := _manager(cat, 64)
	m.roll_source = Rolls.new()
	return m


func _rig(native: bool) -> Dictionary:
	var m := _manager_for_rig()
	var rules := DotAudioSurfRules.new()
	rules.use_native = native
	var steps := DotAudioFootsteps.new()
	steps.manager = m
	steps.default_surface = &"concrete"
	steps.surf_rules = rules
	steps.use_native = native
	var slide := DotAudioSlide.new()
	slide.manager = m
	slide.use_native = native
	var surf := DotAudioSurf.new()
	surf.manager = m
	surf.rules = rules
	surf.use_native = native
	var log: Array = []
	for n: Node in [steps, slide, surf]:
		add_child(n)
		n.set_physics_process(false)
	steps.stepped.connect(func(b: Node3D, s: StringName, l: float) -> void:
		log.append(["step", _tick, b.get_meta(&"i"), s, l]))
	slide.slide_started.connect(func(b: Node3D, s: StringName) -> void: log.append(["slide+", _tick, b.get_meta(&"i"), s]))
	slide.slide_stopped.connect(func(b: Node3D) -> void: log.append(["slide-", _tick, b.get_meta(&"i")]))
	surf.slide_started.connect(func(b: Node3D, s: StringName) -> void: log.append(["surf+", _tick, b.get_meta(&"i"), s]))
	surf.slide_stopped.connect(func(b: Node3D) -> void: log.append(["surf-", _tick, b.get_meta(&"i")]))
	return {"m": m, "rules": rules, "steps": steps, "slide": slide, "surf": surf, "log": log, "seen": 0}


# --- The bodies ---------------------------------------------------------------

func _spawn() -> void:
	var i := _bodies.size()
	var kind := i % 4
	var b: Node3D
	if kind == 1:
		var cb := CharacterBody3D.new()
		var s := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.8
		s.shape = cap
		s.position = Vector3(0, 0.9, 0)
		cb.add_child(s)
		b = cb
	else:
		b = Node3D.new()
	b.set_meta(&"i", i)
	add_child(b)
	b.global_position = Vector3(_rng.randf_range(-65, 65), 0.05, _rng.randf_range(-60, 60))
	_bodies.append(b)
	_plan.append({"dir": Vector3.RIGHT, "speed": 0.0, "y": 0.05})
	var opts := {}
	if kind == 2:
		opts["grounded"] = func() -> bool: return (_tick / 13 + i) % 4 != 0
	elif kind == 3:
		opts["surface"] = &"metal" if i % 8 == 3 else &""
		opts["loudness"] = 0.7
	for rig in _rigs:
		(rig["steps"] as DotAudioFootsteps).track(b, opts)


func _sliding(b: Node3D) -> bool:
	return (int(b.get_meta(&"i")) * 7 + _tick / 9) % 3 != 0


func _live() -> Array:
	var out: Array = []
	for b: Variant in _bodies:
		if b != null:
			out.append(b)
	return out


func _move(i: int, dt: float) -> void:
	var b: Node3D = _bodies[i]
	if b == null or not b.is_inside_tree():
		return
	var p: Dictionary = _plan[i]
	if (_tick + i * 5) % 30 == 0:
		var a := _rng.randf() * TAU
		p["dir"] = Vector3(cos(a), 0, sin(a))
		p["speed"] = SPEEDS[_rng.randi() % SPEEDS.size()]
		var h: float = HEIGHTS[_rng.randi() % HEIGHTS.size()]
		p["y"] = _rng.randf_range(0.0, 12.0) if h < 0.0 else h
	var pos := b.global_position + (p["dir"] as Vector3) * float(p["speed"]) * dt
	pos.y = float(p["y"])
	if _rng.randi() % 150 == 0:
		pos.x += 10.0
	if absf(pos.x) > 70.0:
		pos.x = -signf(pos.x) * 65.0
	if absf(pos.z) > 70.0:
		pos.z = -signf(pos.z) * 65.0
	b.global_position = pos


# --- One tick -----------------------------------------------------------------

func _configure(rig: Dictionary) -> void:
	var t := _tick
	var steps: DotAudioFootsteps = rig["steps"]
	var slide: DotAudioSlide = rig["slide"]
	var surf: DotAudioSurf = rig["surf"]
	var rules: DotAudioSurfRules = rig["rules"]
	(rig["m"] as DotAudioManager).listener_position = Vector3(cos(t * 0.02) * 25.0, 1.0, sin(t * 0.02) * 25.0)
	steps.hear_distance = 0.0 if t < 120 else (12.0 if t >= 240 and t < 300 else 36.0)
	steps.surf_rules = null if t >= 300 and t < 320 else rules
	rules.mute_steps = not (t >= 200 and t < 230)
	rules.enabled = not (t >= 260 and t < 280)
	rules.probe = 2.5 if t >= 140 and t < 160 else 1.2
	rules.mask = 0 if t >= 170 and t < 176 else 0xFFFFFFFF
	steps.ground_probe = 1.5 if t >= 330 and t < 360 else 0.6
	slide.enabled = not (t >= 150 and t < 170)
	slide.reach = 0.0 if t >= 100 and t < 140 else (15.0 if t >= 180 and t < 220 else -1.0)
	surf.reach = 20.0 if t >= 360 else -1.0
	surf.enabled = not (t >= 380 and t < 390)


func _step_world() -> void:
	var dt: float = 0.0 if _tick % 97 == 96 else DELTAS[(_tick / 40) % DELTAS.size()]
	# Lives: freed, out of the tree and back, new, untracked.
	if _tick == 50 or _tick == 211:
		var i := 3 if _tick == 50 else 10
		(_bodies[i] as Node).free()
		_bodies[i] = null
	if _tick == 80:
		remove_child(_bodies[5])
	if _tick == 110:
		add_child(_bodies[5])
	if _tick == 90 or _tick == 250:
		_spawn()
	if _tick == 130:
		for rig in _rigs:
			(rig["steps"] as DotAudioFootsteps).untrack(_bodies[7])
	for i in _bodies.size():
		_move(i, maxf(dt, 1.0 / 66.0))
	var live := _live()
	for r: int in ([0, 1] if _tick % 2 == 0 else [1, 0]):  # neither rig always runs warm
		var rig := _rigs[r]
		_configure(rig)
		if _tick % 10 == 0:
			(rig["slide"] as DotAudioSlide).keep(live, _sliding)
			(rig["surf"] as DotAudioSurf).keep_surfers(live)
		var us: Array = _usec[r]
		var t0 := Time.get_ticks_usec()
		(rig["steps"] as DotAudioFootsteps)._physics_process(dt)
		var t1 := Time.get_ticks_usec()
		(rig["slide"] as DotAudioSlide)._physics_process(dt)
		var t2 := Time.get_ticks_usec()
		(rig["surf"] as DotAudioSurf)._physics_process(dt)
		var t3 := Time.get_ticks_usec()
		us[0] += t1 - t0
		us[1] += t2 - t1
		us[2] += t3 - t2
	_compare()


func _diff(what: String, detail: String) -> void:
	if not _diffs.has(what):
		_diffs[what] = "tick %d: %s" % [_tick, detail]


func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


func _compare() -> void:
	var a := _rigs[0]
	var b := _rigs[1]
	var la: Array = a["log"]
	var lb: Array = b["log"]
	if la.size() != lb.size():
		_diff("signals", "%d against %d" % [la.size(), lb.size()])
	for k in range(int(a["seen"]), mini(la.size(), lb.size())):
		var ea: Array = la[k]
		if not _same(ea, lb[k]):
			_diff("signals", "%s against %s" % [ea, lb[k]])
		var kind := String(ea[0]).trim_suffix("+").trim_suffix("-")
		_counts[kind] = int(_counts[kind]) + 1
	a["seen"] = la.size()
	b["seen"] = lb.size()
	var sa := (a["m"] as DotAudioManager).sink as DotAudioSinkNull
	var sb := (b["m"] as DotAudioManager).sink as DotAudioSinkNull
	var pa := sa.played()
	var pb := sb.played()
	if pa != pb:
		_diff("plays", "%s against %s" % [pa, pb])
	_counts["play"] = int(_counts["play"]) + pa.size()
	sa.forget()
	sb.forget()
	_compare_state("footstep state", (a["steps"] as DotAudioFootsteps)._bodies, (b["steps"] as DotAudioFootsteps)._bodies,
		["last", "travelled", "air", "grounded"])
	for node in ["slide", "surf"]:
		_compare_state(node + " state", (a[node] as DotAudioSlide)._bodies, (b[node] as DotAudioSlide)._bodies,
			["last", "on", "handle", "surface"])


func _compare_state(what: String, da: Dictionary, db: Dictionary, fields: Array) -> void:
	if da.size() != db.size():
		_diff(what, "%d bodies against %d" % [da.size(), db.size()])
		return
	for key: Variant in da:
		if not db.has(key):
			_diff(what, "a body only the script tracks")
			return
		var sa: Dictionary = da[key]
		var sb: Dictionary = db[key]
		for f: String in fields:
			if sa.has(f) != sb.has(f) or (sa.has(f) and not _same(sa[f], sb[f])):
				_diff(what, "%s: %s against %s" % [f, sa.get(f), sb.get(f)])


func _report_run() -> void:
	for what in ["signals", "plays", "footstep state", "slide state", "surf state"]:
		_check(not _diffs.has(what), "%s equal after every tick %s" % [what, _diffs.get(what, "")])
	_check(int(_counts["step"]) > 50 and int(_counts["slide"]) > 20 and int(_counts["surf"]) > 2,
		"over a run that steps, slides and surfs (%d steps, %d slide and %d surf starts and stops, %d plays)" % [
			_counts["step"], _counts["slide"], _counts["surf"], _counts["play"]])
	var steps_b: DotAudioFootsteps = _rigs[1]["steps"]
	var slide_b: DotAudioSlide = _rigs[1]["slide"]
	var rules_b: DotAudioSurfRules = _rigs[1]["rules"]
	_check(steps_b._native != null and slide_b._native != null and rules_b._native != null,
		"and rig B really ran natively (footsteps, slide and surf probe)")
	_check((_rigs[0]["steps"] as DotAudioFootsteps)._native == null and (_rigs[0]["rules"] as DotAudioSurfRules)._native == null,
		"while rig A never did")
	for k in 3:
		_line("   time  %s: script %.1f us/tick, native %.1f us/tick (%d bodies)" % [
			["footsteps", "slide", "surf"][k], float(_usec[0][k]) / TICKS, float(_usec[1][k]) / TICKS, BODIES])
	_section("is_surfing asked directly, %d bodies over %d frames of random rules" % [PROBES, PROBE_FRAMES])
	for k in PROBES:
		var p: Node3D = CharacterBody3D.new() if k % 2 == 0 else Node3D.new()
		if k % 2 == 0:
			var s := CollisionShape3D.new()
			s.shape = SphereShape3D.new()
			p.add_child(s)
		add_child(p)
		_probes.append(p)


func _probe_round() -> void:
	var probe: float = [0.3, 1.2, 2.5, 6.0][_rng.randi() % 4]
	var lo: float = [0.02, 0.0, 0.3, -1.0][_rng.randi() % 4]
	var hi: float = [0.707, 0.95, 0.5, 1.0][_rng.randi() % 4]
	var mask: int = [0xFFFFFFFF, 1, 2, 0][_rng.randi() % 4]
	for k in _probes.size():
		var p := _probes[k]
		if k % 3 == 0:
			# Just above the 50 degree ramp (centre 52, 5; half-thickness 0.25), surfing or not by the rules.
			var x := _rng.randf_range(46.0, 58.0)
			p.global_position = Vector3(x, 5.0 + (x - 52.0) * tan(deg_to_rad(50.0)) + 0.39 + _rng.randf_range(0.0, 1.5),
				_rng.randf_range(-14, 14))
		else:
			p.global_position = Vector3(_rng.randf_range(-70, 70), _rng.randf_range(-1, 14), _rng.randf_range(-60, 60))
	var order: Array = range(_probes.size())
	for k in order.size():
		order.append(order[_rng.randi() % order.size()])  # some asked twice: the frame cache
	for r in 2:
		var rules: DotAudioSurfRules = _rigs[r]["rules"]
		rules.probe = probe
		rules.min_normal_y = lo
		rules.max_normal_y = hi
		rules.mask = mask
		var out: Array = _probe_answers[r]
		for k: int in order:
			out.append(rules.is_surfing(_probes[k]))


func _report_probes() -> void:
	var a: Array = _probe_answers[0]
	var b: Array = _probe_answers[1]
	var first := -1
	var yes := 0
	for k in mini(a.size(), b.size()):
		if a[k] != b[k] and first < 0:
			first = k
		if a[k]:
			yes += 1
	_check(a.size() == b.size() and first < 0, "every answer equal (%d asked, first difference %d)" % [a.size(), first])
	_check(yes > 10 and yes < a.size() - 10, "and both answers occur (%d surfing of %d)" % [yes, a.size()])
