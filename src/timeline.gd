class_name Timeline
## A loop of performed control events: params and actions with timestamps.
## Record up to MAX seconds, then loop. Pure data + logic; the stage owns
## the clock and dispatches through the same path as live controllers.

const MAX := 60.0
const PATH := "user://timeline.json"

var events: Array = []          # {t, kind: "param"|"action", id, value}
var length := 0.0
var recording := false
var playing := false
var _rec_start := 0.0
var _play_start := 0.0
var _play_prev := 0.0


func start_record(now: float) -> void:
	events = []
	length = 0.0
	recording = true
	playing = false
	_rec_start = now


func record(kind: String, id: String, value: float, now: float) -> bool:
	if not recording:
		return false
	var t := now - _rec_start
	if t > MAX:
		stop_record(now)
		return false
	events.append({"t": t, "kind": kind, "id": id, "value": value})
	return true


func stop_record(now: float) -> void:
	if not recording:
		return
	recording = false
	length = clampf(now - _rec_start, 0.0, MAX)


func has_loop() -> bool:
	return length > 0.05 and not events.is_empty()


func start_play(now: float) -> void:
	if not has_loop():
		return
	playing = true
	recording = false
	_play_start = now
	_play_prev = -1.0                                # so an event at t=0 fires on the first pass


func stop_play() -> void:
	playing = false


func position(now: float) -> float:
	return fmod(now - _play_start, length) if playing and length > 0.0 else 0.0


## Events due since the last call, in order, wrapping around the loop end.
func due(now: float) -> Array:
	if not playing or length <= 0.0:
		return []
	var pos := position(now)
	var out: Array = []
	if pos >= _play_prev:
		out = _between(_play_prev, pos)
	else:                                            # wrapped
		out = _between(_play_prev, length + 1.0) + _between(-1.0, pos)
	_play_prev = pos
	return out


func _between(t0: float, t1: float) -> Array:
	var out: Array = []
	for e in events:
		if e["t"] > t0 and e["t"] <= t1:
			out.append(e)
	return out


func save(path := PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"length": length, "events": events}, "\t"))
		f.close()


func load(path := PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary and data.get("events") is Array):
		return false
	events = []
	for e in data["events"]:
		if e is Dictionary:
			events.append({"t": float(e.get("t", 0.0)), "kind": str(e.get("kind", "param")), "id": str(e.get("id", "")), "value": float(e.get("value", 0.0))})
	length = float(data.get("length", 0.0))
	return has_loop()
