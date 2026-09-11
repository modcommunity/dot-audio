@tool
class_name DotAudioCatalogue
extends Resource

## Every sound a game has, as a document a server can check without a sound card.
##
## [b]It validates without loading anything.[/b] Same shape as dot-loadout's schema and
## dot-user-avatar's: a dedicated server with no audio device, and a headless suite, both
## check the whole catalogue and neither touches a file. What that buys is that a typo in a
## sound id fails a boot rather than producing silence in a firefight.

@export var defs: Array[DotAudioDef] = []

var _by_id: Dictionary = {}


func add(def: DotAudioDef) -> DotAudioCatalogue:
	defs.append(def)
	_by_id.clear()
	return self


func find(id: StringName) -> DotAudioDef:
	_ensure_index()
	return _by_id.get(id)


func has(id: StringName) -> bool:
	_ensure_index()
	return _by_id.has(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for d in defs:
		out.append(d.id)
	return out


func with_tag(tag: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for d in defs:
		if d.tags.has(tag):
			out.append(d.id)
	return out


func _ensure_index() -> void:
	if _by_id.size() == defs.size():
		return
	_by_id.clear()
	for d in defs:
		if d != null:
			_by_id[d.id] = d


func validate() -> DotResult:
	var seen := {}
	for d in defs:
		if d == null:
			return DotResult.fail(DotError.CODE_INVALID, "a null entry in the catalogue")
		var res := d.validate()
		if not res.ok:
			return res
		if seen.has(d.id):
			return DotResult.fail(
				DotError.CODE_INVALID,
				"sound id '%s' appears twice" % d.id,
				"the second one is unreachable, and nothing would ever say so"
			)
		seen[d.id] = true
	return DotResult.success(null)


## Which paths in this catalogue are not present. Asked, never assumed.
##
## Separate from [method validate] on purpose: a server validates a catalogue it has no
## files for and must not fail, while a client that is about to play something wants to
## know before a player hears nothing. Two questions, two methods.
func missing_files() -> PackedStringArray:
	var out := PackedStringArray()
	for d in defs:
		for p in _paths_of(d):
			if p != "" and not ResourceLoader.exists(p):
				out.append(p)
	return out


func _paths_of(d: DotAudioDef) -> PackedStringArray:
	if not d.variants.is_empty():
		return d.variants
	return PackedStringArray([d.path]) if d.path != "" else PackedStringArray()


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("catalogue: %d sounds" % defs.size())
	for d in defs:
		out.append("  %s" % d.describe_line())
	return out
