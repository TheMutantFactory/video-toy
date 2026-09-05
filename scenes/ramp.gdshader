shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
// Oscillator: a horizontal ramp through the palette, scrolling.
void fragment() {
	float x = scene_uv(UV).x * 0.6 - TIME * speed * 0.2 + bias;
	COLOR = vec4(ring_color(x), 1.0);
}
