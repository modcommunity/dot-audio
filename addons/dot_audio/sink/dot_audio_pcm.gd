extends RefCounted

## Decodes a short compressed stream to PCM once, so playing it again costs nothing to start.
##
## [b]Why.[/b] Starting an Ogg Vorbis voice builds a decoder (its codebooks) every time, close
## to a millisecond on the game thread per shot layer; a PCM stream starts in microseconds.
## The decode runs on a worker thread and the sink swaps the result in when it is ready.
##
## A script of its own for the same reason as the raw stream cache: the sink must not name
## itself from a static function (see that file). The copies are kept here, once per process, so
## a voice pool outside the sink (a game's own gun voices) shares them through [method copy_for]
## by this file's path instead of keeping a second cache.

const CHUNK := 4096

## Decodes running at once: the worker pool is shared with whatever else the game threads.
const JOBS := 2

## Key (a stream's path) -> its decoded [AudioStreamWAV].
static var _copies: Dictionary = {}
## Every decoded copy, so a player knows to make up [constant HEADROOM_DB].
static var _is_copy: Dictionary = {}
## Key -> [task, out, booked bytes].
static var _jobs: Dictionary = {}
static var _skipped: Dictionary = {}
static var _bytes := 0

## Stored at half scale and played [constant HEADROOM_DB] louder: a decoder overshoots full
## scale on a loud transient (1.27 measured on a stock step), and 16 bits would clip what the
## float mix carries through to the limiter.
const HEADROOM := 0.5
const HEADROOM_DB := 6.0206


## Appends an [AudioStreamWAV] holding [param stream] at [param rate] to [param out], or
## nothing when it cannot be decoded. Safe on a worker thread: it touches only its arguments.
static func decode(stream: AudioStream, rate: int, out: Array) -> void:
	var want := int(ceil(stream.get_length() * float(rate)))
	var playback := stream.instantiate_playback()
	if playback == null or want <= 0 or rate <= 0:
		return
	playback.start(0.0)
	var frames := PackedVector2Array()
	while frames.size() < want:
		var chunk := playback.mix_audio(1.0, mini(CHUNK, want - frames.size()))
		if chunk.is_empty():
			break
		frames.append_array(chunk)
	playback.stop()
	var count := frames.size()
	if count == 0:
		return

	# A mono source comes back as two equal channels; kept as one, it is half the memory.
	var stereo := false
	for i in range(count):
		if frames[i].x != frames[i].y:
			stereo = true
			break

	var data := PackedByteArray()
	if stereo:
		data.resize(count * 4)
		for i in range(count):
			var f := frames[i]
			data.encode_s16(i * 4, clampi(int(f.x * HEADROOM * 32767.0), -32768, 32767))
			data.encode_s16(i * 4 + 2, clampi(int(f.y * HEADROOM * 32767.0), -32768, 32767))
	else:
		data.resize(count * 2)
		for i in range(count):
			data.encode_s16(i * 2, clampi(int(frames[i].x * HEADROOM * 32767.0), -32768, 32767))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = stereo
	wav.data = data
	out.append(wav)


## The PCM copy of the short compressed [param stream] once it is decoded, else [param stream]
## itself; [param key] names it (its path). [b]The first play is the compressed one[/b] and starts
## the decode on a worker thread; a later play picks the copy up. A copy is at half scale: play it
## [constant HEADROOM_DB] louder (see [method is_copy]). Never for a stream longer than
## [param max_seconds] or past [param budget_bytes] held, never without threads (the decode would
## run inline, and it is slower than the start it saves), and not for a loop (the resampled copy's
## ends are not sample-exact, and a seam clicks): that check is the caller's.
static func copy_for(key: String, stream: AudioStream, max_seconds: float = 4.0, budget_bytes: int = 64 * 1024 * 1024) -> AudioStream:
	if _copies.has(key):
		return _copies[key] as AudioStream
	if _skipped.has(key) or key.is_empty():
		return stream
	if _jobs.has(key):
		collect(false)
		return _copies.get(key, stream) as AudioStream
	if not (stream is AudioStreamOggVorbis or stream is AudioStreamMP3):
		_skipped[key] = true
		return stream
	var rate := int(AudioServer.get_mix_rate())
	var seconds := stream.get_length()
	# Booked as stereo until the decode says otherwise.
	var cost := int(seconds * float(rate)) * 4
	# Not remembered as skipped: another caller's limits may allow it.
	if seconds <= 0.0 or seconds > max_seconds or _bytes + cost > budget_bytes or not threaded():
		return stream
	if _jobs.size() >= JOBS:
		collect(false)
		if _jobs.size() >= JOBS:
			return stream
	var out: Array = []
	var task := WorkerThreadPool.add_task(decode.bind(stream, rate, out), false, "dot-audio pcm")
	_jobs[key] = [task, out, cost]
	_bytes += cost
	return stream


## True for a copy [method copy_for] handed out, which plays [constant HEADROOM_DB] louder.
static func is_copy(stream: AudioStream) -> bool:
	return stream is AudioStreamWAV and _is_copy.has(stream)


## Takes in every finished decode; with [param wait], blocks for the ones still running.
static func collect(wait: bool) -> void:
	for key: String in _jobs.keys():
		var job: Array = _jobs[key]
		var task := int(job[0])
		if not wait and not WorkerThreadPool.is_task_completed(task):
			continue
		var _err := WorkerThreadPool.wait_for_task_completion(task)
		_jobs.erase(key)
		_bytes -= int(job[2])
		var out: Array = job[1]
		if out.is_empty():
			_skipped[key] = true
			continue
		var wav := out[0] as AudioStreamWAV
		_bytes += wav.data.size()
		_copies[key] = wav
		_is_copy[wav] = true


## Drops every copy (after waiting out the running decodes), so nothing static holds a stream at quit.
static func clear() -> void:
	collect(true)
	_copies.clear()
	_is_copy.clear()
	_skipped.clear()
	_bytes = 0


static func threaded() -> bool:
	return OS.get_processor_count() > 1 and (not OS.has_feature("web") or OS.has_feature("threads"))
