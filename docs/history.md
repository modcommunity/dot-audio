# History

Bugs worth recognising if they come back. The lessons that still apply are rules in [CLAUDE.md](../CLAUDE.md) and [design.md](design.md).

## A pause menu silenced the game

Concurrency counts were decremented only in `_process`, when the sink reported a sound finished. `_process` does not run while the tree is paused, so a game that opened a pause menu came back with every count stuck at its cap and was silent for the rest of the session, with nothing erroring. The counts are now reaped at the point of refusal as well, the only place they are consulted, and `_test_limits` asserts a finished sound frees its slot **with no frame in between**, so the fix cannot be reverted quietly.

From the same run: `SceneTree.process_frame` is emitted **before** `Node._process`, not after. A test that awaits one frame and expects a node's `_process` to have run passes or fails on scheduling, which is why that check waits for no frame at all.

## `looping` was in every request and no sink read it

`DotAudioManager` always put `def.looping` in the play request, and `DotAudioSinkGodot.play()` never looked, so an engine hum or an ambience bed played once and stopped, while the null sink recorded a request that looked right. A game found it and built its engine sound as a repeating pulse rather than wait. The fix and why it copies the stream are in [design.md](design.md#looping-copies-the-stream); the suite asserts the loop points, that the bank's own stream is untouched, and the restart fallback.
