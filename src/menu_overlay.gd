extends CanvasLayer
## Always-on overlay owned by main: a ☰ button in the top-left corner and an
## Esc-toggled menu. The menu hosts the Attribution screen — a paginated list of
## every downloaded asset with links to the icon and creator pages.

signal navigate(name: String)

const PER_PAGE := 10
const NP := "https://thenounproject.com"

var _burger: Button
var _dim: ColorRect
var _panel: PanelContainer
var _menu: VBoxContainer
var _attrib: VBoxContainer
var _list: VBoxContainer
var _page_lbl: Label
var _page := 0


func _ready() -> void:
	layer = 50
	_burger = Button.new()
	_burger.text = "☰"
	_burger.add_theme_font_size_override("font_size", 28)
	_burger.custom_minimum_size = Vector2(52, 52)
	_burger.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_burger.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_burger.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_burger.offset_right = -16
	_burger.offset_bottom = -16
	_burger.tooltip_text = "Menu (Esc)"
	_burger.pressed.connect(toggle)
	add_child(_burger)

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close())
	_dim.visible = false
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.theme = UI.theme()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(900, 0)
	_panel.visible = false
	add_child(_panel)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 8)
	_panel.add_child(_menu)
	_menu.add_child(UI.title("Menu", 40))
	for m in [["Resume", "resume"], ["Attribution", "attribution"], ["Find Icons", "search"],
			["Play", "stage"], ["Settings", "settings"], ["Start screen", "start"], ["Quit", "quit"]]:
		_menu.add_child(UI.button(m[0], func(): _pick(m[1])))

	_attrib = VBoxContainer.new()
	_attrib.add_theme_constant_override("separation", 6)
	_attrib.visible = false
	_panel.add_child(_attrib)
	var head := HBoxContainer.new()
	head.add_child(UI.button("← Menu", func(): show_menu()))
	head.add_child(UI.hspace())
	head.add_child(UI.label("Attribution", 36, UI.ACCENT))
	_attrib.add_child(head)
	_attrib.add_child(UI.label("Every asset this toy has downloaded, with the license it came under. Click to open the icon or creator page.", 16, UI.DIM))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.custom_minimum_size = Vector2(0, PER_PAGE * 58)
	_attrib.add_child(_list)
	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	nav.add_child(UI.button("◀ Prev", func(): _go(_page - 1), 130))
	_page_lbl = UI.label("", 18, UI.DIM)
	nav.add_child(_page_lbl)
	nav.add_child(UI.button("Next ▶", func(): _go(_page + 1), 130))
	_attrib.add_child(nav)
	Ledger.changed.connect(func(): if _attrib.visible: _render_page())


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if is_open():
		close()
	else:
		show_menu()


func show_menu() -> void:
	_dim.visible = true
	_panel.visible = true
	_menu.visible = true
	_attrib.visible = false


func show_attribution() -> void:
	_dim.visible = true
	_panel.visible = true
	_menu.visible = false
	_attrib.visible = true
	_page = 0
	_render_page()


func close() -> void:
	_dim.visible = false
	_panel.visible = false


func _pick(what: String) -> void:
	match what:
		"resume": close()
		"attribution": show_attribution()
		_:
			close()
			navigate.emit(what)


func _go(p: int) -> void:
	_page = clampi(p, 0, Ledger.page_count(PER_PAGE) - 1)
	_render_page()


func _render_page() -> void:
	for c in _list.get_children():
		c.queue_free()
	var rows: Array = Ledger.page(_page, PER_PAGE)
	if rows.is_empty():
		_list.add_child(UI.label("Nothing downloaded yet. Find Icons to add some.", 18, UI.DIM))
	for e in rows:
		_list.add_child(_row(e))
	_page_lbl.text = "page %d / %d   ·   %d asset%s" % [_page + 1, Ledger.page_count(PER_PAGE),
		Ledger.count(), "" if Ledger.count() == 1 else "s"]


func _row(e: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := UI.label(Ledger.line_for(e), 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(l)
	text.add_child(UI.label(str(e.get("license", "")), 14, UI.DIM))
	h.add_child(text)
	var icon_link := str(e.get("permalink", ""))
	var creator_link := str(e.get("creator_permalink", ""))
	var b1 := UI.button("icon ↗", func(): _open(icon_link), 110)
	b1.disabled = icon_link == ""
	h.add_child(b1)
	var b2 := UI.button("creator ↗", func(): _open(creator_link), 130)
	b2.disabled = creator_link == ""
	h.add_child(b2)
	return h


func _open(link: String) -> void:
	if link.begins_with("http"):
		OS.shell_open(link)
	elif link != "":
		OS.shell_open(NP + link)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()
