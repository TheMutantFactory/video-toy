extends Node3D
## A 3D shape wearing an icon. Two meshes: a dim opaque body (lit, so the shape
## reads) and a slightly larger unshaded skin carrying the white icon texture
## tinted with the palette colour, tiled once per face. Verbs are read live
## from the toolbox slot, like actor.gd, and mapped into 3D.

const SHAPES := ["cube", "sphere", "torus", "cylinder", "prism"]

var slot_id := ""
var shape := "cube"
var bounds := Vector3(4.0, 2.2, 2.0)
var home := Vector3.ZERO
var velocity := Vector3.ZERO
var angle := 0.0
var t := 0.0
var base_scale := 1.0
var orbit_radius := 2.0
var wander_target := Vector3.ZERO
var mouse_point := Vector3.ZERO
var spin_axis := Vector3(0.3, 1.0, 0.2).normalized()

var _body: MeshInstance3D
var _skin: MeshInstance3D
var _body_mat: StandardMaterial3D
var _skin_mat: StandardMaterial3D
var _base_color := Color.WHITE


static func make_mesh(kind: String) -> Mesh:
	match kind:
		"sphere":
			var m := SphereMesh.new()
			m.radius = 0.7
			m.height = 1.4
			return m
		"torus":
			var m := TorusMesh.new()
			m.inner_radius = 0.35
			m.outer_radius = 0.8
			return m
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = 0.6
			m.bottom_radius = 0.6
			m.height = 1.2
			return m
		"prism":
			var m := PrismMesh.new()
			m.size = Vector3(1.3, 1.2, 1.3)
			return m
		_:
			var m := BoxMesh.new()
			m.size = Vector3.ONE * 1.1
			return m


## Godot's primitives lay UVs out as atlases; scaling UV1 makes the whole
## icon land once per face / band instead of a sliver.
static func uv_scale(kind: String) -> Vector3:
	match kind:
		"cube": return Vector3(3, 2, 1)
		"sphere": return Vector3(4, 2, 1)
		"torus": return Vector3(6, 2, 1)
		"cylinder": return Vector3(3, 1, 1)
		"prism": return Vector3(3, 2, 1)
	return Vector3.ONE


## `icon` is the white-on-alpha texture for the slot (the stage passes it in so
## this script has no autoload dependency and stays testable headless).
func setup(slot: Dictionary, kind: String, pos: Vector3, pal: int, icon: Texture2D) -> void:
	slot_id = str(slot.get("id", ""))
	shape = kind
	position = pos
	home = pos
	t = randf() * TAU
	angle = randf() * TAU
	base_scale = randf_range(0.8, 1.3)
	orbit_radius = randf_range(1.2, 2.8)
	velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.5, 0.5)).normalized() * randf_range(1.5, 3.0)
	wander_target = _random_point()
	rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	_base_color = Palettes.color(pal, int(slot.get("color_index", 0)))

	var mesh := make_mesh(kind)
	_body = MeshInstance3D.new()
	_body.mesh = mesh
	_body_mat = StandardMaterial3D.new()
	_body_mat.roughness = 0.55
	_body.material_override = _body_mat
	add_child(_body)

	_skin = MeshInstance3D.new()
	_skin.mesh = mesh
	_skin.scale = Vector3.ONE * 1.015
	_skin_mat = StandardMaterial3D.new()
	_skin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_skin_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_skin_mat.alpha_scissor_threshold = 0.5
	_skin_mat.albedo_texture = icon
	_skin_mat.uv1_scale = uv_scale(kind)
	_skin_mat.texture_repeat = true
	_skin.material_override = _skin_mat
	add_child(_skin)
	_apply_color(_base_color)
	scale = Vector3.ONE * base_scale


func set_palette(pal: int, color_index: int) -> void:
	_base_color = Palettes.color(pal, color_index)
	_apply_color(_base_color)


func _apply_color(c: Color) -> void:
	_skin_mat.albedo_color = c
	_body_mat.albedo_color = c.darkened(0.72)


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
		for axis in 3:
			if absf(position[axis]) > bounds[axis]:
				velocity[axis] = -velocity[axis]
				position[axis] = clampf(position[axis], -bounds[axis], bounds[axis])
		home = position
		moved = true
	if verbs.has("wander"):
		if position.distance_to(wander_target) < 0.15:
			wander_target = _random_point()
		position = position.move_toward(wander_target, 1.2 * delta)
		home = position
		moved = true
	if verbs.has("swarm"):
		velocity = velocity.lerp((mouse_point - position).normalized() * 3.0, 2.0 * delta)
		position += velocity * delta
		home = position
		moved = true
	if verbs.has("orbit"):
		angle += delta * 1.1
		var r := orbit_radius * (0.35 if moved else 1.0)
		var centre := position if moved else home
		position = centre + Vector3(cos(angle), sin(angle) * 0.6, sin(angle * 0.7) * 0.4) * r

	# Solids always turn a little so their faces catch the light; Spin is fast.
	rotate(spin_axis, delta * (2.4 if verbs.has("spin") else 0.35))
	var s := base_scale
	if verbs.has("pulse"):
		s *= 1.0 + 0.25 * sin(t * 4.0)
	scale = Vector3.ONE * s
	if verbs.has("rainbow"):
		var c := _base_color
		c.h = fmod(c.h + t * 0.25, 1.0)
		c.s = maxf(c.s, 0.7)
		_apply_color(c)
	else:
		_apply_color(_base_color)


func _random_point() -> Vector3:
	return Vector3(randf_range(-bounds.x, bounds.x), randf_range(-bounds.y, bounds.y), randf_range(-bounds.z, bounds.z))
