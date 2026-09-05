extends Control
## Play mode. The world renders into a SubViewport; two more viewports ping-pong
## the previous frame back in (zoomed, rotated, faded) for classic video
## feedback — the "camera pointed at its own monitor" effect.
##
## Keys: 1-9 slot · Q W E R T Y U I verbs · click spawn · right-click remove
## · Space random spawn · P palette · F feedback · [ ] zoom · , . rotate
## · - = fade · O kaleidoscope · G chroma key (drop an image for the backdrop)
## · K pixelate · L palette quantise · J dither · V CRT · C clear · H help · Esc menu

signal navigate(name: String)

const HotbarScript = preload("res://src/hotbar.gd")
const ActorScript = preload("res://src/actor.gd")
const FxScript = preload("res://src/fx.gd")
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
var _hud: Label
var _help: PanelContainer
var _verb_panel: VBoxContainer
var _verb_checks := {}
var _fx_pixel_btn: Button
var _fx_kaleido_btn: Button
var _fx_crt_btn: Button
var _fx_chroma: CheckButton
var _fx_quant: CheckButton
var _fx_dither: CheckButton
var _hotbar
var _fx


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Background lives on the screen, not in the world, so the world texture is
	# transparent except for actors — that is what lets feedback trails decay.
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.color = Palettes.bg(palette_index)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_world = SubViewport.new()
	_world.size = WORLD
	_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_world.transparent_bg = true
	_world.disable_3d = true
	add_child(_world)
	_actors = Node2D.new()
	_world.add_child(_actors)

	for i in 2:
		var vp := SubViewport.new()
		vp.size = WORLD
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.transparent_bg = true
		add_child(vp)
		var prev := Sprite2D.new()
		prev.position = Vector2(WORLD) * 0.5
		vp.add_child(prev)
		var live := Sprite2D.new()
		live.position = Vector2(WORLD) * 0.5
		live.texture = _world.get_texture()
		vp.add_child(live)
		_acc.append(vp)
		_acc_prev.append(prev)
		_acc_live.append(live)
	_acc_prev[0].texture = _acc[1].get_texture()
	_acc_prev[1].texture = _acc[0].get_texture()

	_screen = TextureRect.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_screen.texture = _world.get_texture()
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)

	_fx = FxScript.new()
	add_child(_fx)

	_build_hud()
	Toolbox.selection_changed.connect(func(_i): _refresh_verbs())
	Toolbox.changed.connect(_refresh_verbs)
	_refresh_verbs()
	_apply_palette()
	_refresh_fx()
	get_window().files_dropped.connect(_on_files_dropped)


func _exit_tree() -> void:
	if get_window() and get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)


# ---------------- HUD ----------------
func _build_hud() -> void:
	var hud_card := PanelContainer.new()
	hud_card.position = Vector2(12, 8)
	add_child(hud_card)
	_hud = UI.label("", 18, UI.DIM)
	hud_card.add_child(_hud)

	# Verb panel sits on a translucent card so it reads on light palettes too.
	var card := PanelContainer.new()
	card.position = Vector2(12, 56)
	add_child(card)
	_verb_panel = VBoxContainer.new()
	_verb_panel.add_theme_constant_override("separation", 2)
	card.add_child(_verb_panel)
	_verb_panel.add_child(UI.label("Verbs for selected slot", 18, UI.ACCENT))
	for v in Verbs.ALL:
		var cb := CheckButton.new()
		cb.text = "%s  %s" % [v["key"], v["name"]]
		cb.tooltip_text = v["hint"]
		cb.toggled.connect(func(_on): Toolbox.toggle_verb(Toolbox.selected, v["id"]))
		_verb_panel.add_child(cb)
		_verb_checks[v["id"]] = cb
	_verb_panel.add_child(UI.vspace(6))
	_verb_panel.add_child(UI.label("Effects", 18, UI.ACCENT))
	_fx_kaleido_btn = UI.button("", func():
		_fx.cycle_kaleido()
		_refresh_fx())
	_verb_panel.add_child(_fx_kaleido_btn)
	_fx_chroma = CheckButton.new()
	_fx_chroma.text = "G  Chroma key"
	_fx_chroma.tooltip_text = "Keys out the palette background. Drop an image on the window for the backdrop; plasma otherwise."
	_fx_chroma.toggled.connect(func(_on):
		_fx.toggle_chroma()
		_refresh_fx())
	_verb_panel.add_child(_fx_chroma)
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
		+ "G            chroma key (drop image = backdrop)\nK            pixelate size\n"
		+ "L            palette quantise\nJ            dither\nV            CRT off/soft/heavy\n"
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
	_fx_chroma.set_pressed_no_signal(_fx.chroma)
	_fx_crt_btn.text = "V  CRT: %s" % ["off", "soft", "heavy"][_fx.crt_level]
	_fx_pixel_btn.text = "K  Pixelate: %s" % ("off" if _fx.pixel_step == 0 else "%d px" % _fx.pixel_size())
	_fx_quant.set_pressed_no_signal(_fx.quantize)
	_fx_dither.set_pressed_no_signal(_fx.dither)
	_fx_dither.disabled = not _fx.quantize
	_update_hud()


## Used by --capture.
func set_fx(pixel: int, quant: bool, dith: bool, kaleido := 0, chroma := false, crt := 0) -> void:
	_fx.set_state(pixel, quant, dith, kaleido, chroma, crt)
	_refresh_fx()


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp"]:
			if _fx.set_backdrop_from_file(f):
				if not _fx.chroma:
					_fx.toggle_chroma()
				_refresh_fx()
			return


