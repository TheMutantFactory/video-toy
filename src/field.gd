class_name Field
## The flow field: curl of a value-noise potential, so it is divergence-free
## and things riding it swirl instead of piling up. The particle shader
## carries the same maths on the GPU (particles.gdshader); this is the CPU
## side for the Field verb and for tests.

const SCALE := 0.0018          # world px -> noise space
const SPEED := 0.15            # noise drift per second


static func hash21(p: Vector2) -> float:
	var q := Vector2(fmod(p.x * 123.34, 1.0), fmod(p.y * 456.21, 1.0))
	q = Vector2(absf(q.x), absf(q.y))
	var d := q.dot(q + Vector2(45.32, 45.32))
	q += Vector2(d, d)
	return fmod(absf(q.x * q.y), 1.0)


static func vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var a := hash21(i)
	var b := hash21(i + Vector2(1, 0))
	var c := hash21(i + Vector2(0, 1))
	var d := hash21(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


static func potential(p: Vector2, t: float) -> float:
	var q := p + Vector2(t, -t * 0.7)
	return vnoise(q) * 0.6 + vnoise(q * 2.03 + Vector2(1.7, 9.2)) * 0.3 + vnoise(q * 4.1 + Vector2(8.3, 2.8)) * 0.1


## Unit-ish curl vector at world position `p` (px), time `t` (s).
static func curl(p: Vector2, t: float) -> Vector2:
	var n := p * SCALE
	var tt := t * SPEED
	var e := 0.01
	var dx := (potential(n + Vector2(e, 0), tt) - potential(n - Vector2(e, 0), tt)) / (2.0 * e)
	var dy := (potential(n + Vector2(0, e), tt) - potential(n - Vector2(0, e), tt)) / (2.0 * e)
	return Vector2(dy, -dx)
