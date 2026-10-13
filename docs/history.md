# History

Bugs worth recognising if they come back. The lessons that still apply are rules in [CLAUDE.md](../CLAUDE.md) and [design.md](design.md).

## A pause menu silenced the game

Concurrency counts were decremented only in `_process`, when the sink reported a sound finished. `_process` does not run while the tree is paused, so a game that opened a pause menu came back with every count stuck at its cap and was silent for the rest of the session, with nothing erroring. The counts are now reaped at the point of refusal as well, the only place they are consulted, and `_test_limits` asserts a finished sound frees its slot **with no frame in between**, so the fix cannot be reverted quietly.

From the same run: `SceneTree.process_frame` is emitted **before** `Node._process`, not after. A test that awaits one frame and expects a node's `_process` to have run passes or fails on scheduling, which is why that check waits for no frame at all.

## `looping` was in every request and no sink read it

`DotAudioManager` always put `def.looping` in the play request, and `DotAudioSinkGodot.play()` never looked, so an engine hum or an ambience bed played once and stopped, while the null sink recorded a request that looked right. A game found it and built its engine sound as a repeating pulse rather than wait. The fix and why it copies the stream are in [design.md](design.md#looping-copies-the-stream); the suite asserts the loop points, that the bank's own stream is untouched, and the restart fallback.

## A static cache kept a game's whole run alive at exit (2026-10-12)

mg-dangerous-delivery's `headless_run` passed every check and ended with "182 resources still in use at exit" plus RID leaks of meshes, materials, textures and shaders, but only when the suite itself named `DotAudioFootsteps` (a member, a local, a `load()` inside one section). The game creating one did not do it. Bisected with throwaway scripts in a fresh clone: a script that first preloads anything naming `DotAudioDef` and then names `DotAudioManager` is enough, and inside the manager the trigger is `sink = DotAudioSinkGodot.new(...)` into a `DotAudioSink`-typed variable, and inside the sink a `static var` that its own static function writes (`_raw`, `stream_at`'s cache). The scripts already loaded (dot-core's `DotError`, `DotResult`, `DotLog`, `DotLogBus` and everything else the game had preloaded) were then never freed, and every static cache they reached (a route's meshes, the people's animations) stayed with them. Naming the manager before the preload does not do it; a static var nobody writes does not; the same static var on another script, written from the sink, does not. It is the family's known 4.7.2 exit-teardown bug (a script that extends another and is kept alive by a reference to itself makes `GDScriptLanguage::finish` step off its list; fixed upstream after 4.7.2), in a form not listed before: a static var written by its own static function.

The cache is now `sink/dot_audio_raw_streams.gd` (preloaded by path, no `class_name`), and the suite's "Nothing kept alive at exit" section runs `examples/exit_leak_probe.tscn` in a child process, in the order that did it, and fails on any "at exit" line. It also cleared the four dot-core scripts the suite's own exit had reported "still in use" for months, which the README had put down to the engine's script cache. Rule: no `static var` written by its own script's static function in a script that extends another; keep such a cache in a script of its own.
