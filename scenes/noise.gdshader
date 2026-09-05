shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
// Oscillator: drifting fbm, colourised through the ring.
void fragment() {
	vec2 p = scene_uv(UV) * 3.0 + vec2(TIME * speed * 0.1, 0.0);
	float f = fbm(p + 0.3 * TIME * speed * 0.1);
	COLOR = vec4(ring_color(f * 1.2 + bias), 1.0);
}
