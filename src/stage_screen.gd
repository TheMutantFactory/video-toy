class_name Stage
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
const StageModesScript = preload("res://src/stage/modes.gd")
const StageStateScript = preload("res://src/stage/state.gd")
const StageControlsScript = preload("res://src/stage/controls.gd")
const StagePlayersScript = preload("res://src/stage/players.gd")
const StageCreditsScript = preload("res://src/stage/credits.gd")
const StageMediaScript = preload("res://src/stage/media.gd")
const StageFxrigScript = preload("res://src/stage/fxrig.gd")
const StageWorld3dScript = preload("res://src/stage/world3d.gd")
const StageLayersScript = preload("res://src/stage/layers.gd")
const StageInputScript = preload("res://src/stage/input.gd")
const StageHistoryScript = preload("res://src/stage/history.gd")
const ActorScript = preload("res://src/actor.gd")
const FxScript = preload("res://src/fx.gd")
const MonitorScript = preload("res://src/monitor.gd")
const SolidScript = preload("res://src/solid.gd")
const MidiPanelScript = preload("res://src/midi_panel.gd")
const WebcamScript = preload("res://src/webcam.gd")
const GlowScript = preload("res://src/glow.gd")
const AsciiScript = preload("res://src/ascii.gd")
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
uniform int loop_mask = 7;         // bit i: layer i re-enters the feedback loop
uniform bool overlay_pass = false; // true: only the layers NOT in the loop (drawn over the feedback)

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
	bool in0 = ((loop_mask & 1) != 0) != overlay_pass;
	bool in1 = ((loop_mask & 2) != 0) != overlay_pass;
	bool in2 = ((loop_mask & 4) != 0) != overlay_pass;
	vec4 dst = in0 ? texture(world_tex, UV) : vec4(0.0);
	if (rd_on && in0) {
		// reaction-diffusion painted UNDER the world: V through the palette
		float v = texture(rd_tex, UV).g;
		float a = smoothstep(0.08, 0.35, v);
		vec4 rd = vec4(ring_color(v * 1.6 + 0.15), a);
		dst = vec4(mix(rd.rgb, dst.rgb, dst.a), dst.a + rd.a * (1.0 - dst.a));
	}
	if (in1) {
		vec4 s1 = texture(layer1, UV);
		s1.a *= opacity1;
		dst = blend(dst, s1, mode1);
	}
	if (in2) {
		vec4 s2 = texture(layer2, UV);
		s2.a *= opacity2;
		dst = blend(dst, s2, mode2);
	}
	COLOR = dst;
}
"""
const WEBCAM_MODES := ["off", "layer", "backdrop"]
const WORLD := Vector2i(1920, 1080)

var _modes
var _state
var _controls
var _players
var _credits
var _media
var _fxrig
var _m_world3d
var _m_layers                              # src/stage/layers.gd
var _m_input                               # src/stage/input.gd
var _history                               # src/stage/history.gd (undo / redo)
var guest := false                         # mouse-only: right-click wheel, long-press removes, spawn on release
var locks: Array = []                      # Locks.SECTIONS that Surprise / evolve keep
var mutate_amount := 1.0                   # 0.25 nearby .. 1.0 everything
var _locks_panel: PanelContainer
var _lock_checks: Dictionary = {}
var _amount_slider: HSlider
var _wheel: RadialMenu
var _tour: Tour
var _press_pos := Vector2.ZERO             # guest mode: where the left button went down
var _press_ms := 0
var _press_pending := false
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
var _ascii
var _autosave_t := 0.0
var _fade_tween: Tween
var _scene_layer: Node2D
var _acc_mats: Array = []               # warp ShaderMaterials, one per accumulator
var fb_warp := 0.0
var fb_delay := 0                          # frames of delay in the loop (0 = last frame), up to RING - 1
var fb_blur := 0.0                         # -1 sharpen .. 1 blur, inside the loop
var fb_hue := 0.0                          # hue drift per pass, radians
var fb_sat := 1.0                          # saturation per pass
var fb_displace := 0.0                     # displacement amount by fb_disp_src
var fb_disp_src := 0                       # DISP_SOURCES index
var fb_cleanup := 0.0                      # cellular cleanup per pass, 0 .. 1
var fb_cleanup_rule := 0                   # CLEANUP_RULES index
const CLEANUP_RULES := ["majority", "life", "erode"]
const DISP_SOURCES := ["off", "self", "layer 2", "layer 3", "webcam"]
const RING := 24
var _ring: Array = []                      # half-res SubViewports: the loop's history for the delay tap
var _ring_rects: Array = []
var _ring_head := 0
var _overvp: SubViewport                   # the layers kept OUT of the loop, drawn over the feedback
var _over_mix: ColorRect
var _overlay: TextureRect
var _guide: FrameGuide                     # the clip's crop over the picture
var _audio_panel: PanelContainer
var _audio_widgets: Dictionary = {}
var _top_right: HBoxContainer              # ? Keys · Find Icons · Back
var _routing_panel: PanelContainer
var _routing_widgets: Dictionary = {}
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
var _help: HelpOverlay
var hud_mode := 0                         # 0 full, 1 compact, 2 hidden
var gravity := 1.0                        # for Physics icons (IconBody.gravity); 0 floats
var _grab: Node2D                         # physics icon held by the mouse
var _grab_prev := Vector2.ZERO
var _grab_vel := Vector2.ZERO
var _grab_ms := 0
var idle_attract := IDLE_ATTRACT
var autosave_interval := Autosave.INTERVAL
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
	# the stage is the coordinator; each module holds one concern and reaches back through `s`
	_m_layers = StageLayersScript.new(self)
	_m_input = StageInputScript.new(self)
	_history = StageHistoryScript.new(self)
	_modes = StageModesScript.new(self)
	_state = StageStateScript.new(self)
	_controls = StageControlsScript.new(self)
	_players = StagePlayersScript.new(self)
	_credits = StageCreditsScript.new(self)
	_media = StageMediaScript.new(self)
	_fxrig = StageFxrigScript.new(self)
	_m_world3d = StageWorld3dScript.new(self)
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
	for i in RING:                               # the delay tap's history, half resolution
		var rv := SubViewport.new()
		rv.size = WORLD / 2
		rv.disable_3d = true
		rv.transparent_bg = true
		rv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(rv)
		var rr := TextureRect.new()
		rr.size = Vector2(WORLD / 2)
		rr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rv.add_child(rr)
		_ring.append(rv)
		_ring_rects.append(rr)

	_screen = TextureRect.new()
	_screen.size = Vector2(WORLD)
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.texture = _worldmix.get_texture()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite.add_child(_screen)
	_overlay = TextureRect.new()                 # layers kept out of the loop ride over the feedback
	_overlay.size = Vector2(WORLD)
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.texture = _overvp.get_texture()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_composite.add_child(_overlay)

	_glow = GlowScript.new()                     # bloom before fx, so CRT sees it
	_composite.add_child(_glow)

	_fx = FxScript.new()
	_composite.add_child(_fx)
	_fx.set_source(_worldmix.get_texture(), Palettes.bg(palette_index))

	_ascii = AsciiScript.new()                   # last pass: the picture as glyphs
	_composite.add_child(_ascii)

	_display = TextureRect.new()
	_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_display.texture = _composite.get_texture()
	_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_display)
	_guide = FrameGuide.new()
	_guide.display = _display
	_guide.world = WORLD
	add_child(_guide)
	_display.resized.connect(_guide.queue_redraw)
	set_clip_format(str(Settings.get_value("clip_format")), false)

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
	_wheel = RadialMenu.new()
	_wheel.provider = _wheel_items
	_wheel.picked.connect(_on_wheel_pick)
	add_child(_wheel)
	_tour = Tour.new()
	add_child(_tour)
	set_guest(bool(Settings.get_value("guest_mode")))
	locks = Array(Settings.get_value("locks")).filter(func(x): return Locks.SECTIONS.has(str(x))).map(func(x): return str(x))
	mutate_amount = clampf(float(Settings.get_value("mutate_amount")), 0.0, 1.0)
	MidiOut.configure(str(Settings.get_value("osc_out_host")), int(Settings.get_value("osc_out_port")), bool(Settings.get_value("osc_out")))
	AudioReact.beat.connect(_on_beat_out)
	if not Tour.suppress and not Tour.seen():
		call_deferred("start_tour")
	Sounds.attach(self)
	IconBody.gravity = gravity
	Toolbox.selection_changed.connect(func(_i): _refresh_verbs())
	Toolbox.changed.connect(_refresh_verbs)
	_refresh_verbs()
	_apply_palette()
	_refresh_fx()
	get_window().files_dropped.connect(_on_files_dropped)
	_build_midi()
	_sync_videos()
	Toolbox.changed.connect(_sync_videos)
	var names := Quality.LEVELS.map(func(l): return l["name"])
	var lock := str(Settings.get_value("quality_lock"))
	if names.has(lock):
		quality.locked = names.find(lock)
	var args := OS.get_cmdline_user_args()
	var qi := args.find("--quality")
	if qi >= 0 and qi + 1 < args.size():
		var want: String = args[qi + 1]
		quality.locked = names.find(want) if names.has(want) else (int(want) if want.is_valid_int() else -1)
	autosave_interval = maxf(5.0, float(Settings.get_value("autosave_interval")))
	idle_attract = maxf(10.0, float(Settings.get_value("attract_idle")))
	set_hud_mode(maxi(0, ["full", "compact", "hidden"].find(str(Settings.get_value("hud")))))
	apply_quality(quality.effective())
	_enable_measurement()


func _exit_tree() -> void:
	Sounds.detach()
	if AudioReact.beat.is_connected(_on_beat_out):
		AudioReact.beat.disconnect(_on_beat_out)
	_m_input.teardown()
	if get_window() and get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)
	_controls.teardown()
	_fxrig.teardown()


# ---------------- layers + draw mode (src/stage/layers.gd) ----------------
func _build_layers() -> void:
	_m_layers.build()


func _apply_layers() -> void:
	_m_layers.apply()


func layer_actors() -> Node2D:
	return _m_layers.layer_actors()


func all_actors() -> Array:
	return _m_layers.all_actors()


func all_rides() -> Array:
	return _m_layers.all_rides()


func set_active_layer(i: int) -> void:
	_m_layers.set_active_layer(i)


func cycle_blend() -> void:
	_m_layers.cycle_blend()


func set_layer_opacity(v: float) -> void:
	_m_layers.set_layer_opacity(v)


func clear_actors() -> void:
	_history.push("clear")
	_m_layers.clear_actors()


func undo() -> bool:
	return _history.undo()


# ---------------- guest mode: the wheel ----------------
func set_guest(on: bool) -> void:
	guest = on
	if not on:
		_wheel.close()
	_steal_note = "guest: right-click = wheel, hold = remove" if on else "guest mode off"
	_update_hud()


# ---------------- lock and mutate ----------------
func set_locks(sections: Array) -> void:
	locks = []
	for sec in sections:
		if Locks.SECTIONS.has(str(sec)) and not locks.has(str(sec)):
			locks.append(str(sec))
	Settings.set_value("locks", locks)
	_steal_note = ("locked: " + ", ".join(locks)) if not locks.is_empty() else "no locks: Surprise and evolve may change anything"
	_refresh_locks_panel()
	_update_hud()


func toggle_lock(section: String) -> void:
	var l := locks.duplicate()
	if l.has(section):
		l.erase(section)
	else:
		l.append(section)
	set_locks(l)


func set_mutate_amount(v: float) -> void:
	mutate_amount = clampf(v, 0.0, 1.0)
	Settings.set_value("mutate_amount", mutate_amount)
	_steal_note = "mutation amount %.2f (%d mutation%s per surprise)" % [mutate_amount, Locks.mutation_count(mutate_amount), "" if Locks.mutation_count(mutate_amount) == 1 else "s"]
	_refresh_locks_panel()
	_update_hud()


func toggle_locks_panel() -> void:
	if _locks_panel == null:
		_locks_panel = PanelContainer.new()
		_locks_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_locks_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_locks_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		_locks_panel.add_child(col)
		col.add_child(UI.label("Lock and mutate", 26, UI.ACCENT))
		col.add_child(UI.label("Locked sections keep their look through Surprise me (Ctrl+R) and evolve (Shift+E); everything else varies.", 15, UI.DIM))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 14)
		col.add_child(grid)
		for sec in Locks.SECTIONS:
			var cb := CheckButton.new()
			cb.text = sec
			cb.toggled.connect(func(_on: bool): toggle_lock(sec))
			grid.add_child(cb)
			_lock_checks[sec] = cb
		col.add_child(UI.label("Amount: how far a mutation reaches — nearby keeps the idea, everything is a new one. Ctrl+M cycles it.", 15, UI.DIM))
		_amount_slider = HSlider.new()
		_amount_slider.min_value = 0.0
		_amount_slider.max_value = 1.0
		_amount_slider.step = 0.05
		_amount_slider.custom_minimum_size = Vector2(420, 30)
		_amount_slider.value_changed.connect(set_mutate_amount)
		col.add_child(_amount_slider)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.button("Clear locks", func(): set_locks([]), 130))
		row.add_child(UI.button("Surprise me", surprise, 130))
		row.add_child(UI.button("Close (Ctrl+L)", toggle_locks_panel, 150))
		col.add_child(row)
		add_child(_locks_panel)
		_refresh_locks_panel()
	else:
		_locks_panel.visible = not _locks_panel.visible
	if _locks_panel.visible:
		move_child(_locks_panel, -1)


func _refresh_locks_panel() -> void:
	if _locks_panel == null:
		return
	for sec in _lock_checks:
		_lock_checks[sec].set_pressed_no_signal(locks.has(sec))
	_amount_slider.set_value_no_signal(mutate_amount)


func open_wheel(screen_pos: Vector2, page := "slots") -> void:
	_wheel.open_at(screen_pos, page)


func start_tour() -> void:
	_tour.start()


## What the wheel shows on each page (RadialMenu asks; it stays pure).
func _wheel_items(page: String) -> Array:
	var out: Array = []
	match page:
		"slots":
			for i in Toolbox.slots.size():
				var sl: Dictionary = Toolbox.slots[i]
				out.append({"text": "%d %s" % [i + 1, sl.get("term", "")], "tex": IconMedia.texture_for(str(sl.get("svg_path", ""))),
					"color": Color.WHITE if Toolbox.is_raster_slot(sl) else Palettes.color(palette_index, int(sl.get("color_index", i))), "on": i == Toolbox.selected})
			if out.is_empty():
				out.append({"text": "empty toolbox", "sub": "Find Icons or Load demo shapes"})
		"verbs":
			for v in Verbs.all():
				out.append({"text": str(v["name"]), "sub": str(v["key"]), "on": Toolbox.has_verb(Toolbox.selected, str(v["id"]))})
		_:
			out = [{"text": "palette", "sub": Palettes.get_palette(palette_index)["name"]}, {"text": "surprise", "sub": "a random look"},
				{"text": "feedback", "sub": "on" if feedback else "off", "on": feedback}, {"text": "3D solid", "sub": next_shape()},
				{"text": "formation", "sub": formation_kind()}, {"text": "scene", "sub": "next"}, {"text": "glow", "sub": _glow.describe()},
				{"text": "undo", "sub": "last thing"}, {"text": "clear", "sub": "the stage"}, {"text": "panic", "sub": "known-good look"}]
	return out


func _on_wheel_pick(page: String, i: int) -> void:
	match page:
		"slots":
			if i < Toolbox.slots.size():
				Toolbox.select(i)
		"verbs":
			if not Toolbox.current().is_empty():
				Toolbox.toggle_verb(Toolbox.selected, str(Verbs.all()[i]["id"]))
		_:
			match i:
				0:
					palette_index = (palette_index + 1) % Palettes.count()
					_apply_palette()
				1: surprise()
				2: _set_feedback(not feedback)
				3: spawn_solid(_wheel.centre if _wheel.visible else Vector2(-1, -1))
				4: spawn_formation()
				5: step_scene(1)
				6: _glow.cycle()
				7: undo()
				8: clear_actors()
				9: panic()
	_update_hud()


func redo() -> bool:
	return _history.redo()


## A random look from a known-good base (Ctrl+R, the start screen, an action).
func surprise(mutations := 6) -> String:
	return _modes.surprise(mutations)


func layer_describe() -> String:
	return _m_layers.describe()


func begin_stroke(world_pos: Vector2) -> void:
	_m_layers.begin_stroke(world_pos)


func extend_stroke(world_pos: Vector2) -> void:
	_m_layers.extend_stroke(world_pos)


func end_stroke() -> int:
	return _history.batch("path", _m_layers.end_stroke)


# ---------------- particle field ----------------
func _build_particles() -> void:
	_fxrig._build_particles()


func set_particles(on: bool) -> void:
	_fxrig.set_particles(on)


func _push_particles() -> void:
	_fxrig._push_particles()


func scatter_particles() -> void:
	_fxrig.scatter_particles()


func _build_rd() -> void:
	_fxrig._build_rd()


func set_rd_preset(i: int) -> void:
	_fxrig.set_rd_preset(i)


func cycle_rd() -> void:
	_fxrig.cycle_rd()


func _push_rd() -> void:
	_fxrig._push_rd()


func _tick_rd() -> void:
	_fxrig._tick_rd()


func rd_describe() -> String:
	return _fxrig.rd_describe()


func _build_webcam() -> void:
	_media._build_webcam()


func webcam_mode() -> String:
	return _media.webcam_mode()


func set_webcam_mode(i: int) -> void:
	_media.set_webcam_mode(i)


func cycle_webcam() -> void:
	_media.cycle_webcam()


func steal_palette() -> void:
	_media.steal_palette()


func _build_3d() -> void:
	_m_world3d._build_3d()


func next_shape() -> String:
	return _m_world3d.next_shape()


func spawn_solid(world_pos := Vector2(-1, -1)) -> void:
	_history.batch("solid", func(): _spawn_solid(world_pos))


func _spawn_solid(world_pos := Vector2(-1, -1)) -> void:
	_m_world3d.spawn_solid(world_pos)


func formation_kind() -> String:
	return _m_world3d.formation_kind()


func cycle_formation() -> void:
	_m_world3d.cycle_formation()


func spawn_formation(n := 200) -> void:
	_history.batch("formation", func(): _spawn_formation(n))


func _spawn_formation(n := 200) -> void:
	_m_world3d.spawn_formation(n)


func reset_camera() -> void:
	_m_world3d.reset_camera()


func cycle_shape() -> void:
	_m_world3d.cycle_shape()


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
	return _history.batch("mosaic", _spawn_mosaic)


func _spawn_mosaic() -> int:
	return _media.spawn_mosaic()


func mutate() -> String:
	return _modes.mutate()


func set_evolve(on: bool) -> void:
	_modes.set_evolve(on)


func evolve_step() -> void:
	_modes.evolve_step()


func evolve_keep() -> void:
	_modes.evolve_keep()


func evolve_discard() -> void:
	_modes.evolve_discard()


func set_attract(on: bool) -> void:
	_modes.set_attract(on)


func attract_step() -> void:
	_modes.attract_step()


func _tick_modes(delta: float) -> void:
	_modes._tick_modes(delta)


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
	_media._sync_videos()


func _tick_words(delta: float) -> void:
	_media._tick_words(delta)


func advance_words() -> void:
	_media.advance_words()


func pinata_at(world_pos: Vector2, radius := 90.0) -> bool:
	return bool(_history.batch("pinata", func(): return _pinata_at(world_pos, radius)))


func _pinata_at(world_pos: Vector2, radius := 90.0) -> bool:
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
	return _media.syphon_available()


func set_syphon(on: bool) -> void:
	_media.set_syphon(on)


func _tick_clock() -> void:
	_controls._tick_clock()


func onstage_ids() -> Array:
	return _credits.onstage_ids()


func onstage_credit_lines() -> Array:
	return _credits.onstage_credit_lines()


func set_ticker(on: bool) -> void:
	_credits.set_ticker(on)


func _refresh_ticker() -> void:
	_credits._refresh_ticker()


func screenshot_with_credits() -> String:
	return _credits.screenshot_with_credits()


func start_credits_roll() -> void:
	_credits.start_credits_roll()


func stop_credits_roll() -> void:
	_credits.stop_credits_roll()


func _tick_credits(delta: float) -> void:
	_credits._tick_credits(delta)


func _enable_measurement() -> void:
	_fxrig._enable_measurement()


var _t_proc := 0
var script_ms := 0.0


func _find_viewports(node: Node) -> Array:
	return _fxrig._find_viewports(node)


func measure_work_ms() -> float:
	return _fxrig.measure_work_ms()


func perf_breakdown() -> String:
	return _fxrig.perf_breakdown()


func apply_quality(level: int) -> void:
	_fxrig.apply_quality(level)


func _tick_quality(delta: float) -> void:
	_fxrig._tick_quality(delta)


func cycle_quality_lock() -> void:
	_fxrig.cycle_quality_lock()


func panic() -> void:
	_fxrig.panic()


func toggle_blackout() -> void:
	_fxrig.toggle_blackout()


func p2_wake() -> void:
	_players.p2_wake()


func p2_sleep() -> void:
	_players.p2_sleep()


func _refresh_p2() -> void:
	_players._refresh_p2()


func p2_move(delta_px: Vector2) -> void:
	_players.p2_move(delta_px)


func p2_spawn() -> void:
	_players.p2_spawn()


func p2_remove() -> void:
	_players.p2_remove()


func p2_next_slot(step := 1) -> void:
	_players.p2_next_slot(step)


func p2_next_layer() -> void:
	_players.p2_next_layer()


func p2_toggle_spin() -> void:
	_players.p2_toggle_spin()


func p2_spawn_solid() -> void:
	_players.p2_spawn_solid()


func _tick_p2(delta: float) -> void:
	_players._tick_p2(delta)


func _p2_key(k: int) -> bool:
	return _players._p2_key(k)


func _p2_pad_button(b: int) -> void:
	_players._p2_pad_button(b)


func snapshot() -> Dictionary:
	return _state.snapshot()


func restore(d: Dictionary, fade := 1.0) -> void:
	_state.restore(d, fade)


func _tick_crossfade(delta: float) -> void:
	_state._tick_crossfade(delta)


func crossfading() -> bool:
	return _state.crossfading()


func finish_crossfade() -> void:
	_state.finish_crossfade()


func _apply_snapshot(d: Dictionary, persist: bool) -> void:
	_state._apply_snapshot(d, persist)


func set_bank(b: int) -> void:
	_state.set_bank(b)


func step_preset(step: int) -> void:
	_state.step_preset(step)


func cycle_fade() -> void:
	_state.cycle_fade()


func morph(v: float) -> void:
	_state.morph(v)


func save_preset(i: int) -> void:
	_state.save_preset(i)


func recall_preset(i: int) -> void:
	_state.recall_preset(i)


func midi_params() -> Array:
	return _controls.midi_params()


func midi_actions() -> Array:
	return _controls.midi_actions()


static func _step(v: float, n: int) -> int:
	return clampi(int(floor(v * n)), 0, n - 1)


func _build_midi() -> void:
	_controls._build_midi()


func _on_midi_param(id: String, value: float) -> void:
	_controls._on_midi_param(id, value)


func _on_midi_action(id: String) -> void:
	_controls._on_midi_action(id)


func toggle_record() -> void:
	_controls.toggle_record()


func toggle_play() -> void:
	_controls.toggle_play()


func _tick_timeline(delta: float) -> void:
	_controls._tick_timeline(delta)


func toggle_midi_panel() -> void:
	_controls.toggle_midi_panel()


func _build_hud() -> void:
	var hud_card := PanelContainer.new()
	hud_card.position = Vector2(12, 8)
	add_child(hud_card)
	_hud = UI.label("", 18, UI.DIM)
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.custom_minimum_size.x = 1540             # wraps before the top-right buttons
	hud_card.add_child(_hud)

	# Verb panel sits on a translucent card so it reads on light palettes too.
	var card := PanelContainer.new()
	card.position = Vector2(12, 122)              # under the three-line HUD card
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
	for v in Verbs.all():
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

	_help = HelpOverlay.new()
	add_child(_help)

	var top_right := HBoxContainer.new()
	_top_right = top_right
	top_right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_right.offset_right = -20
	top_right.offset_top = 14
	top_right.add_child(UI.button("? Keys", func(): _help.toggle()))
	top_right.add_child(UI.hspace(8))
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
	return _media.add_raster(path)


func _on_files_dropped(files: PackedStringArray) -> void:
	_media._on_files_dropped(files)


func _update_hud() -> void:
	if _fx_glow_btn:
		_fx_glow_btn.text = "D  Glow: %s" % _glow.describe()
	if _fx_scene_btn:
		_fx_scene_btn.text = "Tab  Scene: %s" % (Scenes.get_scene(Scenes.current).get("name", "?") if Scenes.current != "" else "off")
	var cur := Toolbox.current()
	var name := str(cur.get("term", "—")) if not cur.is_empty() else "empty toolbox — press Find Icons"
	var line1: String = "fps %d/%dHz · work %.1f ms · q %s   ·   slot %d: %s   ·   palette: %s   ·   feedback: %s   ·   fx: %s   ·   monitor: %s   ·   actors: %d" % [
		Engine.get_frames_per_second(), roundi(DisplayServer.screen_get_refresh_rate()), quality.avg_ms, quality.describe(),
		Toolbox.selected + 1, name, Palettes.get_palette(palette_index)["name"],
		("zoom %.2f  twist %.2f  fade %.2f" % [fb_zoom, fb_rot, fb_fade]) if feedback else "off",
		_fx.describe() + ("" if _glow.level == 0 else "  glow " + _glow.describe()) + ("" if _ascii.mode == 0 else "  ascii " + _ascii.describe()), ("%.0f%%" % (_monitor.scale_factor() * 100.0)) if _monitor.visible else "off",
		all_actors().size()] + "   ·   layer %s%s   ·   solids: %d (next: %s)   ·   formations: %d (%s)" % [layer_describe(), ("   ·   DRAW" if draw_mode else "") + ("   ·   EVOLVE" if evolve else "") + ("   ·   ATTRACT" if attract else "") + ("   ·   BLACKOUT" if blackout else "") + ("   ·   TICKER" if ticker_on else "") + ("   ·   CREDITS" if _roll.visible else "") + (("   ·   REC %.1fs" % (_clock - timeline._rec_start)) if timeline.recording else "") + (("   ·   LOOP %.1f/%.1fs" % [timeline.position(_clock), timeline.length]) if timeline.playing else ""), _solids.get_child_count(), next_shape(), _formations.get_child_count(), formation_kind()] \
		+ (("   ·   cam orbit %.2f dolly %.1f roll %.2f h %.1f" % [cam_orbit, cam_dolly, cam_roll, cam_height]) if (cam_orbit != 0.0 or cam_roll != 0.0 or cam_height != 0.0 or cam_dolly != 7.5) else "")
	# second line: controllers
	var line2 := ("SAFE (no MIDI / OSC / camera / mic)   ·   " if Safe.active() else "") + ("GUEST (right-click: wheel)   ·   " if guest else "") + "midi: " + (_midi_last if _midi_last != "" else "—")
	line2 += "   ·   audio: " + ((("%s  %s" % [AudioReact.source if AudioReact.source != "file" else AudioReact.file_name, _meter()])) if AudioReact.active() else "off (A)")
	if AudioReact.active() and AudioReact.bpm() > 0.0 and AudioReact.bpm_confidence() >= 0.4:
		line2 += " ~%.0f bpm%s" % [AudioReact.bpm(), " → clock" if AudioReact.follow_clock else ""]
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
	if gravity != 1.0:
		line2 += "   ·   gravity %s" % ("off" if gravity == 0.0 else "%.1f" % gravity)
	if MidiOut.enabled:
		line2 += "   ·   osc out → " + MidiOut.describe()
	if not MidiMap.mods.is_empty():
		line2 += "   ·   mods: %d" % MidiMap.mods.size()
	var rd_s := routing_describe()
	if rd_s != "":
		line2 += "   ·   loop " + rd_s
	if _guide.visible:
		line2 += "   ·   clip %s" % clip_format()
	var lk := Locks.describe(locks, mutate_amount)
	if lk != "":
		line2 += "   ·   " + lk
	if hud_mode == 1:
		_hud.text = "fps %d · work %.1f ms · q %s · slot %d: %s · palette: %s · feedback: %s · fx: %s · actors: %d%s" % [
			Engine.get_frames_per_second(), quality.avg_ms, quality.describe(), Toolbox.selected + 1, name,
			Palettes.get_palette(palette_index)["name"], "on" if feedback else "off", _fx.describe(), all_actors().size(),
			"  ·  BLACKOUT" if blackout else ""]
	else:
		_hud.text = line1 + "\n" + line2


## 0 full (two lines + verb panel), 1 compact (one short line), 2 hidden:
## nothing but the picture (the hotbar and the buttons go too — a clean capture).
func set_hud_mode(m: int) -> void:
	hud_mode = clampi(m, 0, 2)
	_verb_panel.get_parent().visible = hud_mode == 0
	_hud.get_parent().visible = hud_mode < 2
	if _hotbar:
		_hotbar.visible = hud_mode < 2
	if _top_right:
		_top_right.visible = hud_mode < 2
	_update_hud()


func open_help() -> void:
	_help.open()


static func _bar(v: float) -> String:
	var n := clampi(roundi(v * 5.0), 0, 5)
	return "▮".repeat(n) + "▯".repeat(5 - n)


func _meter() -> String:
	return "bass %s mid %s high %s" % [_bar(AudioReact.bass), _bar(AudioReact.mid), _bar(AudioReact.high)]


# ---------------- palette / feedback ----------------
func _apply_palette() -> void:
	_bg.color = Palettes.bg(palette_index)
	_fx.set_palette(palette_index)
	_ascii.set_palette(palette_index)
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
		for rv in _ring:
			rv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_update_hud()


# ---------------- audio shaping (Ctrl+A) ----------------
func clock_from_audio() -> void:
	if AudioReact.clock_from_audio():
		_steal_note = "clock set from the audio: %.1f bpm" % AudioReact.bpm()
	else:
		_steal_note = "no tempo tracked yet — play something with a beat (A)"
	_update_hud()


func toggle_audio_panel() -> void:
	if _audio_panel == null:
		_audio_panel = PanelContainer.new()
		_audio_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_audio_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_audio_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		_audio_panel.add_child(col)
		col.add_child(UI.label("Audio shaping", 26, UI.ACCENT))
		col.add_child(UI.label("Each band's envelope: attack and release times, a decay to a sustain level after every rise (below 1 = transients pop), a gate and extra smoothing. The onset detector and the tempo tracker read the raw bands.", 15, UI.DIM))
		var grid := GridContainer.new()
		grid.columns = 8
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 4)
		col.add_child(grid)
		grid.add_child(UI.label("", 15))
		for k in ["attack", "decay", "sustain", "release", "gate", "smooth"]:
			grid.add_child(UI.label(k, 15, UI.DIM))
		grid.add_child(UI.label("level", 15, UI.DIM))
		for band in ["bass", "mid", "high"]:
			grid.add_child(UI.label(band, 18))
			for k in ["attack", "decay", "sustain", "release", "gate", "smooth"]:
				var sl := HSlider.new()
				var r: Array = BandShaper.RANGES[k]
				sl.min_value = r[0]
				sl.max_value = r[1]
				sl.step = (r[1] - r[0]) / 100.0
				sl.custom_minimum_size = Vector2(120, 26)
				sl.value_changed.connect(func(v: float): AudioReact.set_shape(band, k, v))
				grid.add_child(sl)
				_audio_widgets[band + "." + k] = sl
			var meter := ProgressBar.new()
			meter.min_value = 0.0
			meter.max_value = 1.0
			meter.show_percentage = false
			meter.custom_minimum_size = Vector2(90, 22)
			grid.add_child(meter)
			_audio_widgets[band + ".meter"] = meter
		var brow := HBoxContainer.new()
		brow.add_theme_constant_override("separation", 10)
		var bpm_l := UI.label("", 18, UI.ACCENT)
		bpm_l.custom_minimum_size.x = 300
		brow.add_child(bpm_l)
		_audio_widgets["bpm"] = bpm_l
		brow.add_child(UI.button("Set clock from audio", clock_from_audio, 190))
		var fol := CheckButton.new()
		fol.text = "clock follows the audio"
		fol.toggled.connect(func(on: bool):
			AudioReact.set_follow_clock(on)
			_update_hud())
		brow.add_child(fol)
		_audio_widgets["follow"] = fol
		brow.add_child(UI.button("Reset shapes", func():
			AudioReact.reset_shape()
			_refresh_audio_panel(), 130))
		brow.add_child(UI.button("Close (Ctrl+A)", toggle_audio_panel, 140))
		col.add_child(brow)
		add_child(_audio_panel)
	else:
		_audio_panel.visible = not _audio_panel.visible
	if _audio_panel.visible:
		move_child(_audio_panel, -1)
		_refresh_audio_panel()


func _refresh_audio_panel() -> void:
	if _audio_panel == null or not _audio_panel.visible:
		return
	for band in ["bass", "mid", "high"]:
		var sh: BandShaper = AudioReact.shapers[band]
		for k in ["attack", "decay", "sustain", "release", "gate", "smooth"]:
			_audio_widgets[band + "." + k].set_value_no_signal(float(sh.get(k)))
		_audio_widgets[band + ".meter"].value = float(AudioReact.get(band))
	_audio_widgets["follow"].set_pressed_no_signal(AudioReact.follow_clock)
	_audio_widgets["bpm"].text = ("tracked: %.1f bpm  (confidence %.2f)" % [AudioReact.bpm(), AudioReact.bpm_confidence()]) if AudioReact.bpm() > 0.0 else "tracked: — (needs a few beats)"


# ---------------- clip format (the export's crop) ----------------
func set_clip_format(fmt: String, persist := true) -> void:
	if not ClipExport.FORMATS.has(fmt):
		fmt = "16:9"
	if persist:
		Settings.set_value("clip_format", fmt)
	_guide.crop = ClipExport.crop(fmt)
	_guide.visible = _guide.crop != WORLD
	_guide.queue_redraw()
	if persist:
		_steal_note = "clip format %s%s" % [fmt, "" if _guide.visible else " (the whole picture)"]
		_update_hud()


func clip_format() -> String:
	return str(Settings.get_value("clip_format"))


# ---------------- feedback routing ----------------
func set_fb_delay(n: int) -> void:
	fb_delay = clampi(n, 0, RING - 1)
	_refresh_routing_panel()
	_update_hud()


func set_loop(layer: int, on: bool) -> void:
	if layer < 0 or layer >= _layers.size():
		return
	_layers[layer]["loop"] = on
	_apply_layers()
	_refresh_routing_panel()
	_update_hud()


func loop_mask() -> int:
	var m := 0
	for i in _layers.size():
		if bool(_layers[i].get("loop", true)):
			m |= 1 << i
	return m


func set_cleanup_rule(i: int) -> void:
	fb_cleanup_rule = posmod(i, CLEANUP_RULES.size())
	_refresh_routing_panel()
	_update_hud()


func set_disp_source(i: int) -> void:
	fb_disp_src = posmod(i, DISP_SOURCES.size())
	_refresh_routing_panel()
	_update_hud()


## The texture the loop is displaced by, or null.
func _disp_texture() -> Texture2D:
	match fb_disp_src:
		1: return _worldmix.get_texture()
		2: return _layers[1]["vp"].get_texture()
		3: return _layers[2]["vp"].get_texture()
		4: return _webcam._sprite.texture if _webcam and _webcam._sprite else null
	return null


func routing_describe() -> String:
	var parts: Array = []
	if fb_delay > 0:
		parts.append("delay %d" % fb_delay)
	if absf(fb_blur) > 0.001:
		parts.append(("blur %.2f" % fb_blur) if fb_blur > 0.0 else ("sharpen %.2f" % -fb_blur))
	if absf(fb_hue) > 0.0001:
		parts.append("hue %+.3f" % fb_hue)
	if absf(fb_sat - 1.0) > 0.001:
		parts.append("sat %.2f" % fb_sat)
	if fb_cleanup > 0.001:
		parts.append("cleanup %.2f %s" % [fb_cleanup, CLEANUP_RULES[fb_cleanup_rule]])
	if fb_disp_src > 0 and fb_displace > 0.0:
		parts.append("displace %.2f by %s" % [fb_displace, DISP_SOURCES[fb_disp_src]])
	if loop_mask() != 7:
		var names: Array = []
		for i in _layers.size():
			if bool(_layers[i].get("loop", true)):
				names.append(str(i + 1))
		parts.append("loop: layers " + (", ".join(names) if not names.is_empty() else "none"))
	return " · ".join(parts)


func toggle_routing_panel() -> void:
	if _routing_panel == null:
		_routing_panel = PanelContainer.new()
		_routing_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_routing_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_routing_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		_routing_panel.add_child(col)
		col.add_child(UI.label("Feedback routing", 26, UI.ACCENT))
		col.add_child(UI.label("Which layers re-enter the loop, how many frames back the loop reads, and what happens to the picture on every pass.", 15, UI.DIM))
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 14)
		lrow.add_child(UI.label("In the loop:", 18))
		for i in LAYER_COUNT:
			var cb := CheckButton.new()
			cb.text = "layer %d" % (i + 1)
			cb.toggled.connect(func(on: bool): set_loop(i, on))
			lrow.add_child(cb)
			_routing_widgets["loop%d" % i] = cb
		col.add_child(lrow)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 6)
		col.add_child(grid)
		for spec in [["delay", "frame delay", 0.0, float(RING - 1), 1.0, func(v: float): set_fb_delay(int(v))],
				["blur", "sharpen ← → blur", -1.0, 1.0, 0.05, func(v: float):
					fb_blur = v
					_update_hud()],
				["hue", "hue drift per pass", -0.1, 0.1, 0.005, func(v: float):
					fb_hue = v
					_update_hud()],
				["sat", "saturation per pass", 0.9, 1.1, 0.005, func(v: float):
					fb_sat = v
					_update_hud()],
				["displace", "displacement", 0.0, 1.0, 0.05, func(v: float):
					fb_displace = v
					_update_hud()],
				["cleanup", "cellular cleanup", 0.0, 1.0, 0.05, func(v: float):
					fb_cleanup = v
					_update_hud()]]:
			grid.add_child(UI.label(spec[1], 17))
			var sl := HSlider.new()
			sl.min_value = spec[2]
			sl.max_value = spec[3]
			sl.step = spec[4]
			sl.custom_minimum_size = Vector2(300, 30)
			sl.value_changed.connect(spec[5])
			grid.add_child(sl)
			var vl := UI.label("", 15, UI.DIM)
			vl.custom_minimum_size.x = 80
			grid.add_child(vl)
			_routing_widgets[spec[0]] = sl
			_routing_widgets[spec[0] + "_lbl"] = vl
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 8)
		srow.add_child(UI.label("Cleanup rule:", 17))
		var rb := OptionButton.new()
		for n in CLEANUP_RULES:
			rb.add_item(n)
		rb.item_selected.connect(set_cleanup_rule)
		srow.add_child(rb)
		_routing_widgets["rule"] = rb
		srow.add_child(UI.hspace(8))
		srow.add_child(UI.label("Displace by:", 17))
		var ob := OptionButton.new()
		for n in DISP_SOURCES:
			ob.add_item(n)
		ob.item_selected.connect(set_disp_source)
		srow.add_child(ob)
		_routing_widgets["src"] = ob
		srow.add_child(UI.hspace(12))
		srow.add_child(UI.button("Reset", func():
			set_fb_delay(0)
			fb_blur = 0.0
			fb_hue = 0.0
			fb_sat = 1.0
			fb_displace = 0.0
			fb_cleanup = 0.0
			set_cleanup_rule(0)
			set_disp_source(0)
			for i in LAYER_COUNT:
				_layers[i]["loop"] = true
			_apply_layers()
			_refresh_routing_panel()
			_update_hud(), 100))
		srow.add_child(UI.button("Close (Ctrl+F)", toggle_routing_panel, 150))
		col.add_child(srow)
		add_child(_routing_panel)
	else:
		_routing_panel.visible = not _routing_panel.visible
	if _routing_panel.visible:
		move_child(_routing_panel, -1)
		_refresh_routing_panel()


func _refresh_routing_panel() -> void:
	if _routing_panel == null or not _routing_panel.visible:
		return
	for i in LAYER_COUNT:
		_routing_widgets["loop%d" % i].set_pressed_no_signal(bool(_layers[i].get("loop", true)))
	var vals := {"delay": float(fb_delay), "blur": fb_blur, "hue": fb_hue, "sat": fb_sat, "displace": fb_displace, "cleanup": fb_cleanup}
	for k in vals:
		_routing_widgets[k].set_value_no_signal(vals[k])
		_routing_widgets[k + "_lbl"].text = ("%d" % int(vals[k])) if k == "delay" else ("%.3f" % vals[k])
	_routing_widgets["src"].selected = fb_disp_src
	_routing_widgets["rule"].selected = fb_cleanup_rule


var _prof := {}


# ---------------- autosave / live state ----------------
## The snapshot plus what is on stage, for a crash restore.
func live_state() -> Dictionary:
	var st := snapshot()
	var actors: Array = []
	for i in _layers.size():
		for a in _layers[i]["actors"].get_children():
			if not a._dying:
				actors.append({"slot": a.slot_id, "layer": i, "x": a.position.x, "y": a.position.y})
	var solids: Array = []
	for sol in _solids.get_children():
		solids.append({"slot": sol.slot_id, "shape": sol.shape, "x": sol.position.x, "y": sol.position.y, "z": sol.position.z})
	st["live"] = {"actors": actors, "solids": solids}
	return st


## Put a live state back: the snapshot, then the actors and solids.
func restore_live(st: Dictionary) -> int:
	if st.is_empty():
		return 0
	restore(st, 0.0)
	return restore_contents(st)


## Only the things on stage (undo keeps the look you dialled in afterwards).
func restore_contents(st: Dictionary) -> int:
	_history.muted += 1
	var n := _restore_contents(st)
	_history.muted -= 1
	return n


func _restore_contents(st: Dictionary) -> int:
	clear_actors()
	for sol in _solids.get_children():
		sol.queue_free()
	var live: Dictionary = st.get("live", {})
	var n := 0
	for a in live.get("actors", []):
		var idx := Toolbox.index_of(str(a.get("slot", "")))
		if idx >= 0:
			spawn_slot_at(idx, int(a.get("layer", 0)), Vector2(float(a.get("x", 960)), float(a.get("y", 540))))
			n += 1
	for sd in live.get("solids", []):
		var idx := Toolbox.index_of(str(sd.get("slot", "")))
		if idx >= 0:
			var keep := Toolbox.selected
			Toolbox.select(idx)
			var shape_i: int = SolidScript.SHAPES.find(str(sd.get("shape", "cube")))
			_shape_index = maxi(shape_i, 0)
			spawn_solid(_camera.unproject_position(Vector3(float(sd.get("x", 0)), float(sd.get("y", 0)), float(sd.get("z", 0)))))
			Toolbox.select(keep)
			n += 1
	_steal_note = "restored %d things from the autosave" % n
	_update_hud()
	return n


func _tick_autosave(delta: float) -> void:
	_autosave_t += delta
	if _autosave_t >= autosave_interval:
		_autosave_t = 0.0
		Autosave.write(live_state())


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	MidiOut.tick()
	_tick_crossfade(_delta)
	_tick_credits(_delta)
	_tick_clock()
	_tick_autosave(_delta)
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
		m.set_shader_parameter("blur", fb_blur)
		m.set_shader_parameter("hue", fb_hue)
		m.set_shader_parameter("sat", fb_sat)
		m.set_shader_parameter("cleanup", fb_cleanup)
		m.set_shader_parameter("cleanup_rule", fb_cleanup_rule)
		var dt := _disp_texture() if fb_displace > 0.0 else null
		m.set_shader_parameter("disp_on", dt != null)
		m.set_shader_parameter("displace", fb_displace)
		if dt:
			m.set_shader_parameter("disp_tex", dt)
		if fb_delay > 0:
			# the history ring: this frame's head copies last frame's output; the loop reads N back
			_ring_head = (_ring_head + 1) % RING
			_ring_rects[_ring_head].texture = _acc[1 - cur].get_texture()
			_ring[_ring_head].render_target_update_mode = SubViewport.UPDATE_ONCE
			prev.texture = _ring[posmod(_ring_head - fb_delay, RING)].get_texture()
		else:
			prev.texture = _acc[1 - cur].get_texture()
		_acc[1 - cur].render_target_update_mode = SubViewport.UPDATE_DISABLED
		_acc[cur].render_target_update_mode = SubViewport.UPDATE_ONCE
		_screen.texture = _acc[cur].get_texture()
	if Engine.get_process_frames() % (4 if AudioReact.active() else 15) == 0:
		_update_hud()
		_refresh_audio_panel()


# ---------------- spawning ----------------
func _world_pos(local: Vector2) -> Vector2:
	return _m_input.world_pos(local)


func spawn_at(world_pos: Vector2) -> void:
	spawn_slot_at(Toolbox.selected, active_layer, world_pos)


## Spawn a given slot into a given layer (player 2 uses its own of each).
func spawn_slot_at(slot_index: int, layer_index: int, world_pos: Vector2) -> void:
	if slot_index < 0 or slot_index >= Toolbox.slots.size():
		return
	var slot: Dictionary = Toolbox.slots[slot_index]
	_history.push("spawn")
	if MidiOut.enabled:
		MidiOut.note_on(MidiOut.CH_SPAWN, MidiOut.note_for_slot(slot_index), MidiOut.velocity_for_height(world_pos.y, WORLD.y))
		MidiOut.event("spawn", [slot_index + 1, world_pos.x / WORLD.x, world_pos.y / WORLD.y])
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


func _physics_actor_at(world_pos: Vector2) -> Node2D:
	return _m_input.physics_actor_at(world_pos)


## Every beat (audio, test groove or clock) is a kick on channel 10 for the bridge.
func _on_beat_out() -> void:
	if MidiOut.enabled:
		MidiOut.note_on(MidiOut.CH_BEAT, 36, 100, 0.05)
		MidiOut.event("beat", [Clock.beat_index if Clock.running else -1])


func set_osc_out(on: bool) -> void:
	Settings.set_value("osc_out", on)
	MidiOut.configure(str(Settings.get_value("osc_out_host")), int(Settings.get_value("osc_out_port")), on)
	_steal_note = "OSC out %s" % (("→ %s:%d" % [MidiOut.host, MidiOut.port]) if on else "off")
	_update_hud()


func set_gravity(g: float) -> void:
	gravity = clampf(g, 0.0, 2.0)
	IconBody.gravity = gravity
	_steal_note = "gravity %s" % ("off — Physics icons float" if gravity == 0.0 else "%.1f" % gravity)
	_update_hud()


func play_slot_sound() -> bool:
	var cur := Toolbox.current()
	var ok := Sounds.play(str(cur.get("sound_path", "")))
	_steal_note = "sound: " + (str(cur.get("sound_path", "")).get_file() if ok else "none on slot %d — drop a .wav on it" % (Toolbox.selected + 1))
	_update_hud()
	return ok


func _remove_nearest(world_pos: Vector2) -> void:
	_m_input.remove_nearest(world_pos)


## Mouse and keyboard live in src/stage/input.gd (the keyboard is a table).
func _gui_input(ev: InputEvent) -> void:
	_m_input.mouse(ev)


func _unhandled_key_input(ev: InputEvent) -> void:
	_m_input.key(ev)
