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
const LEVEL := 3
const OLDEST := 1
