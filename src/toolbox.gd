extends Node
## The toolbox (autoload "Toolbox"): a Minecraft-style hotbar of picked icons.
## Each slot is a Dictionary:
##   id, term, svg_path, thumbnail_url, attribution, license, permalink,
##   creator_name, creator_permalink, verbs: Array[String], color_index: int
## Persisted to user://toolbox.json, which doubles as the attribution record.

signal changed
signal selection_changed(index: int)

const PATH := "user://toolbox.json"
const RASTER_DIR := "user://raster"
const TEXT_DIR := "user://text"
const MAX_SLOTS := 9

var slots: Array = []                      # Array of Dictionary
var selected := 0
var path := PATH                           # overridable for tests


func _ready() -> void:
	load_from_disk()


func is_full() -> bool:
	return slots.size() >= MAX_SLOTS


func has_id(id: String) -> bool:
	return index_of(id) >= 0


func index_of(id: String) -> int:
	for i in slots.size():
		if str(slots[i].get("id", "")) == id:
			return i
	return -1


## Build a slot from a Noun Project icon dict (the /v2/icon/{id} shape; the
## search shape works too, minus a few fields) plus the saved SVG path.
func add_from_meta(meta: Dictionary, svg_path: String) -> int:
	var id := str(meta.get("id", ""))
	if id == "":
		return -1
	var existing := index_of(id)
	if existing >= 0:
		slots[existing]["svg_path"] = svg_path
		save_to_disk()
		changed.emit()
		return existing
	if is_full():
		return -1
	var creator: Dictionary = meta.get("creator", {}) if meta.get("creator") is Dictionary else {}
	var slot := {
		"id": id,
		"term": str(meta.get("term", "")),
		"svg_path": svg_path,
		"thumbnail_url": str(meta.get("thumbnail_url", "")),
		"attribution": str(meta.get("attribution", "")),
		"license": str(meta.get("license_description", "")),
		"permalink": str(meta.get("permalink", "")),
		"creator_name": str(creator.get("name", "")),
		"creator_permalink": str(creator.get("permalink", "")),
		"verbs": [],
		"color_index": slots.size(),
		"added_at": int(Time.get_unix_time_from_system()),
	}
	slots.append(slot)
	selected = slots.size() - 1
	save_to_disk()
	changed.emit()
	selection_changed.emit(selected)
	return selected


## A raster image (PNG/JPG/...) as a slot. The file is copied into user://raster
## so the slot survives the original moving. Returns the slot index or -1.
func add_raster(src_path: String) -> int:
	if is_full():
		return -1
	var id := "raster-%d" % absi(src_path.hash())
	var existing := index_of(id)
	if existing >= 0:
		return existing
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RASTER_DIR))
	var dst := "%s/%s.%s" % [RASTER_DIR, id, src_path.get_extension().to_lower()]
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty():
		return -1
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return -1
	f.store_buffer(bytes)
	f.close()
	var slot := {
		"id": id, "kind": "raster",
		"term": src_path.get_file().get_basename(),
		"svg_path": dst, "thumbnail_url": "",
		"attribution": "%s — local image" % src_path.get_file(),
		"license": "user-supplied", "permalink": "",
		"creator_name": "", "creator_permalink": "",
		"verbs": [], "color_index": slots.size(),
		"added_at": int(Time.get_unix_time_from_system()),
	}
	slots.append(slot)
	selected = slots.size() - 1
	save_to_disk()
	changed.emit()
	selection_changed.emit(selected)
	return selected


## A word as a slot: rendered white-on-alpha like an icon, so it tints, gets
## verbs, wraps solids and extrudes. Returns the slot index or -1.
func add_text(word: String) -> int:
	word = word.strip_edges()
	if word == "" or is_full():
		return -1
	var id := "text-%d" % absi(word.hash())
	var existing := index_of(id)
	if existing >= 0:
		return existing
	var img := TextRaster.render(word)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEXT_DIR))
	var dst := "%s/%s.png" % [TEXT_DIR, id]
	if img.save_png(ProjectSettings.globalize_path(dst)) != OK:
		return -1
	var slot := {
		"id": id, "kind": "text",
		"term": word,
		"svg_path": dst, "thumbnail_url": "",
		"attribution": "“%s” — text" % word,
		"license": "yours", "permalink": "",
		"creator_name": "", "creator_permalink": "",
		"verbs": [], "color_index": slots.size(),
		"added_at": int(Time.get_unix_time_from_system()),
	}
	slots.append(slot)
	selected = slots.size() - 1
	save_to_disk()
	changed.emit()
	selection_changed.emit(selected)
	return selected


static func is_raster_slot(slot: Dictionary) -> bool:
	return str(slot.get("kind", "icon")) == "raster"


func remove(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	slots.remove_at(index)
	selected = clampi(selected, 0, maxi(slots.size() - 1, 0))
	save_to_disk()
	changed.emit()
	selection_changed.emit(selected)


func clear() -> void:
	slots.clear()
	selected = 0
	save_to_disk()
	changed.emit()
	selection_changed.emit(selected)


func select(index: int) -> void:
	if slots.is_empty():
		return
	selected = clampi(index, 0, slots.size() - 1)
	selection_changed.emit(selected)


func current() -> Dictionary:
	if slots.is_empty() or selected >= slots.size():
		return {}
	return slots[selected]


func toggle_verb(index: int, verb: String) -> void:
	if index < 0 or index >= slots.size():
		return
	var verbs: Array = slots[index].get("verbs", [])
	if verbs.has(verb):
		verbs.erase(verb)
	else:
		verbs.append(verb)
	slots[index]["verbs"] = verbs
	save_to_disk()
	changed.emit()


func has_verb(index: int, verb: String) -> bool:
	if index < 0 or index >= slots.size():
		return false
	return slots[index].get("verbs", []).has(verb)


func cycle_color(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	slots[index]["color_index"] = int(slots[index].get("color_index", 0)) + 1
	save_to_disk()
	changed.emit()


## Attribution lines for every icon in the box (CC BY needs these visible).
func attributions() -> Array:
	var out: Array = []
	for s in slots:
		var line := str(s.get("attribution", ""))
		if line == "":
			line = "%s by %s from Noun Project" % [s.get("term", "?"), s.get("creator_name", "?")]
		out.append({"line": line, "license": s.get("license", ""), "permalink": s.get("permalink", ""),
			"creator_permalink": s.get("creator_permalink", "")})
	return out


func save_to_disk() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Toolbox: could not write %s" % path)
		return
	f.store_string(JSON.stringify({"slots": slots, "selected": selected}, "\t"))
	f.close()


func load_from_disk() -> void:
	slots = []
	selected = 0
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("slots") is Array:
		for s in data["slots"]:
			if s is Dictionary:
				slots.append(s)
		selected = clampi(int(data.get("selected", 0)), 0, maxi(slots.size() - 1, 0))
	changed.emit()
