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


func _process(delta: float) -> void:
	var verbs := _verbs()
	if not is_inside_tree() or _dying:
		return
	t += delta
	_follow_slot_image()

	position -= _orbit_off                     # orbit rides on top of the base motion
	_orbit_off = Vector2.ZERO
	var moved := false
	var mobile := not riding
	if mobile and verbs.has("bounce"):
		position += velocity * delta
		var half := _sprite.texture.get_size() * _sprite.scale * 0.5 if _sprite.texture else Vector2(40, 40)
		if position.x - half.x < bounds.position.x or position.x + half.x > bounds.end.x:
			velocity.x = -velocity.x
			position.x = clampf(position.x, bounds.position.x + half.x, bounds.end.x - half.x)
		if position.y - half.y < bounds.position.y or position.y + half.y > bounds.end.y:
			velocity.y = -velocity.y
			position.y = clampf(position.y, bounds.position.y + half.y, bounds.end.y - half.y)
		home = position
		moved = true
	if mobile and verbs.has("wander"):
		if position.distance_to(wander_target) < 12.0:
			wander_target = _random_point()
		var speed := 160.0
		position = position.move_toward(wander_target, speed * delta)
		home = position
		moved = true
	if mobile and verbs.has("flock"):
		var others: Array = []
		for a in get_parent().get_children():
			if a != self and is_instance_valid(a) and "slot_id" in a and a.slot_id == slot_id:
				others.append([a.position, a.velocity])
		var acc := Boids.steer2(position, velocity, others, mouse_world if attract else Vector2.INF, 1.5)
		if scatter_from != Vector2.INF:
			acc += (position - scatter_from).normalized() * Boids.MAX_FORCE * 6.0
			scatter_from = Vector2.INF
		velocity = (velocity + acc * delta).limit_length(Boids.MAX_SPEED)
		if velocity.length() < 40.0:
			velocity = Vector2.from_angle(randf() * TAU) * 120.0
		position += velocity * delta
		# soft walls: turn back inside the bounds
		var margin := 80.0
		if position.x < bounds.position.x + margin: velocity.x += 600.0 * delta
		if position.x > bounds.end.x - margin: velocity.x -= 600.0 * delta
		if position.y < bounds.position.y + margin: velocity.y += 600.0 * delta
		if position.y > bounds.end.y - margin: velocity.y -= 600.0 * delta
		position = position.clamp(bounds.position, bounds.end)
		_sprite.rotation = velocity.angle() + PI * 0.5 if not verbs.has("spin") else _sprite.rotation
		home = position
		moved = true
	if mobile and verbs.has("field"):
		var f := Field.curl(position, t) * 240.0
		velocity = velocity.lerp(f, minf(1.0, delta * 3.0))
		position += velocity * delta
		position = Vector2(fposmod(position.x, bounds.size.x), fposmod(position.y, bounds.size.y))
		_sprite.rotation = velocity.angle() + PI * 0.5 if not verbs.has("spin") else _sprite.rotation
		home = position
		moved = true
	if mobile and (verbs.has("lorenz") or verbs.has("rossler")):
		var lor := verbs.has("lorenz")
		_att = Attractors.lorenz_step(_att, delta * 0.9) if lor else Attractors.rossler_step(_att, delta * 1.6)
		var target := Attractors.project_lorenz(_att, _att_centre) if lor else Attractors.project_rossler(_att, _att_centre)
		velocity = (target - position) / maxf(delta, 0.001)
		position = target
		_sprite.rotation = velocity.angle() + PI * 0.5 if not verbs.has("spin") else _sprite.rotation
		home = position
		moved = true
	elif mobile and (verbs.has("clifford") or verbs.has("dejong")):
		# jump to the next map point every ~0.3 s, gliding in between
		_map_t += delta * 3.4
		if _map_t >= 1.0:
			_map_t = 0.0
			_map_from = _map
			_map = Attractors.clifford(_map) if verbs.has("clifford") else Attractors.dejong(_map)
		var a := Attractors.project_map(_map_from, _att_centre)
		var b := Attractors.project_map(_map, _att_centre)
		var target := a.lerp(b, smoothstep(0.0, 1.0, _map_t))
		velocity = (target - position) / maxf(delta, 0.001)
		position = target
		home = position
		moved = true
	if mobile and verbs.has("swarm"):
		var to_mouse := mouse_world - position
		velocity = velocity.lerp(to_mouse.normalized() * 380.0, 2.0 * delta)
		position += velocity * delta
		home = position
		moved = true
	if mobile and verbs.has("orbit"):
		angle += delta * 1.4
		_orbit_off = Vector2.from_angle(angle) * (orbit_radius * (0.35 if moved else 1.0))
		position += _orbit_off

	if verbs.has("spin"):
		_sprite.rotation += delta * 2.2
	elif not (verbs.has("flock") or verbs.has("lorenz") or verbs.has("rossler") or verbs.has("field")):
		_sprite.rotation = lerpf(_sprite.rotation, 0.0, 6.0 * delta)
	var s := base_scale
	if verbs.has("pulse"):
		# With audio on, Pulse follows the bass instead of a sine.
		s *= (1.0 + 0.7 * AudioReact.bass) if AudioReact.active() else (1.0 + 0.25 * sin(t * 4.0))
	if AudioReact.active():
		s *= 1.0 + 0.18 * AudioReact.beat_env              # everyone jumps on the beat
	_sprite.scale = Vector2.ONE * s * _sdf_mult

	_tick_sdf(verbs, delta)

	if verbs.has("rainbow"):
		var c := _base_color
		c.h = fmod(c.h + t * 0.25, 1.0)
		c.s = maxf(c.s, 0.7)
		_sprite.modulate = c
		_particles.color = c
		_burst.color = c
	else:
		_sprite.modulate = _base_color

	_particles.emitting = verbs.has("sparkle")
	# Beat burst: a one-shot puff of icons whenever the envelope restarts.
	if verbs.has("sparkle") and AudioReact.active() and AudioReact.beat_env > _last_beat:
		_burst.restart()
	_last_beat = AudioReact.beat_env


## Live words and cycling lists change the slot's image; pick it up.
func _follow_slot_image() -> void:
	var i := Toolbox.index_of(slot_id)
	if i < 0:
		return
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
	_sprite.visible = false
	_particles.emitting = false
	get_tree().create_timer(1.3).timeout.connect(queue_free)


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
