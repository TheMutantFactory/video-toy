extends RefCounted
## Mouse and keyboard for the stage. The keyboard is a table: keycode ->
## [plain, shift] callables, consulted after the few keys that need
## context (help, presets, digits, panic, Ctrl combos, verbs). Owned by the
## stage; `s` is the stage, whose state stays in one place.

var s: Stage
var _plain: Dictionary = {}     # keycode -> Callable
var _shift: Dictionary = {}


func _init(stage: Stage) -> void:
	s = stage
	_build_table()


## The lambdas in the table hold this module and the module holds the table:
## break the cycle when the stage goes, or the module never frees.
func teardown() -> void:
	_plain.clear()
	_shift.clear()


## The keycodes the table knows.
func table_keys() -> Array:
	var ks: Array = _plain.keys()
	for k in _shift.keys():
		if not ks.has(k):
			ks.append(k)
	return ks


# ---------------- mouse ----------------
func world_pos(local: Vector2) -> Vector2:
	# Map the on-screen rect (keep-aspect centred) back to world pixels.
	var rect := s._display.get_rect()
	var scale := minf(rect.size.x / s.WORLD.x, rect.size.y / s.WORLD.y)
	var drawn := Vector2(s.WORLD) * scale
	var origin := rect.position + (rect.size - drawn) * 0.5
	return (local - origin) / scale


