class_name DotAmbienceRoof
extends RefCounted

## Whether the listener stands under a roof: a short upward ray a few times a second, with
## hysteresis so a doorway or a gap in a ceiling does not flap the mood. Feeds [method DotAmbience.set_indoors].
##
## [codeblock]
## var roof := DotAmbienceRoof.new()
## roof.mask = physics.layer_mask(&"world")
## # each frame, with the listener's eye position:
## if roof.step(delta, eye, get_world_3d().direct_space_state):
##     ambience.set_indoors(roof.roofed)
## [/codeblock]

## How far up a ceiling counts, in metres. A hangar's or a stadium's roof beyond it is the open air.
var height := 8.0

## Seconds between rays.
var interval := 0.25

## Physics layers the ray tests.
var mask := 1

## Consecutive rays that must agree before the state flips: going in is quicker than coming out.
var enter_hits := 2
var leave_misses := 4

var roofed := false

var _query := PhysicsRayQueryParameters3D.new()
var _clock := 0.0
var _run := 0


## Steps by [param delta]; casts when the interval is up. True when [member roofed] changed.
func step(delta: float, at: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	_clock += delta
	if _clock < interval:
		return false
	_clock = 0.0
	_query.from = at
	_query.to = at + Vector3.UP * height
	_query.collision_mask = mask
	return feed(space != null and not space.intersect_ray(_query).is_empty())


## One ray's answer ([param hit]: something overhead). True when [member roofed] changed.
func feed(hit: bool) -> bool:
	if hit == roofed:
		_run = 0
		return false
	_run += 1
	if _run < (enter_hits if hit else leave_misses):
		return false
	_run = 0
	roofed = hit
	return true
