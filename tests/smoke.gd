extends SceneTree
## Headless smoke test:  godot --headless --path . -s tests/smoke.gd
## No network, no quota. Exit code 1 on any failure.

var _fails := 0
var _n := 0


func _check(name: String, ok: bool) -> void:
	_n += 1
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", name])


func _init() -> void:
	# OAuth 1.0a signing pinned to the RFC 5849 reference vector — the same one
	# noun-project-utils and dopaminer-iconoclast pin, so the clients can't drift.
	var api = load("res://src/noun_api.gd").new()
	var b = "GET&http%3A%2F%2Fphotos.example.net%2Fphotos&file%3Dvacation.jpg%26oauth_consumer_key%3Ddpf43f3p2l4k3l03%26oauth_nonce%3Dkllo9940pd9333jh%26oauth_signature_method%3DHMAC-SHA1%26oauth_timestamp%3D1191242096%26oauth_token%3Dnnch734d00sl2jdk%26oauth_version%3D1.0%26size%3Doriginal"
	_check("oauth1 signing matches reference vector",
		api._sign(b, "kd94hf93k423kf44&pfkkdhi9sl3r4s00") == "tR3+Ty81lMeYAr/Fid0kMTYa/WM=")
	_check("percent-encoding keeps unreserved, encodes space and utf-8",
		api._pe("a-b.c_d~ é") == "a-b.c_d~%20%C3%A9")
	var signed: Array = api._sign_request("GET", "https://api.thenounproject.com/v2/icon",
		{"query": "cat food", "limit": "24"}, {"key": "k", "secret": "s"})
	_check("signed url carries encoded query", signed[0].ends_with("query=cat%20food&limit=24"))
	_check("authorization header is OAuth", signed[1].begins_with("OAuth oauth_consumer_key=\"k\""))
	api.free()

	# credentials: INI parser handles the CLI's plain format and quoted values
	var Creds = load("res://src/credentials.gd")
	var ini: Dictionary = Creds._parse_ini("[other]\nkey=nope\n[noun]\nkey = abc\nsecret=\"xyz\"\n")
	_check("ini parser reads [noun] key/secret", ini.get("key") == "abc" and ini.get("secret") == "xyz")

	# toolbox: throwaway path, not the real user://toolbox.json
	var box = load("res://src/toolbox.gd").new()
	box.path = "user://_smoke_toolbox.json"
	box.load_from_disk()
	box.clear()
	var meta := {"id": "1", "term": "cat", "attribution": "cat by A from Noun Project",
		"license_description": "creative-commons-attribution", "permalink": "/icon/cat-1/",
		"creator": {"name": "A", "permalink": "/creator/a/"}}
	_check("add returns slot 0", box.add_from_meta(meta, "user://icons/1.svg") == 0)
	_check("duplicate add returns the same slot", box.add_from_meta(meta, "user://icons/1.svg") == 0)
	box.toggle_verb(0, "spin")
	_check("verb toggles on", box.has_verb(0, "spin"))
	box.toggle_verb(0, "spin")
	_check("verb toggles off", not box.has_verb(0, "spin"))
	box.toggle_verb(0, "orbit")
	var box2 = load("res://src/toolbox.gd").new()
	box2.path = box.path
	box2.load_from_disk()
	_check("toolbox persists slots and verbs", box2.slots.size() == 1 and box2.has_verb(0, "orbit"))
	_check("attribution line present", box2.attributions()[0]["line"] == "cat by A from Noun Project")
	for i in 9:
		box.add_from_meta({"id": str(100 + i), "term": "x"}, "")
	_check("toolbox caps at 9", box.slots.size() == 9 and box.is_full())
	box.remove(0)
	_check("remove shrinks", box.slots.size() == 8)
	box.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(box.path))
	box.free()
	box2.free()

	# verbs and palettes are consistent
	_check("every verb has a unique key", _unique(Verbs.ALL.map(func(v): return v["key"])))
	_check("verb lookup by keycode", Verbs.by_key(KEY_Q) == "wander" and Verbs.by_key(KEY_Z) == "")
	_check("palettes parse to colours", Palettes.bg(0) != Color() and Palettes.ring(1).size() >= 3)
	_check("palette index wraps", Palettes.get_palette(Palettes.count()) == Palettes.get_palette(0))

	# svg whitening on a tiny inline icon
	var p := "user://_smoke.svg"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="#000"/></svg>')
	f.close()
	var tex = load("res://src/icon_media.gd").load_svg_white(p, 1.0)
	_check("svg rasterises white", tex != null and tex.get_image().get_pixel(5, 5).is_equal_approx(Color(1, 1, 1, 1)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	# attribution ledger: paginates, dedupes, survives reload
	var led = load("res://src/ledger.gd").new()
	led.path = "user://_smoke_ledger.json"
	led.load_from_disk()
	led.entries = []
	for i in 23:
		led.record({"id": str(i), "term": "t%d" % i, "creator": {"name": "C", "permalink": "/creator/c/"}})
	led.record({"id": "3", "term": "again"})
	_check("ledger dedupes by id", led.count() == 23)
	_check("ledger paginates", led.page_count(10) == 3 and led.page(2, 10).size() == 3 and led.page(5, 10).is_empty())
	_check("ledger attribution line", led.line_for(led.entries[0]) == "t0 by C from The Noun Project")
	var led2 = load("res://src/ledger.gd").new()
	led2.path = led.path
	led2.load_from_disk()
	_check("ledger persists", led2.count() == 23)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(led.path))
	led.free()
	led2.free()

	# post-process shader parses (compile errors print and fail the load)
	var sh = load("res://src/fx.gdshader")
	_check("fx shader loads", sh is Shader and sh.get_code().contains("hint_screen_texture"))
	var fx = load("res://src/fx.gd")
	_check("fx pixel steps start at off", fx.PIXEL_STEPS[0] == 0 and fx.PIXEL_STEPS.size() >= 4)
	_check("fx shader has kaleidoscope and chroma stages",
		sh.get_code().contains("kaleido_segments") and sh.get_code().contains("key_color"))
	_check("fx shader has a CRT stage", sh.get_code().contains("uniform float crt"))
	_check("fx kaleido steps start at off", fx.KALEIDO_STEPS[0] == 0 and fx.KALEIDO_STEPS.has(6))

	# virtual monitor geometry (no rendering needed)
	var mon = load("res://src/monitor.gd").new()
	var img := Image.create(400, 200, false, Image.FORMAT_RGBA8)
	mon.setup(ImageTexture.create_from_image(img), Vector2(1000, 500))
	mon.size_step = 1                                  # 0.4 -> 160x80 screen
	mon._apply_scale()
	_check("monitor hit-test inside", mon.contains(Vector2(1000, 500)) and mon.contains(Vector2(1075, 535)))
	_check("monitor hit-test outside", not mon.contains(Vector2(1200, 500)) and not mon.contains(Vector2(1000, 600)))
	mon.cycle_size()
	_check("monitor size cycles", mon.scale_factor() == 0.6)
	mon.free()

	# MIDI-learn: arm, bind, params, action edges, persistence (synthetic events)
	var midi = load("res://src/midi_map.gd").new()
	midi.path = "user://_smoke_midi.json"
	var got := {"param": [], "action": [], "learned": []}
	midi.param.connect(func(id, v): got["param"].append([id, v]))
	midi.action.connect(func(id): got["action"].append(id))
	midi.learned.connect(func(id, b): got["learned"].append([id, b]))
	midi.arm("fb_zoom")
	midi.feed(_cc(1, 21, 64))
	_check("learn binds the first message to the armed id", midi.binding_for("fb_zoom") == "cc:1:21" and got["learned"].size() == 1)
	_check("learn does not also emit the param", got["param"].is_empty())
	midi.feed(_cc(1, 21, 127))
	_check("bound CC emits param 0..1", got["param"].size() == 1 and is_equal_approx(got["param"][0][1], 1.0))
	midi.arm("act:spawn")
	midi.feed(_cc(1, 22, 0))
	midi.feed(_cc(1, 22, 100))
	midi.feed(_cc(1, 22, 110))
	midi.feed(_cc(1, 22, 0))
	midi.feed(_cc(1, 22, 127))
	_check("CC action fires on rising edge only", got["action"] == ["spawn", "spawn"])
	var note := InputEventMIDI.new()
	note.message = MIDI_MESSAGE_NOTE_ON
	note.channel = 10
	note.pitch = 36
	note.velocity = 100
	midi.arm("act:clear")
	midi.feed(note)
	midi.feed(note)
	var off := InputEventMIDI.new()
	off.message = MIDI_MESSAGE_NOTE_OFF
	off.channel = 10
	off.pitch = 36
	midi.feed(off)
	_check("note binds and fires, note-off does not", midi.binding_for("act:clear") == "note:10:36" and got["action"].size() == 3)
	midi.arm("fb_zoom")
	midi.feed(_cc(2, 5, 1))
	_check("re-learning steals the old binding", midi.binding_for("fb_zoom") == "cc:2:5" and not midi.bindings.has("cc:1:21"))
	_check("describe is human", midi.describe("cc:2:5") == "CC 5 ch2" and midi.describe("note:10:36") == "note 36 ch10")
	var midi2 = load("res://src/midi_map.gd").new()
	midi2.path = midi.path
	midi2.load_from_disk()
	_check("bindings persist", midi2.binding_for("act:clear") == "note:10:36" and midi2.bindings.size() == 3)
	midi.unbind("act:clear")
	_check("unbind removes", midi.binding_for("act:clear") == "")
	# audio bands as virtual controllers
	got["param"].clear()
	got["action"].clear()
	_check("audio binding cycles through param bands", midi.cycle_audio_binding("fb_zoom") == "bass" and midi.cycle_audio_binding("fb_zoom") == "mid")
	_check("audio binding for actions is beat only", midi.cycle_audio_binding("act:spawn") == "beat" and midi.cycle_audio_binding("act:spawn") == "")
	midi.set_audio_binding("act:spawn", "beat")
	midi.feed_audio({"bass": 0.9, "mid": 0.4, "high": 0.1, "level": 0.9})
	midi.feed_beat()
	_check("audio feeds bound param and beat action", got["param"] == [["fb_zoom", 0.4]] and got["action"] == ["spawn"])
	var midi3 = load("res://src/midi_map.gd").new()
	midi3.path = midi.path
	midi3.load_from_disk()
	_check("audio bindings persist", midi3.audio_binding_for("fb_zoom") == "mid")
	midi3.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(midi.path))
	midi.free()
	midi2.free()

	# audio analysis: smoothing, level, beat detection on synthetic bands
	var Audio = load("res://src/audio_react.gd")
	_check("db scale maps silence and full scale", Audio._db01(Vector2.ZERO) == 0.0 and is_equal_approx(Audio._db01(Vector2(1, 1)), 1.0))
	_check("follower attacks faster than it releases",
		Audio._follow(0.0, 1.0, 0.05) > 1.0 - Audio._follow(1.0, 0.0, 0.05))
	var au = Audio.new()                       # not in tree: _ready/_process never run
	var beats := [0]                           # lambdas capture locals by value; an array is shared
	au.beat.connect(func(): beats[0] += 1)
	for i in 60:                               # 1 s of silence then a kick
		au.update_bands({"bass": 0.0, "mid": 0.0, "high": 0.0}, 1.0 / 60.0)
	var hit: bool = au.update_bands({"bass": 0.9, "mid": 0.2, "high": 0.1}, 1.0 / 60.0)
	_check("bass onset is a beat", hit and beats[0] == 1 and au.beat_env == 1.0)
	for i in 5:
		au.update_bands({"bass": 0.9, "mid": 0.2, "high": 0.1}, 1.0 / 60.0)
	_check("sustained bass is not more beats (cooldown + average)", beats[0] == 1)
	_check("level is the loudest band", au.level == au.bass and au.level > 0.5)
	au.gain = 0.0
	for i in 120:
		au.update_bands({"bass": 0.9, "mid": 0.9, "high": 0.9}, 1.0 / 60.0)
	_check("gain scales bands to nothing", au.level < 0.01)
	au.free()

	# raster: load + downscale, toolbox raster slot, palette extraction
	var big := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	big.fill(Color(0.2, 0.4, 0.9))
	big.fill_rect(Rect2i(0, 0, 512, 512), Color(0.9, 0.2, 0.1))
	var raster_path := ProjectSettings.globalize_path("user://_smoke_raster.png")
	big.save_png(raster_path)
	var Media = load("res://src/icon_media.gd")
	var rt = Media.load_raster(raster_path, 256)
	_check("raster loads and is capped to 256 on the long side", rt != null and rt.get_width() == 256 and rt.get_height() == 128)
	_check("raster keeps its colours", rt.get_image().get_pixel(10, 64).is_equal_approx(Color(0.9, 0.2, 0.1)) or rt.get_image().get_pixel(10, 64).r > 0.8)
	_check("is_raster by extension", Media.is_raster("a.PNG") and Media.is_raster("b.jpeg") and not Media.is_raster("c.svg"))
	var rbox = load("res://src/toolbox.gd").new()
	rbox.path = "user://_smoke_toolbox2.json"
	rbox.load_from_disk()
	rbox.clear()
	var ri: int = rbox.add_raster(raster_path)
	_check("raster becomes a toolbox slot copied into user://raster", ri == 0 and rbox.is_raster_slot(rbox.slots[0]) and FileAccess.file_exists(rbox.slots[0]["svg_path"]))
	_check("same raster twice is one slot", rbox.add_raster(raster_path) == 0 and rbox.slots.size() == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(rbox.slots[0]["svg_path"]))
	rbox.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(rbox.path))
	rbox.free()
	var pal: Dictionary = Palettes.extract(big, "Smoke", 4)
	var ring: Array = pal["ring"]
	_check("extracted palette has a bg and a ring", pal["name"] == "Smoke" and pal["bg"] != "" and ring.size() >= 1)
	var has_red := false
	var has_blue := false
	for hex in ring + [pal["bg"]]:
		var c := Color(str(hex))
		if c.r > 0.6 and c.g < 0.4: has_red = true
		if c.b > 0.6 and c.r < 0.4: has_blue = true
	_check("extraction finds both source colours", has_red and has_blue)
	DirAccess.remove_absolute(raster_path)
	var Webcam = load("res://src/webcam.gd")
	_check("webcam script loads standalone", Webcam != null and Webcam.can_instantiate())

	# presets file: save / get / has / clear, independent slots
	var pp := "user://_smoke_presets.json"
	Presets.save(1, {"palette": 3, "glow": 2}, pp)
	Presets.save(7, {"palette": 1}, pp)
	_check("preset saves and reads back", Presets.get_preset(1, pp).get("palette") == 3 and Presets.get_preset(1, pp).get("glow") == 2)
	_check("presets are independent slots", Presets.has(7, pp) and not Presets.has(2, pp) and Presets.get_preset(2, pp).is_empty())
	Presets.clear(1, pp)
	_check("preset clear", not Presets.has(1, pp) and Presets.has(7, pp))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pp))
	var gsh = load("res://src/glow.gdshader")
	_check("glow shader loads", gsh is Shader and gsh.get_code().contains("uniform float glow"))

	print("\n%d/%d checks passed" % [_n - _fails, _n])
	quit(1 if _fails > 0 else 0)


func _cc(channel: int, number: int, value: int) -> InputEventMIDI:
	var ev := InputEventMIDI.new()
	ev.message = MIDI_MESSAGE_CONTROL_CHANGE
	ev.channel = channel
	ev.controller_number = number
	ev.controller_value = value
	return ev


func _unique(arr: Array) -> bool:
	var seen := {}
	for a in arr:
		if seen.has(a):
			return false
		seen[a] = true
	return true
