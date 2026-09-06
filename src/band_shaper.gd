class_name BandShaper
extends RefCounted
## One audio band's shape: a gate, an attack / release follower, a decay to
## a sustain level after each rise (transient emphasis when sustain < 1),
## and extra smoothing. Pure; AudioReact runs one per band.

const DEFAULTS := {"attack": 0.055, "decay": 0.3, "sustain": 1.0, "release": 0.2, "gate": 0.0, "smooth": 0.0}
const RANGES := {"attack": [0.005, 1.0], "decay": [0.02, 2.0], "sustain": [0.0, 1.0], "release": [0.02, 3.0], "gate": [0.0, 0.8], "smooth": [0.0, 0.95]}

var attack := 0.055
var decay := 0.3
var sustain := 1.0
var release := 0.2
var gate := 0.0
var smooth := 0.0
var value := 0.0                 # the shaped output, 0..1
var _env := 0.0
var _since_rise := 10.0
var _rising := false


## One frame: raw 0..1 in, shaped 0..1 out.
func step(raw: float, delta: float) -> float:
	var target := clampf(raw, 0.0, 1.0)
	if target < gate:
		target = 0.0
	if target > _env:
		if not _rising:
			_since_rise = 0.0
		_rising = true
		_env += (target - _env) * minf(1.0, delta / maxf(attack, 0.001))
	else:
		_rising = false
		_env += (target - _env) * minf(1.0, delta / maxf(release, 0.001))
	_since_rise += delta
	var shape := sustain + (1.0 - sustain) * exp(-_since_rise / maxf(decay, 0.001))
	var out := clampf(_env * shape, 0.0, 1.0)
	value += (out - value) * (1.0 - smooth * minf(1.0, 0.9 + smooth * 0.1)) if smooth > 0.0 else (out - value)
	return value


func to_dict() -> Dictionary:
	return {"attack": attack, "decay": decay, "sustain": sustain, "release": release, "gate": gate, "smooth": smooth}


static func from_dict(d: Dictionary) -> BandShaper:
	var b := BandShaper.new()
	b.apply(d)
	return b


func apply(d: Dictionary) -> void:
	for k in DEFAULTS:
		if d.has(k):
			set(k, clampf(float(d[k]), RANGES[k][0], RANGES[k][1]))


func reset() -> void:
	apply(DEFAULTS)
	value = 0.0
	_env = 0.0


func describe() -> String:
	return "a %.0f ms · r %.0f ms · s %.2f · d %.0f ms · gate %.2f · smooth %.2f" % [attack * 1000.0, release * 1000.0, sustain, decay * 1000.0, gate, smooth]
