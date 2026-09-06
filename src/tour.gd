class_name Tour
extends Control
## Five captions over the stage on the first launch: click, Space, Enter or
## the arrow keys advance, Esc skips, and the last one marks tour_seen in
## the settings. Esc menu → Take the tour brings it back. The harness sets
## `suppress` so captures and self-tests never see it.

signal finished(completed: bool)

const STEPS := [
	{"text": "Click anywhere: the selected icon appears there. Right-click removes the nearest one.\nSpace drops one somewhere; C clears the stage.", "at": Vector2(0.5, 0.42)},
	{"text": "This is the toolbox. 1-9 pick a slot; drop images, SVGs, words, videos or a .wav on a tile.\nFind Icons searches the Noun Project; Load demo shapes needs no key.", "at": Vector2(0.5, 0.78)},
	{"text": "Verbs are toggles on the selected slot and apply live: Q Wander, W Orbit, R Bounce,\nY Sparkle, Shift+Q Flock, Ctrl+P Physics… stack them.", "at": Vector2(0.28, 0.35)},
	{"text": "F turns feedback on. O K L V G are effects, Tab a scene, D glow, M the monitor.\nShift+F1 saves a look, F1 recalls it. Shift+Esc is panic: everything off, icons stay.", "at": Vector2(0.5, 0.2)},
	{"text": "? lists every key with a search box. H cycles the HUD. Ctrl+R surprises you,\nCtrl+Z takes it back. Esc is the menu. Have fun.", "at": Vector2(0.5, 0.5)},
]

static var suppress := false                # harness runs never show it
static var settings_path := Settings.PATH   # tests point this elsewhere

var step := -1
var _card: PanelContainer
var _label: Label
var _foot: Label


static func seen(path := "") -> bool:
	return bool(Settings.get_value("tour_seen", settings_path if path == "" else path))


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_card = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.94)
	sb.border_color = UI.ACCENT
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(18)
	_card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_card.add_child(col)
	_label = UI.label("", 22)
	_label.custom_minimum_size.x = 820
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_foot = UI.label("", 15, UI.DIM)
	_foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_foot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_foot)
	row.add_child(UI.button("Skip", func(): finish(false), 100))
	row.add_child(UI.button("Next ▶", advance, 120))
	col.add_child(row)
	add_child(_card)


func start() -> void:
	step = -1
	visible = true
	if get_parent():
		get_parent().move_child(self, -1)
	advance()


func advance() -> void:
	step += 1
	if step >= STEPS.size():
		finish(true)
		return
	var st: Dictionary = STEPS[step]
	_label.text = str(st["text"])
	_foot.text = "%d / %d   ·   click, Space or Enter: next   ·   Esc: skip" % [step + 1, STEPS.size()]
	call_deferred("_place", st["at"])


func _place(at: Vector2) -> void:
	var box := _card.get_combined_minimum_size()
	var target := Vector2(size.x * at.x, size.y * at.y) - box * 0.5
	_card.position = target.clamp(Vector2(20, 20), size - box - Vector2(20, 20))


func finish(completed: bool) -> void:
	visible = false
	step = -1
	Settings.set_value("tour_seen", true, settings_path)
	finished.emit(completed)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		accept_event()
		if ev.button_index == MOUSE_BUTTON_LEFT:
			advance()
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			finish(false)


func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible or not (ev is InputEventKey and ev.pressed):
		return
	match ev.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_RIGHT, KEY_DOWN:
			advance()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			finish(false)
			get_viewport().set_input_as_handled()
