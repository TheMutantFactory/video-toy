class_name AudioInputSetting
## Microphone input needs audio/driver/enable_input=true at launch, and on a
## machine with no input device that setting silences ALL audio (CoreAudio
## fails and Godot falls back to the dummy driver). run.sh handles it with
## override.cfg; an exported app has no shell, so the Settings screen writes
## the same override next to the executable (or into the project when run
## from the editor). Takes effect on the next launch.

const SECTION := "audio"
const KEY := "driver/enable_input"


## Where the override lives for this run.
static func override_path() -> String:
	if OS.has_feature("editor") or OS.has_feature("template") == false:
		return "res://override.cfg"
	return OS.get_executable_path().get_base_dir().path_join("override.cfg")


static func currently_enabled() -> bool:
	return bool(ProjectSettings.get_setting("audio/driver/enable_input", false))


## What the override file says, or -1 when there is none.
static func override_state(path := "") -> int:
	var p := override_path() if path == "" else path
	if not FileAccess.file_exists(p):
		return -1
	var cfg := ConfigFile.new()
	if cfg.load(p) != OK:
		return -1
	if not cfg.has_section_key(SECTION, KEY):
		return -1
	return 1 if bool(cfg.get_value(SECTION, KEY)) else 0


## Write the override (or remove it when `enabled` matches the project default).
static func set_enabled(enabled: bool, path := "") -> bool:
	var p := override_path() if path == "" else path
	if enabled:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p)
		return true
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, KEY, false)
	return cfg.save(p) == OK
