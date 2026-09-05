class_name Attractors
## Strange attractors as motion: two continuous systems integrated with RK-ish
## substeps, two iterated maps. Pure functions; actor.gd and solid.gd project
## the state onto the stage.


## Lorenz (sigma 10, rho 28, beta 8/3). State roughly x,y in [-25,25], z in [0,50].
static func lorenz_step(p: Vector3, dt: float, sigma := 10.0, rho := 28.0, beta := 8.0 / 3.0) -> Vector3:
	var steps := maxi(1, int(ceil(dt / 0.004)))
	var h := dt / steps
	for i in steps:
		var d := Vector3(sigma * (p.y - p.x), p.x * (rho - p.z) - p.y, p.x * p.y - beta * p.z)
		p += d * h
	return p


## Rössler (a 0.2, b 0.2, c 5.7). x,y in [-12,12], z mostly small with spikes.
static func rossler_step(p: Vector3, dt: float, a := 0.2, b := 0.2, c := 5.7) -> Vector3:
	var steps := maxi(1, int(ceil(dt / 0.01)))
	var h := dt / steps
	for i in steps:
		var d := Vector3(-p.y - p.z, p.x + a * p.y, b + p.z * (p.x - c))
		p += d * h
	return p


## Clifford map. Output in [-|c|-1, |c|+1] x [-|d|-1, |d|+1], typically [-2, 2].
static func clifford(p: Vector2, a := -1.4, b := 1.6, c := 1.0, d := 0.7) -> Vector2:
	return Vector2(sin(a * p.y) + c * cos(a * p.x), sin(b * p.x) + d * cos(b * p.y))


## Peter de Jong map. Output in [-2, 2].
static func dejong(p: Vector2, a := 1.4, b := -2.3, c := 2.4, d := -2.1) -> Vector2:
	return Vector2(sin(a * p.y) - cos(b * p.x), sin(c * p.x) - cos(d * p.y))


## Screen-space projection of a continuous state around `centre`.
static func project_lorenz(p: Vector3, centre: Vector2, scale := 18.0) -> Vector2:
	return centre + Vector2(p.x * scale, -(p.z - 25.0) * scale * 0.7)


static func project_rossler(p: Vector3, centre: Vector2, scale := 30.0) -> Vector2:
	return centre + Vector2(p.x * scale, -p.y * scale)


static func project_map(p: Vector2, centre: Vector2, scale := 220.0) -> Vector2:
	return centre + Vector2(p.x * scale, -p.y * scale)
