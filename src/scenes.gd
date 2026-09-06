class_name Scenes
## The scene table: shader sources that run as a layer behind everything in
## the world. Five "art" scenes and four oscillator primitives, one system.
## Session state (current scene, knobs) lives in static vars so the Scenes
## screen and the stage agree; presets persist it.

const ALL := [
	{"id": "plasma", "name": "Plasma", "kind": "art"},
	{"id": "warpfbm", "name": "Warp", "kind": "art"},
	{"id": "truchet", "name": "Truchet", "kind": "art"},
	{"id": "voronoi", "name": "Voronoi", "kind": "art"},
	{"id": "blobs", "name": "Blobs", "kind": "art"},
	{"id": "purplerain", "name": "Purple rain", "kind": "art"},
	{"id": "ramp", "name": "Ramp", "kind": "osc"},
	{"id": "bars", "name": "Bars", "kind": "osc"},
	{"id": "rings", "name": "Rings", "kind": "osc"},
	{"id": "noise", "name": "Noise", "kind": "osc"},
]

static var current := ""              # "" = off
static var speed := 1.0
static var scale := 1.0
static var bias := 0.0


static func ids() -> Array:
	return ALL.map(func(s): return s["id"])


static func get_scene(id: String) -> Dictionary:
	for s in ALL:
		if s["id"] == id:
			return s
	return {}


static func shader_path(id: String) -> String:
	return "res://scenes/%s.gdshader" % id


static func index_of(id: String) -> int:
	return ids().find(id)


## The id `step` places along the list from `id` ("" counts as before the first).
static func neighbour(id: String, step: int) -> String:
	var i := index_of(id)
	var n := ALL.size()
	if i < 0:
		return ALL[0]["id"] if step > 0 else ALL[n - 1]["id"]
	return ALL[posmod(i + step, n)]["id"]


## Build a ShaderMaterial for a scene with the palette and knobs applied.
static func material_for(id: String, palette_index: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(shader_path(id))
	apply_palette(m, palette_index)
	apply_knobs(m)
	return m


static func apply_palette(m: ShaderMaterial, palette_index: int) -> void:
	var colours: Array = Palettes.ring(palette_index)
	colours.append(Palettes.bg(palette_index))
	var arr: Array[Color] = []
	for i in 16:
		arr.append(colours[i] if i < colours.size() else Color.BLACK)
	m.set_shader_parameter("palette", PackedColorArray(arr))
	m.set_shader_parameter("palette_count", mini(colours.size(), 16))


static func apply_knobs(m: ShaderMaterial) -> void:
	m.set_shader_parameter("speed", speed)
	m.set_shader_parameter("scale", scale)
	m.set_shader_parameter("bias", bias)
