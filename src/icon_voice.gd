class_name IconVoice
extends Node
## The icon as an oscillator: the silhouette's radius around the centre,
## read off its distance field at 512 angles, is one cycle of the waveform
## (a star is a five-bump tone, a bolt a ragged one; a circle falls back to
## the field's ring, then a sine). Played through an AudioStreamGenerator
## by the Voice verb: Morph glides between two tables, Pulse is loudness,
## Spin bends the pitch. Static parts are pure and tested.

const N := 512
const RATE := 22050.0
const NOTES := [0, 2, 4, 7, 9, 12, 14, 16, 19]      # pentatonic degrees per slot, semitones over A2

static var active := 0
static var _tables: Dictionary = {}                 # path -> PackedFloat32Array

var table_a := PackedFloat32Array()
var table_b := PackedFloat32Array()
var morph := 0.0
var freq := 220.0
var amp := 0.5
var pushed := 0
var _player: AudioStreamPlayer
var _phase := 0.0


## Base pitch for a toolbox slot.
static func note_for(slot_index: int) -> float:
	return 110.0 * pow(2.0, NOTES[posmod(slot_index, NOTES.size())] / 12.0)


## One cycle from a distance field (Sdf.from_alpha output: 0.5 at the edge).
static func table_from_sdf(sdf: Image, n := N) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var steps := 96
	for i in n:
		var ang := TAU * i / n
		var dir := Vector2(cos(ang), sin(ang))
		var edge := 0.0
		var prev := Sdf.sample(sdf, 0.5, 0.5)
		for k in range(1, steps + 1):
			var r := 0.5 * k / steps
			var v := Sdf.sample(sdf, 0.5 + dir.x * r, 0.5 + dir.y * r)
			if prev >= 0.5 and v < 0.5:
				edge = r                                  # outermost inside -> outside crossing
			prev = v
		out[i] = edge
	if not _normalise(out):
		for i in n:                                       # a circle: the field's ring instead
			var ang := TAU * i / n
			out[i] = Sdf.sample(sdf, 0.5 + cos(ang) * 0.3, 0.5 + sin(ang) * 0.3)
		if not _normalise(out, 0.12):                     # nearest-pixel jitter on the ring is ~0.04 per px
			for i in n:
				out[i] = sin(TAU * i / n) * 0.9
	return _smooth(out)


## Remove the mean and scale to ±0.9; false when the table is flat (below
## `flat` peak-to-centre, which is pixel jitter on a circle, not a shape).
static func _normalise(t: PackedFloat32Array, flat := 0.04) -> bool:
	var mean := 0.0
	for v in t:
		mean += v
	mean /= maxi(t.size(), 1)
	var peak := 0.0
	for i in t.size():
		t[i] -= mean
		peak = maxf(peak, absf(t[i]))
	if peak < flat:
		return false
	for i in t.size():
		t[i] = t[i] / peak * 0.9
	return true


static func _smooth(t: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(t.size())
	for i in t.size():
		out[i] = (t[(i - 1 + t.size()) % t.size()] + t[i] * 2.0 + t[(i + 1) % t.size()]) * 0.25
	return out


static func zero_crossings(t: PackedFloat32Array) -> int:
	var n := 0
	for i in t.size():
		if (t[i] >= 0.0) != (t[(i + 1) % t.size()] >= 0.0):
			n += 1
	return n


## Cached per image path (the SDF image itself comes from the caller).
static func table_for(path: String, sdf: Image) -> PackedFloat32Array:
	if _tables.has(path):
		return _tables[path]
	var t := table_from_sdf(sdf)
	_tables[path] = t
	return t


static func gain() -> float:
	return 0.22 / sqrt(maxf(1.0, float(active)))


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.12
	_player = AudioStreamPlayer.new()
	_player.stream = gen
	_player.bus = "Master"
	add_child(_player)
	_player.play()
	active += 1


func _exit_tree() -> void:
	active -= 1


func playing() -> bool:
	return _player != null and _player.playing


func _process(_delta: float) -> void:
	if _player == null or table_a.is_empty():
		return
	if not _player.playing:
		_player.play()
	var pb: AudioStreamGeneratorPlayback = _player.get_stream_playback()
	if pb == null:
		return
	var n := mini(pb.get_frames_available(), 4096)
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var step := freq / RATE
	var g := amp * gain()
	var use_b := not table_b.is_empty() and morph > 0.0
	var na := table_a.size()
	for i in n:
		_phase = fmod(_phase + step, 1.0)
		var x := _phase * na
		var i0 := int(x)
		var f := x - i0
		var v := lerpf(table_a[i0 % na], table_a[(i0 + 1) % na], f)
		if use_b:
			var nb := table_b.size()
			var xb := _phase * nb
			var j0 := int(xb)
			var vb := lerpf(table_b[j0 % nb], table_b[(j0 + 1) % nb], xb - j0)
			v = lerpf(v, vb, clampf(morph, 0.0, 1.0))
		buf[i] = Vector2.ONE * (v * g)
	pb.push_buffer(buf)
	pushed += n
