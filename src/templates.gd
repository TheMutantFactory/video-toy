class_name Templates
## Controller layouts generated from the stage's param / action tables:
##   - TouchOSC Mk1 ".touchosc" (a zip holding index.xml; Mk2 imports it) and
##     Mk2 ".tosc" (zlib-compressed lexml) - every param a fader, every action
##     a button, addressed /vt/param/<id> and /vt/action/<id>: no learning.
##   - Launchpad (programmer mode) and APC mini default binding maps for
##     MidiMap: slots, verbs, presets and show actions on the grid.
## Pure string / dictionary builders; the stage supplies the tables.

const PAGE_W := 1024
const PAGE_H := 768


static func _b64(s: String) -> String:
	return Marshalls.utf8_to_base64(s)


static func _esc(s: String) -> String:
	return s.xml_escape()


# ---------------------------------------------------------------- TouchOSC Mk1
static func touchosc_xml(params: Array, actions: Array) -> String:
	var out := '<?xml version="1.0" encoding="UTF-8"?>\n<layout version="17" mode="1" orientation="horizontal">\n'
	# page 1: params as vertical faders, 8 per row
	out += '<tabpage name="%s" scalef="0.0" scalet="1.0">\n' % _b64("Params")
	var cols := 8
	var fw := 112
	var fh := 118
	var lh := 22
	for i in params.size():
		var p: Dictionary = params[i]
		var x := 8 + (i % cols) * (fw + 14)
		var y := 8 + (i / cols) * (fh + lh + 12)
		out += '<control name="%s" x="%d" y="%d" w="%d" h="%d" color="red" scalef="0.0" scalet="1.0" type="faderv" response="absolute" inverted="false" centered="false" osc_cs="/vt/param/%s"></control>\n' % [
			_b64(p["id"]), x, y, fw, fh, p["id"]]
		out += '<control name="%s" x="%d" y="%d" w="%d" h="%d" color="gray" type="labelv" text="%s" size="11" background="false" outline="false"></control>\n' % [
			_b64("l_" + p["id"]), x, y + fh + 2, fw, lh, _b64(p["label"])]
	out += '</tabpage>\n'
	# page 2+: actions as push buttons, 8 per row, 9 rows per page
	var per_page := 8 * 9
	var page := 0
	var i := 0
	while i < actions.size():
		out += '<tabpage name="%s" scalef="0.0" scalet="1.0">\n' % _b64("Actions %d" % (page + 1))
		for k in per_page:
			if i >= actions.size():
				break
			var a: Dictionary = actions[i]
			var x := 8 + (k % 8) * 126
			var y := 8 + (k / 8) * 82
			out += '<control name="%s" x="%d" y="%d" w="112" h="56" color="green" scalef="0.0" scalet="1.0" type="push" local_off="false" sp="true" sr="true" osc_cs="/vt/action/%s"></control>\n' % [
				_b64(a["id"]), x, y, a["id"]]
			out += '<control name="%s" x="%d" y="%d" w="112" h="20" color="gray" type="labelv" text="%s" size="10" background="false" outline="false"></control>\n' % [
				_b64("l_" + a["id"]), x, y + 58, _b64(a["label"])]
			i += 1
		out += '</tabpage>\n'
		page += 1
	out += '</layout>\n'
	return out


## The .touchosc container: a zip with index.xml.
static func write_touchosc(path: String, xml: String) -> bool:
	var z := ZIPPacker.new()
	if z.open(ProjectSettings.globalize_path(path)) != OK:
		return false
	z.start_file("index.xml")
	z.write_file(xml.to_utf8_buffer())
	z.close_file()
	z.close()
	return true


# ---------------------------------------------------------------- TouchOSC Mk2
static func _prop_s(key: String, value: String) -> String:
	return '<property type="s"><key>%s</key><value>%s</value></property>' % [key, _esc(value)]


static func _prop_r(key: String, x: int, y: int, w: int, h: int) -> String:
	return '<property type="r"><key>%s</key><value><x>%d</x><y>%d</y><w>%d</w><h>%d</h></value></property>' % [key, x, y, w, h]


static func _prop_c(key: String, c: Color) -> String:
	return '<property type="c"><key>%s</key><value><r>%.3f</r><g>%.3f</g><b>%.3f</b><a>1</a></value></property>' % [key, c.r, c.g, c.b]


