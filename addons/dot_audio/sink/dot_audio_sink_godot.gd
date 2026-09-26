class_name DotAudioSinkGodot
extends DotAudioSink

## The engine sink: a fixed pool of players, reused, with priority stealing.
##
## [b]A fixed pool is the whole point.[/b] Godot's obvious spelling — create an
## [AudioStreamPlayer], play it, `queue_free` on finished — has no ceiling at all, and a
## firefight with twenty players is a hundred nodes created and destroyed per second.
## That is allocation churn in the frame where the frame is already busy, and on the web,
## where there are no threads to hide it in, it is a visible hitch every time something
## happens.
##
## So: [member capacity] players, created once, never freed. When they are all busy the
## lowest-priority one is stopped and reused — and if nothing is lower, the new sound is
## refused rather than the oldest being cut. A gunshot losing to a footstep because the
## footstep started first is the failure mode of every fixed pool with no priority.

## The node new players are parented to. Set by the manager.
var host: Node = null

var capacity: int = 32

## Streams to fall back on when a def's path resolves to nothing.
##
## [code]{String path: AudioStream}[/code] and [code]{StringName id: AudioStream}[/code],
## in one dictionary — a path entry stands in for one variant, an id entry for the def as
## a whole. [DotAudioSynth.bank] builds both; anything that can produce an [AudioStream]
## can fill it, and nothing here cares where one came from.
##
## [b]It is consulted AFTER the filesystem, and that order is the design.[/b] A deployment
## with no audio files hears the stand-ins; the moment a real file exists at the path the
## def already names, that file wins and the entry beside it goes quiet without anybody
## editing a line. A bank that outranked a shipped asset would be a placeholder somebody
## has to remember to remove, which is how placeholders ship.
##
## [b]Empty by default, so this changes nothing for anyone who does not set it.[/b] The
## path above is untouched: a game that ships its audio never allocates this dictionary and
## never does a lookup in it.
var bank: Dictionary = {}

var _free: Array[Node] = []
var _busy: Dictionary = {}
var _next := 1

## Looping copies of streams, keyed by the stream they were made from. See [method _looped].
var _loop_copies: Dictionary = {}


func _init(p_host: Node = null, p_capacity: int = 32) -> void:
	host = p_host
	capacity = maxi(1, p_capacity)


func play(request: Dictionary) -> int:
	if host == null or not is_instance_valid(host):
		return 0

	var path := str(request.get("path", ""))
	var id := StringName(request.get("id", ""))

	var stream: AudioStream = null

	if not path.is_empty() and ResourceLoader.exists(path):
		stream = load(path) as AudioStream

	# Only once the filesystem has had its turn. See `bank`.
	if stream == null and not bank.is_empty():
		if bank.has(path):
			stream = bank[path] as AudioStream
		elif bank.has(id):
			stream = bank[id] as AudioStream

	if stream == null:
		# Not an error. A client that has not downloaded a pack yet, or a deployment that
		# ships no audio at all, is a legitimate configuration -- and an effect never
		# changes the simulation, so dropping one is always safe. Logged at debug so it is
		# findable and does not turn a soundless build into a wall of red.
		DotLog.debug("audio", "no such stream", {"path": path, "id": String(id)})
		return 0

	# [b]Honoured here, and it was not until 2026-09-25.[/b] The manager has always put
	# `looping` in the request and nothing read it, so a looping def — an engine hum, an
	# ambience bed — played once and stopped, and a game built its engine as a pulse to
	# work round it.
	var looping := bool(request.get("looping", false))
	if looping:
		stream = _looped(stream)

	var kind := int(request.get("kind", DotAudioDef.Kind.FLAT))
	var player := _take(kind, int(request.get("priority", 50)))
	if player == null:
		return 0

	player.stream = stream
	player.bus = str(request.get("bus", "Master"))
	player.volume_db = float(request.get("volume_db", 0.0))
	player.pitch_scale = float(request.get("pitch", 1.0))

	match kind:
		DotAudioDef.Kind.POSITIONAL_3D:
			var p3 := player as AudioStreamPlayer3D
			p3.global_position = request.get("position", Vector3.ZERO)
			p3.unit_size = float(request.get("unit_size", 10.0))
			p3.max_distance = float(request.get("max_distance", 0.0))
		DotAudioDef.Kind.POSITIONAL_2D:
			var p2 := player as AudioStreamPlayer2D
			var pos: Vector3 = request.get("position", Vector3.ZERO)
			# A 2D game's world is the XZ plane everywhere else in this family -- dot-npc
			# maps one onto it so its senses and navigation run unchanged -- so the same
			# convention here means one request shape serves both.
			p2.global_position = Vector2(pos.x, pos.z)
			p2.max_distance = float(request.get("max_distance", 2000.0))

	var handle := _next
	_next += 1
	_busy[handle] = {
		"player": player,
		"priority": int(request.get("priority", 50)),
		"id": str(request.get("id", "")),
		"looping": looping,
	}
	player.set_meta(&"dot_audio_handle", handle)
	player.play()
	return handle


