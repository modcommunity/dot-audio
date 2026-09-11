@tool
class_name DotAudioDef
extends Resource

## One sound, as a document. Names a file by path and never loads one.
##
## [b]This addon ships no audio and never holds an [AudioStream].[/b] Same rule as dot-ui's
## "ships no art", and here it has a second, harder reason: a game delivered as a dot-cloud
## pack is mounted at runtime, and **a mounted pack's `class_name` globals are not
## registered in the host** — measured, in this family, and it is why dot-props names a
## prop's script by PATH. A catalogue that `preload`s its streams cannot describe delivered
## content at all, and a catalogue that holds loaded streams cannot be validated on a
## server that does not have them.
##
## So: [member path] is a string, the manager loads it when something asks to hear it, and
## [method validate] checks everything except whether the file exists.

enum Kind {
	## Positionless. Music, an interface click, a narrator.
	FLAT,
	## Positioned on a 2D plane.
	POSITIONAL_2D,
	## Positioned in the world.
	POSITIONAL_3D,
}

## The id a game asks for. Unique in a catalogue.
@export var id: StringName = &""

## The stream's path. A [code]res://[/code] or a mounted pack's path.
@export var path: String = ""

## Alternatives chosen from at random, so a rifle does not sound like a metronome.
##
## [b]Variation is the single cheapest improvement to any game's audio[/b] and the reason
## it belongs here rather than in the caller: a caller that picks the variant has to hold
## the list, and then the list is in two places.
@export var variants: PackedStringArray = PackedStringArray()

@export var kind: Kind = Kind.FLAT

## Which audio bus it plays on. The bus is the mixer's business, not this document's.
@export var bus: StringName = &"SFX"

## Gain in decibels, applied on top of the bus.
@export_range(-60.0, 24.0, 0.1) var gain_db: float = 0.0

## Pitch is drawn uniformly between these. Equal values means no variation.
##
## Deterministic when a stream is supplied: a rewound replay and a second client hear the
## same shot. A sound that picks its own pitch cannot be reproduced, and an audio bug that
## cannot be reproduced is an audio bug nobody fixes.
@export_range(0.1, 4.0, 0.01) var pitch_min: float = 1.0
@export_range(0.1, 4.0, 0.01) var pitch_max: float = 1.0

## How many of this id may sound at once. Zero is no limit.
##
## [b]Not the same as the pool size, and both are needed.[/b] Twelve NPCs firing the same
## rifle in one tick is twelve identical streams half a millisecond apart, which is not
## twelve gunshots — it is one gunshot twelve times as loud, with comb filtering. Three is
## usually enough to sound like a crowd.
@export_range(0, 64, 1) var max_concurrent: int = 4

## Milliseconds before this id may start again. Zero is none.
##
## The other half of the same problem: a footstep triggered by a physics callback can fire
## twice in a frame, and the second one is inaudible and still costs a voice.
@export_range(0, 60000, 1) var cooldown_ms: int = 0

## Higher wins when the pool is full. See [DotAudioSink].
##
## A footstep losing to a gunshot is correct. A gunshot losing to a footstep because the
## footstep started first is the failure mode of every fixed pool with no priority.
@export_range(0, 100, 1) var priority: int = 50

## Whether it loops. Music and ambience; refused for a one-shot by [method validate].
@export var looping: bool = false

@export_group("Positional")

## Metres at which it is at full volume, and beyond which it falls off.
@export_range(0.1, 1000.0, 0.1, "or_greater") var unit_size: float = 10.0

## Metres past which it is not played at all.
##
## [b]A cull distance is not a volume curve.[/b] A sound at 400 metres attenuated to
## inaudible still costs a voice, a stream and a position update every frame — and on a
## sixty-four player server that is most of the pool spent on things nobody can hear.
@export_range(0.0, 10000.0, 1.0, "or_greater") var max_distance: float = 200.0

## Tags a game can filter on — "weapon", "footstep", "ui". Free text.
@export var tags: Array[StringName] = []

## Whether this sound has no file because the sink makes it.
##
## [b]A game whose audio is generated rather than shipped is a real deployment and this
## addon nearly refused it.[/b] game-hungario bakes its entire bank arithmetically at
## boot — a sine sweep with a hash-derived noise component under an envelope, ten cues, no
## files — which is the best thing about that game's audio: it ships nothing and works
## everywhere. It is also the first thing to use [DotAudioSink] for what the seam is
## actually for, and [method validate] turned it down on the first run for naming no file.
##
## With this set, the id is the whole contract: dot-audio decides whether the sound should
## be heard, how many at once, how far away it stops mattering and at what pitch, and the
## sink is what knows how to make it.
@export var generated: bool = false


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "a sound with no id")
	if path.is_empty() and variants.is_empty() and not generated:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"'%s' names no file and is not marked generated" % id,
			"set `generated` when the sink makes the sound rather than loading it"
		)
	if pitch_max < pitch_min:
		return DotResult.fail(
			DotError.CODE_INVALID, "'%s' has a maximum pitch below its minimum" % id
		)
	if looping and max_concurrent == 1 and cooldown_ms > 0:
		# Not fatal, but it is always a mistake: a looping sound starts once and the
		# cooldown can only ever stop it being restarted after it is deliberately stopped.
		DotLog.warn(
			"audio", "a looping sound with a cooldown", {"id": String(id)}
		)
	if kind != Kind.FLAT and max_distance > 0.0 and max_distance < unit_size:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"'%s' is culled closer than it reaches full volume" % id,
			"max_distance %.1f, unit_size %.1f" % [max_distance, unit_size]
		)
	return DotResult.success(null)


## The path to use for one playback, chosen from [member variants] when there are any.
##
## Takes a stream rather than making its own, so the choice is reproducible: the same seed
## and the same index give the same variant on a server and on every client watching.
func pick_path(roll: float) -> String:
	if variants.is_empty():
		return path
	var i := clampi(int(roll * float(variants.size())), 0, variants.size() - 1)
	return variants[i]


func pick_pitch(roll: float) -> float:
	if is_equal_approx(pitch_min, pitch_max):
		return pitch_min
	return pitch_min + roll * (pitch_max - pitch_min)


func describe_line() -> String:
	return "%-24s %-14s %-6s %+5.1f dB  max %d  %s" % [
		String(id),
		["flat", "2d", "3d"][kind],
		String(bus),
		gain_db,
		max_concurrent,
		path if variants.is_empty() else "%d variants" % variants.size(),
	]