## The physics icon under the cursor, for grabbing.
func physics_actor_at(p: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := 1e9
	for a in s.all_actors():
		if a.body == null:
			continue
		var d: float = a.position.distance_to(p)
		if d < a.hit_radius() and d < best_d:
			best_d = d
			best = a
	return best


func remove_nearest(p: Vector2) -> void:
	for r in s.all_rides():                          # a stroke under the cursor goes first
		if r.near(p):
			r.queue_free()
			return
	var best: Node2D = null
	var best_d := 1e9
	for a in s.all_actors():
		var d: float = a.global_position.distance_to(p) if a.riding else a.position.distance_to(p)
		if d < best_d:
			best_d = d
			best = a
	for sol in s._solids.get_children():
		var d: float = s._camera.unproject_position(sol.position).distance_to(p)
		if d < best_d:
			best_d = d
			best = sol
	if best and best_d < 160.0:
		best.queue_free()
	else:
		for a in s.all_actors():                        # nothing near: scatter the flocks
			a.scatter_from = p
		s.scatter_particles()


func mouse(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var wp := world_pos(ev.position)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				var held := physics_actor_at(wp)
				if held:
					s._grab = held
					s._grab_prev = wp
					s._grab_vel = Vector2.ZERO
					s._grab_ms = Time.get_ticks_msec()
					held.grab(true)
				elif s._monitor.visible and s._monitor.contains(wp):
					s._dragging = true
					s._drag_offset = s._monitor.position - wp
				elif s.draw_mode:
					s.begin_stroke(wp)
				elif not s.pinata_at(wp):
					s.spawn_at(wp)
			else:
				if s._grab:
					if is_instance_valid(s._grab):
						s._grab.release(s._grab_vel)
					s._grab = null
				s._dragging = false
				if not s._stroke.is_empty():
					s.end_stroke()
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			remove_nearest(wp)
	elif ev is InputEventMouseMotion and s._grab:
		if not is_instance_valid(s._grab):
			s._grab = null
			return
		var wp := world_pos(ev.position)
		var now := Time.get_ticks_msec()
		var dt := maxf(0.004, (now - s._grab_ms) / 1000.0)
		s._grab_vel = s._grab_vel.lerp((wp - s._grab_prev) / dt, 0.5)
		s._grab_prev = wp
		s._grab_ms = now
		s._grab.grab_to(wp)
	elif ev is InputEventMouseMotion and s._dragging:
		s._monitor.position = world_pos(ev.position) + s._drag_offset
	elif ev is InputEventMouseMotion and not s._stroke.is_empty():
		s.extend_stroke(world_pos(ev.position))


# ---------------- keyboard ----------------
func key(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed):
		return
	var k: int = ev.keycode
	if s._p2_key(k):
		return
	if k == KEY_ESCAPE and not ev.shift_pressed and s._help.visible:
		s._help.close()
		s.get_viewport().set_input_as_handled()
		return
	if (k == KEY_SLASH and ev.shift_pressed) or k == KEY_QUESTION:
		s._help.toggle()
		s.get_viewport().set_input_as_handled()
		return
	if k >= KEY_F1 and k <= KEY_F12:
		var n := k - KEY_F1 + 1
		if ev.shift_pressed:
			s.save_preset(n)
		else:
			s.recall_preset(n)
		return
	if k == KEY_2 and ev.shift_pressed:
		s.p2_sleep()
		return
	if k == KEY_ESCAPE and ev.shift_pressed:
		s.panic()
		return
	if k >= KEY_1 and k <= KEY_9:
		Toolbox.select(k - KEY_1)
		return
	if ev.ctrl_pressed and k == KEY_G:
		s.set_gravity(0.0 if s.gravity > 0.0 else 1.0)
		return
	if ev.ctrl_pressed and k == KEY_S:
		s.play_slot_sound()
		return
	var verb := Verbs.by_key(k, ev.shift_pressed, ev.ctrl_pressed)
	if verb != "" and not Toolbox.current().is_empty():
		Toolbox.toggle_verb(Toolbox.selected, verb)
		return
	var fn: Variant = (_shift if ev.shift_pressed else _plain).get(k)
	if fn is Callable:
		fn.call()
	s._update_hud()


## keycode -> what plain and Shift do. `both` registers one action for both.
func _bind(k: int, plain: Variant, shift: Variant = null, both := false) -> void:
	if plain is Callable:
		_plain[k] = plain
	if shift is Callable:
		_shift[k] = shift
	elif both and plain is Callable:
		_shift[k] = plain


func _build_table() -> void:
	_bind(KEY_TAB, func(): _tab(1), func(): _tab(-1))
	_bind(KEY_QUOTELEFT, func(): s.set_scene(""), null, true)
	_bind(KEY_APOSTROPHE, _ascii_cycle, null, true)
	_bind(KEY_UP, func(): s.fb_drift.y -= 1.0, func(): s.cam_dolly = maxf(3.0, s.cam_dolly - 0.5))
	_bind(KEY_DOWN, func(): s.fb_drift.y += 1.0, func(): s.cam_dolly = minf(14.0, s.cam_dolly + 0.5))
	_bind(KEY_LEFT, func(): s.fb_drift.x -= 1.0, func(): s.cam_orbit = clampf(s.cam_orbit - 0.1, -1.5, 1.5))
	_bind(KEY_RIGHT, func(): s.fb_drift.x += 1.0, func(): s.cam_orbit = clampf(s.cam_orbit + 0.1, -1.5, 1.5))
	_bind(KEY_PAGEUP, func(): s.fb_warp = minf(1.0, s.fb_warp + 0.05), func(): s.cam_roll += 0.1)
	_bind(KEY_PAGEDOWN, func(): s.fb_warp = maxf(0.0, s.fb_warp - 0.05), func(): s.cam_roll -= 0.1)
	_bind(KEY_HOME, _reset_warp, s.reset_camera)
	_bind(KEY_SPACE, func(): s.spawn_at(Vector2(randf_range(100, s.WORLD.x - 100), randf_range(100, s.WORLD.y - 100))), s.spawn_formation)
	_bind(KEY_X, s._recolor, s.cycle_formation)
	_bind(KEY_DELETE, func(): Toolbox.remove(Toolbox.selected), null, true)
	_bind(KEY_BACKSPACE, func(): Toolbox.remove(Toolbox.selected), null, true)
	_bind(KEY_F, func(): s._set_feedback(not s.feedback), s.cycle_quality_lock)
	_bind(KEY_BRACKETLEFT, func(): s.fb_zoom = maxf(0.90, s.fb_zoom - 0.01), func(): s.set_layer_opacity(s._layers[s.active_layer]["opacity"] - 0.1))
	_bind(KEY_BRACKETRIGHT, func(): s.fb_zoom = minf(1.20, s.fb_zoom + 0.01), func(): s.set_layer_opacity(s._layers[s.active_layer]["opacity"] + 0.1))
	_bind(KEY_COMMA, func(): s.fb_rot -= 0.01, func(): s.set_bank(s.bank - 1))
	_bind(KEY_PERIOD, func(): s.fb_rot += 0.01, func(): s.set_bank(s.bank + 1))
	_bind(KEY_B, _solid_at_mouse, s.cycle_shape)
	_bind(KEY_SEMICOLON, s.toggle_midi_panel, s.cycle_fade)
	_bind(KEY_Z, s.cycle_webcam, func(): s.set_syphon(not s.syphon_on))
	_bind(KEY_D, func(): s._glow.cycle(), _draw_toggle)
	_bind(KEY_BACKSLASH, func(): s.set_active_layer(s.active_layer + 1), s.cycle_blend)
	_bind(KEY_S, s.steal_palette, s.spawn_mosaic)
	_bind(KEY_E, null, func(): s.set_evolve(not s.evolve))
	_bind(KEY_N, func(): s._monitor.cycle_size(), func(): s.set_particles(not s.particles_on))
	_bind(KEY_O, func(): _fx(s._fx.cycle_kaleido), s.cycle_rd)
	_bind(KEY_R, null, s.toggle_record)
	_bind(KEY_P, _next_palette, s.toggle_play)
	_bind(KEY_ENTER, func(): _evolve_vote(true), func(): _evolve_vote(false))
	_bind(KEY_KP_ENTER, func(): _evolve_vote(true), func(): _evolve_vote(false))
	_bind(KEY_A, AudioReact.cycle_source, func(): s.set_attract(not s.attract))
	_bind(KEY_M, func(): s.set_monitor(not s._monitor.visible), null, true)
	_bind(KEY_V, func(): _fx(s._fx.cycle_crt), s.screenshot_with_credits)
	_bind(KEY_G, func(): _fx(s._fx.cycle_key), _key_threshold)
	_bind(KEY_K, func(): _fx(s._fx.cycle_pixelate), func(): _fx(s._fx.cycle_slit))
	_bind(KEY_L, func(): _fx(s._fx.toggle_quantize), func(): s.set_ticker(not s.ticker_on))
	_bind(KEY_J, func(): _fx(s._fx.toggle_dither), null, true)
	_bind(KEY_MINUS, func(): s.fb_fade = maxf(0.5, s.fb_fade - 0.02), func(): s.step_preset(-1))
	_bind(KEY_EQUAL, func(): s.fb_fade = minf(0.995, s.fb_fade + 0.02), func(): s.step_preset(1))
	_bind(KEY_C, _clear_all, _credits_toggle)
	_bind(KEY_H, func(): s.set_hud_mode((s.hud_mode + 1) % 3), s.toggle_blackout)


# ---------------- the multi-statement ones ----------------
func _tab(dir: int) -> void:
	s.step_scene(dir)
	s.get_viewport().set_input_as_handled()


func _ascii_cycle() -> void:
	s._ascii.cycle()
	s._steal_note = "ASCII " + s._ascii.describe()


func _reset_warp() -> void:
	s.fb_warp = 0.0
	s.fb_drift = Vector2.ZERO
	s.fb_stretch = Vector2.ONE


func _solid_at_mouse() -> void:
	s.spawn_solid(world_pos(s.get_local_mouse_position()) if s.get_global_rect().has_point(s.get_global_mouse_position()) else Vector2(-1, -1))


func _draw_toggle() -> void:
	s.draw_mode = not s.draw_mode
	s._steal_note = "draw mode: drag a path, the selected icon rides it" if s.draw_mode else ""


## An fx cycle followed by the button refresh.
func _fx(cycle: Callable) -> void:
	cycle.call()
	s._refresh_fx()


func _key_threshold() -> void:
	s._fx.key_threshold = fmod(s._fx.key_threshold + 0.1, 0.95)
	s._fx._push()
	s._refresh_fx()


func _next_palette() -> void:
	s.palette_index = (s.palette_index + 1) % Palettes.count()
	s._apply_palette()


func _evolve_vote(keep: bool) -> void:
	if not s.evolve:
		return
	if keep:
		s.evolve_keep()
	else:
		s.evolve_discard()


func _clear_all() -> void:
	s.clear_actors()
	for a in s._solids.get_children() + s._formations.get_children():
		a.queue_free()


func _credits_toggle() -> void:
	if s._roll.visible:
		s.stop_credits_roll()
	else:
		s.start_credits_roll()
