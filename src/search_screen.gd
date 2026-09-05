extends Control
## Find Icons mode. Type a term, browse free thumbnails, click one to inspect
## its license, then "Add to toolbox" (one metered download). Keep exploring:
## more pages, new searches; the hotbar at the bottom shows what you've got.

signal navigate(name: String)

const HotbarScript = preload("res://src/hotbar.gd")
const NP := "https://thenounproject.com"
const THUMB := 150

var _query: LineEdit
var _status: Label
var _grid: GridContainer
var _more: Button
var _cursor := ""
var _last_query := ""
var _selected := {}

var _inspect_icon: TextureRect
var _inspect_term: Label
var _inspect_license: Label
var _inspect_attrib: Label
var _inspect_creator: Label
var _add_btn: Button
var _open_btn: Button
var _quota: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Palettes.bg(0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	# --- top bar
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	top.add_child(UI.button("← Back", func(): navigate.emit("start")))
	top.add_child(UI.label("Find Icons", 32, UI.ACCENT))
	top.add_child(UI.hspace(20))
	_query = LineEdit.new()
	_query.placeholder_text = "search the Noun Project… (e.g. cat, synthesizer, cake)"
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.custom_minimum_size = Vector2(0, 48)
	_query.text_submitted.connect(func(_t): _search())
	top.add_child(_query)
	top.add_child(UI.button("Search", _search, 140))
	_quota = UI.label("", 16, UI.DIM)
	top.add_child(_quota)

	_status = UI.label("Type a word and press Enter. Searching is free; adding an icon costs one download.", 18, UI.DIM)
	root.add_child(_status)

	# --- body: results | inspector
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 8
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	_more = UI.button("More results ↓", func(): _search(true), 220)
	_more.visible = false
	left.add_child(_more)

	var right := PanelContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	body.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	rv.add_child(UI.label("Inspect", 24, UI.ACCENT))
	_inspect_icon = TextureRect.new()
	_inspect_icon.custom_minimum_size = Vector2(300, 300)
	_inspect_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_inspect_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_inspect_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rv.add_child(_inspect_icon)
	_inspect_term = UI.label("Click a result to inspect it.", 26)
	_inspect_term.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_inspect_term)
	_inspect_license = UI.label("", 18, UI.DIM)
	_inspect_license.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_inspect_license)
	_inspect_attrib = UI.label("", 18)
	_inspect_attrib.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_inspect_attrib)
	_inspect_creator = UI.label("", 18, UI.DIM)
	_inspect_creator.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_inspect_creator)
	rv.add_child(UI.vspace(8))
	_add_btn = UI.button("Add to toolbox  (1 download)", _add_selected)
	_add_btn.disabled = true
	rv.add_child(_add_btn)
	_open_btn = UI.button("Open on thenounproject.com", func():
		if _selected.has("permalink"):
			OS.shell_open(NP + str(_selected["permalink"])))
	_open_btn.disabled = true
	rv.add_child(_open_btn)

	# --- hotbar
	var bar := HotbarScript.new()
	root.add_child(bar)

	NounApi.search_result.connect(_on_search_result)
	NounApi.download_result.connect(_on_download_result)
	_query.grab_focus()
	if not NounApi.has_creds():
		_status.text = "No API key found. Open Settings (or set NOUN_KEY / NOUN_SECRET) to search."


func _search(more := false) -> void:
	var q := _query.text.strip_edges()
	if q == "":
		return
	if not more:
		_cursor = ""
		_last_query = q
		for c in _grid.get_children():
			c.queue_free()
	elif q != _last_query:
		_search(false)
		return
	_status.text = "Searching “%s”…" % q
	_more.visible = false
	NounApi.search(q, 32, _cursor)


func _on_search_result(ok: bool, data: Dictionary, message: String) -> void:
	if not ok:
		_status.text = "Search failed: " + message
		return
	var icons: Array = data.get("icons", []) if data.get("icons") is Array else []
	_cursor = str(data.get("next_page", ""))
	var total := int(data.get("total", icons.size()))
	_status.text = "%d result%s for “%s” — click one to inspect, or keep exploring." % [
		total, "" if total == 1 else "s", _last_query]
	if icons.is_empty() and _grid.get_child_count() == 0:
		_status.text = "Nothing for “%s”. Try another word." % _last_query
	for icon in icons:
		_grid.add_child(_make_tile(icon))
	_more.visible = _cursor != ""
	_show_quota()


func _make_tile(icon: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(THUMB, THUMB)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.expand_icon = true
	b.tooltip_text = "%s\n%s" % [icon.get("term", ""), icon.get("license_description", "")]
	if Toolbox.has_id(str(icon.get("id", ""))):
		b.text = "✓"
	b.pressed.connect(func(): _inspect(icon))
	IconMedia.get_thumbnail(str(icon.get("thumbnail_url", "")), func(tex):
		if is_instance_valid(b) and tex:
			b.icon = tex)
	return b


func _inspect(icon: Dictionary) -> void:
	_selected = icon
	_inspect_term.text = str(icon.get("term", "?"))
	_inspect_license.text = "License: " + str(icon.get("license_description", "unknown"))
	_inspect_attrib.text = str(icon.get("attribution", ""))
	var creator: Dictionary = icon.get("creator", {}) if icon.get("creator") is Dictionary else {}
	_inspect_creator.text = "by " + str(creator.get("name", "?"))
	_inspect_icon.texture = null
	IconMedia.get_thumbnail(str(icon.get("thumbnail_url", "")), func(tex):
		if _selected == icon:
			_inspect_icon.texture = tex)
	var id := str(icon.get("id", ""))
	if Toolbox.has_id(id):
		_add_btn.text = "Already in toolbox"
		_add_btn.disabled = true
	elif Toolbox.is_full():
		_add_btn.text = "Toolbox full (9) — remove one in Play"
		_add_btn.disabled = true
	else:
		_add_btn.text = "Add to toolbox  (1 download)"
		_add_btn.disabled = false
	_open_btn.disabled = false


func _add_selected() -> void:
	if _selected.is_empty():
		return
	_add_btn.disabled = true
	_add_btn.text = "Downloading…"
	NounApi.download_icon(str(_selected.get("id", "")))


func _on_download_result(ok: bool, meta: Dictionary, svg_path: String, message: String) -> void:
	if not ok:
		_status.text = "Download failed: " + message
		_add_btn.text = "Add to toolbox  (1 download)"
		_add_btn.disabled = false
		return
	# The metered response carries the full record; fall back to the search
	# row for anything it lacks.
	var merged := _selected.duplicate()
	for k in meta:
		merged[k] = meta[k]
	Ledger.record(merged)
	var idx := Toolbox.add_from_meta(merged, svg_path)
	if idx < 0:
		_status.text = "Could not add (toolbox full?)."
		return
	_status.text = "Added “%s” to slot %d. Keep exploring, or press Play." % [merged.get("term", ""), idx + 1]
	_add_btn.text = "Already in toolbox"
	_add_btn.disabled = true
	for c in _grid.get_children():
		if c is Button and c.tooltip_text.begins_with(str(merged.get("term", "")) + "\n") and c.icon == _inspect_icon.texture:
			c.text = "✓"
	_show_quota()


func _show_quota() -> void:
	var u: Dictionary = NounApi.last_usage
	if u.is_empty():
		return
	var m: Dictionary = u.get("monthly", {}) if u.get("monthly") is Dictionary else {}
	if m.has("usage") and m.has("limit"):
		_quota.text = "quota %s/%s" % [m["usage"], m["limit"]]

