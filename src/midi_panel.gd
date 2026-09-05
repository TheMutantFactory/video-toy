extends PanelContainer
## The MIDI-learn panel on the stage. Two columns: params (knobs) and actions
## (pads). Click a row to arm it, move a control to bind it. Right-click a row
## to unbind. The host supplies the tables; this panel only talks to MidiMap.

var params: Array = []             # [{id, label}]
var actions: Array = []            # [{id, label}]
var _rows := {}                    # full id -> Button
var _status: Label
var _inputs: Label


func _ready() -> void:
	custom_minimum_size = Vector2(760, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_child(UI.label("MIDI learn", 28, UI.ACCENT))
	head.add_child(UI.hspace(16))
	head.add_child(UI.button("Rescan", func():
		MidiMap.rescan()
		_refresh_inputs(), 110))
	head.add_child(UI.hspace(8))
	head.add_child(UI.button("Unbind all", func():
		MidiMap.clear_all()
		refresh(), 130))
	col.add_child(head)
	_inputs = UI.label("", 16, UI.DIM)
	col.add_child(_inputs)
	col.add_child(UI.label("Click a row, then move a knob or hit a pad. Right-click a row to unbind. ; closes.", 16, UI.DIM))

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
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 36)
		b.pressed.connect(func():
			MidiMap.arm(full)
			refresh())
		b.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				MidiMap.unbind(full)
				if MidiMap.armed_id == full:
					MidiMap.disarm()
				refresh())
		list.add_child(b)
		_rows[full] = b
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


func _refresh_inputs() -> void:
	var names := MidiMap.inputs()
	_inputs.text = ("inputs: " + ", ".join(names)) if names.size() > 0 else "inputs: none found (plug in a controller and Rescan)"
