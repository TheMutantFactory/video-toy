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
	raster = str(slot.get("kind", "icon")) == "raster"
	_base_color = Color.WHITE if raster else Palettes.color(pal, int(slot.get("color_index", 0)))

	_sprite = Sprite2D.new()
	_sprite.texture = IconMedia.texture_for(str(slot.get("svg_path", "")))
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
	if not is_inside_tree():
		return
	t += delta

	var moved := false
	if verbs.has("bounce"):
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
	if verbs.has("wander"):
		if position.distance_to(wander_target) < 12.0:
			wander_target = _random_point()
		var speed := 160.0
		position = position.move_toward(wander_target, speed * delta)
		home = position
		moved = true
	if verbs.has("flock"):
		var others: Array = []
		for a in get_parent().get_children():
			if a != self and a.slot_id == slot_id and is_instance_valid(a):
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
	if verbs.has("swarm"):
		var to_mouse := mouse_world - position
		velocity = velocity.lerp(to_mouse.normalized() * 380.0, 2.0 * delta)
		position += velocity * delta
		home = position
		moved = true
	if verbs.has("orbit"):
		angle += delta * 1.4
		var centre := home if not moved else position
		position = centre + Vector2.from_angle(angle) * orbit_radius
		if moved:
			position = centre + Vector2.from_angle(angle) * (orbit_radius * 0.35)

	if verbs.has("spin"):
		_sprite.rotation += delta * 2.2
	elif not verbs.has("flock"):
		_sprite.rotation = lerpf(_sprite.rotation, 0.0, 6.0 * delta)
	var s := base_scale
	if verbs.has("pulse"):
		# With audio on, Pulse follows the bass instead of a sine.
		s *= (1.0 + 0.7 * AudioReact.bass) if AudioReact.active() else (1.0 + 0.25 * sin(t * 4.0))
	if AudioReact.active():
		s *= 1.0 + 0.18 * AudioReact.beat_env              # everyone jumps on the beat
	_sprite.scale = Vector2.ONE * s

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


func _random_point() -> Vector2:
	return Vector2(randf_range(bounds.position.x + 80, bounds.end.x - 80),
		randf_range(bounds.position.y + 80, bounds.end.y - 80))
