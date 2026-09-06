extends Verb
## Glides between successive points of an iterated map.

func _init() -> void:
	id = "clifford"; panel = 12; name = "Clifford"; key = "⇧Y"; shift = true; hint = "fly between points of the Clifford map"
	order = 52; group = "attractor"

func has_motion2d() -> bool: return true
func has_motion3d() -> bool: return true

func step(p: Vector2) -> Vector2:
	return Attractors.clifford(p)

func move2d(a, delta: float) -> bool:
	a._map_t += delta * 3.4
	if a._map_t >= 1.0:
		a._map_t = 0.0
		a._map_from = a._map
		a._map = step(a._map)
	var from: Vector2 = Attractors.project_map(a._map_from, a._att_centre)
	var to: Vector2 = Attractors.project_map(a._map, a._att_centre)
	var target: Vector2 = from.lerp(to, smoothstep(0.0, 1.0, a._map_t))
	a.velocity = (target - a.position) / maxf(delta, 0.001)
	a.position = target
	a.home = a.position
	return true

func move3d(s, delta: float) -> bool:
	s._map_t += delta * 3.4
	if s._map_t >= 1.0:
		s._map_t = 0.0
		s._map_from = s._map
		s._map = step(s._map)
	var m: Vector2 = s._map_from.lerp(s._map, smoothstep(0.0, 1.0, s._map_t))
	s.position = Vector3(m.x * 1.6, m.y * 1.0, 0.0)
	s.home = s.position
	return true
