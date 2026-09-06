extends Control
## Play mode. The world renders into a SubViewport; two more viewports ping-pong
## the previous frame back in (zoomed, rotated, faded) for classic video
## feedback — the "camera pointed at its own monitor" effect.
##
## Keys: 1-9 slot · Q W E R T Y U I verbs · click spawn · right-click remove
## · Space random spawn · P palette · F feedback · [ ] zoom · , . rotate
## · - = fade · O kaleidoscope · G chroma key (drop an image for the backdrop)
## · K pixelate · L palette quantise · J dither · V CRT · M monitor · N monitor size
## · drag the monitor to move it · B spawn a 3D solid of the selected icon
## · Shift+B next shape · ; MIDI + audio panel · A audio source (drop an audio file)
## · drop an image = raster slot (Shift+drop = chroma backdrop) · Z webcam layer
## · S steal a palette from the selected raster / webcam · D glow
## · F1-F12 recall preset · Shift+F1-F12 save preset · Tab / Shift+Tab next / previous scene
## · ` scene off · arrows feedback drift · PgUp/PgDn feedback warp · Home reset warp
## · Shift+arrows camera orbit / dolly · Shift+PgUp/PgDn camera roll · Shift+Home reset camera
## · Shift+Space spawn a formation (Shift+X next formation)
## · \ next layer · Shift+\ blend mode · Shift+[ ] layer opacity · Shift+D draw mode
## · C clear · H help · Esc menu
##
## Layers: layer 1 is the world itself; layers 2 and 3 are transparent
## viewports whose actors composite into the world through a sprite with a
## CanvasItemMaterial blend mode and an opacity, so feedback, effects and the
## monitor see the blended result.
##
## Render graph:  world3d (solids) ─> sprite in world
##                world (actors + monitor + world3d) ─┬─> screen ──┐
##                                          └─> acc A/B ─┘ (feedback ping-pong)
##                composite = bg + screen + fx  ──> display (stage) and monitor (world)

signal navigate(name: String)

const HotbarScript = preload("res://src/hotbar.gd")
const ActorScript = preload("res://src/actor.gd")
const FxScript = preload("res://src/fx.gd")
const MonitorScript = preload("res://src/monitor.gd")
const SolidScript = preload("res://src/solid.gd")
const MidiPanelScript = preload("res://src/midi_panel.gd")
const WebcamScript = preload("res://src/webcam.gd")
const GlowScript = preload("res://src/glow.gd")
const SceneLayerScript = preload("res://src/scene_layer.gd")
const FormationScript = preload("res://src/formation.gd")
const RidePathScript = preload("res://src/ride_path.gd")
const P2CursorScript = preload("res://src/p2_cursor.gd")
const P2_SPEED := 800.0
const RD_PRESETS := [
	{"name": "off", "feed": 0.0, "kill": 0.0},
	{"name": "coral", "feed": 0.0545, "kill": 0.062},
	{"name": "mitosis", "feed": 0.0367, "kill": 0.0649},
	{"name": "worms", "feed": 0.078, "kill": 0.061},
	{"name": "spots", "feed": 0.030, "kill": 0.062},
	{"name": "waves", "feed": 0.014, "kill": 0.045},
]
const RD_SIZE := Vector2i(480, 270)
const LAYER_COUNT := 3
const BLENDS := ["mix", "add", "sub", "mul"]
## Layer compositing is one shader pass in its own viewport (_worldmix) that
## reads the world texture and the two layer textures directly: Godot's
## MUL/SUB blend factors turn a transparent layer black, screen-reading sprites
## share one back-buffer copy, and the screen copy loses alpha - which feedback
## needs. blend_disabled = write the composed rgba as computed.
const BLEND_SHADER := """
shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D world_tex : filter_nearest, repeat_disable;
uniform sampler2D rd_tex : filter_linear, repeat_disable;
uniform bool rd_on = false;
uniform int palette_count = 0;
uniform vec4 palette[16];
uniform sampler2D layer1 : filter_linear, repeat_disable;
uniform sampler2D layer2 : filter_linear, repeat_disable;
uniform int mode1 = 0;      // 0 mix, 1 add, 2 sub, 3 mul
uniform int mode2 = 0;
uniform float opacity1 = 1.0;
uniform float opacity2 = 1.0;

vec4 blend(vec4 dst, vec4 src, int mode) {
	vec3 c;
	if (mode == 1) c = dst.rgb + src.rgb * src.a;
	else if (mode == 2) c = dst.rgb - src.rgb * src.a;
	else if (mode == 3) c = mix(dst.rgb, dst.rgb * src.rgb, src.a);
	else c = mix(dst.rgb, src.rgb, src.a);
	float a = (mode == 3) ? dst.a : dst.a + src.a * (1.0 - dst.a);
	return vec4(clamp(c, 0.0, 1.0), a);
}

vec3 ring_color(float t) {
	int n = max(palette_count - 1, 1);
	float f = fract(t) * float(n);
	int i = int(floor(f));
	int j = (i + 1) % n;
	return mix(palette[i].rgb, palette[j].rgb, smoothstep(0.0, 1.0, fract(f)));
}

void fragment() {
	vec4 dst = texture(world_tex, UV);
	if (rd_on) {
		// reaction-diffusion painted UNDER the world: V through the palette
		float v = texture(rd_tex, UV).g;
		float a = smoothstep(0.08, 0.35, v);
		vec4 rd = vec4(ring_color(v * 1.6 + 0.15), a);
		dst = vec4(mix(rd.rgb, dst.rgb, dst.a), dst.a + rd.a * (1.0 - dst.a));
	}
	vec4 s1 = texture(layer1, UV);
	s1.a *= opacity1;
	dst = blend(dst, s1, mode1);
	vec4 s2 = texture(layer2, UV);
	s2.a *= opacity2;
	dst = blend(dst, s2, mode2);
	COLOR = dst;
}
"""
const WEBCAM_MODES := ["off", "layer", "backdrop"]
const WORLD := Vector2i(1920, 1080)

var palette_index := 0
var feedback := false
var fb_zoom := 1.04
var fb_rot := 0.02
var fb_fade := 0.92

var _world: SubViewport
var _bg: ColorRect
var _actors: Node2D
var _acc: Array = []                    # two SubViewports
var _acc_prev: Array = []               # their "previous frame" sprites
var _acc_live: Array = []               # their "live world" sprites
var _flip := 0
var _screen: TextureRect
var _composite: SubViewport
var _display: TextureRect
var _monitor: Node2D
var _world3d: SubViewport
var _camera: Camera3D
var _solids: Node3D
var _shape_index := 0
var _midi_panel: PanelContainer
var _midi_last := ""
var _webcam: Node2D
var _webcam_vp: SubViewport
var _webcam_sprite: Sprite2D
var _webcam_mode := 0
var _steal_note := ""
var _glow
var _fade_tween: Tween
var _scene_layer: Node2D
var _acc_mats: Array = []               # warp ShaderMaterials, one per accumulator
var fb_warp := 0.0
var fb_warp_speed := 1.0
var fb_drift := Vector2.ZERO
var fb_stretch := Vector2.ONE
var cam_orbit := 0.0                    # rad/s around the origin
var cam_dolly := 7.5                    # distance
var cam_roll := 0.0
var cam_height := 0.0
var _cam_angle := 0.0
var _formations: Node3D
var _formation_index := 0
var _layers: Array = []                 # {vp, actors, rides, sprite, blend, opacity}
var active_layer := 0
var draw_mode := false
var _stroke := PackedVector2Array()
var _stroke_line: Line2D
var _stroke_start := Vector2.ZERO
var evolve := false
var _evolve_base := {}
var _evolve_timer := 0.0
var _evolve_beats := 0
var _evolve_last := ""
var attract := false
var _attract_base := {}
var _attract_timer := 0.0
var _idle := 0.0
var timeline := Timeline.new()
var _clock := 0.0
var _particles: GPUParticles2D
var _pmat: ShaderMaterial
var particles_on := false
var particles_flow := 1.0
var particles_attract := 0.5
var _scatter_until := 0.0
var _rd: Array = []                     # two RD viewports (ping-pong)
var _rd_mats: Array = []
var _rd_flip := 0
var rd_preset := 0
var rd_feed := 0.0545
var rd_kill := 0.062
var _videos := {}                       # slot path -> {vp, player}
var _live_timer := 0.0
var _cycle_timer := 0.0
var _cycle_last_beat := 0.0
var _syphon: Node
var syphon_on := false
var _play_pending := false
var _ticker: Label
var ticker_on := false
var _roll: Control
var _roll_body: VBoxContainer
var _roll_t := 0.0
var _roll_speed := 60.0
var bank := 0
var preset_fade := 1.0
var last_preset := 0
var _xf := {}                            # {from, to, t, dur}
var _morph_a := {}
var quality := Quality.new()
var _quality_applied := -1
var _measured: Array = []               # viewport RIDs with render-time measurement on
var work_ms := 0.0                      # script + measured render time, vsync excluded
var _blackout: ColorRect
var blackout := false
var _blackout_tween: Tween
var p2_active := false
var p2_slot := 0
var p2_layer := 1
var p2_cursor := Vector2(1440, 540)
var _p2_node: Node2D
const IDLE_ATTRACT := 60.0
const EVOLVE_SECONDS := 6.0
const EVOLVE_BEATS := 8
const ATTRACT_SECONDS := 20.0
var _layer_mix: ColorRect
var _worldmix: SubViewport
var _drag_offset := Vector2.ZERO
var _dragging := false
var _hud: Label
var _help: PanelContainer
var _verb_panel: VBoxContainer
var _verb_checks := {}
var _fx_pixel_btn: Button
var _fx_kaleido_btn: Button
var _fx_crt_btn: Button
var _fx_glow_btn: Button
var _fx_scene_btn: Button
var _fx_key_btn: Button
var _fx_slit_btn: Button
var _fx_quant: CheckButton
var _fx_dither: CheckButton
var _hotbar
var _fx


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# The final picture (bg + world/feedback + fx) renders into _composite so it
	# can be shown twice: on the stage, and on the monitor inside the world.
	_composite = SubViewport.new()
	_composite.size = WORLD
	_composite.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_composite.disable_3d = true
	add_child(_composite)
	# Background lives here, not in the world, so the world texture is
	# transparent except for actors — that is what lets feedback trails decay.
	_bg = ColorRect.new()
	_bg.size = Vector2(WORLD)
	_bg.color = Palettes.bg(palette_index)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite.add_child(_bg)

	_world = SubViewport.new()
	_world.size = WORLD
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world.transparent_bg = true
	_world.disable_3d = true
	add_child(_world)
	_scene_layer = SceneLayerScript.new()
	_scene_layer.size = Vector2(WORLD)
	_world.add_child(_scene_layer)
	_build_webcam()
	_build_3d()
	_actors = Node2D.new()
	_world.add_child(_actors)
	_build_layers()
	_build_particles()
	_build_rd()
	_p2_node = Node2D.new()
	_p2_node.set_script(P2CursorScript)
	_p2_node.z_index = 3
	_p2_node.visible = false
	_p2_node.position = p2_cursor
	_world.add_child(_p2_node)

	for i in 2:
		var vp := SubViewport.new()
		vp.size = WORLD
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.transparent_bg = true
		add_child(vp)
		var prev := MeshInstance2D.new()          # the warp mesh (see feedback_mesh.gd)
		prev.mesh = FeedbackMesh.build(Vector2(WORLD))
		prev.material = FeedbackMesh.material()
		prev.position = Vector2(WORLD) * 0.5
		vp.add_child(prev)
		_acc_mats.append(prev.material)
		var live := Sprite2D.new()
		live.position = Vector2(WORLD) * 0.5
		live.texture = _worldmix.get_texture()
		vp.add_child(live)
		_acc.append(vp)
		_acc_prev.append(prev)
		_acc_live.append(live)
	_acc_prev[0].texture = _acc[1].get_texture()
	_acc_prev[1].texture = _acc[0].get_texture()

	_screen = TextureRect.new()
	_screen.size = Vector2(WORLD)
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.texture = _worldmix.get_texture()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite.add_child(_screen)

	_glow = GlowScript.new()                     # bloom before fx, so CRT sees it
	_composite.add_child(_glow)

	_fx = FxScript.new()
	_composite.add_child(_fx)
	_fx.set_source(_worldmix.get_texture(), Palettes.bg(palette_index))

	_display = TextureRect.new()
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_display.texture = _composite.get_texture()
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_display)

	_blackout = ColorRect.new()
	_blackout.color = Color.BLACK
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blackout.modulate.a = 0.0
	_blackout.visible = false
	add_child(_blackout)

	# credits ticker: one line along the bottom of the picture, under the blackout
	_ticker = UI.label("", 18, Color(0.92, 0.92, 0.95, 0.9))
	_ticker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_ticker.offset_top = -30
	_ticker.offset_left = 16
	_ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ticker.clip_text = true
	_ticker.visible = false
	_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ticker)
	move_child(_ticker, _blackout.get_index())

	# credits roll: scrolls the full ledger up over the picture (end card)
	_roll = Control.new()
	_roll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_roll.clip_contents = true
	_roll.visible = false
	add_child(_roll)
	move_child(_roll, _blackout.get_index())
	_roll_body = VBoxContainer.new()
	_roll_body.add_theme_constant_override("separation", 10)
	_roll_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_roll.add_child(_roll_body)

	_monitor = MonitorScript.new()
	_monitor.setup(_composite.get_texture(), Vector2(WORLD) * 0.5)
	_monitor.visible = false
	_world.add_child(_monitor)

	_build_hud()
	Toolbox.selection_changed.connect(func(_i): _refresh_verbs())
	Toolbox.changed.connect(_refresh_verbs)
	_refresh_verbs()
	_apply_palette()
	_refresh_fx()
	get_window().files_dropped.connect(_on_files_dropped)
	_build_midi()
	_sync_videos()
	Toolbox.changed.connect(_sync_videos)
	var args := OS.get_cmdline_user_args()
	var qi := args.find("--quality")
	if qi >= 0 and qi + 1 < args.size():
		var names := Quality.LEVELS.map(func(l): return l["name"])
		var want: String = args[qi + 1]
		quality.locked = names.find(want) if names.has(want) else (int(want) if want.is_valid_int() else -1)
	apply_quality(quality.effective())
	_enable_measurement()


