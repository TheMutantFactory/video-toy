extends Node
## MIDI-learn (autoload "MidiMap"). Opens every MIDI input, and maps incoming
## messages to named params (continuous, 0..1) and actions (triggers).
##
## Learn: arm(id) then move a knob / hit a pad -> that message binds to id and
## `learned` fires. Bindings persist in user://midi.json.
##
##   CC        -> param: value/127        action: rising edge through 64
##   note on   -> param: velocity/127     action: trigger (velocity > 0)
##   pitch bend-> param: pitch/16383      action: rising edge through centre
##
## No dependency on other autoloads, so the smoke test can drive it with
## synthetic InputEventMIDI objects.

signal param(id: String, value: float)
signal action(id: String)
signal learned(id: String, binding: String)
signal activity(text: String)

const PATH := "user://midi.json"

var bindings := {}                 # message key -> id
var armed_id := ""
var last_text := ""
var path := PATH
var _last_value := {}              # message key -> last raw 0..1 (edge detection)


func _ready() -> void:
	OS.open_midi_inputs()
	load_from_disk()


func inputs() -> PackedStringArray:
	return OS.get_connected_midi_inputs()


func rescan() -> void:
	OS.close_midi_inputs()
	OS.open_midi_inputs()


func arm(id: String) -> void:
	armed_id = id


func disarm() -> void:
	armed_id = ""


func binding_for(id: String) -> String:
	for k in bindings:
		if bindings[k] == id:
			return k
	return ""


func unbind(id: String) -> void:
	var k := binding_for(id)
	if k != "":
		bindings.erase(k)
		save_to_disk()


func clear_all() -> void:
	bindings.clear()
	save_to_disk()


static func describe(key: String) -> String:
	var p := key.split(":")
	match p[0]:
		"cc": return "CC %s ch%s" % [p[2], p[1]]
		"note": return "note %s ch%s" % [p[2], p[1]]
		"bend": return "bend ch%s" % p[1]
	return key


func _input(ev: InputEvent) -> void:
	if ev is InputEventMIDI:
		feed(ev)


## Message -> (key, value 0..1). Empty key = ignored message.
static func decode(ev: InputEventMIDI) -> Array:
	match ev.message:
		MIDI_MESSAGE_CONTROL_CHANGE:
			return ["cc:%d:%d" % [ev.channel, ev.controller_number], ev.controller_value / 127.0]
		MIDI_MESSAGE_NOTE_ON:
			return ["note:%d:%d" % [ev.channel, ev.pitch], ev.velocity / 127.0]
		MIDI_MESSAGE_NOTE_OFF:
			return ["note:%d:%d" % [ev.channel, ev.pitch], 0.0]
		MIDI_MESSAGE_PITCH_BEND:
			return ["bend:%d" % ev.channel, ev.pitch / 16383.0]
	return ["", 0.0]


func feed(ev: InputEventMIDI) -> void:
	var d := decode(ev)
	var key: String = d[0]
	var value: float = d[1]
	if key == "":
		return
	last_text = "%s = %d" % [describe(key), roundi(value * 127.0)]
	activity.emit(last_text)

	var is_off := ev.message == MIDI_MESSAGE_NOTE_OFF or (ev.message == MIDI_MESSAGE_NOTE_ON and ev.velocity == 0)
	if armed_id != "" and not is_off:
		# steal the message from any earlier binding
		var old := binding_for(armed_id)
		if old != "":
			bindings.erase(old)
		bindings[key] = armed_id
		var id := armed_id
		armed_id = ""
		save_to_disk()
		learned.emit(id, describe(key))
		return

	if not bindings.has(key):
		_last_value[key] = value
		return
	var id: String = bindings[key]
	if id.begins_with("act:"):
		var prev: float = _last_value.get(key, 0.0)
		var rising := (value >= 0.5 and prev < 0.5) if key.begins_with("cc") or key.begins_with("bend") \
			else (ev.message == MIDI_MESSAGE_NOTE_ON and ev.velocity > 0)
		if rising:
			action.emit(id.trim_prefix("act:"))
	else:
		if not is_off:
			param.emit(id, value)
	_last_value[key] = value


func save_to_disk() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"bindings": bindings}, "\t"))
		f.close()


func load_from_disk() -> void:
	bindings = {}
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("bindings") is Dictionary:
		for k in data["bindings"]:
			bindings[str(k)] = str(data["bindings"][k])
