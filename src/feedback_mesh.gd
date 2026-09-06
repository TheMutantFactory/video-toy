class_name FeedbackMesh
## The feedback "previous frame" drawn through a subdivided quad whose vertices
## a shader warps Milkdrop-style. Static builders; autoload-free.

const COLS := 32
const ROWS := 18

const WARP_SHADER := """
shader_type canvas_item;
// Per-vertex warp of the previous frame. All in pixels of the 1920x1080 world.
uniform float warp = 0.0;        // amplitude, 0 .. 1  (~0 .. 60 px)
uniform float warp_speed = 1.0;
uniform vec2 drift = vec2(0.0);  // px per frame, pushed in every pass
uniform vec2 stretch = vec2(1.0);
uniform vec2 centre = vec2(960.0, 540.0);
// inside the loop, per pass:
uniform float blur = 0.0;        // -1 sharpen .. 1 blur
uniform float hue = 0.0;         // hue rotation, radians per pass
uniform float sat = 1.0;         // saturation multiplier per pass
uniform float displace = 0.0;    // 0 .. 1, by disp_tex's colour
uniform bool disp_on = false;
uniform sampler2D disp_tex : filter_linear, repeat_disable;
uniform float cleanup = 0.0;     // cellular cleanup per pass, 0 .. 1
uniform int cleanup_rule = 0;    // 0 majority grow, 1 Life, 2 erode
const vec3 LUMA = vec3(0.299, 0.587, 0.114);
vec3 hue_rotate(vec3 c, float a) {
	const vec3 k = vec3(0.57735);
	float cs = cos(a);
	return c * cs + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cs);
}
void vertex() {
	vec2 p = VERTEX;
	vec2 d = (p - centre) * stretch + centre - p;
	float t = TIME * warp_speed;
	vec2 n = p * 0.0025;
	vec2 w = vec2(
		sin(t * 0.333 + n.x * 3.1 - n.y * 1.7) + cos(t * 0.375 - n.x * 2.3 + n.y * 2.9),
		cos(t * 0.291 + n.x * 1.9 + n.y * 2.7) + sin(t * 0.412 - n.x * 3.7 + n.y * 1.3));
	VERTEX = p + d + w * warp * 30.0 + drift;
}
void fragment() {
	vec2 uv = UV;
	if (disp_on) {
		vec4 d = texture(disp_tex, UV);
		uv += (d.rg - 0.5) * d.a * displace * 0.08;
	}
	vec4 c = texture(TEXTURE, uv);
	if (abs(blur) > 0.001) {
		vec2 px = TEXTURE_PIXEL_SIZE * (1.0 + 2.0 * abs(blur));
		vec4 avg = (texture(TEXTURE, uv + vec2(px.x, 0.0)) + texture(TEXTURE, uv - vec2(px.x, 0.0))
			+ texture(TEXTURE, uv + vec2(0.0, px.y)) + texture(TEXTURE, uv - vec2(0.0, px.y))) * 0.25;
		c = blur > 0.0 ? mix(c, avg, blur) : clamp(c + (c - avg) * (-blur) * 1.5, 0.0, 1.0);
	}
	if (cleanup > 0.001) {
		// the twist-box's cellular cleanup: local rules on the previous pass grow
		// coherent regions out of the smear (or thin it), one iteration per loop pass
		vec2 px = TEXTURE_PIXEL_SIZE * 1.5;
		int alive = 0;
		vec4 sum = vec4(0.0);
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dy == 0) continue;
				vec4 n = texture(TEXTURE, uv + vec2(float(dx), float(dy)) * px);
				sum += n;
				alive += (dot(n.rgb, LUMA) * n.a > 0.18) ? 1 : 0;
			}
		}
		vec4 mean = sum / 8.0;
		bool on = dot(c.rgb, LUMA) * c.a > 0.18;
		vec4 target = c;
		if (cleanup_rule == 0) {
			if (alive >= 5) target = max(c, mean);
			else if (alive <= 2) target = c * 0.6;
		} else if (cleanup_rule == 1) {
			bool next = on ? (alive == 2 || alive == 3) : (alive == 3);
			target = next ? (on ? c : min(mean * 1.4, vec4(1.0))) : c * 0.5;
		} else {
			if (alive <= 4) target = c * 0.5;
		}
		c = mix(c, target, cleanup);
	}
	if (abs(hue) > 0.0001 || abs(sat - 1.0) > 0.0001) {
		vec3 rgb = hue_rotate(c.rgb, hue);
		float l = dot(rgb, vec3(0.299, 0.587, 0.114));
		c.rgb = clamp(mix(vec3(l), rgb, sat), 0.0, 1.0);
	}
	COLOR = c * COLOR;
}
"""


## A cols x rows grid of quads covering `size`, centred on the origin, with UVs.
static func build(size: Vector2, cols := COLS, rows := ROWS) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for y in rows + 1:
		for x in cols + 1:
			var u := float(x) / cols
			var v := float(y) / rows
			verts.append(Vector2((u - 0.5) * size.x, (v - 0.5) * size.y))
			uvs.append(Vector2(u, v))
	for y in rows:
		for x in cols:
			var i := y * (cols + 1) + x
			idx.append_array([i, i + 1, i + cols + 1, i + 1, i + cols + 2, i + cols + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func vertex_count(cols := COLS, rows := ROWS) -> int:
	return (cols + 1) * (rows + 1)


static func material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = WARP_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	return m
