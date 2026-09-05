shader_type canvas_item;
// Bloom for the composite: bright pixels, blurred wide, added back. Sits after
// the world/feedback layer and before fx, so the CRT and pixelate see the glow.
//   glow       0 off, 1 soft, 2 heavy
//   threshold  luminance above which a pixel blooms

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float glow = 0.0;
uniform float threshold = 0.45;
uniform int taps = 16;             // quality ladder halves this

const int TAPS = 16;
const vec2 POISSON[16] = vec2[16](
	vec2(-0.94, 0.34), vec2(0.94, -0.26), vec2(-0.09, -0.93), vec2(0.34, 0.29),
	vec2(-0.91, -0.44), vec2(-0.82, 0.55), vec2(-0.38, -0.27), vec2(0.97, 0.16),
	vec2(0.44, -0.75), vec2(0.53, 0.77), vec2(-0.33, 0.83), vec2(0.09, 0.90),
	vec2(-0.53, -0.72), vec2(0.71, -0.54), vec2(-0.19, 0.47), vec2(0.20, -0.20));

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.30, 0.59, 0.11));
	return c * smoothstep(threshold, threshold + 0.25, l);
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	if (glow > 0.0) {
		float radius_px = 14.0 + 16.0 * glow;
		vec2 r = radius_px * SCREEN_PIXEL_SIZE;
		vec3 acc = vec3(0.0);
		int n = clamp(taps, 1, TAPS);
		for (int i = 0; i < TAPS; i++) {
			if (i >= n) break;
			acc += bright(SCREEN_UV + POISSON[i] * r);
			acc += bright(SCREEN_UV + POISSON[i] * r * 0.45);
		}
		acc /= float(n * 2);
		c += acc * (0.9 * glow);
	}
	COLOR = vec4(c, 1.0);
}