func _update_hud() -> void:
	var cur := Toolbox.current()
	var name := str(cur.get("term", "—")) if not cur.is_empty() else "empty toolbox — press Find Icons"
	_hud.text = "slot %d: %s   ·   palette: %s   ·   feedback: %s   ·   fx: %s   ·   actors: %d" % [
		Toolbox.selected + 1, name, Palettes.get_palette(palette_index)["name"],
		("zoom %.2f  twist %.2f  fade %.2f" % [fb_zoom, fb_rot, fb_fade]) if feedback else "off",
		_fx.describe(), _actors.get_child_count()]


# ---------------- palette / feedback ----------------
func _apply_palette() -> void:
	_bg.color = Palettes.bg(palette_index)
	_fx.set_palette(palette_index)
	_hotbar.palette_index = palette_index
	_hotbar.refresh()
	for a in _actors.get_children():
		var i := Toolbox.index_of(a.slot_id)
		if i >= 0:
			a.set_palette(palette_index, int(Toolbox.slots[i].get("color_index", i)))
	_update_hud()


func _recolor() -> void:
	Toolbox.cycle_color(Toolbox.selected)
	_apply_palette()


func _set_feedback(on: bool) -> void:
	feedback = on
	if not on:
		_screen.texture = _world.get_texture()
		for vp in _acc:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_update_hud()


func _process(_delta: float) -> void:
	var mouse := _world_pos(get_local_mouse_position())
	for a in _actors.get_children():
		a.mouse_world = mouse
	if feedback:
		var cur: int = _flip
		_flip = 1 - _flip
		var prev: Sprite2D = _acc_prev[cur]
		prev.scale = Vector2.ONE * fb_zoom
		prev.rotation = fb_rot
		prev.modulate = Color(1, 1, 1, fb_fade)
		_acc[1 - cur].render_target_update_mode = SubViewport.UPDATE_DISABLED
		_acc[cur].render_target_update_mode = SubViewport.UPDATE_ONCE
		_screen.texture = _acc[cur].get_texture()
	if Engine.get_process_frames() % 15 == 0:
		_update_hud()


# ---------------- spawning ----------------
func _world_pos(local: Vector2) -> Vector2:
	# Map the on-screen rect (keep-aspect centred) back to world pixels.
	var rect := _screen.get_rect()
	var scale := minf(rect.size.x / WORLD.x, rect.size.y / WORLD.y)
	var drawn := Vector2(WORLD) * scale
	var origin := rect.position + (rect.size - drawn) * 0.5
	return (local - origin) / scale


func spawn_at(world_pos: Vector2) -> void:
	var slot := Toolbox.current()
	if slot.is_empty():
		return
	var a := Node2D.new()
	a.set_script(ActorScript)
	a.setup(slot, world_pos, palette_index, Rect2(Vector2.ZERO, Vector2(WORLD)))
	_actors.add_child(a)
	_update_hud()


func demo_spawn() -> void:
	## Used by --capture: a few actors with verbs on, so the screenshot shows something.
	if Toolbox.slots.is_empty():
		return
	for i in 12:
		Toolbox.select(i % Toolbox.slots.size())
		spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))


func _remove_nearest(world_pos: Vector2) -> void:
	var best: Node2D = null
	var best_d := 1e9
	for a in _actors.get_children():
		var d: float = a.position.distance_to(world_pos)
		if d < best_d:
			best_d = d
			best = a
	if best and best_d < 160.0:
		best.queue_free()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		var wp := _world_pos(ev.position)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			spawn_at(wp)
		elif ev.button_index == MOUSE_BUTTON_RIGHT:
			_remove_nearest(wp)


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed):
		return
	var k: int = ev.keycode
	if k >= KEY_1 and k <= KEY_9:
		Toolbox.select(k - KEY_1)
		return
	var verb := Verbs.by_key(k)
	if verb != "" and not Toolbox.current().is_empty():
		Toolbox.toggle_verb(Toolbox.selected, verb)
		return
	match k:
		KEY_SPACE: spawn_at(Vector2(randf_range(100, WORLD.x - 100), randf_range(100, WORLD.y - 100)))
		KEY_P:
			palette_index = (palette_index + 1) % Palettes.count()
			_apply_palette()
		KEY_X: _recolor()
		KEY_DELETE, KEY_BACKSPACE: Toolbox.remove(Toolbox.selected)
		KEY_F: _set_feedback(not feedback)
		KEY_BRACKETLEFT: fb_zoom = maxf(0.90, fb_zoom - 0.01)
		KEY_BRACKETRIGHT: fb_zoom = minf(1.20, fb_zoom + 0.01)
		KEY_COMMA: fb_rot -= 0.01
		KEY_PERIOD: fb_rot += 0.01
		KEY_V:
			_fx.cycle_crt()
			_refresh_fx()
		KEY_O:
			_fx.cycle_kaleido()
			_refresh_fx()
		KEY_G:
			_fx.toggle_chroma()
			_refresh_fx()
		KEY_K:
			_fx.cycle_pixelate()
			_refresh_fx()
		KEY_L:
			_fx.toggle_quantize()
			_refresh_fx()
		KEY_J:
			_fx.toggle_dither()
			_refresh_fx()
		KEY_MINUS: fb_fade = maxf(0.5, fb_fade - 0.02)
		KEY_EQUAL: fb_fade = minf(0.995, fb_fade + 0.02)
		KEY_C:
			for a in _actors.get_children():
				a.queue_free()
		KEY_H:
			_help.visible = not _help.visible
			_verb_panel.get_parent().visible = _help.visible
			_hud.get_parent().visible = _help.visible
	_update_hud()
