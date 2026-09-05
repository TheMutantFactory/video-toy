class_name Presets
## Stage presets: twelve numbered snapshots of everything the stage remembers
## (palette, feedback, fx, glow, monitor, webcam, shape, per-slot verbs), in
## user://presets.json. Static and autoload-free so the smoke test can use it.

const PATH := "user://presets.json"
const COUNT := 12


static func load_all(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("presets") is Dictionary:
		return data["presets"]
	return {}


static func save(index: int, state: Dictionary, path := PATH) -> void:
	var all := load_all(path)
	state["saved_at"] = int(Time.get_unix_time_from_system())
	all[str(index)] = state
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"presets": all}, "\t"))
		f.close()


static func get_preset(index: int, path := PATH) -> Dictionary:
	var all := load_all(path)
	return all.get(str(index), {})


static func has(index: int, path := PATH) -> bool:
	return load_all(path).has(str(index))


static func clear(index: int, path := PATH) -> void:
	var all := load_all(path)
	all.erase(str(index))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"presets": all}, "\t"))
		f.close()
