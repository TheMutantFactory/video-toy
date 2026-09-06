extends Node2D
## One icon on the stage. Reads its verbs live from Toolbox each frame, so
## toggling a verb changes every actor from that slot immediately.

var slot_id := ""
var bounds := Rect2(0, 0, 1920, 1080)
var palette_index := 0
var home := Vector2.ZERO
var velocity := Vector2.ZERO
var angle := 0.0
var t := 0.0
var base_scale := 0.5
var orbit_radius := 160.0
var wander_target := Vector2.ZERO
var mouse_world := Vector2.ZERO
var riding := false                        # on a drawn path: motion verbs are ignored
var _orbit_off := Vector2.ZERO             # last frame's orbit displacement (undone before moving)
var _att := Vector3.ZERO                   # continuous attractor state
var _map := Vector2.ZERO                   # iterated-map state
var _map_from := Vector2.ZERO
var _map_t := 1.0
var _att_centre := Vector2.ZERO
var _tex_orig: Texture2D                     # the plain icon texture
var _tex_path := ""                          # which slot image the sprite shows
var _dying := false
var _sdf_mat: ShaderMaterial                 # set while morph / outline are on
var _sdf_mult := 1.0                         # sprite scale factor when showing the SDF texture
var _morph_target := ""                      # slot id being morphed to
var _morph_t := 0.0
var _morph_last_beat := 0.0
var _sdf_shader: Shader = preload("res://src/morph.gdshader")
var attract := false                       # stage: left button held on empty space
var scatter_from := Vector2.INF            # stage: right-click on empty space (one frame)

var raster := false
var _sprite: Sprite2D
var _particles: CPUParticles2D
var _burst: CPUParticles2D
var _last_beat := 0.0
var _base_color := Color.WHITE
var body: RigidBody2D                      # set while the Physics verb is on
var voice_wanted := false                  # the Voice verb asks each frame
var _voice: IconVoice
var _detune := 1.0
var _sound := ""                           # the slot's sound path, if any
var _last_hit_ms := 0


func setup(slot: Dictionary, pos: Vector2, pal: int, area: Rect2) -> void:
	slot_id = str(slot.get("id", ""))
	bounds = area
	palette_index = pal
	position = pos
	home = pos
	t = randf() * TAU
	angle = randf() * TAU
	base_scale = randf_range(0.35, 0.7)
	orbit_radius = randf_range(90.0, 260.0)
	velocity = Vector2.from_angle(randf() * TAU) * randf_range(180.0, 420.0)
	wander_target = _random_point()
	_att = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(15, 30))
	_map = Vector2(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5))
	_map_from = _map
	_att_centre = area.get_center()
	raster = str(slot.get("kind", "icon")) == "raster"
	_base_color = Color.WHITE if raster else Palettes.color(pal, int(slot.get("color_index", 0)))

	_sprite = Sprite2D.new()
	_sprite.texture = IconMedia.texture_for(str(slot.get("svg_path", "")))
	_tex_orig = _sprite.texture
	_tex_path = str(slot.get("svg_path", ""))
	_sprite.scale = Vector2.ONE * base_scale
	_sprite.modulate = _base_color
	add_child(_sprite)

	# Sparkle emits tiny copies of the icon itself, in the slot colour.
	_particles = _make_emitter(_sprite.texture, 40, 1.4, false)
	add_child(_particles)
	_burst = _make_emitter(_sprite.texture, 28, 1.1, true)      # on the beat
	add_child(_burst)
	_sound = str(slot.get("sound_path", ""))
	if _sound != "":
		Sounds.play(_sound, randf_range(0.95, 1.05))


func _make_emitter(tex: Texture2D, amount: int, life: float, one_shot: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.amount = amount
	p.lifetime = life
	p.texture = tex
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 90)
	p.initial_velocity_min = 60.0 if not one_shot else 160.0
	p.initial_velocity_max = 160.0 if not one_shot else 380.0
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	var size := tex.get_size().x if tex else 400.0
	p.scale_amount_min = 18.0 / size            # ~18-34 px copies of the icon
	p.scale_amount_max = 34.0 / size
	var curve := Curve.new()                    # shrink out
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	p.color = _base_color
	p.z_index = -1
	return p


func set_palette(pal: int, color_index: int) -> void:
	palette_index = pal
	_base_color = Color.WHITE if raster else Palettes.color(pal, color_index)
	_particles.color = _base_color
	_burst.color = _base_color


func _verbs() -> Array:
	var i := Toolbox.index_of(slot_id)
	if i < 0:
		queue_free()
		return []
	return Toolbox.slots[i].get("verbs", [])


## Verb hosts expose these to the verb files (which must not touch autoloads).
var moved := false                         # a motion verb moved the base position this frame
var frame_scale := 1.0                     # verbs multiply this; applied to the sprite after post hooks
var active_ids: Array = []                 # the slot's verb ids this frame
var beat_hit := false                      # the beat envelope restarted this frame (audio or clock)


func audio_active() -> bool:
	return AudioReact.active()


func audio_bass() -> float:
	return AudioReact.bass


func beat_env() -> float:
	return AudioReact.beat_env


