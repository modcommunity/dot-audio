extends RefCounted

## Decodes a short compressed stream to PCM once, so playing it again costs nothing to start.
##
## [b]Why.[/b] Starting an Ogg Vorbis voice builds a decoder (its codebooks) every time, close
## to a millisecond on the game thread per shot layer; a PCM stream starts in microseconds.
## The decode runs on a worker thread and the sink swaps the result in when it is ready.
##
## A script of its own for the same reason as the raw stream cache: the sink must not name
## itself from a static function (see that file).

const CHUNK := 4096

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
