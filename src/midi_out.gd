class_name MidiOut
## MIDI out, over OSC: Godot has no MIDI output, so notes and events go as
## OSC messages to a bridge (docs/controllers/osc-midi-bridge.py turns
## /vt/midi/* into a virtual MIDI port; any OSC-aware host can take the
## /vt/event/* family directly). Static: the stage configures it from the
## settings and ticks the pending note-offs; actors fire notes.
##
##   /vt/midi/note_on  ch note vel     /vt/midi/note_off ch note
##   /vt/midi/cc       ch cc value     /vt/event/<name>  ...

const OscScript = preload("res://src/osc.gd")
const BASE_NOTE := 45                        # A2, the same ladder the Voice verb sings
const GATE := 0.15                           # seconds a spawn note stays on
const CH_SPAWN := 1
const CH_HIT := 2
const CH_PINATA := 3
const CH_BEAT := 10

static var enabled := false
static var host := "127.0.0.1"
static var port := 9001
static var sent := 0
static var last := ""
static var _udp := PacketPeerUDP.new()
static var _configured := false
static var _pending: Array = []              # [{at, ch, note}] note-offs still to send


static func configure(h: String, p: int, on: bool) -> void:
	host = h
	port = p
	enabled = on
	_udp = PacketPeerUDP.new()
	_configured = _udp.set_dest_address(h, p) == OK


static func note_for_slot(slot_index: int) -> int:
	return BASE_NOTE + int(IconVoice.NOTES[posmod(slot_index, IconVoice.NOTES.size())])


static func velocity_for_speed(speed: float) -> int:
	return clampi(int(lerpf(40.0, 127.0, clampf(speed / 700.0, 0.0, 1.0))), 1, 127)


static func velocity_for_height(y: float, height: float) -> int:
	return clampi(int(lerpf(127.0, 60.0, clampf(y / maxf(height, 1.0), 0.0, 1.0))), 1, 127)


static func send(address: String, args: Array = []) -> bool:
	if not enabled:
		return false
	if not _configured:
		configure(host, port, enabled)
		if not _configured:
			return false
	if _udp.put_packet(OscScript.build(address, args)) != OK:
		return false
	sent += 1
	last = address
	return true


static func note_on(ch: int, note: int, vel: int, gate := GATE) -> bool:
	var ok := send("/vt/midi/note_on", [ch, note, vel])
	if ok:
		_pending.append({"at": Time.get_ticks_msec() + int(gate * 1000.0), "ch": ch, "note": note})
	return ok


static func note_off(ch: int, note: int) -> bool:
	return send("/vt/midi/note_off", [ch, note])


static func cc(ch: int, number: int, value: int) -> bool:
	return send("/vt/midi/cc", [ch, number, clampi(value, 0, 127)])


static func event(name: String, args: Array = []) -> bool:
	return send("/vt/event/" + name, args)


## Send the note-offs whose gate has passed (the stage calls this each frame).
static func tick(now_ms := -1) -> int:
	if _pending.is_empty():
		return 0
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	var n := 0
	var keep: Array = []
	for p in _pending:
		if int(p["at"]) <= now:
			note_off(int(p["ch"]), int(p["note"]))
			n += 1
		else:
			keep.append(p)
	_pending = keep
	return n


static func pending() -> int:
	return _pending.size()


static func describe() -> String:
	return "%s:%d · %d sent" % [host, port, sent] if enabled else "off"
