class_name Sdf
## Signed distance field of an icon's alpha. Two Euclidean distance transforms
## (8SSEDT: two sweeps each) on a downscaled copy give the distance to the
## nearest edge inside and outside; the result is stored as an 8-bit image with
## 0.5 at the edge, > 0.5 inside, clamped at ±spread pixels. SDFs upscale
## crisply, so RES is far below the icon's own resolution.

const RES := 200
const SPREAD := 14.0
const INF := 1.0e9


static func from_alpha(src: Image, res := RES, spread := SPREAD) -> Image:
	var img: Image = src.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(res, res, Image.INTERPOLATE_BILINEAR)
	var inside := PackedByteArray()
	inside.resize(res * res)
	for y in res:
		for x in res:
			inside[y * res + x] = 1 if img.get_pixel(x, y).a > 0.5 else 0
	var d_out := _edt(inside, res, 1)          # distance from outside cells to the shape
	var d_in := _edt(inside, res, 0)           # distance from inside cells to the background
	var out := Image.create(res, res, false, Image.FORMAT_RGBA8)
	for y in res:
		for x in res:
			var i := y * res + x
			var signed: float = (d_in[i] if inside[i] == 1 else -d_out[i])
			var v := clampf(0.5 + signed / (2.0 * spread), 0.0, 1.0)
			out.set_pixel(x, y, Color(v, v, v, 1.0))
	return out


## Distance from every cell to the nearest cell whose `inside` equals `target`.
static func _edt(inside: PackedByteArray, n: int, target: int) -> PackedFloat32Array:
	var dx := PackedInt32Array()
	var dy := PackedInt32Array()
	dx.resize(n * n)
	dy.resize(n * n)
	var big := n * 4
	for i in n * n:
		var seed := inside[i] == target
		dx[i] = 0 if seed else big
		dy[i] = 0 if seed else big
	# forward sweep
	for y in n:
		for x in n:
			var i := y * n + x
			if x > 0:
				_relax(dx, dy, i, i - 1, 1, 0)
			if y > 0:
				_relax(dx, dy, i, i - n, 0, 1)
				if x > 0:
					_relax(dx, dy, i, i - n - 1, 1, 1)
				if x < n - 1:
					_relax(dx, dy, i, i - n + 1, -1, 1)
		for x in range(n - 1, -1, -1):
			var i := y * n + x
			if x < n - 1:
				_relax(dx, dy, i, i + 1, -1, 0)
	# backward sweep
	for y in range(n - 1, -1, -1):
		for x in range(n - 1, -1, -1):
			var i := y * n + x
			if x < n - 1:
				_relax(dx, dy, i, i + 1, -1, 0)
			if y < n - 1:
				_relax(dx, dy, i, i + n, 0, -1)
				if x < n - 1:
					_relax(dx, dy, i, i + n + 1, -1, -1)
				if x > 0:
					_relax(dx, dy, i, i + n - 1, 1, -1)
		for x in n:
			var i := y * n + x
			if x > 0:
				_relax(dx, dy, i, i - 1, 1, 0)
	var out := PackedFloat32Array()
	out.resize(n * n)
	for i in n * n:
		out[i] = sqrt(float(dx[i] * dx[i] + dy[i] * dy[i]))
	return out


static func _relax(dx: PackedInt32Array, dy: PackedInt32Array, i: int, j: int, ox: int, oy: int) -> void:
	var cx := dx[j] + ox
	var cy := dy[j] + oy
	if cx * cx + cy * cy < dx[i] * dx[i] + dy[i] * dy[i]:
		dx[i] = cx
		dy[i] = cy


## Sample the field (0..1) at normalised coordinates.
static func sample(sdf: Image, u: float, v: float) -> float:
	var x := clampi(int(u * sdf.get_width()), 0, sdf.get_width() - 1)
	var y := clampi(int(v * sdf.get_height()), 0, sdf.get_height() - 1)
	return sdf.get_pixel(x, y).r
