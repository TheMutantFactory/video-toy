extends Verb

func _init() -> void:
	id = "bounce"; panel = 4; name = "Bounce"; key = "R"; hint = "DVD-logo off the walls"; order = 10

func has_motion2d() -> bool: return true
func has_motion3d() -> bool: return true

func move2d(a, delta: float) -> bool:
	a.position += a.velocity * delta
	var half: Vector2 = a._sprite.texture.get_size() * a._sprite.scale * 0.5 if a._sprite.texture else Vector2(40, 40)
	var b: Rect2 = a.bounds
	if a.position.x - half.x < b.position.x or a.position.x + half.x > b.end.x:
		a.velocity.x = -a.velocity.x
		a.position.x = clampf(a.position.x, b.position.x + half.x, b.end.x - half.x)
	if a.position.y - half.y < b.position.y or a.position.y + half.y > b.end.y:
		a.velocity.y = -a.velocity.y
		a.position.y = clampf(a.position.y, b.position.y + half.y, b.end.y - half.y)
	a.home = a.position
	return true

func move3d(s, delta: float) -> bool:
	s.position += s.velocity * delta
	for axis in 3:
		if absf(s.position[axis]) > s.bounds[axis]:
			s.velocity[axis] = -s.velocity[axis]
			s.position[axis] = clampf(s.position[axis], -s.bounds[axis], s.bounds[axis])
	s.home = s.position
	return true