func _process(delta: float) -> void:
	var verbs := _verbs()
	if not is_inside_tree() or _dying:
		return
	t += delta
	_follow_slot_image()
	active_ids = verbs
	beat_hit = AudioReact.active() and AudioReact.beat_env > _last_beat
	_last_beat = AudioReact.beat_env

	position -= _orbit_off                     # orbit rides on top of the base motion
	_orbit_off = Vector2.ZERO
	moved = false
	var active := Verbs.active_for(verbs)
	var rotation_set := false
	var excl: Array = active.filter(func(v): return v.exclusive)
	if not riding:
		for v in (excl if not excl.is_empty() else active):
			if v.has_motion2d():
				if v.move2d(self, delta):
					moved = true
				if v.sets_rotation:
					rotation_set = true
	if body and not verbs.has("physics"):
		IconBody.detach(self)
	_tick_voice(verbs)
	if beat_hit and _sound != "" and verbs.has("sparkle"):
		Sounds.play_once_this_frame(_sound)

	# defaults the post hooks may override
	frame_scale = base_scale
	_sprite.modulate = _base_color
	_particles.emitting = false
	for v in active:
		v.post2d(self, delta)
		if v.sets_rotation:
			rotation_set = true
	if not rotation_set:
		_sprite.rotation = lerpf(_sprite.rotation, 0.0, 6.0 * delta)
	if AudioReact.active():
		frame_scale *= 1.0 + 0.18 * AudioReact.beat_env    # everyone jumps on the beat
	_sprite.scale = Vector2.ONE * frame_scale * _sdf_mult

	_tick_sdf(verbs, delta)


## Live words and cycling lists change the slot's image; pick it up.
func _follow_slot_image() -> void:
	var i := Toolbox.index_of(slot_id)
	if i < 0:
		return
	_sound = str(Toolbox.slots[i].get("sound_path", ""))
	var pth := str(Toolbox.slots[i].get("svg_path", ""))
	if pth == _tex_path:
		return
	_tex_path = pth
	var tex := IconMedia.texture_for(pth)
	if tex:
		_tex_orig = tex
		if _sdf_mat == null:
			_sprite.texture = tex
		for p in [_particles, _burst]:
			p.texture = tex


## Pinata: burst into confetti of yourself and go.
func pinata() -> void:
	if _dying:
		return
	_dying = true
	_burst.amount = 60
	_burst.restart()
	if _sound != "":
		Sounds.play(_sound, 0.7)
	if MidiOut.enabled:
		var si := Toolbox.index_of(slot_id)
		MidiOut.note_on(MidiOut.CH_PINATA, MidiOut.note_for_slot(maxi(si, 0)) + 12, 110, 0.3)
		MidiOut.event("pinata", [si + 1])
	IconBody.detach(self)
	_sprite.visible = false
	_particles.emitting = false
	get_tree().create_timer(1.3).timeout.connect(queue_free)


# ---------------- voice (the Voice verb asks; the actor owns the node) ----------------
func _tick_voice(verbs: Array) -> void:
	var want := voice_wanted
	voice_wanted = false
	if want and _voice == null:
		var i := Toolbox.index_of(slot_id)
		var tex := IconMedia.sdf_for(_tex_path) if i >= 0 else null
		if tex == null:
			return
		_voice = IconVoice.new()
		_voice.table_a = IconVoice.table_for(_tex_path, tex.get_image())
		_detune = randf_range(0.985, 1.015)
		add_child(_voice)
	elif not want and _voice != null:
		_voice.queue_free()
		_voice = null
	if _voice == null:
		return
	var idx := Toolbox.index_of(slot_id)
	var f := IconVoice.note_for(maxi(idx, 0)) * _detune
	if verbs.has("spin"):
		f *= pow(2.0, 0.25 * sin(_sprite.rotation))
	_voice.freq = f
	var a := 0.6
	if verbs.has("pulse"):
		a *= clampf(frame_scale / maxf(base_scale, 0.01), 0.2, 2.0)
	if AudioReact.active():
		a *= 1.0 + 0.5 * AudioReact.beat_env
	_voice.amp = a
	if verbs.has("morph") and _morph_target != "" and _morph_t > 0.0:
		var j := Toolbox.index_of(_morph_target)
		if j >= 0:
			var tp := str(Toolbox.slots[j].get("svg_path", ""))
			var tb := IconMedia.sdf_for(tp)
			if tb:
				_voice.table_b = IconVoice.table_for(tp, tb.get_image())
				_voice.morph = _morph_t
	else:
		_voice.morph = 0.0


# ---------------- physics (the Physics verb owns `body`) ----------------
func _on_body_entered(other: Node) -> void:
	if body == null:
		return
	var speed: float = body.linear_velocity.length()
	if other is RigidBody2D:
		speed = maxf(speed, (body.linear_velocity - other.linear_velocity).length())
	if speed < 40.0:
		return
	IconBody.collisions += 1
	var now := Time.get_ticks_msec()
	if now - _last_hit_ms < 120:
		return
	_last_hit_ms = now
	if MidiOut.enabled:
		var si := Toolbox.index_of(slot_id)
		MidiOut.note_on(MidiOut.CH_HIT, MidiOut.note_for_slot(maxi(si, 0)), MidiOut.velocity_for_speed(speed), 0.08)
		MidiOut.event("collision", [si + 1, speed])
	_burst.amount = 12
	_burst.restart()
	if _sound != "":
		Sounds.play(_sound, randf_range(0.9, 1.1), lerpf(-18.0, 0.0, clampf(speed / 700.0, 0.0, 1.0)))


