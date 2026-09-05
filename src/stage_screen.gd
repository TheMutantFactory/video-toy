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
## · drop an image = raster slot (Shift+drop = chroma backdrop) · Z webcam layer
## · S steal a palette from the selected raster / webcam · D glow
## · F1-F12 recall preset · Shift+F1-F12 save preset · Tab / Shift+Tab next / previous scene
## · ` scene off · arrows feedback drift · PgUp/PgDn feedback warp · Home reset warp
## · Shift+arrows camera orbit / dolly · Shift+PgUp/PgDn camera roll · Shift+Home reset camera
## · Shift+Space spawn a formation (Shift+X next formation) · C clear · H help · Esc menu
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
const WebcamScript = preload("res://src/webcam.gd")
const GlowScript = preload("res://src/glow.gd")
const SceneLayerScript = preload("res://src/scene_layer.gd")
const FormationScript = preload("res://src/formation.gd")
const WEBCAM_MODES := ["off", "layer", "backdrop"]
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
var _webcam: Node2D
var _webcam_vp: SubViewport
var _webcam_sprite: Sprite2D
var _webcam_mode := 0
var _steal_note := ""
var _glow
var _fade_tween: Tween
var _scene_layer: Node2D
var _acc_mats: Array = []               # warp ShaderMaterials, one per accumulator
var fb_warp := 0.0
var fb_warp_speed := 1.0
var fb_drift := Vector2.ZERO
var fb_stretch := Vector2.ONE
var cam_orbit := 0.0                    # rad/s around the origin
var cam_dolly := 7.5                    # distance
var cam_roll := 0.0
var cam_height := 0.0
var _cam_angle := 0.0
var _formations: Node3D
var _formation_index := 0
var _drag_offset := Vector2.ZERO
var _dragging := false
var _hud: Label
var _help: PanelContainer
var _verb_panel: VBoxContainer
var _verb_checks := {}
var _fx_pixel_btn: Button
var _fx_kaleido_btn: Button
var _fx_crt_btn: Button
var _fx_glow_btn: Button
var _fx_scene_btn: Button
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
	_scene_layer = SceneLayerScript.new()
	_scene_layer.size = Vector2(WORLD)
	_world.add_child(_scene_layer)
	_build_webcam()
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
		var prev := MeshInstance2D.new()          # the warp mesh (see feedback_mesh.gd)
		prev.mesh = FeedbackMesh.build(Vector2(WORLD))
		prev.material = FeedbackMesh.material()
		prev.position = Vector2(WORLD) * 0.5
		vp.add_child(prev)
		_acc_mats.append(prev.material)
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

	_glow = GlowScript.new()                     # bloom before fx, so CRT sees it
	_composite.add_child(_glow)

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


# ---------------- webcam ----------------
## The camera renders into its own viewport so one RGB texture serves both the
## world layer (behind everything, so it feeds back and gets the effects) and
## the chroma-key backdrop.
func _build_webcam() -> void:
	_webcam_vp = SubViewport.new()
	_webcam_vp.size = Vector2i(960, 540)
	_webcam_vp.transparent_bg = false
	_webcam_vp.disable_3d = true
	_webcam_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_webcam_vp)
	_webcam = WebcamScript.new()
	_webcam.box = Vector2(960, 540)
	_webcam.position = Vector2(480, 270)
	_webcam.set_process(false)
	_webcam_vp.add_child(_webcam)
	_webcam_sprite = Sprite2D.new()
	_webcam_sprite.texture = _webcam_vp.get_texture()
	_webcam_sprite.position = Vector2(WORLD) * 0.5
	_webcam_sprite.scale = Vector2(2, 2)
	_webcam_sprite.z_index = -2
	_webcam_sprite.visible = false
	_world.add_child(_webcam_sprite)


func webcam_mode() -> String:
	return WEBCAM_MODES[_webcam_mode]


