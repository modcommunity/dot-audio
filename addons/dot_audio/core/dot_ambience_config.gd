class_name DotAmbienceConfig
extends DotConfig

## What a player or server owner may change about [DotAmbience]. Layered like every config
## here: defaults, JSON file, environment (`DOT_AMBIENCE_`), command line (`--ambience-`).

## Off silences the whole layer (beds fade out, no one-shots).
@export var enabled: bool = true

## Linear level of the layer. Low on purpose: a bed is felt, never listened to.
@export_range(0.0, 1.0, 0.01) var volume: float = 0.5

## One-shot rate: 1 is the set's own intervals, 2 twice as often, 0 none at all.
@export_range(0.0, 4.0, 0.05) var frequency: float = 1.0

## A mood that wins over whatever the game asks for. Empty leaves it to the game.
@export var mood: String = ""

## Comma-separated moods the game may choose; empty allows every mood.
@export var allowed_moods: String = ""

## A directory of extra sounds: a `moods.json` and the files it names (see docs/ambience.md).
## Its moods replace a built-in mood of the same name.
@export var sound_dir: String = ""

## Whether [method DotAmbience.set_indoors] switches to the indoor mood. Off keeps the outdoor one.
@export var follow_indoors: bool = true

## Seconds a mood change takes to cross over.
@export_range(0.5, 30.0, 0.5) var crossfade_seconds: float = 6.0


func env_prefix() -> String:
	return "DOT_AMBIENCE_"


func cli_prefix() -> String:
	return "--ambience-"


## [member allowed_moods] as names.
func allowed() -> PackedStringArray:
	var out := PackedStringArray()
	for part in allowed_moods.split(",", false):
		var name := part.strip_edges()
		if name != "":
			out.append(name)
	return out


func validate() -> DotResult:
	if volume < 0.0 or frequency < 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "ambience volume and frequency cannot be negative")
	return DotResult.success(null)