func _exit_tree() -> void:
	if get_window() and get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)


# ---------------- layers ----------------
func _build_layers() -> void:
	var rides0 := Node2D.new()
	_world.add_child(rides0)
	_layers = [{"vp": null, "actors": _actors, "rides": rides0, "blend": 0, "opacity": 1.0}]
	for i in range(1, LAYER_COUNT):
		var vp := SubViewport.new()
		vp.size = WORLD
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var actors := Node2D.new()
		vp.add_child(actors)
		var rides := Node2D.new()
		vp.add_child(rides)
		_layers.append({"vp": vp, "actors": actors, "rides": rides, "blend": 1 if i == 1 else 0, "opacity": 1.0})
	# one full-screen pass composites layers 2 and 3 over the world, into
	# _worldmix - which is what the screen, the feedback and the monitor see
	_worldmix = SubViewport.new()
	_worldmix.size = WORLD
	_worldmix.transparent_bg = true
	_worldmix.disable_3d = true
	_worldmix.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_worldmix)
	_layer_mix = ColorRect.new()
	_layer_mix.size = Vector2(WORLD)
	_layer_mix.color = Color.WHITE
	_layer_mix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = BLEND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("world_tex", _world.get_texture())
	mat.set_shader_parameter("layer1", _layers[1]["vp"].get_texture())
	mat.set_shader_parameter("layer2", _layers[2]["vp"].get_texture())
	_layer_mix.material = mat
	_worldmix.add_child(_layer_mix)
	_stroke_line = Line2D.new()
	_stroke_line.width = 4.0
	_stroke_line.z_index = 2
	_world.add_child(_stroke_line)
	_apply_layers()


func _apply_layers() -> void:
	var m: ShaderMaterial = _layer_mix.material
	for i in [1, 2]:
		m.set_shader_parameter("mode%d" % i, int(_layers[i]["blend"]))
		m.set_shader_parameter("opacity%d" % i, float(_layers[i]["opacity"]))


func layer_actors() -> Node2D:
	return _layers[active_layer]["actors"]


func all_actors() -> Array:
	var out: Array = []
	for l in _layers:
		out.append_array(l["actors"].get_children())
		for r in l["rides"].get_children():
			out.append_array(r.riders())
	return out


func all_rides() -> Array:
	var out: Array = []
	for l in _layers:
		out.append_array(l["rides"].get_children())
	return out


func set_active_layer(i: int) -> void:
	active_layer = posmod(i, LAYER_COUNT)
	_update_hud()


func cycle_blend() -> void:
	var l: Dictionary = _layers[active_layer]
	if l["vp"] == null:
		_steal_note = "layer 1 is the base; blend modes are for layers 2 and 3"
	else:
		l["blend"] = (int(l["blend"]) + 1) % BLENDS.size()
		_apply_layers()
	_update_hud()


func set_layer_opacity(v: float) -> void:
	_layers[active_layer]["opacity"] = clampf(v, 0.0, 1.0)
	_apply_layers()
	_update_hud()


func clear_actors() -> void:
	for a in all_actors():
		a.queue_free()
	for r in all_rides():
		r.queue_free()


func layer_describe() -> String:
	var l: Dictionary = _layers[active_layer]
	if l["vp"] == null:
		return "1/%d base" % LAYER_COUNT
	return "%d/%d %s %d%%" % [active_layer + 1, LAYER_COUNT, BLENDS[l["blend"]], roundi(float(l["opacity"]) * 100.0)]


# ---------------- draw mode ----------------
func begin_stroke(world_pos: Vector2) -> void:
	_stroke = PackedVector2Array([world_pos])
	_stroke_start = world_pos
	_stroke_line.default_color = Color(Palettes.color(palette_index, 0), 0.8)
	_stroke_line.points = _stroke


func extend_stroke(world_pos: Vector2) -> void:
	if _stroke.is_empty():
		return
	if _stroke[_stroke.size() - 1].distance_to(world_pos) >= 6.0:
		_stroke.append(world_pos)
		_stroke_line.points = _stroke


## Returns the number of riders made (0 = the stroke was just a click).
func end_stroke() -> int:
	var pts := _stroke
	_stroke = PackedVector2Array()
	_stroke_line.points = PackedVector2Array()
	if pts.size() < 2 or RidePathScript.length_of(pts) < 60.0:
		spawn_at(_stroke_start)
		return 0
	var slot := Toolbox.current()
	if slot.is_empty():
		return 0
	var ride := Node2D.new()
	ride.set_script(RidePathScript)
	_layers[active_layer]["rides"].add_child(ride)
	var n: int = ride.setup(pts, slot, Palettes.color(palette_index, 0), func(pos: Vector2) -> Node2D:
		var a := Node2D.new()
		a.set_script(ActorScript)
		a.setup(slot, pos, palette_index, Rect2(Vector2.ZERO, Vector2(WORLD)))
		return a)
	_steal_note = "%d riders on a %d px path" % [n, RidePathScript.length_of(pts)]
	_update_hud()
	return n


# ---------------- particle field ----------------
func _build_particles() -> void:
	_particles = GPUParticles2D.new()
	_particles.amount = 12000
	_particles.lifetime = 600.0
	_particles.explosiveness = 1.0            # all at once; emission would otherwise trickle over the lifetime
	_particles.preprocess = 0.0
	_particles.z_index = -1
	_particles.emitting = false
	_particles.visible = false
	_pmat = ShaderMaterial.new()
	_pmat.shader = load("res://src/particles.gdshader")
	_pmat.set_shader_parameter("bounds", Vector2(WORLD))
	_pmat.set_shader_parameter("dot_size", 0.6)          # x16 px texture -> ~10 px dots
	_particles.process_material = _pmat
	# a soft dot
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length() / 7.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0)))
	_particles.texture = ImageTexture.create_from_image(img)
	_world.add_child(_particles)
	_push_particles()


func set_particles(on: bool) -> void:
	particles_on = on
	_particles.visible = on
	_particles.emitting = on
	if on:
		_particles.restart()
	_update_hud()


func _push_particles() -> void:
	_pmat.set_shader_parameter("flow", particles_flow)
	var repel := _clock < _scatter_until
	_pmat.set_shader_parameter("attract", -1.0 if repel else particles_attract)
	Scenes.apply_palette(_pmat, palette_index)
	# attractors: the mouse, then the first icons
	var list: Array[Color] = []
	if _display == null:                                   # still building
		return
	var mouse := _world_pos(get_local_mouse_position())
	if Rect2(Vector2.ZERO, Vector2(WORLD)).has_point(mouse):
		list.append(Color(mouse.x, mouse.y, 1.0, 420.0))
	for a in all_actors():
		if list.size() >= 16:
			break
		var gp: Vector2 = a.global_position if a.riding else a.position
		list.append(Color(gp.x, gp.y, 0.6, 260.0))
	var arr: Array[Color] = list.duplicate()
	while arr.size() < 16:
		arr.append(Color(0, 0, 0, 1))
	_pmat.set_shader_parameter("attractors", PackedColorArray(arr))
	_pmat.set_shader_parameter("attractor_count", list.size())


func scatter_particles() -> void:
	_scatter_until = _clock + 0.35


# ---------------- reaction-diffusion ----------------
## Gray-Scott in two 480x270 viewports that alternate each frame; the world
## texture seeds V, and _worldmix paints V through the palette under the
## actors (see BLEND_SHADER).
func _build_rd() -> void:
	for i in 2:
		var vp := SubViewport.new()
		vp.size = RD_SIZE
		vp.disable_3d = true
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var r := ColorRect.new()
		r.size = Vector2(RD_SIZE)
		r.color = Color.WHITE
		var m := ShaderMaterial.new()
		m.shader = load("res://src/rd.gdshader")
		m.set_shader_parameter("seed_tex", _world.get_texture())
		m.set_shader_parameter("texel", Vector2(1.0 / RD_SIZE.x, 1.0 / RD_SIZE.y))
		r.material = m
		vp.add_child(r)
		_rd.append(vp)
		_rd_mats.append(m)
	_rd_mats[0].set_shader_parameter("prev_tex", _rd[1].get_texture())
	_rd_mats[1].set_shader_parameter("prev_tex", _rd[0].get_texture())
	_layer_mix.material.set_shader_parameter("rd_tex", _rd[0].get_texture())
	_push_rd()


func set_rd_preset(i: int) -> void:
	rd_preset = posmod(i, RD_PRESETS.size())
	var p: Dictionary = RD_PRESETS[rd_preset]
	if rd_preset > 0:
		rd_feed = p["feed"]
		rd_kill = p["kill"]
	if rd_preset == 0:
		for vp in _rd:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_push_rd()
	_update_hud()


func cycle_rd() -> void:
	set_rd_preset(rd_preset + 1)


func _push_rd() -> void:
	for m in _rd_mats:
		m.set_shader_parameter("feed", rd_feed)
		m.set_shader_parameter("kill", rd_kill)
	_layer_mix.material.set_shader_parameter("rd_on", rd_preset > 0)


func _tick_rd() -> void:
	if rd_preset == 0:
		return
	if Engine.get_process_frames() % int(Quality.get_level(quality.effective())["rd_every"]) != 0:
		return
	var cur := _rd_flip
	_rd_flip = 1 - _rd_flip
	_rd[1 - cur].render_target_update_mode = SubViewport.UPDATE_DISABLED
	_rd[cur].render_target_update_mode = SubViewport.UPDATE_ONCE
	_layer_mix.material.set_shader_parameter("rd_tex", _rd[cur].get_texture())


func rd_describe() -> String:
	if rd_preset == 0:
		return "off"
	return "%s f%.3f k%.3f" % [RD_PRESETS[rd_preset]["name"], rd_feed, rd_kill]


# ---------------- webcam ----------------
## The camera renders into its own viewport so one RGB texture serves both the
## world layer (behind everything, so it feeds back and gets the effects) and
## the chroma-key backdrop.
func _build_webcam() -> void:
	_webcam_vp = SubViewport.new()
	_webcam_vp.size = Vector2i(960, 540)
	_webcam_vp.transparent_bg = false
	_webcam_vp.disable_3d = true
	_webcam_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_webcam_vp)
	_webcam = WebcamScript.new()
	_webcam.box = Vector2(960, 540)
	_webcam.position = Vector2(480, 270)
	_webcam.set_process(false)
	_webcam_vp.add_child(_webcam)
	_webcam_sprite = Sprite2D.new()
	_webcam_sprite.texture = _webcam_vp.get_texture()
	_webcam_sprite.position = Vector2(WORLD) * 0.5
	_webcam_sprite.scale = Vector2(2, 2)
	_webcam_sprite.z_index = -2
	_webcam_sprite.visible = false
	_world.add_child(_webcam_sprite)


func webcam_mode() -> String:
	return WEBCAM_MODES[_webcam_mode]


func set_webcam_mode(i: int) -> void:
	if posmod(i, WEBCAM_MODES.size()) == _webcam_mode and _webcam != null and (_webcam_mode == 0) == (not _webcam.is_processing()):
		_refresh_fx()
		return
	_webcam_mode = posmod(i, WEBCAM_MODES.size())
	var on := _webcam_mode > 0
	_webcam.set_process(on)
	if on:
		_webcam.start()
	else:
		_webcam.stop()
	_webcam_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	_webcam_sprite.visible = webcam_mode() == "layer"
	_fx.set_live_backdrop(_webcam_vp.get_texture() if webcam_mode() == "backdrop" else null)
	if webcam_mode() == "backdrop" and _fx.key_mode == 0:
		_fx.key_mode = 1
		_fx._push()
	_refresh_fx()


func cycle_webcam() -> void:
	set_webcam_mode(_webcam_mode + 1)


## S: a palette from the selected raster slot, or the webcam if it is on.
func steal_palette() -> void:
	var img: Image = null
	var name := ""
	var slot := Toolbox.current()
	if _webcam_mode > 0 and _webcam.is_live():
		img = _webcam_vp.get_texture().get_image()
		name = "Webcam"
	elif not slot.is_empty() and Toolbox.is_raster_slot(slot):
		var tex := IconMedia.texture_for(str(slot.get("svg_path", "")))
		if tex:
			img = tex.get_image()
			name = str(slot.get("term", "image")).capitalize()
	if img == null:
		_steal_note = "select a raster slot (or turn the webcam on) to steal a palette"
		_update_hud()
		return
	var p := Palettes.extract(img, name)
	palette_index = Palettes.add_extra(p)
	_apply_palette()
	_steal_note = "stole palette “%s” (%d colours)" % [name, p["ring"].size()]
	_update_hud()


# ---------------- 3D layer ----------------
## A transparent 3D viewport composited into the world as a sprite, so solids
## get feedback, effects and the monitor exactly like the 2D actors.
func _build_3d() -> void:
	_world3d = SubViewport.new()
	_world3d.size = WORLD
	_world3d.transparent_bg = true
	_world3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world3d.msaa_3d = Viewport.MSAA_2X
	add_child(_world3d)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 7.5)
	_camera.fov = 55.0
	_world3d.add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.4
	_world3d.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.environment.ambient_light_energy = 0.9
	_world3d.add_child(env)
	_solids = Node3D.new()
	_world3d.add_child(_solids)
	_formations = Node3D.new()
	_world3d.add_child(_formations)
	var sprite := Sprite2D.new()
	sprite.texture = _world3d.get_texture()
	sprite.position = Vector2(WORLD) * 0.5
	_world.add_child(sprite)


