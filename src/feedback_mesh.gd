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
	COLOR = texture(TEXTURE, UV) * COLOR;
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
