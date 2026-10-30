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
# 9: DotAudioSurf, DotAudioSurfRules and the stock surf glide (DotAudioStock.SURF_GLIDE_ID);
#    DotAudioFootsteps.surf_rules silences steps and landings on a ramp.
const LEVEL := 9
const OLDEST := 1
