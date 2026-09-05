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
