extends RefCounted
## 3D solids, formations and the camera.
## Owned by the stage (src/stage_screen.gd), which exposes these as one-line
## delegations; `s` is the stage, whose state stays in one place.

var s: Stage


func _init(stage: Stage) -> void:
	s = stage


func _build_3d() -> void:
	s._world3d = SubViewport.new()
	s._world3d.size = s.WORLD
	s._world3d.transparent_bg = true
	s._world3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	s._world3d.msaa_3d = Viewport.MSAA_2X
	s.add_child(s._world3d)
	s._camera = Camera3D.new()
	s._camera.position = Vector3(0, 0, 7.5)
	s._camera.fov = 55.0
	s._world3d.add_child(s._camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.4
	s._world3d.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.environment.ambient_light_energy = 0.9
	s._world3d.add_child(env)
	s._solids = Node3D.new()
	s._world3d.add_child(s._solids)
	s._formations = Node3D.new()
	s._world3d.add_child(s._formations)
	var sprite := Sprite2D.new()
	sprite.texture = s._world3d.get_texture()
	sprite.position = Vector2(s.WORLD) * 0.5
	s._world.add_child(sprite)


func next_shape() -> String:
	return s.SolidScript.SHAPES[s._shape_index]


func spawn_solid(world_pos := Vector2(-1, -1)) -> void:
	var slot := Toolbox.current()
	if slot.is_empty():
		return
	var pos: Vector3
	if world_pos.x < 0:
		pos = Vector3(randf_range(-3.5, 3.5), randf_range(-1.8, 1.8), randf_range(-1.5, 1.0))
	else:
		pos = s._camera.project_position(world_pos, s.cam_dolly)
	var sol := Node3D.new()
	sol.set_script(s.SolidScript)
	sol.setup(slot, next_shape(), pos, s.palette_index, IconMedia.texture_for(str(slot.get("svg_path", ""))))
	s._solids.add_child(sol)
	s._update_hud()


func formation_kind() -> String:
	return s.FormationScript.KINDS[s._formation_index]


func cycle_formation() -> void:
	s._formation_index = (s._formation_index + 1) % s.FormationScript.KINDS.size()
	s._update_hud()


## Shift+Space: 200 copies of the selected icon in the current shape and formation.
func spawn_formation(n := 200) -> void:
	var slot := Toolbox.current()
	if slot.is_empty():
		return
	if formation_kind() == "procession":
		n = s.FormationScript.PROCESSION_N
	var icon := IconMedia.texture_for(str(slot.get("svg_path", "")))
	var mesh: Mesh = s.SolidScript.make_mesh(next_shape(), icon.get_image() if (next_shape() == "cookie" and icon) else null)
	var skin := StandardMaterial3D.new()
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	skin.alpha_scissor_threshold = 0.5
	skin.albedo_texture = icon
	skin.uv1_scale = s.SolidScript.uv_scale(next_shape())
	skin.texture_repeat = true
	skin.vertex_color_use_as_albedo = true
	var body := StandardMaterial3D.new()
	body.roughness = 0.55
	body.vertex_color_use_as_albedo = true
	body.albedo_color = Color(0.35, 0.35, 0.35)
	var f := Node3D.new()
	f.set_script(s.FormationScript)
	f.setup(slot, formation_kind(), mesh, [skin, body], n, s.palette_index)
	s._formations.add_child(f)
	s._update_hud()


func reset_camera() -> void:
	s.cam_orbit = 0.0
	s.cam_dolly = 7.5
	s.cam_roll = 0.0
	s.cam_height = 0.0
	s._cam_angle = 0.0
	s._update_hud()


func cycle_shape() -> void:
	s._shape_index = (s._shape_index + 1) % s.SolidScript.SHAPES.size()
	s._update_hud()


# ---------------- scenes ----------------
