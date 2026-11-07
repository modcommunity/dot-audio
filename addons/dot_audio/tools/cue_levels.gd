extends SceneTree

## Offline per-cue loudness, no audio device (the xvfb Dummy driver records silence):
## `godot --headless --path . --script res://addons/dot_audio/tools/cue_levels.gd -- --table=res://tools/my_cues.gd`.
## The table script (a RefCounted subclass) is the only per-game part:
##   rows() -> Array of {id, stream (AudioStream) or path (String), gain_db, bus, sustained, note}
##     gain_db is everything before the bus: the def's gain plus the level the game runs it at.
##   buses_db() -> {"Master": dB, "SFX": dB, ...}
## Effective = stream level + gain_db + bus + Master. Flags: peak over -1 dBFS or 0 (clip risk),
## silent or missing, more than HOT_DB over or COLD_DB under the median SFX-bus cue, and a
## sustained cue louder than the target. Exit 1 on a clipping, silent or missing cue.

const Meter := preload("cue_meter.gd")

const TARGET_LUFS := -16.0
const HOT_DB := 6.0
const COLD_DB := 15.0
const PEAK_WARN := -1.0


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var path := ""
	for a in args:
		if a.begins_with("--table="):
			path = a.get_slice("=", 1)
	var script := load(path) as GDScript
	if script == null:
		print("cue_levels: no table at '%s'" % path)
		return 2
	var table = script.new()
	var buses: Dictionary = table.buses_db()
	var master := float(buses.get("Master", 0.0))
	var rows: Array = []
	for r: Dictionary in table.rows():
		var m := _measure(r)
		var bus_name := str(r.get("bus", "SFX"))
		var gain := float(r.get("gain_db", 0.0)) + float(buses.get(bus_name, 0.0)) + master
		rows.append({
			"id": str(r["id"]), "bus": bus_name, "sustained": bool(r.get("sustained", false)),
			"ok": not m.is_empty(), "lufs": float(m.get("lufs", -120.0)) + gain, "peak": float(m.get("peak", -120.0)) + gain,
			"raw_lufs": float(m.get("lufs", -120.0)), "note": str(r.get("note", "")),
		})
	var sfx := PackedFloat64Array()
	for r in rows:
		if r["ok"] and r["bus"] == "SFX" and r["lufs"] > -100.0:
			sfx.append(r["lufs"])
	sfx.sort()
	var median := sfx[sfx.size() / 2] if not sfx.is_empty() else 0.0
	var parts := PackedStringArray()
	for k in buses:
		parts.append("%s %.1f" % [k, buses[k]])
	print("buses: %s" % ", ".join(parts))
	print("reference: median SFX-bus cue %.1f LUFS (n=%d); hot > +%.0f, cold < -%.0f dB of it; target %.0f LUFS; peak warn %.0f dBFS" % [
		median, sfx.size(), HOT_DB, COLD_DB, TARGET_LUFS, PEAK_WARN])
	print("%-26s %-8s %-4s %8s %8s %8s  flags" % ["cue", "bus", "sust", "rawLUFS", "effLUFS", "effpeak"])
	var bugs := 0
	var loudest := {"id": "", "lufs": -999.0}
	for r in rows:
		var flags := PackedStringArray()
		if not r["ok"]:
			flags.append("MISSING/undecodable")
			bugs += 1
		elif r["lufs"] <= -100.0:
			flags.append("SILENT")
			bugs += 1
		else:
			if r["peak"] > 0.0:
				flags.append("CLIP(>0 dBFS)")
				bugs += 1
			elif r["peak"] > PEAK_WARN:
				flags.append("peak>-1")
			if r["bus"] == "SFX":
				if r["lufs"] > median + HOT_DB:
					flags.append("HOT %+.1f vs median" % (r["lufs"] - median))
				elif r["lufs"] < median - COLD_DB:
					flags.append("COLD %+.1f vs median" % (r["lufs"] - median))
			if r["sustained"] and r["lufs"] > loudest["lufs"]:
				loudest = r
			if r["sustained"] and r["lufs"] > TARGET_LUFS:
				flags.append("sustained over target")
		print("%-26s %-8s %-4s %8.1f %8.1f %8.1f  %s %s" % [r["id"], r["bus"], "yes" if r["sustained"] else "", r["raw_lufs"],
			r["lufs"], r["peak"], " ".join(flags), r["note"]])
	if loudest["id"] != "":
		print("loudest sustained cue: %s at %.1f LUFS (%+.1f vs %.0f target)" % [loudest["id"], loudest["lufs"], loudest["lufs"] - TARGET_LUFS, TARGET_LUFS])
	print("cue_levels: %d cues, %d bugs" % [rows.size(), bugs])
	return 1 if bugs > 0 else 0


func _measure(r: Dictionary) -> Dictionary:
	var src: Variant = r.get("stream", r.get("path", null))
	var d := {}
	if src is AudioStream:
		d = Meter.decode(src)
	elif src is String:
		d = Meter.decode_file(src)
	if d.is_empty() or (d["samples"] as PackedFloat32Array).is_empty():
		return {}
	return {"lufs": Meter.lufs(d["samples"], d["rate"]), "peak": Meter.peak_db(d["samples"])}
