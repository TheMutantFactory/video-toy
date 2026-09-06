extends Node
## Tempo (autoload "Clock"). MIDI clock in — 24 ticks per quarter note, with
## start / stop / continue — or an internal clock at a set BPM. Emits beats
## and bars; everything beat-driven (sparkle bursts, evolve, morph, the
## timeline) follows it through AudioReact.pulse_beat(). Pure timing logic
## lives in feed_tick / advance so the smoke test can drive it.

signal beat(index: int)
signal bar(index: int)
signal transport(running: bool)

const PPQN := 24
const BEATS_PER_BAR := 4

var source := "off"                  # "off" | "midi" | "internal"
var running := false
var bpm := 120.0
var beat_index := 0                  # beats since start
var phase := 0.0                     # 0..1 within the beat
var beat_env := 0.0                  # 1 on the beat, decays
var lock_scenes := false             # oscillator scenes follow the BPM
var _ticks := 0
var _last_tick_us := 0
var _intervals: Array = []
var _internal_t := 0.0
var _audio: Node


func _ready() -> void:
	_audio = get_node_or_null("/root/AudioReact")
	bpm = clampf(float(Settings.get_value("clock_bpm")), 40.0, 240.0)
	lock_scenes = bool(Settings.get_value("lock_scenes"))
	if str(Settings.get_value("clock_source")) == "internal":
		start_internal(bpm)


func _input(ev: InputEvent) -> void:
	if ev is InputEventMIDI:
		match ev.message:
			MIDI_MESSAGE_TIMING_CLOCK: feed_tick(Time.get_ticks_usec())
			MIDI_MESSAGE_START: start_external()
			MIDI_MESSAGE_CONTINUE: start_external(false)
			MIDI_MESSAGE_STOP: stop()


# ---------------- external (MIDI) ----------------
func start_external(reset := true) -> void:
	source = "midi"
	running = true
	if reset:
		_ticks = 0
		beat_index = 0
		phase = 0.0
	_intervals.clear()
	_last_tick_us = 0
	transport.emit(true)


func stop() -> void:
	if not running:
		return
	running = false
	transport.emit(false)


## One MIDI clock tick at `now_us`. Returns true on a beat boundary.
func feed_tick(now_us: int) -> bool:
	if source != "midi":
		source = "midi"
		running = true
		transport.emit(true)
	if _last_tick_us > 0:
		var dt := now_us - _last_tick_us
		if dt > 1000 and dt < 400000:
			_intervals.append(dt)
			if _intervals.size() > PPQN * 2:
				_intervals.pop_front()
			var avg := 0.0
			for d in _intervals:
				avg += d
			avg /= _intervals.size()
			bpm = 60.0e6 / (avg * PPQN)
	_last_tick_us = now_us
	_ticks += 1
	phase = float(_ticks % PPQN) / PPQN
	if _ticks % PPQN == 0:
		_on_beat()
		return true
	return false


# ---------------- internal ----------------
func start_internal(at_bpm := -1.0) -> void:
	if at_bpm > 0.0:
		bpm = at_bpm
	source = "internal"
	running = true
	beat_index = 0
	phase = 0.0
	_internal_t = 0.0
	transport.emit(true)
	_on_beat()


func toggle_internal() -> void:
	if source == "internal" and running:
		stop()
		source = "off"
	else:
		start_internal()


## Advance the internal clock by `delta` seconds. Returns beats crossed.
func advance(delta: float) -> int:
	beat_env = maxf(0.0, beat_env - delta * 4.0)
	if not running or source != "internal":
		return 0
	var beat_len := 60.0 / maxf(bpm, 1.0)
	_internal_t += delta
	var crossed := 0
	while _internal_t >= beat_len:
		_internal_t -= beat_len
		_on_beat()
		crossed += 1
	phase = _internal_t / beat_len
	return crossed


func _process(delta: float) -> void:
	advance(delta)


func _on_beat() -> void:
	beat_index += 1
	beat_env = 1.0
	beat.emit(beat_index)
	if beat_index % BEATS_PER_BAR == 1:
		bar.emit((beat_index - 1) / BEATS_PER_BAR)
	if _audio and _audio.has_method("pulse_beat"):
		_audio.pulse_beat()


func beat_in_bar() -> int:
	return posmod(beat_index - 1, BEATS_PER_BAR)


func bar_seconds() -> float:
	return BEATS_PER_BAR * 60.0 / maxf(bpm, 1.0)


## Round a duration to whole bars (at least one).
func quantise_to_bars(seconds: float) -> float:
	var b := bar_seconds()
	return maxf(1.0, round(seconds / b)) * b


## Seconds until the next bar starts (0 when not running).
func until_next_bar() -> float:
	if not running:
		return 0.0
	var beat_len := 60.0 / maxf(bpm, 1.0)
	var into_bar := beat_in_bar() * beat_len + phase * beat_len
	return bar_seconds() - into_bar


func describe() -> String:
	if not running:
		return "off"
	var dots := ""
	for i in BEATS_PER_BAR:
		dots += "▮" if i == beat_in_bar() else "▯"
	return "%s %.1f bpm %s" % [source, bpm, dots]
