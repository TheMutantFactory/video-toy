extends Verb

func _init() -> void:
	id = "rainbow"; panel = 7; name = "Rainbow"; key = "U"; hint = "cycle the hue"

static func shifted(base: Color, t: float) -> Color:
	var c := base
	c.h = fmod(c.h + t * 0.25, 1.0)
	c.s = maxf(c.s, 0.7)
	return c

func post2d(a, _delta: float) -> void:
	var c := shifted(a._base_color, a.t)
	a._sprite.modulate = c
	a._particles.color = c
	a._burst.color = c

func post3d(s, _delta: float) -> void:
	s._apply_color(shifted(s._base_color, s.t))

func formation(f, _delta: float) -> void:
	f.recolor(f._pal, f._color_index, fmod(f.t * 0.25, 1.0))
