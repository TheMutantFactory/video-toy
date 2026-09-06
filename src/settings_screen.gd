extends Control
## Settings: the show knobs an exported app has no shell for (quality lock,
## OSC port, Syphon name, autosave and attract timers, HUD, clock at launch),
## the microphone override, the Noun Project key and the reference-diff
## thresholds. Everything but the key and the mic override lives in
## user://settings.cfg (Settings); the key in user://noun_credentials.cfg.

signal navigate(name: String)

const Creds = preload("res://src/credentials.gd")
const QUALITY := ["auto", "full", "high", "medium", "low"]
const HUD := ["full", "compact", "hidden"]
const CLOCK := ["off", "internal"]

var _key: LineEdit
var _secret: LineEdit
var _status: Label
var _osc_note: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Palettes.bg(0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(980, 0)
	col.add_theme_constant_override("separation", 8)
	centre.add_child(col)

	col.add_child(UI.vspace(24))
	var head := HBoxContainer.new()
	head.add_child(UI.title("Settings", 56))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(UI.button("← Back", func(): navigate.emit("start"), 140))
	col.add_child(head)
	col.add_child(UI.label("Saved as you change them; the stage reads them when Play opens unless a note says live.", 16, UI.DIM))

	# ---------------- show
	_section(col, "Show")
	var g := _grid(col)
	var q := OptionButton.new()
	for n in QUALITY:
		q.add_item(n)
	q.selected = maxi(0, QUALITY.find(str(Settings.get_value("quality_lock"))))
	q.item_selected.connect(func(i: int): Settings.set_value("quality_lock", QUALITY[i]))
	_row(g, "Quality", q, "auto lets the ladder shed load under 20 ms of work; a lock holds one level (Shift+F on stage cycles it)")
	var port := _spin(1024, 65535, 1, int(Settings.get_value("osc_port")))
	_osc_note = UI.label("", 15, UI.DIM)
	_osc_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_osc_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port.value_changed.connect(func(v: float):
		Settings.set_value("osc_port", int(v))
		Osc.set_port(int(v))
		_refresh_osc())
	_row(g, "OSC port", port, "", _osc_note)
	_refresh_osc()
	var oo := CheckButton.new()
	oo.text = "send notes and events as OSC (MIDI out through a bridge)"
	oo.button_pressed = bool(Settings.get_value("osc_out"))
	var oh := LineEdit.new()
	oh.text = str(Settings.get_value("osc_out_host"))
	oh.custom_minimum_size = Vector2(170, 40)
	var op := _spin(1024, 65535, 1, int(Settings.get_value("osc_out_port")))
	var apply_out := func():
		var h := oh.text.strip_edges()
		if h == "":
			h = str(Settings.DEFAULTS["osc_out_host"])
		Settings.set_value("osc_out_host", h)
		Settings.set_value("osc_out_port", int(op.value))
		Settings.set_value("osc_out", oo.button_pressed)
		MidiOut.configure(h, int(op.value), oo.button_pressed)
	oo.toggled.connect(func(_on: bool): apply_out.call())
	oh.text_submitted.connect(func(_t): apply_out.call())
	oh.focus_exited.connect(apply_out)
	op.value_changed.connect(func(_v: float): apply_out.call())
	_row(g, "OSC out", oo, "live: /vt/midi/note_on|note_off|cc and /vt/event/spawn|collision|pinata|beat|remove; docs/controllers/osc-midi-bridge.py makes a MIDI port of it")
	var hp := HBoxContainer.new()
	hp.add_theme_constant_override("separation", 8)
	hp.add_child(oh)
	hp.add_child(op)
	_row(g, "  to host : port", hp, "the bridge's machine (127.0.0.1 = this one) and its UDP port")
	var sy := LineEdit.new()
	sy.text = str(Settings.get_value("syphon_name"))
	sy.custom_minimum_size = Vector2(260, 40)
	var save_sy := func():
		var n := sy.text.strip_edges()
		Settings.set_value("syphon_name", n if n != "" else str(Settings.DEFAULTS["syphon_name"]))
	sy.text_submitted.connect(func(_t): save_sy.call())
	sy.focus_exited.connect(save_sy)
	_row(g, "Syphon server", sy, "the name OBS / Resolume see; used the next time Shift+Z turns the output on")
	var auto := _spin(5, 600, 5, int(Settings.get_value("autosave_interval")), " s")
	auto.value_changed.connect(func(v: float): Settings.set_value("autosave_interval", int(v)))
	_row(g, "Autosave every", auto, "the live state for Restore last session")
	var idle := _spin(10, 3600, 10, int(Settings.get_value("attract_idle")), " s")
	idle.value_changed.connect(func(v: float): Settings.set_value("attract_idle", int(v)))
	_row(g, "Attract after", idle, "idle seconds before attract mode starts on its own")
	var hud := OptionButton.new()
	for n in HUD:
		hud.add_item(n)
	hud.selected = maxi(0, HUD.find(str(Settings.get_value("hud"))))
	hud.item_selected.connect(func(i: int): Settings.set_value("hud", HUD[i]))
	_row(g, "HUD at start", hud, "H cycles full / compact / hidden on stage")
	var safe := CheckButton.new()
	safe.text = "no MIDI, OSC, camera or microphone at launch"
	safe.button_pressed = bool(Settings.get_value("safe_mode"))
	safe.toggled.connect(func(on: bool): Settings.set_value("safe_mode", on))
	var guest := CheckButton.new()
	guest.text = "mouse only: right-click opens the wheel, a hold removes"
	guest.button_pressed = bool(Settings.get_value("guest_mode"))
	guest.toggled.connect(func(on: bool): Settings.set_value("guest_mode", on))
	_row(g, "Guest mode", guest, "at launch; Ctrl+U on stage toggles it live. For a party: no keyboard knowledge needed")
	var tour := CheckButton.new()
	tour.text = "show the five first-run captions again"
	tour.button_pressed = not bool(Settings.get_value("tour_seen"))
	tour.toggled.connect(func(on: bool): Settings.set_value("tour_seen", not on))
	_row(g, "Tour", tour, "next time Play opens; Esc menu → Take the tour any time")
	var cf := OptionButton.new()
	for n in ClipExport.FORMATS.keys():
		cf.add_item(n)
	cf.selected = maxi(0, ClipExport.FORMATS.keys().find(str(Settings.get_value("clip_format"))))
	cf.item_selected.connect(func(i: int): Settings.set_value("clip_format", ClipExport.FORMATS.keys()[i]))
	var cfps := _spin(24, 120, 1, int(Settings.get_value("clip_fps")), " fps")
	cfps.value_changed.connect(func(v: float): Settings.set_value("clip_fps", int(v)))
	var cpre := _spin(0.0, 30.0, 0.5, float(Settings.get_value("clip_preroll")), " s")
	cpre.value_changed.connect(func(v: float): Settings.set_value("clip_preroll", v))
	var cseam := _spin(0.0, 10.0, 0.25, float(Settings.get_value("clip_seam")), " s")
	cseam.value_changed.connect(func(v: float): Settings.set_value("clip_seam", v))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	for w in [cf, cfps, cpre, cseam]:
		crow.add_child(w)
	_row(g, "Clip export", crow, "format (a centre crop; Ctrl+E shows the guide on stage) · fps · pre-roll before the clip · seam cross-dissolved for a seamless loop. " + ("ffmpeg found: mp4s are made" if ClipExport.has_ffmpeg() else "no ffmpeg found: the AVI and a script for the mp4 are left instead (brew install ffmpeg)"))
	_row(g, "Safe mode", safe, ("ON NOW — " if Safe.active() else "") + "for a machine that misbehaves; also `--safe` on the command line (./run.sh safe). Next launch.")

	# ---------------- clock
	_section(col, "Clock")
	var gc := _grid(col)
	var bpm := _spin(40, 240, 1, int(Settings.get_value("clock_bpm")), " bpm")
	var src := OptionButton.new()
	for n in CLOCK:
		src.add_item(n)
	src.selected = maxi(0, CLOCK.find(str(Settings.get_value("clock_source"))))
	src.item_selected.connect(func(i: int):
		Settings.set_value("clock_source", CLOCK[i])
		if CLOCK[i] == "internal":
			Clock.start_internal(bpm.value)
		elif Clock.source == "internal":
			Clock.stop())
	_row(gc, "At launch", src, "live: internal beats drive Sparkle, Morph, evolve and the pulse with no audio; a MIDI clock in takes over either way")
	bpm.value_changed.connect(func(v: float):
		Settings.set_value("clock_bpm", int(v))
		Clock.bpm = v)
	_row(gc, "BPM", bpm, "live")
	var lock := CheckButton.new()
	lock.text = "oscillator scenes follow the BPM"
	lock.button_pressed = bool(Settings.get_value("lock_scenes"))
	lock.toggled.connect(func(on: bool):
		Settings.set_value("lock_scenes", on)
		Clock.lock_scenes = on)
	_row(gc, "Lock scenes", lock, "live")

	# ---------------- audio
	_section(col, "Audio")
	var ga := _grid(col)
	var mic := CheckButton.new()
	var ov := AudioInputSetting.override_state()
	mic.button_pressed = AudioInputSetting.currently_enabled() if ov < 0 else ov == 1
	mic.text = "enable the microphone / line-in at launch"
	var mic_note := UI.label("", 15, UI.DIM)
	mic_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mic_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var refresh_note := func():
		var drv := "audio driver: %s" % AudioServer.get_driver_name()
		var warn := "  —  no audio device: turn this OFF on a machine with no input, or all sound goes silent" if AudioReact.driver_missing() else ""
		mic_note.text = "%s%s. Takes effect on the next launch (override file: %s)" % [drv, warn, AudioInputSetting.override_path()]
	mic.toggled.connect(func(on: bool):
		AudioInputSetting.set_enabled(on)
		refresh_note.call())
	refresh_note.call()
	_row(ga, "Microphone", mic, "", mic_note)

	# ---------------- noun project
	_section(col, "Noun Project API")
	col.add_child(UI.label("thenounproject.com/developers — search is free, each Add to toolbox is one metered download", 15, UI.DIM))
	var gk := _grid(col)
	_key = LineEdit.new()
	_key.custom_minimum_size = Vector2(520, 40)
	_row(gk, "Key", _key)
	_secret = LineEdit.new()
	_secret.secret = true
	_secret.custom_minimum_size = Vector2(520, 40)
	_row(gk, "Secret", _secret)
	var existing := Creds.load_creds()
	if not existing.is_empty():
		_key.text = existing["key"]
		_secret.text = existing["secret"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	row.add_child(UI.button("Save", _save, 140))
	row.add_child(UI.button("Test connection", _test, 200))
	row.add_child(UI.button("Clear", func():
		Creds.clear_creds()
		_key.text = ""
		_secret.text = ""
		_status.text = "Cleared the saved key.", 120))
	_status = UI.label("", 16, UI.DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var creds_src := Creds.source()
	_status.text = ("Using credentials from %s." % creds_src) if creds_src != "" else \
		"No credentials yet. Paste your key and secret, Save, then Test."
	NounApi.usage_result.connect(_on_usage)

	# ---------------- reference captures
	_section(col, "Reference captures (./run.sh check)")
	var gd := _grid(col)
	var dm := _spin(0.005, 0.2, 0.005, float(Settings.get_value("diff_mean")))
	dm.value_changed.connect(func(v: float): Settings.set_value("diff_mean", v))
	_row(gd, "Mean limit", dm, "mean per-pixel difference allowed against tests/reference")
	var db := _spin(0.05, 1.0, 0.05, float(Settings.get_value("diff_block")))
	db.value_changed.connect(func(v: float): Settings.set_value("diff_block", v))
	_row(gd, "Block limit", db, "worst 8×8 block allowed; a HUD digit passes, a broken shader fails")

	# ---------------- footer
	col.add_child(UI.vspace(8))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.add_child(UI.button("Reset settings", func():
		Settings.reset()
		navigate.emit("settings"), 170))
	foot.add_child(UI.button("Open data folder", func(): OS.shell_open(ProjectSettings.globalize_path("user://")), 190))
	foot.add_child(UI.button("Open logs", func(): OS.shell_open(ProjectSettings.globalize_path(CrashLog.DIR)), 130))
	var ver := UI.label("%s   ·   %s" % [Build.describe(), ProjectSettings.globalize_path(Settings.PATH)], 14, UI.DIM)
	ver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(ver)
	col.add_child(foot)
	col.add_child(UI.vspace(30))


func _section(col: VBoxContainer, title: String) -> void:
	col.add_child(UI.vspace(10))
	col.add_child(UI.label(title, 26, UI.ACCENT))


func _grid(col: VBoxContainer) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 8)
	col.add_child(g)
	return g


## label | control + note
func _row(g: GridContainer, label: String, control: Control, note := "", note_label: Label = null) -> void:
	var l := UI.label(label, 20)
	l.custom_minimum_size.x = 170
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(l)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)
	if note_label:
		note_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(note_label)
	elif note != "":
		var n := UI.label(note, 15, UI.DIM)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(n)
	g.add_child(h)


static func _spin(lo: float, hi: float, step: float, value: float, suffix := "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.suffix = suffix
	s.custom_minimum_size = Vector2(150, 40)
	return s


func _refresh_osc() -> void:
	_osc_note.text = ("live: listening on UDP %d — /vt/param/<id>, /vt/action/<id>; VIDEO_TOY_OSC_PORT overrides" % Osc.port) if Osc.listening else ("could not bind UDP %d (in use?) — pick another" % Osc.port)


func _save() -> void:
	if _key.text.strip_edges() == "" or _secret.text.strip_edges() == "":
		_status.text = "Both fields are needed."
		return
	Creds.save_creds(_key.text, _secret.text)
	_status.text = "Saved to user://noun_credentials.cfg. Now Test."


func _test() -> void:
	_status.text = "Testing…"
	NounApi.test_connection()


func _on_usage(ok: bool, usage: Dictionary, message: String) -> void:
	if ok:
		_status.text = "Connected. usage: " + JSON.stringify(usage)
	else:
		_status.text = "Failed: " + message
