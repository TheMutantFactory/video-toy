extends Verb
## Rides on top of whatever else moved the host: a small circle when it did,
## a full one around home when it did not.

func _init() -> void:
	id = "orbit"; panel = 2; name = "Orbit"; key = "W"; hint = "circle around spawn point"; order = 90

func has_motion2d() -> bool: return true
func has_motion3d() -> bool: return true

func move2d(a, delta: float) -> bool:
	a.angle += delta * 1.4
	a._orbit_off = Vector2.from_angle(a.angle) * (a.orbit_radius * (0.35 if a.moved else 1.0))
	a.position += a._orbit_off
	return false

func move3d(s, delta: float) -> bool:
	s.angle += delta * 1.1
	var r: float = s.orbit_radius * (0.35 if s.moved else 1.0)
	s._orbit_off = Vector3(cos(s.angle), sin(s.angle) * 0.6, sin(s.angle * 0.7) * 0.4) * r
	s.position += s._orbit_off
	return false

func formation(f, delta: float) -> void:
	f.angle += delta * 0.6
	f.position = Vector3(cos(f.angle), 0.0, sin(f.angle)) * 1.5
