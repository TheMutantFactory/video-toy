extends RefCounted
## Snapshots, presets and banks, the crossfade of everything, morph.
## Owned by the stage (src/stage_screen.gd), which exposes these as one-line
## delegations; `s` is the stage, whose state stays in one place.

var s: Stage


func _init(stage: Stage) -> void:
	s = stage


func snapshot() -> Dictionary:
	var verbs := {}
	for sl in Toolbox.slots:
		verbs[str(sl["id"])] = {"verbs": sl.get("verbs", []).duplicate(), "color_index": int(sl.get("color_index", 0))}
	return {
		"palette": s.palette_index,
		"feedback": {"on": s.feedback, "zoom": s.fb_zoom, "rot": s.fb_rot, "fade": s.fb_fade,
			"delay": s.fb_delay, "blur": s.fb_blur, "hue": s.fb_hue, "sat": s.fb_sat, "displace": s.fb_displace, "disp_src": s.fb_disp_src, "loop": s.loop_mask(),
			"cleanup": s.fb_cleanup, "cleanup_rule": s.fb_cleanup_rule,
			"jag": s.fb_jag, "jag_sides": s.fb_jag_sides, "jag_mode": s.fb_jag_mode, "zones": s.fb_zones, "zone_spread": s.fb_zone_spread},
		"fx": {"pixel": s._fx.pixel_step, "kaleido": s._fx.kaleido_step, "crt": s._fx.crt_level,
			"key": s._fx.key_mode, "key_threshold": s._fx.key_threshold, "slit": s._fx.slit_mode,
			"quantize": s._fx.quantize, "dither": s._fx.dither},
		"glow": s._glow.level,
		"ascii": s._ascii.mode,
		"monitor": {"on": s._monitor.visible, "size": s._monitor.size_step, "x": s._monitor.position.x, "y": s._monitor.position.y},
		"webcam": s._webcam_mode,
		"shape": s._shape_index,
		"selected": Toolbox.selected,
		"slots": verbs,
		"scene": {"id": Scenes.current, "speed": Scenes.speed, "scale": Scenes.scale, "bias": Scenes.bias},
		"warp": {"amount": s.fb_warp, "speed": s.fb_warp_speed, "dx": s.fb_drift.x, "dy": s.fb_drift.y, "sx": s.fb_stretch.x, "sy": s.fb_stretch.y},
		"camera": {"orbit": s.cam_orbit, "dolly": s.cam_dolly, "roll": s.cam_roll, "height": s.cam_height},
		"formation": s._formation_index,
		"layers": s._layers.map(func(l): return {"blend": l["blend"], "opacity": l["opacity"]}),
		"active_layer": s.active_layer,
		"particles": {"on": s.particles_on, "flow": s.particles_flow, "attract": s.particles_attract, "flux": s.particles_flux, "flux_src": s.flux_src},
		"rd": {"preset": s.rd_preset, "feed": s.rd_feed, "kill": s.rd_kill},
		"physics": {"gravity": s.gravity},
	}


## Apply a snapshot. With `fade` > 0 everything crossfades: continuous values
## lerp over the time, discrete ones flip at the midpoint (StateLerp).
func restore(d: Dictionary, fade := 1.0) -> void:
	if d.is_empty():
		return
	if fade <= 0.0:
		s._xf = {}
		_apply_snapshot(d, true)
		return
	s._xf = {"from": snapshot(), "to": d, "t": 0.0, "dur": fade}


func _tick_crossfade(delta: float) -> void:
	if s._xf.is_empty():
		return
	s._xf["t"] += delta
	var t: float = float(s._xf["t"]) / float(s._xf["dur"])
	if t >= 1.0:
		var to: Dictionary = s._xf["to"]
		s._xf = {}
		_apply_snapshot(to, true)
		return
	_apply_snapshot(StateLerp.mix(s._xf["from"], s._xf["to"], t), false)


func crossfading() -> bool:
	return not s._xf.is_empty()


## Jump to the end of a running crossfade (tests, panic).
func finish_crossfade() -> void:
	if s._xf.is_empty():
		return
	var to: Dictionary = s._xf["to"]
	s._xf = {}
	_apply_snapshot(to, true)


