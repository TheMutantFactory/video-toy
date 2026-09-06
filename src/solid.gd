extends Node3D
## A 3D shape wearing an icon. Two meshes: a dim opaque body (lit, so the shape
## reads) and a slightly larger unshaded skin carrying the white icon texture
## tinted with the palette colour, tiled once per face. Verbs are read live
## from the toolbox slot, like actor.gd, and mapped into 3D.

const SHAPES := ["cube", "sphere", "torus", "cylinder", "prism", "cookie", "knot"]
const KNOT_HOLD := 1.2                      # seconds a knot rests before tying into the next
const KNOT_DEFORM := 3.0                    # seconds the tying takes

var slot_id := ""
var shape := "cube"
var verb_state := {}                        # per-verb scratch, cleared through leave()
var knot_family := 0                        # Knot.FAMILIES index shown
var knot_next := 1                          # the family it ties into (Morph)
var knot_morph := 0.0                       # 0 = this family, 1 = the next
var knot_tube := 0.16
var _knot_hold := 0.0
var _knot_frame := 0
var bounds := Vector3(4.0, 2.2, 2.0)
var home := Vector3.ZERO
var velocity := Vector3.ZERO
var angle := 0.0
var t := 0.0
var base_scale := 1.0
var orbit_radius := 2.0
var wander_target := Vector3.ZERO
var mouse_point := Vector3.ZERO
var attract := false
var spin_axis := Vector3(0.3, 1.0, 0.2).normalized()
var _orbit_off := Vector3.ZERO
var _att := Vector3(1, 1, 20)
var _map := Vector2.ZERO
var _map_from := Vector2.ZERO
var _map_t := 1.0

var _body: MeshInstance3D
var _skin: MeshInstance3D
var _particles: CPUParticles3D
var _pmat: StandardMaterial3D
var _body_mat: StandardMaterial3D
var _skin_mat: StandardMaterial3D
var _base_color := Color.WHITE
var raster := false


## `icon_img` is only needed for "cookie" (the extruded icon).
static func make_mesh(kind: String, icon_img: Image = null) -> Mesh:
	match kind:
		"cookie":
			if icon_img == null:
				var m := BoxMesh.new()
				m.size = Vector3(1.4, 1.4, 0.35)
				return m
			return Extrude.build(icon_img)
		"knot":
			return Knot.mesh_for(2, 3, 2, 3, 0.0, 0.16)
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
		"cookie": return Vector3(1, 1, 1)
		"knot": return Vector3(8, 1, 1)
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
	raster = str(slot.get("kind", "icon")) == "raster"
	_base_color = Palettes.color(pal, int(slot.get("color_index", 0)))

	if kind == "knot":
		knot_family = randi() % Knot.FAMILIES.size()
		knot_next = (knot_family + 1) % Knot.FAMILIES.size()
	var mesh := make_mesh(kind, icon.get_image() if (kind == "cookie" and icon) else null)
	if kind == "knot":
		mesh = _knot_mesh()
	_body = MeshInstance3D.new()
	_body.mesh = mesh
	_body_mat = StandardMaterial3D.new()
	_body_mat.roughness = 0.55
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
	if kind == "cookie":
		# One mesh, two surfaces: textured faces (skin) + plain sides (body).
		_body.set_surface_override_material(0, _skin_mat)
		_body.set_surface_override_material(1, _body_mat)
		_skin.visible = false
	else:
		_body.material_override = _body_mat
		_skin.material_override = _skin_mat
	add_child(_skin)

	# Sparkle: little billboarded copies of the icon drifting off the solid.
	_particles = CPUParticles3D.new()
	_particles.emitting = false
	_particles.amount = 30
	_particles.lifetime = 1.4
	_particles.direction = Vector3(0, 1, 0)
	_particles.spread = 180.0
	_particles.gravity = Vector3(0, -0.6, 0)
	_particles.initial_velocity_min = 0.6
	_particles.initial_velocity_max = 1.6
	_particles.scale_amount_min = 0.08
	_particles.scale_amount_max = 0.16
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_pmat = StandardMaterial3D.new()
	_pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_pmat.alpha_scissor_threshold = 0.5
	_pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_pmat.albedo_texture = icon
	quad.material = _pmat
	_particles.mesh = quad
	add_child(_particles)
	_apply_color(_base_color)
	scale = Vector3.ONE * base_scale


