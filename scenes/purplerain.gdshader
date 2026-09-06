shader_type canvas_item;
#include "res://scenes/common.gdshaderinc"
// Purple static: tiny lights raining through the scene in three depths,
// ignoring what they cross, with bursts of static now and then.
void fragment() {
	vec2 uv = scene_uv(UV);
	vec3 col = bg_color() * 0.6;
	for (int l = 0; l < 3; l++) {
		float layer = float(l);
		vec2 p = uv * (18.0 + layer * 10.0) * scale;
		p.y += TIME * speed * (1.5 + layer * 0.8);
		vec2 cell = floor(p);
		vec2 f = fract(p);
		float h = hash21(cell + layer * 7.1);
		vec2 c = vec2(hash21(cell * 1.3 + 2.0), hash21(cell * 0.7 + 5.0));
		float d = length(f - c);
		float on = step(0.82 - bias * 0.3, h);
		float spark = smoothstep(0.09, 0.0, d) * on;
		vec3 tint = mix(vec3(0.55, 0.2, 1.0), vec3(0.9, 0.6, 1.0), hash21(cell + 9.0));
		col += spark * tint * (0.6 + 0.4 * sin(TIME * 20.0 * h)) * (1.0 - layer * 0.25);
	}
	float st = step(0.975, hash21(floor(uv * 90.0) + floor(TIME * 24.0 * speed)));
	col += st * vec3(0.5, 0.3, 0.8) * 0.45;
	COLOR = vec4(col, 1.0);
}
