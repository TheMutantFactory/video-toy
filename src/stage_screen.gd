extends Control
## Play mode. The world renders into a SubViewport; two more viewports ping-pong
## the previous frame back in (zoomed, rotated, faded) for classic video
## feedback — the "camera pointed at its own monitor" effect.
##
## Keys: 1-9 slot · Q W E R T Y U I verbs · click spawn · right-click remove
## · Space random spawn · P palette · F feedback · [ ] zoom · , . rotate
## · - = fade · O kaleidoscope · G chroma key (drop an image for the backdrop)
## · K pixelate · L palette quantise · J dither · V CRT · M monitor · N monitor size
## · drag the monitor to move it · B spawn a 3D solid of the selected icon
## · Shift+B next shape · ; MIDI + audio panel · A audio source (drop an audio file)
## · C clear · H help · Esc menu
##
## Render graph:  world3d (solids) ─> sprite in world
##                world (actors + monitor + world3d) ─┬─> screen ──┐
##                                          └─> acc A/B ─┘ (feedback ping-pong)
##                composite = bg + screen + fx  ──> display (stage) and monitor (world)

signal navigate(name: String)

const HotbarScript = preload("res://src/hotbar.gd")
const ActorScript = preload("res://src/actor.gd")
const FxScript = preload("res://src/fx.gd")
const MonitorScript = preload("res://src/monitor.gd")
const SolidScript = preload("res://src/solid.gd")
const MidiPanelScript = preload("res://src/midi_panel.gd")
const WORLD := Vector2i(1920, 1080)

var palette_index := 0
var feedback := false
var fb_zoom := 1.04
var fb_rot := 0.02
var fb_fade := 0.92

var _world: SubViewport
var _bg: ColorRect
var _actors: Node2D
var _acc: Array = []                    # two SubViewports
var _acc_prev: Array = []               # their "previous frame" sprites
var _acc_live: Array = []               # their "live world" sprites
var _flip := 0
var _screen: TextureRect
var _composite: SubViewport
var _display: TextureRect
var _monitor: Node2D
var _world3d: SubViewport
var _camera: Camera3D
var _solids: Node3D
var _shape_index := 0
var _midi_panel: PanelContainer
var _midi_last := ""
var _drag_offset := Vector2.ZERO
var _dragging := false
var _hud: Label
var _help: PanelContainer
var _verb_panel: VBoxContainer
var _verb_checks := {}
var _fx_pixel_btn: Button
var _fx_kaleido_btn: Button
var _fx_crt_btn: Button
var _fx_chroma: CheckButton
var _fx_quant: CheckButton
var _fx_dither: CheckButton
var _hotbar
var _fx


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# The final picture (bg + world/feedback + fx) renders into _composite so it
	# can be shown twice: on the stage, and on the monitor inside the world.
	_composite = SubViewport.new()
	_composite.size = WORLD
	_composite.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_composite.disable_3d = true
	add_child(_composite)
	# Background lives here, not in the world, so the world texture is
	# transparent except for actors — that is what lets feedback trails decay.
	_bg = ColorRect.new()
	_bg.size = Vector2(WORLD)
	_bg.color = Palettes.bg(palette_index)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite.add_child(_bg)

	_world = SubViewport.new()
	_world.size = WORLD
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world.transparent_bg = true
	_world.disable_3d = true
	add_child(_world)
	_build_3d()
	_actors = Node2D.new()
	_world.add_child(_actors)

	for i in 2:
		var vp := SubViewport.new()
		vp.size = WORLD
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.transparent_bg = true
		add_child(vp)
		var prev := Sprite2D.new()
		prev.position = Vector2(WORLD) * 0.5
		vp.add_child(prev)
		var live := Sprite2D.new()
		live.position = Vector2(WORLD) * 0.5
		live.texture = _world.get_texture()
		vp.add_child(live)
		_acc.append(vp)
		_acc_prev.append(prev)
		_acc_live.append(live)
	_acc_prev[0].texture = _acc[1].get_texture()
	_acc_prev[1].texture = _acc[0].get_texture()

	_screen = TextureRect.new()
	_screen.size = Vector2(WORLD)
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.texture = _world.get_texture()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite.add_child(_screen)

	_fx = FxScript.new()
	_composite.add_child(_fx)

	_display = TextureRect.new()
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_display.texture = _composite.get_texture()
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_display)

	_monitor = MonitorScript.new()
	_monitor.setup(_composite.get_texture(), Vector2(WORLD) * 0.5)
	_monitor.visible = false
	_world.add_child(_monitor)

	_build_hud()
	Toolbox.selection_changed.connect(func(_i): _refresh_verbs())
	Toolbox.changed.connect(_refresh_verbs)
	_refresh_verbs()
	_apply_palette()
	_refresh_fx()
	get_window().files_dropped.connect(_on_files_dropped)
	_build_midi()


