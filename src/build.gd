class_name Build
## The version stamp: res://build.json is written by ./run.sh export (git
## hash + date); the editor run has none and says so.

const PATH := "res://build.json"
const VERSION := "1.0.0"


static func info(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func describe(path := PATH) -> String:
	var d := info(path)
	if d.is_empty():
		return "v%s dev (no build stamp)" % VERSION
	return "v%s %s %s" % [d.get("version", VERSION), str(d.get("hash", "?")).substr(0, 8), str(d.get("date", ""))]
