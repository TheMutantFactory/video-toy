extends RefCounted
## Layers and drawing: the three actor layers (base world + two SubViewports
## composited by one blend shader into _worldmix), blend / opacity, the
## actor and ride collections, and draw mode's strokes that become ride
## paths. Owned by the stage, which keeps the state and the delegations.

var s: Stage


func _init(stage: Stage) -> void:
	s = stage


func build() -> void:
	var rides0 := Node2D.new()
	s._world.add_child(rides0)
	s._layers = [{"vp": null, "actors": s._actors, "rides": rides0, "blend": 0, "opacity": 1.0}]
	for i in range(1, s.LAYER_COUNT):
		var vp := SubViewport.new()
		vp.size = s.WORLD
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		s.add_child(vp)
		var actors := Node2D.new()
		vp.add_child(actors)
		var rides := Node2D.new()
		vp.add_child(rides)
		s._layers.append({"vp": vp, "actors": actors, "rides": rides, "blend": 1 if i == 1 else 0, "opacity": 1.0})
	# one full-screen pass composites layers 2 and 3 over the world, into
	# _worldmix - which is what the screen, the feedback and the monitor see
	s._worldmix = SubViewport.new()
	s._worldmix.size = s.WORLD
	s._worldmix.transparent_bg = true
	s._worldmix.disable_3d = true
	s._worldmix.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	s.add_child(s._worldmix)
	s._layer_mix = ColorRect.new()
	s._layer_mix.size = Vector2(s.WORLD)
	s._layer_mix.color = Color.WHITE
	s._layer_mix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = s.BLEND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("world_tex", s._world.get_texture())
	mat.set_shader_parameter("layer1", s._layers[1]["vp"].get_texture())
	mat.set_shader_parameter("layer2", s._layers[2]["vp"].get_texture())
	s._layer_mix.material = mat
	s._worldmix.add_child(s._layer_mix)
	s._stroke_line = Line2D.new()
	s._stroke_line.width = 4.0
	s._stroke_line.z_index = 2
	s._world.add_child(s._stroke_line)
	apply()


func apply() -> void:
	var m: ShaderMaterial = s._layer_mix.material
	for i in [1, 2]:
		m.set_shader_parameter("mode%d" % i, int(s._layers[i]["blend"]))
		m.set_shader_parameter("opacity%d" % i, float(s._layers[i]["opacity"]))


func layer_actors() -> Node2D:
	return s._layers[s.active_layer]["actors"]


func all_actors() -> Array:
	var out: Array = []
	for l in s._layers:
		out.append_array(l["actors"].get_children())
		for r in l["rides"].get_children():
			out.append_array(r.riders())
	return out


func all_rides() -> Array:
	var out: Array = []
	for l in s._layers:
		out.append_array(l["rides"].get_children())
	return out


func set_active_layer(i: int) -> void:
	s.active_layer = posmod(i, s.LAYER_COUNT)
	s._update_hud()


func cycle_blend() -> void:
	var l: Dictionary = s._layers[s.active_layer]
	if l["vp"] == null:
		s._steal_note = "layer 1 is the base; blend modes are for layers 2 and 3"
	else:
		l["blend"] = (int(l["blend"]) + 1) % s.BLENDS.size()
		apply()
	s._update_hud()


func set_layer_opacity(v: float) -> void:
	s._layers[s.active_layer]["opacity"] = clampf(v, 0.0, 1.0)
	apply()
	s._update_hud()


func clear_actors() -> void:
	for a in all_actors():
		a.queue_free()
	for r in all_rides():
		r.queue_free()


func describe() -> String:
	var l: Dictionary = s._layers[s.active_layer]
	if l["vp"] == null:
		return "1/%d base" % s.LAYER_COUNT
	return "%d/%d %s %d%%" % [s.active_layer + 1, s.LAYER_COUNT, s.BLENDS[l["blend"]], roundi(float(l["opacity"]) * 100.0)]


# ---------------- draw mode ----------------
func begin_stroke(world_pos: Vector2) -> void:
	s._stroke = PackedVector2Array([world_pos])
	s._stroke_start = world_pos
	s._stroke_line.default_color = Color(Palettes.color(s.palette_index, 0), 0.8)
	s._stroke_line.points = s._stroke


func extend_stroke(world_pos: Vector2) -> void:
	if s._stroke.is_empty():
		return
	if s._stroke[s._stroke.size() - 1].distance_to(world_pos) >= 6.0:
		s._stroke.append(world_pos)
		s._stroke_line.points = s._stroke


## Returns the number of riders made (0 = the stroke was just a click).
func end_stroke() -> int:
	var pts := s._stroke
	s._stroke = PackedVector2Array()
	s._stroke_line.points = PackedVector2Array()
	if pts.size() < 2 or s.RidePathScript.length_of(pts) < 60.0:
		s.spawn_at(s._stroke_start)
		return 0
	var slot := Toolbox.current()
	if slot.is_empty():
		return 0
	var ride := Node2D.new()
	ride.set_script(s.RidePathScript)
	s._layers[s.active_layer]["rides"].add_child(ride)
	var pal: int = s.palette_index
	var world: Vector2i = s.WORLD
	var actor_script: GDScript = s.ActorScript
	var n: int = ride.setup(pts, slot, Palettes.color(pal, 0), func(pos: Vector2) -> Node2D:
		var a := Node2D.new()
		a.set_script(actor_script)
		a.setup(slot, pos, pal, Rect2(Vector2.ZERO, Vector2(world)))
		return a)
	s._steal_note = "%d riders on a %d px path" % [n, s.RidePathScript.length_of(pts)]
	s._update_hud()
	return n
