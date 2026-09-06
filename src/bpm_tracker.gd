class_name BpmTracker
extends RefCounted
## Tempo from onsets: every interval between the last onsets is folded into
## one octave (0.3 .. 0.6 s, so all multiples of the beat land together),
## voted in 5 ms bins and refined; the octave is then chosen by the median
## interval between adjacent onsets (a 0.75 s pulse is 80, not 160).
## Confidence is the share of adjacent intervals that agree. Phase runs
## from the last onset. Pure; tested with synthetic onsets.

const KEEP := 24
const MIN_PERIOD := 0.3          # 200 BPM; the fold window is one octave above it
const MAX_PERIOD := 1.2          # 50 BPM
const BIN := 0.005

var onsets: Array = []           # seconds
var period := 0.0                # 0 = unknown
var confidence := 0.0
var anchor := 0.0                # an onset the phase counts from


func onset(t: float) -> void:
	if not onsets.is_empty() and t - onsets[-1] < 0.1:
		return                                   # a double hit
	onsets.append(t)
	while onsets.size() > KEEP:
		onsets.pop_front()
	_estimate()


static func fold(interval: float) -> float:
	var x := interval
	while x >= MIN_PERIOD * 2.0 and x > 0.0:
		x *= 0.5
	while x < MIN_PERIOD and x > 0.0:
		x *= 2.0
	return x


func _estimate() -> void:
	if onsets.size() < 4:
		period = 0.0
		confidence = 0.0
		return
	var votes := {}
	var total := 0
	for i in onsets.size():
		for j in range(i + 1, onsets.size()):
			var d: float = onsets[j] - onsets[i]
			if d <= 0.0 or d > 4.0:
				continue
			var f := fold(d)
			var b := int(round(f / BIN))
			votes[b] = int(votes.get(b, 0)) + 1
			total += 1
	if total == 0:
		return
	var best_bin := -1
	var best := 0
	for b in votes:
		var score: int = int(votes[b]) + int(votes.get(b - 1, 0)) + int(votes.get(b + 1, 0))
		if score > best:
			best = score
			best_bin = b
	var centre := best_bin * BIN
	var sum := 0.0
	var n := 0
	for i in onsets.size():
		for j in range(i + 1, onsets.size()):
			var d: float = onsets[j] - onsets[i]
			if d <= 0.0 or d > 4.0:
				continue
			var f := fold(d)
			if absf(f - centre) <= BIN * 1.5:
				sum += f
				n += 1
	var base := sum / n if n > 0 else centre
	# the octave: the multiple of the base closest to the median adjacent interval
	var adj: Array = []
	for i in range(1, onsets.size()):
		adj.append(onsets[i] - onsets[i - 1])
	adj.sort()
	var median: float = adj[adj.size() / 2]
	period = base
	for mult in [1.0, 2.0, 4.0]:
		if base * mult <= MAX_PERIOD and absf(base * mult - median) < absf(period - median):
			period = base * mult
	# confidence: how many adjacent intervals agree with the period (or its half / double)
	var agree := 0
	for d in adj:
		for mult in [0.5, 1.0, 2.0]:
			if absf(d - period * mult) <= maxf(BIN * 2.0, period * mult * 0.06):
				agree += 1
				break
	confidence = clampf(float(agree) / float(adj.size()), 0.0, 1.0)
	anchor = onsets[-1]


func bpm() -> float:
	return 60.0 / period if period > 0.0 else 0.0


## 0..1 within the beat at time t.
func phase(t: float) -> float:
	if period <= 0.0:
		return 0.0
	return fposmod(t - anchor, period) / period


func next_beat(t: float) -> float:
	if period <= 0.0:
		return t
	return t + (1.0 - phase(t)) * period


func reset() -> void:
	onsets.clear()
	period = 0.0
	confidence = 0.0
