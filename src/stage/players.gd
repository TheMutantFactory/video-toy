extends RefCounted
## Player 2: keypad / gamepad cursor with its own slot and layer.
## Owned by the stage (src/stage_screen.gd), which exposes these as one-line
## delegations; `s` is the stage, whose state stays in one place.

var s: Stage


func _init(stage: Stage) -> void:
	s = stage


func p2_wake() -> void:
	if not s.p2_active:
		s.p2_active = true
		s.p2_slot = clampi(s.p2_slot, 0, maxi(Toolbox.slots.size() - 1, 0))
		s._steal_note = "player 2 is in — keypad or gamepad; Shift+2 hides them"
	s._p2_node.visible = true
	_refresh_p2()


func p2_sleep() -> void:
	s.p2_active = false
	s._p2_node.visible = false
	s._hotbar.second_selected = -1
	s._hotbar.refresh()
	s._update_hud()


func _refresh_p2() -> void:
	s._p2_node.position = s.p2_cursor
	s._p2_node.color = Palettes.color(s.palette_index, int(Toolbox.slots[s.p2_slot].get("color_index", s.p2_slot))) if s.p2_slot < Toolbox.slots.size() else Color.CYAN
	s._p2_node.label = "P2 · L%d" % (s.p2_layer + 1)
	s._p2_node.queue_redraw()
	s._hotbar.second_selected = s.p2_slot if s.p2_active else -1
	s._hotbar.refresh()
	s._update_hud()


func p2_move(delta_px: Vector2) -> void:
	p2_wake()
	s.p2_cursor = (s.p2_cursor + delta_px).clamp(Vector2.ZERO, Vector2(s.WORLD))
	_refresh_p2()


func p2_spawn() -> void:
	p2_wake()
	s.spawn_slot_at(s.p2_slot, s.p2_layer, s.p2_cursor)


func p2_remove() -> void:
	p2_wake()
	s._remove_nearest(s.p2_cursor)


func p2_next_slot(step := 1) -> void:
	p2_wake()
	if not Toolbox.slots.is_empty():
		s.p2_slot = posmod(s.p2_slot + step, Toolbox.slots.size())
	_refresh_p2()


func p2_next_layer() -> void:
	p2_wake()
	s.p2_layer = posmod(s.p2_layer + 1, s.LAYER_COUNT)
	_refresh_p2()


func p2_toggle_spin() -> void:
	p2_wake()
	if s.p2_slot < Toolbox.slots.size():
		Toolbox.toggle_verb(s.p2_slot, "spin")


func p2_spawn_solid() -> void:
	p2_wake()
	var keep := Toolbox.selected
	Toolbox.select(s.p2_slot)
	s.spawn_solid(s.p2_cursor)
	Toolbox.select(keep)


func _tick_p2(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_KP_8): v.y -= 1.0
	if Input.is_key_pressed(KEY_KP_2): v.y += 1.0
	if Input.is_key_pressed(KEY_KP_4): v.x -= 1.0
	if Input.is_key_pressed(KEY_KP_6): v.x += 1.0
	for dev in Input.get_connected_joypads():
		var ax := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if ax.length() > 0.15:
			v += ax
	if v != Vector2.ZERO:
		p2_move(v.limit_length(1.0) * s.P2_SPEED * delta)


func _p2_key(k: int) -> bool:
	match k:
		KEY_KP_5, KEY_KP_ENTER: p2_spawn()
		KEY_KP_0: p2_remove()
		KEY_KP_ADD: p2_next_slot(1)
		KEY_KP_SUBTRACT: p2_next_slot(-1)
		KEY_KP_PERIOD: p2_next_layer()
		KEY_KP_MULTIPLY: p2_toggle_spin()
		KEY_KP_DIVIDE: p2_spawn_solid()
		KEY_KP_1, KEY_KP_3, KEY_KP_7, KEY_KP_9:
			p2_wake()
			s.p2_slot = clampi([KEY_KP_1, KEY_KP_3, KEY_KP_7, KEY_KP_9].find(k) * 2, 0, maxi(Toolbox.slots.size() - 1, 0))
			_refresh_p2()
		_: return false
	return true


func _p2_pad_button(b: int) -> void:
	match b:
		JOY_BUTTON_A: p2_spawn()
		JOY_BUTTON_B: p2_remove()
		JOY_BUTTON_X: p2_next_slot(1)
		JOY_BUTTON_Y: p2_next_layer()
		JOY_BUTTON_LEFT_SHOULDER: p2_toggle_spin()
		JOY_BUTTON_RIGHT_SHOULDER: p2_spawn_solid()


# ---------------- presets ----------------
## Everything the stage remembers, as plain data.