func _exit_tree() -> void:
	if get_window() and get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)


# ---------------- 3D layer ----------------
## A transparent 3D viewport composited into the world as a sprite, so solids
## get feedback, effects and the monitor exactly like the 2D actors.
func _build_3d() -> void:
	_world3d = SubViewport.new()
	_world3d.size = WORLD
	_world3d.transparent_bg = true
	_world3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world3d.msaa_3d = Viewport.MSAA_2X
	add_child(_world3d)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 7.5)
	_camera.fov = 55.0
	_world3d.add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.4
	_world3d.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.environment.ambient_light_energy = 0.9
	_world3d.add_child(env)
	_solids = Node3D.new()
	_world3d.add_child(_solids)
	var sprite := Sprite2D.new()
	sprite.texture = _world3d.get_texture()
	sprite.position = Vector2(WORLD) * 0.5
	_world.add_child(sprite)


func next_shape() -> String:
	return SolidScript.SHAPES[_shape_index]


func spawn_solid(world_pos := Vector2(-1, -1)) -> void:
	var slot := Toolbox.current()
	if slot.is_empty():
		return
	var pos: Vector3
	if world_pos.x < 0:
		pos = Vector3(randf_range(-3.5, 3.5), randf_range(-1.8, 1.8), randf_range(-1.5, 1.0))
	else:
		pos = _camera.project_position(world_pos, _camera.position.z)
	var sol := Node3D.new()
	sol.set_script(SolidScript)
	sol.setup(slot, next_shape(), pos, palette_index, IconMedia.texture_for(str(slot.get("svg_path", ""))))
	_solids.add_child(sol)
	_update_hud()


func cycle_shape() -> void:
	_shape_index = (_shape_index + 1) % SolidScript.SHAPES.size()
	_update_hud()


# ---------------- MIDI ----------------
## Continuous params: id, label, setter(0..1). Actions: id, label, callable.
func midi_params() -> Array:
	return [
		{"id": "fb_zoom", "label": "Feedback zoom", "set": func(v): fb_zoom = lerpf(0.90, 1.20, v)},
		{"id": "fb_twist", "label": "Feedback twist", "set": func(v): fb_rot = lerpf(-0.15, 0.15, v)},
		{"id": "fb_fade", "label": "Feedback fade", "set": func(v): fb_fade = lerpf(0.5, 0.995, v)},
		{"id": "pixelate", "label": "Pixelate size", "set": func(v):
			_fx.pixel_step = _step(v, _fx.PIXEL_STEPS.size())
			_fx._push()
			_refresh_fx()},
		{"id": "kaleido", "label": "Kaleidoscope", "set": func(v):
			_fx.kaleido_step = _step(v, _fx.KALEIDO_STEPS.size())
			_fx._push()
			_refresh_fx()},
		{"id": "crt", "label": "CRT", "set": func(v):
			_fx.crt_level = _step(v, 3)
			_fx._push()
			_refresh_fx()},
		{"id": "monitor", "label": "Monitor size", "set": func(v):
			_monitor.size_step = _step(v, _monitor.SIZES.size())
			_monitor._apply_scale()},
		{"id": "palette", "label": "Palette", "set": func(v):
			var i := _step(v, Palettes.count())
			if i != palette_index:
				palette_index = i
				_apply_palette()},
		{"id": "slot", "label": "Toolbox slot", "set": func(v):
			if not Toolbox.slots.is_empty():
				Toolbox.select(_step(v, Toolbox.slots.size()))},
		{"id": "audio_gain", "label": "Audio gain", "set": func(v): AudioReact.gain = lerpf(0.25, 4.0, v)},
	]


