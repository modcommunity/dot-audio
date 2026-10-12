class_name DotAudioLoudness
extends RefCounted

## The family's loudness standard, and the master limiter that holds its ceiling.
##
## [b]The standard[/b]: a game's master mix, measured over a captured stretch of play
## (`addons/dot_audio/tools/loudness.sh`), sits at [constant TARGET_LUFS] integrated, inside
## [constant BAND_LOW]..[constant BAND_HIGH], with true peaks at or below
## [constant TRUE_PEAK_CEILING] and no 3 s window of digital silence. The reasoning is in
## docs/loudness.md: one level across games means a player sets their volume once, and a
## ceiling under 0 dBTP keeps a lossy encoder and a cheap DAC from clipping.
##
## [b]The limiter is a backstop, not the mix.[/b] It catches the pile-up of ten things at
## once; a game that leans on it for its level sounds squashed. Levels are set in the
## catalogue, and [member DotAudioManager.loudness_trim_db] is the last, whole-game nudge.

const TARGET_LUFS := -17.0
const BAND_LOW := -18.0
const BAND_HIGH := -16.0
const TRUE_PEAK_CEILING := -1.0

## The limiter's sample ceiling. A decibel under the true-peak ceiling, because the
## peaks between samples of a limited signal land a little above its sample peaks.
const LIMITER_CEILING_DB := -2.0


## Puts the family's limiter at the end of the Master bus, or retunes the one already there.
## Idempotent: setting a manager up twice does not stack two limiters.
##
## [b]Desktop and mobile only, in effect.[/b] A web build in sample playback mode does not
## run bus effects, so there the limiter (and a trim through it) does nothing; levels set in
## the catalogue are what reach a browser.
static func install_limiter(trim_db: float = 0.0, bus: int = 0) -> AudioEffectHardLimiter:
	if bus < 0 or bus >= AudioServer.bus_count:
		return null
	var limiter: AudioEffectHardLimiter = null
	for i in AudioServer.get_bus_effect_count(bus):
		var e := AudioServer.get_bus_effect(bus, i)
		if e is AudioEffectHardLimiter:
			limiter = e
			break
	if limiter == null:
		limiter = AudioEffectHardLimiter.new()
		AudioServer.add_bus_effect(bus, limiter)
	limiter.ceiling_db = LIMITER_CEILING_DB
	limiter.pre_gain_db = trim_db
	limiter.release = 0.1
	return limiter


## Where a measured integrated loudness sits against the band: -1 under, 0 in, 1 over.
static func band_of(lufs: float) -> int:
	if lufs < BAND_LOW:
		return -1
	if lufs > BAND_HIGH:
		return 1
	return 0
