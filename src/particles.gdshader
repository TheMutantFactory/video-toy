shader_type particles;
// The particle field: dots riding curl noise, pulled (or pushed) by up to 16
// attractors — the mouse and the icons. Same potential as field.gd.
uniform float flow = 1.0;              // field strength
uniform float attract = 0.5;           // -1 repel .. 1 attract
uniform int attractor_count = 0;
uniform vec4 attractors[16];           // x, y (px), strength, radius (px)
uniform vec2 bounds = vec2(1920.0, 1080.0);
uniform int palette_count = 0;
uniform vec4 palette[16];
uniform float dot_size = 3.0;

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
float potential(vec2 p, float t) {
	vec2 q = p + vec2(t, -t * 0.7);
	return vnoise(q) * 0.6 + vnoise(q * 2.03 + vec2(1.7, 9.2)) * 0.3 + vnoise(q * 4.1 + vec2(8.3, 2.8)) * 0.1;
}
vec2 curl(vec2 p, float t) {
	vec2 n = p * 0.0018;
	float tt = t * 0.15;
	float e = 0.01;
	float dx = (potential(n + vec2(e, 0.0), tt) - potential(n - vec2(e, 0.0), tt)) / (2.0 * e);
	float dy = (potential(n + vec2(0.0, e), tt) - potential(n - vec2(0.0, e), tt)) / (2.0 * e);
	return vec2(dy, -dx);
}
vec3 ring_color(float t) {
	int n = max(palette_count - 1, 1);
	float f = fract(t) * float(n);
	int i = int(floor(f));
	int j = (i + 1) % n;
	return mix(palette[i].rgb, palette[j].rgb, fract(f));
}

void start() {
	// keep the hash input small: fract() of a five-digit index times 123.34
	// quantises to a handful of values and stacks thousands of dots
	float k = float(INDEX) * 0.00037 + 0.11;
	float r1 = hash21(vec2(k, 1.7));
	float r2 = hash21(vec2(k * 1.37, 9.3));
	TRANSFORM[3].xy = vec2(r1, r2) * bounds;
	VELOCITY = vec3(0.0);
	CUSTOM.x = hash21(vec2(k * 0.71, 4.4));               // per-dot hue offset
	float s = dot_size * mix(0.6, 1.4, hash21(vec2(k * 2.3, 2.2)));
	TRANSFORM[0].xyz = vec3(s, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, s, 0.0);
}

void process() {
	vec2 p = TRANSFORM[3].xy;
	vec2 force = curl(p, TIME) * 260.0 * flow;
	for (int i = 0; i < 16; i++) {
		if (i >= attractor_count) break;
		vec2 d = attractors[i].xy - p;
		float dist = length(d);
		float r = attractors[i].w;
		float w = attractors[i].z * attract * smoothstep(r, r * 0.15, dist);
		force += (d / max(dist, 1.0)) * w * 900.0;
	}
	VELOCITY.xy = mix(VELOCITY.xy, force, min(1.0, DELTA * 3.0));
	p += VELOCITY.xy * DELTA;
	p = mod(p + bounds, bounds);                               // wrap
	TRANSFORM[3].xy = p;
	float speed = length(VELOCITY.xy);
	COLOR = vec4(ring_color(CUSTOM.x + speed * 0.0008), clamp(0.7 + speed * 0.002, 0.7, 1.0));
}