func next_shape() -> String:
	return SolidScript.SHAPES[_shape_index]


func spawn_solid(world_pos := Vector2(-1, -1)) -> void:
	var slot := Toolbox.current()
	if slot.is_empty():
		return
	var pos: Vector3
	if world_pos.x < 0:
		pos = Vector3(randf_range(-3.5, 3.5), randf_range(-1.8, 1.8), randf_range(-1.5, 1.0))
	else:
		pos = _camera.project_position(world_pos, cam_dolly)
	var sol := Node3D.new()
	sol.set_script(SolidScript)
	sol.setup(slot, next_shape(), pos, palette_index, IconMedia.texture_for(str(slot.get("svg_path", ""))))
	_solids.add_child(sol)
	_update_hud()


func formation_kind() -> String:
	return FormationScript.KINDS[_formation_index]


func cycle_formation() -> void:
	_formation_index = (_formation_index + 1) % FormationScript.KINDS.size()
	_update_hud()


## Shift+Space: 200 copies of the selected icon in the current shape and formation.
func spawn_formation(n := 200) -> void:
	var slot := Toolbox.current()
	if slot.is_empty():
		return
	var icon := IconMedia.texture_for(str(slot.get("svg_path", "")))
	var mesh: Mesh = SolidScript.make_mesh(next_shape(), icon.get_image() if (next_shape() == "cookie" and icon) else null)
	var skin := StandardMaterial3D.new()
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	skin.alpha_scissor_threshold = 0.5
	skin.albedo_texture = icon
	skin.uv1_scale = SolidScript.uv_scale(next_shape())
	skin.texture_repeat = true
	skin.vertex_color_use_as_albedo = true
	var body := StandardMaterial3D.new()
	body.roughness = 0.55
	body.vertex_color_use_as_albedo = true
	body.albedo_color = Color(0.35, 0.35, 0.35)
	var f := Node3D.new()
	f.set_script(FormationScript)
	f.setup(slot, formation_kind(), mesh, [skin, body], n, palette_index)
	_formations.add_child(f)
	_update_hud()


func reset_camera() -> void:
	cam_orbit = 0.0
	cam_dolly = 7.5
	cam_roll = 0.0
	cam_height = 0.0
	_cam_angle = 0.0
	_update_hud()


func cycle_shape() -> void:
	_shape_index = (_shape_index + 1) % SolidScript.SHAPES.size()
	_update_hud()


# ---------------- scenes ----------------
func set_scene(id: String, fade := 0.8) -> void:
	Scenes.current = id
	_scene_layer.refresh(fade)
	_update_hud()


func step_scene(step: int) -> void:
	set_scene(Scenes.neighbour(Scenes.current, step))


func set_scene_knobs(speed: float, scale: float, bias: float) -> void:
	Scenes.speed = speed
	Scenes.scale = scale
	Scenes.bias = bias
	_scene_layer.apply_knobs()
	_update_hud()


# ---------------- mosaic ----------------
## Shift+S: the selected slot's picture rebuilt from the toolbox icons.
## A raster picks the icon whose palette colour is nearest each cell; an icon
## or word uses its own shape, cells tinted the slot colour. Cells become
## ordinary actors, so verbs can explode the picture (Bounce) and reform it
## (Orbit around home).
func spawn_mosaic() -> int:
	var slot := Toolbox.current()
	if slot.is_empty():
		return 0
	var tex := IconMedia.texture_for(str(slot.get("svg_path", "")))
	if tex == null:
		return 0
	var img := tex.get_image()
	var cells: Array = Mosaic.cells(img)
	if cells.is_empty():
		return 0
	# candidates: the icon/text slots and their palette colours
	var cand_slots: Array = []
	var cand_colors: Array = []
	for i in Toolbox.slots.size():
		if not Toolbox.is_raster_slot(Toolbox.slots[i]):
			cand_slots.append(Toolbox.slots[i])
			cand_colors.append(Palettes.color(palette_index, int(Toolbox.slots[i].get("color_index", i))))
	if cand_slots.is_empty():
		_steal_note = "mosaic needs at least one icon or word in the toolbox"
		_update_hud()
		return 0
	var is_raster := Toolbox.is_raster_slot(slot)
	var g := Mosaic.grid_size(img)
	var box := Vector2(1600, 900)
	var cell := minf(box.x / g.x, box.y / g.y)
	var origin := (Vector2(WORLD) - Vector2(g) * cell) * 0.5
	var layer := layer_actors()
	for c in cells:
		var src: Dictionary = slot if not is_raster else cand_slots[Mosaic.nearest(c["color"], cand_colors)]
		var a := Node2D.new()
		a.set_script(ActorScript)
		a.setup(src, origin + Vector2(c["u"] * g.x, c["v"] * g.y) * cell, palette_index, Rect2(Vector2.ZERO, Vector2(WORLD)))
		var lum: float = c["lum"] if is_raster else 1.0
		var size_px := cell * lerpf(0.45, 1.05, lum)
		a.base_scale = size_px / maxf(a._sprite.texture.get_size().x, 1.0)
		a._sprite.scale = Vector2.ONE * a.base_scale
		a.orbit_radius = cell * 0.6
		layer.add_child(a)
	_steal_note = "mosaic: %d cells of “%s”" % [cells.size(), slot.get("term", "")]
	_update_hud()
	return cells.size()


# ---------------- evolve ----------------
## One random change to the stage. Returns a description for the HUD.
func mutate() -> String:
	var kinds: Array = ["verb", "verb", "palette", "fx", "feedback", "glow", "scene", "key", "slit", "layer", "camera"]
	match kinds[randi() % kinds.size()]:
		"verb":
			if Toolbox.slots.is_empty():
				return mutate()
			var i := randi() % Toolbox.slots.size()
			var v: String = Verbs.ALL[randi() % Verbs.ALL.size()]["id"]
			Toolbox.toggle_verb(i, v)
			return "%s %s on slot %d" % ["+" if Toolbox.has_verb(i, v) else "-", v, i + 1]
		"palette":
			palette_index = posmod(palette_index + (1 if randf() < 0.5 else -1), Palettes.count())
			_apply_palette()
			return "palette " + str(Palettes.get_palette(palette_index)["name"])
		"fx":
			var which := randi() % 3
			if which == 0:
				_fx.cycle_pixelate()
			elif which == 1:
				_fx.cycle_kaleido()
			else:
				_fx.cycle_crt()
			_refresh_fx()
			return "fx " + _fx.describe()
		"feedback":
			if not feedback or randf() < 0.3:
				_set_feedback(not feedback)
				return "feedback " + ("on" if feedback else "off")
			fb_rot = clampf(fb_rot + randf_range(-0.03, 0.03), -0.15, 0.15)
			fb_zoom = clampf(fb_zoom + randf_range(-0.02, 0.02), 0.95, 1.12)
			return "feedback twist %.2f zoom %.2f" % [fb_rot, fb_zoom]
		"glow":
			_glow.cycle()
			return "glow " + _glow.describe()
		"scene":
			if randf() < 0.3:
				set_scene("")
				return "scene off"
			step_scene(1)
			return "scene " + str(Scenes.get_scene(Scenes.current).get("name", "?"))
		"key":
			_fx.cycle_key()
			_refresh_fx()
			return "key " + _fx.KEY_MODES[_fx.key_mode]
		"slit":
			_fx.cycle_slit()
			_refresh_fx()
			return "slit " + _fx.SLIT_MODES[_fx.slit_mode]
		"layer":
			var li := 1 + randi() % (LAYER_COUNT - 1)
			_layers[li]["blend"] = randi() % BLENDS.size()
			_apply_layers()
			return "layer %d %s" % [li + 1, BLENDS[_layers[li]["blend"]]]
		_:
			cam_orbit = clampf(cam_orbit + randf_range(-0.3, 0.3), -1.0, 1.0)
			cam_roll = clampf(cam_roll + randf_range(-0.2, 0.2), -1.0, 1.0)
			return "camera orbit %.2f roll %.2f" % [cam_orbit, cam_roll]


func set_evolve(on: bool) -> void:
	evolve = on
	_evolve_timer = 0.0
	_evolve_beats = 0
	_evolve_last = ""
	if on:
		_evolve_base = snapshot()
		_steal_note = "evolve: mutating every %d beats / %.0f s — Enter keeps, Shift+Enter discards" % [EVOLVE_BEATS, EVOLVE_SECONDS]
	else:
		_steal_note = ""
	_update_hud()


func evolve_step() -> void:
	_evolve_base = snapshot()                  # the previous mutation stands
	_evolve_last = mutate()
	_steal_note = "evolve: " + _evolve_last + "   (Enter keep · Shift+Enter discard)"
	_update_hud()


func evolve_keep() -> void:
	_evolve_base = snapshot()
	_steal_note = "kept: " + _evolve_last
	_update_hud()


func evolve_discard() -> void:
	if not _evolve_base.is_empty():
		restore(_evolve_base, 0.3)
	_steal_note = "discarded: " + _evolve_last
	_evolve_last = ""
	_update_hud()


# ---------------- attract ----------------
## Idle show: every ATTRACT_SECONDS a random saved preset (or three mutations
## when there are none), a slow camera orbit and the monitor on. Any input
## ends it and puts the stage back the way it was.
func set_attract(on: bool) -> void:
	if on == attract:
		return
	attract = on
	_attract_timer = 0.0
	if on:
		_attract_base = snapshot()
		cam_orbit = 0.25 if cam_orbit == 0.0 else cam_orbit
		if not _monitor.visible:
			set_monitor(true)
		attract_step()
	else:
		if not _attract_base.is_empty():
			restore(_attract_base, 0.5)
		_steal_note = ""
	_update_hud()


func attract_step() -> void:
	var saved: Array = Presets.filled(Presets.PATH, bank)
	if saved.is_empty():
		var notes: Array = []
		for i in 3:
			notes.append(mutate())
		_steal_note = "attract: " + ", ".join(notes)
	else:
		var n: int = saved[randi() % saved.size()]
		restore(Presets.get_preset(n, Presets.PATH, bank), maxf(preset_fade, 1.0))
		_steal_note = "attract: preset %d.%d" % [bank + 1, n]
	_update_hud()


func _tick_modes(delta: float) -> void:
	_idle += delta
	if not attract and _idle >= IDLE_ATTRACT:
		set_attract(true)
	if attract:
		_attract_timer += delta
		if _attract_timer >= ATTRACT_SECONDS:
			_attract_timer = 0.0
			attract_step()
	if evolve:
		if AudioReact.active():
			if AudioReact.beat_env >= 1.0 and _evolve_timer <= 0.0:
				_evolve_beats += 1
				_evolve_timer = 0.15
				if _evolve_beats >= EVOLVE_BEATS:
					_evolve_beats = 0
					evolve_step()
			_evolve_timer = maxf(0.0, _evolve_timer - delta)
		else:
			_evolve_timer += delta
			if _evolve_timer >= EVOLVE_SECONDS:
				_evolve_timer = 0.0
				evolve_step()


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey or ev is InputEventMouseButton or ev is InputEventMIDI or ev is InputEventJoypadButton \
			or (ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.5):
		_idle = 0.0
		if attract:
			set_attract(false)
	if ev is InputEventJoypadButton and ev.pressed:
		_p2_pad_button(ev.button_index)


# ---------------- video slots ----------------
## One looping VideoStreamPlayer in a viewport per video slot; IconMedia hands
## the viewport texture to whoever asks for the slot's path.
func _sync_videos() -> void:
	var wanted := {}
	for sl in Toolbox.slots:
		if str(sl.get("kind", "")) == "video":
			wanted[str(sl["svg_path"])] = true
	for pth in _videos.keys():
		if not wanted.has(pth):
			IconMedia.unregister_live(pth)
			_videos[pth]["vp"].queue_free()
			_videos.erase(pth)
	for pth in wanted:
		if _videos.has(pth):
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(480, 270)
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var player := VideoStreamPlayer.new()
		player.size = Vector2(480, 270)
		player.expand = true
		player.loop = true
		player.autoplay = true
		var stream := VideoStreamTheora.new()
		stream.file = pth
		player.stream = stream
		vp.add_child(player)
		_videos[pth] = {"vp": vp, "player": player}
		IconMedia.register_live(pth, vp.get_texture())
	if not wanted.is_empty():
		_hotbar.refresh()


## Live words (clock, countdown) re-render when their text changes; cycling
## word lists advance on the beat, or every 2 s without one.
func _tick_words(delta: float) -> void:
	_live_timer += delta
	if _live_timer >= 0.5:
		_live_timer = 0.0
		var now := int(Time.get_unix_time_from_system())
		for i in Toolbox.slots.size():
			var sl: Dictionary = Toolbox.slots[i]
			if not sl.has("live"):
				continue
			var text := LiveText.text_for(str(sl["live"]), int(sl.get("target", 0)), now)
			if text == str(sl.get("shown", "")):
				continue
			var img := TextRaster.render(text)
			var v := int(sl.get("version", 0)) + 1
			var pth := "%s/%s_v%d.png" % [Toolbox.TEXT_DIR, sl["id"], v]
			if img.save_png(ProjectSettings.globalize_path(pth)) != OK:
				continue
			var old := str(sl.get("svg_path", ""))
			sl["shown"] = text
			sl["version"] = v
			Toolbox.set_slot_path(i, pth, v % 20 == 0)
			if old != pth and old.begins_with(Toolbox.TEXT_DIR) and FileAccess.file_exists(old):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(old))    # the slot's previous render
	var beat := AudioReact.active() and AudioReact.beat_env > _cycle_last_beat
	_cycle_last_beat = AudioReact.beat_env
	_cycle_timer += delta
	var step := beat or (not AudioReact.active() and _cycle_timer >= 2.0)
	if step:
		_cycle_timer = 0.0
		for i in Toolbox.slots.size():
			var sl: Dictionary = Toolbox.slots[i]
			if not sl.has("word_paths"):
				continue
			var paths: Array = sl["word_paths"]
			var idx := (int(sl.get("word_index", 0)) + 1) % paths.size()
			sl["word_index"] = idx
			Toolbox.set_slot_path(i, str(paths[idx]))