func set_webcam_mode(i: int) -> void:
	_webcam_mode = posmod(i, WEBCAM_MODES.size())
	var on := _webcam_mode > 0
	_webcam.set_process(on)
	if on:
		_webcam.start()
	else:
		_webcam.stop()
	_webcam_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_webcam_sprite.visible = webcam_mode() == "layer"
	_fx.set_live_backdrop(_webcam_vp.get_texture() if webcam_mode() == "backdrop" else null)
	if webcam_mode() == "backdrop" and not _fx.chroma:
		_fx.toggle_chroma()
	_refresh_fx()


func cycle_webcam() -> void:
	set_webcam_mode(_webcam_mode + 1)


## S: a palette from the selected raster slot, or the webcam if it is on.
func steal_palette() -> void:
	var img: Image = null
	var name := ""
	var slot := Toolbox.current()
	if _webcam_mode > 0 and _webcam.is_live():
		img = _webcam_vp.get_texture().get_image()
		name = "Webcam"
	elif not slot.is_empty() and Toolbox.is_raster_slot(slot):
		var tex := IconMedia.texture_for(str(slot.get("svg_path", "")))
		if tex:
			img = tex.get_image()
			name = str(slot.get("term", "image")).capitalize()
	if img == null:
		_steal_note = "select a raster slot (or turn the webcam on) to steal a palette"
		_update_hud()
		return
	var p := Palettes.extract(img, name)
	palette_index = Palettes.add_extra(p)
	_apply_palette()
	_steal_note = "stole palette “%s” (%d colours)" % [name, p["ring"].size()]
	_update_hud()


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
	_formations = Node3D.new()
	_world3d.add_child(_formations)
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
		pos = _camera.project_position(world_pos, cam_dolly)
	var sol := Node3D.new()
	sol.set_script(SolidScript)
	sol.setup(slot, next_shape(), pos, palette_index, IconMedia.texture_for(str(slot.get("svg_path", ""))))
	_solids.add_child(sol)
	_update_hud()


func formation_kind() -> String:
	return FormationScript.KINDS[_formation_index]


func cycle_formation() -> void:
	_formation_index = (_formation_index + 1) % FormationScript.KINDS.size()
	_update_hud()


## Shift+Space: 200 copies of the selected icon in the current shape and formation.
func spawn_formation(n := 200) -> void:
	var slot := Toolbox.current()
	if slot.is_empty():
		return
	var icon := IconMedia.texture_for(str(slot.get("svg_path", "")))
	var mesh: Mesh = SolidScript.make_mesh(next_shape(), icon.get_image() if (next_shape() == "cookie" and icon) else null)
	var skin := StandardMaterial3D.new()
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	skin.alpha_scissor_threshold = 0.5
	skin.albedo_texture = icon
	skin.uv1_scale = SolidScript.uv_scale(next_shape())
	skin.texture_repeat = true
	skin.vertex_color_use_as_albedo = true
	var body := StandardMaterial3D.new()
	body.roughness = 0.55
	body.vertex_color_use_as_albedo = true
	body.albedo_color = Color(0.35, 0.35, 0.35)
	var f := Node3D.new()
	f.set_script(FormationScript)
	f.setup(slot, formation_kind(), mesh, [skin, body], n, palette_index)
	_formations.add_child(f)
	_update_hud()


func reset_camera() -> void:
	cam_orbit = 0.0
	cam_dolly = 7.5
	cam_roll = 0.0
	cam_height = 0.0
	_cam_angle = 0.0
	_update_hud()


func cycle_shape() -> void:
	_shape_index = (_shape_index + 1) % SolidScript.SHAPES.size()
	_update_hud()


# ---------------- scenes ----------------
func set_scene(id: String, fade := 0.8) -> void:
	Scenes.current = id
	_scene_layer.refresh(fade)
	_update_hud()


func step_scene(step: int) -> void:
	set_scene(Scenes.neighbour(Scenes.current, step))


func set_scene_knobs(speed: float, scale: float, bias: float) -> void:
	Scenes.speed = speed
	Scenes.scale = scale
	Scenes.bias = bias
	_scene_layer.apply_knobs()
	_update_hud()


