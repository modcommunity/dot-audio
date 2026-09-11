class_name DotAudioSinkNull
extends DotAudioSink

## A sink that records what it would have played. The headless deployment, and the suite.
##
## [b]It is not a mock.[/b] Everything above it is the real thing: the real catalogue, the
## real voice limiting, the real cooldowns, the real priority stealing. Only the last four
## lines — the ones that would create an [AudioStreamPlayer] — are replaced, which is why
## a check against this is a check of the system rather than of a stand-in.
##
## It is also the correct sink for a dedicated server, which has no sound card and still
## has to decide what its clients are told to play.

var capacity: int = 32

var _playing: Dictionary = {}
var _log: Array[Dictionary] = []
var _next := 1


func _init(p_capacity: int = 32) -> void:
	capacity = maxi(1, p_capacity)


func play(request: Dictionary) -> int:
	if _playing.size() >= capacity:
		return 0
	var handle := _next
	_next += 1
	_playing[handle] = request.duplicate()
	_log.append(request.duplicate())
	return handle


func stop(handle: int) -> void:
	_playing.erase(handle)


func stop_all() -> void:
	_playing.clear()


func is_playing(handle: int) -> bool:
	return _playing.has(handle)


func move(handle: int, position: Vector3) -> void:
	if _playing.has(handle):
		(_playing[handle] as Dictionary)["position"] = position


func usage() -> Dictionary:
	return {"playing": _playing.size(), "capacity": capacity}


## Ends a playback the way a real one ends: on its own.
##
## A suite needs this because nothing else finishes a sound here, and a manager whose
## concurrency counts never fall is a manager that refuses everything after a while --
## which is a bug worth being able to reproduce.
func finish(handle: int) -> void:
	_playing.erase(handle)


## Everything that has been played since the last [method forget], in order.
func played() -> Array[Dictionary]:
	return _log.duplicate(true)


func played_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for r in _log:
		out.append(str(r.get("id", "")))
	return out


func count_of(id: StringName) -> int:
	var n := 0
	for r in _log:
		if str(r.get("id", "")) == String(id):
			n += 1
	return n


func forget() -> void:
	_log.clear()


func sink_name() -> String:
	return "null"