func advance_words() -> void:
	_cycle_timer = 2.0
	_tick_words(0.0)


## Pinata: the nearest Sparkle icon under a point bursts and goes.
func pinata_at(world_pos: Vector2, radius := 90.0) -> bool:
	var best: Node2D = null
	var bd := radius
	for a in all_actors():
		if a._dying or not Toolbox.has_verb(Toolbox.index_of(a.slot_id), "sparkle"):
			continue
		var d: float = (a.global_position if a.riding else a.position).distance_to(world_pos)
		if d < bd:
			bd = d
			best = a
	if best == null:
		return false
	best.pinata()
	return true


func pinata_random() -> void:
	var c: Array = []
	for a in all_actors():
		if not a._dying and Toolbox.has_verb(Toolbox.index_of(a.slot_id), "sparkle"):
			c.append(a)
	if not c.is_empty():
		c[randi() % c.size()].pinata()


# ---------------- syphon ----------------
func syphon_available() -> bool:
	return ClassDB.class_exists("SyphonOutput") and DisplayServer.get_name() != "headless"


## Publishes the composite (the picture, no HUD) as a Syphon server named
## "Video Toy". The addon cannot switch textures on a live output, so the
## node is created fresh each time it is turned on.
func set_syphon(on: bool) -> void:
	if on and not syphon_available():
		_steal_note = "Syphon: addon not loaded (macOS + Forward+ only)"
		syphon_on = false
		_update_hud()
		return
	if _syphon:
		_syphon.queue_free()
		_syphon = null
	syphon_on = on
	if on:
		_syphon = ClassDB.instantiate("SyphonOutput")
		_syphon.server_name = "Video Toy"
		add_child(_syphon)
		_syphon.texture = _composite.get_texture()
		_steal_note = "Syphon: publishing 'Video Toy' (1920x1080, no HUD)"
	else:
		_steal_note = "Syphon: off"
	_update_hud()


# ---------------- clock ----------------
func _tick_clock() -> void:
	if Clock.lock_scenes and Clock.running and Scenes.current != "":
		var want := Clock.bpm / 120.0
		if not is_equal_approx(want, Scenes.speed):
			set_scene_knobs(want, Scenes.scale, Scenes.bias)
	if _play_pending and timeline.has_loop():
		if not Clock.running or Clock.until_next_bar() <= get_process_delta_time() * 1.5:
			_play_pending = false
			timeline.start_play(_clock)
			_steal_note = "looping %.1f s on the bar" % timeline.length
			_update_hud()


# ---------------- credits ----------------
## Distinct slot ids of everything on stage (actors, riders, solids, formations).
func onstage_ids() -> Array:
	var ids := {}
	for a in all_actors():
		ids[a.slot_id] = true
	for sol in _solids.get_children():
		ids[sol.slot_id] = true
	for f in _formations.get_children():
		ids[f.slot_id] = true
	return ids.keys()


func onstage_credit_lines() -> Array:
	var out: Array = []
	var ids := onstage_ids()
	for e in Ledger.entries:
		if ids.has(str(e.get("id", ""))):
			out.append(Ledger.credit_line(e))
	return out


func set_ticker(on: bool) -> void:
	ticker_on = on
	_ticker.visible = on
	_refresh_ticker()
	_update_hud()


func _refresh_ticker() -> void:
	if not ticker_on:
		return
	var parts: Array = []
	var ids := onstage_ids()
	for e in Ledger.entries:
		if ids.has(str(e.get("id", ""))):
			parts.append(Ledger.line_for(e))
	_ticker.text = ("icons: " + "  ·  ".join(parts)) if not parts.is_empty() else "icons from The Noun Project — thenounproject.com"


## Screenshot of the picture (composite, no HUD) with the credits burned in.
func screenshot_with_credits() -> String:
	var img: Image = _composite.get_texture().get_image()
	if img == null or img.is_empty():
		_steal_note = "screenshot: no picture (headless?)"
		_update_hud()
		return ""
	var lines := onstage_credit_lines()
	lines.push_front("Made with Video Toy — icons from The Noun Project (CC BY unless noted)")
	var path := Shot.save(Shot.compose(img, lines))
	_steal_note = ("saved " + ProjectSettings.globalize_path(path)) if path != "" else "screenshot failed"
	_update_hud()
	return path


func start_credits_roll() -> void:
	for c in _roll_body.get_children():
		c.queue_free()
	_roll_body.add_child(UI.label("Video Toy", 64, UI.ACCENT))
	_roll_body.add_child(UI.label("icons from The Noun Project · thenounproject.com", 26))
	_roll_body.add_child(UI.vspace(30))
	for line in Ledger.credits_text().split("\n"):
		if line.strip_edges() != "":
			_roll_body.add_child(UI.label(line, 22 if not line.ends_with(":") else 26, Color.WHITE if not line.ends_with(":") else UI.ACCENT))
	_roll_body.add_child(UI.vspace(80))
	_roll_body.add_child(UI.label("thank you", 40, UI.ACCENT))
	_roll_body.position = Vector2((1920 - 1200) * 0.5, 1080)
	_roll_body.custom_minimum_size = Vector2(1200, 0)
	_roll_t = 0.0
	_roll.visible = true
	_update_hud()


func stop_credits_roll() -> void:
	_roll.visible = false
	_update_hud()


func _tick_credits(delta: float) -> void:
	if _roll.visible:
		_roll_t += delta
		_roll_body.position.y = 1080.0 - _roll_t * _roll_speed
		if _roll_body.position.y + _roll_body.size.y < -20.0:
			stop_credits_roll()
	if ticker_on and Engine.get_process_frames() % 60 == 0:
		_refresh_ticker()


# ---------------- quality ----------------
## Frame delta is useless on a vsynced display (this one is 30 Hz), so the
## ladder watches real work: script time plus measured CPU + GPU render time
## of the window and every SubViewport the stage owns.
func _enable_measurement() -> void:
	_measured = [get_viewport().get_viewport_rid()]
	for vp in _find_viewports(self):
		_measured.append(vp.get_viewport_rid())
	for rid in _measured:
		RenderingServer.viewport_set_measure_render_time(rid, true)
	# Performance.TIME_PROCESS includes the present/vsync wait on macOS, so
	# script time is bracketed by hand: process_frame -> frame_pre_draw.
	get_tree().process_frame.connect(func(): _t_proc = Time.get_ticks_usec())
	RenderingServer.frame_pre_draw.connect(func():
		if _t_proc > 0:
			script_ms = (Time.get_ticks_usec() - _t_proc) / 1000.0)


var _t_proc := 0
var script_ms := 0.0


