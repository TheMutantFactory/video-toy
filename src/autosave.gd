class_name Autosave
## The live state, written every INTERVAL seconds so a crash costs at most
## half a minute: the stage snapshot plus what is on stage (actors, solids).
## A running flag marks an unclean exit; the start screen offers a restore.

const PATH := "user://autosave.json"
const FLAG := "user://running.flag"
const INTERVAL := 30.0


static func write(state: Dictionary, path := PATH) -> bool:
	state["saved_at"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(state))
	f.close()
	return true


static func read(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


static func age_seconds(path := PATH, now := -1) -> int:
	var d := read(path)
	if d.is_empty():
		return -1
	var n := int(Time.get_unix_time_from_system()) if now < 0 else now
	return n - int(d.get("saved_at", n))


static func mark_running(flag := FLAG) -> void:
	var f := FileAccess.open(flag, FileAccess.WRITE)
	if f:
		f.store_string(str(OS.get_process_id()))
		f.close()


static func mark_clean_exit(flag := FLAG) -> void:
	if FileAccess.file_exists(flag):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(flag))


## True when the previous run left its flag behind (it did not exit cleanly).
static func crashed_last_time(flag := FLAG) -> bool:
	return FileAccess.file_exists(flag)


static func describe_age(seconds: int) -> String:
	if seconds < 0:
		return "no autosave"
	if seconds < 90:
		return "%d s ago" % seconds
	if seconds < 3600 * 2:
		return "%d min ago" % (seconds / 60)
	return "%d h ago" % (seconds / 3600)
