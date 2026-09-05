shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
// Metaballs: the field is banded through the palette.
void fragment() {
	float t = TIME * speed * 0.6;
	vec2 p = scene_uv(UV);
	float field = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		vec2 c = vec2(sin(t * (0.5 + fi * 0.13) + fi * 1.7), cos(t * (0.4 + fi * 0.11) + fi * 2.3)) * vec2(0.7, 0.4);
		float r = 0.12 + 0.05 * sin(t + fi);
		field += r * r / max(dot(p - c, p - c), 1e-4);
	}
	float band = smoothstep(0.9, 1.1, field);
	vec3 c = ring_color(field * 0.15 + bias + t * 0.02);
	c = mix(bg_color(), c, band);
	c += 0.25 * ring_color(bias + 0.5) * smoothstep(0.95, 1.05, field) * (1.0 - smoothstep(1.05, 1.5, field));
	COLOR = vec4(c, 1.0);
}
