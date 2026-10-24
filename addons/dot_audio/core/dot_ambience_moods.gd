class_name DotAmbienceMoods
extends RefCounted

## Which mood a map's own sound names point at: keywords in soundscape names and ambient
## sound files vote, the most votes wins. Small on purpose; a map that disagrees names its mood.

const OUTDOOR_NIGHT := &"outdoor_night"
const INDOOR_HALL := &"indoor_hall"
const INDUSTRIAL := &"industrial"
const CAVE_TUNNEL := &"cave_tunnel"
const SNOW_WIND := &"snow_wind"
const SWAMP := &"swamp"
const CITY_RUINS := &"city_ruins"
const INTERIOR_HORROR := &"interior_horror"

## Order is the tie-break: horror and caves outrank the generic ones.
const KEYWORDS := [
	[INTERIOR_HORROR, ["spooky", "infested", "zombie", "horror", "haunt", "ghost", "creep", "eerie", "morgue", "cellblock", "asylum", "chapel", "grave", "scary", "prison", "laborat", "_lab", "hospital", "manor", "goth"]],
	[CAVE_TUNNEL, ["cave", "tunnel", "mine", "drip", "sewer", "canal", "cellar", "basement", "underground", "crypt", "cavern", "pipe"]],
	[SNOW_WIND, ["snow", "wind", "frozen", "arctic", "antarctic", "blizzard", "mountain", "gust"]],
	[SWAMP, ["swamp", "marsh", "bog", "jungle", "slime", "river", "lake", "pond", "frog", "bubbl", "water"]],
	[INDUSTRIAL, ["industr", "factory", "machine", "generator", "turbine", "engine", "steam", "refinery", "transformer", "airconditioner", "boiler", "warehouse", "tank", "gas", "metal"]],
	[CITY_RUINS, ["city", "town", "street", "rain", "storm", "siren", "ruin", "highway", "traffic", "urban", "alley", "mall", "plaza"]],
	[INDOOR_HALL, ["hall", "corridor", "room", "office", "bedroom", "bathroom", "lobby", "library", "house", "interior", "apartment", "mansion", "school", "kitchen", "storage"]],
	[OUTDOOR_NIGHT, ["outside", "outdoor", "night", "forest", "field", "yard", "cricket", "woods", "camp"]],
]


## The mood the most [param names] point at, or [param fallback] when none does.
static func vote(names: Array, fallback: StringName = &"") -> StringName:
	var tally := {}
	for raw: Variant in names:
		var text := str(raw).to_lower()
		for row: Array in KEYWORDS:
			for word: String in row[1]:
				if text.contains(word):
					tally[row[0]] = int(tally.get(row[0], 0)) + 1
					break
	var best := fallback
	var most := 0
	for row: Array in KEYWORDS:
		var n := int(tally.get(row[0], 0))
		if n > most:
			most = n
			best = row[0]
	return best


## The names a converted map's `sounds` block offers: its soundscapes, and the stand-in and
## message of each ambient sound.
static func names_in(sounds: Dictionary) -> Array:
	var out: Array = []
	for rec: Variant in sounds.get("soundscapes", []):
		if rec is Dictionary:
			out.append(str((rec as Dictionary).get("soundscape", "")))
	for rec: Variant in sounds.get("ambient", []):
		if rec is Dictionary:
			out.append(str((rec as Dictionary).get("message", "")))
			out.append(str((rec as Dictionary).get("stand_in", "")))
	return out
