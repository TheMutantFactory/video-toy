extends Node
## Screen router. Each screen is a full-rect Control built in code that emits
## `navigate(name)`; the router swaps it out. `--capture DIR` (after `--` on the
## command line) screenshots every screen into DIR and quits — used for proof.

const SCREENS := {
	"start": "res://src/start_screen.gd",
	"search": "res://src/search_screen.gd",
	"stage": "res://src/stage_screen.gd",
	"settings": "res://src/settings_screen.gd",
	"scenes": "res://src/scenes_screen.gd",
}
const MenuOverlay = preload("res://src/menu_overlay.gd")

var current: Control
var current_name := ""
var menu: CanvasLayer


var args := PackedStringArray()
var _cleanup_birthday: Array = []


var restore_offer := {}                      # {age, state} when the last run did not exit cleanly
var crashed := false                         # the running flag was still there at launch


func _ready() -> void:
	get_window().title = "Video Toy"
	restore_offer = {}
	crashed = Autosave.crashed_last_time()
	if crashed and not Autosave.read().is_empty():
		restore_offer = {"age": Autosave.age_seconds(), "state": Autosave.read()}
	Autosave.mark_running()
	get_tree().auto_accept_quit = false
	menu = MenuOverlay.new()
	menu.navigate.connect(show_screen)
	add_child(menu)
	args = OS.get_cmdline_user_args()
	for harness in ["--selftest", "--capture", "--templates", "--keycard", "--clip", "--safecheck"]:
		if args.has(harness):
			Tour.suppress = true                     # the first-run captions never land in a test or a shot
	var cap := args.find("--capture")
	var ti := args.find("--templates")
	var ki := args.find("--keycard")
	if args.has("--safecheck"):
		print("SAFECHECK active=%s midi_inputs=%d osc_listening=%s mic=%s webcam=%s log=%s" % [Safe.active(), MidiMap.inputs().size(), Osc.listening, AudioReact.mic_available(), "off" if Safe.active() else "on", FileAccess.file_exists(CrashLog.current())])
		quit_clean()
		return
	var ci := args.find("--clip")
	if ci >= 0 and ci + 1 < args.size():
		_clip(float(args[ci + 1]))
	elif ti >= 0 and ti + 1 < args.size():
		_templates(args[ti + 1])
	elif ki >= 0 and ki + 1 < args.size():
		_keycard(args[ki + 1])
	elif args.has("--selftest"):
		_selftest()
	elif cap >= 0 and cap + 1 < args.size():
		_capture_all(args[cap + 1])
	else:
		show_screen("start")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_clean()


func quit_clean() -> void:
	if current_name == "stage" and current:
		Autosave.write(current.live_state())
	Autosave.mark_clean_exit()
	get_tree().quit()


## Restore the autosave onto a fresh stage (the start screen's offer).
func restore_autosave() -> void:
	var st: Dictionary = restore_offer.get("state", Autosave.read())
	restore_offer = {}
	show_screen("stage")
	await get_tree().process_frame
	current.restore_live(st)


## Render the current state to a movie in a child Godot process: Movie Maker
## needs --write-movie at launch, so the child restores this run's autosave.
func render_clip(seconds := 20.0) -> String:
	if current_name == "stage" and current:
		Autosave.write(current.live_state())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://clips"))
	var t := Time.get_datetime_dict_from_system()
	var out := ProjectSettings.globalize_path("user://clips/clip-%04d%02d%02d-%02d%02d%02d.avi" % [t.year, t.month, t.day, t.hour, t.minute, t.second])
	var argv := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--write-movie", out, "--fixed-fps", "60", "--", "--clip", str(seconds)])
	var pid := OS.create_process(OS.get_executable_path(), argv)
	if current_name == "stage" and current:
		current._steal_note = ("rendering %.0f s to %s (pid %d)" % [seconds, out.get_file(), pid]) if pid > 0 else "could not start the render"
		current._update_hud()
	return out if pid > 0 else ""


## Movie Maker mode: restore the autosave, hide the HUD, run `seconds`, quit.
func _clip(seconds: float) -> void:
	show_screen("stage")
	await get_tree().process_frame
	var st := Autosave.read()
	if not st.is_empty():
		current.restore_live(st)
	current._help.close()
	current.set_hud_mode(2)
	if current.timeline.load():
		current.toggle_play()
	await get_tree().create_timer(seconds).timeout
	Autosave.mark_clean_exit()
	get_tree().quit()


func show_screen(name: String) -> void:
	if name == "quit":
		quit_clean()
		return
	if name == "attribution":
		menu.show_attribution()
		return
	if name in ["help", "undo", "surprise", "guest", "tour"]:
		if current_name != "stage":
			show_screen("stage")
		match name:
			"help": current.open_help()
			"undo": current.undo()
			"surprise": current.surprise()
			"guest": current.set_guest(not current.guest)
			"tour": current.start_tour()
		return
	if name == "panic" or name == "blackout":
		if current_name != "stage":
			show_screen("stage")
		if name == "panic":
			current.panic()
		else:
			current.toggle_blackout()
		return
	if not SCREENS.has(name):
		push_warning("Unknown screen: " + name)
		return
	if current:
		current.queue_free()
	current = Control.new()
	current.name = name.capitalize()
	current.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	current.theme = UI.theme()
	current.set_script(load(SCREENS[name]))
	current.navigate.connect(show_screen)
	add_child(current)
	current_name = name


## Write the controller templates from the live tables into `dir`, then quit.
func _templates(dir: String) -> void:
	show_screen("stage")
	await get_tree().process_frame
	var files: Array = Templates.write_all(current.midi_params(), current.midi_actions(), dir)
	print("TEMPLATES ", dir, ": ", ", ".join(files), "  (%d params, %d actions)" % [current.midi_params().size(), current.midi_actions().size()])
	get_tree().quit()