func midi_actions() -> Array:
	var out: Array = [
		{"id": "spawn", "label": "Spawn icon", "do": func(): spawn_at(Vector2(randf_range(100, WORLD.x - 100), randf_range(100, WORLD.y - 100)))},
		{"id": "spawn_solid", "label": "Spawn 3D solid", "do": func(): spawn_solid()},
		{"id": "clear", "label": "Clear stage", "do": func():
			for a in _actors.get_children() + _solids.get_children():
				a.queue_free()},
		{"id": "feedback", "label": "Feedback on/off", "do": func(): _set_feedback(not feedback)},
		{"id": "next_palette", "label": "Next palette", "do": func():
			palette_index = (palette_index + 1) % Palettes.count()
			_apply_palette()},
		{"id": "chroma", "label": "Chroma key on/off", "do": func():
			_fx.toggle_chroma()
			_refresh_fx()},
		{"id": "quantise", "label": "Palette quantise on/off", "do": func():
			_fx.toggle_quantize()
			_refresh_fx()},
		{"id": "dither", "label": "Dither on/off", "do": func():
			_fx.toggle_dither()
			_refresh_fx()},
		{"id": "monitor", "label": "Monitor on/off", "do": func(): set_monitor(not _monitor.visible)},
		{"id": "next_shape", "label": "Next 3D shape", "do": cycle_shape},
		{"id": "audio_source", "label": "Next audio source", "do": func():
			AudioReact.cycle_source()
			_update_hud()},
		{"id": "recolor", "label": "Recolor slot", "do": _recolor},
	]
	for i in Toolbox.MAX_SLOTS:
		out.append({"id": "slot_%d" % (i + 1), "label": "Select slot %d" % (i + 1), "do": func(): Toolbox.select(i)})
	for v in Verbs.ALL:
		out.append({"id": "verb_" + v["id"], "label": "Toggle verb: " + v["name"], "do": func():
			if not Toolbox.current().is_empty():
				Toolbox.toggle_verb(Toolbox.selected, v["id"])})
	return out


static func _step(v: float, n: int) -> int:
	return clampi(int(floor(v * n)), 0, n - 1)


func _build_midi() -> void:
	_midi_panel = MidiPanelScript.new()
	_midi_panel.params = midi_params()
	_midi_panel.actions = midi_actions()
	_midi_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_midi_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_midi_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_midi_panel.visible = false
	add_child(_midi_panel)
	MidiMap.param.connect(_on_midi_param)
	MidiMap.action.connect(_on_midi_action)
	MidiMap.activity.connect(func(text):
		_midi_last = text
		_update_hud())


func _on_midi_param(id: String, value: float) -> void:
	for p in midi_params():
		if p["id"] == id:
			p["set"].call(value)
			_update_hud()
			return


func _on_midi_action(id: String) -> void:
	for a in midi_actions():
		if a["id"] == id:
			a["do"].call()
			_update_hud()
			return


func toggle_midi_panel() -> void:
	_midi_panel.visible = not _midi_panel.visible
	if _midi_panel.visible:
		_midi_panel.refresh()
	else:
		MidiMap.disarm()