static func _osc_msg(address: String, with_value: bool) -> String:
	var args := ('<arguments><argument><type>VALUE</type><conversion>FLOAT</conversion><value>x</value><scaleMin>0</scaleMin><scaleMax>1</scaleMax></argument></arguments>'
		if with_value else '<arguments><argument><type>CONSTANT</type><conversion>FLOAT</conversion><value>1</value><scaleMin>0</scaleMin><scaleMax>1</scaleMax></argument></arguments>')
	var trig := '<triggers><trigger><var>x</var><condition>%s</condition></trigger></triggers>' % ("ANY" if with_value else "RISE")
	return ('<messages><osc><enabled>1</enabled><send>1</send><receive>1</receive><feedback>0</feedback><connections>11111</connections>'
		+ trig + '<path><partial><type>CONSTANT</type><conversion>STRING</conversion><value>%s</value><scaleMin>0</scaleMin><scaleMax>1</scaleMax></partial></path>' % _esc(address)
		+ args + '</osc></messages>')


static func _node(kind: String, name: String, x: int, y: int, w: int, h: int, color: Color, extra_props := "", messages := "") -> String:
	return '<node type="%s"><properties>%s%s%s%s</properties>%s</node>' % [
		kind, _prop_s("name", name), _prop_r("frame", x, y, w, h), _prop_c("color", color), extra_props, messages]


static func tosc_xml(params: Array, actions: Array) -> String:
	var pages := ""
	# params page
	var body := ""
	for i in params.size():
		var p: Dictionary = params[i]
		var x := 8 + (i % 8) * 126
		var y := 8 + (i / 8) * 152
		body += _node("FADER", p["id"], x, y, 112, 118, Color("#ff4fa3"), "", _osc_msg("/vt/param/" + p["id"], true))
		body += _node("LABEL", "l_" + p["id"], x, y + 120, 112, 22, Color(0.7, 0.7, 0.75), _prop_s("text", p["label"]))
	pages += _node("GROUP", "Params", 0, 0, PAGE_W, PAGE_H, Color(0.1, 0.1, 0.14), _prop_s("tag", "page")) .replace("</properties></node>", "</properties><children>%s</children></node>" % body)
	# action pages
	var per_page := 72
	var i := 0
	var page := 0
	while i < actions.size():
		body = ""
		for k in per_page:
			if i >= actions.size():
				break
			var a: Dictionary = actions[i]
			var x := 8 + (k % 8) * 126
			var y := 8 + (k / 8) * 82
			body += _node("BUTTON", a["id"], x, y, 112, 56, Color("#7cff6b"), "", _osc_msg("/vt/action/" + a["id"], false))
			body += _node("LABEL", "l_" + a["id"], x, y + 58, 112, 20, Color(0.7, 0.7, 0.75), _prop_s("text", a["label"]))
			i += 1
		pages += _node("GROUP", "Actions %d" % (page + 1), 0, 0, PAGE_W, PAGE_H, Color(0.1, 0.1, 0.14), _prop_s("tag", "page")).replace("</properties></node>", "</properties><children>%s</children></node>" % body)
		page += 1
	var root := _node("GROUP", "Video Toy", 0, 0, PAGE_W, PAGE_H, Color(0.06, 0.06, 0.09)).replace("</properties></node>", "</properties><children>%s</children></node>" % pages)
	return '<?xml version="1.0" encoding="UTF-8"?>\n<lexml version="3">%s</lexml>\n' % root


## The .tosc container: zlib-compressed XML.
static func write_tosc(path: String, xml: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(xml.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE))
	f.close()
	return true


# ---------------------------------------------------------------- MIDI grids
## Launchpad (Mini MK3 / X in programmer mode): pads are notes row*10+col,
## rows 1..8 bottom-up, cols 1..8, channel 1. Top row of round buttons: CC 91-98.
static func launchpad_bindings() -> Dictionary:
	var b := {}
	var row := func(r: int, ids: Array) -> void:
		for c in mini(8, ids.size()):
			b["note:1:%d" % (r * 10 + c + 1)] = ids[c]
	row.call(1, ["act:slot_1", "act:slot_2", "act:slot_3", "act:slot_4", "act:slot_5", "act:slot_6", "act:slot_7", "act:slot_8"])
	row.call(2, ["act:verb_wander", "act:verb_orbit", "act:verb_spin", "act:verb_bounce", "act:verb_pulse", "act:verb_sparkle", "act:verb_rainbow", "act:verb_swarm"])
	row.call(3, ["act:verb_flock", "act:verb_field", "act:verb_morph", "act:verb_outline", "act:verb_lorenz", "act:verb_rossler", "act:verb_clifford", "act:verb_dejong"])
	row.call(4, ["act:preset_1", "act:preset_2", "act:preset_3", "act:preset_4", "act:preset_5", "act:preset_6", "act:preset_7", "act:preset_8"])
	row.call(5, ["act:spawn", "act:spawn_solid", "act:spawn_formation", "act:mosaic", "act:clear", "act:scatter", "act:next_shape", "act:recolor"])
	row.call(6, ["act:feedback", "act:glow", "act:chroma", "act:quantise", "act:slit", "act:next_scene", "act:particles", "act:rd"])
	row.call(7, ["act:next_palette", "act:monitor", "act:webcam", "act:evolve", "act:evolve_keep", "act:evolve_discard", "act:timeline_record", "act:timeline_play"])
	row.call(8, ["act:panic", "act:blackout", "act:prev_preset", "act:next_preset", "act:prev_bank", "act:next_bank", "act:clock_internal", "act:syphon"])
	for c in 8:
		b["cc:1:%d" % (91 + c)] = ["act:attract", "act:screenshot", "act:ticker", "act:credits_roll", "act:quality", "act:cam_auto", "act:draw_mode", "act:audio_source"][c]
	return b


