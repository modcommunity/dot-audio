extends Node

## Loads dot-audio the way a game's suite does and quits: run as a child process by
## audio_selftest's "nothing keeps a game alive at exit" section, which reads its stderr.
##
## [b]The order is the test.[/b] A [DotAudioDef] preloaded first, and only then a script naming
## [DotAudioManager], is what kept mg-dangerous-delivery's whole run alive at exit when
## [DotAudioSinkGodot] held its cache in a `static var` (see dot_audio_raw_streams.gd). Naming
## the manager first does not do it, so a probe written the other way round would pass on the
## bug.

const _DEF := preload("res://addons/dot_audio/core/dot_audio_def.gd")
const _STOCK := preload("res://addons/dot_audio/core/dot_audio_stock.gd")

var _named: Array[Script] = [DotAudioManager, DotAudioFootsteps]


func _ready() -> void:
	print("exit probe: %d scripts named" % _named.size())
	get_tree().quit()
