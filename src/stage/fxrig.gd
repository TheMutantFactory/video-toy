extends RefCounted
## Particle field, reaction-diffusion, the quality ladder, panic and blackout.
## Owned by the stage (src/stage_screen.gd), which exposes these as one-line
## delegations; `s` is the stage, whose state stays in one place.

var s: Stage


func _init(stage: Stage) -> void:
	s = stage


func _build_particles() -> void:
	s._particles = GPUParticles2D.new()
	s._particles.amount = 12000
	s._particles.lifetime = 600.0
	s._particles.explosiveness = 1.0            # all at once; emission would otherwise trickle over the lifetime
	s._particles.preprocess = 0.0
	s._particles.z_index = -1
	s._particles.emitting = false
	s._particles.visible = false
	s._pmat = ShaderMaterial.new()
	s._pmat.shader = load("res://src/particles.gdshader")
	s._pmat.set_shader_parameter("bounds", Vector2(s.WORLD))
	s._pmat.set_shader_parameter("dot_size", 0.6)          # x16 px texture -> ~10 px dots
	s._particles.process_material = s._pmat
	# a soft dot
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	s._particles.texture = ImageTexture.create_from_image(img)
	s._world.add_child(s._particles)
	_push_particles()


func set_particles(on: bool) -> void:
	s.particles_on = on
	s._particles.visible = on
	s._particles.emitting = on
	if on:
		s._particles.restart()
	s._update_hud()


func _push_particles() -> void:
	s._pmat.set_shader_parameter("flow", s.particles_flow)
	var repel := s._clock < s._scatter_until
	s._pmat.set_shader_parameter("attract", -1.0 if repel else s.particles_attract)
	Scenes.apply_palette(s._pmat, s.palette_index)
	# attractors: the mouse, then the first icons
	var list: Array[Color] = []
	if s._display == null:                                   # still building
		return
	var mouse := s._world_pos(s.get_local_mouse_position())
	if Rect2(Vector2.ZERO, Vector2(s.WORLD)).has_point(mouse):
		list.append(Color(mouse.x, mouse.y, 1.0, 420.0))
	for a in s.all_actors():
		if list.size() >= 16:
			break
		var gp: Vector2 = a.global_position if a.riding else a.position
		list.append(Color(gp.x, gp.y, 0.6, 260.0))
	var arr: Array[Color] = list.duplicate()
	while arr.size() < 16:
		arr.append(Color(0, 0, 0, 1))
	s._pmat.set_shader_parameter("attractors", PackedColorArray(arr))
	s._pmat.set_shader_parameter("attractor_count", list.size())


func scatter_particles() -> void:
	s._scatter_until = s._clock + 0.35


# ---------------- reaction-diffusion ----------------
## Gray-Scott in two 480x270 viewports that alternate each frame; the world
## texture seeds V, and _worldmix paints V through the palette under the
## actors (see BLEND_SHADER).
func _build_rd() -> void:
	for i in 2:
		var vp := SubViewport.new()
		vp.size = s.RD_SIZE
		vp.disable_3d = true
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		s.add_child(vp)
		var r := ColorRect.new()
		r.size = Vector2(s.RD_SIZE)
		r.color = Color.WHITE
		var m := ShaderMaterial.new()
		m.shader = load("res://src/rd.gdshader")
		m.set_shader_parameter("seed_tex", s._world.get_texture())
		m.set_shader_parameter("texel", Vector2(1.0 / s.RD_SIZE.x, 1.0 / s.RD_SIZE.y))
		r.material = m
		vp.add_child(r)
		s._rd.append(vp)
		s._rd_mats.append(m)
	s._rd_mats[0].set_shader_parameter("prev_tex", s._rd[1].get_texture())
	s._rd_mats[1].set_shader_parameter("prev_tex", s._rd[0].get_texture())
	s._layer_mix.material.set_shader_parameter("rd_tex", s._rd[0].get_texture())
	_push_rd()


func set_rd_preset(i: int) -> void:
	s.rd_preset = posmod(i, s.RD_PRESETS.size())
	var p: Dictionary = s.RD_PRESETS[s.rd_preset]
	if s.rd_preset > 0:
		s.rd_feed = p["feed"]
		s.rd_kill = p["kill"]
	if s.rd_preset == 0:
		for vp in s._rd:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_push_rd()
	s._update_hud()


func cycle_rd() -> void:
	set_rd_preset(s.rd_preset + 1)


func _push_rd() -> void:
	for m in s._rd_mats:
		m.set_shader_parameter("feed", s.rd_feed)
		m.set_shader_parameter("kill", s.rd_kill)
	s._layer_mix.material.set_shader_parameter("rd_on", s.rd_preset > 0)


func _tick_rd() -> void:
	if s.rd_preset == 0:
		return
	if Engine.get_process_frames() % int(Quality.get_level(s.quality.effective())["rd_every"]) != 0:
		return
	var cur := s._rd_flip
	s._rd_flip = 1 - s._rd_flip
	s._rd[1 - cur].render_target_update_mode = SubViewport.UPDATE_DISABLED
	s._rd[cur].render_target_update_mode = SubViewport.UPDATE_ONCE
	s._layer_mix.material.set_shader_parameter("rd_tex", s._rd[cur].get_texture())


func rd_describe() -> String:
	if s.rd_preset == 0:
		return "off"
	return "%s f%.3f k%.3f" % [s.RD_PRESETS[s.rd_preset]["name"], s.rd_feed, s.rd_kill]