# ---------------- presets ----------------
## Everything the stage remembers, as plain data.
func snapshot() -> Dictionary:
	var verbs := {}
	for sl in Toolbox.slots:
		verbs[str(sl["id"])] = {"verbs": sl.get("verbs", []).duplicate(), "color_index": int(sl.get("color_index", 0))}
	return {
		"palette": palette_index,
		"feedback": {"on": feedback, "zoom": fb_zoom, "rot": fb_rot, "fade": fb_fade},
		"fx": {"pixel": _fx.pixel_step, "kaleido": _fx.kaleido_step, "crt": _fx.crt_level,
			"chroma": _fx.chroma, "quantize": _fx.quantize, "dither": _fx.dither},
		"glow": _glow.level,
		"monitor": {"on": _monitor.visible, "size": _monitor.size_step, "x": _monitor.position.x, "y": _monitor.position.y},
		"webcam": _webcam_mode,
		"shape": _shape_index,
		"selected": Toolbox.selected,
		"slots": verbs,
		"scene": {"id": Scenes.current, "speed": Scenes.speed, "scale": Scenes.scale, "bias": Scenes.bias},
		"warp": {"amount": fb_warp, "speed": fb_warp_speed, "dx": fb_drift.x, "dy": fb_drift.y, "sx": fb_stretch.x, "sy": fb_stretch.y},
		"camera": {"orbit": cam_orbit, "dolly": cam_dolly, "roll": cam_roll, "height": cam_height},
		"formation": _formation_index,
	}


## Apply a snapshot. Continuous feedback params crossfade over `fade` seconds.
func restore(d: Dictionary, fade := 1.0) -> void:
	if d.is_empty():
		return
	palette_index = posmod(int(d.get("palette", palette_index)), Palettes.count())
	var fb: Dictionary = d.get("feedback", {})
	if _fade_tween:
		_fade_tween.kill()
	if fade > 0.0 and feedback and bool(fb.get("on", feedback)):
		_fade_tween = create_tween().set_parallel(true)
		_fade_tween.tween_property(self, "fb_zoom", float(fb.get("zoom", fb_zoom)), fade)
		_fade_tween.tween_property(self, "fb_rot", float(fb.get("rot", fb_rot)), fade)
		_fade_tween.tween_property(self, "fb_fade", float(fb.get("fade", fb_fade)), fade)
	else:
		fb_zoom = float(fb.get("zoom", fb_zoom))
		fb_rot = float(fb.get("rot", fb_rot))
		fb_fade = float(fb.get("fade", fb_fade))
	_set_feedback(bool(fb.get("on", feedback)))
	var fx: Dictionary = d.get("fx", {})
	_fx.pixel_step = clampi(int(fx.get("pixel", _fx.pixel_step)), 0, _fx.PIXEL_STEPS.size() - 1)
	_fx.kaleido_step = clampi(int(fx.get("kaleido", _fx.kaleido_step)), 0, _fx.KALEIDO_STEPS.size() - 1)
	_fx.crt_level = clampi(int(fx.get("crt", _fx.crt_level)), 0, 2)
	_fx.chroma = bool(fx.get("chroma", _fx.chroma))
	_fx.quantize = bool(fx.get("quantize", _fx.quantize))
	_fx.dither = bool(fx.get("dither", _fx.dither))
	_fx._push()
	_glow.set_level(int(d.get("glow", _glow.level)))
	var mon: Dictionary = d.get("monitor", {})
	_monitor.size_step = clampi(int(mon.get("size", _monitor.size_step)), 0, _monitor.SIZES.size() - 1)
	_monitor._apply_scale()
	_monitor.position = Vector2(float(mon.get("x", _monitor.position.x)), float(mon.get("y", _monitor.position.y)))
	_monitor.visible = bool(mon.get("on", _monitor.visible))
	set_webcam_mode(int(d.get("webcam", _webcam_mode)))
	_shape_index = posmod(int(d.get("shape", _shape_index)), SolidScript.SHAPES.size())
	var slots: Dictionary = d.get("slots", {})
	for i in Toolbox.slots.size():
		var rec = slots.get(str(Toolbox.slots[i]["id"]))
		if rec is Dictionary:
			Toolbox.slots[i]["verbs"] = Array(rec.get("verbs", [])).duplicate()
			Toolbox.slots[i]["color_index"] = int(rec.get("color_index", Toolbox.slots[i].get("color_index", 0)))
	Toolbox.save_to_disk()
	Toolbox.changed.emit()
	Toolbox.select(int(d.get("selected", Toolbox.selected)))
	var sc: Dictionary = d.get("scene", {})
	if not sc.is_empty():
		set_scene_knobs(float(sc.get("speed", Scenes.speed)), float(sc.get("scale", Scenes.scale)), float(sc.get("bias", Scenes.bias)))
		set_scene(str(sc.get("id", Scenes.current)), fade)
	var cam: Dictionary = d.get("camera", {})
	if not cam.is_empty():
		cam_orbit = float(cam.get("orbit", cam_orbit))
		cam_dolly = float(cam.get("dolly", cam_dolly))
		cam_roll = float(cam.get("roll", cam_roll))
		cam_height = float(cam.get("height", cam_height))
	_formation_index = posmod(int(d.get("formation", _formation_index)), FormationScript.KINDS.size())
	var w: Dictionary = d.get("warp", {})
	if not w.is_empty():
		fb_warp = float(w.get("amount", fb_warp))
		fb_warp_speed = float(w.get("speed", fb_warp_speed))
		fb_drift = Vector2(float(w.get("dx", fb_drift.x)), float(w.get("dy", fb_drift.y)))
		fb_stretch = Vector2(float(w.get("sx", fb_stretch.x)), float(w.get("sy", fb_stretch.y)))
	_apply_palette()
	_refresh_fx()


