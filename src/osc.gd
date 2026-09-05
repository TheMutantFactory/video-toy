extends Node
## OSC over UDP (autoload "Osc"). Listens on `port` (env VIDEO_TOY_OSC_PORT,
## default 9000) and hands every message to MidiMap as a learnable
## controller ("osc:<address>"), with two direct routes that need no learn:
##   /vt/param/<id>  <float 0..1>     /vt/action/<id>
## Messages and bundles are parsed here; the codec is static and tested.

const DEFAULT_PORT := 9000

var port := DEFAULT_PORT
var listening := false
var last_text := ""
var received := 0
var _udp := PacketPeerUDP.new()
var _midi: Node


func _ready() -> void:
	var env := OS.get_environment("VIDEO_TOY_OSC_PORT")
	if env.is_valid_int():
		port = int(env)
	_midi = get_node_or_null("/root/MidiMap")
	start()


func start() -> void:
	stop()
	listening = _udp.bind(port, "0.0.0.0") == OK
	if not listening:
		push_warning("OSC: could not bind UDP port %d" % port)


func stop() -> void:
	if listening:
		_udp.close()
	listening = false


func _process(_delta: float) -> void:
	if not listening:
		return
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		for m in parse(pkt):
			_deliver(m)


func _deliver(m: Dictionary) -> void:
	received += 1
	var addr: String = m["address"]
	var args: Array = m["args"]
	var value := 1.0
	if args.size() > 0 and (args[0] is float or args[0] is int):
		value = float(args[0])
	last_text = "%s %s" % [addr, ("%.2f" % value) if args.size() > 0 else ""]
	if _midi:
		_midi.feed_osc(addr, value)


# ---------------------------------------------------------------- codec
## Packet -> Array of {address, args}. Handles messages and (nested) bundles.
static func parse(pkt: PackedByteArray) -> Array:
	var out: Array = []
	if pkt.size() < 4:
		return out
	if pkt.slice(0, 8).get_string_from_ascii() == "#bundle":
		var pos := 16                                     # "#bundle\0" + 64-bit timetag
		while pos + 4 <= pkt.size():
			var size := pkt.decode_u32(pos)
			size = _swap32(size)
			pos += 4
			if size <= 0 or pos + size > pkt.size():
				break
			out.append_array(parse(pkt.slice(pos, pos + size)))
			pos += size
		return out
	var r := [0]
	var address := _read_string(pkt, r)
	if not address.begins_with("/"):
		return out
	var args: Array = []
	if r[0] < pkt.size() and pkt[r[0]] == 44:               # ','
		var tags := _read_string(pkt, r).substr(1)
		for t in tags:
			match t:
				"f":
					if r[0] + 4 > pkt.size(): break
					args.append(_be_float(pkt, r[0]))
					r[0] += 4
				"i":
					if r[0] + 4 > pkt.size(): break
					args.append(_be_int(pkt, r[0]))
					r[0] += 4
				"s":
					args.append(_read_string(pkt, r))
				"T": args.append(true)
				"F": args.append(false)
				"N": args.append(null)
				"d":
					if r[0] + 8 > pkt.size(): break
					var b := pkt.slice(r[0], r[0] + 8)
					b.reverse()
					args.append(b.decode_double(0))
					r[0] += 8
				_:
					pass
	out.append({"address": address, "args": args})
	return out


## Encode one message (floats, ints, strings, bools).
static func build(address: String, args: Array = []) -> PackedByteArray:
	var pkt := _pad_string(address)
	var tags := ","
	var body := PackedByteArray()
	for a in args:
		if a is float:
			tags += "f"
			var b := PackedByteArray()
			b.resize(4)
			b.encode_float(0, a)
			b.reverse()
			body.append_array(b)
		elif a is int:
			tags += "i"
			var b := PackedByteArray()
			b.resize(4)
			b.encode_s32(0, a)
			b.reverse()
			body.append_array(b)
		elif a is String:
			tags += "s"
			body.append_array(_pad_string(a))
		elif a is bool:
			tags += "T" if a else "F"
	pkt.append_array(_pad_string(tags))
	pkt.append_array(body)
	return pkt


static func _pad_string(s: String) -> PackedByteArray:
	var b := s.to_ascii_buffer()
	b.append(0)
	while b.size() % 4 != 0:
		b.append(0)
	return b


static func _read_string(pkt: PackedByteArray, r: Array) -> String:
	var start: int = r[0]
	var end := start
	while end < pkt.size() and pkt[end] != 0:
		end += 1
	var s := pkt.slice(start, end).get_string_from_ascii()
	end += 1
	while end % 4 != 0:
		end += 1
	r[0] = end
	return s


static func _be_float(pkt: PackedByteArray, at: int) -> float:
	var b := pkt.slice(at, at + 4)
	b.reverse()
	return b.decode_float(0)


static func _be_int(pkt: PackedByteArray, at: int) -> int:
	var b := pkt.slice(at, at + 4)
	b.reverse()
	return b.decode_s32(0)


static func _swap32(v: int) -> int:
	return ((v & 0xFF) << 24) | ((v & 0xFF00) << 8) | ((v >> 8) & 0xFF00) | ((v >> 24) & 0xFF)
