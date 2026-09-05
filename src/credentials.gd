extends RefCounted
## Noun Project API key/secret. Resolution order (mirrors noun-project-utils):
##   1. NOUN_KEY / NOUN_SECRET environment variables
##   2. user://noun_credentials.cfg   (written by the Settings screen)
##   3. ~/.config/noun/credentials.cfg (plain INI, [noun] key= / secret=)
## Values are never logged. user:// lives outside the repo, so nothing here can
## be committed by accident.

const PATH := "user://noun_credentials.cfg"
const SECTION := "noun"


static func save_creds(key: String, secret: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "key", key.strip_edges())
	cfg.set_value(SECTION, "secret", secret.strip_edges())
	cfg.save(PATH)


static func clear_creds() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func load_creds() -> Dictionary:
	var key := OS.get_environment("NOUN_KEY").strip_edges()
	var secret := OS.get_environment("NOUN_SECRET").strip_edges()
	if key != "" and secret != "":
		return {"key": key, "secret": secret, "source": "env"}

	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		key = str(cfg.get_value(SECTION, "key", "")).strip_edges()
		secret = str(cfg.get_value(SECTION, "secret", "")).strip_edges()
		if key != "" and secret != "":
			return {"key": key, "secret": secret, "source": "user://"}

	var ini := _ini_path()
	if ini != "" and FileAccess.file_exists(ini):
		var parsed := _parse_ini(FileAccess.get_file_as_string(ini))
		if parsed.get("key", "") != "" and parsed.get("secret", "") != "":
			parsed["source"] = "~/.config/noun"
			return parsed
	return {}


static func has_creds() -> bool:
	return not load_creds().is_empty()


static func source() -> String:
	return str(load_creds().get("source", ""))


static func _ini_path() -> String:
	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	if home == "":
		return ""
	return home.path_join(".config/noun/credentials.cfg")


## Minimal INI reader: only the [noun] section, only key/secret. Godot's
## ConfigFile rejects unquoted strings, and the CLI writes plain INI.
static func _parse_ini(text: String) -> Dictionary:
	var out := {}
	var in_section := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with(";"):
			continue
		if line.begins_with("["):
			in_section = line.trim_prefix("[").trim_suffix("]").strip_edges() == SECTION
			continue
		if not in_section or not line.contains("="):
			continue
		var kv := line.split("=", true, 1)
		var k := kv[0].strip_edges()
		var v := kv[1].strip_edges().trim_prefix("\"").trim_suffix("\"")
		if k == "key" or k == "secret":
			out[k] = v
	return out