## Windowed: render docs/key-card.png and write docs/KEYS.md from Keys, then quit.
func _keycard(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var img: Image = await KeyCard.render(self)
	img.save_png(dir.path_join("key-card.png"))
	var f := FileAccess.open(dir.path_join("KEYS.md"), FileAccess.WRITE)
	f.store_string(Keys.markdown())
	f.close()
	var rows := 0
	for g in Keys.groups():
		rows += g["rows"].size()
	print("KEYCARD ", dir, ": key-card.png %dx%d, KEYS.md (%d groups, %d rows)" % [img.get_width(), img.get_height(), Keys.groups().size(), rows])
	quit_clean()


## Headless-safe: instantiate every screen and the menu, then quit. Fails loudly
## (non-zero exit) if any screen errors while building itself.
func _selftest() -> void:
	var fails := 0
	if Toolbox.slots.is_empty():                        # a fresh machine (CI): the five demo shapes
		DemoPack.load_into(Toolbox, Ledger)
	for name in SCREENS.keys():
		show_screen(name)
		await get_tree().process_frame
		if current == null or current.get_child_count() == 0:
			fails += 1
			printerr("FAIL screen did not build: ", name)
		else:
			print("PASS screen builds: ", name)
	menu.show_attribution()
	await get_tree().process_frame
	print("PASS attribution overlay opens (%d entries)" % Ledger.count())
	menu.close()
	# presets: snapshot -> change -> restore round-trips through the real stage
	show_screen("stage")
	await get_tree().process_frame
	var st = current
	st.palette_index = 2
	st.fb_zoom = 1.11
	st._fx.crt_level = 2
	st._glow.set_level(1)
	var snap: Dictionary = st.snapshot()
	st.palette_index = 0
	st.fb_zoom = 1.0
	st._fx.crt_level = 0
	st._glow.set_level(0)
	st.restore(snap, 0.0)
	var ok_preset: bool = st.palette_index == 2 and is_equal_approx(st.fb_zoom, 1.11) and st._fx.crt_level == 2 and st._glow.level == 1
	# scenes: every shader compiles into a material, switching crossfades, knobs apply
	var ok_scenes := true
	for sid in Scenes.ids():
		var m := Scenes.material_for(sid, 0)
		if m.shader == null:
			ok_scenes = false
			printerr("FAIL scene shader: ", sid)
	st.set_scene("truchet", 0.0)
	st.set_scene_knobs(2.0, 1.5, 0.25)
	await get_tree().process_frame
	var snap2: Dictionary = st.snapshot()
	st.set_scene("", 0.0)
	st.restore(snap2, 0.0)
	ok_scenes = ok_scenes and Scenes.current == "truchet" and is_equal_approx(Scenes.speed, 2.0) and snap2["scene"]["id"] == "truchet"
	st.set_scene("", 0.0)
	# extrusion + formation on the real stage: a cookie solid and a lattice
	var ring_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dd := Vector2(x - 32, y - 32).length()
			ring_img.set_pixel(x, y, Color(1, 1, 1, 1.0 if (dd > 12 and dd < 28) else 0.0))
	var cookie := Extrude.build(ring_img, 1.4, 0.35, 32)
	var ok_3d: bool = cookie.get_surface_count() == 2 and cookie.surface_get_array_len(0) > 0 and cookie.surface_get_array_len(1) > 0
	Toolbox.select(0)
	st._formation_index = 1
	st.spawn_formation(64)
	await get_tree().process_frame
	ok_3d = ok_3d and st._formations.get_child_count() == 1 and st._formations.get_child(0)._mm.multimesh.instance_count == 64
	var Formation = load("res://src/formation.gd")
	for k in Formation.KINDS:
		var xf: Array = Formation.transforms(k, 50, 3.0)
		var seen := {}
		for tr in xf:
			seen[str(tr.origin.snapped(Vector3.ONE * 0.001))] = true
			if tr.origin.length() > 4.0:
				ok_3d = false
		if xf.size() != 50 or seen.size() < 45:
			ok_3d = false
			printerr("FAIL formation transforms: ", k)
	for f in st._formations.get_children():
		f.queue_free()
	if ok_3d:
		print("PASS extruded icon mesh and formation spawn")
	else:
		fails += 1
		printerr("FAIL extrusion / formation")
	# layers + draw on the real stage
	var ok_layers: bool = st._layers.size() == 3
	st.set_active_layer(1)
	Toolbox.select(0)
	st.spawn_at(Vector2(500, 500))
	ok_layers = ok_layers and st._layers[1]["actors"].get_child_count() == 1 and st._layers[0]["actors"].get_child_count() == 0
	st.cycle_blend()
	ok_layers = ok_layers and st._layers[1]["blend"] == 2 and int(st._layer_mix.material.get_shader_parameter("mode1")) == 2
	st.set_layer_opacity(0.5)
	ok_layers = ok_layers and is_equal_approx(float(st._layer_mix.material.get_shader_parameter("opacity1")), 0.5)
	st.set_active_layer(0)
	st.begin_stroke(Vector2(100, 100))
	for i in 40:
		st.extend_stroke(Vector2(100 + i * 20, 100 + (i % 2) * 30))
	var riders: int = st.end_stroke()
	ok_layers = ok_layers and riders >= 5 and st.all_rides().size() == 1 and st.all_actors().size() == 1 + riders
	st.begin_stroke(Vector2(300, 300))
	ok_layers = ok_layers and st.end_stroke() == 0 and st.all_actors().size() == 2 + riders    # a click spawns
	var snap3: Dictionary = st.snapshot()
	ok_layers = ok_layers and snap3["layers"][1]["blend"] == 2 and is_equal_approx(snap3["layers"][1]["opacity"], 0.5)
	st.clear_actors()
	# keyers and slit-scan: modes cycle, history atlas exists, preset round-trip
	var ok_fx: bool = st._fx.KEY_MODES.size() == 5 and st._fx.SLIT_MODES.size() == 4 and st._fx._hist.size() == 2
	st._fx.cycle_key()
	st._fx.cycle_key()
	st._fx.key_threshold = 0.6
	st._fx.cycle_slit()
	await get_tree().process_frame
	await get_tree().process_frame
	var snap4: Dictionary = st.snapshot()
	ok_fx = ok_fx and snap4["fx"]["key"] == 2 and snap4["fx"]["slit"] == 1 and is_equal_approx(float(snap4["fx"]["key_threshold"]), 0.6)
	st._fx.set_state(0, false, false)
	st.restore(snap4, 0.0)
	ok_fx = ok_fx and st._fx.key_mode == 2 and st._fx.slit_mode == 1 and st._fx.describe().contains("luma") and st._fx.describe().contains("slit rows")
	st.restore({"fx": {"chroma": true}}, 0.0)
	ok_fx = ok_fx and st._fx.key_mode == 1
	st._fx.set_state(0, false, false)
	if ok_fx:
		print("PASS keyers + slit-scan modes, history atlas, presets (old chroma key migrates)")
	else:
		fails += 1
		printerr("FAIL keyers / slit-scan")
	# mosaic, evolve, attract on the real stage
	var ok_modes := true
	st.clear_actors()
	Toolbox.select(0)
	var n_cells: int = st.spawn_mosaic()                 # the star icon out of stars
	await get_tree().process_frame
	ok_modes = ok_modes and n_cells > 50 and st.all_actors().size() == n_cells
	st.clear_actors()
	var before: Dictionary = st.snapshot()
	st.set_evolve(true)
	var changed := false
	for i in 6:
		st.evolve_step()
		if st.snapshot().hash() != before.hash():
			changed = true
	ok_modes = ok_modes and changed and st.evolve
	st.evolve_discard()
	st.set_evolve(false)
	ok_modes = ok_modes and not st.evolve
	st._idle = st.idle_attract + 1.0
	st._tick_modes(0.016)
	ok_modes = ok_modes and st.attract and st._monitor.visible
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_H
	st._input(key)
	ok_modes = ok_modes and not st.attract and st._idle == 0.0
	if ok_modes:
		print("PASS mosaic spawns cells, evolve mutates/keeps/discards, attract starts idle and ends on input")
	else:
		fails += 1
		printerr("FAIL mosaic / evolve / attract")
	# OSC: a real UDP packet into the listener drives a stage param and an action
	var ok_osc: bool = Osc.listening
	if ok_osc:
		var tx := PacketPeerUDP.new()
		tx.set_dest_address("127.0.0.1", Osc.port)
		if st._fade_tween:                                # an earlier restore() may still be crossfading
			st._fade_tween.kill()
		st.finish_crossfade()
		st.fb_zoom = 1.0
		tx.put_packet(Osc.build("/vt/param/fb_zoom", [0.5]))
		var solids_before: int = st._solids.get_child_count()
		Toolbox.select(0)
		tx.put_packet(Osc.build("/vt/action/spawn_solid"))
		for i in 6:
			await get_tree().process_frame
		ok_osc = is_equal_approx(st.fb_zoom, 1.05) and st._solids.get_child_count() == solids_before + 1 and Osc.received >= 2
		for sol in st._solids.get_children():
			sol.queue_free()
	if ok_osc:
		print("PASS OSC over UDP drives a param and an action on the stage")
	else:
		fails += 1
		printerr("FAIL OSC (listening=%s received=%d fb_zoom=%.3f)" % [Osc.listening, Osc.received, st.fb_zoom])
	# timeline: record two gestures through the control path, loop them back
	var ok_tl := true
	st.finish_crossfade()
	st.timeline = Timeline.new()
	st._clock = 100.0
	st.toggle_record()
	MidiMap.last_source = "midi"
	st._on_midi_param("fb_zoom", 0.0)                    # t=0   -> zoom 0.90
	st._clock = 100.5
	st._on_midi_param("fb_zoom", 1.0)                    # t=0.5 -> zoom 1.20
	st._clock = 101.0
	st.toggle_record()                                   # length 1.0
	ok_tl = ok_tl and st.timeline.events.size() == 2 and is_equal_approx(st.timeline.length, 1.0) and not st.timeline.recording
	st.fb_zoom = 1.0
	st.toggle_play()
	ok_tl = ok_tl and st.timeline.playing
	st._tick_timeline(0.3)                                # pos 0.3: event at 0 fired -> 0.90
	ok_tl = ok_tl and is_equal_approx(st.fb_zoom, 0.90)
	st._tick_timeline(0.4)                                # pos 0.7: event at 0.5 fired -> 1.20
	ok_tl = ok_tl and is_equal_approx(st.fb_zoom, 1.20)
	st._tick_timeline(0.5)                                # pos 0.2 (wrapped): event at 0 -> 0.90
	ok_tl = ok_tl and is_equal_approx(st.fb_zoom, 0.90)
	st.toggle_play()
	ok_tl = ok_tl and not st.timeline.playing and FileAccess.file_exists(Timeline.PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Timeline.PATH))
	if ok_tl:
		print("PASS timeline records controller gestures and loops them back with wrap")
	else:
		fails += 1
		printerr("FAIL timeline")
	# particle field + reaction-diffusion: build, toggle, presets, round-trip
	var ok_pf: bool = st._particles != null and st._pmat.shader != null and st._rd.size() == 2
	st.set_particles(true)
	st._push_particles()
	ok_pf = ok_pf and st.particles_on and st._particles.emitting
	st.set_rd_preset(2)
	st._tick_rd()
	st._tick_rd()
	ok_pf = ok_pf and st.rd_describe().begins_with("mitosis") and bool(st._layer_mix.material.get_shader_parameter("rd_on"))
	var snap5: Dictionary = st.snapshot()
	st.set_particles(false)
	st.set_rd_preset(0)
	st.restore(snap5, 0.0)
	ok_pf = ok_pf and st.particles_on and st.rd_preset == 2
	st.set_particles(false)
	st.set_rd_preset(0)
	if ok_pf:
		print("PASS particle field and reaction-diffusion build, toggle and round-trip")
	else:
		fails += 1
		printerr("FAIL particles / rd")
	# player 2: wakes on keypad, spawns own slot into own layer, hotbar ring, sleeps
	var ok_p2 := true
	st.clear_actors()
	st.p2_slot = 2
	st.p2_layer = 1
	var kp := InputEventKey.new()
	kp.pressed = true
	kp.keycode = KEY_KP_5
	st._unhandled_key_input(kp)
	await get_tree().process_frame
	ok_p2 = ok_p2 and st.p2_active and st._layers[1]["actors"].get_child_count() == 1 \
		and st._layers[1]["actors"].get_child(0).slot_id == Toolbox.slots[2]["id"] and st._hotbar.second_selected == 2
	st.p2_move(Vector2(-5000, 0))
	ok_p2 = ok_p2 and st.p2_cursor.x == 0.0
	kp.keycode = KEY_KP_ADD
	st._unhandled_key_input(kp)
	ok_p2 = ok_p2 and st.p2_slot == 3
	var pb := InputEventJoypadButton.new()
	pb.pressed = true
	pb.button_index = JOY_BUTTON_Y
	st._input(pb)
	ok_p2 = ok_p2 and st.p2_layer == 2
	st.p2_sleep()
	ok_p2 = ok_p2 and not st.p2_active and st._hotbar.second_selected == -1
	st.clear_actors()
	if ok_p2:
		print("PASS player 2 wakes, spawns into its layer, cycles slot and layer, sleeps")
	else:
		fails += 1
		printerr("FAIL player 2")
	# quality ladder applies, panic resets, blackout fades
	var ok_q := true
	st.set_particles(true)
	st.apply_quality(3)
	ok_q = ok_q and st._particles.amount == 1500 and st._fx.slit_stride == 6 and st._world3d.msaa_3d == Viewport.MSAA_DISABLED
	st.apply_quality(0)
	ok_q = ok_q and st._particles.amount == 12000 and st._fx.slit_stride == 2 and st._world3d.msaa_3d == Viewport.MSAA_2X
	st.quality.locked = 2
	st.cycle_quality_lock()
	ok_q = ok_q and st.quality.locked == 3 and st._quality_applied == 3
	st.cycle_quality_lock()
	ok_q = ok_q and st.quality.locked == -1
	st._set_feedback(true)
	st.set_rd_preset(1)
	st.set_scene("plasma", 0.0)
	st._fx.set_state(12, true, true, 6, false, 2)
	st.set_evolve(true)
	st.panic()
	ok_q = ok_q and not st.feedback and st.rd_preset == 0 and Scenes.current == "" and not st._fx.is_active() \
		and st._glow.level == 1 and not st.particles_on and not st.evolve and Toolbox.slots.size() > 0
	st.toggle_blackout()
	ok_q = ok_q and st.blackout and st._blackout.visible
	st.toggle_blackout()
	await get_tree().create_timer(0.6).timeout
	ok_q = ok_q and not st.blackout and not st._blackout.visible
	if ok_q:
		print("PASS quality ladder applies, lock cycles, panic resets, blackout fades")
	else:
		fails += 1
		printerr("FAIL quality / panic / blackout")
	# banks + crossfade: continuous lerps, discrete flips at the midpoint, lands exactly
	var ok_xf := true
	var pp := "user://_selftest_banks.json"
	var a: Dictionary = st.snapshot()
	a["feedback"]["zoom"] = 1.0
	a["glow"] = 0
	a["camera"]["dolly"] = 6.0
	var b: Dictionary = a.duplicate(true)
	b["feedback"]["zoom"] = 1.2
	b["glow"] = 2
	b["camera"]["dolly"] = 10.0
	Presets.save(3, a, pp, 0)
	Presets.save(5, b, pp, 2)
	Presets.save(9, b, pp, 2)
	ok_xf = ok_xf and Presets.filled(pp, 2) == [5, 9] and Presets.filled(pp, 0) == [3] and not Presets.has(5, pp, 0)
	ok_xf = ok_xf and Presets.neighbour(5, 1, pp, 2) == 9 and Presets.neighbour(9, 1, pp, 2) == 5 and Presets.neighbour(0, 1, pp, 2) == 5 and Presets.neighbour(0, -1, pp, 2) == 9
	st.restore(a, 0.0)
	st.restore(b, 1.0)
	st._tick_crossfade(0.25)
	ok_xf = ok_xf and st.crossfading() and is_equal_approx(st.fb_zoom, 1.05) and st._glow.level == 0 and is_equal_approx(st.cam_dolly, 7.0)
	st._tick_crossfade(0.30)                              # t = 0.55: discrete flipped
	ok_xf = ok_xf and is_equal_approx(st.fb_zoom, 1.11) and st._glow.level == 2
	st._tick_crossfade(0.60)                              # done: exact landing
	ok_xf = ok_xf and not st.crossfading() and is_equal_approx(st.fb_zoom, 1.2) and is_equal_approx(st.cam_dolly, 10.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pp))
	st.restore(a, 0.0)
	# and the same crossfade driven by the real process loop
	st.restore(a, 0.0)
	st.restore(b, 0.5)
	await get_tree().create_timer(0.2).timeout
	var mid_zoom: float = st.fb_zoom
	ok_xf = ok_xf and st.crossfading() and mid_zoom > 1.02 and mid_zoom < 1.18
	await get_tree().create_timer(0.5).timeout
	ok_xf = ok_xf and not st.crossfading() and is_equal_approx(st.fb_zoom, 1.2)
	st.start_credits_roll()
	await get_tree().create_timer(0.3).timeout
	ok_xf = ok_xf and st._roll_body.position.y < 1075.0
	st.stop_credits_roll()
	if ok_xf:
		print("PASS preset banks, neighbour stepping, crossfade of everything")
	else:
		fails += 1
		printerr("FAIL banks / crossfade (zoom=%.3f glow=%d dolly=%.2f)" % [st.fb_zoom, st._glow.level, st.cam_dolly])
	# credits: on-stage ids, ticker text, roll, and the burned-in strip composer
	var ok_cr := true
	st.clear_actors()
	Toolbox.select(0)
	st.spawn_at(Vector2(500, 500))
	Toolbox.select(2)
	st.spawn_at(Vector2(700, 500))
	await get_tree().process_frame
	var ids: Array = st.onstage_ids()
	ok_cr = ok_cr and ids.size() == 2 and ids.has(Toolbox.slots[0]["id"]) and ids.has(Toolbox.slots[2]["id"])
	st.set_ticker(true)
	ok_cr = ok_cr and st._ticker.visible and st._ticker.text.begins_with("icons: ") and st._ticker.text.contains("star")
	st.set_ticker(false)
	st.start_credits_roll()
	st._tick_credits(0.5)
	ok_cr = ok_cr and st._roll.visible and st._roll_body.position.y < 1080.0 and st._roll_body.get_child_count() > 4
	st.stop_credits_roll()
	var pic := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	pic.fill(Color(0.2, 0.3, 0.9))
	var burned := Shot.compose(pic, ["Made with Video Toy", "star by The Mutant Factory (public-domain)"])
	var strip_has_text := false
	for yy in range(180, burned.get_height(), 2):
		for xx in range(0, 320, 2):
			if burned.get_pixel(xx, yy).r > 0.5:
				strip_has_text = true
	ok_cr = ok_cr and burned.get_height() == 180 + Shot.PAD * 2 + Shot.LINE_PX * 2 and burned.get_pixel(10, 10).b > 0.8 and strip_has_text
	var saved_path := Shot.save(burned, "user://_selftest_shots")
	ok_cr = ok_cr and saved_path != "" and FileAccess.file_exists(saved_path)
	if saved_path != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://_selftest_shots"))
	var ctext: String = Ledger.credits_text()
	ok_cr = ok_cr and ctext.begins_with("Made with Video Toy") and ctext.contains("Other assets:")
	st.clear_actors()
	if ok_cr:
		print("PASS credits: on-stage ids, ticker, roll, burned-in strip, export text")
	else:
		fails += 1
		printerr("FAIL credits")
	# SDF: field cached, morph verb swaps texture + material and advances, outline sets the ring
	var ok_sdf := true
	var sdf_tex = IconMedia.sdf_for(str(Toolbox.slots[0]["svg_path"]))
	ok_sdf = ok_sdf and sdf_tex != null and sdf_tex.get_width() == Sdf.RES and FileAccess.file_exists("%s/%d.png" % [IconMedia.SDF_DIR, absi(str(Toolbox.slots[0]["svg_path"]).hash())])
	st.clear_actors()
	if not Toolbox.has_verb(0, "morph"):
		Toolbox.toggle_verb(0, "morph")
	Toolbox.select(0)
	st.spawn_at(Vector2(600, 500))
	await get_tree().create_timer(0.4).timeout
	var act = st.all_actors()[0]
	var t_now: float = float(act._sdf_mat.get_shader_parameter("t")) if act._sdf_mat else -1.0
	ok_sdf = ok_sdf and act._sdf_mat != null and act._sprite.texture == sdf_tex and act._morph_target == Toolbox.slots[1]["id"] and t_now > 0.05 and t_now < 0.9 and act._sdf_mult > 1.5
	Toolbox.toggle_verb(0, "morph")
	if not Toolbox.has_verb(0, "outline"):                # a killed run can leave it on disk
		Toolbox.toggle_verb(0, "outline")
	await get_tree().process_frame
	await get_tree().process_frame
	ok_sdf = ok_sdf and act._sdf_mat != null and float(act._sdf_mat.get_shader_parameter("outline")) > 0.0 and float(act._sdf_mat.get_shader_parameter("t")) == 0.0
	Toolbox.toggle_verb(0, "outline")
	await get_tree().process_frame
	ok_sdf = ok_sdf and act._sdf_mat == null and act._sprite.material == null and act._sprite.texture == act._tex_orig
	st.clear_actors()
	if ok_sdf:
		print("PASS icon SDFs cached, Morph advances toward the next slot, Outline rings, both restore")
	else:
		fails += 1
		printerr("FAIL sdf / morph")
	# physics: bodies from the icon alpha fall onto the floor, pile, count collisions, float
	# without gravity, get thrown; the verb's removal frees the body. Sounds: a wav on a slot
	# plays on spawn and by hand, the hotbar marks it, and the tile hit test finds the slot.
	var ok_ph := true
	var ph_bad: Array = []
	var ph_chk := func(label: String, ok: bool):
		if not ok:
			ph_bad.append(label)
	st.clear_actors()
	Toolbox.select(0)
	if not Toolbox.has_verb(0, "physics"):
		Toolbox.toggle_verb(0, "physics")
	st.set_gravity(1.0)
	for i in 3:
		st.spawn_at(Vector2(900.0 + i * 12.0, 150.0 + i * 100.0))
	await get_tree().process_frame
	await get_tree().process_frame
	var pa = st.all_actors()[0]
	ph_chk.call("1 pa.body != null and pa.body.get_child_co", pa.body != null and pa.body.get_child_count() >= 1 and pa.get_parent().get_parent().has_node("IconWalls"))
	var y0: float = pa.position.y
	await get_tree().create_timer(1.5).timeout
	ph_chk.call("2 pa.position.y > y0 + 100.0 and pa.positi", pa.position.y > y0 + 100.0 and pa.position.y < st.WORLD.y + 1.0)
	ph_chk.call("3 IconBody.collisions > 0", IconBody.collisions > 0)
	st.set_gravity(0.0)
	await get_tree().process_frame
	await get_tree().process_frame                       # the verb copies gravity in its _process
	ph_chk.call("4 pa.body.gravity_scale == 0.0 and st.snap", pa.body.gravity_scale == 0.0 and st.snapshot()["physics"]["gravity"] == 0.0)
	pa.grab(true)
	pa.grab_to(Vector2(500, 500))
	await get_tree().physics_frame                       # a real drag spans frames
	pa.release(Vector2(900, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("physics throw: pos=%s vel=%s sleeping=%s" % [pa.position, pa.body.linear_velocity, pa.body.sleeping])
	ph_chk.call("5 pa.position.distance_to(Vector2(500, 500", pa.position.distance_to(Vector2(500, 500)) < 400.0 and pa.body.linear_velocity.x > 500.0)
	ph_chk.call("6 st._physics_actor_at(pa.position) == pa", st._physics_actor_at(pa.position) == pa)
	Toolbox.toggle_verb(0, "physics")
	await get_tree().process_frame
	await get_tree().process_frame
	ph_chk.call("7 pa.body == null", pa.body == null)
	st.set_gravity(1.0)
	var wav := ProjectSettings.globalize_path("user://_selftest_tone.wav")
	ph_chk.call("8 Sounds.make_test_wav(wav) and Toolbox.se", Sounds.make_test_wav(wav) and Toolbox.set_slot_sound(0, wav))
	var sp := str(Toolbox.slots[0].get("sound_path", ""))
	var played0: int = Sounds.played
	ph_chk.call("9 sp.ends_with('.wav') and st.play_slot_so", sp.ends_with(".wav") and st.play_slot_sound() and Sounds.last_played == sp and Sounds.played == played0 + 1)
	st.spawn_at(Vector2(700, 300))
	ph_chk.call("10 Sounds.played == played0 + 2            ", Sounds.played == played0 + 2)
	ph_chk.call("11 Sounds.play_once_this_frame(sp) and not ", Sounds.play_once_this_frame(sp) and not Sounds.play_once_this_frame(sp))
	await get_tree().process_frame
	var tile: Control = st._hotbar._tiles[0]
	ph_chk.call("12 st._hotbar.slot_at(tile.get_global_rect(", st._hotbar.slot_at(tile.get_global_rect().get_center()) == 0 and st._hotbar.slot_at(Vector2(-50, -50)) == -1 and tile.get_child(2).visible)
	Toolbox.set_slot_sound(0, "")
	ph_chk.call("13 not Toolbox.slots[0].has('sound_path')", not Toolbox.slots[0].has("sound_path"))
	DirAccess.remove_absolute(wav)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))
	st.clear_actors()
	ok_ph = ph_bad.is_empty()
	if not ok_ph:
		printerr("physics / sounds sub-checks failed: ", ph_bad)
	if ok_ph:
		print("PASS physics bodies fall, pile, collide, float, throw and detach; slot sounds play on spawn / by hand, once per frame, and the hotbar marks them")
	else:
		fails += 1
		printerr("FAIL physics / sounds")
	# MIDI out over OSC: a spawn sends a note and an event, the beat a kick, both over loopback
	var ok_mo := true
	var mrx := PacketPeerUDP.new()
	ok_mo = ok_mo and mrx.bind(9152, "127.0.0.1") == OK
	st.timeline.stop_play()                                     # a loop from an earlier block would keep spawning
	st.set_evolve(false)
	MidiOut.configure("127.0.0.1", 9152, true)
	st.clear_actors()
	Toolbox.select(2)
	st.spawn_at(Vector2(300, 108))
	ok_mo = ok_mo and AudioReact.beat.is_connected(st._on_beat_out)
	st._on_beat_out()                                           # the beat handler itself (a real pulse would also fire learned actions)
	await get_tree().create_timer(0.3).timeout                 # gates pass; the stage ticks note-offs
	var mgot: Array = []
	while mrx.get_available_packet_count() > 0:
		mgot.append_array(Osc.parse(mrx.get_packet()))
	mrx.close()
	var maddr: Array = mgot.map(func(m): return m["address"])
	var spawn_msgs: Array = mgot.filter(func(m): return m["address"] == "/vt/event/spawn" and m["args"][0] == 3)
	ok_mo = ok_mo and maddr.has("/vt/midi/note_on") and maddr.has("/vt/event/spawn") and maddr.has("/vt/event/beat") and maddr.count("/vt/midi/note_off") >= 2
	ok_mo = ok_mo and spawn_msgs.size() == 1 and spawn_msgs[0]["args"][0] == 3 and absf(float(spawn_msgs[0]["args"][2]) - 0.1) < 0.01
	var first_on: Array = mgot.filter(func(m): return m["address"] == "/vt/midi/note_on" and m["args"][1] == MidiOut.note_for_slot(2))
	ok_mo = ok_mo and not first_on.is_empty() and first_on[0]["args"] == [1, MidiOut.note_for_slot(2), MidiOut.velocity_for_height(108.0, 1080.0)]
	st._update_hud()
	ok_mo = ok_mo and st._hud.text.contains("osc out →")
	MidiOut.configure("127.0.0.1", 9001, false)
	Toolbox.select(0)
	st.clear_actors()
	if ok_mo:
		print("PASS MIDI out over OSC: spawn note + event, beat kick, gated note-offs, HUD")
	else:
		fails += 1
		printerr("FAIL midi out (%s)" % [maddr])
	# voice: the verb gives the actor an oscillator fed from its distance field; pitched by slot
	var ok_v := true
	st.clear_actors()
	await get_tree().process_frame
	Toolbox.select(0)
	if not Toolbox.has_verb(0, "voice"):
		Toolbox.toggle_verb(0, "voice")
	st.spawn_at(Vector2(600, 400))
	await get_tree().process_frame
	await get_tree().process_frame
	var va = st.all_actors()[0]
	ok_v = ok_v and va._voice != null and IconVoice.active == 1 and va._voice.table_a.size() == IconVoice.N and va._voice.playing() and absf(va._voice.freq - 110.0) < 3.0 and va._voice.amp > 0.0
	Toolbox.select(1)
	st.spawn_at(Vector2(800, 400))
	await get_tree().process_frame
	await get_tree().process_frame
	ok_v = ok_v and IconVoice.active == 1 and st.all_actors().size() == 2               # slot 1 has no voice verb
	Toolbox.toggle_verb(0, "voice")
	await get_tree().process_frame
	await get_tree().process_frame
	ok_v = ok_v and va._voice == null and IconVoice.active == 0
	Toolbox.select(0)
	st.clear_actors()
	if ok_v:
		print("PASS voice: an oscillator per icon from its distance field, pitched by slot, gone with the verb")
	else:
		fails += 1
		printerr("FAIL voice")
	# undo / redo over spawns, removes and clears (contents only); surprise is a full step
	var ok_u := true
	st.clear_actors()
	await get_tree().process_frame
	st._history.clear()
	Toolbox.select(0)
	st.spawn_at(Vector2(400, 400))
	st.spawn_at(Vector2(500, 400))
	await get_tree().process_frame
	ok_u = ok_u and st.all_actors().size() == 2 and st._history.depth() == 2 and st._history.labels() == ["spawn", "spawn"]
	st.undo()
	await get_tree().process_frame
	await get_tree().process_frame
	ok_u = ok_u and st.all_actors().size() == 1 and st._history.depth() == 1
	st.redo()
	await get_tree().process_frame
	await get_tree().process_frame
	ok_u = ok_u and st.all_actors().size() == 2 and st._history.depth() == 2
	st._remove_nearest(Vector2(500, 400))
	await get_tree().process_frame
	ok_u = ok_u and st.all_actors().size() == 1 and st._history.labels()[-1] == "remove"
	st.undo()
	await get_tree().process_frame
	await get_tree().process_frame
	ok_u = ok_u and st.all_actors().size() == 2
	st.clear_actors()
	await get_tree().process_frame
	ok_u = ok_u and st.all_actors().is_empty()
	st.undo()
	await get_tree().process_frame
	await get_tree().process_frame
	ok_u = ok_u and st.all_actors().size() == 2
	var pal0: int = st.palette_index
	var pre_hash: int = st.snapshot().hash()
	var note: String = st.surprise()
	await get_tree().process_frame
	ok_u = ok_u and note.begins_with("surprise:") and note.length() > 12 and not st.all_actors().is_empty() and st._history.labels()[-1] == "surprise"
	st.undo()
	await get_tree().process_frame
	await get_tree().process_frame
	ok_u = ok_u and st.palette_index == pal0 and st.snapshot().hash() == pre_hash and st.all_actors().size() == 2
	st._history.clear()
	ok_u = ok_u and not st.undo() and st._steal_note == "nothing to undo"
	st.clear_actors()
	st.panic()
	if ok_u:
		print("PASS undo / redo over spawn, remove and clear; surprise changes the look and undo restores it exactly")
	else:
		fails += 1
		printerr("FAIL undo / surprise")
	# guest mode: right-click opens the wheel, its pages pick a slot / toggle a verb / act,
	# a tap spawns on release and a hold removes; the tour runs its five steps and persists
	var ok_g := true
	var g_bad: Array = []
	var g_chk := func(label: String, ok: bool):
		if not ok:
			g_bad.append(label)
	st.clear_actors()
	await get_tree().process_frame                       # the frees land before we count
	st.set_guest(true)
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	rmb.position = Vector2(900, 500)
	st._gui_input(rmb)
	g_chk.call("1", st._wheel.visible and st._wheel.page == "slots" and st._wheel.items.size() == Toolbox.slots.size())
	st._wheel.activate(2)
	g_chk.call("2", Toolbox.selected == 2)
	st._wheel.next_page()
	g_chk.call("3", st._wheel.page == "verbs" and st._wheel.items.size() == Verbs.all().size())
	var vid: String = str(Verbs.all()[0]["id"])
	var had: bool = Toolbox.has_verb(2, vid)
	st._wheel.activate(0)
	g_chk.call("4", Toolbox.has_verb(2, vid) != had and bool(st._wheel.items[0]["on"]) != had)
	st._wheel.activate(0)                                # back as it was
	st._wheel.next_page()
	g_chk.call("5", st._wheel.page == "more")
	var pal_g: int = st.palette_index
	st._wheel.activate(0)                                # palette
	g_chk.call("6", st.palette_index == (pal_g + 1) % Palettes.count())
	st._wheel.close()
	g_chk.call("7", not st._wheel.visible)
	Toolbox.select(0)
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	lmb.pressed = true
	lmb.position = Vector2(700, 400)
	var n0: int = st.all_actors().size()
	st._gui_input(lmb)
	g_chk.call("8", st.all_actors().size() == n0 and st._press_pending)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(700, 400)
	st._gui_input(up)
	g_chk.call("9", st.all_actors().size() == n0 + 1)
	st._gui_input(lmb)
	st._press_ms -= 800                                                       # pretend the hold lasted
	st._gui_input(up)
	await get_tree().process_frame
	g_chk.call("10", st.all_actors().size() == n0)
	st.set_guest(false)
	Tour.settings_path = "user://_selftest_tour.cfg"
	Settings.reset(Tour.settings_path)
	g_chk.call("11", not Tour.seen())
	st.start_tour()
	g_chk.call("12", st._tour.visible and st._tour.step == 0 and st._tour._label.text.begins_with("Click anywhere"))
	for i in 3:
		st._tour.advance()
	g_chk.call("13", st._tour.step == 3 and st._tour.visible)
	var esc2 := InputEventKey.new()
	esc2.pressed = true
	esc2.keycode = KEY_ESCAPE
	st._tour._unhandled_key_input(esc2)
	g_chk.call("14", not st._tour.visible and Tour.seen())
	Settings.reset(Tour.settings_path)
	Tour.settings_path = Settings.PATH
	st.clear_actors()
	ok_g = g_bad.is_empty()
	if not ok_g:
		printerr("guest / tour sub-checks failed: ", g_bad)
	if ok_g:
		print("PASS guest wheel pages pick slots, toggle verbs and act; tap spawns on release, hold removes; the tour steps and persists")
	else:
		fails += 1
		printerr("FAIL guest / tour")
	# the key table: a few keys through the real dispatcher (plain, Shift, Ctrl, digits)
	var ok_keys := true
	var send := func(code: int, shift := false, ctrl := false):
		var kev := InputEventKey.new()
		kev.pressed = true
		kev.keycode = code
		kev.shift_pressed = shift
		kev.ctrl_pressed = ctrl
		st._unhandled_key_input(kev)
	var fb0: bool = st.feedback
	send.call(KEY_F)
	ok_keys = ok_keys and st.feedback != fb0
	send.call(KEY_F)
	ok_keys = ok_keys and st.feedback == fb0
	var g0: float = st.gravity
	send.call(KEY_G, false, true)
	ok_keys = ok_keys and st.gravity != g0
	send.call(KEY_G, false, true)
	ok_keys = ok_keys and st.gravity == g0
	st.set_active_layer(1)
	var op0: float = st._layers[1]["opacity"]
	send.call(KEY_BRACKETLEFT, true)
	ok_keys = ok_keys and st._layers[1]["opacity"] < op0
	st.set_layer_opacity(op0)
	st.set_active_layer(0)
	send.call(KEY_3)
	ok_keys = ok_keys and Toolbox.selected == 2
	Toolbox.select(0)
	var hm0: int = st.hud_mode
	send.call(KEY_H)
	ok_keys = ok_keys and st.hud_mode == (hm0 + 1) % 3
	st.set_hud_mode(hm0)
	ok_keys = ok_keys and st._m_input.table_keys().size() >= 40 and st._m_input.table_keys().has(KEY_TAB) and st._m_input.table_keys().has(KEY_H)
	if ok_keys:
		print("PASS key table dispatches plain, Shift and Ctrl keys and digits")
	else:
		fails += 1
		printerr("FAIL key table")
	# help overlay (tabs, search, Esc), HUD modes, settings-backed knobs, live OSC re-bind
	var ok_help := true
	st.open_help()
	await get_tree().process_frame
	ok_help = ok_help and st._help.visible and st._help.row_count() > 60
	st._help.search("slit-scan")
	ok_help = ok_help and st._help.row_count() == 1
	st._help.search("")
	st._help.select_tab("Verbs")
	ok_help = ok_help and st._help.row_count() == Verbs.instances().size()
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	st._unhandled_key_input(esc)
	ok_help = ok_help and not st._help.visible and not menu.is_open()
	st.set_hud_mode(1)
	ok_help = ok_help and st._hud.get_parent().visible and not st._verb_panel.get_parent().visible and not st._hud.text.contains("\n")
	st.set_hud_mode(2)
	ok_help = ok_help and not st._hud.get_parent().visible
	st.set_hud_mode(0)
	ok_help = ok_help and st._hud.text.contains("\n") and st._verb_panel.get_parent().visible
	var old_port: int = Osc.port
	ok_help = ok_help and Osc.set_port(9137) and Osc.port == 9137 and Osc.set_port(old_port) and Osc.port == old_port
	ok_help = ok_help and st.idle_attract >= 10.0 and st.autosave_interval >= 5.0 and Settings.get_value("syphon_name") != null
	if ok_help:
		print("PASS help overlay tabs + search + Esc, HUD full / compact / hidden, OSC port re-bind, settings-backed knobs")
	else:
		fails += 1
		printerr("FAIL help / hud / settings")
	# clock: internal beats drive AudioReact, the timeline quantises and waits for the bar, scenes lock
	var ok_ck := true
	Clock.start_internal(120.0)
	ok_ck = ok_ck and Clock.running and AudioReact.active() and AudioReact.beat_env >= 0.99
	st.finish_crossfade()
	st.timeline = Timeline.new()
	st._clock = 200.0
	st.toggle_record()
	MidiMap.last_source = "midi"
	st._on_midi_param("glow", 1.0)
	st._clock = 203.3
	st.toggle_record()                                        # 3.3 s -> 2 bars = 4.0 s at 120 bpm
	ok_ck = ok_ck and is_equal_approx(st.timeline.length, 4.0)
	st.toggle_play()
	ok_ck = ok_ck and st._play_pending and not st.timeline.playing
	Clock.advance(Clock.until_next_bar() - 0.005)          # just before the bar: the tick starts the loop
	st._tick_clock()
	ok_ck = ok_ck and not st._play_pending and st.timeline.playing
	st.toggle_play()
	Scenes.current = "plasma"
	Clock.lock_scenes = true
	Clock.bpm = 150.0
	st._tick_clock()
	ok_ck = ok_ck and is_equal_approx(Scenes.speed, 1.25)
	Clock.lock_scenes = false
	Scenes.current = ""
	Clock.toggle_internal()
	ok_ck = ok_ck and not Clock.running
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Timeline.PATH))
	ok_ck = ok_ck and (ClassDB.class_exists("SyphonOutput") or OS.get_name() != "macOS")
	if ok_ck:
		print("PASS clock drives beats, quantises the loop, waits for the bar, locks scenes; Syphon addon present")
	else:
		fails += 1
		printerr("FAIL clock / syphon")
	# birthday extras on the real stage: txt drop cycles, live clock re-renders, pinata bursts, video registers
	var ok_bd := true
	var _bd_trace: Array = []
	var txt := ProjectSettings.globalize_path("user://_selftest_words.txt")
	var tf := FileAccess.open(txt, FileAccess.WRITE)
	for i in 12:
		tf.store_line("W%d" % i)
	tf.close()
	var before_n := Toolbox.slots.size()
	st._on_files_dropped(PackedStringArray([txt]))
	var wi := Toolbox.slots.size() - 1
	ok_bd = ok_bd and Toolbox.slots.size() == before_n + 1 and Toolbox.slots[wi].has("words")
	_bd_trace.append("drop:%s" % ok_bd)
	var p0: String = Toolbox.slots[wi]["svg_path"]
	st.advance_words()
	ok_bd = ok_bd and Toolbox.slots[wi]["svg_path"] != p0 and Toolbox.slots[wi]["word_index"] == 1
	_bd_trace.append("cycle:%s" % ok_bd)
	var ci2 := Toolbox.add_text("clock")
	st._live_timer = 1.0
	st._tick_words(0.0)
	var live_path: String = Toolbox.slots[ci2]["svg_path"]
	ok_bd = ok_bd and Toolbox.slots[ci2].get("version", 0) == 1 and live_path.contains("_v1") and FileAccess.file_exists(live_path)
	_bd_trace.append("live:%s v=%s path=%s" % [ok_bd, Toolbox.slots[ci2].get("version", 0), live_path])
	st.clear_actors()
	if not Toolbox.has_verb(0, "sparkle"):
		Toolbox.toggle_verb(0, "sparkle")
	Toolbox.select(0)
	st.spawn_at(Vector2(800, 400))
	await get_tree().process_frame
	var acts: Array = st.all_actors()
	_bd_trace.append("pre: n=%d slot=%s sparkle=%s pos=%s sel=%d" % [acts.size(), acts[0].slot_id if acts.size() > 0 else "-", Toolbox.has_verb(0, "sparkle"), acts[0].position if acts.size() > 0 else Vector2.INF, Toolbox.selected])
	var at: Vector2 = acts[0].position if acts.size() > 0 else Vector2(800, 400)
	var hit1: bool = st.pinata_at(at + Vector2(20, 10))
	var dying: bool = acts.size() > 0 and acts[0]._dying
	var hit2: bool = st.pinata_at(at + Vector2(20, 10))
	ok_bd = ok_bd and hit1 and dying and not hit2
	_bd_trace.append("pinata:%s hit1=%s dying=%s hit2=%s" % [ok_bd, hit1, dying, hit2])
	await get_tree().create_timer(1.5).timeout
	ok_bd = ok_bd and st.all_actors().is_empty()
	_bd_trace.append("gone:%s n=%d" % [ok_bd, st.all_actors().size()])
	Toolbox.toggle_verb(0, "sparkle")
	var vtmp := ProjectSettings.globalize_path("user://_selftest.ogv")
	var vf2 := FileAccess.open(vtmp, FileAccess.WRITE)
	vf2.store_string("x")
	vf2.close()
	var vi2 := Toolbox.add_video(vtmp)
	st._sync_videos()
	var vpath: String = Toolbox.slots[vi2]["svg_path"]
	ok_bd = ok_bd and st._videos.has(vpath) and IconMedia.texture_for(vpath) is ViewportTexture
	_bd_trace.append("video:%s" % ok_bd)
	# clean up the slots and files this made
	for idx in [vi2, ci2, wi]:
		var sl: Dictionary = Toolbox.slots[idx]
		for pth in [sl.get("svg_path", "")] + Array(sl.get("word_paths", [])):
			if str(pth).begins_with("user://") and FileAccess.file_exists(str(pth)):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(str(pth)))
		Ledger.remove(sl["id"])
		Toolbox.remove(idx)
	st._sync_videos()
	ok_bd = ok_bd and not st._videos.has(vpath)
	DirAccess.remove_absolute(txt)
	DirAccess.remove_absolute(vtmp)
	if ok_bd:
		print("PASS birthday extras: word list cycles, live clock re-renders, pinata bursts, video slot registers and unregisters")
	else:
		fails += 1
		printerr("FAIL birthday extras: ", _bd_trace)
	# autosave: live state round-trips actors and solids; the running flag marks unclean exits; ascii pass
	var ok_as := true
	var _as_trace: Array = []
	st.clear_actors()
	for sol in st._solids.get_children():
		sol.queue_free()
	Toolbox.select(0)
	st.spawn_at(Vector2(400, 300))
	st.set_active_layer(1)
	Toolbox.select(1)
	st.spawn_at(Vector2(800, 600))
	st.set_active_layer(0)
	Toolbox.select(2)
	st._shape_index = 2
	st.spawn_solid(Vector2(960, 540))
	st._ascii.set_mode(2)
	await get_tree().process_frame
	var ls: Dictionary = st.live_state()
	ok_as = ok_as and ls["live"]["actors"].size() == 2 and ls["live"]["solids"].size() == 1 and ls["live"]["solids"][0]["shape"] == "torus" and ls["ascii"] == 2
	_as_trace.append("live:%s actors=%d solids=%s ascii=%s" % [ok_as, ls["live"]["actors"].size(), ls["live"]["solids"], ls.get("ascii")])
	var apath := "user://_selftest_autosave.json"
	ok_as = ok_as and Autosave.write(ls, apath) and Autosave.age_seconds(apath) <= 1 and Autosave.describe_age(5) == "5 s ago" and Autosave.describe_age(600) == "10 min ago"
	st.clear_actors()
	for sol in st._solids.get_children():
		sol.queue_free()
	st._ascii.set_mode(0)
	await get_tree().process_frame
	var back2: Dictionary = Autosave.read(apath)
	var n_back: int = st.restore_live(back2)
	await get_tree().process_frame
	ok_as = ok_as and n_back == 3 and st._layers[1]["actors"].get_child_count() == 1 and st._solids.get_child_count() == 1 and st._ascii.mode == 2 and st._solids.get_child(0).shape == "torus"
	_as_trace.append("restore:%s n=%d l1=%d solids=%d ascii=%d" % [ok_as, n_back, st._layers[1]["actors"].get_child_count(), st._solids.get_child_count(), st._ascii.mode])
	var flag := "user://_selftest_running.flag"
	Autosave.mark_running(flag)
	ok_as = ok_as and Autosave.crashed_last_time(flag)
	Autosave.mark_clean_exit(flag)
	ok_as = ok_as and not Autosave.crashed_last_time(flag)
	var atlas: Image = st._ascii.build_atlas(" .:-=+*#%@", Vector2(12, 20))
	var dark := 0
	var bright := 0
	for yy in 20:
		for xx in 12:
			if atlas.get_pixel(12 + xx, yy).a > 0.5: dark += 1
			if atlas.get_pixel(12 * 9 + xx, yy).a > 0.5: bright += 1
	ok_as = ok_as and atlas.get_width() == 120 and dark > 0 and bright > dark * 3
	_as_trace.append("atlas:%s w=%d dark=%d bright=%d" % [ok_as, atlas.get_width(), dark, bright])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(apath))
	st.clear_actors()
	for sol in st._solids.get_children():
		sol.queue_free()
	st._ascii.set_mode(0)
	if ok_as:
		print("PASS autosave live state round-trips, running flag, ASCII atlas ramps dark to bright")
	else:
		fails += 1
		printerr("FAIL autosave / ascii: ", _as_trace)
	if ok_layers:
		print("PASS layers blend/opacity, spawn into layer, drawn path riders, preset")
	else:
		fails += 1
		printerr("FAIL layers / draw")
	if ok_scenes:
		print("PASS scenes build, switch and round-trip through presets")
	else:
		fails += 1
		printerr("FAIL scenes")
	Presets.save(12, snap, "user://_selftest_presets.json")
	var back: Dictionary = Presets.get_preset(12, "user://_selftest_presets.json")
	ok_preset = ok_preset and int(back.get("fx", {}).get("crt", 0)) == 2 and int(back.get("glow", 0)) == 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://_selftest_presets.json"))
	if ok_preset:
		print("PASS stage snapshot/restore and preset file round-trip")
	else:
		fails += 1
		printerr("FAIL preset round-trip")
	# 3D solids need the autoloads, so they are checked here, not in smoke.gd
	var Solid = load("res://src/solid.gd")
	var ok_shapes: bool = Solid != null and Solid.SHAPES.size() == 6
	if ok_shapes:
		for k in Solid.SHAPES:
			if Solid.make_mesh(k) == null or (k != "cookie" and Solid.uv_scale(k) == Vector3.ONE):
				ok_shapes = false
	if ok_shapes:
		print("PASS every solid shape has a mesh and uv tiling")
	else:
		fails += 1
		printerr("FAIL solid shapes")
	Autosave.mark_clean_exit()
	get_tree().quit(1 if fails > 0 else 0)


