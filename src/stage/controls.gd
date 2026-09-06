extends RefCounted
## The learnable param / action tables, control dispatch, the timeline and the clock ticks.
## Owned by the stage (src/stage_screen.gd), which exposes these as one-line
## delegations; `s` is the stage, whose state stays in one place.

var s: Stage


func _init(stage: Stage) -> void:
	s = stage


func _tick_clock() -> void:
	if Clock.lock_scenes and Clock.running and Scenes.current != "":
		var want := Clock.bpm / 120.0
		if not is_equal_approx(want, Scenes.speed):
			s.set_scene_knobs(want, Scenes.scale, Scenes.bias)
	if s._play_pending and s.timeline.has_loop():
		if not Clock.running or Clock.until_next_bar() <= s.get_process_delta_time() * 1.5:
			s._play_pending = false
			s.timeline.start_play(s._clock)
			s._steal_note = "looping %.1f s on the bar" % s.timeline.length
			s._update_hud()


# ---------------- credits ----------------
## Distinct slot ids of everything on stage (actors, riders, solids, formations).
func midi_params() -> Array:
	return [
		{"id": "fb_zoom", "label": "Feedback zoom", "set": func(v): s.fb_zoom = lerpf(0.90, 1.20, v)},
		{"id": "gravity", "label": "Gravity (Physics icons)", "set": func(v): s.set_gravity(v * 2.0)},
		{"id": "fb_twist", "label": "Feedback twist", "set": func(v): s.fb_rot = lerpf(-0.15, 0.15, v)},
		{"id": "fb_fade", "label": "Feedback fade", "set": func(v): s.fb_fade = lerpf(0.5, 0.995, v)},
		{"id": "pixelate", "label": "Pixelate size", "set": func(v):
			s._fx.pixel_step = s._step(v, s._fx.PIXEL_STEPS.size())
			s._fx._push()
			s._refresh_fx()},
		{"id": "kaleido", "label": "Kaleidoscope", "set": func(v):
			s._fx.kaleido_step = s._step(v, s._fx.KALEIDO_STEPS.size())
			s._fx._push()
			s._refresh_fx()},
		{"id": "crt", "label": "CRT", "set": func(v):
			s._fx.crt_level = s._step(v, 3)
			s._fx._push()
			s._refresh_fx()},
		{"id": "key_mode", "label": "Key mode", "set": func(v):
			s._fx.key_mode = s._step(v, s._fx.KEY_MODES.size())
			s._fx._push()
			s._refresh_fx()},
		{"id": "key_threshold", "label": "Key threshold", "set": func(v):
			s._fx.key_threshold = v
			s._fx._push()
			s._refresh_fx()},
		{"id": "slit", "label": "Slit-scan mode", "set": func(v):
			s._fx.slit_mode = s._step(v, s._fx.SLIT_MODES.size())
			s._fx._push()
			s._refresh_fx()},
		{"id": "monitor", "label": "Monitor size", "set": func(v):
			s._monitor.size_step = s._step(v, s._monitor.SIZES.size())
			s._monitor._apply_scale()},
		{"id": "palette", "label": "Palette", "set": func(v):
			var i := s._step(v, Palettes.count())
			if i != s.palette_index:
				s.palette_index = i
				s._apply_palette()},
		{"id": "slot", "label": "Toolbox slot", "set": func(v):
			if not Toolbox.slots.is_empty():
				Toolbox.select(s._step(v, Toolbox.slots.size()))},
		{"id": "audio_gain", "label": "Audio gain", "set": func(v): AudioReact.gain = lerpf(0.25, 4.0, v)},
		{"id": "glow", "label": "Glow", "set": func(v):
			s._glow.set_level(s._step(v, 3))
			s._update_hud()},
		{"id": "ascii", "label": "ASCII mode", "set": func(v):
			s._ascii.set_mode(s._step(v, 3))
			s._update_hud()},
		{"id": "ascii", "label": "ASCII mode", "set": func(v):
			s._ascii.set_mode(s._step(v, 3))
			s._update_hud()},
		{"id": "scene", "label": "Scene", "set": func(v):
			var n := Scenes.ALL.size() + 1
			var i := s._step(v, n)
			s.set_scene("" if i == 0 else Scenes.ALL[i - 1]["id"])},
		{"id": "scene_speed", "label": "Scene speed", "set": func(v): s.set_scene_knobs(lerpf(0.1, 4.0, v), Scenes.scale, Scenes.bias)},
		{"id": "scene_scale", "label": "Scene scale", "set": func(v): s.set_scene_knobs(Scenes.speed, lerpf(0.3, 4.0, v), Scenes.bias)},
		{"id": "scene_bias", "label": "Scene colour bias", "set": func(v): s.set_scene_knobs(Scenes.speed, Scenes.scale, v)},
		{"id": "fb_warp", "label": "Feedback warp", "set": func(v): s.fb_warp = v},
		{"id": "fb_warp_speed", "label": "Feedback warp speed", "set": func(v): s.fb_warp_speed = lerpf(0.1, 4.0, v)},
		{"id": "fb_dx", "label": "Feedback drift X", "set": func(v): s.fb_drift.x = lerpf(-6.0, 6.0, v)},
		{"id": "fb_dy", "label": "Feedback drift Y", "set": func(v): s.fb_drift.y = lerpf(-6.0, 6.0, v)},
		{"id": "fb_sx", "label": "Feedback stretch X", "set": func(v): s.fb_stretch.x = lerpf(0.9, 1.1, v)},
		{"id": "fb_sy", "label": "Feedback stretch Y", "set": func(v): s.fb_stretch.y = lerpf(0.9, 1.1, v)},
		{"id": "cam_orbit", "label": "Camera orbit speed", "set": func(v): s.cam_orbit = lerpf(-1.5, 1.5, v)},
		{"id": "cam_dolly", "label": "Camera dolly", "set": func(v): s.cam_dolly = lerpf(3.0, 14.0, v)},
		{"id": "cam_roll", "label": "Camera roll", "set": func(v): s.cam_roll = lerpf(-PI, PI, v)},
		{"id": "cam_height", "label": "Camera height", "set": func(v): s.cam_height = lerpf(-4.0, 4.0, v)},
		{"id": "particles_flow", "label": "Particle flow", "set": func(v): s.particles_flow = lerpf(0.0, 2.0, v)},
		{"id": "particles_attract", "label": "Particle attract (-1..1)", "set": func(v): s.particles_attract = lerpf(-1.0, 1.0, v)},
		{"id": "rd_feed", "label": "Reaction feed", "set": func(v):
			s.rd_feed = lerpf(0.01, 0.09, v)
			s._push_rd()},
		{"id": "rd_kill", "label": "Reaction kill", "set": func(v):
			s.rd_kill = lerpf(0.04, 0.07, v)
			s._push_rd()},
		{"id": "bpm", "label": "Internal clock BPM", "set": func(v):
			Clock.bpm = lerpf(60.0, 200.0, v)
			s._update_hud()},
		{"id": "bank", "label": "Preset bank", "set": func(v): s.set_bank(s._step(v, Presets.BANKS))},
		{"id": "preset_fade", "label": "Preset crossfade time", "set": func(v):
			s.preset_fade = lerpf(0.0, 5.0, v)
			s._update_hud()},
		{"id": "preset_morph", "label": "Preset morph (to next)", "set": s.morph},
		{"id": "active_layer", "label": "Active layer", "set": func(v): s.set_active_layer(s._step(v, s.LAYER_COUNT))},
		{"id": "layer_opacity", "label": "Layer opacity (active)", "set": func(v): s.set_layer_opacity(v)},
	]


