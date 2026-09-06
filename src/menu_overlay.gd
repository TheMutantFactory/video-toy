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
	for m in [["Resume", "resume"], ["Panic — known-good look", "panic"], ["Blackout", "blackout"],
			["Attribution", "attribution"], ["Export rig (zip)", "rig_export"], ["Import rig…", "rig_import"],
			["Render 20 s clip (offline)", "clip"], ["Find Icons", "search"],
			["Play", "stage"], ["Scenes", "scenes"], ["Settings", "settings"], ["Start screen", "start"], ["Quit", "quit"]]:
		_menu.add_child(UI.button(m[0], func(): _pick(m[1])))

	_attrib = VBoxContainer.new()
	_attrib.add_theme_constant_override("separation", 6)
	_attrib.visible = false
	_panel.add_child(_attrib)
	var head := HBoxContainer.new()
	head.add_child(UI.button("← Menu", func(): show_menu()))
	head.add_child(UI.hspace())
	head.add_child(UI.label("Attribution", 36, UI.ACCENT))
	head.add_child(UI.hspace(16))
	head.add_child(UI.button("Copy credits", func():
		DisplayServer.clipboard_set(Ledger.credits_text())
		_page_lbl.text = "credits copied to the clipboard (%d assets)" % Ledger.count(), 160))
	head.add_child(UI.hspace(6))
	head.add_child(UI.button("Save credits.txt", func():
		var p := Ledger.write_credits()
		_page_lbl.text = ("saved " + ProjectSettings.globalize_path(p)) if p != "" else "could not write credits.txt", 190))
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
		"clip":
			var out: String = get_parent().render_clip(20.0)
			_note(("rendering 20 s at 60 fps in a second Godot; the movie lands at " + out) if out != "" else "could not start the render")
		"rig_export":
			var p := Rig.default_export_path()
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://rigs"))
			var n := Rig.export(p)
			_note("exported %d files to %s" % [n, ProjectSettings.globalize_path(p)] if n >= 0 else "could not write the rig")
		"rig_import":
			var dlg := FileDialog.new()
			dlg.access = FileDialog.ACCESS_FILESYSTEM
			dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			dlg.filters = PackedStringArray(["*.zip ; Video Toy rig"])
			dlg.use_native_dialog = true
			dlg.title = "Import a Video Toy rig"
			add_child(dlg)
			dlg.file_selected.connect(func(path: String):
				_note(import_rig(path))
				dlg.queue_free())
			dlg.canceled.connect(func(): dlg.queue_free())
			dlg.popup_centered(Vector2i(900, 600))
		_:
			close()
			navigate.emit(what)


## A note under the menu title (the menu has no status line of its own).
func _note(text: String) -> void:
	if not _menu.has_node("Note"):
		var l := UI.label("", 16, UI.DIM)
		l.name = "Note"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_menu.add_child(l)
		_menu.move_child(l, 1)
	_menu.get_node("Note").text = text


## Unpack a rig and reload everything that reads user://.
static func import_rig(path: String) -> String:
	var n := Rig.import(path)
	if n < 0:
		return "that zip is not a Video Toy rig"
	Toolbox.load_from_disk()
	Ledger.load_from_disk()
	MidiMap.load_from_disk()
	Palettes._loaded = false
	IconMedia._svgs.clear()
	IconMedia._sdfs.clear()
	TextRaster._custom_checked = false
	return "imported %d files from %s — toolbox, presets, bindings, palettes reloaded" % [n, path.get_file()]


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
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE and not ev.shift_pressed:
		toggle()
		get_viewport().set_input_as_handled()
