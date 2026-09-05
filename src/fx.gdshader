shader_type canvas_item;
// Post-process for the stage. Drawn as a full-screen ColorRect above the world
// and below the HUD, sampling whatever was rendered underneath it.
//
// Order: CRT curvature (remap uv, outermost) -> kaleidoscope (remap uv) ->
// pixelate (snap uv) -> sample -> chroma key (swap keyed pixels for the
// backdrop) -> palette quantise (+dither) -> CRT display (aberration, scanlines,
// mask, vignette). The CRT samples the inner chain three times, one per channel.
//
//   crt               0 = off, 1 = soft, 2 = heavy (scales every CRT term)
//   kaleido_segments  0 = off, else mirrored wedges around the centre
//   kaleido_drift     radians/second the wedge pattern rotates
//   pixel_size        0 = off, else block size in screen pixels
//   key_mode          0 off, 1 chroma (key_color), 2 luma (dark), 3 difference
//                     (vs the previous frame: static parts keyed), 4 edge
//                     (non-edges keyed); keyed pixels show the backdrop
//   slit_mode         0 off, 1 rows, 2 columns, 3 radial: sample from the
//                     history atlas (slit_tex, slit_cols x slit_rows slots)
//   backdrop_tex      dropped image; when !has_backdrop a palette plasma is drawn
//   quantize / dither snap to the nearest palette colour, optional 4x4 Bayer
//   palette[]         the active Palettes ring + background, palette_count entries

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform float crt = 0.0;
uniform int kaleido_segments = 0;
uniform float kaleido_drift = 0.12;
uniform float pixel_size = 0.0;
uniform int key_mode = 0;
uniform float key_threshold = 0.35;
uniform sampler2D prev_tex : filter_linear, repeat_disable;
uniform int slit_mode = 0;
uniform sampler2D slit_tex : filter_linear, repeat_disable;
uniform int slit_cols = 6;
uniform int slit_rows = 6;
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

// Slit-scan: which history slot a uv reads from, and where that slot lives.
vec3 sample_source(vec2 uv) {
	if (slit_mode == 0) return texture(screen_tex, uv).rgb;
	float t;
	if (slit_mode == 1) t = uv.y;
	else if (slit_mode == 2) t = uv.x;
	else t = clamp(length((uv - 0.5) * vec2(1.78, 1.0)) * 1.1, 0.0, 0.999);
	int slots = slit_cols * slit_rows;
	int slot = clamp(int(t * float(slots)), 0, slots - 1);
	vec2 cell = vec2(float(slot % slit_cols), float(slot / slit_cols));
	vec2 suv = (cell + uv) / vec2(float(slit_cols), float(slit_rows));
	return texture(slit_tex, suv).rgb;
}

float lum_at(vec2 uv) {
	return dot(sample_source(clamp(uv, vec2(0.0), vec2(1.0))), vec3(0.30, 0.59, 0.11));
}

// Everything between the CRT lens and the CRT display: takes a screen-pixel
// position, returns the processed colour there.
vec3 chain(vec2 frag, vec2 screen_px) {
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
	vec3 c = sample_source(uv);

	if (key_mode > 0) {
		float k = 0.0;
		if (key_mode == 1) {
			float dist = distance(c, key_color.rgb);
			k = 1.0 - smoothstep(key_tolerance, key_tolerance + key_softness, dist);
		} else if (key_mode == 2) {
			float l = dot(c, vec3(0.30, 0.59, 0.11));
			k = 1.0 - smoothstep(key_threshold, key_threshold + key_softness, l);
		} else if (key_mode == 3) {
			vec4 p = texture(prev_tex, uv);
			vec3 prev = mix(key_color.rgb, p.rgb, p.a);
			k = 1.0 - smoothstep(key_threshold * 0.5, key_threshold * 0.5 + key_softness, distance(c, prev));
		} else {
			vec2 px = 1.5 / screen_px;
			float tl = lum_at(uv + vec2(-px.x, -px.y)), t = lum_at(uv + vec2(0.0, -px.y)), tr = lum_at(uv + vec2(px.x, -px.y));
			float l = lum_at(uv + vec2(-px.x, 0.0)), r = lum_at(uv + vec2(px.x, 0.0));
			float bl = lum_at(uv + vec2(-px.x, px.y)), b = lum_at(uv + vec2(0.0, px.y)), br = lum_at(uv + vec2(px.x, px.y));
			float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
			float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
			float edge = length(vec2(gx, gy));
			k = 1.0 - smoothstep(key_threshold * 0.6, key_threshold * 0.6 + key_softness, edge);
		}
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
	return c;
}

void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 frag = SCREEN_UV * screen_px;

	if (crt <= 0.0) {
		COLOR = vec4(chain(frag, screen_px), 1.0);
	} else {
		// --- lens: barrel curvature around the centre, in normalised coords
		vec2 cc = SCREEN_UV - 0.5;
		float d2 = dot(cc, cc);
		float curvature = 0.10 * crt;
		vec2 uv = SCREEN_UV + cc * d2 * curvature * 2.0;
		// rounded-rectangle tube edge: black outside, soft falloff inside
		vec2 edge = abs(uv - 0.5) * 2.0;                       // 0 centre .. 1 edge
		vec2 corner = max(edge - (1.0 - 0.06 * crt), 0.0);
		float outside = length(corner) / (0.06 * crt + 1e-4);
		float tube = 1.0 - smoothstep(0.85, 1.0, outside);
		bool off_screen = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;

		// --- chromatic aberration: sample the chain per channel, offset radially
		vec2 dir = cc * (0.0025 * crt);
		vec2 f = uv * screen_px;
		vec2 fr = clamp(f + dir * screen_px, vec2(0.0), screen_px - 1.0);
		vec2 fb = clamp(f - dir * screen_px, vec2(0.0), screen_px - 1.0);
		vec3 c;
		c.r = chain(fr, screen_px).r;
		c.g = chain(clamp(f, vec2(0.0), screen_px - 1.0), screen_px).g;
		c.b = chain(fb, screen_px).b;

		// --- scanlines (3 px period) and aperture mask (RGB stripes)
		float scan = 0.5 + 0.5 * cos(f.y * TAU / 3.0);
		c *= 1.0 - (0.18 * crt) * scan;
		int col = int(mod(f.x, 3.0));
		vec3 mask = vec3(col == 0 ? 1.0 : 0.0, col == 1 ? 1.0 : 0.0, col == 2 ? 1.0 : 0.0);
		c *= mix(vec3(1.0), mask * 1.6 + 0.4, 0.12 * crt);

		// --- rolling bar, flicker, vignette
		float bar = smoothstep(0.0, 0.08, 1.0 - abs(fract(uv.y - TIME * 0.08) * 2.0 - 1.0));
		c += bar * 0.025 * crt;
		c *= 1.0 + 0.012 * crt * sin(TIME * 110.0);
		c *= 1.0 - (0.35 * crt) * d2 * 2.0;
		c *= off_screen ? 0.0 : tube;
		COLOR = vec4(c, 1.0);
	}
}