func midi_actions() -> Array:
	var out: Array = [
		{"id": "spawn", "label": "Spawn icon", "do": func(): s.spawn_at(Vector2(randf_range(100, s.WORLD.x - 100), randf_range(100, s.WORLD.y - 100)))},
		{"id": "spawn_solid", "label": "Spawn 3D solid", "do": func(): s.spawn_solid()},
		{"id": "clear", "label": "Clear stage", "do": func():
			s.clear_actors()
			for a in s._solids.get_children() + s._formations.get_children():
				a.queue_free()},
		{"id": "feedback", "label": "Feedback on/off", "do": func(): s._set_feedback(not s.feedback)},
		{"id": "next_palette", "label": "Next palette", "do": func():
			s.palette_index = (s.palette_index + 1) % Palettes.count()
			s._apply_palette()},
		{"id": "chroma", "label": "Next key mode", "do": func():
			s._fx.cycle_key()
			s._refresh_fx()},
		{"id": "slit", "label": "Next slit-scan mode", "do": func():
			s._fx.cycle_slit()
			s._refresh_fx()},
		{"id": "quantise", "label": "Palette quantise on/off", "do": func():
			s._fx.toggle_quantize()
			s._refresh_fx()},
		{"id": "dither", "label": "Dither on/off", "do": func():
			s._fx.toggle_dither()
			s._refresh_fx()},
		{"id": "monitor", "label": "Monitor on/off", "do": func(): s.set_monitor(not s._monitor.visible)},
		{"id": "next_shape", "label": "Next 3D shape", "do": s.cycle_shape},
		{"id": "webcam", "label": "Next webcam mode", "do": s.cycle_webcam},
		{"id": "steal_palette", "label": "Steal palette", "do": s.steal_palette},
		{"id": "audio_source", "label": "Next audio source", "do": func():
			AudioReact.cycle_source()
			s._update_hud()},
		{"id": "recolor", "label": "Recolor slot", "do": s._recolor},
	]
	out.append({"id": "pinata", "label": "Pinata: burst a random Sparkle icon", "do": s.pinata_random})
	out.append({"id": "next_word", "label": "Word lists: next word", "do": s.advance_words})
	out.append({"id": "syphon", "label": "Syphon output on/off", "do": func(): s.set_syphon(not s.syphon_on)})
	out.append({"id": "clock_internal", "label": "Internal clock on/off", "do": func():
		Clock.toggle_internal()
		s._update_hud()})
	out.append({"id": "clock_lock_scenes", "label": "Lock scenes to BPM on/off", "do": func():
		Clock.lock_scenes = not Clock.lock_scenes
		s._update_hud()})
	out.append({"id": "screenshot", "label": "Screenshot with credits", "do": func(): s.screenshot_with_credits()})
	out.append({"id": "ticker", "label": "Credits ticker on/off", "do": func(): s.set_ticker(not s.ticker_on)})
	out.append({"id": "credits_roll", "label": "Credits roll start/stop", "do": func():
		if s._roll.visible:
			s.stop_credits_roll()
		else:
			s.start_credits_roll()})
	out.append({"id": "ascii", "label": "ASCII mode off/mono/colour", "do": func():
		s._ascii.cycle()
		s._update_hud()})
	out.append({"id": "render_clip", "label": "Render a 20 s clip (offline)", "do": func(): s.get_parent().render_clip(20.0)})
	out.append({"id": "ascii", "label": "ASCII mode off/mono/colour", "do": func():
		s._ascii.cycle()
		s._update_hud()})
	out.append({"id": "render_clip", "label": "Render a 20 s clip (offline)", "do": func(): s.get_parent().render_clip(20.0)})
	out.append({"id": "panic", "label": "PANIC: known-good look", "do": s.panic})
	out.append({"id": "gravity_toggle", "label": "Gravity on / off", "do": func(): s.set_gravity(0.0 if s.gravity > 0.0 else 1.0)})
	out.append({"id": "play_sound", "label": "Play the selected slot's sound", "do": func(): s.play_slot_sound()})
	out.append({"id": "blackout", "label": "Blackout on/off", "do": s.toggle_blackout})
	out.append({"id": "quality", "label": "Quality lock: cycle", "do": s.cycle_quality_lock})
	out.append({"id": "particles", "label": "Particle field on/off", "do": func(): s.set_particles(not s.particles_on)})
	out.append({"id": "scatter", "label": "Scatter particles", "do": s.scatter_particles})
	out.append({"id": "rd", "label": "Next reaction-diffusion preset", "do": s.cycle_rd})
	out.append({"id": "timeline_record", "label": "Timeline: record on/off", "do": toggle_record})
	out.append({"id": "timeline_play", "label": "Timeline: loop on/off", "do": toggle_play})
	out.append({"id": "mosaic", "label": "Mosaic of selected slot", "do": func(): s.spawn_mosaic()})
	out.append({"id": "evolve", "label": "Evolve on/off", "do": func(): s.set_evolve(not s.evolve)})
	out.append({"id": "evolve_keep", "label": "Evolve: keep", "do": s.evolve_keep})
	out.append({"id": "evolve_discard", "label": "Evolve: discard", "do": s.evolve_discard})
	out.append({"id": "mutate", "label": "Mutate once", "do": func():
		s._steal_note = "mutation: " + s.mutate()
		s._update_hud()})
	out.append({"id": "attract", "label": "Attract mode on/off", "do": func(): s.set_attract(not s.attract)})
	out.append({"id": "next_layer", "label": "Next layer", "do": func(): s.set_active_layer(s.active_layer + 1)})
	out.append({"id": "next_blend", "label": "Next blend mode (active layer)", "do": s.cycle_blend})
	out.append({"id": "draw_mode", "label": "Draw mode on/off", "do": func():
		s.draw_mode = not s.draw_mode
		s._update_hud()})
	out.append({"id": "spawn_formation", "label": "Spawn formation", "do": func(): s.spawn_formation()})
	out.append({"id": "next_formation", "label": "Next formation kind", "do": s.cycle_formation})
	out.append({"id": "cam_reset", "label": "Reset camera", "do": s.reset_camera})
	out.append({"id": "cam_auto", "label": "Camera slow orbit on/off", "do": func():
		s.cam_orbit = 0.0 if s.cam_orbit != 0.0 else 0.35
		s._update_hud()})
	out.append({"id": "next_scene", "label": "Next scene", "do": func(): s.step_scene(1)})
	out.append({"id": "prev_scene", "label": "Previous scene", "do": func(): s.step_scene(-1)})
	out.append({"id": "scene_off", "label": "Scene off", "do": func(): s.set_scene("")})
	out.append({"id": "warp_reset", "label": "Reset feedback warp", "do": func():
		s.fb_warp = 0.0
		s.fb_drift = Vector2.ZERO
		s.fb_stretch = Vector2.ONE
		s._update_hud()})
	out.append({"id": "glow", "label": "Glow off/soft/heavy", "do": func():
		s._glow.cycle()
		s._update_hud()})
	out.append({"id": "next_preset", "label": "Next preset (in bank)", "do": func(): s.step_preset(1)})
	out.append({"id": "prev_preset", "label": "Previous preset (in bank)", "do": func(): s.step_preset(-1)})
	out.append({"id": "next_bank", "label": "Next bank", "do": func(): s.set_bank(s.bank + 1)})
	out.append({"id": "prev_bank", "label": "Previous bank", "do": func(): s.set_bank(s.bank - 1)})
	for i in Presets.COUNT:
		out.append({"id": "preset_%d" % (i + 1), "label": "Recall preset %d" % (i + 1), "do": func(): s.recall_preset(i + 1)})
	for i in Toolbox.MAX_SLOTS:
		out.append({"id": "slot_%d" % (i + 1), "label": "Select slot %d" % (i + 1), "do": func(): Toolbox.select(i)})
	for v in Verbs.all():
		out.append({"id": "verb_" + v["id"], "label": "Toggle verb: " + v["name"], "do": func():
			if not Toolbox.current().is_empty():
				Toolbox.toggle_verb(Toolbox.selected, v["id"])})
	return out


