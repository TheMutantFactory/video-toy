extends Control
## Start screen: pick a mode.

signal navigate(name: String)

const HotbarScript = preload("res://src/hotbar.gd")


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Palettes.bg(0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	add_child(col)

	col.add_child(UI.title("VIDEO TOY", 96))
	var sub := UI.label("icons · verbs · feedback  —  for Knobcon, streams and birthdays", 24, UI.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(UI.vspace(20))

	var modes := [
		["Find Icons", "search", "search the Noun Project and fill the toolbox"],
		["Play", "stage", "spawn icons, give them verbs, turn on feedback"],
		["Scenes", "scenes", "shader backgrounds and oscillators"],
		["Settings", "settings", "Noun Project API key"],
		["Attribution", "attribution", "every downloaded asset, with links"],
		["Quit", "quit", ""],
	]
	for m in modes:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		var b := UI.button(m[0], func(): navigate.emit(m[1]), 320)
		row.add_child(b)
		if m[2] != "":
			row.add_child(UI.hspace())
			row.add_child(UI.label(m[2], 18, UI.DIM))
		col.add_child(row)

	var demo_row := HBoxContainer.new()
	demo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	demo_row.add_child(UI.button("Load demo shapes", func():
		var n := DemoPack.load_into(Toolbox, Ledger)
		navigate.emit("stage") if n > 0 else null, 320))
	demo_row.add_child(UI.hspace())
	demo_row.add_child(UI.label("five built-in shapes, no API key needed", 18, UI.DIM))
	col.add_child(demo_row)

	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.add_theme_constant_override("separation", 8)
	var word := LineEdit.new()
	word.placeholder_text = "a word, an emoji, clock, countdown 23:59…"
	word.custom_minimum_size = Vector2(320, 48)
	wrow.add_child(word)
	var add_word := func():
		var idx := Toolbox.add_text(word.text)
		if idx >= 0:
			Ledger.record_local(Toolbox.slots[idx])
			navigate.emit("stage")
	word.text_submitted.connect(func(_t): add_word.call())
	wrow.add_child(UI.button("Add word", add_word, 140))
	wrow.add_child(UI.hspace())
	wrow.add_child(UI.label("words are icons · emoji keep colour · drop .svg .ttf .txt .ogv on Play", 18, UI.DIM))
	col.add_child(wrow)

	col.add_child(UI.vspace(30))
	var status := "%d icon%s in the toolbox" % [Toolbox.slots.size(), "" if Toolbox.slots.size() == 1 else "s"]
	if NounApi.has_creds():
		status += "  ·  API key found"
	else:
		status += "  ·  no API key yet (Settings)"
	var st := UI.label(status, 18, UI.DIM)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(st)

	var bar := HotbarScript.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -30
	add_child(bar)


func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_ENTER: navigate.emit("stage")
			KEY_SLASH: navigate.emit("search")
