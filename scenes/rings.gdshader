shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
// Oscillator: radial rings pulsing outward from the centre.
void fragment() {
	vec2 p = scene_uv(UV);
	float d = length(p) * 3.0 - TIME * speed * 0.5;
	float n = float(max(palette_count - 1, 1));
	float v = floor(fract(d) * n) / n;
	COLOR = vec4(ring_color(v + bias), 1.0);
}
