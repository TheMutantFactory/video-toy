class_name HelpOverlay
extends PanelContainer
## The keys reference on the stage: a tab per group, a search box, three
## balanced columns from Keys. ? (Shift+/) or the Keys button opens it,
## Esc closes it. Typing in the search box does not reach the stage.

signal closed

const WIDTH := 1560
const HEIGHT := 900

var _search: LineEdit
var _content: VBoxContainer
var _foot: Label
var _tab := ""                        # "" = every group
var _tab_buttons: Dictionary = {}     # tab -> Button
var _rows := 0


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	visible = false
	var sb := StyleBoxFlat.new()                   # opaque: it sits over the verb panel
	sb.bg_color = Color(0.06, 0.06, 0.1, 0.97)
	sb.border_color = UI.ACCENT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)
	head.add_child(UI.label("Keys", 30, UI.ACCENT))
	head.add_child(UI.hspace(14))
	var group := ButtonGroup.new()
	for t in [""] + tabs():
		var b := UI.button("All" if t == "" else t, func(): _pick_tab(t))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t == ""
		head.add_child(b)
		_tab_buttons[t] = b
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	_search = LineEdit.new()
	_search.placeholder_text = "search keys…"
	_search.custom_minimum_size = Vector2(300, 40)
	_search.text_changed.connect(func(_t): _rebuild())
	_search.gui_input.connect(_on_search_input)
	head.add_child(_search)
	head.add_child(UI.hspace(6))
	head.add_child(UI.button("Esc", close))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_foot = UI.label("", 14, UI.DIM)
	col.add_child(_foot)
	_rebuild()


static func tabs() -> Array:
	return Keys.groups().map(func(g): return str(g["tab"]))


## The groups that survive a tab and a query (pure, tested).
static func filter(groups: Array, tab: String, query: String) -> Array:
	var q := query.strip_edges().to_lower()
	var out: Array = []
	for g in groups:
		if tab != "" and str(g["tab"]) != tab:
			continue
		var rows: Array = []
		for r in g["rows"]:
			if q == "" or str(r[0]).to_lower().contains(q) or str(r[1]).to_lower().contains(q):
				rows.append(r)
		if not rows.is_empty():
			out.append({"title": g["title"], "tab": g["tab"], "rows": rows})
	return out


func open() -> void:
	visible = true
	_search.text = ""
	_pick_tab("")
	_tab_buttons[""].button_pressed = true
	if get_parent():
		get_parent().move_child(self, -1)              # above the hotbar and panels
	_search.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	_search.release_focus()
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func search(q: String) -> void:
	_search.text = q
	_rebuild()


func select_tab(tab: String) -> void:
	if _tab_buttons.has(tab):
		_tab_buttons[tab].button_pressed = true
	_pick_tab(tab)


func row_count() -> int:
	return _rows


func _pick_tab(tab: String) -> void:
	_tab = tab
	_rebuild()


func _on_search_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		accept_event()
		close()


func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	var gs := filter(Keys.groups(), _tab, _search.text)
	_rows = 0
	for g in gs:
		_rows += g["rows"].size()
	if gs.is_empty():
		_content.add_child(UI.label("nothing matches \"%s\"" % _search.text, 18, UI.DIM))
	else:
		_content.add_child(KeyCard.help(3, 15, gs))
	_foot.text = "%d keys   ·   ? (Shift+/) toggles this   ·   H cycles the HUD: full / compact / hidden   ·   ; controllers   ·   Esc menu   ·   printable card: docs/key-card.png" % _rows
