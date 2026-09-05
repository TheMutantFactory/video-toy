extends Node
## Audio reactivity (autoload "AudioReact"). Analyses one source into four
## smoothed 0..1 bands and a beat envelope:
##   bass 30-200 Hz · mid 200-2k · high 2k-12k · level (all)
## Sources: "off", "mic", "file" (a dropped audio file, audible), "test" (a
## synthetic 120 BPM groove so bindings can be tried with no input at all).
##
## Bands go to MidiMap.feed_audio() each frame, so anything learnable can be
## driven by audio; actors also read `bass` and `beat_env` directly.

signal beat
signal source_changed(source: String)

const SOURCES := ["off", "mic", "test", "file"]

var source := "off"
var bass := 0.0
var mid := 0.0
var high := 0.0
var level := 0.0
var beat_env := 0.0                     # 1 on a beat, decays to 0
var gain := 1.0                         # 0.25 .. 4
var file_name := ""

var _mic_bus := -1
var _file_bus := -1
var _mic_player: AudioStreamPlayer
var _file_player: AudioStreamPlayer
var _bass_avg := 0.0
var _cooldown := 0.0
var _test_t := 0.0
var _rng := RandomNumberGenerator.new()
var _midi: Node                         # MidiMap, resolved at runtime so this script has no autoload dependency


func _ready() -> void:
	_mic_bus = _make_bus("MicAnalyze", -80.0)          # analysed, never heard
	_file_bus = _make_bus("FileAnalyze", 0.0)           # analysed and heard
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "MicAnalyze"
	add_child(_mic_player)
	_file_player = AudioStreamPlayer.new()
	_file_player.bus = "FileAnalyze"
	add_child(_file_player)
	_midi = get_node_or_null("/root/MidiMap")
	if _midi:
		beat.connect(_midi.feed_beat)


func _make_bus(name: String, volume_db: float) -> int:
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_volume_db(idx, volume_db)
	AudioServer.set_bus_send(idx, "Master")
	var fx := AudioEffectSpectrumAnalyzer.new()
	fx.buffer_length = 0.1
	fx.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
	AudioServer.add_bus_effect(idx, fx)
	return idx


var _clock: Node


func active() -> bool:
	return source != "off" or clock_running()


func clock_running() -> bool:
	if _clock == null:
		_clock = get_node_or_null("/root/Clock")
	return _clock != null and _clock.running


## A beat from the tempo clock: the envelope and the beat signal fire exactly
## as they would from the bass detector, so everything beat-driven follows.
func pulse_beat() -> void:
	beat_env = 1.0
	_cooldown = 0.18
	beat.emit()


## True when the engine fell back to the silent dummy driver in a real run
## (typically: audio input enabled but no input device — see run.sh).
func driver_missing() -> bool:
	return AudioServer.get_driver_name() == "Dummy" and DisplayServer.get_name() != "headless"


## The microphone needs the project setting AND a live driver.
func mic_available() -> bool:
	return bool(ProjectSettings.get_setting("audio/driver/enable_input", false)) and not driver_missing()


func set_source(s: String) -> void:
	if s == "file" and _file_player.stream == null:
		s = "off"
	if s == "mic" and not mic_available():
		s = "off"
	if s == source:
		return
	source = s
	_mic_player.stop()
	_file_player.stop()
	if s == "mic":
		_mic_player.play()
	elif s == "file":
		_file_player.play()
	elif s == "off":
		bass = 0.0
		mid = 0.0
		high = 0.0
		level = 0.0
		beat_env = 0.0
	source_changed.emit(source)


func cycle_source() -> void:
	var i := SOURCES.find(source)
	for n in SOURCES.size():
		i = (i + 1) % SOURCES.size()
		var s: String = SOURCES[i]
		if s == "file" and _file_player.stream == null:
			continue
		if s == "mic" and not mic_available():
			continue
		set_source(s)
		return


## Load an mp3 / ogg / wav from disk and switch to it (audible).
func load_file(path: String) -> bool:
	var stream: AudioStream = null
	match path.get_extension().to_lower():
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"wav": stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		return false
	if "loop" in stream:
		stream.loop = true
	_file_player.stream = stream
	file_name = path.get_file()
	source = ""                              # force the switch
	set_source("file")
	return true


func _process(delta: float) -> void:
	if source == "off":
		beat_env = maxf(0.0, beat_env - delta * 4.0)      # clock pulses still decay
		return
	var raw: Dictionary
	if source == "test":
		raw = _test_bands(delta)
	else:
		var inst = AudioServer.get_bus_effect_instance(_mic_bus if source == "mic" else _file_bus, 0)
		if inst == null:
			return
		raw = {
			"bass": _db01(inst.get_magnitude_for_frequency_range(30, 200)),
			"mid": _db01(inst.get_magnitude_for_frequency_range(200, 2000)),
			"high": _db01(inst.get_magnitude_for_frequency_range(2000, 12000)),
		}
	update_bands(raw, delta)
	if _midi:
		_midi.feed_audio({"bass": bass, "mid": mid, "high": high, "level": level})


## Pure: smooth raw 0..1 bands (fast attack, slow release), track level, and
## detect bass onsets. Split out so the smoke test can drive it.
func update_bands(raw: Dictionary, delta: float) -> bool:
	bass = _follow(bass, clampf(raw.get("bass", 0.0) * gain, 0.0, 1.0), delta)
	mid = _follow(mid, clampf(raw.get("mid", 0.0) * gain, 0.0, 1.0), delta)
	high = _follow(high, clampf(raw.get("high", 0.0) * gain, 0.0, 1.0), delta)
	level = maxf(bass, maxf(mid, high))
	_bass_avg = lerpf(_bass_avg, bass, minf(1.0, delta * 2.0))
	_cooldown = maxf(0.0, _cooldown - delta)
	beat_env = maxf(0.0, beat_env - delta * 4.0)
	var hit := bass > 0.18 and bass > _bass_avg * 1.35 and _cooldown <= 0.0
	if hit:
		_cooldown = 0.18
		beat_env = 1.0
		beat.emit()
	return hit


static func _follow(cur: float, target: float, delta: float) -> float:
	var k := 18.0 if target > cur else 5.0           # attack fast, release slow
	return lerpf(cur, target, minf(1.0, delta * k))


## Stereo magnitude -> 0..1 on a -60..0 dB scale.
static func _db01(mag: Vector2) -> float:
	var m := maxf(mag.x, mag.y)
	if m <= 0.0:
		return 0.0
	return clampf((linear_to_db(m) + 60.0) / 60.0, 0.0, 1.0)


## A fake groove at 120 BPM: kick on every beat, hats on the offbeats, a
## wandering mid line. Enough to see bindings move without a microphone.
func _test_bands(delta: float) -> Dictionary:
	_test_t += delta
	var beat_phase := fmod(_test_t * 2.0, 1.0)                 # 120 BPM
	var kick := pow(1.0 - beat_phase, 6.0)
	var hat := pow(1.0 - fmod(_test_t * 4.0 + 0.5, 1.0), 10.0) * 0.6
	var line := 0.35 + 0.3 * sin(_test_t * 1.7) + 0.1 * sin(_test_t * 5.3)
	return {"bass": kick * 0.9, "mid": line, "high": hat + _rng.randf() * 0.05}
