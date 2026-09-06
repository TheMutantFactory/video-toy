extends Verb

func _init() -> void:
	id = "swarm"; panel = 8; name = "Swarm"; key = "I"; hint = "chase the mouse"; order = 60

func has_motion2d() -> bool: return true
func has_motion3d() -> bool: return true

func move2d(a, delta: float) -> bool:
	var to_mouse: Vector2 = a.mouse_world - a.position
	a.velocity = a.velocity.lerp(to_mouse.normalized() * 380.0, 2.0 * delta)
	a.position += a.velocity * delta
	a.home = a.position
	return true

func move3d(s, delta: float) -> bool:
	s.velocity = s.velocity.lerp((s.mouse_point - s.position).normalized() * 3.0, 2.0 * delta)
	s.position += s.velocity * delta
	s.home = s.position
	return true
