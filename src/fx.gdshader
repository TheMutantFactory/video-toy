shader_type canvas_item;
// Post-process for the stage. Drawn as a full-screen ColorRect above the world
// and below the HUD, sampling whatever was rendered underneath it.
//
//   pixel_size   0 = off, else block size in screen pixels
//   quantize     snap every pixel to the nearest palette colour
//   dither       ordered 4x4 Bayer before quantising (needs quantize)
//   palette[]    the active Palettes ring + background, palette_count entries

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform float pixel_size = 0.0;
uniform bool quantize = false;
uniform bool dither = false;
uniform float dither_strength = 0.12;
uniform int palette_count = 0;
uniform vec4 palette[16];

const float BAYER[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0);

vec3 nearest_palette(vec3 c) {
	vec3 best = c;
	float best_d = 1e9;
	// Perceptual-ish weights so green differences count more than blue.
	const vec3 w = vec3(0.30, 0.59, 0.11);
	for (int i = 0; i < 16; i++) {
		if (i >= palette_count) break;
		vec3 d = (c - palette[i].rgb) * w;
		float dist = dot(d, d);
		if (dist < best_d) {
			best_d = dist;
			best = palette[i].rgb;
		}
	}
	return best;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 frag = uv * screen_px;
	if (pixel_size > 0.5) {
		frag = (floor(frag / pixel_size) + 0.5) * pixel_size;
		uv = frag / screen_px;
	}
	vec3 c = texture(screen_tex, uv).rgb;
	if (quantize && palette_count > 0) {
		if (dither) {
			// Threshold on the block grid when pixelated, else on real pixels.
			vec2 cell = pixel_size > 0.5 ? floor(frag / pixel_size) : floor(frag);
			int ix = int(mod(cell.x, 4.0));
			int iy = int(mod(cell.y, 4.0));
			float t = (BAYER[iy * 4 + ix] + 0.5) / 16.0 - 0.5;
			c += t * dither_strength;
		}
		c = nearest_palette(clamp(c, 0.0, 1.0));
	}
	COLOR = vec4(c, 1.0);
}
