extends RefCounted
## Evolve (mutations with keep / discard votes) and attract mode.
## Owned by the stage (src/stage_screen.gd), which exposes these as one-line
## delegations; `s` is the stage, whose state stays in one place.

var s: Stage


func _init(stage: Stage) -> void:
	s = stage


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
			s.palette_index = posmod(s.palette_index + (1 if randf() < 0.5 else -1), Palettes.count())
			s._apply_palette()
			return "palette " + str(Palettes.get_palette(s.palette_index)["name"])
		"fx":
			var which := randi() % 3
			if which == 0:
				s._fx.cycle_pixelate()
			elif which == 1:
				s._fx.cycle_kaleido()
			else:
				s._fx.cycle_crt()
			s._refresh_fx()
			return "fx " + s._fx.describe()
		"feedback":
			if not s.feedback or randf() < 0.3:
				s._set_feedback(not s.feedback)
				return "feedback " + ("on" if s.feedback else "off")
			s.fb_rot = clampf(s.fb_rot + randf_range(-0.03, 0.03), -0.15, 0.15)
			s.fb_zoom = clampf(s.fb_zoom + randf_range(-0.02, 0.02), 0.95, 1.12)
			return "feedback twist %.2f zoom %.2f" % [s.fb_rot, s.fb_zoom]
		"glow":
			s._glow.cycle()
			return "glow " + s._glow.describe()
		"scene":
			if randf() < 0.3:
				s.set_scene("")
				return "scene off"
			s.step_scene(1)
			return "scene " + str(Scenes.get_scene(Scenes.current).get("name", "?"))
		"key":
			s._fx.cycle_key()
			s._refresh_fx()
			return "key " + s._fx.KEY_MODES[s._fx.key_mode]
		"slit":
			s._fx.cycle_slit()
			s._refresh_fx()
			return "slit " + s._fx.SLIT_MODES[s._fx.slit_mode]
		"layer":
			var li := 1 + randi() % (s.LAYER_COUNT - 1)
			s._layers[li]["blend"] = randi() % s.BLENDS.size()
			s._apply_layers()
			return "layer %d %s" % [li + 1, s.BLENDS[s._layers[li]["blend"]]]
		_:
			s.cam_orbit = clampf(s.cam_orbit + randf_range(-0.3, 0.3), -1.0, 1.0)
			s.cam_roll = clampf(s.cam_roll + randf_range(-0.2, 0.2), -1.0, 1.0)
			return "camera orbit %.2f roll %.2f" % [s.cam_orbit, s.cam_roll]


func set_evolve(on: bool) -> void:
	s.evolve = on
	s._evolve_timer = 0.0
	s._evolve_beats = 0
	s._evolve_last = ""
	if on:
		s._evolve_base = s.snapshot()
		s._steal_note = "evolve: mutating every %d beats / %.0f s — Enter keeps, Shift+Enter discards" % [s.EVOLVE_BEATS, s.EVOLVE_SECONDS]
	else:
		s._steal_note = ""
	s._update_hud()


func evolve_step() -> void:
	s._evolve_base = s.snapshot()                  # the previous mutation stands
	s._evolve_last = mutate()
	s._steal_note = "evolve: " + s._evolve_last + "   (Enter keep · Shift+Enter discard)"
	s._update_hud()


func evolve_keep() -> void:
	s._evolve_base = s.snapshot()
	s._steal_note = "kept: " + s._evolve_last
	s._update_hud()


func evolve_discard() -> void:
	if not s._evolve_base.is_empty():
		s.restore(s._evolve_base, 0.3)
	s._steal_note = "discarded: " + s._evolve_last
	s._evolve_last = ""
	s._update_hud()


# ---------------- attract ----------------
## Idle show: every ATTRACT_SECONDS a random saved preset (or three mutations
## when there are none), a slow camera orbit and the monitor on. Any input
## ends it and puts the stage back the way it was.
func set_attract(on: bool) -> void:
	if on == s.attract:
		return
	s.attract = on
	s._attract_timer = 0.0
	if on:
		s._attract_base = s.snapshot()
		s.cam_orbit = 0.25 if s.cam_orbit == 0.0 else s.cam_orbit
		if not s._monitor.visible:
			s.set_monitor(true)
		attract_step()
	else:
		if not s._attract_base.is_empty():
			s.restore(s._attract_base, 0.5)
		s._steal_note = ""
	s._update_hud()


func attract_step() -> void:
	var saved: Array = Presets.filled(Presets.PATH, s.bank)
	if saved.is_empty():
		var notes: Array = []
		for i in 3:
			notes.append(mutate())
		s._steal_note = "attract: " + ", ".join(notes)
	else:
		var n: int = saved[randi() % saved.size()]
		s.restore(Presets.get_preset(n, Presets.PATH, s.bank), maxf(s.preset_fade, 1.0))
		s._steal_note = "attract: preset %d.%d" % [s.bank + 1, n]
	s._update_hud()


func _tick_modes(delta: float) -> void:
	s._idle += delta
	if not s.attract and s._idle >= s.IDLE_ATTRACT:
		set_attract(true)
	if s.attract:
		s._attract_timer += delta
		if s._attract_timer >= s.ATTRACT_SECONDS:
			s._attract_timer = 0.0
			attract_step()
	if s.evolve:
		if AudioReact.active():
			if AudioReact.beat_env >= 1.0 and s._evolve_timer <= 0.0:
				s._evolve_beats += 1
				s._evolve_timer = 0.15
				if s._evolve_beats >= s.EVOLVE_BEATS:
					s._evolve_beats = 0
					evolve_step()
			s._evolve_timer = maxf(0.0, s._evolve_timer - delta)
		else:
			s._evolve_timer += delta
			if s._evolve_timer >= s.EVOLVE_SECONDS:
				s._evolve_timer = 0.0
				evolve_step()
