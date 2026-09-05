shader_type canvas_item;
// Post-process for the stage. Drawn as a full-screen ColorRect above the world
// and below the HUD, sampling whatever was rendered underneath it.
//
// Order: kaleidoscope (remap uv) -> pixelate (snap uv) -> sample -> chroma key
// (swap keyed pixels for the backdrop) -> palette quantise (+dither).
//
//   kaleido_segments  0 = off, else mirrored wedges around the centre
//   kaleido_drift     radians/second the wedge pattern rotates
//   pixel_size        0 = off, else block size in screen pixels
//   chroma            key out `key_color` (± key_tolerance) and show the backdrop
//   backdrop_tex      dropped image; when !has_backdrop a palette plasma is drawn
//   quantize / dither snap to the nearest palette colour, optional 4x4 Bayer
//   palette[]         the active Palettes ring + background, palette_count entries

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform int kaleido_segments = 0;
uniform float kaleido_drift = 0.12;
uniform float pixel_size = 0.0;
uniform bool chroma = false;
uniform vec4 key_color : source_color = vec4(0.0, 1.0, 0.0, 1.0);
uniform float key_tolerance = 0.18;
uniform float key_softness = 0.10;
uniform bool has_backdrop = false;
uniform sampler2D backdrop_tex : filter_linear, repeat_disable;
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
	const vec3 w = vec3(0.30, 0.59, 0.11);   // perceptual-ish weights
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

// Smoothly blend through the palette ring (excluding the background, which is
// the last entry) so the plasma is always "on brand".
vec3 ring_color(float t) {
	int n = max(palette_count - 1, 1);
	float f = fract(t) * float(n);
	int i = int(floor(f));
	int j = (i + 1) % n;
	return mix(palette[i].rgb, palette[j].rgb, smoothstep(0.0, 1.0, fract(f)));
}

vec3 plasma(vec2 uv, float t) {
	vec2 p = uv * vec2(1.78, 1.0) * 3.0;
	float v = sin(p.x + t)
		+ sin(p.y * 1.3 + t * 0.7)
		+ sin((p.x + p.y) * 0.8 + t * 1.1)
		+ sin(length(p - vec2(2.7, 1.5)) * 1.5 - t * 0.9);
	return ring_color(v * 0.125 + t * 0.03);
}

void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 frag = SCREEN_UV * screen_px;

	if (kaleido_segments > 0) {
		vec2 centre = screen_px * 0.5;
		vec2 d = frag - centre;
		float r = length(d);
		float wedge = TAU / float(kaleido_segments);
		float a = atan(d.y, d.x) - TIME * kaleido_drift;
		a = mod(a, wedge);
		if (a > wedge * 0.5) a = wedge - a;      // mirror every other wedge
		a += TIME * kaleido_drift * 0.5;         // and let the source drift too
		frag = centre + vec2(cos(a), sin(a)) * r;
		frag = clamp(frag, vec2(0.0), screen_px - 1.0);
	}
	if (pixel_size > 0.5) {
		frag = (floor(frag / pixel_size) + 0.5) * pixel_size;
	}
	vec2 uv = frag / screen_px;
	vec3 c = texture(screen_tex, uv).rgb;

	if (chroma) {
		float dist = distance(c, key_color.rgb);
		float k = 1.0 - smoothstep(key_tolerance, key_tolerance + key_softness, dist);
		vec3 back = has_backdrop ? texture(backdrop_tex, uv).rgb : plasma(uv, TIME);
		c = mix(c, back, k);
	}
	if (quantize && palette_count > 0) {
		if (dither) {
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
