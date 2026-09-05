shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
// Quarter-circle truchet tiles; the grid slowly rotates and drifts.
void fragment() {
	float t = TIME * speed;
	vec2 p = scene_uv(UV) * 5.0;
	float a = t * 0.08;
	p = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * p + vec2(t * 0.15, 0.0);
	vec2 id = floor(p);
	vec2 f = fract(p);
	float flip = hash21(id + floor(t * 0.25) * 0.37);
	if (flip > 0.5) f.x = 1.0 - f.x;
	float d = min(abs(length(f) - 0.5), abs(length(f - 1.0) - 0.5));
	float line = 1.0 - smoothstep(0.06, 0.10, d);
	vec3 c = mix(bg_color(), ring_color(hash21(id) + bias + t * 0.02), line);
	COLOR = vec4(c, 1.0);
}