# ---------------- HUD ----------------
func _build_hud() -> void:
	var hud_card := PanelContainer.new()
	hud_card.position = Vector2(12, 8)
	add_child(hud_card)
	_hud = UI.label("", 18, UI.DIM)
	hud_card.add_child(_hud)

	# Verb panel sits on a translucent card so it reads on light palettes too.
	var card := PanelContainer.new()
	card.position = Vector2(12, 96)
	add_child(card)
	_verb_panel = VBoxContainer.new()
	_verb_panel.add_theme_constant_override("separation", 2)
	card.add_child(_verb_panel)
	_verb_panel.add_child(UI.label("Verbs for selected slot", 18, UI.ACCENT))
	for v in Verbs.ALL:
		var cb := CheckButton.new()
		cb.text = "%s  %s" % [v["key"], v["name"]]
		cb.tooltip_text = v["hint"]
		cb.toggled.connect(func(_on): Toolbox.toggle_verb(Toolbox.selected, v["id"]))
		_verb_panel.add_child(cb)
		_verb_checks[v["id"]] = cb
	_verb_panel.add_child(UI.vspace(6))
	_verb_panel.add_child(UI.label("Effects", 18, UI.ACCENT))
	_fx_kaleido_btn = UI.button("", func():
		_fx.cycle_kaleido()
		_refresh_fx())
	_verb_panel.add_child(_fx_kaleido_btn)
	_fx_chroma = CheckButton.new()
	_fx_chroma.text = "G  Chroma key"
	_fx_chroma.tooltip_text = "Keys out the palette background. Drop an image on the window for the backdrop; plasma otherwise."
	_fx_chroma.toggled.connect(func(_on):
		_fx.toggle_chroma()
		_refresh_fx())
	_verb_panel.add_child(_fx_chroma)
	_fx_pixel_btn = UI.button("", func():
		_fx.cycle_pixelate()
		_refresh_fx())
	_verb_panel.add_child(_fx_pixel_btn)
	_fx_quant = CheckButton.new()
	_fx_quant.text = "L  Palette quantise"
	_fx_quant.toggled.connect(func(_on):
		_fx.toggle_quantize()
		_refresh_fx())
	_verb_panel.add_child(_fx_quant)
	_fx_dither = CheckButton.new()
	_fx_dither.text = "J  Dither"
	_fx_dither.toggled.connect(func(_on):
		_fx.toggle_dither()
		_refresh_fx())
	_verb_panel.add_child(_fx_dither)
	_fx_crt_btn = UI.button("", func():
		_fx.cycle_crt()
		_refresh_fx())
	_verb_panel.add_child(_fx_crt_btn)
	_verb_panel.add_child(UI.vspace(6))
	_verb_panel.add_child(UI.button("Recolor slot (X)", func(): _recolor()))
	_verb_panel.add_child(UI.button("Remove slot (Del)", func(): Toolbox.remove(Toolbox.selected)))

	_help = PanelContainer.new()
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help.grow_vertical = Control.GROW_DIRECTION_BOTH
	_help.offset_right = -20
	var hl := UI.label(
		"click        spawn selected icon\nright-click  remove nearest\nSpace        spawn somewhere\n"
		+ "1-9          select slot\nQ..I         toggle verbs\nX            recolor slot\n"
		+ "P            next palette\nF            feedback on/off\n[ ]          feedback zoom\n"
		+ ", .          feedback twist\n- =          feedback fade\nO            kaleidoscope\n"
		+ "G            chroma key (drop image = backdrop)\nK            pixelate size\n"
		+ "L            palette quantise\nJ            dither\nV            CRT off/soft/heavy\n"
		+ "M            monitor in the scene\nN            monitor size (drag to move)\n"
		+ "B            3D solid of selected icon at mouse\nShift+B      next shape\n"
		+ ";            MIDI + audio panel\nA            audio: off/mic/test/file (drop mp3/ogg/wav)\n"
		+ "C            clear stage\n"
		+ "H            hide this\nEsc          menu / attribution", 16)
	_help.add_child(hl)
	add_child(_help)

	var top_right := HBoxContainer.new()
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.offset_right = -20
	top_right.offset_top = 14
	top_right.add_child(UI.button("Find Icons", func(): navigate.emit("search")))
	top_right.add_child(UI.hspace(8))
	top_right.add_child(UI.button("← Back", func(): navigate.emit("start")))
	add_child(top_right)

	_hotbar = HotbarScript.new()
	_hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hotbar.offset_bottom = -20
	add_child(_hotbar)


func _refresh_verbs() -> void:
	var idx := Toolbox.selected
	var has := not Toolbox.current().is_empty()
	for id in _verb_checks:
		var cb: CheckButton = _verb_checks[id]
		cb.disabled = not has
		cb.set_pressed_no_signal(Toolbox.has_verb(idx, id))
	_update_hud()


func _refresh_fx() -> void:
	_fx_kaleido_btn.text = "O  Kaleidoscope: %s" % ("off" if _fx.kaleido_step == 0 else "%d" % _fx.kaleido_segments())
	_fx_chroma.set_pressed_no_signal(_fx.chroma)
	_fx_crt_btn.text = "V  CRT: %s" % ["off", "soft", "heavy"][_fx.crt_level]
	_fx_pixel_btn.text = "K  Pixelate: %s" % ("off" if _fx.pixel_step == 0 else "%d px" % _fx.pixel_size())
	_fx_quant.set_pressed_no_signal(_fx.quantize)
	_fx_dither.set_pressed_no_signal(_fx.dither)
	_fx_dither.disabled = not _fx.quantize
	_update_hud()


