class_name DotAudioSink
extends RefCounted

## Where a sound actually goes. The seam that lets the whole path run headless.
##
## [b]This exists for the same reason dot-voice's `DotVoiceSource` does, and because of a
## bug that addon found: `AudioServer` reports a working sound card when there is
## none.[/b] In a headless run `get_mix_rate()` is 44100, `get_input_device_list()` is
## `["Default"]` and `get_output_latency()` is 0.0. Only `get_driver_name()` says
## `"Dummy"`. A capability check built on any of the others passes on a machine with no
## audio at all, and the symptom is silence for ever with nothing reporting a problem.
##
## So the honest check is here, once, in [method device_present], and every deployment
## takes the same path: the manager still resolves ids, applies limits, honours cooldowns
## and steals voices, and the sink either makes a noise or writes down that it would have.
## A suite asserts the second one and is therefore testing the whole system rather than a
## mock of it.

## A playback request, after the manager has resolved everything.
##
## A dictionary rather than a class because it crosses no boundary that would benefit from
## a type, and because a sink written by somebody else should not have to extend anything
## but this.
##
## [code]{id, path, bus, volume_db, pitch, kind, position, unit_size, max_distance,
## looping, priority}[/code]

## Starts a sound. Returns a handle, or 0 when nothing was started.
func play(_request: Dictionary) -> int:
	return 0


## Stops one playback. A handle that has already finished is not an error.
func stop(_handle: int) -> void:
	pass


func stop_all() -> void:
	pass


## Whether [param handle] is still sounding.
func is_playing(_handle: int) -> bool:
	return false


## Moves a positional sound that is already playing.
##
## Separate from [method play] because a sound attached to a moving thing is the common
## case and restarting it every frame is not a way to move it.
func move(_handle: int, _position: Vector3) -> void:
	pass


## Sets a playing voice's loudness and pitch, in the request's own units: decibels, and a
## pitch scale. A handle that is not playing is ignored, as [method move] ignores one.
##
## [b]Separate from [method play] for the reason [method move] is.[/b] An engine is one loop
## whose pitch follows the speed and whose load follows the throttle, every frame; stopping
## and restarting it to change either is a click a frame and a new handle a frame. Added at
## API level 2 (2026-10-11) after a game had to subclass the Godot sink and read its pool to
## do this. A no-op here, so a sink written before it existed still loads and simply cannot
## shape: the voice keeps the level it started at, which is what it did before.
func shape(_handle: int, _volume_db: float, _pitch: float) -> void:
	pass


## What a playing voice is set to: [code]{volume_db, pitch, playing}[/code], or empty when
## the handle is not playing or this sink cannot say.
##
## The read-back of [method shape], for a probe or a suite: under xvfb it is the engine's
## own player that answers, which is the only place "is it loud enough to hear" is true.
func voice(_handle: int) -> Dictionary:
	return {}


## How many voices are in use, and how many there are.
func usage() -> Dictionary:
	return {"playing": 0, "capacity": 0}


## Whether there is a real output device.
##
## [b]`AudioServer.get_driver_name()` is the only honest question.[/b] Everything else the
## engine reports about audio is plausible on a machine with none.
static func device_present() -> bool:
	return AudioServer.get_driver_name() != "Dummy"


func sink_name() -> String:
	return "none"
