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
const SVG_DIR := "user://svg"
const VIDEO_DIR := "user://video"
const CYCLE_MAX := 24
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
## verbs, wraps solids and extrudes. Emoji keep their colours (untinted).
## "clock" and "countdown HH:MM" become live words the stage re-renders.
## Returns the slot index or -1.
func add_text(word: String) -> int:
	word = word.strip_edges()
	if word == "" or is_full():
		return -1
	var id := "text-%d" % absi(word.hash())
	var existing := index_of(id)
	if existing >= 0:
		return existing
	var live := LiveText.parse(word)
	var shown := word if live.is_empty() else LiveText.text_for(live["live"], int(live.get("target", 0)), int(Time.get_unix_time_from_system()))
	var img := TextRaster.render(shown)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEXT_DIR))
	var dst := "%s/%s.png" % [TEXT_DIR, id]
	if img.save_png(ProjectSettings.globalize_path(dst)) != OK:
		return -1
	var slot := {
		"id": id, "kind": "raster" if TextRaster.last_had_color else "text",
		"term": word,
		"svg_path": dst, "thumbnail_url": "",
		"attribution": "“%s” — text" % word,
		"license": "yours", "permalink": "",
		"creator_name": "", "creator_permalink": "",
		"verbs": [], "color_index": slots.size(),
		"added_at": int(Time.get_unix_time_from_system()),
	}
	if not live.is_empty():
		slot["live"] = live["live"]
		slot["target"] = int(live.get("target", 0))
		slot["version"] = 0
	slots.append(slot)
	selected = slots.size() - 1
	save_to_disk()
	changed.emit()
	selection_changed.emit(selected)
	return selected


## A list of words: one slot each while there is room, otherwise a single slot
## that cycles through them (the stage advances it on the beat).
func add_words(lines: Array) -> int:
	var words: Array = []
	for l in lines:
		var w := str(l).strip_edges()
		if w != "":
			words.append(w)
	if words.is_empty() or is_full():
		return -1
	var free := MAX_SLOTS - slots.size()
	if words.size() <= free:
		var last := -1
		for w in words:
			last = add_text(w)
		return last
	words = words.slice(0, CYCLE_MAX)
	var id := "words-%d" % absi("\n".join(words).hash())
	var existing := index_of(id)
	if existing >= 0:
		return existing
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEXT_DIR))
	var paths: Array = []
	for i in words.size():
		var img := TextRaster.render(words[i])
		var pth := "%s/%s_%d.png" % [TEXT_DIR, id, i]
		if img.save_png(ProjectSettings.globalize_path(pth)) != OK:
			return -1
		paths.append(pth)
	var slot := {
		"id": id, "kind": "text",
		"term": "%s… (%d words)" % [words[0], words.size()],
		"svg_path": paths[0], "thumbnail_url": "",
		"attribution": "word list (%d words) — text" % words.size(),
		"license": "yours", "permalink": "",
		"creator_name": "", "creator_permalink": "",
		"verbs": [], "color_index": slots.size(),
		"words": words, "word_paths": paths, "word_index": 0,
		"added_at": int(Time.get_unix_time_from_system()),
	}
	slots.append(slot)
	selected = slots.size() - 1
	save_to_disk()
	changed.emit()
	selection_changed.emit(selected)
	return selected


## Any SVG file as an icon: copied and whitened like a Noun icon (tinted).
func add_svg(src_path: String) -> int:
	if is_full():
		return -1
	var id := "svg-%d" % absi(src_path.hash())
	var existing := index_of(id)
	if existing >= 0:
		return existing
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty():
		return -1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SVG_DIR))
	var dst := "%s/%s.svg" % [SVG_DIR, id]
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return -1
	f.store_buffer(bytes)
	f.close()
	var slot := {
		"id": id, "kind": "icon",
		"term": src_path.get_file().get_basename(),
		"svg_path": dst, "thumbnail_url": "",
		"attribution": "%s — local SVG" % src_path.get_file(),
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


## A Theora .ogv as an animated slot; the stage plays it into a viewport.
func add_video(src_path: String) -> int:
	if is_full():
		return -1
	var id := "video-%d" % absi(src_path.hash())
	var existing := index_of(id)
	if existing >= 0:
		return existing
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty():
		return -1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VIDEO_DIR))
	var dst := "%s/%s.ogv" % [VIDEO_DIR, id]
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return -1
	f.store_buffer(bytes)
	f.close()
	var slot := {
		"id": id, "kind": "video",
		"term": src_path.get_file().get_basename(),
		"svg_path": dst, "thumbnail_url": "",
		"attribution": "%s — local video" % src_path.get_file(),
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


## Point a slot at a new image (live words, cycling lists) without touching disk.
const SOUND_DIR := "user://sounds"


## A sound for a slot (copied into user://sounds); "" clears it.
func set_slot_sound(index: int, src_path: String) -> bool:
	if index < 0 or index >= slots.size():
		return false
	if src_path == "":
		slots[index].erase("sound_path")
	else:
		var ext := src_path.get_extension().to_lower()
		if not ext in ["wav", "mp3", "ogg"]:
			return false
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SOUND_DIR))
		var dst := "%s/%s.%s" % [SOUND_DIR, slots[index]["id"], ext]
		if DirAccess.copy_absolute(src_path, ProjectSettings.globalize_path(dst)) != OK:
			return false
		Sounds.forget(dst)
		slots[index]["sound_path"] = dst
	save_to_disk()
	changed.emit()
	return true


func set_slot_path(index: int, path: String, persist := false) -> void:
	if index < 0 or index >= slots.size():
		return
	slots[index]["svg_path"] = path
	if persist:
		save_to_disk()
	changed.emit()


## Untinted slots: photos, videos and colour emoji keep their own colours.
static func is_raster_slot(slot: Dictionary) -> bool:
	return str(slot.get("kind", "icon")) in ["raster", "video"]


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
