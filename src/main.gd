extends Node
## Screen router. Each screen is a full-rect Control built in code that emits
## `navigate(name)`; the router swaps it out. `--capture DIR` (after `--` on the
## command line) screenshots every screen into DIR and quits — used for proof.

const SCREENS := {
	"start": "res://src/start_screen.gd",
	"search": "res://src/search_screen.gd",
	"stage": "res://src/stage_screen.gd",
	"settings": "res://src/settings_screen.gd",
}
const MenuOverlay = preload("res://src/menu_overlay.gd")

var current: Control
var current_name := ""
var menu: CanvasLayer


func _ready() -> void:
	get_window().title = "Video Toy"
	menu = MenuOverlay.new()
	menu.navigate.connect(show_screen)
	add_child(menu)
	var args := OS.get_cmdline_user_args()
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
	# 3D solids need the autoloads, so they are checked here, not in smoke.gd
	var Solid = load("res://src/solid.gd")
	var ok_shapes: bool = Solid != null and Solid.SHAPES.size() == 5
	if ok_shapes:
		for k in Solid.SHAPES:
			if Solid.make_mesh(k) == null or Solid.uv_scale(k) == Vector3.ONE:
				ok_shapes = false
	if ok_shapes:
		print("PASS every solid shape has a mesh and uv tiling")
	else:
		fails += 1
		printerr("FAIL solid shapes")
	get_tree().quit(1 if fails > 0 else 0)


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
	var shots := SCREENS.keys() + ["menu", "attribution", "feedback", "pixelate", "quantise", "kaleido", "chroma", "crt", "monitor", "solids", "midi"]
	for name in shots:
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
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join(name + ".png"))
		print("captured ", name)
	if MidiMap.path != MidiMap.PATH:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MidiMap.path))
		MidiMap.path = MidiMap.PATH
		MidiMap.load_from_disk()
	get_tree().quit()
