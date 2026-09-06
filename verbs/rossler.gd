extends Verb

func _init() -> void:
	id = "rossler"; panel = 11; name = "Rössler"; key = "⇧T"; shift = true; hint = "ride the Rössler spiral"
	order = 51; group = "attractor"; sets_rotation = true

func has_motion2d() -> bool: return true
func has_motion3d() -> bool: return true

func move2d(a, delta: float) -> bool:
	a._att = Attractors.rossler_step(a._att, delta * 1.6)
	var target: Vector2 = Attractors.project_rossler(a._att, a._att_centre)
	a.velocity = (target - a.position) / maxf(delta, 0.001)
	a.position = target
	if not a.active_ids.has("spin"):
		a._sprite.rotation = a.velocity.angle() + PI * 0.5
	a.home = a.position
	return true

func move3d(s, delta: float) -> bool:
	s._att = Attractors.rossler_step(s._att, delta * 1.6)
	s.position = Vector3(s._att.x * 0.25, s._att.z * 0.12 - 1.0, s._att.y * 0.25)
	s.home = s.position
	return true
