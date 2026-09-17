class_name DotAudioSynth
extends RefCounted

## Sound made of arithmetic, for a deployment that has no audio files yet.
##
## [b]This does not break "this addon ships no audio".[/b] The rule exists because a
## catalogue that holds [AudioStream]s cannot describe content delivered in a mounted pack
## and cannot be validated on a server that does not have the files — see [DotAudioDef].
## A synthesiser holds nothing: it is a pure function from a handful of numbers to bytes,
## it is a few hundred milliseconds of work at startup, and the catalogue it feeds is still
## a document naming paths. What ships is the arithmetic, not a bank.
##
## [b]Why it is in the addon rather than in a game.[/b] One game in this family had already
## written it — a sine sweep, a hash for the grit, an attack-decay envelope — and four more
## were silent with complete catalogues pointing at files nobody had produced. A second
## copy is the duplication this family keeps having to extract back out, and the numbers
## worth arguing about (what a shot sounds like against what a footstep sounds like) are
## the same numbers in every one of them.
##
## [b]It is a stand-in and is meant to be replaced.[/b] [DotAudioSinkGodot] consults its
## bank only when the def's path resolves to nothing, so dropping the real files in turns
## the synthesiser off one id at a time, with no code change anywhere. That ordering is the
## whole design: a placeholder that outranked a shipped asset would be a placeholder
## somebody has to remember to remove.
##
## [codeblock]
## var bank := DotAudioSynth.bank(catalogue, {
##     &"fire_rifle": DotAudioSynth.Voice.SHOT,
##     &"hit_marker": DotAudioSynth.Voice.BLIP,
## })
## (audio.sink as DotAudioSinkGodot).bank = bank
## [/codeblock]

const CHANNEL := "audio.synth"

## 22 kHz mono. Half the size of 44 kHz and indistinguishable for what these are: short
## noises with nothing in them above a few kilohertz. A placeholder that costs a megabyte
## of RAM per id is a placeholder that changes how the game runs.
const RATE := 22050

## The voices this ships, chosen to cover the catalogues that already exist in this family
## rather than to be a general instrument set.
##
## [b]Naming them by ROLE rather than by sound is deliberate.[/b] A game says "this is the
## shot" and gets whatever this file currently thinks a shot sounds like; a game that said
## "sine sweep 700 to 90 Hz" would have to be edited to benefit from anyone improving it.
enum Voice {
	## A rifle. Short, loud, mostly noise over a fast downward sweep.
	SHOT,
	## A shotgun. Lower, longer, noisier.
	SHOT_HEAVY,
	## A rail or an energy weapon. Tonal, so it reads as a different weapon and not as a
	## quieter rifle — the one property a player actually needs from weapon audio.
	SHOT_TIGHT,
	## Something striking a surface. A click with a body.
	IMPACT,
	## Confirmation of your own hit. High, tonal, very short.
	BLIP,
	## Taking damage.
	HURT,
	## Dying.
	DIE,
	## Arriving in the world. The one upward sweep here, because up reads as "on".
	SPAWN,
	## Picking something up.
	PICKUP,
	## An interface press.
	CLICK,
	## A footstep.
	STEP,
	## An explosion.
	BOOM,
	## A refusal: a buy you cannot afford, a door that will not open.
	DENY,
}

## [code]Voice -> [from_hz, to_hz, seconds, amplitude, noise, attack_seconds][/code].
##
## Kept as one table so the voices can be read against each other, which is the only way
## the relative choices — a shot is louder than a step, a blip is shorter than everything —
## can be checked at all.
const RECIPES := {
	Voice.SHOT: [760.0, 90.0, 0.16, 0.55, 0.72, 0.004],
	Voice.SHOT_HEAVY: [420.0, 60.0, 0.30, 0.62, 0.85, 0.006],
	Voice.SHOT_TIGHT: [1450.0, 320.0, 0.22, 0.42, 0.18, 0.003],
	Voice.IMPACT: [900.0, 180.0, 0.09, 0.34, 0.65, 0.003],
	Voice.BLIP: [1650.0, 1650.0, 0.045, 0.30, 0.0, 0.002],
	Voice.HURT: [520.0, 190.0, 0.22, 0.44, 0.35, 0.008],
	Voice.DIE: [340.0, 60.0, 0.62, 0.50, 0.40, 0.010],
	Voice.SPAWN: [260.0, 880.0, 0.28, 0.34, 0.06, 0.012],
	Voice.PICKUP: [680.0, 1240.0, 0.12, 0.30, 0.0, 0.004],
	Voice.CLICK: [980.0, 860.0, 0.035, 0.24, 0.10, 0.002],
	Voice.STEP: [190.0, 110.0, 0.075, 0.22, 0.80, 0.003],
	Voice.BOOM: [160.0, 38.0, 0.85, 0.70, 0.90, 0.012],
	Voice.DENY: [300.0, 150.0, 0.16, 0.30, 0.12, 0.004],
}


