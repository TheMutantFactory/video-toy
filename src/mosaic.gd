class_name Mosaic
## An image as a grid of cells: colour, luminance and coverage per cell, in
## normalised 0..1 coordinates. The stage turns each cell into an actor of the
## nearest-coloured icon, scaled by luminance. Static and autoload-free.

const MAX_COLS := 44
const MAX_CELLS := 1100


static func grid_size(img: Image, cols := MAX_COLS) -> Vector2i:
	var aspect := float(img.get_height()) / maxf(img.get_width(), 1.0)
	var c := cols
	var r := maxi(1, int(round(c * aspect)))
	while c * r > MAX_CELLS:
		c -= 1
		r = maxi(1, int(round(c * aspect)))
	return Vector2i(c, r)


## Cells with alpha > 0.5 after downsampling. Each: {"u", "v", "color", "lum"}.
static func cells(img: Image, cols := MAX_COLS) -> Array:
	var g := grid_size(img, cols)
	var small: Image = img.duplicate()
	small.convert(Image.FORMAT_RGBA8)
	small.resize(g.x, g.y, Image.INTERPOLATE_LANCZOS)
	var out: Array = []
	for y in g.y:
		for x in g.x:
			var c := small.get_pixel(x, y)
			if c.a < 0.5:
				continue
			out.append({"u": (x + 0.5) / g.x, "v": (y + 0.5) / g.y, "color": c, "lum": c.get_luminance()})
	return out


## Index of the candidate colour nearest `c` (weighted RGB). -1 if none.
static func nearest(c: Color, candidates: Array) -> int:
	var best := -1
	var bd := 1e9
	for i in candidates.size():
		var k: Color = candidates[i]
		var d := pow((c.r - k.r) * 0.30, 2) + pow((c.g - k.g) * 0.59, 2) + pow((c.b - k.b) * 0.11, 2)
		if d < bd:
			bd = d
			best = i
	return best
