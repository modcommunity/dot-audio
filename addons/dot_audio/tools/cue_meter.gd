extends RefCounted

## Offline loudness of one stream: no audio device. Peak dBFS and an ITU-R BS.1770 style
## integrated loudness (K-weighting, 400 ms blocks, -70 LUFS and -10 LU gates), on the mono
## mixdown. Short clips (under one block) use their whole length. Ignores pitch and 3D falloff.

const BLOCK_S := 0.4
const FLOOR := -120.0


## {samples: PackedFloat32Array, rate: int}, empty on failure. An AudioStreamWAV is read from its
## data; anything with a file behind it (ogg, mp3) is decoded by ffmpeg.
static func decode(stream: AudioStream) -> Dictionary:
	if stream is AudioStreamWAV:
		return _wav(stream as AudioStreamWAV)
	var path := stream.resource_path if stream != null else ""
	return decode_file(path)


static func decode_file(path: String) -> Dictionary:
	var src := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(src):
		return {}
	var tmp := OS.get_cache_dir().path_join("cue_meter_%d.raw" % Time.get_ticks_usec())
	var code := OS.execute("ffmpeg", ["-v", "error", "-y", "-i", src, "-ac", "1", "-ar", "48000", "-f", "f32le", tmp], [])
	if code != 0 or not FileAccess.file_exists(tmp):
		return {}
	var bytes := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	return {"samples": bytes.to_float32_array(), "rate": 48000}


static func _wav(w: AudioStreamWAV) -> Dictionary:
	var d := w.data
	var out := PackedFloat32Array()
	var ch := 2 if w.stereo else 1
	match w.format:
		AudioStreamWAV.FORMAT_16_BITS:
			var n := d.size() / (2 * ch)
			out.resize(n)
			for i in n:
				var s := 0.0
				for c in ch:
					s += d.decode_s16((i * ch + c) * 2) / 32768.0
				out[i] = s / ch
		AudioStreamWAV.FORMAT_8_BITS:
			var n8 := d.size() / ch
			out.resize(n8)
			for i in n8:
				var s8 := 0.0
				for c in ch:
					s8 += d.decode_s8(i * ch + c) / 128.0
				out[i] = s8 / ch
		_:
			return {}
	return {"samples": out, "rate": w.mix_rate}


static func peak_db(x: PackedFloat32Array) -> float:
	var p := 0.0
	for v in x:
		p = maxf(p, absf(v))
	return linear_to_db(p) if p > 0.0 else FLOOR


static func rms_db(x: PackedFloat32Array) -> float:
	if x.is_empty():
		return FLOOR
	var s := 0.0
	for v in x:
		s += v * v
	s /= x.size()
	return 10.0 * log(s) / log(10.0) if s > 1e-12 else FLOOR


## K-weighted (BS.1770 shelf then high-pass), coefficients derived for any rate.
static func k_weight(x: PackedFloat32Array, rate: int) -> PackedFloat32Array:
	var y := _biquad(x, _shelf(rate))
	return _biquad(y, _highpass(rate))


static func _shelf(fs: int) -> Array:
	var db := 3.999843853973347
	var f0 := 1681.974450955533
	var q := 0.7071752369554196
	var k := tan(PI * f0 / fs)
	var vh := pow(10.0, db / 20.0)
	var vb := pow(vh, 0.4996667741545416)
	var a0 := 1.0 + k / q + k * k
	return [(vh + vb * k / q + k * k) / a0, 2.0 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0,
		2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0]


static func _highpass(fs: int) -> Array:
	var f0 := 38.13547087602444
	var q := 0.5003270373238773
	var k := tan(PI * f0 / fs)
	var a0 := 1.0 + k / q + k * k
	return [1.0, -2.0, 1.0, 2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0]


static func _biquad(x: PackedFloat32Array, c: Array) -> PackedFloat32Array:
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var b0: float = c[0]
	var b1: float = c[1]
	var b2: float = c[2]
	var a1: float = c[3]
	var a2: float = c[4]
	for i in x.size():
		var xi := x[i]
		var yi := b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = xi
		y2 = y1
		y1 = yi
		y[i] = yi
	return y


## Integrated loudness (LUFS) of mono samples; FLOOR when silent.
static func lufs(x: PackedFloat32Array, rate: int) -> float:
	if x.is_empty():
		return FLOOR
	var k := k_weight(x, rate)
	var block := int(BLOCK_S * rate)
	var hop := block / 4
	var powers := PackedFloat64Array()
	if k.size() < block:
		powers.append(_ms(k, 0, k.size()))
	else:
		var i := 0
		while i + block <= k.size():
			powers.append(_ms(k, i, block))
			i += hop
	var kept := PackedFloat64Array()
	for p in powers:
		if _l(p) > -70.0:
			kept.append(p)
	if kept.is_empty():
		return FLOOR
	var rel := _l(_mean(kept)) - 10.0
	var gated := PackedFloat64Array()
	for p in kept:
		if _l(p) > rel:
			gated.append(p)
	return _l(_mean(gated)) if not gated.is_empty() else FLOOR


static func _ms(k: PackedFloat32Array, from: int, n: int) -> float:
	var s := 0.0
	for i in n:
		var v := k[from + i]
		s += v * v
	return s / maxi(n, 1)


static func _mean(a: PackedFloat64Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _l(ms: float) -> float:
	return -0.691 + 10.0 * log(maxf(ms, 1e-12)) / log(10.0)
