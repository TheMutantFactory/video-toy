class_name Rig
## A rig is everything that makes this toy *yours*, in one zip: the toolbox
## and every asset it points at, the attribution ledger, presets and banks,
## controller bindings, palettes, the timeline loop, the current font and
## the chroma backdrop. Export it, hand it to someone, import it on their
## machine. Paths are relative to `root` (user:// in the game; a scratch
## directory in tests).

const TOP := ["toolbox.json", "attribution.json", "presets.json", "midi.json", "palettes.json", "timeline.json", "backdrop.png"]
const FONTS := ["fonts/current.ttf", "fonts/current.otf"]
const VERSION := 1


## The relative paths a rig at `root` should carry (existing files only).
static func manifest(root := "user://") -> Array:
	var files: Array = []
	for f in TOP + FONTS:
		if FileAccess.file_exists(root.path_join(f)):
			files.append(f)
	var tb := root.path_join("toolbox.json")
	if FileAccess.file_exists(tb):
		var data = JSON.parse_string(FileAccess.get_file_as_string(tb))
		if data is Dictionary and data.get("slots") is Array:
			for sl in data["slots"]:
				if not (sl is Dictionary):
					continue
				var paths: Array = [str(sl.get("svg_path", "")), str(sl.get("sound_path", ""))] + Array(sl.get("word_paths", []))
				for p in paths:
					var ps := str(p)
					if ps.begins_with("user://"):
						var rel := ps.trim_prefix("user://")
						if FileAccess.file_exists(root.path_join(rel)) and not files.has(rel):
							files.append(rel)
	return files


static func export(zip_path: String, root := "user://") -> int:
	var z := ZIPPacker.new()
	if z.open(ProjectSettings.globalize_path(zip_path)) != OK:
		return -1
	var files := manifest(root)
	z.start_file("rig.json")
	z.write_file(JSON.stringify({"version": VERSION, "made": Time.get_datetime_string_from_system(), "files": files}).to_utf8_buffer())
	z.close_file()
	for rel in files:
		z.start_file(rel)
		z.write_file(FileAccess.get_file_as_bytes(root.path_join(rel)))
		z.close_file()
	z.close()
	return files.size()


## Unpack a rig into `root`, overwriting the files it carries. Returns the
## number of files written, or -1 if the zip is not a rig.
static func import(zip_path: String, root := "user://") -> int:
	var z := ZIPReader.new()
	if z.open(zip_path if not zip_path.begins_with("user://") and not zip_path.begins_with("res://") else ProjectSettings.globalize_path(zip_path)) != OK:
		return -1
	var names := z.get_files()
	if not names.has("rig.json"):
		z.close()
		return -1
	var meta = JSON.parse_string(z.read_file("rig.json").get_string_from_utf8())
	if not (meta is Dictionary and meta.get("files") is Array):
		z.close()
		return -1
	var n := 0
	for rel in meta["files"]:
		var r := str(rel)
		if r.begins_with("/") or r.contains(".."):        # never write outside root
			continue
		if not names.has(r):
			continue
		var dst := root.path_join(r)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst.get_base_dir()))
		var f := FileAccess.open(dst, FileAccess.WRITE)
		if f:
			f.store_buffer(z.read_file(r))
			f.close()
			n += 1
	z.close()
	return n


static func default_export_path() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "user://rigs/rig-%04d%02d%02d-%02d%02d%02d.zip" % [t.year, t.month, t.day, t.hour, t.minute, t.second]
