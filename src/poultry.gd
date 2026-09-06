class_name Poultry
extends ColorRect
## Perplexing Poultry: the picture as a quasicrystal. A pentagrid (five —
## or seven — families of parallel lines, de Bruijn's construction) cuts
## the plane into non-repeating cells; each cell gets one of the toolbox
## icons as its glyph, skinny or fat, coloured from the palette and the
## picture under it, and on the beat the cells peck at a neighbour. A
## composite pass over the screen; the atlas of glyphs is built from the
## toolbox (static, tested).

const ATLAS_CELL := 128
const ATLAS_COLS := 3
const ORDERS := [5, 7]
const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D atlas : filter_linear, repeat_disable;
uniform int glyphs = 1;
uniform int atlas_cols = 3;
uniform int order = 5;          // line families: 5 (Penrose-like) or 7
uniform float scale = 9.0;      // cells across the width
uniform float adherence = 0.4;  // how much the picture under a cell shows through
uniform float fat = 0.5;        // share of fat cells
uniform float peck = 0.0;       // beat envelope
uniform float peck_seed = 0.0;
uniform int palette_count = 0;
uniform vec4 palette[16];

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec3 ring_color(float t) {
	int n = max(palette_count - 1, 1);
	float f = fract(t) * float(n);
	int i = int(floor(f));
	int j = (i + 1) % n;
	return mix(palette[i].rgb, palette[j].rgb, fract(f));
}
vec2 rot(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

void fragment() {
	vec4 src = texture(screen_tex, SCREEN_UV);
	vec2 p = SCREEN_UV * vec2(1.7778, 1.0) * scale;
	// the pentagrid: which strip of each family, and the cell's centre from the strip midlines
	vec2 c = vec2(0.0);
	float id_a = 0.0;
	float id_b = 0.0;
	float edge = 1.0;
	int n = clamp(order, 3, 7);
	for (int k = 0; k < 7; k++) {
		if (k >= n) break;
		float ang = 6.283185 * float(k) / float(n);
		vec2 e = vec2(cos(ang), sin(ang));
		float gamma = 0.21 + 0.137 * float(k);
		float g = dot(p, e) + gamma;
		float K = floor(g);
		c += (K + 0.5 - gamma) * e;
		id_a += K * float(7 + k * 11);
		id_b += K * float(3 + k * 5);
		edge = min(edge, abs(fract(g) - 0.5) * 2.0);      // 0 on a grid line
	}
	c *= 2.0 / float(n);
	vec2 d = p - c;
	float h = hash21(vec2(id_a, id_b));
	float h2 = hash21(vec2(id_b * 1.7, id_a * 0.3));
	// the peck: this cell leans toward one neighbour while the beat rings
	float na = 6.283185 * floor(hash21(vec2(id_a + peck_seed, id_b)) * float(n)) / float(n);
	d -= vec2(cos(na), sin(na)) * peck * 0.12;
	bool is_fat = h2 < fat;
	float gs = is_fat ? 0.62 : 0.4;                         // glyph radius in cell units
	vec2 guv = rot(d, (h - 0.5) * 1.2 + peck * (h2 - 0.5)) / gs * 0.5 + 0.5;
	vec3 bg = mix(palette[max(palette_count - 1, 0)].rgb, src.rgb, adherence);
	vec3 col = bg;
	float a = 0.0;
	if (guv.x > 0.0 && guv.x < 1.0 && guv.y > 0.0 && guv.y < 1.0) {
		int gi = int(h * float(max(glyphs, 1))) % max(glyphs, 1);
		vec2 cell = vec2(float(gi % atlas_cols), float(gi / atlas_cols));
		vec4 g4 = texture(atlas, (cell + guv) / float(atlas_cols));
		a = g4.a;
		vec3 tint = mix(ring_color(h * 0.9 + 0.05), src.rgb, adherence);
		col = mix(bg, g4.rgb * tint, a);
	}
	// the tessellation's seams
	float seam = 1.0 - smoothstep(0.0, 0.05, edge);
	col = mix(col, ring_color(0.5) * 0.7, seam * 0.6);
	COLOR = vec4(col, 1.0);
}
"""

var on := false
var cell_scale := 9.0                     # cells across the width (Control has its own `scale`)
var adherence := 0.4
var order := 5
var fat := 0.5
var peck_env := 0.0
var _mat: ShaderMaterial
var _seed := 0.0


func _init(size_px: Vector2) -> void:
	size = size_px
	color = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	material = _mat
	visible = false


## One atlas of `ATLAS_COLS`² cells from the slot textures (white-on-alpha icons keep
## their alpha; rasters keep their colour).
static func build_atlas(textures: Array, cell := ATLAS_CELL, cols := ATLAS_COLS) -> ImageTexture:
	var img := Image.create(cell * cols, cell * cols, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var n := mini(textures.size(), cols * cols)
	for i in n:
		var tex: Texture2D = textures[i]
		if tex == null:
			continue
		var src: Image = tex.get_image()
		if src == null or src.is_empty():
			continue
		var s: Image = src.duplicate()
		s.convert(Image.FORMAT_RGBA8)
		var f := minf(float(cell - 8) / s.get_width(), float(cell - 8) / s.get_height())
		s.resize(maxi(1, int(s.get_width() * f)), maxi(1, int(s.get_height() * f)), Image.INTERPOLATE_LANCZOS)
		var at := Vector2i((i % cols) * cell + (cell - s.get_width()) / 2, (i / cols) * cell + (cell - s.get_height()) / 2)
		img.blit_rect(s, Rect2i(Vector2i.ZERO, s.get_size()), at)
	return ImageTexture.create_from_image(img)


func set_atlas(textures: Array) -> void:
	_mat.set_shader_parameter("atlas", build_atlas(textures))
	_mat.set_shader_parameter("glyphs", maxi(1, mini(textures.size(), ATLAS_COLS * ATLAS_COLS)))
	_mat.set_shader_parameter("atlas_cols", ATLAS_COLS)


func glyph_count() -> int:
	return int(_mat.get_shader_parameter("glyphs"))


func set_on(v: bool) -> void:
	on = v
	visible = v
	push()


func peck() -> void:
	peck_env = 1.0
	_seed += 1.0
	push()


func cycle_order() -> void:
	order = ORDERS[(ORDERS.find(order) + 1) % ORDERS.size()]
	push()


func push() -> void:
	_mat.set_shader_parameter("scale", cell_scale)
	_mat.set_shader_parameter("adherence", adherence)
	_mat.set_shader_parameter("order", order)
	_mat.set_shader_parameter("fat", fat)
	_mat.set_shader_parameter("peck", peck_env)
	_mat.set_shader_parameter("peck_seed", _seed)


func _process(delta: float) -> void:
	if not on or peck_env <= 0.0:
		return
	peck_env = maxf(0.0, peck_env - delta * 3.0)
	_mat.set_shader_parameter("peck", peck_env)


func describe() -> String:
	return "poultry %d-fold ×%.0f adhere %.2f" % [order, cell_scale, adherence] if on else ""
