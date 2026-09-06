extends RefCounted
## The cue runner: plays a CueSheet on the stage's clock — seconds from the
## start, bars and beats at the running clock's tempo (120 when none) —
## firing the same params and actions the learn table fires, ramping params
## from their last scripted value, showing notes in the HUD, looping if the
## sheet says so. Owned by the stage; `s` is the stage.

var s: Stage
var sheet := {}                  # CueSheet.parse() result
var resolved: Array = []
var playing := false
var time := 0.0
var next := 0                    # index into resolved
var fired := 0
var name := ""
var _ramps: Array = []           # [{id, from, to, t0, t1}]
var _last: Dictionary = {}       # param id -> last scripted value


func _init(stage: Stage) -> void:
	s = stage


func bpm() -> float:
	return Clock.bpm if Clock.running else 120.0


## Load text; returns the parse errors (empty = fine).
func load_text(text: String, label := "cue sheet") -> Array:
	sheet = CueSheet.parse(text)
	name = label
	resolved = CueSheet.resolve(sheet["cues"], bpm())
	return sheet["errors"]


func load_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return ["no such file: " + path]
	return load_text(FileAccess.get_file_as_string(path), path.get_file())


func start() -> void:
	if resolved.is_empty():
		return
	playing = true
	time = 0.0
	next = 0
	fired = 0
	_ramps.clear()
	s._steal_note = "cues: %s (%d cues, %.0f s%s)" % [name, resolved.size(), CueSheet.length(resolved), ", loops" if sheet.get("loop", false) else ""]
	s._update_hud()


func stop() -> void:
	playing = false
	_ramps.clear()
	s._update_hud()


func length() -> float:
	return CueSheet.length(resolved)


func _tick(delta: float) -> void:
	if not playing:
		return
	time += delta
	while next < resolved.size() and float(resolved[next]["t"]) <= time:
		_fire(resolved[next])
		next += 1
	var keep: Array = []
	for r in _ramps:
		var k := clampf((time - float(r["t0"])) / maxf(float(r["t1"]) - float(r["t0"]), 0.001), 0.0, 1.0)
		s._on_midi_param(str(r["id"]), lerpf(float(r["from"]), float(r["to"]), k))
		if k < 1.0:
			keep.append(r)
	_ramps = keep
	if next >= resolved.size() and _ramps.is_empty():
		if bool(sheet.get("loop", false)):
			time -= maxf(length(), 0.001)
			next = 0
		else:
			playing = false
			s._steal_note = "cues: %s done" % name
			s._update_hud()


func _fire(c: Dictionary) -> void:
	fired += 1
	match c["cmd"]:
		"action":
			s._on_midi_action(str(c["id"]))
		"param":
			var to := float(c["value"])
			var over := float(c.get("over_s", 0.0))
			if over > 0.0:
				_ramps.append({"id": c["id"], "from": float(_last.get(c["id"], 0.5)), "to": to, "t0": time, "t1": time + over})
			else:
				s._on_midi_param(str(c["id"]), to)
			_last[c["id"]] = to
		"note":
			s._steal_note = str(c["text"])
			s._update_hud()


func describe() -> String:
	if not playing:
		return ""
	return "cue %d/%d · %s" % [next, resolved.size(), _fmt(time)]


static func _fmt(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]
