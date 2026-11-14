extends RefCounted

## dot-audio's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: shape() and voice() on DotAudioManager and DotAudioSink: a playing voice's volume and
#    pitch changed without restarting it, and read back.
# 3: DotAudioStock (stock footsteps and ambience beds), DotAudioFootsteps, DotAudioAmbience,
#    DotAudioLoudness and the manager's master limiter (limit_master, loudness_trim_db).
# 4: DotAudioSinkGodot.stream_at (a file with no imported output, as an addon pack brings
#    it, is decoded from its own bytes).
# 5: DotAmbience (moods of beds and random one-shots, crossfaded), DotAmbienceConfig,
#    DotAmbienceSet, DotAmbienceMood, DotAmbienceMoods.
# 6: DotAmbienceDirector, DotAmbienceRules, DotAudioStock.moods_directory (the stock mood set).
# 7: DotAudioSlide and the stock slide loops (DotAudioStock.slide_id, slide_defs).
# 8: DotBoxSounds (per-event box sounds, stock set, effect-end once).
# 10: DotShotDef, DotShotPlayer, DotShotRules, DotAudioEnclosure and DotAudioShotStock (layered shots, room-aware tails).
# 9: DotAudioSurf, DotAudioSurfRules and the stock surf glide (DotAudioStock.SURF_GLIDE_ID);
#    DotAudioFootsteps.surf_rules silences steps and landings on a ramp.
# 11: DotShotRules.tail_voices (snd_shot_tail_voices) and DotShotPlayer.tail_voices(): a cap on stacked room tails.
# 13: DotAudioSynth.bank(..., stock): the opt-in flag that swaps the sine-sweep voices for the self-synthesised stock/voices.
# 14: DotHurtSound (the damage-scaled hurt grunt that yields to a lethal hit's death cry).
# 15: DotAudioSink.close(); DotAudioSinkGodot.pcm_max_seconds and pcm_budget_bytes; DotAudioFootsteps.hear_distance (a short compressed
#     stream is decoded to PCM off the game thread after its first play, so starting it again is cheap).
# 16: DotVoiceQueue (one announcer or medal line at a time, by priority).
# 17: sink/dot_audio_pcm.gd copy_for/is_copy/collect/clear: the decoded copies kept once per process, for a voice pool outside the sink.
# 18: dot_audio_pcm.gd pump()/slice_usec: without threads (the web export) the decode is sliced on the game thread, not skipped.
# 19: DotAudioSlide.reach and reach_margin (DotAudioSurf inherits them): a body out of earshot of the listener is not asked.
# 20: DotAudioFootsteps, DotAudioSlide (and DotAudioSurf) and DotAudioSurfRules run dot-sim's native tick and probe when
#     present: native_enabled (static), use_native, native_available(); DotAudioSurfRules.native_probe()/native_args().
const LEVEL := 20
const OLDEST := 1
