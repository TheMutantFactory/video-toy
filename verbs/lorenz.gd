extends Verb

func _init() -> void:
	id = "lorenz"; panel = 10; name = "Lorenz"; key = "⇧W"; shift = true; hint = "ride the Lorenz butterfly"
	order = 50; group = "attractor"; sets_rotation = true

func has_motion2d() -> bool: return true
func has_motion3d() -> bool: return true

func move2d(a, delta: float) -> bool:
	a._att = Attractors.lorenz_step(a._att, delta * 0.9)
	var target: Vector2 = Attractors.project_lorenz(a._att, a._att_centre)
	a.velocity = (target - a.position) / maxf(delta, 0.001)
	a.position = target
	if not a.active_ids.has("spin"):
		a._sprite.rotation = a.velocity.angle() + PI * 0.5
	a.home = a.position
	return true

func move3d(s, delta: float) -> bool:
	s._att = Attractors.lorenz_step(s._att, delta * 0.9)
	s.position = Vector3(s._att.x * 0.13, (s._att.z - 25.0) * 0.08, s._att.y * 0.09)
	s.home = s.position
	return true