## Immediate apply. `persist` writes the toolbox verbs to disk (skipped on the
## per-frame crossfade path). Every setter is guarded so re-applying the same
## state each frame does not restart particles, webcams or scenes.
func _apply_snapshot(d: Dictionary, persist: bool) -> void:
	var pal := posmod(int(d.get("palette", s.palette_index)), Palettes.count())
	var pal_changed := pal != s.palette_index
	s.palette_index = pal
	var fb: Dictionary = d.get("feedback", {})
	if s._fade_tween:
		s._fade_tween.kill()
	s.fb_zoom = float(fb.get("zoom", s.fb_zoom))
	s.fb_rot = float(fb.get("rot", s.fb_rot))
	s.fb_fade = float(fb.get("fade", s.fb_fade))
	s.fb_delay = clampi(int(fb.get("delay", s.fb_delay)), 0, s.RING - 1)
	s.fb_blur = clampf(float(fb.get("blur", s.fb_blur)), -1.0, 1.0)
	s.fb_hue = clampf(float(fb.get("hue", s.fb_hue)), -0.2, 0.2)
	s.fb_sat = clampf(float(fb.get("sat", s.fb_sat)), 0.8, 1.2)
	s.fb_displace = clampf(float(fb.get("displace", s.fb_displace)), 0.0, 1.0)
	s.fb_disp_src = posmod(int(fb.get("disp_src", s.fb_disp_src)), s.DISP_SOURCES.size())
	s.fb_cleanup = clampf(float(fb.get("cleanup", s.fb_cleanup)), 0.0, 1.0)
	s.fb_cleanup_rule = posmod(int(fb.get("cleanup_rule", s.fb_cleanup_rule)), s.CLEANUP_RULES.size())
	s.fb_jag = clampf(float(fb.get("jag", s.fb_jag)), 0.0, 1.0)
	s.fb_jag_sides = int(fb.get("jag_sides", s.fb_jag_sides)) if s.JAG_SIDES.has(int(fb.get("jag_sides", s.fb_jag_sides))) else s.fb_jag_sides
	s.fb_jag_mode = posmod(int(fb.get("jag_mode", s.fb_jag_mode)), s.JAG_MODES.size())
	s.fb_zones = clampf(float(fb.get("zones", s.fb_zones)), 0.0, 1.0)
	s.fb_zone_spread = clampi(int(fb.get("zone_spread", s.fb_zone_spread)), 1, 7)
	if fb.has("loop"):
		var mask := int(fb["loop"])
		for i in s._layers.size():
			s._layers[i]["loop"] = (mask & (1 << i)) != 0
	var fb_on := bool(fb.get("on", s.feedback))
	if fb_on != s.feedback:
		s._set_feedback(fb_on)
	var fx: Dictionary = d.get("fx", {})
	s._fx.pixel_step = clampi(int(fx.get("pixel", s._fx.pixel_step)), 0, s._fx.PIXEL_STEPS.size() - 1)
	s._fx.kaleido_step = clampi(int(fx.get("kaleido", s._fx.kaleido_step)), 0, s._fx.KALEIDO_STEPS.size() - 1)
	s._fx.crt_level = clampi(int(fx.get("crt", s._fx.crt_level)), 0, 2)
	if fx.has("key"):
		s._fx.key_mode = clampi(int(fx["key"]), 0, s._fx.KEY_MODES.size() - 1)
	elif fx.has("chroma"):
		s._fx.key_mode = 1 if bool(fx["chroma"]) else 0
	s._fx.key_threshold = clampf(float(fx.get("key_threshold", s._fx.key_threshold)), 0.0, 1.0)
	s._fx.slit_mode = clampi(int(fx.get("slit", s._fx.slit_mode)), 0, s._fx.SLIT_MODES.size() - 1)
	s._fx.quantize = bool(fx.get("quantize", s._fx.quantize))
	s._fx.dither = bool(fx.get("dither", s._fx.dither))
	s._fx._push()
	s._glow.set_level(int(d.get("glow", s._glow.level)))
	s._ascii.set_mode(int(d.get("ascii", s._ascii.mode)))
	s._ascii.set_mode(int(d.get("ascii", s._ascii.mode)))
	var mon: Dictionary = d.get("monitor", {})
	var msize := clampi(int(mon.get("size", s._monitor.size_step)), 0, s._monitor.SIZES.size() - 1)
	if msize != s._monitor.size_step:
		s._monitor.size_step = msize
		s._monitor._apply_scale()
	s._monitor.position = Vector2(float(mon.get("x", s._monitor.position.x)), float(mon.get("y", s._monitor.position.y)))
	s._monitor.visible = bool(mon.get("on", s._monitor.visible))
	var wm := int(d.get("webcam", s._webcam_mode))
	if wm != s._webcam_mode:
		s.set_webcam_mode(wm)
	s._shape_index = posmod(int(d.get("shape", s._shape_index)), s.SolidScript.SHAPES.size())
	var cam: Dictionary = d.get("camera", {})
	if not cam.is_empty():
		s.cam_orbit = float(cam.get("orbit", s.cam_orbit))
		s.cam_dolly = float(cam.get("dolly", s.cam_dolly))
		s.cam_roll = float(cam.get("roll", s.cam_roll))
		s.cam_height = float(cam.get("height", s.cam_height))
	s._formation_index = posmod(int(d.get("formation", s._formation_index)), s.FormationScript.KINDS.size())
	var pt: Dictionary = d.get("particles", {})
	if not pt.is_empty():
		s.particles_flow = float(pt.get("flow", s.particles_flow))
		s.particles_attract = float(pt.get("attract", s.particles_attract))
		s.particles_flux = clampf(float(pt.get("flux", s.particles_flux)), 0.0, 1.0)
		s.flux_src = posmod(int(pt.get("flux_src", s.flux_src)), s.FLUX_SOURCES.size())
		var pon := bool(pt.get("on", s.particles_on))
		if pon != s.particles_on:
			s.set_particles(pon)
	var ph: Dictionary = d.get("physics", {})
	if not ph.is_empty() and not is_equal_approx(float(ph.get("gravity", s.gravity)), s.gravity):
		s.set_gravity(float(ph.get("gravity", s.gravity)))
	var rdd: Dictionary = d.get("rd", {})
	if not rdd.is_empty():
		var rp := int(rdd.get("preset", s.rd_preset))
		if rp != s.rd_preset:
			s.set_rd_preset(rp)
		s.rd_feed = float(rdd.get("feed", s.rd_feed))
		s.rd_kill = float(rdd.get("kill", s.rd_kill))
		s._push_rd()
	var lay: Array = d.get("layers", [])
	for i in mini(lay.size(), s._layers.size()):
		if lay[i] is Dictionary:
			s._layers[i]["blend"] = clampi(int(lay[i].get("blend", 0)), 0, s.BLENDS.size() - 1)
			s._layers[i]["opacity"] = clampf(float(lay[i].get("opacity", 1.0)), 0.0, 1.0)
	s._apply_layers()
	s.active_layer = posmod(int(d.get("active_layer", s.active_layer)), s.LAYER_COUNT)
	var w: Dictionary = d.get("warp", {})
	if not w.is_empty():
		s.fb_warp = float(w.get("amount", s.fb_warp))
		s.fb_warp_speed = float(w.get("speed", s.fb_warp_speed))
		s.fb_drift = Vector2(float(w.get("dx", s.fb_drift.x)), float(w.get("dy", s.fb_drift.y)))
		s.fb_stretch = Vector2(float(w.get("sx", s.fb_stretch.x)), float(w.get("sy", s.fb_stretch.y)))
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
		s._scene_layer.apply_knobs()
		var sid := str(sc.get("id", Scenes.current))
		if sid != Scenes.current:
			s.set_scene(sid, 0.8)
	if pal_changed or verbs_changed:
		s._apply_palette()
	s._refresh_fx()
	s._update_hud()


