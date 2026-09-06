class_name CueSheet
## A cue sheet: one cue per line, a time and a command, the commands being
## the same params and actions the learn table and OSC use, plus ramps,
## notes and a loop. Pure: parse() reads text, resolve() turns bar / beat
## times into seconds for a tempo. The stage's cues module plays it.
##
##   # comment
##   0:00        action preset_1
##   0:04.5      param fb_zoom 0.7
##   bar 8       param fb_zoom 0.9 over 4 bars
##   beat 3      action spawn
##   +2          action spawn            (2 s after the previous cue)
##   +1 bar      note "verse two"        (shows in the HUD)
##   loop                                (the sheet restarts when it ends)
##
## Times: m:ss[.f], <n>s or a bare number (seconds), bar <n>, beat <n>,
## +<n> [s|bars|beats] relative to the previous cue. Bars are four beats.

const BEATS_PER_BAR := 4


static func parse(text: String) -> Dictionary:
	var cues: Array = []
	var errors: Array = []
	var loop := false
	var line_no := 0
	for raw in text.split("\n"):
		line_no += 1
		var line := raw.strip_edges()
		var hash := line.find("#")
		if hash >= 0:
			line = line.substr(0, hash).strip_edges()
		if line == "":
			continue
		if line.to_lower() == "loop":
			loop = true
			continue
		var when := _parse_when(line)
		if when.is_empty():
			errors.append("line %d: no time in '%s'" % [line_no, raw.strip_edges()])
			continue
		var rest: String = when["rest"]
		var cmd := _parse_command(rest)
		if cmd.is_empty():
			errors.append("line %d: no command in '%s'" % [line_no, rest])
			continue
		cmd["when"] = when["kind"]
		cmd["at"] = when["value"]
		cmd["relative"] = when["relative"]
		cmd["line"] = line_no
		cues.append(cmd)
	return {"cues": cues, "loop": loop, "errors": errors}


## {kind: "s"|"bar"|"beat", value, relative, rest}
static func _parse_when(line: String) -> Dictionary:
	var parts := line.split(" ", false)
	if parts.is_empty():
		return {}
	var head: String = parts[0]
	var relative := head.begins_with("+")
	if relative:
		head = head.substr(1)
	var kind := "s"
	var value := 0.0
	var used := 1
	if head == "bar" or head == "beat":
		if parts.size() < 2 or not parts[1].is_valid_float():
			return {}
		kind = head
		value = float(parts[1])
		used = 2
	elif head.contains(":"):
		var ms := head.split(":")
		if ms.size() != 2 or not ms[0].is_valid_int() or not ms[1].is_valid_float():
			return {}
		value = float(ms[0]) * 60.0 + float(ms[1])
	elif head.ends_with("s") and head.trim_suffix("s").is_valid_float():
		value = float(head.trim_suffix("s"))
	elif head.is_valid_float():
		value = float(head)
		if relative and parts.size() > 1 and parts[1] in ["bar", "bars", "beat", "beats", "s"]:
			kind = "bar" if parts[1].begins_with("bar") else ("beat" if parts[1].begins_with("beat") else "s")
			used = 2
	else:
		return {}
	var rest := " ".join(parts.slice(used))
	return {"kind": kind, "value": value, "relative": relative, "rest": rest}


## {cmd: "action"|"param"|"note", id, value, over, over_kind, text}
static func _parse_command(rest: String) -> Dictionary:
	var parts := rest.split(" ", false)
	if parts.is_empty():
		return {}
	match parts[0].to_lower():
		"action":
			if parts.size() < 2:
				return {}
			return {"cmd": "action", "id": parts[1]}
		"preset":
			if parts.size() < 2 or not parts[1].is_valid_int():
				return {}
			return {"cmd": "action", "id": "preset_%d" % int(parts[1])}
		"param":
			if parts.size() < 3 or not parts[2].is_valid_float():
				return {}
			var out := {"cmd": "param", "id": parts[1], "value": clampf(float(parts[2]), 0.0, 1.0), "over": 0.0, "over_kind": "s"}
			var oi := parts.find("over")
			if oi >= 0 and oi + 1 < parts.size():
				var num: String = parts[oi + 1]
				var unit: String = parts[oi + 2] if oi + 2 < parts.size() else ""
				for suffix in ["bars", "bar", "beats", "beat", "s"]:        # "6s", "4bars" glued on
					if num.ends_with(suffix) and num.trim_suffix(suffix).is_valid_float():
						unit = suffix
						num = num.trim_suffix(suffix)
						break
				if num.is_valid_float():
					out["over"] = float(num)
					out["over_kind"] = "bar" if unit.begins_with("bar") else ("beat" if unit.begins_with("beat") else "s")
			return out
		"note":
			var text := rest.substr(4).strip_edges().trim_prefix("\"").trim_suffix("\"")
			return {"cmd": "note", "text": text}
	return {}


## Seconds for a time of `kind` at `bpm`.
static func seconds(kind: String, value: float, bpm: float) -> float:
	var beat := 60.0 / maxf(bpm, 1.0)
	match kind:
		"bar": return value * BEATS_PER_BAR * beat
		"beat": return value * beat
	return value


## Absolute start times (and ramp lengths) in seconds, in sheet order.
static func resolve(cues: Array, bpm: float) -> Array:
	var out: Array = []
	var prev := 0.0
	for c in cues:
		var t := seconds(c["when"], float(c["at"]), bpm)
		if c["relative"]:
			t += prev
		var r: Dictionary = c.duplicate()
		r["t"] = t
		if c["cmd"] == "param":
			r["over_s"] = seconds(c["over_kind"], float(c["over"]), bpm)
		out.append(r)
		prev = t
	out.sort_custom(func(a, b): return a["t"] < b["t"] if a["t"] != b["t"] else a["line"] < b["line"])
	return out


static func length(resolved: Array) -> float:
	var end := 0.0
	for c in resolved:
		end = maxf(end, float(c["t"]) + float(c.get("over_s", 0.0)))
	return end


static func describe(c: Dictionary) -> String:
	match c["cmd"]:
		"action": return "action " + str(c["id"])
		"param": return "%s → %.2f%s" % [c["id"], c["value"], (" over %.1fs" % c["over_s"]) if float(c.get("over_s", 0.0)) > 0.0 else ""]
		"note": return "note: " + str(c["text"])
	return "?"