func save_preset(i: int) -> void:
	Presets.save(i, snapshot())
	_steal_note = "saved preset %d (F%d)" % [i, i]
	_update_hud()


func recall_preset(i: int) -> void:
	var d := Presets.get_preset(i)
	if d.is_empty():
		_steal_note = "preset %d is empty — Shift+F%d saves" % [i, i]
	else:
		restore(d)
		_steal_note = "preset %d" % i
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
		{"id": "glow", "label": "Glow", "set": func(v):
			_glow.set_level(_step(v, 3))
			_update_hud()},
		{"id": "scene", "label": "Scene", "set": func(v):
			var n := Scenes.ALL.size() + 1
			var i := _step(v, n)
			set_scene("" if i == 0 else Scenes.ALL[i - 1]["id"])},
		{"id": "scene_speed", "label": "Scene speed", "set": func(v): set_scene_knobs(lerpf(0.1, 4.0, v), Scenes.scale, Scenes.bias)},
		{"id": "scene_scale", "label": "Scene scale", "set": func(v): set_scene_knobs(Scenes.speed, lerpf(0.3, 4.0, v), Scenes.bias)},
		{"id": "scene_bias", "label": "Scene colour bias", "set": func(v): set_scene_knobs(Scenes.speed, Scenes.scale, v)},
		{"id": "fb_warp", "label": "Feedback warp", "set": func(v): fb_warp = v},
		{"id": "fb_warp_speed", "label": "Feedback warp speed", "set": func(v): fb_warp_speed = lerpf(0.1, 4.0, v)},
		{"id": "fb_dx", "label": "Feedback drift X", "set": func(v): fb_drift.x = lerpf(-6.0, 6.0, v)},
		{"id": "fb_dy", "label": "Feedback drift Y", "set": func(v): fb_drift.y = lerpf(-6.0, 6.0, v)},
		{"id": "fb_sx", "label": "Feedback stretch X", "set": func(v): fb_stretch.x = lerpf(0.9, 1.1, v)},
		{"id": "fb_sy", "label": "Feedback stretch Y", "set": func(v): fb_stretch.y = lerpf(0.9, 1.1, v)},
		{"id": "cam_orbit", "label": "Camera orbit speed", "set": func(v): cam_orbit = lerpf(-1.5, 1.5, v)},
		{"id": "cam_dolly", "label": "Camera dolly", "set": func(v): cam_dolly = lerpf(3.0, 14.0, v)},
		{"id": "cam_roll", "label": "Camera roll", "set": func(v): cam_roll = lerpf(-PI, PI, v)},
		{"id": "cam_height", "label": "Camera height", "set": func(v): cam_height = lerpf(-4.0, 4.0, v)},
	]