func set_monitor(on: bool, size_step := -1) -> void:
	_monitor.visible = on
	if size_step >= 0:
		_monitor.size_step = size_step
		_monitor._apply_scale()
	_update_hud()


## Used by --capture.
func set_fx(pixel: int, quant: bool, dith: bool, kaleido := 0, chroma := false, crt := 0) -> void:
	_fx.set_state(pixel, quant, dith, kaleido, chroma, crt)
	_refresh_fx()


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		var ext := f.get_extension().to_lower()
		if ext in ["png", "jpg", "jpeg", "webp", "bmp"]:
			if _fx.set_backdrop_from_file(f):
				if not _fx.chroma:
					_fx.toggle_chroma()
				_refresh_fx()
			return
		if ext in ["mp3", "ogg", "wav"]:
			AudioReact.load_file(f)
			_update_hud()
			return


func _update_hud() -> void:
	var cur := Toolbox.current()
	var name := str(cur.get("term", "—")) if not cur.is_empty() else "empty toolbox — press Find Icons"
	_hud.text = "slot %d: %s   ·   palette: %s   ·   feedback: %s   ·   fx: %s   ·   monitor: %s   ·   actors: %d" % [
		Toolbox.selected + 1, name, Palettes.get_palette(palette_index)["name"],
		("zoom %.2f  twist %.2f  fade %.2f" % [fb_zoom, fb_rot, fb_fade]) if feedback else "off",
		_fx.describe(), ("%.0f%%" % (_monitor.scale_factor() * 100.0)) if _monitor.visible else "off",
		_actors.get_child_count()] + "   ·   solids: %d (next: %s)" % [_solids.get_child_count(), next_shape()]
	# second line: controllers
	var line2 := "midi: " + (_midi_last if _midi_last != "" else "—")
	line2 += "   ·   audio: " + ((("%s  %s" % [AudioReact.source if AudioReact.source != "file" else AudioReact.file_name, _meter()])) if AudioReact.active() else "off (A)")
	if AudioReact.driver_missing():
		line2 += "   ·   no audio device: mic/file unavailable"
	_hud.text += "\n" + line2


static func _bar(v: float) -> String:
	var n := clampi(roundi(v * 5.0), 0, 5)
	return "▮".repeat(n) + "▯".repeat(5 - n)


func _meter() -> String:
	return "bass %s mid %s high %s" % [_bar(AudioReact.bass), _bar(AudioReact.mid), _bar(AudioReact.high)]


# ---------------- palette / feedback ----------------
func _apply_palette() -> void:
	_bg.color = Palettes.bg(palette_index)
	_fx.set_palette(palette_index)
	_monitor.accent = Palettes.color(palette_index, 0)
	_monitor.queue_redraw()
	_hotbar.palette_index = palette_index
	_hotbar.refresh()
	for a in _actors.get_children() + _solids.get_children():
		var i := Toolbox.index_of(a.slot_id)
		if i >= 0:
			a.set_palette(palette_index, int(Toolbox.slots[i].get("color_index", i)))
	_update_hud()


func _recolor() -> void:
	Toolbox.cycle_color(Toolbox.selected)
	_apply_palette()


func _set_feedback(on: bool) -> void:
	feedback = on
	if not on:
		_screen.texture = _world.get_texture()
		for vp in _acc:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_update_hud()


func _process(_delta: float) -> void:
	var mouse := _world_pos(get_local_mouse_position())
	for a in _actors.get_children():
		a.mouse_world = mouse
	if _solids.get_child_count() > 0:
		var mp := _camera.project_position(mouse, _camera.position.z)
		for sol in _solids.get_children():
			sol.mouse_point = mp
	if feedback:
		var cur: int = _flip
		_flip = 1 - _flip
		var prev: Sprite2D = _acc_prev[cur]
		prev.scale = Vector2.ONE * fb_zoom
		prev.rotation = fb_rot
		prev.modulate = Color(1, 1, 1, fb_fade)
		_acc[1 - cur].render_target_update_mode = SubViewport.UPDATE_DISABLED
		_acc[cur].render_target_update_mode = SubViewport.UPDATE_ONCE
		_screen.texture = _acc[cur].get_texture()
	if Engine.get_process_frames() % (4 if AudioReact.active() else 15) == 0:
		_update_hud()


