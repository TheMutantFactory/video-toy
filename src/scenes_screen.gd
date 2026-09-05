extends Control
## Scenes mode: a grid of live previews. Click one to make it the scene layer
## and go to Play; "None" turns the layer off.

signal navigate(name: String)

const TILE := Vector2(400, 225)


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Palettes.bg(0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 30)
	col.add_theme_constant_override("separation", 14)
	add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(UI.button("← Back", func(): navigate.emit("start")))
	top.add_child(UI.label("Scenes", 40, UI.ACCENT))
	top.add_child(UI.hspace(16))
	top.add_child(UI.label("shader sources behind everything · Tab cycles them in Play · knobs: speed, scale, bias", 18, UI.DIM))
	col.add_child(top)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	col.add_child(grid)
	grid.add_child(_tile("", "None", "off"))
	for s in Scenes.ALL:
		grid.add_child(_tile(s["id"], s["name"], s["kind"]))


func _tile(id: String, name: String, kind: String) -> Control:
	var v := VBoxContainer.new()
	var b := Button.new()
	b.custom_minimum_size = TILE
	b.pressed.connect(func():
		Scenes.current = id
		navigate.emit("stage"))
	if id != "":
		var r := ColorRect.new()
		r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
		r.color = Color.WHITE
		r.material = Scenes.material_for(id, 0)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(r)
	else:
		b.text = "no scene"
	if Scenes.current == id:
		b.add_theme_stylebox_override("normal", UI.slot_style(true, true))
	v.add_child(b)
	v.add_child(UI.label("%s   %s" % [name, "· oscillator" if kind == "osc" else ""], 20 if id != "" else 18))
	return v
