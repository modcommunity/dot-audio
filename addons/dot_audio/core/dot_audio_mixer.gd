@tool
class_name DotAudioMixer
extends DotConfig

## The volume sliders, and the one conversion everybody gets wrong.
##
## [b]A volume slider is not decibels.[/b] Mapping a 0..1 slider straight onto a bus's
## `volume_db` — even scaled to -60..0 — gives a control where everything below about 0.9
## is inaudible and the bottom two thirds of the travel does nothing. Hearing is roughly
## logarithmic, so the slider has to be too: [method @GlobalScope.linear_to_db] is the
## conversion, and the slider carries a linear amplitude.
##
## The second half is that **zero has to be silence**. `linear_to_db(0.0)` is negative
## infinity, which Godot handles, but a bus that is muted is cheaper and unambiguous — and
## a slider that reaches -60 dB instead of silence is one where a player who dragged it to
## the bottom can still hear the game.
##
## It is a [DotConfig], so dot-ui generates the screen and dot-settings persists it with
## nothing here knowing either exists.

## Linear amplitudes, 0..1. What a slider carries.
@export_range(0.0, 1.0, 0.01) var master: float = 1.0
@export_range(0.0, 1.0, 0.01) var music: float = 0.6
@export_range(0.0, 1.0, 0.01) var sfx: float = 1.0
@export_range(0.0, 1.0, 0.01) var ui: float = 0.8
@export_range(0.0, 1.0, 0.01) var voice: float = 1.0
@export_range(0.0, 1.0, 0.01) var ambience: float = 0.7

## Bus names, in the order the values above are declared.
##
## Exported so a project with its own bus layout does not have to rename anything, and so
## a project with fewer buses can point several of these at one.
@export var bus_names: Array[StringName] = [
	&"Master", &"Music", &"SFX", &"UI", &"Voice", &"Ambience"
]

## Whether to create any bus that is named here and missing.
##
## On, because the alternative is an addon that silently plays everything on Master when a
## project has not been set up — which sounds like the mixer not working rather than like
## a bus that is not there.
@export var create_missing_buses: bool = true

## Ducking: how far music drops, in dB, while something ducks it.
@export_range(-60.0, 0.0, 0.5) var duck_db: float = -12.0

## Seconds the duck takes to apply and to release.
@export_range(0.0, 5.0, 0.01) var duck_attack: float = 0.15
@export_range(0.0, 10.0, 0.01) var duck_release: float = 0.6


func env_prefix() -> String:
	return "DOT_AUDIO_"


func cli_prefix() -> String:
	return "--audio-"


## Every slider, by bus name.
func levels() -> Dictionary:
	var out := {}
	var values: Array[float] = [master, music, sfx, ui, voice, ambience]
	for i in range(mini(values.size(), bus_names.size())):
		out[bus_names[i]] = values[i]
	return out


## Pushes the sliders onto the engine's buses.
##
## Returns the names it could not find, rather than erroring on each: a project with three
## buses and a mixer that names six is a normal thing, and six red lines at boot is how a
## real one stops being read.
func apply_to_buses() -> PackedStringArray:
	var missing := PackedStringArray()
	for bus_name in levels().keys():
		var idx := AudioServer.get_bus_index(String(bus_name))
		if idx < 0:
			if create_missing_buses:
				idx = _create_bus(String(bus_name))
			if idx < 0:
				missing.append(String(bus_name))
				continue
		var linear: float = levels()[bus_name]
		# Muted rather than -inf dB. Both are silence; one of them is a number that a
		# later `+ 3.0` turns back into sound.
		AudioServer.set_bus_mute(idx, linear <= 0.0)
		if linear > 0.0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(linear))
	return missing


func _create_bus(bus_name: String) -> int:
	if bus_name == "Master":
		return 0
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx


## The dB a given bus is at, for a sound that wants to pre-multiply rather than route.
func db_for(bus_name: StringName) -> float:
	var linear: float = levels().get(bus_name, 1.0)
	return -80.0 if linear <= 0.0 else linear_to_db(linear)


func validate() -> DotResult:
	if bus_names.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "a mixer with no buses named")
	return DotResult.success(null)


func describe_lines(_redact_sensitive: bool = true) -> PackedStringArray:
	var out := PackedStringArray()
	var l := levels()
	for k in l.keys():
		var linear: float = l[k]
		out.append(
			"  %-10s %5.2f  %s"
			% [String(k), linear, "muted" if linear <= 0.0 else "%+.1f dB" % linear_to_db(linear)]
		)
	return out