## APC mini (mk1/mk2): 8x8 grid notes 0..63 (row 0 bottom), 8 faders CC 48-55,
## master fader CC 56, channel 1.
static func apc_mini_bindings() -> Dictionary:
	var b := {}
	var faders := ["fb_zoom", "fb_twist", "fb_fade", "glow", "fb_warp", "scene_speed", "pixelate", "kaleido"]
	for i in faders.size():
		b["cc:1:%d" % (48 + i)] = faders[i]
	b["cc:1:56"] = "preset_fade"
	var rows := [
		["act:slot_1", "act:slot_2", "act:slot_3", "act:slot_4", "act:slot_5", "act:slot_6", "act:slot_7", "act:slot_8"],
		["act:verb_wander", "act:verb_orbit", "act:verb_spin", "act:verb_bounce", "act:verb_pulse", "act:verb_sparkle", "act:verb_rainbow", "act:verb_swarm"],
		["act:verb_flock", "act:verb_field", "act:verb_morph", "act:verb_outline", "act:verb_lorenz", "act:verb_rossler", "act:verb_clifford", "act:verb_dejong"],
		["act:preset_1", "act:preset_2", "act:preset_3", "act:preset_4", "act:preset_5", "act:preset_6", "act:preset_7", "act:preset_8"],
		["act:spawn", "act:spawn_solid", "act:spawn_formation", "act:mosaic", "act:clear", "act:scatter", "act:next_shape", "act:recolor"],
		["act:feedback", "act:glow", "act:chroma", "act:quantise", "act:slit", "act:next_scene", "act:particles", "act:rd"],
		["act:next_palette", "act:monitor", "act:webcam", "act:evolve", "act:evolve_keep", "act:evolve_discard", "act:timeline_record", "act:timeline_play"],
		["act:panic", "act:blackout", "act:prev_preset", "act:next_preset", "act:prev_bank", "act:next_bank", "act:clock_internal", "act:syphon"],
	]
	for r in rows.size():
		for c in 8:
			b["note:1:%d" % (r * 8 + c)] = rows[r][c]
	return b


## Write every template into `dir`. Returns the file names written.
static func write_all(params: Array, actions: Array, dir: String) -> Array:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var out: Array = []
	if write_touchosc(dir.path_join("video-toy.touchosc"), touchosc_xml(params, actions)):
		out.append("video-toy.touchosc")
	if write_tosc(dir.path_join("video-toy.tosc"), tosc_xml(params, actions)):
		out.append("video-toy.tosc")
	for pair in [["launchpad.json", launchpad_bindings()], ["apc-mini.json", apc_mini_bindings()]]:
		var f := FileAccess.open(dir.path_join(pair[0]), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"bindings": pair[1], "audio": {}}, "\t"))
			f.close()
			out.append(pair[0])
	# a plain list of every address, for any other surface
	var f2 := FileAccess.open(dir.path_join("osc-addresses.txt"), FileAccess.WRITE)
	if f2:
		f2.store_string("Video Toy OSC (UDP 9000)\n\nParams (float 0..1):\n")
		for p in params:
			f2.store_string("  /vt/param/%s   %s\n" % [p["id"], p["label"]])
		f2.store_string("\nActions (any message with a non-zero first argument, or no argument):\n")
		for a in actions:
			f2.store_string("  /vt/action/%s   %s\n" % [a["id"], a["label"]])
		f2.store_string("\nOutgoing (Settings -> OSC out, default UDP 9001; osc-midi-bridge.py turns the /vt/midi family into a MIDI port):\n")
		for line in ["/vt/midi/note_on  ch note vel     spawn (ch 1, pitch by slot, velocity by height), collision (ch 2, by speed), pinata (ch 3, +12), beat (ch 10 note 36)",
				"/vt/midi/note_off ch note         after the gate (0.15 s spawn, 0.08 s hit, 0.3 s pinata, 0.05 s beat)",
				"/vt/midi/cc       ch cc value",
				"/vt/event/spawn     slot x y   /vt/event/collision slot speed   /vt/event/pinata slot   /vt/event/remove slot   /vt/event/beat index"]:
			f2.store_string("  " + line + "\n")
		f2.close()
		out.append("osc-addresses.txt")
	return out
