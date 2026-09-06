extends Verb
## Rides the curl-noise flow field (the same one the particles ride).

func _init() -> void:
	id = "field"; panel = 14; name = "Field"; key = "⇧I"; shift = true; order = 40; sets_rotation = true
	hint = "ride the curl-noise flow field (the same one the particles ride)"

func has_motion2d() -> bool: return true

func move2d(a, delta: float) -> bool:
	var f: Vector2 = Field.curl(a.position, a.t) * 240.0
	a.velocity = a.velocity.lerp(f, minf(1.0, delta * 3.0))
	a.position += a.velocity * delta
	a.position = Vector2(fposmod(a.position.x, a.bounds.size.x), fposmod(a.position.y, a.bounds.size.y))
	if not a.active_ids.has("spin"):
		a._sprite.rotation = a.velocity.angle() + PI * 0.5
	a.home = a.position
	return true
