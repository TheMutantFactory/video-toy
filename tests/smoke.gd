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
	_check("every verb has a unique key", _unique(Verbs.all().map(func(v): return v["key"])))
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
	led.record({"id": "n1", "term": "cat", "attribution": "cat by A from Noun Project", "license_description": "creative-commons-attribution",
		"permalink": "/icon/cat-1/", "creator": {"name": "A", "permalink": "/creator/a/"}})
	led.record({"id": "loc1", "term": "photo", "attribution": "photo.jpg — local image", "license": "user-supplied", "source": "local file"})
	_check("credit line carries license and absolute link",
		led.credit_line(led.entries[led.count() - 2]) == "cat by A from Noun Project (creative-commons-attribution) — https://thenounproject.com/icon/cat-1/")
	var ct: String = led.credits_text(["n1", "loc1"])
	_check("credits text groups Noun Project and other assets and filters by id",
		ct.contains("Icons from The Noun Project") and ct.contains("cat by A") and ct.contains("Other assets:") and ct.contains("photo.jpg") and not ct.contains("t0 by C"))
	var led2 = load("res://src/ledger.gd").new()
	led2.path = led.path
	led2.load_from_disk()
	_check("ledger persists", led2.count() == led.count() and led2.count() == 25)
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
	_check("fx shader has keyers and slit-scan", sh.get_code().contains("key_mode") and sh.get_code().contains("slit_tex") and sh.get_code().contains("prev_tex"))
	_check("history atlas slots tile a 6x6 grid", fx.slot_rect(0, Vector2(1920, 1080)) == Rect2(0, 0, 320, 180)
		and fx.slot_rect(7, Vector2(1920, 1080)) == Rect2(320, 180, 320, 180) and fx.slot_rect(35, Vector2(1920, 1080)).end == Vector2(1920, 1080))
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

	# scenes table and shaders; warp mesh geometry
	var all_load := true
	for sid in Scenes.ids():
		var sh2 = load(Scenes.shader_path(sid))
		if not (sh2 is Shader) or not sh2.get_code().contains("common.gdshaderinc"):
			all_load = false
	_check("every scene shader loads and includes common", all_load and Scenes.ALL.size() == 9)
	_check("scene neighbour wraps and enters from off", Scenes.neighbour("", 1) == "plasma" and Scenes.neighbour("noise", 1) == "plasma" and Scenes.neighbour("plasma", -1) == "noise")
	var fm := FeedbackMesh.build(Vector2(1920, 1080), 4, 2)
	_check("warp mesh has (cols+1)(rows+1) vertices and 6 indices per quad",
		fm.get_surface_count() == 1 and fm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == FeedbackMesh.vertex_count(4, 2)
		and fm.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() == 4 * 2 * 6)
	var wm := FeedbackMesh.material()
	_check("warp material has a vertex stage", wm.shader != null and wm.shader.code.contains("void vertex()"))

	# extrusion: a ring keeps its hole; sides only on boundaries
	var ring_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dd := Vector2(x - 32, y - 32).length()
			ring_img.set_pixel(x, y, Color(1, 1, 1, 1.0 if (dd > 12 and dd < 28) else 0.0))
	var grid: Array = Extrude.opaque_cells(ring_img, 32)
	_check("extrude grid keeps the hole", not grid[16][16] and grid[16][4] and Extrude.count_cells(grid) > 100)
	var cookie := Extrude.build(ring_img, 1.4, 0.35, 32)
	# SurfaceTool.index() merges shared vertices, so count triangles via indices
	var front_idx: int = cookie.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()
	var side_idx: int = cookie.surface_get_arrays(1)[Mesh.ARRAY_INDEX].size()
	_check("extrude mesh: two surfaces, 4 triangles per cell on the faces, fewer on the sides", cookie.get_surface_count() == 2
		and front_idx == Extrude.count_cells(grid) * 12 and side_idx > 0 and side_idx < front_idx)
	var solid_box := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	solid_box.fill(Color(1, 1, 1, 1))
	var slab := Extrude.build(solid_box, 1.0, 0.2, 4)
	_check("solid slab has sides only on its 16 boundary edges", slab.surface_get_arrays(1)[Mesh.ARRAY_INDEX].size() == 16 * 6)
	# (formation.gd reads autoloads, so its transforms are checked in --selftest)

	# text slots: CPU glyph rasterisation, white on alpha, wider than tall
	var timg := TextRaster.render("Hello", 120)
	var topaque := TextRaster.opaque_count(timg)
	var twhite := true
	for y in range(0, timg.get_height(), 3):
		for x in range(0, timg.get_width(), 3):
			var c := timg.get_pixel(x, y)
			if c.a > 0.5 and (c.r < 0.99 or c.g < 0.99 or c.b < 0.99):
				twhite = false
	_check("text renders white-on-alpha glyphs", topaque > 1000 and twhite and timg.get_width() > timg.get_height())
	_check("longer words are wider", TextRaster.render("HAPPY BIRTHDAY", 120).get_width() > timg.get_width() * 3)
	var tbox = load("res://src/toolbox.gd").new()
	tbox.path = "user://_smoke_toolbox3.json"
	tbox.load_from_disk()
	tbox.clear()
	var ti: int = tbox.add_text("  Knobcon ")
	_check("word becomes a tinted (non-raster) text slot with a png", ti == 0 and tbox.slots[0]["kind"] == "text"
		and tbox.slots[0]["term"] == "Knobcon" and not tbox.is_raster_slot(tbox.slots[0]) and FileAccess.file_exists(tbox.slots[0]["svg_path"]))
	_check("same word twice is one slot; empty word rejected", tbox.add_text("Knobcon") == 0 and tbox.add_text("   ") == -1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tbox.slots[0]["svg_path"]))
	tbox.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tbox.path))
	tbox.free()
	_check("flock verb is on Shift+Q only", Verbs.by_key(KEY_Q, true) == "flock" and Verbs.by_key(KEY_Q, false) == "wander")

	# boids: separation pushes apart, cohesion pulls together, attractor pulls
	var close := Boids.steer2(Vector2(0, 0), Vector2.ZERO, [[Vector2(20, 0), Vector2.ZERO]])
	_check("boids separate when too close", close.x < 0.0)
	var far := Boids.steer2(Vector2(0, 0), Vector2.ZERO, [[Vector2(150, 0), Vector2.ZERO]])
	_check("boids cohere at mid range", far.x > 0.0)
	var pulled := Boids.steer2(Vector2(0, 0), Vector2.ZERO, [], Vector2(0, 300))
	_check("boids follow the attractor", pulled.y > 0.0 and absf(pulled.x) < 1.0)
	var alone := Boids.steer2(Vector2(0, 0), Vector2(10, 0), [])
	_check("a lone boid without attractor gets no force", alone == Vector2.ZERO)
	var c3 := Boids.steer3(Vector3.ZERO, Vector3.ZERO, [[Vector3(0.3, 0, 0), Vector3.ZERO]])
	_check("3D boids separate", c3.x < 0.0)

	# drawn paths: resampling and rider counts
	var Ride = load("res://src/ride_path.gd")
	var raw := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 50)])
	var rs: PackedVector2Array = Ride.resample(raw, 10.0)
	var even := true
	for i in range(1, rs.size() - 1):
		if absf(rs[i - 1].distance_to(rs[i]) - 10.0) > 0.01:
			even = false
	_check("stroke resamples to even spacing", rs.size() >= 15 and even and rs[0] == raw[0])
	_check("stroke length and rider count", is_equal_approx(Ride.length_of(raw), 150.0) and Ride.rider_count(150.0) == 2
		and Ride.rider_count(1200.0) == 10 and Ride.rider_count(9999.0) == 24)

	# mosaic: grid sizing, transparent cells skipped, nearest colour
	var mimg := Image.create(200, 100, false, Image.FORMAT_RGBA8)
	mimg.fill(Color(0, 0, 0, 0))
	mimg.fill_rect(Rect2i(0, 0, 100, 100), Color(1, 0, 0, 1))
	var mg := Mosaic.grid_size(mimg)
	_check("mosaic grid keeps aspect and cell cap", mg.x == Mosaic.MAX_COLS and mg.y == Mosaic.MAX_COLS / 2 and mg.x * mg.y <= Mosaic.MAX_CELLS)
	var mc: Array = Mosaic.cells(mimg)
	var left_only := true
	for c in mc:
		if c["u"] > 0.52 or c["color"].r < 0.9:
			left_only = false
	_check("mosaic cells cover only the opaque half", mc.size() > 0 and absi(mc.size() - mg.x * mg.y / 2) <= mg.y and left_only)
	_check("mosaic nearest colour", Mosaic.nearest(Color(0.9, 0.1, 0.1), [Color.BLUE, Color.RED, Color.GREEN]) == 1 and Mosaic.nearest(Color.WHITE, []) == -1)

	# OSC codec: message, types, bundle; and the map's pad / osc feeds
	var OscC = load("res://src/osc.gd")
	var pk: PackedByteArray = OscC.build("/vt/param/fb_zoom", [0.75])
	var msgs: Array = OscC.parse(pk)
	_check("osc message round-trips a float", pk.size() % 4 == 0 and msgs.size() == 1 and msgs[0]["address"] == "/vt/param/fb_zoom" and is_equal_approx(msgs[0]["args"][0], 0.75))
	var multi: Array = OscC.parse(OscC.build("/x", [3, "hi", 0.25, true]))
	_check("osc int / string / float / bool args", multi[0]["args"] == [3, "hi", 0.25, true])
	var m1: PackedByteArray = OscC.build("/a", [1.0])
	var m2: PackedByteArray = OscC.build("/b/c", [2])
	var bundle := PackedByteArray()
	bundle.append_array("#bundle".to_ascii_buffer())
	bundle.append(0)
	bundle.resize(16)                                     # zero timetag
	for m in [m1, m2]:
		var sz := PackedByteArray()
		sz.resize(4)
		sz.encode_u32(0, m.size())
		sz.reverse()
		bundle.append_array(sz)
		bundle.append_array(m)
	var bm: Array = OscC.parse(bundle)
	_check("osc bundle yields its messages in order", bm.size() == 2 and bm[0]["address"] == "/a" and bm[1]["address"] == "/b/c" and bm[1]["args"][0] == 2)
	_check("osc garbage is ignored", OscC.parse("nope".to_ascii_buffer()).is_empty() and OscC.parse(PackedByteArray()).is_empty())
	var cm = load("res://src/midi_map.gd").new()
	cm.path = "user://_smoke_ctrl.json"
	var got2 := {"param": [], "action": []}
	cm.param.connect(func(id, v): got2["param"].append([id, snappedf(v, 0.01)]))
	cm.action.connect(func(id): got2["action"].append(id))
	cm.feed_osc("/vt/param/glow", 0.6)
	cm.feed_osc("/vt/action/clear", 1.0)
	_check("osc direct routes need no learning", got2["param"] == [["glow", 0.6]] and got2["action"] == ["clear"])
	cm.arm("fb_twist")
	cm.feed_osc("/1/fader3", 0.2)
	cm.feed_osc("/1/fader3", 0.9)
	_check("osc address learns like a CC", cm.binding_for("fb_twist") == "osc:/1/fader3" and got2["param"][-1] == ["fb_twist", 0.9] and cm.describe("osc:/1/fader3") == "osc /1/fader3")
	var ax := InputEventJoypadMotion.new()
	ax.device = 0
	ax.axis = JOY_AXIS_LEFT_X
	ax.axis_value = 0.02
	cm.arm("fb_dx")
	cm.feed_pad(ax)                                       # noise: not learned
	ax.axis_value = 1.0
	cm.feed_pad(ax)                                       # deliberate: learned, then value
	ax.axis_value = -1.0
	cm.feed_pad(ax)
	ax.axis_value = 0.0
	cm.feed_pad(ax)
	var vals: Array = got2["param"].filter(func(p): return p[0] == "fb_dx").map(func(p): return p[1])
	_check("stick learns on a deliberate move and maps -1..1 to 0..1 with a centre deadzone", cm.binding_for("fb_dx") == "pad:0:axis:0" and vals == [0.0, 0.5])
	var tr := InputEventJoypadMotion.new()
	tr.axis = JOY_AXIS_TRIGGER_RIGHT
	tr.axis_value = 0.7
	cm.arm("glow")
	cm.feed_pad(tr)
	tr.axis_value = 0.3
	cm.feed_pad(tr)
	_check("trigger maps 0..1 directly", got2["param"][-1] == ["glow", 0.3])
	var bt := InputEventJoypadButton.new()
	bt.device = 1
	bt.button_index = JOY_BUTTON_A
	bt.pressed = true
	cm.arm("act:spawn")
	cm.feed_pad(bt)
	got2["action"].clear()
	cm.feed_pad(bt)
	bt.pressed = false
	cm.feed_pad(bt)
	bt.pressed = true
	cm.feed_pad(bt)
	_check("button learns on press, fires on each press not release", cm.binding_for("act:spawn") == "pad:1:btn:0" and got2["action"] == ["spawn", "spawn"] and cm.describe("pad:1:btn:0") == "pad1 btn 0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cm.path))
	cm.free()

	# strange attractors stay bounded and actually move
	var lp := Vector3(1, 1, 20)
	var lmax := 0.0
	var lmoved := 0.0
	for i in 3000:
		var np := Attractors.lorenz_step(lp, 1.0 / 60.0)
		lmoved += np.distance_to(lp)
		lp = np
		lmax = maxf(lmax, lp.length())
	_check("lorenz stays bounded and travels", lmax < 80.0 and lmoved > 100.0)
	var rp := Vector3(1, 1, 0)
	var rmax := 0.0
	for i in 6000:
		rp = Attractors.rossler_step(rp, 1.0 / 60.0)
		rmax = maxf(rmax, rp.length())
	_check("rossler stays bounded", rmax < 60.0 and rmax > 2.0)
	var cp := Vector2(0.1, 0.1)
	var dp := Vector2(0.1, 0.1)
	var cok := true
	for i in 2000:
		cp = Attractors.clifford(cp)
		dp = Attractors.dejong(dp)
		if absf(cp.x) > 2.01 or absf(cp.y) > 2.01 or absf(dp.x) > 2.01 or absf(dp.y) > 2.01:
			cok = false
	_check("clifford and de jong maps stay in [-2, 2]", cok and cp != Vector2(0.1, 0.1))
	_check("attractor verbs are on Shift+W/T/Y/U", Verbs.by_key(KEY_W, true) == "lorenz" and Verbs.by_key(KEY_T, true) == "rossler"
		and Verbs.by_key(KEY_Y, true) == "clifford" and Verbs.by_key(KEY_U, true) == "dejong" and Verbs.by_key(KEY_W, false) == "orbit")

	# timeline: record, stop, loop with wrap, persistence
	var tl := Timeline.new()
	tl.start_record(10.0)
	tl.record("param", "a", 0.2, 10.0)
	tl.record("action", "spawn", 1.0, 10.5)
	tl.record("param", "a", 0.8, 11.0)
	tl.stop_record(12.0)
	_check("timeline records with relative times and length", tl.events.size() == 3 and is_equal_approx(tl.length, 2.0) and is_equal_approx(tl.events[2]["t"], 1.0))
	_check("no recording after stop", not tl.record("param", "a", 0.5, 12.5))
	tl.start_play(20.0)
	var d1: Array = tl.due(20.6)                          # (0, 0.6]: t=0 and t=0.5
	var d2: Array = tl.due(21.5)                          # (0.6, 1.5]: t=1.0
	var d3: Array = tl.due(22.3)                          # wrap: (1.5, 2] + (0, 0.3]: t=0
	_check("timeline due() returns events in windows and wraps", d1.size() == 2 and d1[1]["id"] == "spawn" and d2.size() == 1 and d2[0]["value"] == 0.8 and d3.size() == 1 and d3[0]["t"] == 0.0)
	var tpath := "user://_smoke_timeline.json"
	tl.save(tpath)
	var tl2 := Timeline.new()
	_check("timeline persists", tl2.load(tpath) and tl2.events.size() == 3 and is_equal_approx(tl2.length, 2.0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tpath))
	var tl3 := Timeline.new()
	tl3.start_record(0.0)
	_check("recording past MAX stops itself", not tl3.record("param", "a", 1.0, Timeline.MAX + 1.0) and not tl3.recording)

	# flow field: bounded, varies in space, nearly divergence-free
	var fmax := 0.0
	var fsum := Vector2.ZERO
	for i in 200:
		var pnt := Vector2(randf() * 1920.0, randf() * 1080.0)
		var c := Field.curl(pnt, 3.0)
		fmax = maxf(fmax, c.length())
		fsum += c
	var e := 2.0
	var q := Vector2(700, 400)
	var div := (Field.curl(q + Vector2(e, 0), 1.0).x - Field.curl(q - Vector2(e, 0), 1.0).x) / (2 * e) \
		+ (Field.curl(q + Vector2(0, e), 1.0).y - Field.curl(q - Vector2(0, e), 1.0).y) / (2 * e)
	_check("curl field is bounded, non-trivial and divergence-free", fmax > 0.05 and fmax < 5.0 and absf(div) < 0.01 and Field.curl(Vector2(10, 10), 0.0) != Field.curl(Vector2(900, 700), 0.0))
	_check("field verb is on Shift+I", Verbs.by_key(KEY_I, true) == "field" and Verbs.by_key(KEY_I, false) == "swarm")
	var psh = load("res://src/particles.gdshader")
	var rsh = load("res://src/rd.gdshader")
	_check("particle and reaction-diffusion shaders load", psh is Shader and psh.get_code().contains("shader_type particles") and rsh is Shader and rsh.get_code().contains("feed"))

	# quality monitor: steps down after sustained slow frames, up after sustained fast ones, honours the lock
	var qm := Quality.new()
	var changed := 0
	for i in 200:                                          # 3.3 s at 30 ms frames
		if qm.update(30.0, 1.0 / 60.0):
			changed += 1
	_check("quality steps down under sustained 30 ms frames (once per cooldown)", qm.level >= 1 and changed == qm.level)
	var lvl := qm.level
	for i in 60:                                           # 1 s in the dead band: nothing
		qm.update(16.0, 1.0 / 60.0)
	_check("dead band holds the level", qm.level == lvl)
	for i in 900:                                          # 15 s at 8 ms frames
		qm.update(8.0, 1.0 / 60.0)
	_check("quality steps back up under sustained fast frames", qm.level < lvl)
	qm.locked = 2
	for i in 300:
		qm.update(40.0, 1.0 / 60.0)
	_check("a locked level never moves; effective is the lock", qm.effective() == 2 and qm.describe() == "medium")
	qm.locked = 3
	qm.cycle_lock()
	_check("lock cycles back to auto", qm.locked == -1 and qm.describe().ends_with("(auto)"))
	_check("ladder sheds load monotonically", Quality.get_level(0)["particles"] > Quality.get_level(3)["particles"]
		and Quality.get_level(3)["rd_every"] > Quality.get_level(0)["rd_every"] and Quality.get_level(3)["glow_taps"] < Quality.get_level(0)["glow_taps"])

	# state lerp: continuous fields interpolate, discrete flip at the midpoint, layers' opacity too
	var sa := {"palette": 0, "glow": 0, "feedback": {"on": false, "zoom": 1.0, "rot": 0.0, "fade": 0.9},
		"camera": {"orbit": 0.0, "dolly": 6.0}, "layers": [{"blend": 0, "opacity": 1.0}, {"blend": 1, "opacity": 0.0}], "fx": {"crt": 0, "key_threshold": 0.2}}
	var sb := {"palette": 3, "glow": 2, "feedback": {"on": true, "zoom": 1.2, "rot": 0.1, "fade": 0.5},
		"camera": {"orbit": 1.0, "dolly": 10.0}, "layers": [{"blend": 0, "opacity": 1.0}, {"blend": 3, "opacity": 1.0}], "fx": {"crt": 2, "key_threshold": 0.6}}
	var q1 := StateLerp.mix(sa, sb, 0.25)
	var q2 := StateLerp.mix(sa, sb, 0.75)
	_check("state lerp: continuous at t=0.25", is_equal_approx(q1["feedback"]["zoom"], 1.05) and is_equal_approx(q1["camera"]["dolly"], 7.0)
		and is_equal_approx(q1["layers"][1]["opacity"], 0.25) and is_equal_approx(q1["fx"]["key_threshold"], 0.3))
	_check("state lerp: discrete from A before the midpoint, B after", q1["palette"] == 0 and q1["glow"] == 0 and q1["feedback"]["on"] == false and q1["layers"][1]["blend"] == 1
		and q2["palette"] == 3 and q2["glow"] == 2 and q2["feedback"]["on"] == true and q2["layers"][1]["blend"] == 3 and q2["fx"]["crt"] == 2)
	_check("state lerp: ends are exact", StateLerp.mix(sa, sb, 0.0)["feedback"]["zoom"] == 1.0 and StateLerp.mix(sa, sb, 1.0)["feedback"]["zoom"] == 1.2)
	# preset banks: isolation and legacy layout
	var bp := "user://_smoke_banks.json"
	var lf := FileAccess.open(bp, FileAccess.WRITE)
	lf.store_string(JSON.stringify({"presets": {"2": {"palette": 1}}}))          # an old, bank-less file
	lf.close()
	_check("legacy preset file is bank 0", Presets.get_preset(2, bp, 0).get("palette") == 1 and Presets.filled(bp, 0) == [2])
	Presets.save(2, {"palette": 7}, bp, 4)
	_check("banks are isolated and the old bank survives", Presets.get_preset(2, bp, 4).get("palette") == 7 and Presets.get_preset(2, bp, 0).get("palette") == 1 and Presets.filled(bp, 3).is_empty())
	Presets.save(6, {"palette": 2}, bp, 4)
	_check("neighbour steps through filled slots and wraps", Presets.neighbour(2, 1, bp, 4) == 6 and Presets.neighbour(6, 1, bp, 4) == 2 and Presets.neighbour(6, -1, bp, 4) == 2 and Presets.neighbour(4, 1, bp, 4) == 6 and Presets.neighbour(1, 1, bp, 1) == 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bp))

	# signed distance field of a disc: inside high, outside low, 0.5 at the rim, symmetric
	var disc := Image.create(120, 120, false, Image.FORMAT_RGBA8)
	for y in 120:
		for x in 120:
			disc.set_pixel(x, y, Color(1, 1, 1, 1.0 if Vector2(x - 60, y - 60).length() < 40 else 0.0))
	var t0 := Time.get_ticks_msec()
	var field := Sdf.from_alpha(disc, 100, 14.0)
	var took := Time.get_ticks_msec() - t0
	var c := Sdf.sample(field, 0.5, 0.5)
	var rim := Sdf.sample(field, 0.5 + 40.0 / 120.0, 0.5)
	var corner := Sdf.sample(field, 0.02, 0.02)
	var just_in := Sdf.sample(field, 0.5 + 34.0 / 120.0, 0.5)
	var just_out := Sdf.sample(field, 0.5 + 46.0 / 120.0, 0.5)
	_check("sdf: centre saturates inside, corner outside, rim at 0.5", c > 0.95 and corner < 0.05 and absf(rim - 0.5) < 0.08)
	_check("sdf: monotone across the edge and symmetric", just_in > 0.6 and just_out < 0.4 and absf(Sdf.sample(field, 0.5 - 34.0 / 120.0, 0.5) - just_in) < 0.05)
	_check("sdf: a 100 px field computes in well under a second", took < 800)
	var msh = load("res://src/morph.gdshader")
	_check("morph shader loads", msh is Shader and msh.get_code().contains("sdf_b") and msh.get_code().contains("outline"))
	_check("morph and outline verbs are on Shift+M / Shift+J", Verbs.by_key(KEY_M, true) == "morph" and Verbs.by_key(KEY_J, true) == "outline")

	# clock: MIDI ticks -> bpm and beats; internal clock advances; bar maths
	var ck = load("res://src/clock.gd").new()
	var cbeats := [0]
	var cbars := [0]
	ck.beat.connect(func(_i): cbeats[0] += 1)
	ck.bar.connect(func(_i): cbars[0] += 1)
	var us := 1000000
	var tick_us := int(60.0e6 / (125.0 * 24))                 # 125 bpm
	for i in 24 * 8:                                          # 8 beats = 2 bars
		ck.feed_tick(us)
		us += tick_us
	_check("midi clock estimates bpm from tick spacing", absf(ck.bpm - 125.0) < 0.5 and ck.running and ck.source == "midi")
	_check("24 ticks per beat, 4 beats per bar", cbeats[0] == 8 and cbars[0] == 2 and ck.beat_in_bar() == 3)
	ck.stop()
	_check("stop halts", not ck.running)
	var ck2 = load("res://src/clock.gd").new()
	var b2 := [0]
	ck2.beat.connect(func(_i): b2[0] += 1)
	ck2.start_internal(120.0)
	var crossed := 0
	for i in 100:                                             # 1 s at 120 bpm = 2 beats after the initial one
		crossed += ck2.advance(0.01)
	_check("internal clock crosses beats on time", crossed == 2 and b2[0] == 3 and absf(ck2.phase) < 0.05)
	_check("bar maths", is_equal_approx(ck2.bar_seconds(), 2.0) and is_equal_approx(ck2.quantise_to_bars(3.2), 4.0) and is_equal_approx(ck2.quantise_to_bars(0.3), 2.0))
	ck2.toggle_internal()
	_check("toggle_internal stops and turns off", not ck2.running and ck2.source == "off" and ck2.describe() == "off")
	ck.free()
	ck2.free()

	# controller templates: valid XML, right counts, addresses; MIDI maps in range; containers round-trip
	var tp := [{"id": "fb_zoom", "label": "Feedback zoom"}, {"id": "glow", "label": "Glow"}]
	var ta := [{"id": "spawn", "label": "Spawn icon"}, {"id": "panic", "label": "PANIC"}, {"id": "next_scene", "label": "Next scene"}]
	var mk1 := Templates.touchosc_xml(tp, ta)
	var xp := XMLParser.new()
	var okx := xp.open_buffer(mk1.to_utf8_buffer()) == OK
	var faders := 0
	var pushes := 0
	var addr_ok := true
	while okx and xp.read() == OK:
		if xp.get_node_type() == XMLParser.NODE_ELEMENT and xp.get_node_name() == "control":
			var t := xp.get_named_attribute_value_safe("type")
			if t == "faderv":
				faders += 1
				addr_ok = addr_ok and xp.get_named_attribute_value_safe("osc_cs").begins_with("/vt/param/")
			elif t == "push":
				pushes += 1
				addr_ok = addr_ok and xp.get_named_attribute_value_safe("osc_cs").begins_with("/vt/action/")
	_check("touchosc mk1 layout: a fader per param, a push per action, addressed by id", okx and faders == 2 and pushes == 3 and addr_ok and mk1.contains(Marshalls.utf8_to_base64("Feedback zoom")))
	var mk2 := Templates.tosc_xml(tp, ta)
	var xp2 := XMLParser.new()
	var ok2 := xp2.open_buffer(mk2.to_utf8_buffer()) == OK
	var fader_nodes := 0
	var button_nodes := 0
	while ok2 and xp2.read() == OK:
		if xp2.get_node_type() == XMLParser.NODE_ELEMENT and xp2.get_node_name() == "node":
			var t := xp2.get_named_attribute_value_safe("type")
			if t == "FADER": fader_nodes += 1
			if t == "BUTTON": button_nodes += 1
	_check("tosc mk2 layout parses with the right nodes and addresses", ok2 and fader_nodes == 2 and button_nodes == 3 and mk2.contains("/vt/param/glow") and mk2.contains("/vt/action/panic") and mk2.contains("<lexml version=\"3\">"))
	var zt := "user://_smoke.tosc"
	Templates.write_tosc(zt, mk2)
	var back := FileAccess.get_file_as_bytes(zt).decompress(mk2.to_utf8_buffer().size() + 64, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8()
	_check("tosc container is zlib-compressed XML that round-trips", back == mk2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zt))
	var zp := "user://_smoke.touchosc"
	Templates.write_touchosc(zp, mk1)
	var zr := ZIPReader.new()
	var zok := zr.open(ProjectSettings.globalize_path(zp)) == OK
	var inner := zr.read_file("index.xml").get_string_from_utf8() if zok else ""
	zr.close()
	_check("touchosc container is a zip holding index.xml", zok and inner == mk1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zp))
	var lpm := Templates.launchpad_bindings()
	var lp_ok := lpm.size() == 72
	for k in lpm:
		var parts: PackedStringArray = k.split(":")
		if parts[0] == "note":
			var n := int(parts[2])
			if n < 11 or n > 88 or n % 10 == 0 or n % 10 == 9:
				lp_ok = false
		elif parts[0] == "cc":
			if int(parts[2]) < 91 or int(parts[2]) > 98:
				lp_ok = false
		else:
			lp_ok = false
	_check("launchpad map: 64 pads + 8 top buttons, all in programmer-mode ranges", lp_ok and lpm["note:1:11"] == "act:slot_1" and lpm["note:1:81"] == "act:panic")
	var apc := Templates.apc_mini_bindings()
	_check("apc mini map: 64 pads, 8 faders + master", apc.size() == 73 and apc["cc:1:48"] == "fb_zoom" and apc["cc:1:56"] == "preset_fade" and apc["note:1:0"] == "act:slot_1" and apc["note:1:63"] == "act:syphon")
	var im = load("res://src/midi_map.gd").new()
	im.path = "user://_smoke_import.json"
	im.bindings = {"cc:1:1": "fb_zoom"}
	var n_in: int = im.import_map({"bindings": {"note:1:11": "act:slot_1", "cc:1:1": "glow"}})
	_check("import_map merges over existing bindings", n_in == 2 and im.bindings.size() == 2 and im.bindings["cc:1:1"] == "glow")
	im.import_map({"bindings": {"cc:1:5": "crt"}}, true)
	_check("import_map replace clears the old map", im.bindings.size() == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(im.path))
	var got3 := {"action": []}
	im.action.connect(func(id): got3["action"].append(id))
	im.feed_osc("/vt/action/spawn", 1.0)
	im.feed_osc("/vt/action/spawn", 0.0)
	_check("osc action ignores a push button's release", got3["action"] == ["spawn"])
	im.free()

	# birthday extras: live text, emoji colour, svg / word-list / video slots, video placeholder
	var now_unix := 1_700_000_000
	var cd := LiveText.parse("countdown 23:59", now_unix)
	var tgt := int(cd.get("target", 0))
	_check("countdown parses to the next 23:59", cd.get("live") == "countdown" and tgt > now_unix and tgt - now_unix <= 86400
		and Time.get_datetime_dict_from_unix_time(tgt)["hour"] == 23 and Time.get_datetime_dict_from_unix_time(tgt)["minute"] == 59)
	_check("countdown text and clock text", LiveText.text_for("countdown", now_unix + 3725, now_unix) == "1:02:05" and LiveText.text_for("countdown", now_unix + 65, now_unix) == "1:05"
		and LiveText.text_for("countdown", now_unix, now_unix + 5) == "🎉" and LiveText.parse("clock").get("live") == "clock" and LiveText.parse("hello").is_empty()
		and LiveText.text_for("clock", 0, now_unix).length() == 8)
	var em := TextRaster.render("🎂", 96)
	_check("emoji renders in colour from the system emoji font", TextRaster.last_had_color and TextRaster.opaque_count(em) > 500)
	var plain := TextRaster.render("Cake", 96)
	_check("plain words stay white", not TextRaster.last_had_color and TextRaster.opaque_count(plain) > 100)
	var xb = load("res://src/toolbox.gd").new()
	xb.path = "user://_smoke_toolbox4.json"
	xb.load_from_disk()
	xb.clear()
	var svg_src := ProjectSettings.globalize_path("user://_smoke_drop.svg")
	var sf := FileAccess.open(svg_src, FileAccess.WRITE)
	sf.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><circle cx="10" cy="10" r="8" fill="#000"/></svg>')
	sf.close()
	var si: int = xb.add_svg(svg_src)
	_check("svg drop becomes a tinted icon slot copied into user://svg", si == 0 and xb.slots[0]["kind"] == "icon" and not xb.is_raster_slot(xb.slots[0]) and xb.slots[0]["svg_path"].begins_with("user://svg/") and FileAccess.file_exists(xb.slots[0]["svg_path"]))
	var few: int = xb.add_words(["ONE", "TWO"])
	_check("a short word list becomes one slot per word", few == 2 and xb.slots.size() == 3 and xb.slots[1]["term"] == "ONE")
	var many: Array = []
	for i in 12:
		many.append("WORD%d" % i)
	var ci: int = xb.add_words(many)
	_check("a long word list becomes one cycling slot with pre-rendered images", ci == 3 and xb.slots[3].has("words") and xb.slots[3]["word_paths"].size() == 12 and FileAccess.file_exists(xb.slots[3]["word_paths"][11]))
	xb.set_slot_path(3, xb.slots[3]["word_paths"][5])
	_check("set_slot_path swaps the image", xb.slots[3]["svg_path"] == xb.slots[3]["word_paths"][5])
	var cake: int = xb.add_text("🎂")
	_check("an emoji word is an untinted slot", cake == 4 and xb.is_raster_slot(xb.slots[4]))
	var live_i: int = xb.add_text("clock")
	_check("clock is a live text slot", live_i == 5 and xb.slots[5].get("live") == "clock")
	var vsrc := ProjectSettings.globalize_path("user://_smoke_drop.ogv")
	var vf := FileAccess.open(vsrc, FileAccess.WRITE)
	vf.store_string("not really theora")
	vf.close()
	var vi: int = xb.add_video(vsrc)
	_check("video drop becomes an untinted video slot in user://video", vi == 6 and xb.slots[6]["kind"] == "video" and xb.is_raster_slot(xb.slots[6]) and xb.slots[6]["svg_path"].ends_with(".ogv"))
	var media = load("res://src/icon_media.gd").new()
	var ph = media.texture_for(xb.slots[6]["svg_path"])
	var fake := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	media.register_live(xb.slots[6]["svg_path"], fake)
	_check("video slots get a placeholder until a live texture is registered", ph != null and ph.get_width() == 480 and media.texture_for(xb.slots[6]["svg_path"]) == fake and media.is_video("a.OGV"))
	media.free()
	for sl in xb.slots:
		for pth in [sl.get("svg_path", "")] + Array(sl.get("word_paths", [])):
			if str(pth).begins_with("user://") and FileAccess.file_exists(str(pth)):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(str(pth)))
	xb.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(xb.path))
	DirAccess.remove_absolute(svg_src)
	DirAccess.remove_absolute(vsrc)
	xb.free()

	# verbs as files: discovered from res://verbs, ordered, group-exclusive; a foreign directory loads too
	var vids: Array = Verbs.ids()
	_check("eighteen verbs are discovered from res://verbs", vids.size() == 18 and vids.has("bounce") and vids.has("morph") and vids.has("dejong") and vids.has("physics") and vids.has("voice"))
	var order_ok := vids.find("bounce") < vids.find("wander") and vids.find("wander") < vids.find("flock") and vids.find("swarm") < vids.find("orbit") and vids.find("lorenz") < vids.find("rossler")
	_check("verbs are ordered by their motion order", order_ok)
	var panel_ids: Array = Verbs.all().map(func(m): return m["id"])
	_check("the panel keeps keyboard order", panel_ids.slice(0, 8) == ["wander", "orbit", "spin", "bounce", "pulse", "sparkle", "rainbow", "swarm"] and panel_ids[-3] == "outline" and panel_ids[-2] == "physics" and panel_ids[-1] == "voice")
	var act: Array = Verbs.active_for(["orbit", "rossler", "lorenz", "spin", "dejong"]).map(func(v): return v.id)
	_check("active_for keeps order and runs one attractor only", act == ["lorenz", "orbit", "spin"])
	_check("verb objects carry hooks", Verbs.instances()[0] is Verb and Verbs.get_verb("flock")["shift"] == true and Verbs.get_verb("bounce").has("hint"))
	var vdir := "user://_smoke_verbs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(vdir))
	var jvf := FileAccess.open(vdir.path_join("jitter.gd"), FileAccess.WRITE)
	jvf.store_string("extends Verb\nfunc _init() -> void:\n\tid = \"jitter\"; name = \"Jitter\"; key = \"9\"; order = 5\nfunc has_motion2d() -> bool: return true\nfunc move2d(a, _d: float) -> bool:\n\ta.position += Vector2(1, 0)\n\treturn true\n")
	jvf.close()
	var extra: Array = Verbs.load_from(vdir)
	var probe := {"position": Vector2.ZERO}
	var jit_ok: bool = extra.size() == 1 and extra[0].id == "jitter" and extra[0].has_motion2d()
	var host := Node2D.new()
	if jit_ok:
		jit_ok = extra[0].move2d(host, 0.016) and host.position == Vector2(1, 0)
	host.free()
	_check("a verb file in another directory loads and runs against a host", jit_ok)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(vdir.path_join("jitter.gd")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(vdir))

	# rig: manifest follows the toolbox's assets, export/import round-trips into another root
	var rroot := "user://_smoke_rig_root"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(rroot.path_join("text")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(rroot.path_join("fonts")))
	for pair in [["toolbox.json", JSON.stringify({"slots": [{"id": "t1", "svg_path": "user://text/t1.png", "word_paths": ["user://text/w0.png"]}, {"id": "d", "svg_path": "res://demo/star.svg"}], "selected": 0})],
			["presets.json", "{\"presets\":{}}"], ["midi.json", "{\"bindings\":{\"cc:1:1\":\"glow\"}}"], ["text/t1.png", "PNG1"], ["text/w0.png", "PNG2"], ["fonts/current.ttf", "FONT"]]:
		var wf := FileAccess.open(rroot.path_join(pair[0]), FileAccess.WRITE)
		wf.store_string(pair[1])
		wf.close()
	var man: Array = Rig.manifest(rroot)
	_check("rig manifest lists top files, the font and every asset the toolbox points at (user:// only)",
		man.has("toolbox.json") and man.has("midi.json") and man.has("fonts/current.ttf") and man.has("text/t1.png") and man.has("text/w0.png") and not man.has("attribution.json") and man.size() == 6)
	var zpath := "user://_smoke_rig.zip"
	var rig_out: int = Rig.export(zpath, rroot)
	var rroot2 := "user://_smoke_rig_root2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(rroot2))
	var rig_in: int = Rig.import(zpath, rroot2)
	_check("rig export/import round-trips every file", rig_out == 6 and rig_in == 6 and FileAccess.get_file_as_string(rroot2.path_join("text/w0.png")) == "PNG2"
		and FileAccess.get_file_as_string(rroot2.path_join("midi.json")).contains("glow") and FileAccess.file_exists(rroot2.path_join("fonts/current.ttf")))
	var bogus := "user://_smoke_not_rig.zip"
	var zb := ZIPPacker.new()
	zb.open(ProjectSettings.globalize_path(bogus))
	zb.start_file("hello.txt")
	zb.write_file("hi".to_utf8_buffer())
	zb.close_file()
	zb.close()
	_check("a zip without rig.json is refused", Rig.import(bogus, rroot2) == -1)
	for rel in ["text/t1.png", "text/w0.png", "fonts/current.ttf", "toolbox.json", "presets.json", "midi.json", "rig.json"]:
		for rr in [rroot, rroot2]:
			var pp2: String = rr.path_join(rel)
			if FileAccess.file_exists(pp2):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(pp2))
	for rr in [rroot, rroot2]:
		for sub in ["text", "fonts"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(rr.path_join(sub)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rr))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zpath))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bogus))
	# image diff: identical passes, a shifted digit passes, a broken picture fails
	var ia := Image.create(640, 360, false, Image.FORMAT_RGB8)
	ia.fill(Color(0.1, 0.1, 0.15))
	ia.fill_rect(Rect2i(200, 100, 240, 160), Color(1.0, 0.3, 0.6))
	var ib: Image = ia.duplicate()
	ib.fill_rect(Rect2i(20, 20, 30, 12), Color.WHITE)                   # a HUD digit changed
	var ic: Image = ia.duplicate()
	ic.fill_rect(Rect2i(200, 100, 240, 160), Color(0.1, 0.1, 0.15))   # the picture vanished
	var same: Dictionary = ImageDiff.compare(ia, ia)
	var digit: Dictionary = ImageDiff.compare(ia, ib)
	var broken: Dictionary = ImageDiff.compare(ia, ic)
	_check("image diff: identical and near-identical pass, a missing picture fails",
		same["pass"] and same["mean"] == 0.0 and digit["pass"] and not broken["pass"] and broken["mean"] > digit["mean"])

	# autosave helpers (pure): write / read / age / flag / describe; ascii shader
	var ap := "user://_smoke_autosave.json"
	var okw := Autosave.write({"palette": 2, "live": {"actors": []}}, ap)
	var rd := Autosave.read(ap)
	_check("autosave writes and reads with a timestamp", okw and rd.get("palette") == 2 and rd.has("saved_at") and Autosave.age_seconds(ap) <= 1 and Autosave.age_seconds(ap, int(rd["saved_at"]) + 125) == 125)
	_check("autosave age text", Autosave.describe_age(-1) == "no autosave" and Autosave.describe_age(40) == "40 s ago" and Autosave.describe_age(3000) == "50 min ago" and Autosave.describe_age(9000) == "2 h ago")
	var fl := "user://_smoke_running.flag"
	Autosave.mark_running(fl)
	var was := Autosave.crashed_last_time(fl)
	Autosave.mark_clean_exit(fl)
	_check("running flag marks an unclean exit until a clean one", was and not Autosave.crashed_last_time(fl))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ap))
	var ash = load("res://src/ascii.gdshader")
	_check("ascii shader loads", ash is Shader and ash.get_code().contains("glyphs") and ash.get_code().contains("mode"))

	# build stamp and the audio-input override
	var bp2 := "user://_smoke_build.json"
	var bf := FileAccess.open(bp2, FileAccess.WRITE)
	bf.store_string('{"version":"1.2.3","hash":"abcdef1234567890","date":"2026-09-06"}')
	bf.close()
	_check("build stamp reads version, short hash and date", Build.describe(bp2) == "v1.2.3 abcdef12 2026-09-06" and Build.describe("user://_none.json").begins_with("v1.0.0 dev"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bp2))
	var op := "user://_smoke_override.cfg"
	_check("no override = -1", AudioInputSetting.override_state(op) == -1)
	AudioInputSetting.set_enabled(false, op)
	var st0 := AudioInputSetting.override_state(op)
	AudioInputSetting.set_enabled(true, op)
	_check("audio input override writes enable_input=false and is removed when re-enabled", st0 == 0 and AudioInputSetting.override_state(op) == -1 and not FileAccess.file_exists(op))
	_check("override path is res:// in the editor and beside the executable in a build", AudioInputSetting.override_path().ends_with("override.cfg"))

	# keys: one source of truth; every verb is on the card; docs are regenerated from it
	var kg: Array = Keys.groups()
	var card_keys: Array = []
	for g in kg:
		for r in g["rows"]:
			card_keys.append(r[0])
	var all_verbs := true
	for v in Verbs.instances():
		all_verbs = all_verbs and card_keys.has(v.key.replace("⇧", "Shift+").replace("^", "Ctrl+"))
	_check("key groups cover every verb, panic, blackout and the menu", kg.size() >= 8 and all_verbs and card_keys.has("Shift+Esc") and card_keys.has("Shift+H") and card_keys.has("Esc / ☰"))
	_check("help text and markdown come from the same rows", Keys.help_text().contains("Shift+Esc") and Keys.markdown().begins_with("# Video Toy keys") and Keys.markdown().count("\n| `") == card_keys.size())
	_check("docs/KEYS.md is up to date (./run.sh keycard)", FileAccess.get_file_as_string("res://docs/KEYS.md") == Keys.markdown())
	_check("docs/key-card.png exists and docs/SHOW.md points at it", FileAccess.file_exists("res://docs/key-card.png") and FileAccess.get_file_as_string("res://docs/SHOW.md").contains("key-card.png"))

	# settings.cfg: defaults, round trip, reset; help filter is pure
	var sp := "user://_smoke_settings.cfg"
	Settings.reset(sp)
	_check("settings defaults", int(Settings.get_value("osc_port", sp)) == 9000 and str(Settings.get_value("quality_lock", sp)) == "auto" and Settings.get_value("nope", sp) == null)
	Settings.set_value("osc_port", 9123, sp)
	Settings.set_value("syphon_name", "Knobcon", sp)
	Settings._cache.erase(sp)                             # force a re-read from disk
	_check("settings round-trip through the file", int(Settings.get_value("osc_port", sp)) == 9123 and str(Settings.get_value("syphon_name", sp)) == "Knobcon" and Settings.all(sp).size() == Settings.DEFAULTS.size())
	Settings.reset(sp)
	_check("settings reset restores defaults and removes the file", int(Settings.get_value("osc_port", sp)) == 9000 and not FileAccess.file_exists(sp))
	var tabs_ok := true
	for g in Keys.groups():
		tabs_ok = tabs_ok and str(g.get("tab", "")) != ""
	var f1 := HelpOverlay.filter(Keys.groups(), "", "slit-scan")
	var f2 := HelpOverlay.filter(Keys.groups(), "Verbs", "")
	var f3 := HelpOverlay.filter(Keys.groups(), "", "zzzz-nothing")
	var f4 := HelpOverlay.filter(Keys.groups(), "Show", "blackout")
	_check("help filter: every group has a tab; query, tab, tab+query, no match", tabs_ok and f1.size() == 1 and f1[0]["rows"].size() == 1 and f2.size() == 1 and f2[0]["rows"].size() == Verbs.instances().size() and f3.is_empty() and f4.size() == 1 and f4[0]["rows"].size() == 1)
	_check("image diff thresholds come from settings", is_equal_approx(float(Settings.get_value("diff_mean", sp)), 0.035) and is_equal_approx(float(Settings.get_value("diff_block", sp)), 0.45))

	# physics polygons from alpha, verb key lookup with Ctrl, exclusive flag, test wav
	var disc2 := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			disc2.set_pixel(x, y, Color(1, 1, 1, 1.0 if Vector2(x - 32, y - 32).length() < 28 else 0.0))
	var polys: Array = IconBody.polygons_for(ImageTexture.create_from_image(disc2), 0.5)
	var far2 := 0.0
	for poly_pt in polys[0]:
		far2 = maxf(far2, Vector2(poly_pt).length())
	_check("icon body polygons come from the alpha, scaled", polys.size() >= 1 and polys[0].size() >= 8 and far2 > 10.0 and far2 < 20.0)
	_check("polygons for a null texture fall back to a box", IconBody.polygons_for(null, 1.0)[0].size() == 4)
	var pv = Verbs.instances().filter(func(v): return v.id == "physics")
	_check("physics verb: Ctrl+P, exclusive, order 0, rotation", pv.size() == 1 and pv[0].ctrl and pv[0].exclusive and pv[0].order == 0 and pv[0].sets_rotation and Verbs.by_key(KEY_P, false, true) == "physics" and Verbs.by_key(KEY_P, false, false) == "")
	var twav := "user://_smoke_tone.wav"
	_check("test wav writes and loads", Sounds.make_test_wav(twav) and Sounds.load_stream(twav) is AudioStreamWAV and Sounds.load_stream(twav).get_length() > 0.1)
	_check("no host: play is a no-op", not Sounds.play(twav))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(twav))
	_check("key card names gravity and slot sounds", Keys.markdown().contains("Ctrl+G") and Keys.markdown().contains("Ctrl+P") and Keys.markdown().contains("drop .wav"))

	# safe mode decision is pure; crash logs: rotation naming, error extraction, report
	_check("safe mode from the flag or the setting", Safe.from(PackedStringArray(["--safe"]), false) and Safe.from(PackedStringArray(), true) and not Safe.from(PackedStringArray(["--selftest"]), false))
	var ld := "user://_smoke_logs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ld))
	for nm in ["godot.log", "godot2026-09-06T01.22.18.log", "godot2026-09-06T01.44.01.log", "notes.txt"]:
		var lgf := FileAccess.open(ld.path_join(nm), FileAccess.WRITE)
		lgf.store_string("Godot Engine v4.7\nhello\nERROR: something broke\n   at: foo\nSCRIPT ERROR: Invalid call\nERROR: something broke\nbye\n")
		lgf.close()
	var lfs := CrashLog.files(ld)
	_check("previous run's log is the newest timestamped file, not godot.log", lfs.size() == 2 and CrashLog.previous(ld).ends_with("godot2026-09-06T01.44.01.log") and CrashLog.current(ld).ends_with("godot.log"))
	var errs := CrashLog.errors(FileAccess.get_file_as_string(CrashLog.previous(ld)))
	_check("error lines are extracted, deduplicated in sequence", errs == ["ERROR: something broke", "SCRIPT ERROR: Invalid call", "ERROR: something broke"])
	var rep := CrashLog.report(CrashLog.previous(ld))
	_check("report names the file, counts errors and ends with the tail", rep.contains("3 error lines") and rep.contains("tail:") and rep.ends_with("bye") and CrashLog.report("") == "no log from the last run")
	_check("this run is being logged to user://logs/godot.log", FileAccess.file_exists(CrashLog.current()))
	for nm in ["godot.log", "godot2026-09-06T01.22.18.log", "godot2026-09-06T01.44.01.log", "notes.txt"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ld.path_join(nm)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ld))

	# the guest wheel's hit test is pure; the tour has five steps
	var wc := Vector2(500, 500)
	_check("wheel: hub, outside, and the first item straight up", RadialMenu.pick(wc, wc, 8) == -2 and RadialMenu.pick(wc + Vector2(400, 0), wc, 8) == -1 and RadialMenu.pick(wc + Vector2(0, -150), wc, 8) == 0 and RadialMenu.pick(wc + Vector2(150, 0), wc, 8) == 2 and RadialMenu.pick(wc + Vector2(0, 150), wc, 8) == 4 and RadialMenu.pick(wc + Vector2(-150, 0), wc, 8) == 6)
	_check("wheel: item positions land in their own sector", RadialMenu.pick(RadialMenu.item_pos(wc, 5, 9), wc, 9) == 5 and RadialMenu.pick(RadialMenu.item_pos(wc, 0, 17), wc, 17) == 0 and RadialMenu.pick(RadialMenu.item_pos(wc, 16, 17), wc, 17) == 16)
	_check("tour: five captions with anchors inside the picture", Tour.STEPS.size() == 5 and Tour.STEPS.all(func(st): return str(st["text"]).length() > 40 and Rect2(0, 0, 1, 1).has_point(st["at"])))
	_check("tour_seen defaults off", not Tour.seen("user://_smoke_no_settings.cfg"))

	# icon voice: the silhouette's radius is the waveform
	var star_img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			var d := Vector2(x - 48, y - 48)
			var rr := 18.0 + 22.0 * maxf(0.0, cos(5.0 * d.angle()))      # a five-pointed star
			star_img.set_pixel(x, y, Color(1, 1, 1, 1.0 if d.length() < rr else 0.0))
	var star_t := IconVoice.table_from_sdf(Sdf.from_alpha(star_img, 96), 256)
	var peak := 0.0
	var mean := 0.0
	for v in star_t:
		peak = maxf(peak, absf(v))
		mean += v
	var zc := IconVoice.zero_crossings(star_t)
	_check("star: 256 samples, centred, five bumps (about ten zero crossings)", star_t.size() == 256 and absf(mean / 256.0) < 0.05 and peak > 0.7 and peak <= 0.91 and zc >= 8 and zc <= 12)
	var circ_img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 96:
			circ_img.set_pixel(x, y, Color(1, 1, 1, 1.0 if Vector2(x - 48, y - 48).length() < 30 else 0.0))
	var circ_t := IconVoice.table_from_sdf(Sdf.from_alpha(circ_img, 96), 256)
	var cpeak := 0.0
	for v in circ_t:
		cpeak = maxf(cpeak, absf(v))
	_check("circle: flat profile falls back to a sine (two zero crossings)", circ_t.size() == 256 and cpeak > 0.5 and IconVoice.zero_crossings(circ_t) == 2)
	_check("pentatonic pitches rise per slot from A2", is_equal_approx(IconVoice.note_for(0), 110.0) and IconVoice.note_for(1) > IconVoice.note_for(0) and is_equal_approx(IconVoice.note_for(5), 220.0) and IconVoice.note_for(9) == IconVoice.note_for(0))
	var vv = Verbs.instances().filter(func(v): return v.id == "voice")
	_check("voice verb: Ctrl+V, post-only", vv.size() == 1 and vv[0].ctrl and not vv[0].has_motion2d() and Verbs.by_key(KEY_V, false, true) == "voice")

	# MIDI out over OSC: the ladder, velocities, a loopback round trip, gated note-offs
	_check("midi out: pentatonic ladder from A2 and velocity curves", MidiOut.note_for_slot(0) == 45 and MidiOut.note_for_slot(5) == 57 and MidiOut.note_for_slot(9) == 45 and MidiOut.velocity_for_speed(0.0) == 40 and MidiOut.velocity_for_speed(5000.0) == 127 and MidiOut.velocity_for_height(0.0, 1080.0) == 127 and MidiOut.velocity_for_height(1080.0, 1080.0) == 60)
	MidiOut.configure("127.0.0.1", 9151, false)
	_check("midi out: off means nothing is sent", not MidiOut.send("/vt/midi/cc", [1, 1, 1]) and MidiOut.sent == 0)
	var rx := PacketPeerUDP.new()
	var bound := rx.bind(9151, "127.0.0.1") == OK
	MidiOut.configure("127.0.0.1", 9151, true)
	MidiOut.note_on(1, 60, 100, 0.0)
	MidiOut.cc(1, 7, 200)
	MidiOut.tick(Time.get_ticks_msec() + 10)
	var mo_got: Array = []
	for i in 40:
		while rx.get_available_packet_count() > 0:
			mo_got.append_array(OscC.parse(rx.get_packet()))
		if mo_got.size() >= 3:
			break
		OS.delay_msec(5)
	rx.close()
	var mo_addrs: Array = mo_got.map(func(m): return m["address"])
	_check("midi out: note_on, cc (clamped) and the gated note_off arrive over loopback", bound and mo_addrs == ["/vt/midi/note_on", "/vt/midi/cc", "/vt/midi/note_off"] and mo_got[0]["args"] == [1, 60, 100] and mo_got[1]["args"] == [1, 7, 127] and mo_got[2]["args"] == [1, 60] and MidiOut.pending() == 0 and MidiOut.sent == 3)
	MidiOut.configure("127.0.0.1", 9001, false)
	MidiOut.sent = 0

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
