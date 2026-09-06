class_name ImageDiff
## Compare two captures for regressions: both downscaled to a small grid, mean
## absolute difference per channel plus the worst 8x8-block difference, so a
## shifted HUD digit passes and a broken shader fails.

const GRID := Vector2i(240, 135)
const MEAN_LIMIT := 0.035
const BLOCK_LIMIT := 0.45


static func compare(a: Image, b: Image) -> Dictionary:
	var x: Image = a.duplicate()
	var y: Image = b.duplicate()
	x.convert(Image.FORMAT_RGB8)
	y.convert(Image.FORMAT_RGB8)
	x.resize(GRID.x, GRID.y, Image.INTERPOLATE_LANCZOS)
	y.resize(GRID.x, GRID.y, Image.INTERPOLATE_LANCZOS)
	var total := 0.0
	var worst := 0.0
	var bw := 8
	for by in range(0, GRID.y, bw):
		for bx in range(0, GRID.x, bw):
			var acc := 0.0
			var cnt := 0
			for yy in range(by, mini(by + bw, GRID.y)):
				for xx in range(bx, mini(bx + bw, GRID.x)):
					var p := x.get_pixel(xx, yy)
					var q := y.get_pixel(xx, yy)
					var d := (absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b)) / 3.0
					acc += d
					cnt += 1
			total += acc
			worst = maxf(worst, acc / maxf(cnt, 1))
	var mean := total / float(GRID.x * GRID.y)
	return {"mean": mean, "worst_block": worst, "pass": mean <= float(Settings.get_value("diff_mean")) and worst <= float(Settings.get_value("diff_block"))}
