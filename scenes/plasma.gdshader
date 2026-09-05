shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
void fragment() {
	vec2 p = scene_uv(UV) * 3.0;
	float t = TIME * speed;
	float v = sin(p.x + t) + sin(p.y * 1.3 + t * 0.7) + sin((p.x + p.y) * 0.8 + t * 1.1)
		+ sin(length(p - vec2(0.8, 0.4)) * 1.5 - t * 0.9);
	COLOR = vec4(ring_color(v * 0.125 + t * 0.03 + bias), 1.0);
}