## A copy of [param stream] that loops, or [param stream] itself when it already does.
##
## [b]A copy, never the stream itself.[/b] What [code]load()[/code] returns is the cached
## resource every other caller of that path shares, and a [member bank] entry is shared by
## every play of that id — so setting [code]loop_mode[/code] on it in place would make the
## next ONE-SHOT of the same sound loop for ever. One copy per source, kept, so a looping
## sound started a hundred times is one duplicate rather than a hundred.
##
## [b]Natively where the stream can[/b]: [AudioStreamWAV] by its loop points (a baked
## synth voice is one), and anything with a [code]loop[/code] property (Ogg Vorbis, MP3).
## Anything else is returned unchanged and loops by restarting on
## [signal AudioStreamPlayer.finished] — see [method _on_finished] — which costs a mix
## buffer of silence at the seam and is the answer for a stream type this does not know.
func _looped(stream: AudioStream) -> AudioStream:
	if _loop_copies.has(stream):
		return _loop_copies[stream] as AudioStream

	var out: AudioStream = stream

	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			var frames := _wav_frames(wav)
			if frames > 0:
				var copy := wav.duplicate() as AudioStreamWAV
				copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
				copy.loop_begin = 0
				copy.loop_end = frames
				out = copy
	elif "loop" in stream and not bool(stream.get("loop")):
		var copy := stream.duplicate() as AudioStream
		copy.set("loop", true)
		out = copy

	_loop_copies[stream] = out
	return out


## How many sample frames a WAV holds, or 0 when that cannot be known from its bytes.
##
## Zero sends it to the restart fallback rather than guessing: a loop end past the data
## reads past the buffer and one short of it clips the tail every lap.
static func _wav_frames(wav: AudioStreamWAV) -> int:
	var channels := 2 if wav.stereo else 1
	match wav.format:
		AudioStreamWAV.FORMAT_8_BITS:
			return wav.data.size() / channels
		AudioStreamWAV.FORMAT_16_BITS:
			return wav.data.size() / (2 * channels)
		_:
			return int(round(wav.get_length() * float(wav.mix_rate)))


func _take(kind: int, priority: int) -> Node:
	for i in range(_free.size()):
		if _kind_of(_free[i]) == kind:
			return _free.pop_at(i)

	if _free.size() + _busy.size() < capacity:
		return _make(kind)

	# Steal, but only downwards. Stopping something more important than what is arriving
	# is worse than not playing the new thing at all.
	var worst := -1
	var worst_priority := priority
	for h in _busy.keys():
		var entry: Dictionary = _busy[h]
		if _kind_of(entry["player"]) != kind:
			continue
		if int(entry["priority"]) < worst_priority:
			worst_priority = int(entry["priority"])
			worst = h
	if worst < 0:
		return null
	var stolen: Node = (_busy[worst] as Dictionary)["player"]
	_busy.erase(worst)
	stolen.call("stop")
	return stolen


func _make(kind: int) -> Node:
	var player: Node
	match kind:
		DotAudioDef.Kind.POSITIONAL_3D:
			player = AudioStreamPlayer3D.new()
		DotAudioDef.Kind.POSITIONAL_2D:
			player = AudioStreamPlayer2D.new()
		_:
			player = AudioStreamPlayer.new()
	host.add_child(player)
	player.connect("finished", _on_finished.bind(player))
	return player


func _kind_of(player: Node) -> int:
	if player is AudioStreamPlayer3D:
		return DotAudioDef.Kind.POSITIONAL_3D
	if player is AudioStreamPlayer2D:
		return DotAudioDef.Kind.POSITIONAL_2D
	return DotAudioDef.Kind.FLAT


func _on_finished(player: Node) -> void:
	var handle := int(player.get_meta(&"dot_audio_handle", 0))

	# A looping sound whose stream could not be told to loop. It stays busy under the
	# same handle, so the manager's concurrency count and the caller's handle both stay
	# right, and it goes round again. See [method _looped].
	var entry: Dictionary = _busy.get(handle, {})
	if bool(entry.get("looping", false)) and entry.get("player") == player:
		player.call("play")
		return

	_busy.erase(handle)
	# Returned to the pool rather than freed. The whole reason the pool exists.
	if not _free.has(player):
		_free.append(player)


func stop(handle: int) -> void:
	if not _busy.has(handle):
		return
	var entry: Dictionary = _busy[handle]
	var player: Node = entry["player"]
	_busy.erase(handle)
	player.call("stop")
	if not _free.has(player):
		_free.append(player)


func stop_all() -> void:
	for h in _busy.keys().duplicate():
		stop(h)


func is_playing(handle: int) -> bool:
	if not _busy.has(handle):
		return false
	var player: Node = (_busy[handle] as Dictionary)["player"]
	return bool(player.call("is_playing"))


func move(handle: int, position: Vector3) -> void:
	if not _busy.has(handle):
		return
	var player: Node = (_busy[handle] as Dictionary)["player"]
	if player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).global_position = position
	elif player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).global_position = Vector2(position.x, position.z)


func usage() -> Dictionary:
	return {"playing": _busy.size(), "capacity": capacity}


func sink_name() -> String:
	# The bank is named here because "the sound I expected was a different sound" is
	# otherwise indistinguishable from "the file I added is not being read", and this
	# string is what a `describe()` and a bug report carry.
	return "godot" if bank.is_empty() else "godot+bank(%d)" % bank.size()
