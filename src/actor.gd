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

var _sprite: Sprite2D
var _particles: CPUParticles2D
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
	_base_color = Palettes.color(pal, int(slot.get("color_index", 0)))

	_sprite = Sprite2D.new()
	_sprite.texture = IconMedia.texture_for(str(slot.get("svg_path", "")))
	_sprite.scale = Vector2.ONE * base_scale
	_sprite.modulate = _base_color
	add_child(_sprite)

	_particles = CPUParticles2D.new()
	_particles.emitting = false
	_particles.amount = 40
	_particles.lifetime = 1.2
	_particles.direction = Vector2(0, -1)
	_particles.spread = 180.0
	_particles.gravity = Vector2(0, 120)
	_particles.initial_velocity_min = 40.0
	_particles.initial_velocity_max = 140.0
	_particles.scale_amount_min = 3.0
	_particles.scale_amount_max = 7.0
	_particles.color = _base_color
	_particles.z_index = -1
	add_child(_particles)


func set_palette(pal: int, color_index: int) -> void:
	palette_index = pal
	_base_color = Palettes.color(pal, color_index)
	_particles.color = _base_color


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

	_sprite.rotation = _sprite.rotation + delta * 2.2 if verbs.has("spin") else lerpf(_sprite.rotation, 0.0, 6.0 * delta)
	var s := base_scale
	if verbs.has("pulse"):
		s *= 1.0 + 0.25 * sin(t * 4.0)
	_sprite.scale = Vector2.ONE * s

	if verbs.has("rainbow"):
		var c := _base_color
		c.h = fmod(c.h + t * 0.25, 1.0)
		c.s = maxf(c.s, 0.7)
		_sprite.modulate = c
		_particles.color = c
	else:
		_sprite.modulate = _base_color

	_particles.emitting = verbs.has("sparkle")


func _random_point() -> Vector2:
	return Vector2(randf_range(bounds.position.x + 80, bounds.end.x - 80),
		randf_range(bounds.position.y + 80, bounds.end.y - 80))
