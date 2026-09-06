extends PanelContainer
## The control panel on the stage. Two columns: params (knobs) and actions
## (pads). Click a row to arm it, move a control to bind it. Right-click a row
## to unbind. The ♪ button on each row cycles an audio band (bass/mid/high/
## level for params, beat for actions). The host supplies the tables.

var params: Array = []             # [{id, label}]
var actions: Array = []            # [{id, label}]
var _rows := {}                    # full id -> Button
var _audio_btns := {}              # full id -> Button
var _mod_btns := {}                # param id -> Button (shape · rate)
var _depths := {}                  # param id -> HSlider
var _status: Label
var _inputs: Label
var _osc_line: Label


func _ready() -> void:
	custom_minimum_size = Vector2(760, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_child(UI.label("MIDI · pads · OSC · audio", 28, UI.ACCENT))
	head.add_child(UI.hspace(16))
	head.add_child(UI.button("Rescan", func():
		MidiMap.rescan()
		_refresh_inputs(), 110))
	head.add_child(UI.hspace(8))
	head.add_child(UI.button("Unbind all", func():
		MidiMap.clear_all()
		refresh(), 130))
	head.add_child(UI.hspace(8))
	head.add_child(UI.button("Launchpad map", func():
		var n := MidiMap.import_map(Templates.launchpad_bindings())
		_status.text = "Launchpad template: %d bindings merged (programmer mode, ch 1)" % n
		refresh(), 150))
	head.add_child(UI.hspace(4))
	head.add_child(UI.button("APC mini map", func():
		var n := MidiMap.import_map(Templates.apc_mini_bindings())
		_status.text = "APC mini template: %d bindings merged (ch 1)" % n
		refresh(), 140))
	head.add_child(UI.hspace(4))
	head.add_child(UI.button("Export TouchOSC", func():
		var files: Array = Templates.write_all(params, actions, "user://controllers")
		_status.text = "wrote %s to %s" % [", ".join(files), ProjectSettings.globalize_path("user://controllers")], 170))
	col.add_child(head)
	_inputs = UI.label("", 16, UI.DIM)
	col.add_child(_inputs)
	col.add_child(UI.label("Click a row, then move a knob / stick / fader or hit a pad / button / send an OSC message. Right-click to unbind. ♪ cycles an audio band. ~ cycles a modulator (sine, tri, square, saw, random walk, sample & hold, beat envelope; right-click: rate) and the slider is its depth around the knob's last value. ; closes.", 16, UI.DIM))
	_osc_line = UI.label("", 16, UI.DIM)
	col.add_child(_osc_line)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	col.add_child(cols)
	cols.add_child(_column("Params — knobs & faders", params, ""))
	cols.add_child(_column("Actions — pads & buttons", actions, "act:"))

	_status = UI.label("", 18)
	col.add_child(_status)
	MidiMap.learned.connect(func(id, binding):
		_status.text = "Bound %s → %s" % [_label_for(id), binding]
		refresh())
	MidiMap.activity.connect(func(text): _status.text = "last: " + text)
	_refresh_inputs()
	refresh()


func _column(title: String, table: Array, prefix: String) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UI.label(title, 18, UI.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for e in table:
		var full: String = prefix + e["id"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			MidiMap.arm(full)
			refresh())
		b.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				MidiMap.unbind(full)
				if MidiMap.armed_id == full:
					MidiMap.disarm()
				refresh())
		row.add_child(b)
		var a := Button.new()
		a.custom_minimum_size = Vector2(74, 36)
		a.tooltip_text = "audio band driving this"
		a.pressed.connect(func():
			MidiMap.cycle_audio_binding(full)
			refresh())
		row.add_child(a)
		if prefix == "":
			var mb := Button.new()
			mb.custom_minimum_size = Vector2(92, 36)
			mb.tooltip_text = "modulator: click cycles the shape, right-click the rate"
			mb.pressed.connect(func():
				MidiMap.cycle_mod(full)
				refresh())
			mb.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					MidiMap.cycle_mod_rate(full)
					refresh())
			row.add_child(mb)
			var sl := HSlider.new()
			sl.min_value = 0.0
			sl.max_value = 1.0
			sl.step = 0.05
			sl.custom_minimum_size = Vector2(70, 36)
			sl.tooltip_text = "depth"
			sl.value_changed.connect(func(v: float): MidiMap.set_mod_depth(full, v))
			row.add_child(sl)
			_mod_btns[full] = mb
			_depths[full] = sl
		list.add_child(row)
		_rows[full] = b
		_audio_btns[full] = a
	return v


func _label_for(full: String) -> String:
	var id := full.trim_prefix("act:")
	for e in params + actions:
		if e["id"] == id:
			return e["label"]
	return id


func refresh() -> void:
	for full in _rows:
		var b: Button = _rows[full]
		var bound: String = MidiMap.binding_for(full)
		var armed: bool = MidiMap.armed_id == full
		b.text = "%s%s" % [_label_for(full), ("   ← move a control…" if armed else ("   [%s]" % MidiMap.describe(bound) if bound != "" else ""))]
		b.modulate = UI.ACCENT if armed else (Color.WHITE if bound != "" else UI.DIM)
		var band: String = MidiMap.audio_binding_for(full)
		var a: Button = _audio_btns[full]
		a.text = ("♪ " + band) if band != "" else "♪"
		a.modulate = Color.WHITE if band != "" else UI.DIM
		if _mod_btns.has(full):
			var m: Modulator = MidiMap.mod_for(full)
			var mb: Button = _mod_btns[full]
			mb.text = ("~ " + m.describe()) if m else "~"
			mb.modulate = Color.WHITE if m else UI.DIM
			var sl: HSlider = _depths[full]
			sl.visible = m != null
			if m:
				sl.set_value_no_signal(m.depth)


func _refresh_inputs() -> void:
	var names := MidiMap.inputs()
	var line := ("MIDI: " + ", ".join(names)) if names.size() > 0 else "MIDI: none found (plug in a controller and Rescan)"
	var pads := Input.get_connected_joypads()
	line += "   ·   gamepads: " + (", ".join(pads.map(func(i): return Input.get_joy_name(i))) if pads.size() > 0 else "none")
	_inputs.text = line
	_osc_line.text = ("OSC: listening on UDP %d — /vt/param/<id> <0..1>, /vt/action/<id>, or learn any address" % Osc.port) if Osc.listening \
		else "OSC: port %d not available (VIDEO_TOY_OSC_PORT to change)" % Osc.port
