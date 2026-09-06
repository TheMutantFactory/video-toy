extends Verb
## Boids with the others from this slot; hold click to attract, right-click
## empty space to scatter.

func _init() -> void:
	id = "flock"; panel = 9; name = "Flock"; key = "⇧Q"; shift = true; order = 30; sets_rotation = true
	hint = "boids with the others from this slot; hold click to attract, right-click empty space to scatter"

func has_motion2d() -> bool: return true
func has_motion3d() -> bool: return true

func move2d(a, delta: float) -> bool:
	var others: Array = []
	for o in a.get_parent().get_children():
		if o != a and is_instance_valid(o) and "slot_id" in o and o.slot_id == a.slot_id:
			others.append([o.position, o.velocity])
	var acc: Vector2 = Boids.steer2(a.position, a.velocity, others, a.mouse_world if a.attract else Vector2.INF, 1.5)
	if a.scatter_from != Vector2.INF:
		acc += (a.position - a.scatter_from).normalized() * Boids.MAX_FORCE * 6.0
		a.scatter_from = Vector2.INF
	a.velocity = (a.velocity + acc * delta).limit_length(Boids.MAX_SPEED)
	if a.velocity.length() < 40.0:
		a.velocity = Vector2.from_angle(randf() * TAU) * 120.0
	a.position += a.velocity * delta
	var b: Rect2 = a.bounds
	var margin := 80.0
	if a.position.x < b.position.x + margin: a.velocity.x += 600.0 * delta
	if a.position.x > b.end.x - margin: a.velocity.x -= 600.0 * delta
	if a.position.y < b.position.y + margin: a.velocity.y += 600.0 * delta
	if a.position.y > b.end.y - margin: a.velocity.y -= 600.0 * delta
	a.position = a.position.clamp(b.position, b.end)
	if not a.active_ids.has("spin"):
		a._sprite.rotation = a.velocity.angle() + PI * 0.5
	a.home = a.position
	return true

func move3d(s, delta: float) -> bool:
	var others: Array = []
	for o in s.get_parent().get_children():
		if o != s and is_instance_valid(o) and "slot_id" in o and o.slot_id == s.slot_id:
			others.append([o.position, o.velocity])
	var acc: Vector3 = Boids.steer3(s.position, s.velocity, others, s.mouse_point if s.attract else Vector3.INF, 1.5)
	s.velocity = (s.velocity + acc * delta).limit_length(Boids.MAX_SPEED * 0.01)
	if s.velocity.length() < 0.4:
		s.velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.5, 0.5)).normalized() * 1.2
	s.position += s.velocity * delta
	for axis in 3:
		if absf(s.position[axis]) > s.bounds[axis]:
			s.velocity[axis] -= signf(s.position[axis]) * 6.0 * delta
	s.position = s.position.clamp(-s.bounds, s.bounds)
	if s.velocity.length() > 0.01:
		s.look_at(s.position + s.velocity, Vector3.UP)
	s.home = s.position
	return true
