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

## Streams decoded from a file's own bytes, by path. See [method stream_at]. In a file of its
## own, never a `static var` here: one here kept a game's whole run alive at exit (see that file).
const _RAW := preload("dot_audio_raw_streams.gd")

## How long a path that resolved to nothing is taken at its word before the disk is asked again.
const ABSENT_RECHECK_MS := 2000

## What each path resolved to, so a play is a lookup and not a read of the import marker:
## resolving from disk every time was a millisecond a shot. Per sink, never static, so the
## streams go when the manager does and nothing is still in use at exit.
var _resolved: Dictionary = {}

## When a path last resolved to nothing. Asked again after [constant ABSENT_RECHECK_MS], so a
## file that arrives mid-session (a pack still downloading) still wins over the bank.
var _absent_ms: Dictionary = {}

## The longest compressed stream that is decoded to PCM after its first play, in seconds.
## Zero turns the decoding off. See [method _pcm_for].
var pcm_max_seconds: float = 4.0

## What the decoded copies may hold together. Past it a stream keeps playing compressed.
var pcm_budget_bytes: int = 64 * 1024 * 1024

const _PCM := preload("dot_audio_pcm.gd")

## Decodes running at once: the worker pool is shared with whatever else the game threads.
const PCM_JOBS := 2

var _pcm: Dictionary = {}
var _pcm_copies: Dictionary = {}
var _pcm_jobs: Dictionary = {}
var _pcm_skipped: Dictionary = {}
var _pcm_bytes := 0


func _init(p_host: Node = null, p_capacity: int = 32) -> void:
	host = p_host
	capacity = maxi(1, p_capacity)


func play(request: Dictionary) -> int:
	if host == null or not is_instance_valid(host):
		return 0

	var stream := _stream_for(request)
	if stream == null:
		return 0

	var looping := bool(request.get("looping", false))
	if looping:
		stream = _looped(stream)

	var kind := int(request.get("kind", DotAudioDef.Kind.FLAT))
	var player := _take(kind, int(request.get("priority", 50)))
	if player == null:
		return 0

	player.stream = stream
	_configure(player, kind, request)
	# A decoded copy is stored with headroom and made up here. See the decoder.
	var trim_db := _PCM.HEADROOM_DB if stream is AudioStreamWAV and _pcm_copies.has(stream) else 0.0
	if trim_db != 0.0:
		player.set(&"volume_db", float(request.get("volume_db", 0.0)) + trim_db)

	var handle := _next
	_next += 1
	_busy[handle] = {
		"player": player,
		"priority": int(request.get("priority", 50)),
		"id": str(request.get("id", "")),
		"looping": looping,
		"trim_db": trim_db,
	}
	player.set_meta(&"dot_audio_handle", handle)
	player.play()
	return handle


## The stream for a request: by path, then the bank; null (and a debug line) when neither has it.
func _stream_for(request: Dictionary) -> AudioStream:
	var path := str(request.get("path", ""))
	var id := StringName(request.get("id", ""))
	var stream: AudioStream = null
	if not path.is_empty():
		stream = _resolved.get(path) as AudioStream
		if stream == null:
			var now := Time.get_ticks_msec()
			if not _absent_ms.has(path) or now - int(_absent_ms[path]) >= ABSENT_RECHECK_MS:
				stream = stream_at(path)
				if stream != null:
					_resolved[path] = stream
					_absent_ms.erase(path)
				else:
					_absent_ms[path] = now
		if stream != null and not bool(request.get("looping", false)):
			stream = _pcm_for(path, stream)
	# Only once the filesystem has had its turn. See `bank`.
	if stream == null and not bank.is_empty():
		if bank.has(path):
			stream = bank[path] as AudioStream
		elif bank.has(id):
			stream = bank[id] as AudioStream
	if stream == null:
		# A pack not downloaded yet, or a build with no audio, is legitimate and never changes the simulation.
		DotLog.debug("audio", "no such stream", {"path": path, "id": String(id)})
	return stream


func _configure(player: Node, kind: int, request: Dictionary) -> void:
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
			# The family's 2D world is the XZ plane, so one request shape serves both.
			p2.global_position = Vector2(pos.x, pos.z)
			p2.max_distance = float(request.get("max_distance", 2000.0))


## The PCM copy of a short compressed stream once it is decoded, else [param stream] itself.
##
## [b]The first play is the compressed one[/b] and starts the decode on a worker thread; a
## later play of the same path picks the copy up. Never for a looping request (the resampled
## copy's ends are not sample-exact, and a seam clicks), never without threads (the decode
## would run inline, and it is slower than the start it saves).
func _pcm_for(path: String, stream: AudioStream) -> AudioStream:
	if _pcm.has(path):
		return _pcm[path] as AudioStream
	if _pcm_skipped.has(path):
		return stream
	if _pcm_jobs.has(path):
		_collect_pcm(false)
		return _pcm.get(path, stream) as AudioStream
	if not (stream is AudioStreamOggVorbis or stream is AudioStreamMP3):
		_pcm_skipped[path] = true
		return stream
	var rate := int(AudioServer.get_mix_rate())
	var seconds := stream.get_length()
	# Booked as stereo until the decode says otherwise.
	var cost := int(seconds * float(rate)) * 4
	if seconds <= 0.0 or seconds > pcm_max_seconds or _pcm_bytes + cost > pcm_budget_bytes or not _threaded():
		_pcm_skipped[path] = true
		return stream
	if _pcm_jobs.size() >= PCM_JOBS:
		_collect_pcm(false)
		if _pcm_jobs.size() >= PCM_JOBS:
			return stream
	var out: Array = []
	var task := WorkerThreadPool.add_task(_PCM.decode.bind(stream, rate, out), false, "dot-audio pcm")
	_pcm_jobs[path] = [task, out, cost]
	_pcm_bytes += cost
	return stream


