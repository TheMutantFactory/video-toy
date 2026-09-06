extends Verb

func _init() -> void:
	id = "wander"; panel = 1; name = "Wander"; key = "Q"; hint = "random motion"; order = 20

func has_motion2d() -> bool: return true
func has_motion3d() -> bool: return true

func move2d(a, delta: float) -> bool:
	if a.position.distance_to(a.wander_target) < 12.0:
		a.wander_target = a._random_point()
	a.position = a.position.move_toward(a.wander_target, 160.0 * delta)
	a.home = a.position
	return true

func move3d(s, delta: float) -> bool:
	if s.position.distance_to(s.wander_target) < 0.15:
		s.wander_target = s._random_point()
	s.position = s.position.move_toward(s.wander_target, 1.2 * delta)
	s.home = s.position
	return true
