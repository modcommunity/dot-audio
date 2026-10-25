class_name DotAudioStock
extends RefCounted

## The family's stock footsteps and ambience beds, as [DotAudioDef]s a game adds to its own
## catalogue. Files in [code]stock/[/code] beside this addon, every one CC0 (stock/CREDITS.md).
##
## [codeblock]
## DotAudioStock.add_to(catalogue)          # skips any id the game already defines
## [/codeblock]
##
## [b]Why an addon that "ships no audio" ships these.[/b] The rule is about the catalogue: a
## def names a path and never holds a stream, and that still holds. Footsteps and beds are
## the same thirty-nine files in every game, and thirteen vendored copies are thirteen
## places to fix a level. A game that wants its own defines the same id first and wins.

const FOOTSTEP_PREFIX := "footstep_"

## Canonical surfaces, each with five files.
const SURFACES: Array[StringName] = [&"concrete", &"wood", &"grass", &"snow", &"carpet", &"metal"]

## Names a map or a material is likely to use, folded onto a surface that has files. A map
## says `stone`; nobody should have to know the stock set calls it concrete.
const ALIASES := {
	"stone": &"concrete", "rock": &"concrete", "asphalt": &"concrete", "road": &"concrete",
	"tile": &"concrete", "brick": &"concrete", "cement": &"concrete", "pavement": &"concrete",
	"sidewalk": &"concrete", "kerb": &"concrete", "curb": &"concrete", "roof": &"concrete",
	"plank": &"wood", "wooden": &"wood", "floorboard": &"wood", "deck": &"wood",
	"parquet": &"wood", "gym": &"wood", "stage": &"wood",
	"dirt": &"grass", "earth": &"grass", "mud": &"grass", "sand": &"grass", "gravel": &"grass",
	"leaves": &"grass", "lawn": &"grass", "turf": &"grass", "field": &"grass",
	"foliage": &"grass", "slime": &"grass", "moss": &"grass",
	"ice": &"snow",
	"rug": &"carpet", "fabric": &"carpet", "mat": &"carpet", "cloth": &"carpet", "foam": &"carpet",
	"rubber": &"carpet", "linoleum": &"carpet", "mattress": &"carpet",
	"steel": &"metal", "iron": &"metal", "grate": &"metal", "grating": &"metal", "tin": &"metal",
}

## Ambience beds, each a seamless 32 s loop at -24 LUFS.
const BEDS: Array[StringName] = [
	&"amb_wind", &"amb_outdoor", &"amb_night", &"amb_city", &"amb_indoor",
	&"amb_eerie", &"amb_industrial", &"amb_cave", &"amb_rain",
]

# Per surface: gain that brings the five sets to one loudness (grass is recorded about
# 8 dB under the rest), and a pitch spread.
const _FOOTSTEP_GAIN := {
	&"concrete": 0.0, &"wood": 0.0, &"grass": 5.0, &"snow": 0.0, &"carpet": 2.0, &"metal": -2.0,
}


## Where the files are, found from this script so a delivered pack mounted under another
## root still finds them.
static func directory() -> String:
	var here: String = (DotAudioStock as Script).resource_path
	return here.get_base_dir().get_base_dir().path_join("stock")


## The stock mood set for [DotAmbience] (`moods.json` and its files, CC0, `moods/CREDITS.md`).
static func moods_directory() -> String:
	return directory().path_join("moods")


## A surface name from anything: a canonical one, an alias, or a longer name containing one
## ("Floor_Wood_02", "snowbank"). Empty when nothing matches.
static func surface_of(name: String) -> StringName:
	var low := name.to_lower()
	if low.is_empty():
		return &""
	for s in SURFACES:
		if low == String(s):
			return s
	if ALIASES.has(low):
		return ALIASES[low]
	for s in SURFACES:
		if low.contains(String(s)):
			return s
	for k: String in ALIASES:
		if low.contains(k):
			return ALIASES[k]
	return &""


## The sound id for a surface; an unknown one walks on concrete.
static func footstep_id(surface: StringName) -> StringName:
	var s := surface_of(String(surface))
	return StringName(FOOTSTEP_PREFIX + String(s if s != &"" else &"concrete"))


static func footstep_defs() -> Array[DotAudioDef]:
	var out: Array[DotAudioDef] = []
	var dir := directory().path_join("footsteps")
	for s in SURFACES:
		var d := DotAudioDef.new()
		d.id = StringName(FOOTSTEP_PREFIX + String(s))
		d.kind = DotAudioDef.Kind.POSITIONAL_3D
		d.bus = &"SFX"
		var variants := PackedStringArray()
		for i in 5:
			variants.append(dir.path_join("footstep_%s_%d.ogg" % [s, i]))
		d.path = variants[0]
		d.variants = variants
		d.gain_db = float(_FOOTSTEP_GAIN[s]) - 4.0
		d.pitch_min = 0.92
		d.pitch_max = 1.08
		# Low priority: a footstep is the first thing a full pool gives up, and a gunshot
		# never loses to one. Eight at once is a crowd; more is comb filtering.
		d.priority = 20
		d.max_concurrent = 8
		# Heard across a room and a little more: footsteps are information in a hiding game,
		# and at thirty metres they are nobody's business.
		d.unit_size = 3.0
		d.max_distance = 32.0
		d.tags = [&"footstep"]
		out.append(d)
	return out


static func ambience_defs() -> Array[DotAudioDef]:
	var out: Array[DotAudioDef] = []
	var dir := directory().path_join("ambience")
	for b in BEDS:
		var d := DotAudioDef.new()
		d.id = b
		d.path = dir.path_join(String(b) + ".ogg")
		d.kind = DotAudioDef.Kind.FLAT
		d.bus = &"Ambience"
		d.looping = true
		# A bed is never stolen: a silent stretch where the world was is worse than one
		# missing gunshot. Two at once is a crossfade.
		d.priority = 95
		d.max_concurrent = 2
		d.max_distance = 0.0
		d.tags = [&"ambience"]
		out.append(d)
	return out


## Every stock id, footsteps then beds: for a game whose suite asserts its id list is whole.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in SURFACES:
		out.append(StringName(FOOTSTEP_PREFIX + String(s)))
	out.append_array(BEDS)
	return out


## Adds every stock def whose id the catalogue does not already have. Returns how many.
static func add_to(catalogue: DotAudioCatalogue) -> int:
	var added := 0
	for d in footstep_defs() + ambience_defs():
		if catalogue.has(d.id):
			continue
		catalogue.add(d)
		added += 1
	return added
