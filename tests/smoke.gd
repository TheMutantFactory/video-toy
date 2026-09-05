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

	print("\n%d/%d checks passed" % [_n - _fails, _n])
	quit(1 if _fails > 0 else 0)


func _unique(arr: Array) -> bool:
	var seen := {}
	for a in arr:
		if seen.has(a):
			return false
		seen[a] = true
	return true
