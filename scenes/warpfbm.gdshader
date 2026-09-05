shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
// Domain-warped fbm: noise fed through itself twice.
void fragment() {
	vec2 p = scene_uv(UV) * 2.5;
	float t = TIME * speed * 0.15;
	vec2 q = vec2(fbm(p + t), fbm(p + vec2(5.2, 1.3) - t));
	vec2 r = vec2(fbm(p + 4.0 * q + vec2(1.7, 9.2) + t * 0.7), fbm(p + 4.0 * q + vec2(8.3, 2.8) - t * 0.4));
	float f = fbm(p + 4.0 * r);
	vec3 c = ring_color(f * 1.4 + bias);
	c = mix(bg_color(), c, smoothstep(0.15, 0.75, f + 0.15 * length(r)));
	COLOR = vec4(c, 1.0);
}
