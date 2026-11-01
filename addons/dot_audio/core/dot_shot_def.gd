@tool
class_name DotShotDef
extends Resource

## One weapon's shot as layers: an attack (the crack), a body (the report), a tail per room class, a far set and an
## optional suppressed pair. Each layer holds 3-6 variant paths; a pack assigns its own. Paths only, never streams.

const ATTACK := &"attack"
const BODY := &"body"
const FAR := &"far"
const SUPPRESSED_BODY := &"suppressed_body"
const SUPPRESSED_FAR := &"suppressed_far"
## The tail classes an enclosure can name, smallest room first; each is the layer `tail_<class>`.
const TAIL_CLASSES: Array[StringName] = [&"small", &"medium", &"large", &"hall", &"outdoor"]

@export var id: StringName = &""
@export var attack: PackedStringArray = PackedStringArray()
@export var body: PackedStringArray = PackedStringArray()
@export var tail_small: PackedStringArray = PackedStringArray()
@export var tail_medium: PackedStringArray = PackedStringArray()
@export var tail_large: PackedStringArray = PackedStringArray()
@export var tail_hall: PackedStringArray = PackedStringArray()
@export var tail_outdoor: PackedStringArray = PackedStringArray()
@export var far: PackedStringArray = PackedStringArray()
@export var suppressed_body: PackedStringArray = PackedStringArray()
@export var suppressed_far: PackedStringArray = PackedStringArray()

## Gain on every layer, in dB.
@export_range(-24.0, 12.0, 0.1) var gain_db: float = 0.0
## Metres at full volume for the near layers and for the far set.
@export_range(0.1, 200.0, 0.1, "or_greater") var near_unit_size: float = 10.0
@export_range(0.1, 500.0, 0.1, "or_greater") var far_unit_size: float = 45.0
## Metres past which no layer plays.
@export_range(10.0, 5000.0, 1.0, "or_greater") var max_distance: float = 600.0


## The variant paths of [param layer] (a layer constant, or `tail_<class>`); empty for an unknown layer.
func layer(name: StringName) -> PackedStringArray:
	match name:
		ATTACK: return attack
		BODY: return body
		FAR: return far
		SUPPRESSED_BODY: return suppressed_body
		SUPPRESSED_FAR: return suppressed_far
		&"tail_small": return tail_small
		&"tail_medium": return tail_medium
		&"tail_large": return tail_large
		&"tail_hall": return tail_hall
		&"tail_outdoor": return tail_outdoor
	return PackedStringArray()


## Every layer that has files, in play order.
func layer_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for n: StringName in [ATTACK, BODY, &"tail_small", &"tail_medium", &"tail_large", &"tail_hall", &"tail_outdoor",
			FAR, SUPPRESSED_BODY, SUPPRESSED_FAR]:
		if not layer(n).is_empty():
			out.append(n)
	return out


## The catalogue id of one variant file.
func def_id(name: StringName, index: int) -> StringName:
	return StringName("%s/%s/%d" % [id, name, index])


## One [DotAudioDef] per variant file, ready for a catalogue: the player picks the file itself (no repeat), so the
## manager's own variant roll is never used.
func defs(tail_bus: StringName = &"SFX", bus: StringName = &"SFX") -> Array[DotAudioDef]:
	var out: Array[DotAudioDef] = []
	for name in layer_names():
		var is_far := name == FAR or name == SUPPRESSED_FAR
		var paths := layer(name)
		for i in paths.size():
			var d := DotAudioDef.new()
			d.id = def_id(name, i)
			d.path = paths[i]
			d.kind = DotAudioDef.Kind.POSITIONAL_3D
			d.bus = tail_bus if name.begins_with("tail_") else bus
			d.gain_db = gain_db
			d.unit_size = far_unit_size if is_far else near_unit_size
			d.max_distance = max_distance
			d.max_concurrent = 0
			d.cooldown_ms = 0
			d.priority = 60
			d.tags = [&"shot"]
			out.append(d)
	return out


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "a shot with no id")
	if body.is_empty() and suppressed_body.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "shot '%s' has no body layer" % id,
				"a shot needs `body` (or `suppressed_body`) files")
	if not suppressed_body.is_empty() and suppressed_far.is_empty() and far.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "shot '%s' is suppressed with nothing for a far listener" % id)
	return DotResult.success(null)
