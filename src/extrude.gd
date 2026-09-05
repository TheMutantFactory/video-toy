class_name Extrude
## An icon as a solid: the alpha channel sampled on a grid becomes a slab of
## columns. Front and back faces carry the icon texture (so the silhouette is
## the smooth icon, not the grid), side faces are plain and take the body
## colour. Holes survive because empty cells simply emit nothing.
##
## Surface 0 = front/back (skin material), surface 1 = sides (body material).

const RES := 56


static func opaque_cells(img: Image, res := RES) -> Array:
	## Bool grid [y][x] of cells whose centre alpha > 0.5.
	var w := img.get_width()
	var h := img.get_height()
	var grid: Array = []
	for y in res:
		var row: Array = []
		for x in res:
			var px := int((x + 0.5) / res * w)
			var py := int((y + 0.5) / res * h)
			row.append(img.get_pixel(clampi(px, 0, w - 1), clampi(py, 0, h - 1)).a > 0.5)
		grid.append(row)
	return grid


static func count_cells(grid: Array) -> int:
	var n := 0
	for row in grid:
		for c in row:
			if c:
				n += 1
	return n


static func build(img: Image, size := 1.4, depth := 0.35, res := RES) -> ArrayMesh:
	var grid := opaque_cells(img, res)
	var cell := size / res
	var half := size * 0.5
	var hd := depth * 0.5
	var faces := SurfaceTool.new()
	faces.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)

	for y in res:
		for x in res:
			if not grid[y][x]:
				continue
			var x0 := -half + x * cell
			var x1 := x0 + cell
			var y0 := half - y * cell             # image y down -> world y up
			var y1 := y0 - cell
			var u0 := float(x) / res
			var u1 := float(x + 1) / res
			var v0 := float(y) / res
			var v1 := float(y + 1) / res
			# front (+z)
			_quad(faces, Vector3(x0, y0, hd), Vector3(x1, y0, hd), Vector3(x1, y1, hd), Vector3(x0, y1, hd),
				Vector3(0, 0, 1), [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
			# back (-z), mirrored so the icon reads correctly from behind too
			_quad(faces, Vector3(x1, y0, -hd), Vector3(x0, y0, -hd), Vector3(x0, y1, -hd), Vector3(x1, y1, -hd),
				Vector3(0, 0, -1), [Vector2(u1, v0), Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1)])
			# sides only where the neighbour is empty
			if x == 0 or not grid[y][x - 1]:
				_quad(sides, Vector3(x0, y0, -hd), Vector3(x0, y0, hd), Vector3(x0, y1, hd), Vector3(x0, y1, -hd), Vector3(-1, 0, 0), [])
			if x == res - 1 or not grid[y][x + 1]:
				_quad(sides, Vector3(x1, y0, hd), Vector3(x1, y0, -hd), Vector3(x1, y1, -hd), Vector3(x1, y1, hd), Vector3(1, 0, 0), [])
			if y == 0 or not grid[y - 1][x]:
				_quad(sides, Vector3(x0, y0, -hd), Vector3(x1, y0, -hd), Vector3(x1, y0, hd), Vector3(x0, y0, hd), Vector3(0, 1, 0), [])
			if y == res - 1 or not grid[y + 1][x]:
				_quad(sides, Vector3(x0, y1, hd), Vector3(x1, y1, hd), Vector3(x1, y1, -hd), Vector3(x0, y1, -hd), Vector3(0, -1, 0), [])

	var mesh := ArrayMesh.new()
	faces.index()
	mesh = faces.commit(mesh)
	sides.index()
	mesh = sides.commit(mesh)
	return mesh


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv: Array) -> void:
	var pts := [a, b, c, d]
	var uvs := uv if uv.size() == 4 else [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
