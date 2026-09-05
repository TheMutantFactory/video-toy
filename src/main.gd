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


func _ready() -> void:
	get_window().title = "Video Toy"
	menu = MenuOverlay.new()
	menu.navigate.connect(show_screen)
	add_child(menu)
	args = OS.get_cmdline_user_args()
	var cap := args.find("--capture")
	if args.has("--selftest"):
		_selftest()
	elif cap >= 0 and cap + 1 < args.size():
		_capture_all(args[cap + 1])
	else:
		show_screen("start")


func show_screen(name: String) -> void:
	if name == "quit":
		get_tree().quit()
		return
	if name == "attribution":
		menu.show_attribution()
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


## Headless-safe: instantiate every screen and the menu, then quit. Fails loudly
## (non-zero exit) if any screen errors while building itself.
func _selftest() -> void:
	var fails := 0
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
	st._idle = st.IDLE_ATTRACT + 1.0
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
	var shots := SCREENS.keys() + ["menu", "attribution", "feedback", "pixelate", "quantise", "kaleido", "chroma", "crt", "monitor", "solids", "midi", "audio", "raster", "glow", "scene_stage", "solids3d", "text_flock", "layers", "draw", "keyers", "slitscan", "mosaic", "attractors", "particles", "rd", "two_player", "blackout"]
	for name in shots:
		if only != "" and name != only and name != "stage":
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
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join(name + ".png"))
		print("captured ", name)
	AudioReact.set_source("off")
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
	get_tree().quit()
