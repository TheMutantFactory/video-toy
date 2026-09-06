class_name Knot
## TonKnoT: torus-knot tubes that tie themselves. A (p, q) torus knot winds
## p times through the hole and q times around; a tube is swept along it
## with parallel-transport frames so the icon skin tiles along its length
## (the arrow-marked stick), and two knots blend point for point so one
## can deform into the next without a cross-dissolve. Pure; tested.

const FAMILIES := [[2, 3], [3, 4], [2, 5], [3, 5], [4, 5], [3, 7], [2, 7]]
const SEGMENTS := 200
const SIDES := 10
const R_MAJOR := 0.62
const R_MINOR := 0.28


## A point of the (p, q) torus knot at t in 0..1.
static func curve(p: int, q: int, t: float, big := R_MAJOR, small := R_MINOR) -> Vector3:
	var a := TAU * t
	var rr := big + small * cos(q * a)
	return Vector3(rr * cos(p * a), small * sin(q * a), rr * sin(p * a))


## `segments` points along a blend of two knots (m 0 = a, 1 = b), closed.
static func points(pa: int, qa: int, pb: int, qb: int, m: float, segments := SEGMENTS) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(segments)
	var k := clampf(m, 0.0, 1.0)
	for i in segments:
		var t := float(i) / segments
		out[i] = curve(pa, qa, t) if k <= 0.0 else (curve(pb, qb, t) if k >= 1.0 else curve(pa, qa, t).lerp(curve(pb, qb, t), k))
	return out


## Sweep a tube of `radius` along closed `pts` with parallel-transport frames.
## UV u runs along the tube (0..1 once), v around it.
static func tube(pts: PackedVector3Array, radius: float, sides := SIDES) -> ArrayMesh:
	var n := pts.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# frames: transport a normal along the tangents so the tube never twists
	var tangents: Array = []
	for i in n:
		tangents.append((pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized())
	var nrm: Vector3 = tangents[0].cross(Vector3.UP)
	if nrm.length() < 0.01:
		nrm = tangents[0].cross(Vector3.RIGHT)
	nrm = nrm.normalized()
	for i in n + 1:
		var ii := i % n
		var tg: Vector3 = tangents[ii]
		nrm = (nrm - tg * nrm.dot(tg)).normalized()
		var bn := tg.cross(nrm).normalized()
		for j in sides + 1:
			var ang := TAU * float(j) / sides
			var dir := nrm * cos(ang) + bn * sin(ang)
			verts.append(pts[ii] + dir * radius)
			normals.append(dir)
			uvs.append(Vector2(float(i) / n, float(j) / sides))
	for i in n:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func mesh_for(pa: int, qa: int, pb: int, qb: int, m: float, radius: float, segments := SEGMENTS, sides := SIDES) -> ArrayMesh:
	return tube(points(pa, qa, pb, qb, m, segments), radius, sides)


static func vertex_count(segments := SEGMENTS, sides := SIDES) -> int:
	return (segments + 1) * (sides + 1)


static func family_name(i: int) -> String:
	var f: Array = FAMILIES[posmod(i, FAMILIES.size())]
	return "(%d,%d)" % [f[0], f[1]]
