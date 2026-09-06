shader_type canvas_item;
// ASCII mode: the picture as a grid of glyphs picked by luminance. Runs last
// in the composite (after fx), reading the screen underneath.
//   mode     0 off, 1 mono (accent glyphs on the background), 2 colour (glyphs
//            take the cell's own colour)
//   glyphs   an atlas of `count` glyphs side by side, each cell_w x cell_h px,
//            dark to bright
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D glyphs : filter_nearest, repeat_disable;
uniform int mode = 0;
uniform int count = 10;
uniform vec2 cell = vec2(12.0, 20.0);
uniform vec4 accent : source_color = vec4(0.9, 0.9, 0.95, 1.0);
uniform vec4 bg : source_color = vec4(0.04, 0.04, 0.06, 1.0);

void fragment() {
	vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 frag = SCREEN_UV * screen_px;
	vec2 idx = floor(frag / cell);
	vec2 centre = (idx + 0.5) * cell / screen_px;
	// average a small cross around the centre so thin shapes still register
	vec2 d = cell * 0.25 / screen_px;
	vec3 c = texture(screen_tex, centre).rgb * 0.4
		+ texture(screen_tex, centre + vec2(d.x, 0.0)).rgb * 0.15 + texture(screen_tex, centre - vec2(d.x, 0.0)).rgb * 0.15
		+ texture(screen_tex, centre + vec2(0.0, d.y)).rgb * 0.15 + texture(screen_tex, centre - vec2(0.0, d.y)).rgb * 0.15;
	float lum = dot(c, vec3(0.30, 0.59, 0.11));
	int g = int(clamp(floor(lum * float(count)), 0.0, float(count - 1)));
	vec2 inner = fract(frag / cell);
	vec2 guv = vec2((float(g) + inner.x) / float(count), inner.y);
	float a = texture(glyphs, guv).a;
	vec3 ink = mode == 2 ? max(c, vec3(0.15)) * 1.2 : accent.rgb;
	COLOR = vec4(mix(bg.rgb, ink, a), 1.0);
}