# ---------------- webcam ----------------
## The camera renders into its own viewport so one RGB texture serves both the
## world layer (behind everything, so it feeds back and gets the effects) and
## the chroma-key backdrop.
func _enable_measurement() -> void:
	s._measured = [s.get_viewport().get_viewport_rid()]
	for vp in _find_viewports(s):
		s._measured.append(vp.get_viewport_rid())
	for rid in s._measured:
		RenderingServer.viewport_set_measure_render_time(rid, true)
	# Performance.TIME_PROCESS includes the present/vsync wait on macOS, so
	# script time is bracketed by hand: process_frame -> frame_pre_draw.
	if not s.get_tree().process_frame.is_connected(_on_process_frame):
		s.get_tree().process_frame.connect(_on_process_frame)
	if not RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)


func _on_process_frame() -> void:
	if is_instance_valid(s):
		s._t_proc = Time.get_ticks_usec()


func _on_pre_draw() -> void:
	if is_instance_valid(s) and s._t_proc > 0:
		s.script_ms = (Time.get_ticks_usec() - s._t_proc) / 1000.0


## The stage is going away: these connections would otherwise outlive it.
func teardown() -> void:
	if is_instance_valid(s) and s.get_tree() and s.get_tree().process_frame.is_connected(_on_process_frame):
		s.get_tree().process_frame.disconnect(_on_process_frame)
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)


func _find_viewports(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is SubViewport:
			out.append(c)
		out.append_array(_find_viewports(c))
	return out


func measure_work_ms() -> float:
	var ms := s.script_ms
	for rid in s._measured:
		ms += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return ms


## Where the frame goes: script, then cpu/gpu per measured viewport (debug HUD / capture).
func perf_breakdown() -> String:
	var parts := ["script %.1f (TIME_PROCESS %.1f)" % [s.script_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]]
	var i := 0
	for rid in s._measured:
		var c := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var g := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if c + g > 0.3:
			parts.append("vp%d %.1f/%.1f" % [i, c, g])
		i += 1
	var rest := "   nodes %d  orphans %d  objects %d  draw_calls %d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
	return "  ".join(parts) + "   stage_process(us) " + str(s._prof) + rest


func apply_quality(level: int) -> void:
	level = clampi(level, 0, Quality.count() - 1)
	if level == s._quality_applied:
		return
	s._quality_applied = level
	var q: Dictionary = Quality.get_level(level)
	if s._particles.amount != int(q["particles"]):
		s._particles.amount = int(q["particles"])           # restarts the system
		if s.particles_on:
			s._particles.restart()
	s._fx.slit_stride = int(q["slit_stride"])
	s._glow.set_taps(int(q["glow_taps"]))
	s._world3d.msaa_3d = Viewport.MSAA_2X if q["msaa"] else Viewport.MSAA_DISABLED
	s._update_hud()


func _tick_quality(delta: float) -> void:
	if Engine.get_process_frames() % 10 == 0:            # the render-time queries cost ~1.5 ms; sample, don't poll
		s.work_ms = measure_work_ms()
	if s.quality.update(s.work_ms, delta):
		s._steal_note = "quality → " + s.quality.describe()
	apply_quality(s.quality.effective())


func cycle_quality_lock() -> void:
	s.quality.cycle_lock()
	apply_quality(s.quality.effective())
	s._steal_note = "quality " + s.quality.describe()
	s._update_hud()


# ---------------- panic / blackout ----------------
## A known-good look, toolbox and actors untouched.
func panic() -> void:
	if s._fade_tween:
		s._fade_tween.kill()
	s._xf = {}
	s._set_feedback(false)
	s.fb_zoom = 1.04
	s.fb_rot = 0.02
	s.fb_fade = 0.92
	s.fb_warp = 0.0
	s.fb_drift = Vector2.ZERO
	s.fb_stretch = Vector2.ONE
	s._fx.set_state(0, false, false, 0, false, 0, 0, 0)
	s._glow.set_level(1)
	s._ascii.set_mode(0)
	set_particles(false)
	set_rd_preset(0)
	s.set_scene("", 0.3)
	s.set_monitor(false)
	s.set_webcam_mode(0)
	for i in range(1, s.LAYER_COUNT):
		s._layers[i]["blend"] = 0
		s._layers[i]["opacity"] = 1.0
	s._apply_layers()
	s.set_active_layer(0)
	s.reset_camera()
	s.draw_mode = false
	s.set_evolve(false)
	if s.attract:
		s.attract = false
		s._attract_base = {}
	s.timeline.stop_play()
	if s.timeline.recording:
		s.toggle_record()
	if s.blackout:
		toggle_blackout()
	s.stop_credits_roll()
	s._refresh_fx()
	s._steal_note = "PANIC: known-good look (toolbox kept)"
	s._update_hud()


func toggle_blackout() -> void:
	s.blackout = not s.blackout
	if s._blackout_tween:
		s._blackout_tween.kill()
	s._blackout.visible = true
	s._blackout_tween = s.create_tween()
	s._blackout_tween.tween_property(s._blackout, "modulate:a", 1.0 if s.blackout else 0.0, 0.5)
	if not s.blackout:
		s._blackout_tween.tween_callback(func(): s._blackout.visible = false)
	s._update_hud()


# ---------------- player 2 ----------------