## Takes in every finished decode; with [param wait], blocks for the ones still running.
func _collect_pcm(wait: bool) -> void:
	for path: String in _pcm_jobs.keys():
		var job: Array = _pcm_jobs[path]
		var task := int(job[0])
		if not wait and not WorkerThreadPool.is_task_completed(task):
			continue
		var _err := WorkerThreadPool.wait_for_task_completion(task)
		_pcm_jobs.erase(path)
		_pcm_bytes -= int(job[2])
		var out: Array = job[1]
		if out.is_empty():
			_pcm_skipped[path] = true
			continue
		var wav := out[0] as AudioStreamWAV
		_pcm_bytes += wav.data.size()
		_pcm[path] = wav
		_pcm_copies[wav] = true


func _threaded() -> bool:
	return OS.get_processor_count() > 1 and (not OS.has_feature("web") or OS.has_feature("threads"))


## Waits for the decodes still running, so the worker pool shuts down with none of them left.
func close() -> void:
	_collect_pcm(true)


## The stream at [param path]: the imported resource when the build has it, else the file's
## own bytes, else null.
##
## [b]Why a second way in.[/b] An addon release reaches players as an overlay pack laid over
## the build's own [code]res://addons/<dir>/[/code] (dot-cloud's addon packs), and that pack
## is the addon's release zip: tracked files only, so a sound arrives as [code]x.ogg[/code]
## and [code]x.ogg.import[/code] with no [code].godot/imported/[/code] output behind it. On a
## build exported before that sound existed, the importer follows the marker to nothing and
## the sound is silence. Every file dot-audio itself ships (the stock footsteps and beds)
## would be silent for a player until a new shell, which is exactly what addon packs exist
## to avoid. So when the marker's output is missing and the source file is in the pack, it is
## decoded from its bytes (Ogg Vorbis, WAV or MP3), once per path.
##
## The marker is read first rather than trying [code]load[/code] and falling back, because a
## failed load prints an engine error per attempt, which on a footstep is several a second.
static func stream_at(path: String) -> AudioStream:
	if _RAW.streams.has(path):
		return _RAW.streams[path]
	if ResourceLoader.exists(path) and _import_output_present(path):
		var loaded := load(path) as AudioStream
		if loaded != null:
			return loaded
	if not FileAccess.file_exists(path):
		return null
	var raw: AudioStream = null
	match path.get_extension().to_lower():
		"ogg":
			raw = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			raw = AudioStreamWAV.load_from_file(path)
		"mp3":
			raw = AudioStreamMP3.load_from_file(path)
	if raw != null:
		DotLog.debug("audio", "decoded from its own bytes (no imported output)", {"path": path})
		_RAW.streams[path] = raw
	return raw


## Drops [method stream_at]'s cache. Call after the last manager has left the tree, before
## `quit()`, so a process exits with no stream still in use.
static func clear_streams() -> void:
	_RAW.clear()


## Whether the file a path's [code].import[/code] marker names is there. True when there is
## no marker (a plain resource) or the marker names no single output.
static func _import_output_present(path: String) -> bool:
	var marker := path + ".import"
	if not FileAccess.file_exists(marker):
		return true
	var text := FileAccess.get_file_as_string(marker)
	var at := text.find("\npath=\"")
	if at < 0:
		at = text.find("\npath.")
		if at < 0:
			return true
		# One output per feature tag (path.s3tc=...): any of them present will do.
		var any := false
		for line in text.split("\n"):
			if line.begins_with("path.") and line.contains("=\""):
				var target := line.get_slice("\"", 1)
				any = any or FileAccess.file_exists(target)
		return any
	var target := text.substr(at + 7).get_slice("\"", 0)
	return FileAccess.file_exists(target)


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
			var p3 := AudioStreamPlayer3D.new()
			# No area lookup: the default mask asks the physics space which Area3D each voice
			# is in on every physics tick it plays, and nothing in the family routes audio by area.
			p3.area_mask = 0
			player = p3
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


## Sets the pooled player's own volume and pitch. A stolen or finished voice is not in
## [code]_busy[/code] any more, so a late call cannot reach the player some other sound has
## since been given.
func shape(handle: int, volume_db: float, pitch: float) -> void:
	if not _busy.has(handle):
		return
	var entry: Dictionary = _busy[handle]
	var player: Node = entry["player"]
	player.set(&"volume_db", volume_db + float(entry.get("trim_db", 0.0)))
	# The same range the manager clamps a request to: past about four times, resampling is
	# an artefact rather than a pitch, and zero or below is an engine error.
	player.set(&"pitch_scale", clampf(pitch, 0.05, 4.0))


## Read from the player rather than remembered, so it reports what the engine is doing.
func voice(handle: int) -> Dictionary:
	if not _busy.has(handle):
		return {}
	var entry: Dictionary = _busy[handle]
	var player: Node = entry["player"]
	return {
		"volume_db": float(player.get(&"volume_db")) - float(entry.get("trim_db", 0.0)),
		"pitch": float(player.get(&"pitch_scale")),
		"playing": bool(player.call(&"is_playing")),
	}


func usage() -> Dictionary:
	return {"playing": _busy.size(), "capacity": capacity}


func sink_name() -> String:
	# The bank is named here because "the sound I expected was a different sound" is
	# otherwise indistinguishable from "the file I added is not being read", and this
	# string is what a `describe()` and a bug report carry.
	return "godot" if bank.is_empty() else "godot+bank(%d)" % bank.size()
