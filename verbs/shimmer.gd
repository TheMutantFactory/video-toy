extends Verb
## The thirty-colour flicker: a "gold" that is never one gold. Every frame
## the colour steps to one of about thirty shades close to the base, so the
## icon looks lit rather than painted. Composes with Rainbow (it shimmers
## whatever colour the earlier verbs left).

func _init() -> void:
	id = "shimmer"; panel = 19; name = "Shimmer"; key = "^H"; ctrl = true; order = 150
	hint = "never one fixed colour: thirty close shades, a new one every frame"


## Pure: one of ~30 shades near `base`, chosen by the frame's step.
static func shade(base: Color, t: float, rate := 30.0) -> Color:
	var step: float = floor(t * rate)
	var h1: float = fmod(sin(step * 12.9898) * 43758.5453, 1.0)
	var h2: float = fmod(sin(step * 78.233 + 1.7) * 43758.5453, 1.0)
	var c: Color = base
	c.h = fmod(c.h + (absf(h1) - 0.5) * 0.06 + 1.0, 1.0)
	c.v = clampf(c.v * (0.82 + absf(h2) * 0.36), 0.0, 1.0)
	c.s = clampf(c.s * (0.9 + absf(h1) * 0.2), 0.0, 1.0)
	return c


func post2d(a, _delta: float) -> void:
	var c: Color = shade(a._sprite.modulate, a.t)
	a._sprite.modulate = c
	a._particles.color = c


func post3d(s, _delta: float) -> void:
	s._apply_color(shade(s._skin_mat.albedo_color, s.t))
