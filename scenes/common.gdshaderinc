// Shared by every scene shader: the palette ring, the three learnable knobs,
// and small noise helpers. Included with #include "res://scenes/common.gdshaderinc".
uniform int palette_count = 0;
uniform vec4 palette[16];
uniform float speed = 1.0;      // 0.1 .. 4
uniform float scale = 1.0;      // 0.3 .. 4
uniform float bias = 0.0;       // 0 .. 1, slides colours around the ring

vec3 ring_color(float t) {
	int n = max(palette_count - 1, 1);          // last entry is the background
	float f = fract(t) * float(n);
	int i = int(floor(f));
	int j = (i + 1) % n;
	return mix(palette[i].rgb, palette[j].rgb, smoothstep(0.0, 1.0, fract(f)));
}

vec3 bg_color() {
	return palette_count > 0 ? palette[max(palette_count - 1, 0)].rgb : vec3(0.0);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i), b = hash21(i + vec2(1, 0)), c = hash21(i + vec2(0, 1)), d = hash21(i + vec2(1, 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// 16:9-corrected coordinates centred on the screen, scaled by `scale`.
vec2 scene_uv(vec2 uv) {
	return (uv - 0.5) * vec2(1.7778, 1.0) * scale;
}
