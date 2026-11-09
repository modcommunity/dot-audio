class_name DotHurtSound
extends RefCounted
## The grunt a player makes when hurt: louder and lower for a heavy hit, quieter and higher for a graze, and none when the hit is lethal (the death or down cry owns that moment, and the two stacked are one muddy noise).
## Pure numbers plus one call; a game passes its [DotAudioManager] (or anything with `play(id, volume, pitch)`).

## Damage at which the grunt is full volume and lowest.
const FULL_DAMAGE := 40.0
## Volume of a scratch (damage near zero).
const MIN_VOLUME := 0.5
## Pitch of a scratch and of a full hit.
const PITCH_LIGHT := 1.08
const PITCH_HEAVY := 0.94


## 0..1: how hard the hit was, against [constant FULL_DAMAGE].
static func weight(amount: float) -> float:
	return clampf(amount / FULL_DAMAGE, 0.0, 1.0)


static func volume_for(amount: float) -> float:
	return lerpf(MIN_VOLUME, 1.0, weight(amount))


static func pitch_for(amount: float) -> float:
	return lerpf(PITCH_LIGHT, PITCH_HEAVY, weight(amount))


## Plays [param id] on [param audio] scaled by [param amount], unless [param lethal]. Returns the handle, 0 when nothing played.
static func play(audio: Object, id: StringName, amount: float, lethal: bool = false) -> int:
	if lethal or audio == null:
		return 0
	return int(audio.call("play", id, volume_for(amount), pitch_for(amount)))
