extends HBoxContainer
## The Minecraft-style hotbar: nine slots showing the toolbox, selected one
## highlighted. Click a slot to select it. Lives on every screen that cares.

const SLOT := 88

var palette_index := 0
var _tiles: Array = []


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	for i in Toolbox.MAX_SLOTS:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(SLOT, SLOT)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		p.gui_input.connect(_on_slot_input.bind(i))
		var tex := TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(SLOT - 20, SLOT - 20)
		p.add_child(tex)
		var num := UI.label(str(i + 1), 14, UI.DIM)
		num.position = Vector2(6, 2)
		p.add_child(num)
		add_child(p)
		_tiles.append(p)
	Toolbox.changed.connect(refresh)
	Toolbox.selection_changed.connect(func(_i): refresh())
	refresh()


func refresh() -> void:
	for i in _tiles.size():
		var p: PanelContainer = _tiles[i]
		var tex: TextureRect = p.get_child(0)
		var filled := i < Toolbox.slots.size()
		p.add_theme_stylebox_override("panel", UI.slot_style(i == Toolbox.selected and filled, filled))
		if filled:
			var slot: Dictionary = Toolbox.slots[i]
			tex.texture = IconMedia.texture_for(str(slot.get("svg_path", "")))
			tex.modulate = Color.WHITE if Toolbox.is_raster_slot(slot) else Palettes.color(palette_index, int(slot.get("color_index", i)))
			p.tooltip_text = "%s\n%s" % [slot.get("term", ""), slot.get("attribution", "")]
		else:
			tex.texture = null
			p.tooltip_text = ""


func _on_slot_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		Toolbox.select(i)