func set_palette(pal: int, color_index: int) -> void:
	_base_color = Palettes.color(pal, color_index)
	_apply_color(_base_color)


func _apply_color(c: Color) -> void:
	# A raster keeps its own colours; the body under it still takes the palette.
	_skin_mat.albedo_color = c if not raster or c != _base_color else Color.WHITE
	_body_mat.albedo_color = c.darkened(0.72)
	if _pmat:
		_pmat.albedo_color = _skin_mat.albedo_color


func _verbs() -> Array:
	var i := Toolbox.index_of(slot_id)
	if i < 0:
		queue_free()
		return []
	return Toolbox.slots[i].get("verbs", [])


var moved := false
var frame_scale := 1.0
var active_ids: Array = []
var beat_hit := false


func audio_active() -> bool:
	return AudioReact.active()


func audio_bass() -> float:
	return AudioReact.bass


func beat_env() -> float:
	return AudioReact.beat_env


func _process(delta: float) -> void:
	var verbs := _verbs()
	if not is_inside_tree():
		return
	t += delta
	active_ids = verbs
	position -= _orbit_off
	_orbit_off = Vector3.ZERO
	moved = false
	var active := Verbs.active_for(verbs)
	for v in active:
		if v.has_motion3d() and v.move3d(self, delta):
			moved = true
	# Solids always turn a little so their faces catch the light; Spin adds to it.
	rotate(spin_axis, delta * 0.35)
	frame_scale = base_scale
	_apply_color(_base_color)
	_particles.emitting = false
	for v in active:
		v.post3d(self, delta)
	if AudioReact.active():
		frame_scale *= 1.0 + 0.18 * AudioReact.beat_env
	scale = Vector3.ONE * frame_scale
	if shape == "knot":
		_tick_knot(verbs, delta)


# ---------------- TonKnoT ----------------
func _knot_mesh() -> ArrayMesh:
	var a: Array = Knot.FAMILIES[knot_family]
	var b: Array = Knot.FAMILIES[knot_next]
	return Knot.mesh_for(a[0], a[1], b[0], b[1], knot_morph, knot_tube)


func _rebuild_knot() -> void:
	var mesh := _knot_mesh()
	_body.mesh = mesh
	_skin.mesh = mesh


## The arrow flows along the tube always; with Morph the knot rests, then ties
## itself into the next family over KNOT_DEFORM seconds, and starts again.
func _tick_knot(verbs: Array, delta: float) -> void:
	_skin_mat.uv1_offset.x = fmod(_skin_mat.uv1_offset.x + delta * 0.12, 1.0)
	if not verbs.has("morph"):
		return
	_knot_frame += 1
	if _knot_hold > 0.0:
		_knot_hold = maxf(0.0, _knot_hold - delta)
		return
	knot_morph = minf(1.0, knot_morph + delta / KNOT_DEFORM)
	if _knot_frame % 3 == 0 or knot_morph >= 1.0:
		_rebuild_knot()
	if knot_morph >= 1.0:
		knot_family = knot_next
		knot_next = (knot_family + 1) % Knot.FAMILIES.size()
		knot_morph = 0.0
		_knot_hold = KNOT_HOLD
		_rebuild_knot()


## Tie into a given family now (the stage's "next knot" action).
func knot_jump(family: int) -> void:
	if shape != "knot":
		return
	knot_family = knot_next if knot_morph >= 0.5 else knot_family
	knot_next = posmod(family, Knot.FAMILIES.size())
	knot_morph = 0.0
	_knot_hold = 0.0
	_rebuild_knot()


func set_knot_tube(r: float) -> void:
	if shape != "knot":
		return
	knot_tube = clampf(r, 0.05, 0.35)
	_rebuild_knot()


func knot_describe() -> String:
	return "%s→%s %.0f%%" % [Knot.family_name(knot_family), Knot.family_name(knot_next), knot_morph * 100.0] if shape == "knot" else ""


func _random_point() -> Vector3:
	return Vector3(randf_range(-bounds.x, bounds.x), randf_range(-bounds.y, bounds.y), randf_range(-bounds.z, bounds.z))