# ---------------- banks, stepping, morph ----------------
func set_bank(b: int) -> void:
	s.bank = posmod(b, Presets.BANKS)
	s._steal_note = "bank %d: %d presets" % [s.bank + 1, Presets.filled(Presets.PATH, s.bank).size()]
	s._update_hud()


func step_preset(step: int) -> void:
	var n := Presets.neighbour(s.last_preset, step, Presets.PATH, s.bank)
	if n == 0:
		s._steal_note = "bank %d is empty — Shift+F1..F12 saves" % (s.bank + 1)
		s._update_hud()
		return
	recall_preset(n)


func cycle_fade() -> void:
	var steps := [0.0, 0.5, 1.0, 2.0, 4.0]
	var i := steps.find(s.preset_fade)
	s.preset_fade = steps[(i + 1) % steps.size()] if i >= 0 else 1.0
	s._steal_note = "preset crossfade %.1f s" % s.preset_fade
	s._update_hud()


## 0..1 scrub from the last recalled preset toward the next filled one.
func morph(v: float) -> void:
	if s._morph_a.is_empty():
		s._morph_a = snapshot()
	var n := Presets.neighbour(s.last_preset, 1, Presets.PATH, s.bank)
	if n == 0:
		return
	s._xf = {}
	_apply_snapshot(StateLerp.mix(s._morph_a, Presets.get_preset(n, Presets.PATH, s.bank), v), false)


func save_preset(i: int) -> void:
	Presets.save(i, snapshot(), Presets.PATH, s.bank)
	s.last_preset = i
	s._morph_a = snapshot()
	s._steal_note = "saved preset %d in bank %d (F%d)" % [i, s.bank + 1, i]
	s._update_hud()


func recall_preset(i: int) -> void:
	var d := Presets.get_preset(i, Presets.PATH, s.bank)
	if d.is_empty():
		s._steal_note = "preset %d in bank %d is empty — Shift+F%d saves" % [i, s.bank + 1, i]
	else:
		restore(d, s.preset_fade)
		s.last_preset = i
		s._morph_a = d.duplicate(true)
		s._steal_note = "preset %d.%d%s" % [s.bank + 1, i, ("  (crossfade %.1f s)" % s.preset_fade) if s.preset_fade > 0.0 else ""]
	s._update_hud()


# ---------------- MIDI ----------------
## Continuous params: id, label, setter(0..1). Actions: id, label, callable.