# ---------------- spawning ----------------
func _world_pos(local: Vector2) -> Vector2:
	# Map the on-screen rect (keep-aspect centred) back to world pixels.
	var rect := _display.get_rect()
	var scale := minf(rect.size.x / WORLD.x, rect.size.y / WORLD.y)
	var drawn := Vector2(WORLD) * scale
	var origin := rect.position + (rect.size - drawn) * 0.5
	return (local - origin) / scale


func spawn_at(world_pos: Vector2) -> void:
	var slot := Toolbox.current()
	if slot.is_empty():
		return
	var a := Node2D.new()
	a.set_script(ActorScript)
	a.setup(slot, world_pos, palette_index, Rect2(Vector2.ZERO, Vector2(WORLD)))
	_actors.add_child(a)
	_update_hud()


func demo_spawn() -> void:
	## Used by --capture: a few actors with verbs on, so the screenshot shows something.
	if Toolbox.slots.is_empty():
		return
	for i in 12:
		Toolbox.select(i % Toolbox.slots.size())
		spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))


func _remove_nearest(world_pos: Vector2) -> void:
	var best: Node2D = null
	var best_d := 1e9
	for a in _actors.get_children():
		var d: float = a.position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = a
	for sol in _solids.get_children():
		var d: float = _camera.unproject_position(sol.position).distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = sol
	if best and best_d < 160.0:
		best.queue_free()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var wp := _world_pos(ev.position)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				if _monitor.visible and _monitor.contains(wp):
					_dragging = true
					_drag_offset = _monitor.position - wp
				else:
					spawn_at(wp)
			else:
				_dragging = false
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			_remove_nearest(wp)
	elif ev is InputEventMouseMotion and _dragging:
		_monitor.position = _world_pos(ev.position) + _drag_offset


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed):
		return
	var k: int = ev.keycode
	if k >= KEY_1 and k <= KEY_9:
		Toolbox.select(k - KEY_1)
		return
	var verb := Verbs.by_key(k)
	if verb != "" and not Toolbox.current().is_empty():
		Toolbox.toggle_verb(Toolbox.selected, verb)
		return
	match k:
		KEY_SPACE: spawn_at(Vector2(randf_range(100, WORLD.x - 100), randf_range(100, WORLD.y - 100)))
		KEY_P:
			palette_index = (palette_index + 1) % Palettes.count()
			_apply_palette()
		KEY_X: _recolor()
		KEY_DELETE, KEY_BACKSPACE: Toolbox.remove(Toolbox.selected)
		KEY_F: _set_feedback(not feedback)
		KEY_BRACKETLEFT: fb_zoom = maxf(0.90, fb_zoom - 0.01)
		KEY_BRACKETRIGHT: fb_zoom = minf(1.20, fb_zoom + 0.01)
		KEY_COMMA: fb_rot -= 0.01
		KEY_PERIOD: fb_rot += 0.01
		KEY_B:
			if ev.shift_pressed:
				cycle_shape()
			else:
				spawn_solid(_world_pos(get_local_mouse_position()) if get_global_rect().has_point(get_global_mouse_position()) else Vector2(-1, -1))
		KEY_SEMICOLON: toggle_midi_panel()
		KEY_A:
			AudioReact.cycle_source()
			_update_hud()
		KEY_M: set_monitor(not _monitor.visible)
		KEY_N:
			_monitor.cycle_size()
			_update_hud()
		KEY_V:
			_fx.cycle_crt()
			_refresh_fx()
		KEY_O:
			_fx.cycle_kaleido()
			_refresh_fx()
		KEY_G:
			_fx.toggle_chroma()
			_refresh_fx()
		KEY_K:
			_fx.cycle_pixelate()
			_refresh_fx()
		KEY_L:
			_fx.toggle_quantize()
			_refresh_fx()
		KEY_J:
			_fx.toggle_dither()
			_refresh_fx()
		KEY_MINUS: fb_fade = maxf(0.5, fb_fade - 0.02)
		KEY_EQUAL: fb_fade = minf(0.995, fb_fade + 0.02)
		KEY_C:
			for a in _actors.get_children() + _solids.get_children():
				a.queue_free()
		KEY_H:
			_help.visible = not _help.visible
			_verb_panel.get_parent().visible = _help.visible
			_hud.get_parent().visible = _help.visible
	_update_hud()
