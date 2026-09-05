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
## Gamepads and OSC are controllers too:
##   pad:<device>:axis:<n>  param: stick -1..1 -> 0..1, trigger 0..1; action: crossing 0.5
##   pad:<device>:btn:<n>   param: 1/0;  action: press
##   osc:<address>          param: first float arg (0..1); action: any message
##   /vt/param/<id> and /vt/action/<id> address params and actions directly.
##
## Audio bands are virtual controllers: audio_bindings maps an id to "bass",
## "mid", "high", "level" (params) or "beat" (actions); feed_audio() and
## feed_beat() emit exactly like a knob or a pad would.
##
## No dependency on other autoloads, so the smoke test can drive it with
## synthetic InputEventMIDI objects and band dictionaries.

signal param(id: String, value: float)
signal action(id: String)
signal learned(id: String, binding: String)
signal activity(text: String)

const PATH := "user://midi.json"

const AUDIO_PARAM_BANDS := ["", "bass", "mid", "high", "level"]
const AUDIO_ACTION_BANDS := ["", "beat"]

var last_source := ""              # "midi" | "pad" | "osc" | "audio" — who emitted last
var bindings := {}                 # message key -> id
var audio_bindings := {}           # id -> band
var armed_id := ""
var last_text := ""
var path := PATH
var _last_value := {}              # message key -> last raw 0..1 (edge detection)


func _ready() -> void:
	if DisplayServer.get_name() != "headless":      # CoreMIDI has no server to talk to headless
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
	audio_bindings.clear()
	save_to_disk()


func audio_binding_for(id: String) -> String:
	return str(audio_bindings.get(id, ""))


func set_audio_binding(id: String, band: String) -> void:
	if band == "":
		audio_bindings.erase(id)
	else:
		audio_bindings[id] = band
	save_to_disk()


## Cycle a row through the bands that make sense for it.
func cycle_audio_binding(id: String) -> String:
	var table: Array = AUDIO_ACTION_BANDS if id.begins_with("act:") else AUDIO_PARAM_BANDS
	var i := table.find(audio_binding_for(id))
	var band: String = table[(i + 1) % table.size()]
	set_audio_binding(id, band)
	return band


## Called every frame by AudioReact with 0..1 bands.
func feed_audio(bands: Dictionary) -> void:
	last_source = "audio"
	for id in audio_bindings:
		var band: String = audio_bindings[id]
		if bands.has(band) and not id.begins_with("act:"):
			param.emit(id, float(bands[band]))


## Called by AudioReact on each detected beat.
func feed_beat() -> void:
	last_source = "audio"
	for id in audio_bindings:
		if audio_bindings[id] == "beat" and id.begins_with("act:"):
			action.emit(id.trim_prefix("act:"))


static func describe(key: String) -> String:
	var p := key.split(":")
	match p[0]:
		"cc": return "CC %s ch%s" % [p[2], p[1]]
		"note": return "note %s ch%s" % [p[2], p[1]]
		"bend": return "bend ch%s" % p[1]
		"pad":
			if p.size() >= 4:
				return "pad%s %s %s" % [p[1], "axis" if p[2] == "axis" else "btn", p[3]]
		"osc": return "osc " + key.substr(4)
	return key


func _input(ev: InputEvent) -> void:
	if ev is InputEventMIDI:
		feed(ev)
	elif ev is InputEventJoypadMotion or ev is InputEventJoypadButton:
		feed_pad(ev)


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
	var is_off := ev.message == MIDI_MESSAGE_NOTE_OFF or (ev.message == MIDI_MESSAGE_NOTE_ON and ev.velocity == 0)
	var is_note := ev.message == MIDI_MESSAGE_NOTE_ON or ev.message == MIDI_MESSAGE_NOTE_OFF
	last_source = "midi"
	_handle(key, value, is_off, is_note, "%s = %d" % [describe(key), roundi(value * 127.0)])


## Gamepad: sticks and triggers are params, buttons are actions or 1/0 params.
func feed_pad(ev: InputEvent) -> void:
	last_source = "pad"
	if ev is InputEventJoypadMotion:
		var raw: float = ev.axis_value
		var trigger: bool = ev.axis == JOY_AXIS_TRIGGER_LEFT or ev.axis == JOY_AXIS_TRIGGER_RIGHT
		var value := clampf(raw if trigger else raw * 0.5 + 0.5, 0.0, 1.0)
		var key := "pad:%d:axis:%d" % [ev.device, ev.axis]
		# learning needs a deliberate move, not stick noise
		if armed_id != "" and absf(raw) < 0.5:
			return
		if absf(raw) < 0.08 and not trigger:
			value = 0.5
		_handle(key, value, false, false, "%s = %.2f" % [describe(key), value])
	elif ev is InputEventJoypadButton:
		var key := "pad:%d:btn:%d" % [ev.device, ev.button_index]
		_handle(key, 1.0 if ev.pressed else 0.0, not ev.pressed, true, "%s %s" % [describe(key), "down" if ev.pressed else "up"])


## OSC: /vt/param/<id> and /vt/action/<id> go straight through; anything else
## is a learnable "osc:<address>" controller.
func feed_osc(address: String, value: float) -> void:
	last_source = "osc"
	if address.begins_with("/vt/param/"):
		var id := address.trim_prefix("/vt/param/")
		last_text = "osc %s = %.2f" % [id, value]
		activity.emit(last_text)
		param.emit(id, clampf(value, 0.0, 1.0))
		return
	if address.begins_with("/vt/action/"):
		var id := address.trim_prefix("/vt/action/")
		last_text = "osc " + id
		activity.emit(last_text)
		action.emit(id)
		return
	_handle("osc:" + address, clampf(value, 0.0, 1.0), false, false, "%s = %.2f" % [describe("osc:" + address), value])


## Shared learn / dispatch. `is_note`: actions fire on press rather than on a
## value crossing 0.5; `is_off`: a release, never learned and never a param.
func _handle(key: String, value: float, is_off: bool, is_note: bool, text: String) -> void:
	last_text = text
	activity.emit(last_text)
	if armed_id != "" and not is_off:
		var old := binding_for(armed_id)          # steal the message from any earlier binding
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
		var rising := (not is_off and value > 0.0) if is_note else (value >= 0.5 and prev < 0.5)
		if rising:
			action.emit(id.trim_prefix("act:"))
	elif not is_off:
		param.emit(id, value)
	_last_value[key] = value


func save_to_disk() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"bindings": bindings, "audio": audio_bindings}, "\t"))
		f.close()


func load_from_disk() -> void:
	bindings = {}
	audio_bindings = {}
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("bindings") is Dictionary:
		for k in data["bindings"]:
			bindings[str(k)] = str(data["bindings"][k])
	if data is Dictionary and data.get("audio") is Dictionary:
		for k in data["audio"]:
			audio_bindings[str(k)] = str(data["audio"][k])
