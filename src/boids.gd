class_name Boids
## Flocking (Reynolds): separation, alignment, cohesion, plus an optional
## attractor. Pure functions in 2D and 3D; actor.gd and solid.gd call them.
## `others` is an Array of [position, velocity] pairs for flock-mates.

const NEIGHBOUR := 220.0
const SEPARATION := 70.0
const MAX_SPEED := 340.0
const MAX_FORCE := 900.0


static func steer2(pos: Vector2, vel: Vector2, others: Array, attract: Vector2 = Vector2.INF, attract_weight := 1.0) -> Vector2:
	var sep := Vector2.ZERO
	var ali := Vector2.ZERO
	var coh := Vector2.ZERO
	var n := 0
	for o in others:
		var op: Vector2 = o[0]
		var d := pos.distance_to(op)
		if d <= 0.001 or d > NEIGHBOUR:
			continue
		n += 1
		ali += o[1]
		coh += op
		if d < SEPARATION:
			sep += (pos - op) / d * (SEPARATION - d) / SEPARATION
	var acc := Vector2.ZERO
	if n > 0:
		ali = (ali / n).limit_length(MAX_SPEED) - vel
		coh = ((coh / n) - pos).limit_length(MAX_SPEED) - vel
		acc += sep * 3.0 * MAX_FORCE / SEPARATION + ali.limit_length(MAX_FORCE) * 0.8 + coh.limit_length(MAX_FORCE) * 0.6
	if attract != Vector2.INF:
		acc += ((attract - pos).limit_length(MAX_SPEED) - vel).limit_length(MAX_FORCE) * attract_weight
	return acc.limit_length(MAX_FORCE * 2.0)


static func steer3(pos: Vector3, vel: Vector3, others: Array, attract: Vector3 = Vector3.INF, attract_weight := 1.0, scale := 0.01) -> Vector3:
	# The 3D world is ~100x smaller than the 2D one; `scale` converts the radii.
	var neigh := NEIGHBOUR * scale
	var sepr := SEPARATION * scale
	var max_speed := MAX_SPEED * scale
	var max_force := MAX_FORCE * scale
	var sep := Vector3.ZERO
	var ali := Vector3.ZERO
	var coh := Vector3.ZERO
	var n := 0
	for o in others:
		var op: Vector3 = o[0]
		var d := pos.distance_to(op)
		if d <= 0.0001 or d > neigh:
			continue
		n += 1
		ali += o[1]
		coh += op
		if d < sepr:
			sep += (pos - op) / d * (sepr - d) / sepr
	var acc := Vector3.ZERO
	if n > 0:
		ali = (ali / n).limit_length(max_speed) - vel
		coh = ((coh / n) - pos).limit_length(max_speed) - vel
		acc += sep * 3.0 * max_force / sepr + ali.limit_length(max_force) * 0.8 + coh.limit_length(max_force) * 0.6
	if attract != Vector3.INF:
		acc += ((attract - pos).limit_length(max_speed) - vel).limit_length(max_force) * attract_weight
	return acc.limit_length(max_force * 2.0)
