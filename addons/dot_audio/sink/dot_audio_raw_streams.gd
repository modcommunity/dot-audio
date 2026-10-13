extends RefCounted

## Streams decoded from a file's own bytes, by path: [method DotAudioSinkGodot.stream_at]'s
## cache. Preloaded by path, no `class_name`.
##
## [b]A file of its own, and not a `static var` on [DotAudioSinkGodot], because the static var
## there leaked a game's whole run at exit.[/b] A script with a `static var` that its own static
## function writes, which is a subclass assigned to a variable typed as its base (the manager's
## `sink: DotAudioSink = DotAudioSinkGodot.new(...)`), compiled after something had already
## preloaded scripts it shares (a game preloading anything that names [DotAudioDef]), kept those
## shared scripts alive at exit; every static cache they reached came with them. In
## mg-dangerous-delivery that was 182 resources and the meshes, materials, textures and shaders
## behind them. Godot 4.7.2's exit teardown steps off its script list when a script that extends
## another is kept alive by a reference to itself, and a static var its own static function writes
## is one (game-dev's gdscript-hazards, "A script that names itself"; fixed upstream after 4.7.2).
## The same static var here, written from another script, does not do it.

static var streams: Dictionary = {}
