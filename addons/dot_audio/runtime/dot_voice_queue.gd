class_name DotVoiceQueue
extends Node

## One voice at a time for announcer and medal lines, so they do not talk over each other.
##
## [codeblock]
## var voice := DotVoiceQueue.new()
## add_child(voice)
## voice.setup(audio)
## voice.say(&"medal_headshot", 40)
## voice.say(&"flag_captured", 80)   # waits its turn, or cuts in if it is far more urgent
## [/codeblock]
##
## A line starts at once when nothing is speaking. While one speaks, a line that outranks it
## by [member interrupt_margin] cuts it off; any other waits, highest priority first and then
## in the order said. A line already waiting is not queued twice, the queue is capped (the
## lowest priority goes first) and a line that waited longer than [member max_wait] is
## dropped, since an announcement that late is noise. The end of a line is read from
## [method DotAudioManager.is_playing], so it works the same on the null sink.

const PLAYING := &"playing"
const INTERRUPTED := &"interrupted"
const QUEUED := &"queued"
const DUPLICATE := &"duplicate"
const DROPPED := &"dropped"

## How much more urgent a line must be to cut off the one speaking.
@export var interrupt_margin: int = 20
@export_range(1, 32, 1) var max_queued: int = 4
## Seconds a line may wait before it is stale and dropped.
@export var max_wait: float = 3.0
## Silence between two lines.
@export var gap: float = 0.12

var _manager: DotAudioManager = null
var _handle: int = 0
var _current_priority: int = 0
var _gap_left: float = 0.0
var _now: float = 0.0
## Each entry: {id, priority, volume, at}.
var _queue: Array = []


func setup(manager: DotAudioManager) -> void:
	_manager = manager


## Says [param id], or queues it. Returns what happened to it (PLAYING, INTERRUPTED, QUEUED,
## DUPLICATE or DROPPED).
func say(id: StringName, priority: int = 50, volume_scale: float = 1.0) -> StringName:
	if _manager == null:
		return DROPPED
	if not _speaking() and _gap_left <= 0.0:
		return PLAYING if _start(id, priority, volume_scale) else DROPPED
	if _speaking() and priority >= _current_priority + interrupt_margin:
		_manager.stop(_handle)
		_handle = 0
		return INTERRUPTED if _start(id, priority, volume_scale) else DROPPED
	for entry in _queue:
		if entry["id"] == id:
			entry["priority"] = maxi(int(entry["priority"]), priority)
			return DUPLICATE
	if _queue.size() >= max_queued:
		var worst := _worst()
		if int(_queue[worst]["priority"]) >= priority:
			return DROPPED
		_queue.remove_at(worst)
	_queue.append({"id": id, "priority": priority, "volume": volume_scale, "at": _now})
	return QUEUED


func is_speaking() -> bool:
	return _speaking()


## The waiting lines in the order they will speak.
func queued_ids() -> Array:
	var rest := _queue.duplicate()
	var out: Array = []
	while not rest.is_empty():
		var best := 0
		for i in range(1, rest.size()):
			if int(rest[i]["priority"]) > int(rest[best]["priority"]):
				best = i
		out.append(rest[best]["id"])
		rest.remove_at(best)
	return out


func clear() -> void:
	_queue.clear()


func _process(delta: float) -> void:
	tick(delta)


## Advances time by [param delta]; [method _process] calls it, a suite calls it by hand.
func tick(delta: float) -> void:
	_now += delta
	if _manager == null:
		return
	if _handle != 0 and not _manager.is_playing(_handle):
		_handle = 0
		_gap_left = gap
	if _speaking():
		return
	_gap_left = maxf(0.0, _gap_left - delta)
	if _gap_left > 0.0:
		return
	while not _queue.is_empty():
		var best := _best()
		var entry: Dictionary = _queue[best]
		_queue.remove_at(best)
		if _now - float(entry["at"]) > max_wait:
			continue
		if _start(entry["id"], int(entry["priority"]), float(entry["volume"])):
			return


func _speaking() -> bool:
	return _handle != 0 and _manager != null and _manager.is_playing(_handle)


func _start(id: StringName, priority: int, volume_scale: float) -> bool:
	_handle = _manager.play(id, volume_scale)
	_current_priority = priority
	return _handle != 0


## Highest priority, earliest first.
func _best() -> int:
	var best := 0
	for i in range(1, _queue.size()):
		if int(_queue[i]["priority"]) > int(_queue[best]["priority"]):
			best = i
	return best


## Lowest priority, latest first.
func _worst() -> int:
	var worst := 0
	for i in range(1, _queue.size()):
		if int(_queue[i]["priority"]) <= int(_queue[worst]["priority"]):
			worst = i
	return worst