func _build_midi() -> void:
	s._midi_panel = s.MidiPanelScript.new()
	s._midi_panel.params = midi_params()
	s._midi_panel.actions = midi_actions()
	s._midi_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	s._midi_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	s._midi_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	s._midi_panel.visible = false
	s.add_child(s._midi_panel)
	MidiMap.param.connect(_on_midi_param)
	MidiMap.action.connect(_on_midi_action)
	MidiMap.activity.connect(_on_midi_activity)


func _on_midi_activity(text: String) -> void:
	if is_instance_valid(s):
		s._midi_last = text
		s._update_hud()


## The stage is going away: unhook from the control table's signals.
func teardown() -> void:
	for pair in [[MidiMap.param, _on_midi_param], [MidiMap.action, _on_midi_action], [MidiMap.activity, _on_midi_activity]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _on_midi_param(id: String, value: float) -> void:
	if s.timeline.recording and MidiMap.last_source != "audio":
		s.timeline.record("param", id, value, s._clock)
	for p in midi_params():
		if p["id"] == id:
			p["set"].call(value)
			s._update_hud()
			return


func _on_midi_action(id: String) -> void:
	if s.timeline.recording and MidiMap.last_source != "audio" and not id.begins_with("timeline"):
		s.timeline.record("action", id, 1.0, s._clock)
	for a in midi_actions():
		if a["id"] == id:
			a["do"].call()
			s._update_hud()
			return


# ---------------- timeline ----------------
func toggle_record() -> void:
	if s.timeline.recording:
		s.timeline.stop_record(s._clock)
		if Clock.running:
			s.timeline.length = Clock.quantise_to_bars(s.timeline.length)
		s.timeline.save()
		s._steal_note = "recorded %.1f s, %d events — Shift+P loops it" % [s.timeline.length, s.timeline.events.size()]
	else:
		s.timeline.start_record(s._clock)
		s._steal_note = "REC — move controllers; Shift+R stops (60 s max)"
	s._update_hud()


func toggle_play() -> void:
	if s.timeline.playing or s._play_pending:
		s.timeline.stop_play()
		s._play_pending = false
		s._steal_note = "loop stopped"
	else:
		if not s.timeline.has_loop():
			s.timeline.load()
		if s.timeline.has_loop():
			if Clock.running:
				s._play_pending = true
				s._steal_note = "loop starts on the next bar (%.1f s)" % Clock.until_next_bar()
			else:
				s.timeline.start_play(s._clock)
				s._steal_note = "looping %.1f s of gestures" % s.timeline.length
		else:
			s._steal_note = "nothing recorded — Shift+R records controller moves"
	s._update_hud()


func _tick_timeline(delta: float) -> void:
	s._clock += delta
	if s.timeline.recording and s._clock - s.timeline._rec_start >= Timeline.MAX:
		toggle_record()
	for e in s.timeline.due(s._clock):
		if e["kind"] == "param":
			for p in midi_params():
				if p["id"] == e["id"]:
					p["set"].call(float(e["value"]))
		else:
			for a in midi_actions():
				if a["id"] == e["id"]:
					a["do"].call()


func toggle_midi_panel() -> void:
	s._midi_panel.visible = not s._midi_panel.visible
	if s._midi_panel.visible:
		s._help.close()                                   # the panel is wide; give it the room
	if s._midi_panel.visible:
		s._midi_panel.refresh()
	else:
		MidiMap.disarm()


# ---------------- HUD ----------------