## Held by the mouse: kinematic, follows the cursor; released with a fling.
func grab(on: bool) -> void:
	if body == null:
		return
	body.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC   # static teleports at once; kinematic queues the move for the next step and a same-frame unfreeze drops it
	body.freeze = on


func grab_to(p: Vector2) -> void:
	if body:
		# Straight into the physics server: a node transform change is only
		# forwarded on the next flush, and the physics sync can overwrite it
		# with the old position first (a lost teleport, seen on CI).
		PhysicsServer2D.body_set_state(body.get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(body.rotation, p))
		body.global_position = p
	position = p


func release(fling: Vector2) -> void:
	if body == null:
		return
	body.freeze = false
	body.sleeping = false                     # a body that dozed off on the floor ignores velocity
	body.linear_velocity = fling.limit_length(2500.0)


func hit_radius() -> float:
	return (_sprite.texture.get_size().x * _sprite.scale.x * 0.5) if _sprite.texture else 40.0


# ---------------- morph / outline (signed distance fields) ----------------
func _sdf_enter() -> bool:
	var i := Toolbox.index_of(slot_id)
	if i < 0:
		return false
	var mine := IconMedia.sdf_for(str(Toolbox.slots[i].get("svg_path", "")))
	if mine == null:
		return false
	_sdf_mat = ShaderMaterial.new()
	_sdf_mat.shader = _sdf_shader
	_sdf_mat.set_shader_parameter("sdf_b", mine)
	_sdf_mat.set_shader_parameter("t", 0.0)
	_sprite.texture = mine
	_sprite.material = _sdf_mat
	_sdf_mult = (_tex_orig.get_size().x / mine.get_size().x) if _tex_orig else 1.0
	_morph_target = ""
	_morph_t = 0.0
	return true


func _sdf_leave() -> void:
	_sprite.texture = _tex_orig
	_sprite.material = null
	_sdf_mat = null
	_sdf_mult = 1.0
	_morph_target = ""


## The next non-raster slot after `from_id` in the toolbox (wrapping), or "".
static func next_morph_target(from_id: String) -> String:
	var n := Toolbox.slots.size()
	if n < 2:
		return ""
	var i := Toolbox.index_of(from_id)
	for k in range(1, n):
		var j := posmod(i + k, n)
		if not Toolbox.is_raster_slot(Toolbox.slots[j]):
			return str(Toolbox.slots[j]["id"])
	return ""


func _tick_sdf(verbs: Array, delta: float) -> void:
	var want := verbs.has("morph") or verbs.has("outline")
	if want and _sdf_mat == null:
		if not _sdf_enter():
			return
	elif not want and _sdf_mat != null:
		_sdf_leave()
		return
	if _sdf_mat == null:
		return
	_sdf_mat.set_shader_parameter("outline", 0.06 if verbs.has("outline") else 0.0)
	if not verbs.has("morph"):
		if _morph_t != 0.0:
			_morph_t = 0.0
			_sdf_mat.set_shader_parameter("t", 0.0)
		return
	if _morph_target == "":
		_morph_target = next_morph_target(slot_id)
		if _morph_target == "":
			return
		var ti := Toolbox.index_of(_morph_target)
		var tex := IconMedia.sdf_for(str(Toolbox.slots[ti].get("svg_path", "")))
		if tex == null:
			_morph_target = ""
			return
		_sdf_mat.set_shader_parameter("sdf_b", tex)
	# advance: steadily, or in jumps on the beat when audio is on
	if AudioReact.active():
		if AudioReact.beat_env > _morph_last_beat:
			_morph_t = minf(1.0, _morph_t + 0.5)
		_morph_last_beat = AudioReact.beat_env
	else:
		_morph_t = minf(1.0, _morph_t + delta / 1.5)
	_sdf_mat.set_shader_parameter("t", smoothstep(0.0, 1.0, _morph_t))
	if _morph_t >= 1.0:
		# arrived: the target's field becomes A, pick the next B
		_sprite.texture = _sdf_mat.get_shader_parameter("sdf_b")
		var arrived := _morph_target
		_morph_target = next_morph_target(arrived)
		_morph_t = 0.0
		_sdf_mat.set_shader_parameter("t", 0.0)
		if _morph_target != "":
			var ti2 := Toolbox.index_of(_morph_target)
			var tex2 := IconMedia.sdf_for(str(Toolbox.slots[ti2].get("svg_path", "")))
			if tex2:
				_sdf_mat.set_shader_parameter("sdf_b", tex2)


func _random_point() -> Vector2:
	return Vector2(randf_range(bounds.position.x + 80, bounds.end.x - 80),
		randf_range(bounds.position.y + 80, bounds.end.y - 80))
