shader_type canvas_item;
// Draws a shape from one or two signed distance fields (0.5 = edge, > 0.5
// inside). t mixes field A into field B; outline > 0 hollows the shape.
// The fragment COLOR input already has the (grey) field texture multiplied
// in, so the pure tint is carried from the vertex stage.
uniform sampler2D sdf_b : filter_linear, repeat_disable;
uniform float t = 0.0;
uniform float outline = 0.0;      // ring half-width in field units (0 = filled)

varying vec4 tint;

void vertex() {
	tint = COLOR;                 // the sprite's modulate
}

void fragment() {
	float a = texture(TEXTURE, UV).r;
	float b = texture(sdf_b, UV).r;
	float d = mix(a, b, t);
	float aa = max(fwidth(d) * 0.8, 0.004);
	float alpha;
	if (outline > 0.0) {
		alpha = 1.0 - smoothstep(outline - aa, outline + aa, abs(d - 0.5));
	} else {
		alpha = smoothstep(0.5 - aa, 0.5 + aa, d);
	}
	COLOR = vec4(tint.rgb, tint.a * alpha);
}