func _find_viewports(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is SubViewport:
			out.append(c)
		out.append_array(_find_viewports(c))
	return out


func measure_work_ms() -> float:
	var ms := script_ms
	for rid in _measured:
		ms += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return ms


## Where the frame goes: script, then cpu/gpu per measured viewport (debug HUD / capture).
func perf_breakdown() -> String:
	var parts := ["script %.1f (TIME_PROCESS %.1f)" % [script_ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0]]
	var i := 0
	for rid in _measured:
		var c := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var g := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if c + g > 0.3:
			parts.append("vp%d %.1f/%.1f" % [i, c, g])
		i += 1
	var rest := "   nodes %d  orphans %d  objects %d  draw_calls %d" % [Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
	return "  ".join(parts) + "   stage_process(us) " + str(_prof) + rest


func apply_quality(level: int) -> void:
	level = clampi(level, 0, Quality.count() - 1)
	if level == _quality_applied:
		return
	_quality_applied = level
	var q: Dictionary = Quality.get_level(level)
	if _particles.amount != int(q["particles"]):
		_particles.amount = int(q["particles"])           # restarts the system
		if particles_on:
			_particles.restart()
	_fx.slit_stride = int(q["slit_stride"])
	_glow.set_taps(int(q["glow_taps"]))
	_world3d.msaa_3d = Viewport.MSAA_2X if q["msaa"] else Viewport.MSAA_DISABLED
	_update_hud()


func _tick_quality(delta: float) -> void:
	if Engine.get_process_frames() % 10 == 0:            # the render-time queries cost ~1.5 ms; sample, don't poll
		work_ms = measure_work_ms()
	if quality.update(work_ms, delta):
		_steal_note = "quality → " + quality.describe()
	apply_quality(quality.effective())
	_enable_measurement()


func cycle_quality_lock() -> void:
	quality.cycle_lock()
	apply_quality(quality.effective())
	_enable_measurement()
	_steal_note = "quality " + quality.describe()
	_update_hud()


# ---------------- panic / blackout ----------------
## A known-good look, toolbox and actors untouched.
func panic() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_xf = {}
	_set_feedback(false)
	fb_zoom = 1.04
	fb_rot = 0.02
	fb_fade = 0.92
	fb_warp = 0.0
	fb_drift = Vector2.ZERO
	fb_stretch = Vector2.ONE
	_fx.set_state(0, false, false, 0, false, 0, 0, 0)
	_glow.set_level(1)
	set_particles(false)
	set_rd_preset(0)
	set_scene("", 0.3)
	set_monitor(false)
	set_webcam_mode(0)
	for i in range(1, LAYER_COUNT):
		_layers[i]["blend"] = 0
		_layers[i]["opacity"] = 1.0
	_apply_layers()
	set_active_layer(0)
	reset_camera()
	draw_mode = false
	set_evolve(false)
	if attract:
		attract = false
		_attract_base = {}
	timeline.stop_play()
	if timeline.recording:
		toggle_record()
	if blackout:
		toggle_blackout()
	stop_credits_roll()
	_refresh_fx()
	_steal_note = "PANIC: known-good look (toolbox kept)"
	_update_hud()


func toggle_blackout() -> void:
	blackout = not blackout
	if _blackout_tween:
		_blackout_tween.kill()
	_blackout.visible = true
	_blackout_tween = create_tween()
	_blackout_tween.tween_property(_blackout, "modulate:a", 1.0 if blackout else 0.0, 0.5)
	if not blackout:
		_blackout_tween.tween_callback(func(): _blackout.visible = false)
	_update_hud()


# ---------------- player 2 ----------------
func p2_wake() -> void:
	if not p2_active:
		p2_active = true
		p2_slot = clampi(p2_slot, 0, maxi(Toolbox.slots.size() - 1, 0))
		_steal_note = "player 2 is in — keypad or gamepad; Shift+2 hides them"
	_p2_node.visible = true
	_refresh_p2()


func p2_sleep() -> void:
	p2_active = false
	_p2_node.visible = false
	_hotbar.second_selected = -1
	_hotbar.refresh()
	_update_hud()


func _refresh_p2() -> void:
	_p2_node.position = p2_cursor
	_p2_node.color = Palettes.color(palette_index, int(Toolbox.slots[p2_slot].get("color_index", p2_slot))) if p2_slot < Toolbox.slots.size() else Color.CYAN
	_p2_node.label = "P2 · L%d" % (p2_layer + 1)
	_p2_node.queue_redraw()
	_hotbar.second_selected = p2_slot if p2_active else -1
	_hotbar.refresh()
	_update_hud()


func p2_move(delta_px: Vector2) -> void:
	p2_wake()
	p2_cursor = (p2_cursor + delta_px).clamp(Vector2.ZERO, Vector2(WORLD))
	_refresh_p2()


func p2_spawn() -> void:
	p2_wake()
	spawn_slot_at(p2_slot, p2_layer, p2_cursor)


func p2_remove() -> void:
	p2_wake()
	_remove_nearest(p2_cursor)


func p2_next_slot(step := 1) -> void:
	p2_wake()
	if not Toolbox.slots.is_empty():
		p2_slot = posmod(p2_slot + step, Toolbox.slots.size())
	_refresh_p2()


func p2_next_layer() -> void:
	p2_wake()
	p2_layer = posmod(p2_layer + 1, LAYER_COUNT)
	_refresh_p2()


func p2_toggle_spin() -> void:
	p2_wake()
	if p2_slot < Toolbox.slots.size():
		Toolbox.toggle_verb(p2_slot, "spin")


func p2_spawn_solid() -> void:
	p2_wake()
	var keep := Toolbox.selected
	Toolbox.select(p2_slot)
	spawn_solid(p2_cursor)
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
		p2_move(v.limit_length(1.0) * P2_SPEED * delta)


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
			p2_slot = clampi([KEY_KP_1, KEY_KP_3, KEY_KP_7, KEY_KP_9].find(k) * 2, 0, maxi(Toolbox.slots.size() - 1, 0))
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
func snapshot() -> Dictionary:
	var verbs := {}
	for sl in Toolbox.slots:
		verbs[str(sl["id"])] = {"verbs": sl.get("verbs", []).duplicate(), "color_index": int(sl.get("color_index", 0))}
	return {
		"palette": palette_index,
		"feedback": {"on": feedback, "zoom": fb_zoom, "rot": fb_rot, "fade": fb_fade},
		"fx": {"pixel": _fx.pixel_step, "kaleido": _fx.kaleido_step, "crt": _fx.crt_level,
			"key": _fx.key_mode, "key_threshold": _fx.key_threshold, "slit": _fx.slit_mode,
			"quantize": _fx.quantize, "dither": _fx.dither},
		"glow": _glow.level,
		"monitor": {"on": _monitor.visible, "size": _monitor.size_step, "x": _monitor.position.x, "y": _monitor.position.y},
		"webcam": _webcam_mode,
		"shape": _shape_index,
		"selected": Toolbox.selected,
		"slots": verbs,
		"scene": {"id": Scenes.current, "speed": Scenes.speed, "scale": Scenes.scale, "bias": Scenes.bias},
		"warp": {"amount": fb_warp, "speed": fb_warp_speed, "dx": fb_drift.x, "dy": fb_drift.y, "sx": fb_stretch.x, "sy": fb_stretch.y},
		"camera": {"orbit": cam_orbit, "dolly": cam_dolly, "roll": cam_roll, "height": cam_height},
		"formation": _formation_index,
		"layers": _layers.map(func(l): return {"blend": l["blend"], "opacity": l["opacity"]}),
		"active_layer": active_layer,
		"particles": {"on": particles_on, "flow": particles_flow, "attract": particles_attract},
		"rd": {"preset": rd_preset, "feed": rd_feed, "kill": rd_kill},
	}


## Apply a snapshot. With `fade` > 0 everything crossfades: continuous values
## lerp over the time, discrete ones flip at the midpoint (StateLerp).
func restore(d: Dictionary, fade := 1.0) -> void:
	if d.is_empty():
		return
	if fade <= 0.0:
		_xf = {}
		_apply_snapshot(d, true)
		return
	_xf = {"from": snapshot(), "to": d, "t": 0.0, "dur": fade}


func _tick_crossfade(delta: float) -> void:
	if _xf.is_empty():
		return
	_xf["t"] += delta
	var t: float = float(_xf["t"]) / float(_xf["dur"])
	if t >= 1.0:
		var to: Dictionary = _xf["to"]
		_xf = {}
		_apply_snapshot(to, true)
		return
	_apply_snapshot(StateLerp.mix(_xf["from"], _xf["to"], t), false)


func crossfading() -> bool:
	return not _xf.is_empty()


## Jump to the end of a running crossfade (tests, panic).
func finish_crossfade() -> void:
	if _xf.is_empty():
		return
	var to: Dictionary = _xf["to"]
	_xf = {}
	_apply_snapshot(to, true)


## Immediate apply. `persist` writes the toolbox verbs to disk (skipped on the
## per-frame crossfade path). Every setter is guarded so re-applying the same
## state each frame does not restart particles, webcams or scenes.
func _apply_snapshot(d: Dictionary, persist: bool) -> void:
	var pal := posmod(int(d.get("palette", palette_index)), Palettes.count())
	var pal_changed := pal != palette_index
	palette_index = pal
	var fb: Dictionary = d.get("feedback", {})
	if _fade_tween:
		_fade_tween.kill()
	fb_zoom = float(fb.get("zoom", fb_zoom))
	fb_rot = float(fb.get("rot", fb_rot))
	fb_fade = float(fb.get("fade", fb_fade))
	var fb_on := bool(fb.get("on", feedback))
	if fb_on != feedback:
		_set_feedback(fb_on)
	var fx: Dictionary = d.get("fx", {})
	_fx.pixel_step = clampi(int(fx.get("pixel", _fx.pixel_step)), 0, _fx.PIXEL_STEPS.size() - 1)
	_fx.kaleido_step = clampi(int(fx.get("kaleido", _fx.kaleido_step)), 0, _fx.KALEIDO_STEPS.size() - 1)
	_fx.crt_level = clampi(int(fx.get("crt", _fx.crt_level)), 0, 2)
	if fx.has("key"):
		_fx.key_mode = clampi(int(fx["key"]), 0, _fx.KEY_MODES.size() - 1)
	elif fx.has("chroma"):
		_fx.key_mode = 1 if bool(fx["chroma"]) else 0
	_fx.key_threshold = clampf(float(fx.get("key_threshold", _fx.key_threshold)), 0.0, 1.0)
	_fx.slit_mode = clampi(int(fx.get("slit", _fx.slit_mode)), 0, _fx.SLIT_MODES.size() - 1)
	_fx.quantize = bool(fx.get("quantize", _fx.quantize))
	_fx.dither = bool(fx.get("dither", _fx.dither))
	_fx._push()
	_glow.set_level(int(d.get("glow", _glow.level)))
	var mon: Dictionary = d.get("monitor", {})
	var msize := clampi(int(mon.get("size", _monitor.size_step)), 0, _monitor.SIZES.size() - 1)
	if msize != _monitor.size_step:
		_monitor.size_step = msize
		_monitor._apply_scale()
	_monitor.position = Vector2(float(mon.get("x", _monitor.position.x)), float(mon.get("y", _monitor.position.y)))
	_monitor.visible = bool(mon.get("on", _monitor.visible))
	var wm := int(d.get("webcam", _webcam_mode))
	if wm != _webcam_mode:
		set_webcam_mode(wm)
	_shape_index = posmod(int(d.get("shape", _shape_index)), SolidScript.SHAPES.size())
	var cam: Dictionary = d.get("camera", {})
	if not cam.is_empty():
		cam_orbit = float(cam.get("orbit", cam_orbit))
		cam_dolly = float(cam.get("dolly", cam_dolly))
		cam_roll = float(cam.get("roll", cam_roll))
		cam_height = float(cam.get("height", cam_height))
	_formation_index = posmod(int(d.get("formation", _formation_index)), FormationScript.KINDS.size())
	var pt: Dictionary = d.get("particles", {})
	if not pt.is_empty():
		particles_flow = float(pt.get("flow", particles_flow))
		particles_attract = float(pt.get("attract", particles_attract))
		var pon := bool(pt.get("on", particles_on))
		if pon != particles_on:
			set_particles(pon)
	var rdd: Dictionary = d.get("rd", {})
	if not rdd.is_empty():
		var rp := int(rdd.get("preset", rd_preset))
		if rp != rd_preset:
			set_rd_preset(rp)
		rd_feed = float(rdd.get("feed", rd_feed))
		rd_kill = float(rdd.get("kill", rd_kill))
		_push_rd()
	var lay: Array = d.get("layers", [])
	for i in mini(lay.size(), _layers.size()):
		if lay[i] is Dictionary:
			_layers[i]["blend"] = clampi(int(lay[i].get("blend", 0)), 0, BLENDS.size() - 1)
			_layers[i]["opacity"] = clampf(float(lay[i].get("opacity", 1.0)), 0.0, 1.0)
	_apply_layers()
	active_layer = posmod(int(d.get("active_layer", active_layer)), LAYER_COUNT)
	var w: Dictionary = d.get("warp", {})
	if not w.is_empty():
		fb_warp = float(w.get("amount", fb_warp))
		fb_warp_speed = float(w.get("speed", fb_warp_speed))
		fb_drift = Vector2(float(w.get("dx", fb_drift.x)), float(w.get("dy", fb_drift.y)))
		fb_stretch = Vector2(float(w.get("sx", fb_stretch.x)), float(w.get("sy", fb_stretch.y)))
	var slots: Dictionary = d.get("slots", {})
	var verbs_changed := false
	for i in Toolbox.slots.size():
		var rec = slots.get(str(Toolbox.slots[i]["id"]))
		if rec is Dictionary:
			var nv: Array = Array(rec.get("verbs", [])).duplicate()
			var nc := int(rec.get("color_index", Toolbox.slots[i].get("color_index", 0)))
			if nv != Toolbox.slots[i].get("verbs", []) or nc != int(Toolbox.slots[i].get("color_index", 0)):
				Toolbox.slots[i]["verbs"] = nv
				Toolbox.slots[i]["color_index"] = nc
				verbs_changed = true
	if verbs_changed:
		if persist:
			Toolbox.save_to_disk()
		Toolbox.changed.emit()
	var sel := int(d.get("selected", Toolbox.selected))
	if sel != Toolbox.selected:
		Toolbox.select(sel)
	var sc: Dictionary = d.get("scene", {})
	if not sc.is_empty():
		Scenes.speed = float(sc.get("speed", Scenes.speed))
		Scenes.scale = float(sc.get("scale", Scenes.scale))
		Scenes.bias = float(sc.get("bias", Scenes.bias))
		_scene_layer.apply_knobs()
		var sid := str(sc.get("id", Scenes.current))
		if sid != Scenes.current:
			set_scene(sid, 0.8)
	if pal_changed or verbs_changed:
		_apply_palette()
	_refresh_fx()
	_update_hud()


# ---------------- banks, stepping, morph ----------------
func set_bank(b: int) -> void:
	bank = posmod(b, Presets.BANKS)
	_steal_note = "bank %d: %d presets" % [bank + 1, Presets.filled(Presets.PATH, bank).size()]
	_update_hud()


func step_preset(step: int) -> void:
	var n := Presets.neighbour(last_preset, step, Presets.PATH, bank)
	if n == 0:
		_steal_note = "bank %d is empty — Shift+F1..F12 saves" % (bank + 1)
		_update_hud()
		return
	recall_preset(n)


func cycle_fade() -> void:
	var steps := [0.0, 0.5, 1.0, 2.0, 4.0]
	var i := steps.find(preset_fade)
	preset_fade = steps[(i + 1) % steps.size()] if i >= 0 else 1.0
	_steal_note = "preset crossfade %.1f s" % preset_fade
	_update_hud()


## 0..1 scrub from the last recalled preset toward the next filled one.
func morph(v: float) -> void:
	if _morph_a.is_empty():
		_morph_a = snapshot()
	var n := Presets.neighbour(last_preset, 1, Presets.PATH, bank)
	if n == 0:
		return
	_xf = {}
	_apply_snapshot(StateLerp.mix(_morph_a, Presets.get_preset(n, Presets.PATH, bank), v), false)


func save_preset(i: int) -> void:
	Presets.save(i, snapshot(), Presets.PATH, bank)
	last_preset = i
	_morph_a = snapshot()
	_steal_note = "saved preset %d in bank %d (F%d)" % [i, bank + 1, i]
	_update_hud()


func recall_preset(i: int) -> void:
	var d := Presets.get_preset(i, Presets.PATH, bank)
	if d.is_empty():
		_steal_note = "preset %d in bank %d is empty — Shift+F%d saves" % [i, bank + 1, i]
	else:
		restore(d, preset_fade)
		last_preset = i
		_morph_a = d.duplicate(true)
		_steal_note = "preset %d.%d%s" % [bank + 1, i, ("  (crossfade %.1f s)" % preset_fade) if preset_fade > 0.0 else ""]
	_update_hud()


# ---------------- MIDI ----------------
## Continuous params: id, label, setter(0..1). Actions: id, label, callable.
func midi_params() -> Array:
	return [
		{"id": "fb_zoom", "label": "Feedback zoom", "set": func(v): fb_zoom = lerpf(0.90, 1.20, v)},
		{"id": "fb_twist", "label": "Feedback twist", "set": func(v): fb_rot = lerpf(-0.15, 0.15, v)},
		{"id": "fb_fade", "label": "Feedback fade", "set": func(v): fb_fade = lerpf(0.5, 0.995, v)},
		{"id": "pixelate", "label": "Pixelate size", "set": func(v):
			_fx.pixel_step = _step(v, _fx.PIXEL_STEPS.size())
			_fx._push()
			_refresh_fx()},
		{"id": "kaleido", "label": "Kaleidoscope", "set": func(v):
			_fx.kaleido_step = _step(v, _fx.KALEIDO_STEPS.size())
			_fx._push()
			_refresh_fx()},
		{"id": "crt", "label": "CRT", "set": func(v):
			_fx.crt_level = _step(v, 3)
			_fx._push()
			_refresh_fx()},
		{"id": "key_mode", "label": "Key mode", "set": func(v):
			_fx.key_mode = _step(v, _fx.KEY_MODES.size())
			_fx._push()
			_refresh_fx()},
		{"id": "key_threshold", "label": "Key threshold", "set": func(v):
			_fx.key_threshold = v
			_fx._push()
			_refresh_fx()},
		{"id": "slit", "label": "Slit-scan mode", "set": func(v):
			_fx.slit_mode = _step(v, _fx.SLIT_MODES.size())
			_fx._push()
			_refresh_fx()},
		{"id": "monitor", "label": "Monitor size", "set": func(v):
			_monitor.size_step = _step(v, _monitor.SIZES.size())
			_monitor._apply_scale()},
		{"id": "palette", "label": "Palette", "set": func(v):
			var i := _step(v, Palettes.count())
			if i != palette_index:
				palette_index = i
				_apply_palette()},
		{"id": "slot", "label": "Toolbox slot", "set": func(v):
			if not Toolbox.slots.is_empty():
				Toolbox.select(_step(v, Toolbox.slots.size()))},
		{"id": "audio_gain", "label": "Audio gain", "set": func(v): AudioReact.gain = lerpf(0.25, 4.0, v)},
		{"id": "glow", "label": "Glow", "set": func(v):
			_glow.set_level(_step(v, 3))
			_update_hud()},
		{"id": "scene", "label": "Scene", "set": func(v):
			var n := Scenes.ALL.size() + 1
			var i := _step(v, n)
			set_scene("" if i == 0 else Scenes.ALL[i - 1]["id"])},
		{"id": "scene_speed", "label": "Scene speed", "set": func(v): set_scene_knobs(lerpf(0.1, 4.0, v), Scenes.scale, Scenes.bias)},
		{"id": "scene_scale", "label": "Scene scale", "set": func(v): set_scene_knobs(Scenes.speed, lerpf(0.3, 4.0, v), Scenes.bias)},
		{"id": "scene_bias", "label": "Scene colour bias", "set": func(v): set_scene_knobs(Scenes.speed, Scenes.scale, v)},
		{"id": "fb_warp", "label": "Feedback warp", "set": func(v): fb_warp = v},
		{"id": "fb_warp_speed", "label": "Feedback warp speed", "set": func(v): fb_warp_speed = lerpf(0.1, 4.0, v)},
		{"id": "fb_dx", "label": "Feedback drift X", "set": func(v): fb_drift.x = lerpf(-6.0, 6.0, v)},
		{"id": "fb_dy", "label": "Feedback drift Y", "set": func(v): fb_drift.y = lerpf(-6.0, 6.0, v)},
		{"id": "fb_sx", "label": "Feedback stretch X", "set": func(v): fb_stretch.x = lerpf(0.9, 1.1, v)},
		{"id": "fb_sy", "label": "Feedback stretch Y", "set": func(v): fb_stretch.y = lerpf(0.9, 1.1, v)},
		{"id": "cam_orbit", "label": "Camera orbit speed", "set": func(v): cam_orbit = lerpf(-1.5, 1.5, v)},
		{"id": "cam_dolly", "label": "Camera dolly", "set": func(v): cam_dolly = lerpf(3.0, 14.0, v)},
		{"id": "cam_roll", "label": "Camera roll", "set": func(v): cam_roll = lerpf(-PI, PI, v)},
		{"id": "cam_height", "label": "Camera height", "set": func(v): cam_height = lerpf(-4.0, 4.0, v)},
		{"id": "particles_flow", "label": "Particle flow", "set": func(v): particles_flow = lerpf(0.0, 2.0, v)},
		{"id": "particles_attract", "label": "Particle attract (-1..1)", "set": func(v): particles_attract = lerpf(-1.0, 1.0, v)},
		{"id": "rd_feed", "label": "Reaction feed", "set": func(v):
			rd_feed = lerpf(0.01, 0.09, v)
			_push_rd()},
		{"id": "rd_kill", "label": "Reaction kill", "set": func(v):
			rd_kill = lerpf(0.04, 0.07, v)
			_push_rd()},
		{"id": "bpm", "label": "Internal clock BPM", "set": func(v):
			Clock.bpm = lerpf(60.0, 200.0, v)
			_update_hud()},
		{"id": "bank", "label": "Preset bank", "set": func(v): set_bank(_step(v, Presets.BANKS))},
		{"id": "preset_fade", "label": "Preset crossfade time", "set": func(v):
			preset_fade = lerpf(0.0, 5.0, v)
			_update_hud()},
		{"id": "preset_morph", "label": "Preset morph (to next)", "set": morph},
		{"id": "active_layer", "label": "Active layer", "set": func(v): set_active_layer(_step(v, LAYER_COUNT))},
		{"id": "layer_opacity", "label": "Layer opacity (active)", "set": func(v): set_layer_opacity(v)},
	]


func midi_actions() -> Array:
	var out: Array = [
		{"id": "spawn", "label": "Spawn icon", "do": func(): spawn_at(Vector2(randf_range(100, WORLD.x - 100), randf_range(100, WORLD.y - 100)))},
		{"id": "spawn_solid", "label": "Spawn 3D solid", "do": func(): spawn_solid()},
		{"id": "clear", "label": "Clear stage", "do": func():
			clear_actors()
			for a in _solids.get_children() + _formations.get_children():
				a.queue_free()},
		{"id": "feedback", "label": "Feedback on/off", "do": func(): _set_feedback(not feedback)},
		{"id": "next_palette", "label": "Next palette", "do": func():
			palette_index = (palette_index + 1) % Palettes.count()
			_apply_palette()},
		{"id": "chroma", "label": "Next key mode", "do": func():
			_fx.cycle_key()
			_refresh_fx()},
		{"id": "slit", "label": "Next slit-scan mode", "do": func():
			_fx.cycle_slit()
			_refresh_fx()},
		{"id": "quantise", "label": "Palette quantise on/off", "do": func():
			_fx.toggle_quantize()
			_refresh_fx()},
		{"id": "dither", "label": "Dither on/off", "do": func():
			_fx.toggle_dither()
			_refresh_fx()},
		{"id": "monitor", "label": "Monitor on/off", "do": func(): set_monitor(not _monitor.visible)},
		{"id": "next_shape", "label": "Next 3D shape", "do": cycle_shape},
		{"id": "webcam", "label": "Next webcam mode", "do": cycle_webcam},
		{"id": "steal_palette", "label": "Steal palette", "do": steal_palette},
		{"id": "audio_source", "label": "Next audio source", "do": func():
			AudioReact.cycle_source()
			_update_hud()},
		{"id": "recolor", "label": "Recolor slot", "do": _recolor},
	]
	out.append({"id": "pinata", "label": "Pinata: burst a random Sparkle icon", "do": pinata_random})
	out.append({"id": "next_word", "label": "Word lists: next word", "do": advance_words})
	out.append({"id": "syphon", "label": "Syphon output on/off", "do": func(): set_syphon(not syphon_on)})
	out.append({"id": "clock_internal", "label": "Internal clock on/off", "do": func():
		Clock.toggle_internal()
		_update_hud()})
	out.append({"id": "clock_lock_scenes", "label": "Lock scenes to BPM on/off", "do": func():
		Clock.lock_scenes = not Clock.lock_scenes
		_update_hud()})
	out.append({"id": "screenshot", "label": "Screenshot with credits", "do": func(): screenshot_with_credits()})
	out.append({"id": "ticker", "label": "Credits ticker on/off", "do": func(): set_ticker(not ticker_on)})
	out.append({"id": "credits_roll", "label": "Credits roll start/stop", "do": func():
		if _roll.visible:
			stop_credits_roll()
		else:
			start_credits_roll()})
	out.append({"id": "panic", "label": "PANIC: known-good look", "do": panic})
	out.append({"id": "blackout", "label": "Blackout on/off", "do": toggle_blackout})
	out.append({"id": "quality", "label": "Quality lock: cycle", "do": cycle_quality_lock})
	out.append({"id": "particles", "label": "Particle field on/off", "do": func(): set_particles(not particles_on)})
	out.append({"id": "scatter", "label": "Scatter particles", "do": scatter_particles})
	out.append({"id": "rd", "label": "Next reaction-diffusion preset", "do": cycle_rd})
	out.append({"id": "timeline_record", "label": "Timeline: record on/off", "do": toggle_record})
	out.append({"id": "timeline_play", "label": "Timeline: loop on/off", "do": toggle_play})
	out.append({"id": "mosaic", "label": "Mosaic of selected slot", "do": func(): spawn_mosaic()})
	out.append({"id": "evolve", "label": "Evolve on/off", "do": func(): set_evolve(not evolve)})
	out.append({"id": "evolve_keep", "label": "Evolve: keep", "do": evolve_keep})
	out.append({"id": "evolve_discard", "label": "Evolve: discard", "do": evolve_discard})
	out.append({"id": "mutate", "label": "Mutate once", "do": func():
		_steal_note = "mutation: " + mutate()
		_update_hud()})
	out.append({"id": "attract", "label": "Attract mode on/off", "do": func(): set_attract(not attract)})
	out.append({"id": "next_layer", "label": "Next layer", "do": func(): set_active_layer(active_layer + 1)})
	out.append({"id": "next_blend", "label": "Next blend mode (active layer)", "do": cycle_blend})
	out.append({"id": "draw_mode", "label": "Draw mode on/off", "do": func():
		draw_mode = not draw_mode
		_update_hud()})
	out.append({"id": "spawn_formation", "label": "Spawn formation", "do": func(): spawn_formation()})
	out.append({"id": "next_formation", "label": "Next formation kind", "do": cycle_formation})
	out.append({"id": "cam_reset", "label": "Reset camera", "do": reset_camera})
	out.append({"id": "cam_auto", "label": "Camera slow orbit on/off", "do": func():
		cam_orbit = 0.0 if cam_orbit != 0.0 else 0.35
		_update_hud()})
	out.append({"id": "next_scene", "label": "Next scene", "do": func(): step_scene(1)})
	out.append({"id": "prev_scene", "label": "Previous scene", "do": func(): step_scene(-1)})
	out.append({"id": "scene_off", "label": "Scene off", "do": func(): set_scene("")})
	out.append({"id": "warp_reset", "label": "Reset feedback warp", "do": func():
		fb_warp = 0.0
		fb_drift = Vector2.ZERO
		fb_stretch = Vector2.ONE
		_update_hud()})
	out.append({"id": "glow", "label": "Glow off/soft/heavy", "do": func():
		_glow.cycle()
		_update_hud()})
	out.append({"id": "next_preset", "label": "Next preset (in bank)", "do": func(): step_preset(1)})
	out.append({"id": "prev_preset", "label": "Previous preset (in bank)", "do": func(): step_preset(-1)})
	out.append({"id": "next_bank", "label": "Next bank", "do": func(): set_bank(bank + 1)})
	out.append({"id": "prev_bank", "label": "Previous bank", "do": func(): set_bank(bank - 1)})
	for i in Presets.COUNT:
		out.append({"id": "preset_%d" % (i + 1), "label": "Recall preset %d" % (i + 1), "do": func(): recall_preset(i + 1)})
	for i in Toolbox.MAX_SLOTS:
		out.append({"id": "slot_%d" % (i + 1), "label": "Select slot %d" % (i + 1), "do": func(): Toolbox.select(i)})
	for v in Verbs.ALL:
		out.append({"id": "verb_" + v["id"], "label": "Toggle verb: " + v["name"], "do": func():
			if not Toolbox.current().is_empty():
				Toolbox.toggle_verb(Toolbox.selected, v["id"])})
	return out


static func _step(v: float, n: int) -> int:
	return clampi(int(floor(v * n)), 0, n - 1)


func _build_midi() -> void:
	_midi_panel = MidiPanelScript.new()
	_midi_panel.params = midi_params()
	_midi_panel.actions = midi_actions()
	_midi_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_midi_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_midi_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_midi_panel.visible = false
	add_child(_midi_panel)
	MidiMap.param.connect(_on_midi_param)
	MidiMap.action.connect(_on_midi_action)
	MidiMap.activity.connect(func(text):
		_midi_last = text
		_update_hud())


func _on_midi_param(id: String, value: float) -> void:
	if timeline.recording and MidiMap.last_source != "audio":
		timeline.record("param", id, value, _clock)
	for p in midi_params():
		if p["id"] == id:
			p["set"].call(value)
			_update_hud()
			return


func _on_midi_action(id: String) -> void:
	if timeline.recording and MidiMap.last_source != "audio" and not id.begins_with("timeline"):
		timeline.record("action", id, 1.0, _clock)
	for a in midi_actions():
		if a["id"] == id:
			a["do"].call()
			_update_hud()
			return


# ---------------- timeline ----------------
func toggle_record() -> void:
	if timeline.recording:
		timeline.stop_record(_clock)
		if Clock.running:
			timeline.length = Clock.quantise_to_bars(timeline.length)
		timeline.save()
		_steal_note = "recorded %.1f s, %d events — Shift+P loops it" % [timeline.length, timeline.events.size()]
	else:
		timeline.start_record(_clock)
		_steal_note = "REC — move controllers; Shift+R stops (60 s max)"
	_update_hud()


func toggle_play() -> void:
	if timeline.playing or _play_pending:
		timeline.stop_play()
		_play_pending = false
		_steal_note = "loop stopped"
	else:
		if not timeline.has_loop():
			timeline.load()
		if timeline.has_loop():
			if Clock.running:
				_play_pending = true
				_steal_note = "loop starts on the next bar (%.1f s)" % Clock.until_next_bar()
			else:
				timeline.start_play(_clock)
				_steal_note = "looping %.1f s of gestures" % timeline.length
		else:
			_steal_note = "nothing recorded — Shift+R records controller moves"
	_update_hud()


func _tick_timeline(delta: float) -> void:
	_clock += delta
	if timeline.recording and _clock - timeline._rec_start >= Timeline.MAX:
		toggle_record()
	for e in timeline.due(_clock):
		if e["kind"] == "param":
			for p in midi_params():
				if p["id"] == e["id"]:
					p["set"].call(float(e["value"]))
		else:
			for a in midi_actions():
				if a["id"] == e["id"]:
					a["do"].call()


func toggle_midi_panel() -> void:
	_midi_panel.visible = not _midi_panel.visible
	_help.visible = not _midi_panel.visible          # the panel is wide; give it the room
	if _midi_panel.visible:
		_midi_panel.refresh()
	else:
		MidiMap.disarm()


# ---------------- HUD ----------------
func _build_hud() -> void:
	var hud_card := PanelContainer.new()
	hud_card.position = Vector2(12, 8)
	add_child(hud_card)
	_hud = UI.label("", 18, UI.DIM)
	hud_card.add_child(_hud)

	# Verb panel sits on a translucent card so it reads on light palettes too.
	var card := PanelContainer.new()
	card.position = Vector2(12, 96)
	add_child(card)
	_verb_panel = VBoxContainer.new()
	_verb_panel.add_theme_constant_override("separation", 2)
	card.add_child(_verb_panel)
	_verb_panel.add_child(UI.label("Verbs for selected slot", 18, UI.ACCENT))
	var vgrid := GridContainer.new()
	vgrid.columns = 2
	vgrid.add_theme_constant_override("h_separation", 6)
	vgrid.add_theme_constant_override("v_separation", 0)
	_verb_panel.add_child(vgrid)
	for v in Verbs.ALL:
		var cb := CheckButton.new()
		cb.text = "%s %s" % [v["key"], v["name"]]
		cb.add_theme_font_size_override("font_size", 18)
		cb.tooltip_text = v["hint"]
		cb.toggled.connect(func(_on): Toolbox.toggle_verb(Toolbox.selected, v["id"]))
		vgrid.add_child(cb)
		_verb_checks[v["id"]] = cb
	_verb_panel.add_child(UI.vspace(6))
	_verb_panel.add_child(UI.label("Effects", 18, UI.ACCENT))
	_fx_kaleido_btn = UI.button("", func():
		_fx.cycle_kaleido()
		_refresh_fx())
	_verb_panel.add_child(_fx_kaleido_btn)
	_fx_key_btn = UI.button("", func():
		_fx.cycle_key()
		_refresh_fx())
	_fx_key_btn.tooltip_text = "chroma keys the palette background; luma keys darks; diff keys what didn't move; edge keeps outlines. Keyed pixels show the backdrop (drop an image, webcam, or plasma)."
	_verb_panel.add_child(_fx_key_btn)
	_fx_slit_btn = UI.button("", func():
		_fx.cycle_slit()
		_refresh_fx())
	_fx_slit_btn.tooltip_text = "time runs down the rows, across the columns, or out from the centre"
	_verb_panel.add_child(_fx_slit_btn)
	_fx_pixel_btn = UI.button("", func():
		_fx.cycle_pixelate()
		_refresh_fx())
	_verb_panel.add_child(_fx_pixel_btn)
	_fx_quant = CheckButton.new()
	_fx_quant.text = "L  Palette quantise"
	_fx_quant.toggled.connect(func(_on):
		_fx.toggle_quantize()
		_refresh_fx())
	_verb_panel.add_child(_fx_quant)
	_fx_dither = CheckButton.new()
	_fx_dither.text = "J  Dither"
	_fx_dither.toggled.connect(func(_on):
		_fx.toggle_dither()
		_refresh_fx())
	_verb_panel.add_child(_fx_dither)
	_fx_crt_btn = UI.button("", func():
		_fx.cycle_crt()
		_refresh_fx())
	_verb_panel.add_child(_fx_crt_btn)
	_fx_glow_btn = UI.button("", func():
		_glow.cycle()
		_refresh_fx())
	_verb_panel.add_child(_fx_glow_btn)
	_fx_scene_btn = UI.button("", func(): step_scene(1))
	_fx_scene_btn.tooltip_text = "Tab / Shift+Tab; ` turns it off"
	_verb_panel.add_child(_fx_scene_btn)
	_verb_panel.add_child(UI.vspace(6))
	_verb_panel.add_child(UI.button("Recolor slot (X)", func(): _recolor()))
	_verb_panel.add_child(UI.button("Remove slot (Del)", func(): Toolbox.remove(Toolbox.selected)))

	_help = PanelContainer.new()
	_help.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help.grow_vertical = Control.GROW_DIRECTION_BOTH
	_help.offset_right = -20
	var hl := UI.label(
		"click        spawn selected icon\nright-click  remove nearest\nSpace        spawn somewhere\n"
		+ "1-9          select slot\nQ..I         toggle verbs\nX            recolor slot\n"
		+ "P            next palette\nF            feedback on/off\n[ ]          feedback zoom\n"
		+ ", .          feedback twist\n- =          feedback fade\nO            kaleidoscope\n"
		+ "G            key: chroma/luma/diff/edge (Shift: threshold)\nK            pixelate size · Shift+K slit-scan\n"
		+ "L            palette quantise\nJ            dither\nV            CRT off/soft/heavy\n"
		+ "M            monitor in the scene\nN            monitor size (drag to move)\n"
		+ "B            3D solid of selected icon at mouse\nShift+B      next shape\n"
		+ ";            MIDI + audio panel\nA            audio: off/mic/test/file (drop mp3/ogg/wav)\n"
		+ "drop image   raster slot (Shift+drop: chroma backdrop)\nZ            webcam: off/layer/backdrop\n"
		+ "S            steal palette from raster / webcam · Shift+S mosaic\nD            glow off/soft/heavy\n"
		+ "Shift+E      evolve (Enter keep · Shift+Enter discard)\nShift+A      attract mode (auto after 60 s idle)\n"
		+ "Shift+R      record controller gestures · Shift+P loop them\nShift+W/T/Y/U  Lorenz / Rössler / Clifford / de Jong verbs\n"
		+ "Shift+N      particle field (right-click scatters) · Shift+I Field verb\nShift+O      reaction-diffusion presets\n"
		+ "keypad/pad   player 2: 8/2/4/6 or stick moves · 5/A spawns · 0/B removes\n             +/-/X slot · ./Y layer · */LB spin · //RB solid · Shift+2 hides\n"
		+ "Shift+Esc    PANIC: known-good look · Shift+H blackout · Shift+F quality lock\n"
		+ "Shift+V      screenshot + credits strip · Shift+L credits ticker · Shift+C credits roll\n"
		+ "Shift+Z      Syphon output (picture, no HUD) · clock: ; panel or MIDI clock in\n"
		+ "drop .svg/.ttf/.txt/.ogv   icon / font for words / word list / video slot\nclick Sparkle icon   pinata\n"
		+ "F1-F12       recall preset · Shift+F saves · Shift+, . bank · Shift+- = prev/next preset · Shift+; fade\n"
		+ "Tab          next scene (Shift: previous) · ` off\narrows       feedback drift · PgUp/PgDn warp · Home reset\n"
		+ "Shift+arrows camera orbit / dolly · Shift+PgUp/Dn roll · Shift+Home reset\n"
		+ "Shift+Space  formation of 200 (Shift+X: helix/lattice/shell/ring)\n"
		+ "\\            next layer · Shift+\\ blend · Shift+[ ] opacity\nShift+D      draw mode: drag a path, icons ride it\n"
		+ "C            clear stage\n"
		+ "H            hide this\nEsc          menu / attribution", 16)
	_help.add_child(hl)
	add_child(_help)

	var top_right := HBoxContainer.new()
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.offset_right = -20
	top_right.offset_top = 14
	top_right.add_child(UI.button("Find Icons", func(): navigate.emit("search")))
	top_right.add_child(UI.hspace(8))
	top_right.add_child(UI.button("← Back", func(): navigate.emit("start")))
	add_child(top_right)

	_hotbar = HotbarScript.new()
	_hotbar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hotbar.offset_bottom = -20
	add_child(_hotbar)


func _refresh_verbs() -> void:
	var idx := Toolbox.selected
	var has := not Toolbox.current().is_empty()
	for id in _verb_checks:
		var cb: CheckButton = _verb_checks[id]
		cb.disabled = not has
		cb.set_pressed_no_signal(Toolbox.has_verb(idx, id))
	_update_hud()


func _refresh_fx() -> void:
	_fx_kaleido_btn.text = "O  Kaleidoscope: %s" % ("off" if _fx.kaleido_step == 0 else "%d" % _fx.kaleido_segments())
	_fx_key_btn.text = "G  Key: %s" % _fx.KEY_MODES[_fx.key_mode] + ("" if _fx.key_mode < 2 else "  (thr %.2f)" % _fx.key_threshold)
	_fx_slit_btn.text = "⇧K  Slit-scan: %s" % _fx.SLIT_MODES[_fx.slit_mode]
	_fx_crt_btn.text = "V  CRT: %s" % ["off", "soft", "heavy"][_fx.crt_level]
	_fx_glow_btn.text = "D  Glow: %s" % _glow.describe()
	_fx_pixel_btn.text = "K  Pixelate: %s" % ("off" if _fx.pixel_step == 0 else "%d px" % _fx.pixel_size())
	_fx_quant.set_pressed_no_signal(_fx.quantize)
	_fx_dither.set_pressed_no_signal(_fx.dither)
	_fx_dither.disabled = not _fx.quantize
	_update_hud()


func set_monitor(on: bool, size_step := -1) -> void:
	_monitor.visible = on
	if size_step >= 0:
		_monitor.size_step = size_step
		_monitor._apply_scale()
	_update_hud()


## Used by --capture.
func set_fx(pixel: int, quant: bool, dith: bool, kaleido := 0, chroma := false, crt := 0, key := -1, slit := 0) -> void:
	_fx.set_state(pixel, quant, dith, kaleido, chroma, crt, key, slit)
	_refresh_fx()


## Plain drop: the image becomes a toolbox slot with verbs like any icon.
func add_raster(path: String) -> int:
	var idx := Toolbox.add_raster(path)
	if idx >= 0:
		Ledger.record_local(Toolbox.slots[idx])
		_steal_note = "added “%s” to slot %d — S steals its palette" % [Toolbox.slots[idx]["term"], idx + 1]
	else:
		_steal_note = "could not add image (toolbox full?)"
	_update_hud()
	return idx


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		var ext := f.get_extension().to_lower()
		if ext in IconMedia.RASTER_EXT:
			if Input.is_key_pressed(KEY_SHIFT):
				# Shift+drop: chroma-key backdrop
				if _fx.set_backdrop_from_file(f):
					if _fx.key_mode == 0:
						_fx.key_mode = 1
						_fx._push()
					_refresh_fx()
			else:
				add_raster(f)
			return
		if ext in ["mp3", "ogg", "wav"]:
			AudioReact.load_file(f)
			_update_hud()
			return
		if ext == "svg":
			var si := Toolbox.add_svg(f)
			if si >= 0:
				Ledger.record_local(Toolbox.slots[si])
				_steal_note = "added SVG “%s” to slot %d" % [Toolbox.slots[si]["term"], si + 1]
			_update_hud()
			return
		if ext in ["ttf", "otf"]:
			_steal_note = ("font set: %s — new words use it" % f.get_file()) if TextRaster.set_font_file(f) else "could not load that font"
			_update_hud()
			return
		if ext == "txt":
			var lines := Array(FileAccess.get_file_as_string(f).split("\n"))
			var wi := Toolbox.add_words(lines)
			if wi >= 0:
				Ledger.record_local(Toolbox.slots[wi])
				_steal_note = "added words to slot %d%s" % [wi + 1, " (cycling on the beat)" if Toolbox.slots[wi].has("words") else ""]
			else:
				_steal_note = "could not add the word list (empty, or toolbox full)"
			_update_hud()
			return
		if ext == "ogv":
			var vi := Toolbox.add_video(f)
			if vi >= 0:
				Ledger.record_local(Toolbox.slots[vi])
				_sync_videos()
				_steal_note = "added video “%s” to slot %d" % [Toolbox.slots[vi]["term"], vi + 1]
			_update_hud()
			return


func _update_hud() -> void:
	if _fx_glow_btn:
		_fx_glow_btn.text = "D  Glow: %s" % _glow.describe()
	if _fx_scene_btn:
		_fx_scene_btn.text = "Tab  Scene: %s" % (Scenes.get_scene(Scenes.current).get("name", "?") if Scenes.current != "" else "off")
	var cur := Toolbox.current()
	var name := str(cur.get("term", "—")) if not cur.is_empty() else "empty toolbox — press Find Icons"
	_hud.text = "fps %d/%dHz · work %.1f ms · q %s   ·   slot %d: %s   ·   palette: %s   ·   feedback: %s   ·   fx: %s   ·   monitor: %s   ·   actors: %d" % [
		Engine.get_frames_per_second(), roundi(DisplayServer.screen_get_refresh_rate()), quality.avg_ms, quality.describe(),
		Toolbox.selected + 1, name, Palettes.get_palette(palette_index)["name"],
		("zoom %.2f  twist %.2f  fade %.2f" % [fb_zoom, fb_rot, fb_fade]) if feedback else "off",
		_fx.describe() + ("" if _glow.level == 0 else "  glow " + _glow.describe()), ("%.0f%%" % (_monitor.scale_factor() * 100.0)) if _monitor.visible else "off",
		all_actors().size()] + "   ·   layer %s%s   ·   solids: %d (next: %s)   ·   formations: %d (%s)" % [layer_describe(), ("   ·   DRAW" if draw_mode else "") + ("   ·   EVOLVE" if evolve else "") + ("   ·   ATTRACT" if attract else "") + ("   ·   BLACKOUT" if blackout else "") + ("   ·   TICKER" if ticker_on else "") + ("   ·   CREDITS" if _roll.visible else "") + (("   ·   REC %.1fs" % (_clock - timeline._rec_start)) if timeline.recording else "") + (("   ·   LOOP %.1f/%.1fs" % [timeline.position(_clock), timeline.length]) if timeline.playing else ""), _solids.get_child_count(), next_shape(), _formations.get_child_count(), formation_kind()] \
		+ (("   ·   cam orbit %.2f dolly %.1f roll %.2f h %.1f" % [cam_orbit, cam_dolly, cam_roll, cam_height]) if (cam_orbit != 0.0 or cam_roll != 0.0 or cam_height != 0.0 or cam_dolly != 7.5) else "")
	# second line: controllers
	var line2 := "midi: " + (_midi_last if _midi_last != "" else "—")
	line2 += "   ·   audio: " + ((("%s  %s" % [AudioReact.source if AudioReact.source != "file" else AudioReact.file_name, _meter()])) if AudioReact.active() else "off (A)")
	if AudioReact.driver_missing():
		line2 += "   ·   no audio device: mic/file unavailable"
	line2 += "   ·   webcam: " + (("%s, %s" % [webcam_mode(), _webcam.status]) if _webcam_mode > 0 else "off (Z)")
	if _steal_note != "":
		line2 += "   ·   " + _steal_note
	line2 += "   ·   clock: " + Clock.describe() + (" ·lock" if Clock.lock_scenes else "")
	if syphon_on:
		line2 += "   ·   SYPHON"
	line2 += "   ·   bank %d · fade %.1fs%s" % [bank + 1, preset_fade, "   XFADE" if crossfading() else ""]
	line2 += "   ·   scene: " + (("%s  spd %.1f  scl %.1f" % [Scenes.get_scene(Scenes.current).get("name", "?"), Scenes.speed, Scenes.scale]) if Scenes.current != "" else "off (Tab)")
	if p2_active:
		line2 += "   ·   P2: slot %d, layer %d" % [p2_slot + 1, p2_layer + 1]
	if particles_on:
		line2 += "   ·   particles flow %.1f %s %.1f" % [particles_flow, "repel" if particles_attract < 0.0 else "attract", absf(particles_attract)]
	if rd_preset > 0:
		line2 += "   ·   rd " + rd_describe()
	if fb_warp > 0.0 or fb_drift != Vector2.ZERO:
		line2 += "   ·   warp %.2f drift %d,%d" % [fb_warp, fb_drift.x, fb_drift.y]
	_hud.text += "\n" + line2


static func _bar(v: float) -> String:
	var n := clampi(roundi(v * 5.0), 0, 5)
	return "▮".repeat(n) + "▯".repeat(5 - n)


func _meter() -> String:
	return "bass %s mid %s high %s" % [_bar(AudioReact.bass), _bar(AudioReact.mid), _bar(AudioReact.high)]


# ---------------- palette / feedback ----------------
func _apply_palette() -> void:
	_bg.color = Palettes.bg(palette_index)
	_fx.set_palette(palette_index)
	Scenes.apply_palette(_layer_mix.material, palette_index)
	if p2_active:
		_refresh_p2()
	_fx.set_source(_worldmix.get_texture(), Palettes.bg(palette_index))
	_monitor.accent = Palettes.color(palette_index, 0)
	_monitor.queue_redraw()
	_scene_layer.set_palette(palette_index)
	_hotbar.palette_index = palette_index
	_hotbar.refresh()
	for a in all_actors() + _solids.get_children():
		var i := Toolbox.index_of(a.slot_id)
		if i >= 0:
			a.set_palette(palette_index, int(Toolbox.slots[i].get("color_index", i)))
	for f in _formations.get_children():
		var i := Toolbox.index_of(f.slot_id)
		if i >= 0:
			f.recolor(palette_index, int(Toolbox.slots[i].get("color_index", i)))
	_update_hud()


func _recolor() -> void:
	Toolbox.cycle_color(Toolbox.selected)
	_apply_palette()


func _set_feedback(on: bool) -> void:
	feedback = on
	if not on:
		_screen.texture = _worldmix.get_texture()
		for vp in _acc:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_update_hud()


var _prof := {}


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick_crossfade(_delta)
	_tick_credits(_delta)
	_tick_clock()
	_tick_words(_delta)
	_tick_modes(_delta)
	var t1 := Time.get_ticks_usec()
	_tick_timeline(_delta)
	_tick_rd()
	var t2 := Time.get_ticks_usec()
	_tick_quality(_delta)
	var t3 := Time.get_ticks_usec()
	_tick_p2(_delta)
	var t4 := Time.get_ticks_usec()
	if particles_on:
		_push_particles()
	var t5 := Time.get_ticks_usec()
	_prof = {"modes": t1 - t0, "tl_rd": t2 - t1, "quality": t3 - t2, "p2": t4 - t3, "particles": t5 - t4}
	var mouse := _world_pos(get_local_mouse_position())
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _dragging
	for a in all_actors():
		a.mouse_world = mouse
		a.attract = held
	for sol in _solids.get_children():
		sol.attract = held
	_cam_angle += cam_orbit * _delta
	_camera.position = Vector3(sin(_cam_angle) * cam_dolly, cam_height, cos(_cam_angle) * cam_dolly)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_camera.rotate_object_local(Vector3.FORWARD, cam_roll)
	if _solids.get_child_count() > 0:
		var mp := _camera.project_position(mouse, cam_dolly)
		for sol in _solids.get_children():
			sol.mouse_point = mp
	if feedback:
		var cur: int = _flip
		_flip = 1 - _flip
		var prev: MeshInstance2D = _acc_prev[cur]
		prev.scale = Vector2.ONE * fb_zoom
		prev.rotation = fb_rot
		prev.modulate = Color(1, 1, 1, fb_fade)
		var m: ShaderMaterial = _acc_mats[cur]
		m.set_shader_parameter("warp", fb_warp)
		m.set_shader_parameter("warp_speed", fb_warp_speed)
		m.set_shader_parameter("drift", fb_drift)
		m.set_shader_parameter("stretch", fb_stretch)
		_acc[1 - cur].render_target_update_mode = SubViewport.UPDATE_DISABLED
		_acc[cur].render_target_update_mode = SubViewport.UPDATE_ONCE
		_screen.texture = _acc[cur].get_texture()
	if Engine.get_process_frames() % (4 if AudioReact.active() else 15) == 0:
		_update_hud()


# ---------------- spawning ----------------
func _world_pos(local: Vector2) -> Vector2:
	# Map the on-screen rect (keep-aspect centred) back to world pixels.
	var rect := _display.get_rect()
	var scale := minf(rect.size.x / WORLD.x, rect.size.y / WORLD.y)
	var drawn := Vector2(WORLD) * scale
	var origin := rect.position + (rect.size - drawn) * 0.5
	return (local - origin) / scale


func spawn_at(world_pos: Vector2) -> void:
	spawn_slot_at(Toolbox.selected, active_layer, world_pos)


## Spawn a given slot into a given layer (player 2 uses its own of each).
func spawn_slot_at(slot_index: int, layer_index: int, world_pos: Vector2) -> void:
	if slot_index < 0 or slot_index >= Toolbox.slots.size():
		return
	var slot: Dictionary = Toolbox.slots[slot_index]
	var a := Node2D.new()
	a.set_script(ActorScript)
	a.setup(slot, world_pos, palette_index, Rect2(Vector2.ZERO, Vector2(WORLD)))
	_layers[posmod(layer_index, LAYER_COUNT)]["actors"].add_child(a)
	_update_hud()


func demo_spawn() -> void:
	## Used by --capture: a few actors with verbs on, so the screenshot shows something.
	if Toolbox.slots.is_empty():
		return
	for i in 12:
		Toolbox.select(i % Toolbox.slots.size())
		spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))