func midi_actions() -> Array:
	var out: Array = [
		{"id": "spawn", "label": "Spawn icon", "do": func(): spawn_at(Vector2(randf_range(100, WORLD.x - 100), randf_range(100, WORLD.y - 100)))},
		{"id": "spawn_solid", "label": "Spawn 3D solid", "do": func(): spawn_solid()},
		{"id": "clear", "label": "Clear stage", "do": func():
			for a in _actors.get_children() + _solids.get_children() + _formations.get_children():
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
		{"id": "webcam", "label": "Next webcam mode", "do": cycle_webcam},
		{"id": "steal_palette", "label": "Steal palette", "do": steal_palette},
		{"id": "audio_source", "label": "Next audio source", "do": func():
			AudioReact.cycle_source()
			_update_hud()},
		{"id": "recolor", "label": "Recolor slot", "do": _recolor},
	]
	out.append({"id": "spawn_formation", "label": "Spawn formation", "do": func(): spawn_formation()})
	out.append({"id": "next_formation", "label": "Next formation kind", "do": cycle_formation})
	out.append({"id": "cam_reset", "label": "Reset camera", "do": reset_camera})
	out.append({"id": "cam_auto", "label": "Camera slow orbit on/off", "do": func():
		cam_orbit = 0.0 if cam_orbit != 0.0 else 0.35
		_update_hud()})
	out.append({"id": "next_scene", "label": "Next scene", "do": func(): step_scene(1)})
	out.append({"id": "prev_scene", "label": "Previous scene", "do": func(): step_scene(-1)})
	out.append({"id": "scene_off", "label": "Scene off", "do": func(): set_scene("")})
	out.append({"id": "warp_reset", "label": "Reset feedback warp", "do": func():
		fb_warp = 0.0
		fb_drift = Vector2.ZERO
		fb_stretch = Vector2.ONE
		_update_hud()})
	out.append({"id": "glow", "label": "Glow off/soft/heavy", "do": func():
		_glow.cycle()
		_update_hud()})
	for i in Presets.COUNT:
		out.append({"id": "preset_%d" % (i + 1), "label": "Recall preset %d" % (i + 1), "do": func(): recall_preset(i + 1)})
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
	_fx_glow_btn = UI.button("", func():
		_glow.cycle()
		_refresh_fx())
	_verb_panel.add_child(_fx_glow_btn)
	_fx_scene_btn = UI.button("", func(): step_scene(1))
	_fx_scene_btn.tooltip_text = "Tab / Shift+Tab; ` turns it off"
	_verb_panel.add_child(_fx_scene_btn)
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
		+ "drop image   raster slot (Shift+drop: chroma backdrop)\nZ            webcam: off/layer/backdrop\n"
		+ "S            steal palette from raster / webcam\nD            glow off/soft/heavy\n"
		+ "F1-F12       recall preset · Shift+F saves\n"
		+ "Tab          next scene (Shift: previous) · ` off\narrows       feedback drift · PgUp/PgDn warp · Home reset\n"
		+ "Shift+arrows camera orbit / dolly · Shift+PgUp/Dn roll · Shift+Home reset\n"
		+ "Shift+Space  formation of 200 (Shift+X: helix/lattice/shell/ring)\n"
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
	_fx_glow_btn.text = "D  Glow: %s" % _glow.describe()
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


## Plain drop: the image becomes a toolbox slot with verbs like any icon.
func add_raster(path: String) -> int:
	var idx := Toolbox.add_raster(path)
	if idx >= 0:
		Ledger.record_local(Toolbox.slots[idx])
		_steal_note = "added “%s” to slot %d — S steals its palette" % [Toolbox.slots[idx]["term"], idx + 1]
	else:
		_steal_note = "could not add image (toolbox full?)"
	_update_hud()
	return idx


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		var ext := f.get_extension().to_lower()
		if ext in IconMedia.RASTER_EXT:
			if Input.is_key_pressed(KEY_SHIFT):
				# Shift+drop: chroma-key backdrop
				if _fx.set_backdrop_from_file(f):
					if not _fx.chroma:
						_fx.toggle_chroma()
					_refresh_fx()
			else:
				add_raster(f)
			return
		if ext in ["mp3", "ogg", "wav"]:
			AudioReact.load_file(f)
			_update_hud()
			return


func _update_hud() -> void:
	if _fx_glow_btn:
		_fx_glow_btn.text = "D  Glow: %s" % _glow.describe()
	if _fx_scene_btn:
		_fx_scene_btn.text = "Tab  Scene: %s" % (Scenes.get_scene(Scenes.current).get("name", "?") if Scenes.current != "" else "off")
	var cur := Toolbox.current()
	var name := str(cur.get("term", "—")) if not cur.is_empty() else "empty toolbox — press Find Icons"
	_hud.text = "slot %d: %s   ·   palette: %s   ·   feedback: %s   ·   fx: %s   ·   monitor: %s   ·   actors: %d" % [
		Toolbox.selected + 1, name, Palettes.get_palette(palette_index)["name"],
		("zoom %.2f  twist %.2f  fade %.2f" % [fb_zoom, fb_rot, fb_fade]) if feedback else "off",
		_fx.describe() + ("" if _glow.level == 0 else "  glow " + _glow.describe()), ("%.0f%%" % (_monitor.scale_factor() * 100.0)) if _monitor.visible else "off",
		_actors.get_child_count()] + "   ·   solids: %d (next: %s)   ·   formations: %d (%s)" % [_solids.get_child_count(), next_shape(), _formations.get_child_count(), formation_kind()] \
		+ (("   ·   cam orbit %.2f dolly %.1f roll %.2f h %.1f" % [cam_orbit, cam_dolly, cam_roll, cam_height]) if (cam_orbit != 0.0 or cam_roll != 0.0 or cam_height != 0.0 or cam_dolly != 7.5) else "")
	# second line: controllers
	var line2 := "midi: " + (_midi_last if _midi_last != "" else "—")
	line2 += "   ·   audio: " + ((("%s  %s" % [AudioReact.source if AudioReact.source != "file" else AudioReact.file_name, _meter()])) if AudioReact.active() else "off (A)")
	if AudioReact.driver_missing():
		line2 += "   ·   no audio device: mic/file unavailable"
	line2 += "   ·   webcam: " + (("%s, %s" % [webcam_mode(), _webcam.status]) if _webcam_mode > 0 else "off (Z)")
	if _steal_note != "":
		line2 += "   ·   " + _steal_note
	line2 += "   ·   scene: " + (("%s  spd %.1f  scl %.1f" % [Scenes.get_scene(Scenes.current).get("name", "?"), Scenes.speed, Scenes.scale]) if Scenes.current != "" else "off (Tab)")
	if fb_warp > 0.0 or fb_drift != Vector2.ZERO:
		line2 += "   ·   warp %.2f drift %d,%d" % [fb_warp, fb_drift.x, fb_drift.y]
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
	_scene_layer.set_palette(palette_index)
	_hotbar.palette_index = palette_index
	_hotbar.refresh()
	for a in _actors.get_children() + _solids.get_children():
		var i := Toolbox.index_of(a.slot_id)
		if i >= 0:
			a.set_palette(palette_index, int(Toolbox.slots[i].get("color_index", i)))
	for f in _formations.get_children():
		var i := Toolbox.index_of(f.slot_id)
		if i >= 0:
			f.recolor(palette_index, int(Toolbox.slots[i].get("color_index", i)))
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
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _dragging
	for a in _actors.get_children():
		a.mouse_world = mouse
		a.attract = held
	for sol in _solids.get_children():
		sol.attract = held
	_cam_angle += cam_orbit * _delta
	_camera.position = Vector3(sin(_cam_angle) * cam_dolly, cam_height, cos(_cam_angle) * cam_dolly)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.rotate_object_local(Vector3.FORWARD, cam_roll)
	if _solids.get_child_count() > 0:
		var mp := _camera.project_position(mouse, cam_dolly)
		for sol in _solids.get_children():
			sol.mouse_point = mp
	if feedback:
		var cur: int = _flip
		_flip = 1 - _flip
		var prev: MeshInstance2D = _acc_prev[cur]
		prev.scale = Vector2.ONE * fb_zoom
		prev.rotation = fb_rot
		prev.modulate = Color(1, 1, 1, fb_fade)
		var m: ShaderMaterial = _acc_mats[cur]
		m.set_shader_parameter("warp", fb_warp)
		m.set_shader_parameter("warp_speed", fb_warp_speed)
		m.set_shader_parameter("drift", fb_drift)
		m.set_shader_parameter("stretch", fb_stretch)
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
	else:
		for a in _actors.get_children():              # nothing near: scatter the flocks
			a.scatter_from = world_pos


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
	if k >= KEY_F1 and k <= KEY_F12:
		var n := k - KEY_F1 + 1
		if ev.shift_pressed:
			save_preset(n)
		else:
			recall_preset(n)
		return
	if k >= KEY_1 and k <= KEY_9:
		Toolbox.select(k - KEY_1)
		return
	match k:
		KEY_TAB:
			step_scene(-1 if ev.shift_pressed else 1)
			get_viewport().set_input_as_handled()
			return
		KEY_QUOTELEFT:
			set_scene("")
			return
		KEY_UP:
			if ev.shift_pressed: cam_dolly = maxf(3.0, cam_dolly - 0.5)
			else: fb_drift.y -= 1.0
		KEY_DOWN:
			if ev.shift_pressed: cam_dolly = minf(14.0, cam_dolly + 0.5)
			else: fb_drift.y += 1.0
		KEY_LEFT:
			if ev.shift_pressed: cam_orbit = clampf(cam_orbit - 0.1, -1.5, 1.5)
			else: fb_drift.x -= 1.0
		KEY_RIGHT:
			if ev.shift_pressed: cam_orbit = clampf(cam_orbit + 0.1, -1.5, 1.5)
			else: fb_drift.x += 1.0
		KEY_PAGEUP:
			if ev.shift_pressed: cam_roll += 0.1
			else: fb_warp = minf(1.0, fb_warp + 0.05)
		KEY_PAGEDOWN:
			if ev.shift_pressed: cam_roll -= 0.1
			else: fb_warp = maxf(0.0, fb_warp - 0.05)
		KEY_HOME:
			if ev.shift_pressed:
				reset_camera()
			else:
				fb_warp = 0.0
				fb_drift = Vector2.ZERO
				fb_stretch = Vector2.ONE
	var verb := Verbs.by_key(k, ev.shift_pressed)
	if verb != "" and not Toolbox.current().is_empty():
		Toolbox.toggle_verb(Toolbox.selected, verb)
		return
	match k:
		KEY_SPACE:
			if ev.shift_pressed:
				spawn_formation()
			else:
				spawn_at(Vector2(randf_range(100, WORLD.x - 100), randf_range(100, WORLD.y - 100)))
		KEY_P:
			palette_index = (palette_index + 1) % Palettes.count()
			_apply_palette()
		KEY_X:
			if ev.shift_pressed:
				cycle_formation()
			else:
				_recolor()
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
		KEY_Z: cycle_webcam()
		KEY_D:
			_glow.cycle()
			_update_hud()
		KEY_S: steal_palette()
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
			for a in _actors.get_children() + _solids.get_children() + _formations.get_children():
				a.queue_free()
		KEY_H:
			_help.visible = not _help.visible
			_verb_panel.get_parent().visible = _help.visible
			_hud.get_parent().visible = _help.visible
	_update_hud()