## A 480x320 sunset-ish image with a few blobs, written to the scratch dir.
static func _demo_photo() -> String:
	var img := Image.create(480, 320, false, Image.FORMAT_RGBA8)
	for y in 320:
		for x in 480:
			var t := float(y) / 320.0
			img.set_pixel(x, y, Color(0.95 - 0.5 * t, 0.45 - 0.3 * t, 0.25 + 0.4 * t))
	for b in [[120, 110, 60, Color("#ffd166")], [330, 200, 80, Color("#1b998b")], [240, 70, 40, Color("#e63946")]]:
		for y in range(b[1] - b[2], b[1] + b[2]):
			for x in range(b[0] - b[2], b[0] + b[2]):
				if Vector2(x - b[0], y - b[1]).length() < b[2] and x >= 0 and y >= 0 and x < 480 and y < 320:
					img.set_pixel(x, y, b[3])
	var path := ProjectSettings.globalize_path("user://_capture_photo.png")
	img.save_png(path)
	return path


static func _cc(channel: int, number: int, value: int) -> InputEventMIDI:
	var ev := InputEventMIDI.new()
	ev.message = MIDI_MESSAGE_CONTROL_CHANGE
	ev.channel = channel
	ev.controller_number = number
	ev.controller_value = value
	return ev


