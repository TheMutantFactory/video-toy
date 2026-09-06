class_name Settings
## user://settings.cfg: the show knobs an exported app has no shell or
## environment for. Static, cached per path; every consumer reads at its
## own start (the stage, Osc, Clock, the Syphon output, ImageDiff).

const PATH := "user://settings.cfg"
const SECTION := "settings"
const DEFAULTS := {
	"quality_lock": "auto",        # auto | full | high | medium | low
	"osc_port": 9000,
	"syphon_name": "Video Toy",
	"autosave_interval": 30,       # seconds
	"attract_idle": 60,            # seconds idle before attract mode
	"hud": "full",                 # full | compact | hidden at Play start
	"clock_source": "off",         # off | internal, at launch
	"clock_bpm": 120,
	"lock_scenes": false,
	"diff_mean": 0.035,            # ./run.sh check thresholds
	"diff_block": 0.45,
	"safe_mode": false,            # no MIDI / OSC / camera / mic at launch (also --safe)
	"guest_mode": false,           # mouse-only: right-click wheel, long-press removes
	"osc_out": false,              # notes + events as OSC to a bridge (MIDI out)
	"osc_out_host": "127.0.0.1",
	"osc_out_port": 9001,
	"tour_seen": false,            # the first-run captions have been shown
	"beauty_outlet": true,         # when the quality ladder sheds load, add glow and trails back
	"audio_shape": {},             # per-band attack / decay / sustain / release / gate / smooth
	"clock_follow_audio": false,   # the internal clock follows the tempo tracked from audio
	"clip_format": "16:9",         # 16:9 | 9:16 | 1:1 (a centre crop of the picture)
	"clip_fps": 60,
	"clip_preroll": 2.0,           # seconds rendered before the clip starts (feedback warms up)
	"clip_seam": 1.0,              # seconds cross-dissolved to make a loop seamless (ffmpeg)
	"locks": [],                   # sections Surprise / evolve leave alone
	"mutate_amount": 1.0,          # 0.25 nearby .. 1.0 everything
}

static var _cache: Dictionary = {}     # path -> Dictionary


static func _load(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var d: Dictionary = {}
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(path) and cfg.load(path) == OK and cfg.has_section(SECTION):
		for k in cfg.get_section_keys(SECTION):
			d[k] = cfg.get_value(SECTION, k)
	_cache[path] = d
	return d


static func get_value(key: String, path := PATH) -> Variant:
	var d := _load(path)
	if d.has(key):
		return d[key]
	return DEFAULTS.get(key)


static func set_value(key: String, value: Variant, path := PATH) -> bool:
	var d := _load(path)
	d[key] = value
	return _save(path)


static func all(path := PATH) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	out.merge(_load(path), true)
	return out


static func reset(path := PATH) -> void:
	_cache[path] = {}
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _save(path: String) -> bool:
	var cfg := ConfigFile.new()
	for k in _cache[path]:
		cfg.set_value(SECTION, k, _cache[path][k])
	return cfg.save(path) == OK
