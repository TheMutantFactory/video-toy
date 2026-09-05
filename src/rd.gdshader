shader_type canvas_item;
render_mode blend_disabled;
// Gray-Scott reaction-diffusion, one step per pass, ping-ponged between two
// viewports. R = U, G = V. The world's alpha (icons) seeds V.
uniform sampler2D prev_tex : filter_linear, repeat_disable;
uniform sampler2D seed_tex : filter_linear, repeat_disable;
uniform float feed = 0.0545;
uniform float kill = 0.062;
uniform float seeding = 0.35;
uniform float dt = 1.0;
uniform vec2 texel = vec2(0.00208333, 0.00370370);   // 1/480, 1/270 (set by the stage)

vec2 uv_at(vec2 uv) {
	vec4 c = texture(prev_tex, uv);
	return c.a < 0.5 ? vec2(1.0, 0.0) : c.rg;        // never written: U=1, V=0
}

void fragment() {
	vec2 c = uv_at(UV);
	vec2 lap = -c
		+ 0.2 * (uv_at(UV + vec2(texel.x, 0.0)) + uv_at(UV - vec2(texel.x, 0.0)) + uv_at(UV + vec2(0.0, texel.y)) + uv_at(UV - vec2(0.0, texel.y)))
		+ 0.05 * (uv_at(UV + texel) + uv_at(UV - texel) + uv_at(UV + vec2(texel.x, -texel.y)) + uv_at(UV + vec2(-texel.x, texel.y)));
	float u = c.x, v = c.y;
	float uvv = u * v * v;
	float du = 1.0 * lap.x - uvv + feed * (1.0 - u);
	float dv = 0.5 * lap.y + uvv - (feed + kill) * v;
	u = clamp(u + du * dt, 0.0, 1.0);
	v = clamp(v + dv * dt, 0.0, 1.0);
	float s = texture(seed_tex, UV).a;
	v = max(v, s * seeding);
	COLOR = vec4(u, v, 0.0, 1.0);
}
