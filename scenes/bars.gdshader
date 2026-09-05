shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
// Oscillator: sine bars, quantised to palette bands.
void fragment() {
	vec2 p = scene_uv(UV);
	float v = 0.5 + 0.5 * sin(p.y * 12.0 + TIME * speed * 2.0 + sin(p.x * 3.0 + TIME * speed * 0.5));
	float n = float(max(palette_count - 1, 1));
	v = floor(v * n) / n;
	COLOR = vec4(ring_color(v + bias), 1.0);
}