## Screenshot every screen (and the menu + attribution overlay) into `dir`.
func _capture_all(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	if Toolbox.slots.is_empty():
		DemoPack.load_into(Toolbox, Ledger)
	var only := ""
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1]
	var shots := SCREENS.keys() + ["menu", "attribution", "feedback", "pixelate", "quantise", "kaleido", "chroma", "crt", "monitor", "solids", "midi", "audio", "raster", "glow", "scene_stage", "solids3d", "text_flock", "layers", "draw", "keyers", "slitscan", "mosaic", "attractors", "particles", "rd", "two_player", "blackout", "credits", "morph", "birthday", "ascii", "physics", "ref_stage", "ref_crt", "help", "ref_panel", "ref_help", "wheel", "tour"]
	var only_set: PackedStringArray = only.split(",") if only != "" else PackedStringArray()
	for name in shots:
		if only != "" and not only_set.has(name) and name != "stage":
			continue
		match name:
			"menu":
				menu.show_menu()
				await get_tree().create_timer(0.4).timeout
			"attribution":
				menu.show_attribution()
				await get_tree().create_timer(0.4).timeout
			"feedback":
				menu.close()
				show_screen("stage")
				await get_tree().create_timer(0.3).timeout
				current.demo_spawn()
				current._set_feedback(true)
				await get_tree().create_timer(3.0).timeout
			"pixelate":
				current.set_fx(12, false, false)
				await get_tree().create_timer(0.3).timeout
			"quantise":
				current.palette_index = 3          # Cream: light bg, 5 inks
				current._apply_palette()
				current.set_fx(8, true, true)
				await get_tree().create_timer(0.5).timeout
			"kaleido":
				current.palette_index = 0
				current._apply_palette()
				current.set_fx(0, false, false, 6, false)
				await get_tree().create_timer(1.0).timeout
			"chroma":
				current.set_fx(0, false, false, 0, true)
				await get_tree().create_timer(0.5).timeout
			"crt":
				current.palette_index = 2          # VHS
				current._apply_palette()
				current.set_fx(0, false, false, 0, false, 2)
				await get_tree().create_timer(0.8).timeout
			"monitor":
				current.palette_index = 0
				current._apply_palette()
				current.set_fx(0, false, false)
				current._set_feedback(false)
				current.set_monitor(true, 2)
				await get_tree().create_timer(2.0).timeout
			"solids":
				current.set_monitor(false)
				for a in current._actors.get_children():
					a.queue_free()
				for i in 10:
					Toolbox.select(i % Toolbox.slots.size())
					current.spawn_solid()
					current.cycle_shape()
				await get_tree().create_timer(1.5).timeout
			"midi":
				# Prove the learn path without hardware: arm a param, feed a CC,
				# then turn the "knob" and watch feedback zoom follow it. Bindings
				# go to a throwaway file so the user's real map is untouched.
				MidiMap.path = "user://_capture_midi.json"
				MidiMap.bindings = {}
				current._set_feedback(true)
				current.toggle_midi_panel()
				MidiMap.arm("fb_zoom")
				MidiMap.feed(_cc(1, 21, 10))
				MidiMap.arm("act:next_palette")
				MidiMap.feed(_cc(1, 22, 127))
				MidiMap.feed(_cc(1, 21, 96))                     # fb_zoom -> ~1.13
				MidiMap.feed(_cc(1, 22, 0))
				MidiMap.feed(_cc(1, 22, 127))                    # rising edge -> next palette
				await get_tree().create_timer(0.6).timeout
			"audio":
				# Test groove drives feedback zoom from bass and spawns on beats.
				current.toggle_midi_panel()
				MidiMap.set_audio_binding("fb_zoom", "bass")
				MidiMap.set_audio_binding("act:spawn", "beat")
				for i in Toolbox.slots.size():
					var v: String = ["pulse", "bounce", "pulse", "orbit", "pulse"][i % 5]
					if not Toolbox.has_verb(i, v):
						Toolbox.toggle_verb(i, v)
				current.set_fx(0, false, false)
				AudioReact.set_source("test")
				await get_tree().create_timer(2.6).timeout
			"raster":
				# A generated "photo" stands in for a dropped file: raster slot,
				# actors and a solid wearing it, then S steals its palette.
				AudioReact.set_source("off")
				current.toggle_midi_panel()
				current.set_webcam_mode(0)
				for a in current._actors.get_children() + current._solids.get_children():
					a.queue_free()
				var photo := _demo_photo()
				var idx: int = current.add_raster(photo)
				Toolbox.select(idx)
				for v in ["bounce", "spin"]:
					if not Toolbox.has_verb(idx, v):
						Toolbox.toggle_verb(idx, v)
				for i in 5:
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current.spawn_solid()
				current.steal_palette()
				current.set_webcam_mode(1)          # shows "no camera" here; live elsewhere
				await get_tree().create_timer(1.2).timeout
			"glow":
				# Glow heavy, icon-shaped sparkle, test groove for beat bursts,
				# and the whole thing saved to a throwaway preset slot.
				current.toggle_midi_panel()
				current.set_webcam_mode(0)
				current.palette_index = 0
				current._apply_palette()
				for a in current._actors.get_children() + current._solids.get_children():
					a.queue_free()
				for i in Toolbox.slots.size():
					for v in ["orbit", "sparkle"]:
						if not Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
				for i in 8:
					Toolbox.select(i % Toolbox.slots.size())
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current.spawn_solid()
				current._glow.set_level(2)
				current._set_feedback(false)
				AudioReact.set_source("test")
				await get_tree().create_timer(2.0).timeout
			"scenes":
				AudioReact.set_source("off")
				show_screen("scenes")
				await get_tree().create_timer(0.8).timeout
			"scene_stage":
				# Truchet scene behind bouncing icons, feedback through the warp
				# mesh with drift and stretch, soft glow.
				Scenes.current = "truchet"
				Scenes.speed = 1.0
				show_screen("stage")
				await get_tree().create_timer(0.3).timeout
				for i in Toolbox.slots.size():
					for v in ["sparkle"]:
						if Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
				for i in 6:
					Toolbox.select(i % Toolbox.slots.size())
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current._glow.set_level(1)
				current.fb_warp = 0.5
				current.fb_drift = Vector2(2, -1)
				current.fb_stretch = Vector2(1.01, 0.99)
				current._set_feedback(true)
				await get_tree().create_timer(2.5).timeout
				Scenes.current = ""
			"solids3d":
				# Extruded star and heart cookies, a helix of 200 bolts, camera
				# orbiting with a little roll, soft glow, no feedback.
				current.set_scene("", 0.0)
				current._set_feedback(false)
				current._glow.set_level(1)
				for a in current._actors.get_children() + current._solids.get_children():
					a.queue_free()
				current._shape_index = 5              # cookie
				for i in [0, 1]:
					Toolbox.select(i)
					current.spawn_solid(Vector2(500 + i * 900, 420))
				Toolbox.select(2)
				current._formation_index = 0          # helix
				current.spawn_formation(200)
				current.cam_orbit = 0.4
				current.cam_roll = 0.15
				current.cam_height = 1.0
				await get_tree().create_timer(1.6).timeout
				for f in current._formations.get_children():
					f.queue_free()
				current.reset_camera()
			"text_flock":
				# A word as a slot, forty of them flocking; the star flocks too.
				current._glow.set_level(1)
				for a in current._actors.get_children() + current._solids.get_children():
					a.queue_free()
				var ti: int = Toolbox.add_text("HAPPY BDAY")
				Ledger.record_local(Toolbox.slots[ti])
				for i in [ti, 0]:
					if not Toolbox.has_verb(i, "flock"):
						Toolbox.toggle_verb(i, "flock")
					if Toolbox.has_verb(i, "orbit"):
						Toolbox.toggle_verb(i, "orbit")
					if Toolbox.has_verb(i, "spin"):
						Toolbox.toggle_verb(i, "spin")
					if Toolbox.has_verb(i, "pulse"):
						Toolbox.toggle_verb(i, "pulse")
				AudioReact.set_source("off")
				Toolbox.select(ti)
				for i in 24:
					current.spawn_at(Vector2(randf_range(400, 1500), randf_range(200, 900)))
				Toolbox.select(0)
				for i in 30:
					current.spawn_at(Vector2(randf_range(400, 1500), randf_range(200, 900)))
				await get_tree().create_timer(2.5).timeout
			"layers":
				# Base hearts, an ADD layer of rings at 90 %, a MUL layer of bolts;
				# overlaps show the blend maths. Feedback off, glow off.
				current.clear_actors()
				current._glow.set_level(0)
				for i in Toolbox.slots.size():
					for v in ["flock", "spin"]:
						if Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
					if not Toolbox.has_verb(i, "bounce"):
						Toolbox.toggle_verb(i, "bounce")
				current.set_active_layer(0)
				Toolbox.select(1)
				for i in 10:
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current.set_active_layer(1)
				current._layers[1]["blend"] = 1
				current.set_layer_opacity(0.9)
				Toolbox.select(3)
				for i in 10:
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current.set_active_layer(2)
				current._layers[2]["blend"] = 3
				current.set_layer_opacity(1.0)
				Toolbox.select(2)
				for i in 8:
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current._apply_layers()
				await get_tree().create_timer(1.5).timeout
			"draw":
				# A drawn heart-ish loop and a wave, each ridden by icons.
				current.clear_actors()
				current.set_active_layer(0)
				current.draw_mode = true
				Toolbox.select(0)
				var heart := PackedVector2Array()
				for i in 121:
					var t := TAU * i / 120.0
					heart.append(Vector2(960 + 16.0 * pow(sin(t), 3) * 18.0,
						470 - 18.0 * (13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))))
				current.begin_stroke(heart[0])
				for q in heart:
					current.extend_stroke(q)
				current.end_stroke()
				Toolbox.select(2)
				current.begin_stroke(Vector2(250, 880))
				for i in 80:
					current.extend_stroke(Vector2(250 + i * 18.0, 880 + sin(i * 0.25) * 70.0))
				current.end_stroke()
				await get_tree().create_timer(1.5).timeout
				current.draw_mode = false
			"keyers":
				# Edge key over the plasma backdrop: outlines of bouncing icons.
				current.clear_actors()
				current.set_active_layer(0)
				for i in Toolbox.slots.size():
					if not Toolbox.has_verb(i, "bounce"):
						Toolbox.toggle_verb(i, "bounce")
				for i in 12:
					Toolbox.select(i % 5)
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current.set_fx(0, false, false, 0, false, 0, 4, 0)
				await get_tree().create_timer(1.0).timeout
			"slitscan":
				# Rows mode: time runs down the picture, bouncing icons smear.
				current.clear_actors()
				current.set_active_layer(0)
				for i in Toolbox.slots.size():
					if not Toolbox.has_verb(i, "bounce"):
						Toolbox.toggle_verb(i, "bounce")
				for i in 10:
					Toolbox.select(i % 5)
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current.set_fx(0, false, false, 0, false, 0, 0, 1)
				await get_tree().create_timer(2.5).timeout
			"mosaic":
				# The stand-in photo rebuilt from the demo icons; Orbit makes it breathe.
				current.set_fx(0, false, false)
				current.clear_actors()
				current.set_active_layer(0)
				current._glow.set_level(0)
				var photo2 := _demo_photo()
				var pidx: int = current.add_raster(photo2)
				for i in Toolbox.slots.size():
					for v in ["bounce", "spin", "pulse"]:
						if Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
					if not Toolbox.has_verb(i, "orbit"):
						Toolbox.toggle_verb(i, "orbit")
				Toolbox.select(pidx)
				current.spawn_mosaic()
				await get_tree().create_timer(1.0).timeout
			"attractors":
				# Stars on Lorenz, hearts on Clifford, long feedback fade paints them.
				current.clear_actors()
				for i in Toolbox.slots.size():
					for v in ["orbit", "bounce", "spin", "pulse", "flock"]:
						if Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
				if not Toolbox.has_verb(0, "lorenz"):
					Toolbox.toggle_verb(0, "lorenz")
				if not Toolbox.has_verb(1, "clifford"):
					Toolbox.toggle_verb(1, "clifford")
				if not Toolbox.has_verb(2, "rossler"):
					Toolbox.toggle_verb(2, "rossler")
				for i in 6:
					Toolbox.select(0)
					current.spawn_at(Vector2(960, 540))
					Toolbox.select(1)
					current.spawn_at(Vector2(960, 540))
				Toolbox.select(2)
				current.spawn_at(Vector2(960, 540))
				current.fb_fade = 0.975
				current.fb_zoom = 1.0
				current.fb_rot = 0.0
				current._set_feedback(true)
				await get_tree().create_timer(4.0).timeout
			"particles":
				# 12k dots on the curl field, pulled toward three icons on Field.
				current._set_feedback(false)
				current.clear_actors()
				for i in Toolbox.slots.size():
					for v in ["lorenz", "rossler", "clifford", "swarm"]:
						if Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
				if not Toolbox.has_verb(1, "field"):
					Toolbox.toggle_verb(1, "field")
				Toolbox.select(1)
				for i in 3:
					current.spawn_at(Vector2(randf_range(500, 1400), randf_range(300, 800)))
				current.particles_attract = 0.8
				current.set_particles(true)
				await get_tree().create_timer(3.0).timeout
			"rd":
				# Coral preset seeded by orbiting icons, a few seconds in.
				current.set_particles(false)
				current.clear_actors()
				for i in Toolbox.slots.size():
					if Toolbox.has_verb(i, "field"):
						Toolbox.toggle_verb(i, "field")
					if not Toolbox.has_verb(i, "orbit"):
						Toolbox.toggle_verb(i, "orbit")
				for i in 5:
					Toolbox.select(i)
					current.spawn_at(Vector2(400 + i * 280, 540))
				current.set_rd_preset(1)
				await get_tree().create_timer(6.0).timeout
				current.set_rd_preset(0)
			"two_player":
				# Player 1's hearts on the base, player 2's bolts on the ADD layer
				# from their cursor, both slots ringed on the hotbar.
				current.clear_actors()
				current.set_active_layer(0)
				for i in Toolbox.slots.size():
					for v in ["orbit", "pulse", "rainbow"]:
						if Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
					if not Toolbox.has_verb(i, "bounce"):
						Toolbox.toggle_verb(i, "bounce")
				Toolbox.select(1)
				for i in 6:
					current.spawn_at(Vector2(randf_range(300, 900), randf_range(200, 900)))
				current.p2_slot = 2
				current.p2_layer = 1
				current._layers[1]["blend"] = 1
				current._apply_layers()
				current.p2_move(Vector2(-100, 0))
				for i in 6:
					current.p2_cursor = Vector2(randf_range(1000, 1700), randf_range(200, 900))
					current.p2_spawn()
				current.p2_cursor = Vector2(1150, 700)
				current._refresh_p2()
				await get_tree().create_timer(1.0).timeout
			"blackout":
				# Everything on, then PANIC, then blackout: the shot is the fade.
				current.p2_sleep()
				current.set_particles(true)
				current._glow.set_level(2)
				current.set_fx(12, true, true, 6, false, 2)
				current._set_feedback(true)
				await get_tree().create_timer(0.5).timeout
				current.panic()
				await get_tree().create_timer(0.3).timeout
				current.toggle_blackout()
				await get_tree().create_timer(0.25).timeout       # mid-fade
			"credits":
				# Ticker on, then the credits roll a few seconds in; and a burned-in shot.
				if current.blackout:
					current.toggle_blackout()
					await get_tree().create_timer(0.6).timeout
				current.p2_sleep()
				Toolbox.select(1)
				for i in 5:
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current.set_ticker(true)
				await get_tree().create_timer(0.3).timeout
				var shot_path: String = current.screenshot_with_credits()
				print("SHOT ", shot_path)
				current.start_credits_roll()
				await get_tree().create_timer(4.0).timeout
			"morph":
				# Stars morphing toward hearts, hearts outlined, bolts both.
				current.stop_credits_roll()
				current.set_ticker(false)
				current.clear_actors()
				for i in Toolbox.slots.size():
					for v in ["pulse", "bounce", "field", "dejong"]:
						if Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
				for pair in [[0, "morph"], [1, "outline"], [2, "morph"], [2, "outline"]]:
					if not Toolbox.has_verb(pair[0], pair[1]):
						Toolbox.toggle_verb(pair[0], pair[1])
				for i in 4:
					Toolbox.select(0)
					current.spawn_at(Vector2(400 + i * 380, 300))
					Toolbox.select(1)
					current.spawn_at(Vector2(400 + i * 380, 560))
					Toolbox.select(2)
					current.spawn_at(Vector2(400 + i * 380, 820))
				await get_tree().create_timer(0.8).timeout     # mid-morph
			"birthday":
				# A cycling word list, a cake emoji, a live clock, a dropped SVG,
				# and a pinata bursting mid-shot.
				current.clear_actors()
				for i in Toolbox.slots.size():
					for v in ["morph", "outline", "spin"]:
						if Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
				var ctxt := ProjectSettings.globalize_path("user://_capture_words.txt")
				var cf := FileAccess.open(ctxt, FileAccess.WRITE)
				for w in ["HAPPY", "BIRTHDAY", "DANIEL", "MAKE", "NOISE", "KNOBCON", "PARTY", "TIME", "GO", "GO", "GO", "!!!"]:
					cf.store_line(w)
				cf.close()
				current._on_files_dropped(PackedStringArray([ctxt]))
				var w_i := Toolbox.slots.size() - 1
				var cake_i := Toolbox.add_text("🎂")
				var clock_i := Toolbox.add_text("clock")
				var csvg := ProjectSettings.globalize_path("user://_capture_drop.svg")
				DirAccess.copy_absolute(ProjectSettings.globalize_path("res://icon.svg"), csvg)
				var svg_i := Toolbox.add_svg(csvg)
				for idx in [w_i, cake_i, clock_i, svg_i]:
					if not Toolbox.has_verb(idx, "bounce"):
						Toolbox.toggle_verb(idx, "bounce")
				for k in 3:
					Toolbox.select(w_i)
					current.spawn_at(Vector2(randf_range(400, 1500), randf_range(200, 900)))
					Toolbox.select(cake_i)
					current.spawn_at(Vector2(randf_range(400, 1500), randf_range(200, 900)))
				Toolbox.select(clock_i)
				current.spawn_at(Vector2(960, 540))
				Toolbox.select(svg_i)
				current.spawn_at(Vector2(1300, 300))
				if not Toolbox.has_verb(0, "sparkle"):
					Toolbox.toggle_verb(0, "sparkle")
				Toolbox.select(0)
				current.spawn_at(Vector2(500, 750))
				await get_tree().create_timer(1.2).timeout
				current.pinata_at(Vector2(500, 750))
				await get_tree().create_timer(0.35).timeout
				for idx in [svg_i, clock_i, cake_i, w_i]:
					var sl: Dictionary = Toolbox.slots[idx]
					for pth in [sl.get("svg_path", "")] + Array(sl.get("word_paths", [])):
						if str(pth).begins_with("user://") and FileAccess.file_exists(str(pth)):
							DirAccess.remove_absolute(ProjectSettings.globalize_path(str(pth)))
					Ledger.remove(sl["id"])
				DirAccess.remove_absolute(ctxt)
				DirAccess.remove_absolute(csvg)
				_cleanup_birthday = [svg_i, clock_i, cake_i, w_i]
			"ascii":
				menu.close()
				if current_name != "stage":
					show_screen("stage")
					await get_tree().create_timer(0.3).timeout
				current.clear_actors()
				current.set_fx(0, false, false)
				current._glow.set_level(0)
				current.palette_index = 0
				current._apply_palette()
				for i in Toolbox.slots.size():
					if not Toolbox.has_verb(i, "bounce"):
						Toolbox.toggle_verb(i, "bounce")
				for i in 8:
					Toolbox.select(i % mini(5, Toolbox.slots.size()))
					current.spawn_at(Vector2(randf_range(300, 1600), randf_range(200, 900)))
				current._ascii.set_mode(2)
				await get_tree().create_timer(0.8).timeout
			"help":
				menu.close()
				if current_name != "stage":
					show_screen("stage")
					await get_tree().create_timer(0.3).timeout
				current.open_help()
				await get_tree().create_timer(0.3).timeout
			"physics":
				menu.close()
				if current_name != "stage":
					show_screen("stage")
					await get_tree().create_timer(0.3).timeout
				current.clear_actors()
				current.set_gravity(1.0)
				for i in Toolbox.slots.size():
					if not Toolbox.has_verb(i, "physics"):
						Toolbox.toggle_verb(i, "physics")
				for i in 18:
					Toolbox.select(i % Toolbox.slots.size())
					current.spawn_at(Vector2(500 + (i % 6) * 180, 80 + (i / 6) * 160))
				await get_tree().create_timer(2.5).timeout
				for i in Toolbox.slots.size():
					Toolbox.toggle_verb(i, "physics")            # bodies go, the pile stays
				Toolbox.select(0)
			"wheel", "tour":
				menu.close()
				if current_name != "stage":
					show_screen("stage")
					await get_tree().create_timer(0.3).timeout
				current.panic()
				current._help.close()
				if current._midi_panel.visible:
					current.toggle_midi_panel()
				current.set_hud_mode(0)
				if current.all_actors().size() < 6:
					current.demo_spawn()
				if name == "wheel":
					current.set_guest(true)
					current.open_wheel(Vector2(1100, 520), "slots")
				else:
					current.set_guest(false)
					current.start_tour()
				await get_tree().create_timer(0.5).timeout
			"ref_panel", "ref_help":
				# Deterministic: an empty stage, HUD hidden, with the control panel
				# (a throwaway binding file, one learned CC) or the help overlay.
				menu.close()
				if current_name != "stage":
					show_screen("stage")
					await get_tree().create_timer(0.3).timeout
				current.panic()                               # every effect off, whatever ran before
				current.clear_actors()
				current.p2_sleep()
				current.set_hud_mode(2)
				current._help.close()
				if current._midi_panel.visible:
					current.toggle_midi_panel()
				if name == "ref_panel":
					MidiMap.path = "user://_capture_midi.json"
					MidiMap.bindings = {}
					MidiMap.arm("fb_zoom")
					MidiMap.feed(_cc(1, 21, 10))
					current.toggle_midi_panel()
				else:
					current.open_help()
				await get_tree().create_timer(0.5).timeout
			"ref_stage", "ref_crt":
				# Deterministic reference shots for tests/diff.gd: seeded RNG, fixed
				# positions, no motion verbs, no feedback, HUD hidden.
				menu.close()
				if current_name != "stage":
					show_screen("stage")
					await get_tree().create_timer(0.3).timeout
				current.p2_sleep()
				current.set_particles(false)
				current.set_rd_preset(0)
				current.set_scene("", 0.0)
				current._set_feedback(false)
				current.set_ticker(false)
				current.stop_credits_roll()
				current.clear_actors()
				for a in current._solids.get_children() + current._formations.get_children():
					a.queue_free()
				for i in Toolbox.slots.size():
					for v in Verbs.ids():
						if Toolbox.has_verb(i, v):
							Toolbox.toggle_verb(i, v)
				current._ascii.set_mode(0)
				current.palette_index = 3                 # Cream
				current._apply_palette()
				current._glow.set_level(0)
				current.set_monitor(false)
				current.set_fx(12, true, true, 0, false, 2 if name == "ref_crt" else 0)
				seed(4242)
				var grid := [Vector2(500, 330), Vector2(960, 330), Vector2(1420, 330), Vector2(500, 750), Vector2(960, 750), Vector2(1420, 750)]
				for i in grid.size():
					Toolbox.select(i % mini(5, Toolbox.slots.size()))
					current.spawn_at(grid[i])
				current._help.close()
				current.set_hud_mode(2)
				await get_tree().create_timer(0.5).timeout
			"stage":
				show_screen(name)
				await get_tree().create_timer(0.3).timeout
				for i in Toolbox.slots.size():
					var v: String = ["orbit", "bounce", "spin", "sparkle", "rainbow"][i % 5]
					if not Toolbox.has_verb(i, v):
						Toolbox.toggle_verb(i, v)
				current.demo_spawn()
				await get_tree().create_timer(1.5).timeout
			_:
				show_screen(name)
				await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		if current_name == "stage":
			print("PERF ", name, ": ", current.perf_breakdown())
		if name == "stage" and current.syphon_available():
			# Syphon: publish, then read our own server back through a client texture
			current.set_syphon(true)
			var client = ClassDB.instantiate("SyphonTexture")
			client.server_name = "Video Toy"
			await get_tree().create_timer(1.0).timeout
			print("SYPHON server 'Video Toy' read back: ", client.get_size(), " on=", current.syphon_on)
			current.set_syphon(false)
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join(name + ".png"))
		print("captured ", name)
	AudioReact.set_source("off")
	_cleanup_birthday.sort()
	_cleanup_birthday.reverse()
	for idx in _cleanup_birthday:
		if idx < Toolbox.slots.size():
			Toolbox.remove(idx)
	var cap_slot := Toolbox.index_of("raster-%d" % absi(ProjectSettings.globalize_path("user://_capture_photo.png").hash()))
	if cap_slot >= 0:
		var cap_id: String = Toolbox.slots[cap_slot]["id"]
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Toolbox.slots[cap_slot]["svg_path"]))
		Toolbox.remove(cap_slot)
		Ledger.remove(cap_id)
	var text_slot := Toolbox.index_of("text-%d" % absi("HAPPY BDAY".hash()))
	if text_slot >= 0:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Toolbox.slots[text_slot]["svg_path"]))
		Ledger.remove(Toolbox.slots[text_slot]["id"])
		Toolbox.remove(text_slot)
	for i in range(Palettes.extra.size() - 1, -1, -1):
		if Palettes.extra[i].get("name") == "Capture Photo":
			Palettes.extra.remove_at(i)
			Palettes._save_extra()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://_capture_photo.png"))
	if MidiMap.path != MidiMap.PATH:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MidiMap.path))
		MidiMap.path = MidiMap.PATH
		MidiMap.load_from_disk()
	Autosave.mark_clean_exit()
	get_tree().quit()
