class_name Gnarl
## The gnarl regulator: hold the picture near the edge of interestingness.
## A tiny probe of the composite is read back every few frames; its edge
## density and frame-to-frame change make a complexity score, and the loop's
## fade, warp and cleanup are nudged toward an artist-set target. Pure parts
## here (measure, adjust, apply); the stage owns the probe and the knobs.

const PROBE := Vector2i(96, 54)
const EDGE_NORM := 0.22          # mean gradient of a busy picture
const DIFF_NORM := 0.18          # mean change of a lively picture


static func _lum(c: Color) -> float:
	return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * c.a


## {edge, fill, diff, complexity}, all 0..1.
static func measure(img: Image, prev: Image = null) -> Dictionary:
	if img == null or img.is_empty():
		return {"edge": 0.0, "fill": 0.0, "diff": 0.0, "complexity": 0.0}
	var w := img.get_width()
	var h := img.get_height()
	var edge := 0.0
	var fill := 0.0
	var diff := 0.0
	var n := 0
	var same_prev := prev != null and prev.get_width() == w and prev.get_height() == h
	for y in range(0, h - 1):
		for x in range(0, w - 1):
			var l := _lum(img.get_pixel(x, y))
			edge += absf(_lum(img.get_pixel(x + 1, y)) - l) + absf(_lum(img.get_pixel(x, y + 1)) - l)
			fill += l
			if same_prev:
				diff += absf(_lum(prev.get_pixel(x, y)) - l)
			n += 1
	if n == 0:
		return {"edge": 0.0, "fill": 0.0, "diff": 0.0, "complexity": 0.0}
	var e := clampf(edge / n / EDGE_NORM, 0.0, 1.0)
	var d := clampf(diff / n / DIFF_NORM, 0.0, 1.0) if same_prev else 0.0
	return {"edge": e, "fill": fill / n, "diff": d, "complexity": clampf(0.65 * e + 0.35 * d, 0.0, 1.0)}


## How far to push this measurement: positive = the picture wants more.
static func adjust(complexity: float, target: float, speed: float) -> float:
	return (target - complexity) * clampf(speed, 0.0, 1.0) * 0.08


## New fade / warp / cleanup after a push `d`; bias 0 = vary warp and fade
## (order), 1 = vary cleanup and fade (noise).
static func apply(fade: float, warp: float, cleanup: float, d: float, bias: float) -> Dictionary:
	var b := clampf(bias, 0.0, 1.0)
	return {
		"fade": clampf(fade + d * 0.5, 0.5, 0.995),
		"warp": clampf(warp + d * 0.8 * (1.0 - b), 0.0, 1.0),
		"cleanup": clampf(cleanup - d * 0.8 * b, 0.0, 1.0),
	}
