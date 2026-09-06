class_name Modulator
extends RefCounted
## A modulation source for one learnable param: LFO shapes, a random walk,
## sample-and-hold and a beat envelope, with a depth around a centre (the
## last value the knob sent). Pure: advance() takes the frame time and
## whether a beat landed; the output is 0..1 like any controller.

const SHAPES := ["sine", "tri", "square", "saw", "random", "sh", "env"]
const RATES := [0.1, 0.25, 0.5, 1.0, 2.0, 4.0]         # Hz

var shape := "sine"
var rate := 0.5
var depth := 0.5
var centre := 0.5
var phase := 0.0
var _walk := 0.0
var _hold := 0.0
var _env := 0.0
var _since_hold := 0.0


static func wave(shape_name: String, p: float) -> float:
	match shape_name:
		"sine": return sin(TAU * p)
		"tri": return 1.0 - 4.0 * absf(fposmod(p, 1.0) - 0.5)
		"square": return 1.0 if fposmod(p, 1.0) < 0.5 else -1.0
		"saw": return 2.0 * fposmod(p, 1.0) - 1.0
	return 0.0


## The next output, -1..1 before depth; `beat` retriggers env and S&H.
func advance(delta: float, beat := false) -> float:
	var w := 0.0
	match shape:
		"sine", "tri", "square", "saw":
			phase = fposmod(phase + rate * delta, 1.0)
			w = wave(shape, phase)
		"random":
			_walk = clampf(_walk + randfn(0.0, 1.0) * sqrt(maxf(delta, 0.0)) * rate * 1.5, -1.0, 1.0)
			_walk *= 1.0 - minf(delta * 0.2, 1.0)          # a gentle pull back to the centre
			w = _walk
		"sh":
			_since_hold += delta
			if beat or _since_hold >= 1.0 / maxf(rate, 0.01):
				_hold = randf_range(-1.0, 1.0)
				_since_hold = 0.0
			w = _hold
		"env":
			if beat:
				_env = 1.0
			_env *= exp(-delta * maxf(rate, 0.05) * 3.0)
			w = _env * 2.0 - 1.0
	return w


func output(delta: float, beat := false) -> float:
	return clampf(centre + depth * 0.5 * advance(delta, beat), 0.0, 1.0)


func next_rate() -> float:
	var i := RATES.find(rate)
	rate = RATES[(i + 1) % RATES.size()] if i >= 0 else RATES[2]
	return rate


func describe() -> String:
	var r := "%s Hz" % rate
	if shape in ["env", "sh"]:
		r += " / beat"
	return "%s %s" % [shape, r]


func to_dict() -> Dictionary:
	return {"shape": shape, "rate": rate, "depth": depth, "centre": centre}


static func from_dict(d: Dictionary) -> Modulator:
	var m := Modulator.new()
	m.shape = str(d.get("shape", "sine")) if SHAPES.has(str(d.get("shape", ""))) else "sine"
	m.rate = clampf(float(d.get("rate", 0.5)), 0.01, 20.0)
	m.depth = clampf(float(d.get("depth", 0.5)), 0.0, 1.0)
	m.centre = clampf(float(d.get("centre", 0.5)), 0.0, 1.0)
	return m