func _remove_nearest(world_pos: Vector2) -> void:
	for r in all_rides():                          # a stroke under the cursor goes first
		if r.near(world_pos):
			r.queue_free()
			return
	var best: Node2D = null
	var best_d := 1e9
	for a in all_actors():
		var d: float = a.global_position.distance_to(world_pos) if a.riding else a.position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = a
	for sol in _solids.get_children():
		var d: float = _camera.unproject_position(sol.position).distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = sol
	if best and best_d < 160.0:
		best.queue_free()
	else:
		for a in all_actors():                        # nothing near: scatter the flocks
			a.scatter_from = world_pos
		scatter_particles()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var wp := _world_pos(ev.position)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				if _monitor.visible and _monitor.contains(wp):
					_dragging = true
					_drag_offset = _monitor.position - wp
				elif draw_mode:
					begin_stroke(wp)
				elif not pinata_at(wp):
					spawn_at(wp)
			else:
				_dragging = false
				if not _stroke.is_empty():
					end_stroke()
		elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			_remove_nearest(wp)
	elif ev is InputEventMouseMotion and _dragging:
		_monitor.position = _world_pos(ev.position) + _drag_offset
	elif ev is InputEventMouseMotion and not _stroke.is_empty():
		extend_stroke(_world_pos(ev.position))


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed):
		return
	var k: int = ev.keycode
	if _p2_key(k):
		return
	if k >= KEY_F1 and k <= KEY_F12:
		var n := k - KEY_F1 + 1
		if ev.shift_pressed:
			save_preset(n)
		else:
			recall_preset(n)
		return
	if k == KEY_2 and ev.shift_pressed:
		p2_sleep()
		return
	if k == KEY_ESCAPE and ev.shift_pressed:
		panic()
		return
	if k >= KEY_1 and k <= KEY_9:
		Toolbox.select(k - KEY_1)
		return
	match k:
		KEY_TAB:
			step_scene(-1 if ev.shift_pressed else 1)
			get_viewport().set_input_as_handled()
			return
		KEY_QUOTELEFT:
			set_scene("")
			return
		KEY_UP:
			if ev.shift_pressed: cam_dolly = maxf(3.0, cam_dolly - 0.5)
			else: fb_drift.y -= 1.0
		KEY_DOWN:
			if ev.shift_pressed: cam_dolly = minf(14.0, cam_dolly + 0.5)
			else: fb_drift.y += 1.0
		KEY_LEFT:
			if ev.shift_pressed: cam_orbit = clampf(cam_orbit - 0.1, -1.5, 1.5)
			else: fb_drift.x -= 1.0
		KEY_RIGHT:
			if ev.shift_pressed: cam_orbit = clampf(cam_orbit + 0.1, -1.5, 1.5)
			else: fb_drift.x += 1.0
		KEY_PAGEUP:
			if ev.shift_pressed: cam_roll += 0.1
			else: fb_warp = minf(1.0, fb_warp + 0.05)
		KEY_PAGEDOWN:
			if ev.shift_pressed: cam_roll -= 0.1
			else: fb_warp = maxf(0.0, fb_warp - 0.05)
		KEY_HOME:
			if ev.shift_pressed:
				reset_camera()
			else:
				fb_warp = 0.0
				fb_drift = Vector2.ZERO
				fb_stretch = Vector2.ONE
	var verb := Verbs.by_key(k, ev.shift_pressed)
	if verb != "" and not Toolbox.current().is_empty():
		Toolbox.toggle_verb(Toolbox.selected, verb)
		return
	match k:
		KEY_SPACE:
			if ev.shift_pressed:
				spawn_formation()
			else:
				spawn_at(Vector2(randf_range(100, WORLD.x - 100), randf_range(100, WORLD.y - 100)))
		KEY_X:
			if ev.shift_pressed:
				cycle_formation()
			else:
				_recolor()
		KEY_DELETE, KEY_BACKSPACE: Toolbox.remove(Toolbox.selected)
		KEY_F:
			if ev.shift_pressed:
				cycle_quality_lock()
			else:
				_set_feedback(not feedback)
		KEY_BRACKETLEFT:
			if ev.shift_pressed: set_layer_opacity(_layers[active_layer]["opacity"] - 0.1)
			else: fb_zoom = maxf(0.90, fb_zoom - 0.01)
		KEY_BRACKETRIGHT:
			if ev.shift_pressed: set_layer_opacity(_layers[active_layer]["opacity"] + 0.1)
			else: fb_zoom = minf(1.20, fb_zoom + 0.01)
		KEY_COMMA:
			if ev.shift_pressed: set_bank(bank - 1)
			else: fb_rot -= 0.01
		KEY_PERIOD:
			if ev.shift_pressed: set_bank(bank + 1)
			else: fb_rot += 0.01
		KEY_B:
			if ev.shift_pressed:
				cycle_shape()
			else:
				spawn_solid(_world_pos(get_local_mouse_position()) if get_global_rect().has_point(get_global_mouse_position()) else Vector2(-1, -1))
		KEY_SEMICOLON:
			if ev.shift_pressed:
				cycle_fade()
			else:
				toggle_midi_panel()
		KEY_Z:
			if ev.shift_pressed:
				set_syphon(not syphon_on)
			else:
				cycle_webcam()
		KEY_D:
			if ev.shift_pressed:
				draw_mode = not draw_mode
				_steal_note = "draw mode: drag a path, the selected icon rides it" if draw_mode else ""
				_update_hud()
			else:
				_glow.cycle()
				_update_hud()
		KEY_BACKSLASH:
			if ev.shift_pressed:
				cycle_blend()
			else:
				set_active_layer(active_layer + 1)
		KEY_S:
			if ev.shift_pressed:
				spawn_mosaic()
			else:
				steal_palette()
		KEY_E:
			if ev.shift_pressed:
				set_evolve(not evolve)
		KEY_N:
			if ev.shift_pressed:
				set_particles(not particles_on)
			else:
				_monitor.cycle_size()
				_update_hud()
		KEY_O:
			if ev.shift_pressed:
				cycle_rd()
			else:
				_fx.cycle_kaleido()
				_refresh_fx()
		KEY_R:
			if ev.shift_pressed:
				toggle_record()
		KEY_P:
			if ev.shift_pressed:
				toggle_play()
			else:
				palette_index = (palette_index + 1) % Palettes.count()
				_apply_palette()
		KEY_ENTER, KEY_KP_ENTER:
			if evolve:
				if ev.shift_pressed:
					evolve_discard()
				else:
					evolve_keep()
		KEY_A:
			if ev.shift_pressed:
				set_attract(not attract)
			else:
				AudioReact.cycle_source()
				_update_hud()
		KEY_M: set_monitor(not _monitor.visible)
		KEY_V:
			if ev.shift_pressed:
				screenshot_with_credits()
			else:
				_fx.cycle_crt()
				_refresh_fx()
		KEY_G:
			if ev.shift_pressed:
				_fx.key_threshold = fmod(_fx.key_threshold + 0.1, 0.95)
				_fx._push()
			else:
				_fx.cycle_key()
			_refresh_fx()
		KEY_K:
			if ev.shift_pressed:
				_fx.cycle_slit()
			else:
				_fx.cycle_pixelate()
			_refresh_fx()
		KEY_L:
			if ev.shift_pressed:
				set_ticker(not ticker_on)
			else:
				_fx.toggle_quantize()
				_refresh_fx()
		KEY_J:
			_fx.toggle_dither()
			_refresh_fx()
		KEY_MINUS:
			if ev.shift_pressed: step_preset(-1)
			else: fb_fade = maxf(0.5, fb_fade - 0.02)
		KEY_EQUAL:
			if ev.shift_pressed: step_preset(1)
			else: fb_fade = minf(0.995, fb_fade + 0.02)
		KEY_C:
			if ev.shift_pressed:
				if _roll.visible:
					stop_credits_roll()
				else:
					start_credits_roll()
				return
			clear_actors()
			for a in _solids.get_children() + _formations.get_children():
				a.queue_free()
		KEY_H:
			if ev.shift_pressed:
				toggle_blackout()
				return
			_help.visible = not _help.visible
			_verb_panel.get_parent().visible = _help.visible
			_hud.get_parent().visible = _help.visible
	_update_hud()
