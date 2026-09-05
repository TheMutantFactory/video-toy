shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
// Cellular noise: each cell wears a ring colour, edges darken.
void fragment() {
	float t = TIME * speed * 0.3;
	vec2 p = scene_uv(UV) * 4.0;
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0, d2 = 8.0;
	vec2 best = vec2(0.0);
	for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
		vec2 g = vec2(float(x), float(y));
		vec2 o = vec2(hash21(i + g), hash21(i + g + 7.7));
		o = 0.5 + 0.45 * sin(t + 6.2831 * o);
		float d = length(g + o - f);
		if (d < d1) { d2 = d1; d1 = d; best = i + g; }
		else if (d < d2) { d2 = d; }
	}
	float edge = smoothstep(0.0, 0.08, d2 - d1);
	vec3 c = ring_color(hash21(best) + bias) * (0.55 + 0.45 * (1.0 - d1));
	c = mix(bg_color(), c, edge);
	COLOR = vec4(c, 1.0);
}
