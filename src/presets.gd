class_name Presets
## Stage presets: BANKS banks of twelve numbered snapshots of everything the
## stage remembers, in user://presets.json. Bank 0 is stored under "presets"
## (the original layout, so old files still load); banks 1+ under "banks".
## Static and autoload-free so the smoke test can use it.

const PATH := "user://presets.json"
const COUNT := 12
const BANKS := 8


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


## All presets of one bank: {"1": state, ...}
static func load_all(path := PATH, bank := 0) -> Dictionary:
	var data := _read(path)
	if bank == 0:
		return data["presets"] if data.get("presets") is Dictionary else {}
	var banks = data.get("banks")
	if banks is Dictionary and banks.get(str(bank)) is Dictionary:
		return banks[str(bank)]
	return {}


static func _store(path: String, bank: int, all: Dictionary) -> void:
	var data := _read(path)
	if bank == 0:
		data["presets"] = all
	else:
		if not (data.get("banks") is Dictionary):
			data["banks"] = {}
		data["banks"][str(bank)] = all
	_write(path, data)


static func save(index: int, state: Dictionary, path := PATH, bank := 0) -> void:
	var all := load_all(path, bank)
	state["saved_at"] = int(Time.get_unix_time_from_system())
	all[str(index)] = state
	_store(path, bank, all)


static func get_preset(index: int, path := PATH, bank := 0) -> Dictionary:
	return load_all(path, bank).get(str(index), {})


static func has(index: int, path := PATH, bank := 0) -> bool:
	return load_all(path, bank).has(str(index))


static func clear(index: int, path := PATH, bank := 0) -> void:
	var all := load_all(path, bank)
	all.erase(str(index))
	_store(path, bank, all)


## Indices (1..COUNT) that hold a preset in `bank`, ascending.
static func filled(path := PATH, bank := 0) -> Array:
	var out: Array = []
	var all := load_all(path, bank)
	for i in COUNT:
		if all.has(str(i + 1)):
			out.append(i + 1)
	return out


## The next / previous filled index after `from` in `bank`, wrapping; 0 if none.
static func neighbour(from: int, step: int, path := PATH, bank := 0) -> int:
	var f := filled(path, bank)
	if f.is_empty():
		return 0
	var i := f.find(from)
	if i < 0:
		# not on a filled slot: nearest in the travel direction
		for j in f.size():
			var k: int = f[j] if step > 0 else f[f.size() - 1 - j]
			if (step > 0 and k > from) or (step < 0 and k < from):
				return k
		return f[0] if step > 0 else f[f.size() - 1]
	return f[posmod(i + step, f.size())]
