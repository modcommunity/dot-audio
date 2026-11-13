extends RefCounted

## Decodes a short compressed stream to PCM once, so playing it again costs nothing to start.
##
## [b]Why.[/b] Starting an Ogg Vorbis voice builds a decoder (its codebooks) every time, close
## to a millisecond on the game thread per shot layer; a PCM stream starts in microseconds.
## The decode runs on a worker thread and the sink swaps the result in when it is ready.
##
## [b]Without threads[/b] (the single-threaded web export) there is no worker, and that is where
## a start costs most (about a millisecond each in the browser, on the one thread that also draws).
## There the decode is sliced on the game thread instead: [method pump] runs once a frame from
## [signal SceneTree.process_frame] for at most [member slice_usec], a chunk of Vorbis at a time,
## and the finished frames become PCM in native calls ([method _wav_native]), never a per-sample
## loop. Held copies are capped lower there ([constant WEB_BUDGET_BYTES]): the wasm heap is small.
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

## Without threads: key -> [playback (null until started), chunks, frames wanted, rate, booked
## bytes, stream, frames done], decoded in insertion order by [method pump].
static var _slices: Dictionary = {}
## Whether [method pump] is connected to the frame.
static var _pumping := false

## Takes the sliced path even with threads, as a suite does to cover the web's path natively.
static var slice_always := false
## Without threads: game-thread time [method pump] may spend a frame, in microseconds.
static var slice_usec := 1500
## Without threads: decodes waiting at most; a further sound plays compressed until one is done.
const SLICE_QUEUE := 48
## Frames decoded per step of a slice: small enough that one step stays well under the slice.
const SLICE_CHUNK := 2048
## Without threads, the held copies never pass this, whatever a caller's budget.
const WEB_BUDGET_BYTES := 24 * 1024 * 1024

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
## [param max_seconds] or past [param budget_bytes] held, and not for a loop (the resampled copy's
## ends are not sample-exact, and a seam clicks): that check is the caller's. Without threads the
## decode is queued for [method pump] and the budget is at most [constant WEB_BUDGET_BYTES].
static func copy_for(key: String, stream: AudioStream, max_seconds: float = 4.0, budget_bytes: int = 64 * 1024 * 1024) -> AudioStream:
	if _copies.has(key):
		return _copies[key] as AudioStream
	if _skipped.has(key) or key.is_empty() or _slices.has(key):
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
	var sliced := slice_always or not threaded()
	if sliced:
		budget_bytes = mini(budget_bytes, WEB_BUDGET_BYTES)
	# Not remembered as skipped: another caller's limits may allow it.
	if seconds <= 0.0 or seconds > max_seconds or _bytes + cost > budget_bytes:
		return stream
	if sliced:
		_queue_slice(key, stream, rate, cost)
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


## Without threads: books [param key] for [method pump]; the decoder is set up there, not here,
## so the play that asked pays nothing more than its own start.
static func _queue_slice(key: String, stream: AudioStream, rate: int, cost: int) -> void:
	if _slices.size() >= SLICE_QUEUE:
		return
	_slices[key] = [null, [], int(ceil(stream.get_length() * float(rate))), rate, cost, stream, 0]
	_bytes += cost
	if not _pumping:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.process_frame.connect(pump)
			_pumping = true


## Without threads: decodes the queued sounds, oldest first, for at most [param usec] microseconds
## ([member slice_usec] when negative; at least one step). Runs once a frame on its own while any
## are queued; a suite calls it with a large [param usec] to finish them now.
static func pump(usec: int = -1) -> void:
	var until := Time.get_ticks_usec() + (slice_usec if usec < 0 else usec)
	while not _slices.is_empty():
		var key: String = _slices.keys()[0]
		var job: Array = _slices[key]
		var stream := job[5] as AudioStream
		var want := int(job[2])
		var chunks: Array = job[1]
		var done := int(job[6])
		if job[0] == null:
			var playback := stream.instantiate_playback()
			if playback == null:
				_drop_slice(key, true)
				continue
			playback.start(0.0)
			job[0] = playback
		elif done < want:
			var chunk := (job[0] as AudioStreamPlayback).mix_audio(1.0, mini(SLICE_CHUNK, want - done))
			if chunk.is_empty():
				job[2] = done
			else:
				chunks.append(chunk)
				job[6] = done + chunk.size()
		else:
			(job[0] as AudioStreamPlayback).stop()
			var frames := PackedVector2Array()
			for c: PackedVector2Array in chunks:
				frames.append_array(c)
			var wav := _wav_native(frames, int(job[3]))
			_drop_slice(key, wav == null)
			if wav != null:
				_bytes += wav.data.size()
				_copies[key] = wav
				_is_copy[wav] = true
		if Time.get_ticks_usec() >= until:
			break
	if _slices.is_empty():
		_stop_pump()


static func _drop_slice(key: String, skip: bool) -> void:
	var job: Array = _slices[key]
	_slices.erase(key)
	_bytes -= int(job[4])
	if skip:
		_skipped[key] = true


static func _stop_pump() -> void:
	if not _pumping:
		return
	_pumping = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(pump):
		tree.process_frame.disconnect(pump)


## [param frames] (a decoder's float pairs) as [method decode]'s half-scale 16-bit copy, built by
## native calls only: a per-sample loop in script is what makes the threaded decode too slow for
## the game thread. Mono when the two channels are equal everywhere, as in [method decode].
static func _wav_native(frames: PackedVector2Array, rate: int) -> AudioStreamWAV:
	var count := frames.size()
	if count == 0 or rate <= 0:
		return null
	# (x - y, 0) for every frame: exactly +0.0 in both lanes where the channels are equal.
	var diff := Transform2D(Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2.ZERO) * frames
	var zeros := PackedByteArray()
	zeros.resize(count * 8)
	var stereo := diff.to_byte_array() != zeros
	var body := (Transform2D(Vector2(HEADROOM, 0.0), Vector2(0.0, HEADROOM), Vector2.ZERO) * frames).to_byte_array()
	# A float WAV in memory; the engine's reader turns it into 16 bits (and one channel) natively.
	var head := PackedByteArray()
	head.resize(44)
	head.encode_u32(0, 0x46464952)  # "RIFF"
	head.encode_u32(4, 36 + body.size())
	head.encode_u32(8, 0x45564157)  # "WAVE"
	head.encode_u32(12, 0x20746d66)  # "fmt "
	head.encode_u32(16, 16)
	head.encode_u16(20, 3)  # IEEE float
	head.encode_u16(22, 2)
	head.encode_u32(24, rate)
	head.encode_u32(28, rate * 8)
	head.encode_u16(32, 8)
	head.encode_u16(34, 32)
	head.encode_u32(36, 0x61746164)  # "data"
	head.encode_u32(40, body.size())
	head.append_array(body)
	var wav := AudioStreamWAV.load_from_buffer(head, {
		"force/8_bit": false,
		"force/mono": not stereo,
		"force/max_rate": false,
		"force/max_rate_hz": 44100,
		"edit/trim": false,
		"edit/normalize": false,
		"edit/loop_mode": 0,
		"edit/loop_begin": 0,
		"edit/loop_end": -1,
		"compress/mode": 0,
	})
	if wav == null or wav.format != AudioStreamWAV.FORMAT_16_BITS:
		return null
	return wav


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
	_slices.clear()
	_stop_pump()
	_copies.clear()
	_is_copy.clear()
	_skipped.clear()
	_bytes = 0


static func threaded() -> bool:
	return OS.get_processor_count() > 1 and (not OS.has_feature("web") or OS.has_feature("threads"))
