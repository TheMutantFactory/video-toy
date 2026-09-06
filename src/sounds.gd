class_name Sounds
## Slot sounds: a wav / mp3 / ogg dropped on a hotbar slot plays on spawn,
## on the beat (with Sparkle), on pinata and on physics collisions. A small
## pool of players on the stage; streams cached by path. No autoload
## references: callers pass the path (the actor reads it off its slot).

const POLY := 8

static var last_played := ""
static var played := 0
static var _host: Node
static var _players: Array = []
static var _next := 0
static var _streams: Dictionary = {}
static var _frame_guard: Dictionary = {}   # path -> process frame it already played in


static func attach(host: Node) -> void:
	_host = host
	_players = []
	for i in POLY:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		host.add_child(p)
		_players.append(p)


static func detach() -> void:
	_host = null
	_players = []


static func load_stream(path: String) -> AudioStream:
	if path == "":
		return null
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = null
	match path.get_extension().to_lower():
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"wav": stream = AudioStreamWAV.load_from_file(path)
	if stream != null:
		_streams[path] = stream
	return stream


static func forget(path: String) -> void:
	_streams.erase(path)


static func play(path: String, pitch := 1.0, volume_db := 0.0) -> bool:
	if path == "" or _host == null or _players.is_empty():
		return false
	var stream := load_stream(path)
	if stream == null:
		return false
	var p: AudioStreamPlayer = null
	for cand in _players:
		if not cand.playing:
			p = cand
			break
	if p == null:                                       # steal round-robin
		p = _players[_next % _players.size()]
		_next += 1
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.volume_db = volume_db
	p.play()
	last_played = path
	played += 1
	return true


## At most once per process frame per path (every actor of a slot hears the
## same beat in the same frame).
static func play_once_this_frame(path: String, pitch := 1.0, volume_db := 0.0) -> bool:
	var frame := Engine.get_process_frames()
	if int(_frame_guard.get(path, -1)) == frame:
		return false
	_frame_guard[path] = frame
	return play(path, pitch, volume_db)


## A short 16-bit sine for tests and demos.
static func make_test_wav(path: String, hz := 440.0, seconds := 0.12, rate := 22050) -> bool:
	var n := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := 1.0 - float(i) / n
		var v := int(sin(TAU * hz * i / rate) * env * 24000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav.save_to_wav(path) == OK
