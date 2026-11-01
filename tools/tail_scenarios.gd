extends SceneTree

## Prints the tail weights, tightness, comb delay and body pitch the enclosure code gives each named room, as JSON, for
## tools/measure_tails.py.

const SCENARIOS := {
	"outdoor": [40.0, 0.92],
	"open room": [12.0, 0.33],
	"corridor": [3.4, 0.03],
	"closet": [1.3, 0.0],
	"hall": [30.0, 0.0],
}


func _init() -> void:
	var out := {}
	for name: String in SCENARIOS:
		var size: float = SCENARIOS[name][0]
		var open: float = SCENARIOS[name][1]
		var w := DotAudioEnclosure.tail_weights(size, open)
		var t := DotAudioEnclosure.tightness(size, open)
		var weights := {}
		for k in w:
			weights[String(k)] = w[k]
		out[name] = {"size": size, "open": open, "weights": weights, "tight": t,
				"tail_gain": 1.0 + DotAudioEnclosure.TIGHT_TAIL_GAIN * t,
				"loud_db": DotAudioEnclosure.TIGHT_LOUD_DB * t,
				"body_pitch": lerpf(1.0, DotAudioEnclosure.TIGHT_BODY_PITCH, t),
				"comb_ms": clampf(2.0 * size / DotAudioEnclosure.SPEED_OF_SOUND * 1000.0, 3.0, 60.0)}
	print("JSON:" + JSON.stringify(out))
	quit()