## Bakes one voice.
##
## [param seconds] is clamped to something a placeholder has any business being: a synth
## asked for a minute of audio is a caller that meant milliseconds, and the result would be
## 2.6 MB of silence nobody hears the end of.
static func voice(kind: Voice) -> AudioStreamWAV:
	var r: Array = RECIPES.get(kind, RECIPES[Voice.CLICK])
	return bake(r[0], r[1], r[2], r[3], r[4], r[5])


## A sine sweep from [param from_hz] to [param to_hz] over [param seconds], with
## [param noise] of the amplitude replaced by a deterministic hash, under an
## attack-decay envelope. That is the whole synthesiser.
##
## [b]The sweep is exponential, not linear.[/b] Pitch is heard logarithmically, so a linear
## sweep from 760 Hz to 90 Hz spends most of its length near the top and arrives as a
## click with a tail rather than as a shot.
##
## [b]Deterministic, and that matters more than it sounds.[/b] The grit comes from
## [method DotRandomStream.mix4] rather than from [method @GlobalScope.randf], so the bank
## is byte-identical on every machine and every run. That is what makes it something a
## suite can assert about rather than listen to — and it is the same reason
## [DotAudioDef.pitch_min] is documented as deterministic when a stream is supplied.
static func bake(
	from_hz: float,
	to_hz: float,
	seconds: float,
	amplitude: float = 0.4,
	noise: float = 0.0,
	attack_seconds: float = 0.004,
	salt: int = 0
) -> AudioStreamWAV:
	var length := clampf(seconds, 0.005, 4.0)
	var frames := maxi(1, int(length * float(RATE)))
	var data := PackedByteArray()
	data.resize(frames * 2)

	var from := maxf(1.0, from_hz)
	var to := maxf(1.0, to_hz)
	var ratio := to / from
	var grit := clampf(noise, 0.0, 1.0)
	var gain := clampf(amplitude, 0.0, 1.0)
	var attack := maxf(1.0 / float(RATE), attack_seconds)

	var phase := 0.0

	for index in range(frames):
		var t := float(index) / float(frames)
		var seconds_in := float(index) / float(RATE)

		var hz := from * pow(ratio, t)
		phase += TAU * hz / float(RATE)

		# Fast attack, then a decay that reaches zero at the end of the buffer. It has to
		# reach zero exactly: an [AudioStreamWAV] that stops mid-cycle is a click, and a
		# click on the end of every sound is the thing that makes placeholder audio
		# unbearable rather than merely rough.
		var rise := minf(1.0, seconds_in / attack)
		var envelope := rise * pow(1.0 - t, 1.8)

		var tone := sin(phase)
		var hiss := DotRandomStream.unit_from(
			DotRandomStream.mix4(index, salt, int(from), int(to))
		) * 2.0 - 1.0
		var sample := lerpf(tone, hiss, grit) * envelope * gain

		var value := clampi(int(sample * 32767.0), -32768, 32767)
		# Little-endian 16-bit, which is what FORMAT_16_BITS expects. Godot does not
		# check, so the wrong byte order here is not an error — it is noise.
		data[index * 2] = value & 0xFF
		data[index * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream


## Bakes a stand-in for every id in [param recipes], keyed the way
## [DotAudioSinkGodot.bank] reads it.
##
## [param recipes] is [code]{StringName id: Voice}[/code]. An id the catalogue does not
## have is skipped and counted in the log rather than refused: a game that names a sound it
## has not added to its catalogue yet has a typo or a work in progress, and neither is a
## reason to leave the other twelve silent.
##
## [b]Every variant of a def gets its own bake, salted by its path.[/b] [DotAudioDef]
## exists partly to stop a rifle sounding like a metronome, and a bank that collapsed three
## variants onto one stream would quietly undo that — the def would still pick a variant,
## and all three would resolve to the same bytes.
static func bank(catalogue: DotAudioCatalogue, recipes: Dictionary) -> Dictionary:
	var out := {}
	var missing: Array[String] = []

	for id in recipes.keys():
		var name := StringName(id)
		var def := catalogue.find(name) if catalogue != null else null

		if def == null:
			missing.append(String(name))
			continue

		var kind: Voice = recipes[id]

		# The id entry stands in for the def as a whole. The sink reads path first, so
		# this is what answers a def with no variants, and the fallback for one whose
		# chosen variant has no entry of its own.
		out[name] = voice(kind)

		var paths: Array[String] = []
		if not def.path.is_empty():
			paths.append(def.path)
		for v in def.variants:
			if not String(v).is_empty():
				paths.append(String(v))

		for p in paths:
			var r: Array = RECIPES.get(kind, RECIPES[Voice.CLICK])
			# Salted by the path, so two variants of one weapon differ -- and the SAME
			# path always bakes the same bytes, which is what keeps a replay honest.
			out[p] = bake(r[0], r[1], r[2], r[3], r[4], r[5], hash(p))

	if not missing.is_empty():
		DotLog.warn(
			CHANNEL,
			"a synth recipe names an id the catalogue does not have",
			{"ids": missing, "count": missing.size()}
		)

	return out
