extends RefCounted
## Webcam, video slots, live and cycling words, mosaic, raster drops, file drops, Syphon output.
## Owned by the stage (src/stage_screen.gd), which exposes these as one-line
## delegations; `s` is the stage, whose state stays in one place.

var s: Stage


func _init(stage: Stage) -> void:
	s = stage


func _build_webcam() -> void:
	s._webcam_vp = SubViewport.new()
	s._webcam_vp.size = Vector2i(960, 540)
	s._webcam_vp.transparent_bg = false
	s._webcam_vp.disable_3d = true
	s._webcam_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	s.add_child(s._webcam_vp)
	s._webcam = s.WebcamScript.new()
	s._webcam.box = Vector2(960, 540)
	s._webcam.position = Vector2(480, 270)
	s._webcam.set_process(false)
	s._webcam_vp.add_child(s._webcam)
	s._webcam_sprite = Sprite2D.new()
	s._webcam_sprite.texture = s._webcam_vp.get_texture()
	s._webcam_sprite.position = Vector2(s.WORLD) * 0.5
	s._webcam_sprite.scale = Vector2(2, 2)
	s._webcam_sprite.z_index = -2
	s._webcam_sprite.visible = false
	s._world.add_child(s._webcam_sprite)


func webcam_mode() -> String:
	return s.WEBCAM_MODES[s._webcam_mode]


func set_webcam_mode(i: int) -> void:
	if posmod(i, s.WEBCAM_MODES.size()) == s._webcam_mode and s._webcam != null and (s._webcam_mode == 0) == (not s._webcam.is_processing()):
		s._refresh_fx()
		return
	s._webcam_mode = posmod(i, s.WEBCAM_MODES.size())
	var on := s._webcam_mode > 0
	s._webcam.set_process(on)
	if on:
		s._webcam.start()
	else:
		s._webcam.stop()
	s._webcam_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	s._webcam_sprite.visible = webcam_mode() == "layer"
	s._fx.set_live_backdrop(s._webcam_vp.get_texture() if webcam_mode() == "backdrop" else null)
	if webcam_mode() == "backdrop" and s._fx.key_mode == 0:
		s._fx.key_mode = 1
		s._fx._push()
	s._refresh_fx()


func cycle_webcam() -> void:
	set_webcam_mode(s._webcam_mode + 1)


## S: a palette from the selected raster slot, or the webcam if it is on.
func steal_palette() -> void:
	var img: Image = null
	var name := ""
	var slot := Toolbox.current()
	if s._webcam_mode > 0 and s._webcam.is_live():
		img = s._webcam_vp.get_texture().get_image()
		name = "Webcam"
	elif not slot.is_empty() and Toolbox.is_raster_slot(slot):
		var tex := IconMedia.texture_for(str(slot.get("svg_path", "")))
		if tex:
			img = tex.get_image()
			name = str(slot.get("term", "image")).capitalize()
	if img == null:
		s._steal_note = "select a raster slot (or turn the webcam on) to steal a palette"
		s._update_hud()
		return
	var p := Palettes.extract(img, name)
	s.palette_index = Palettes.add_extra(p)
	s._apply_palette()
	s._steal_note = "stole palette “%s” (%d colours)" % [name, p["ring"].size()]
	s._update_hud()


# ---------------- 3D layer ----------------
## A transparent 3D viewport composited into the world as a sprite, so solids
## get feedback, effects and the monitor exactly like the 2D actors.
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
			cand_colors.append(Palettes.color(s.palette_index, int(Toolbox.slots[i].get("color_index", i))))
	if cand_slots.is_empty():
		s._steal_note = "mosaic needs at least one icon or word in the toolbox"
		s._update_hud()
		return 0
	var is_raster := Toolbox.is_raster_slot(slot)
	var g := Mosaic.grid_size(img)
	var box := Vector2(1600, 900)
	var cell := minf(box.x / g.x, box.y / g.y)
	var origin := (Vector2(s.WORLD) - Vector2(g) * cell) * 0.5
	var layer := s.layer_actors()
	for c in cells:
		var src: Dictionary = slot if not is_raster else cand_slots[Mosaic.nearest(c["color"], cand_colors)]
		var a := Node2D.new()
		a.set_script(s.ActorScript)
		a.setup(src, origin + Vector2(c["u"] * g.x, c["v"] * g.y) * cell, s.palette_index, Rect2(Vector2.ZERO, Vector2(s.WORLD)))
		var lum: float = c["lum"] if is_raster else 1.0
		var size_px := cell * lerpf(0.45, 1.05, lum)
		a.base_scale = size_px / maxf(a._sprite.texture.get_size().x, 1.0)
		a._sprite.scale = Vector2.ONE * a.base_scale
		a.orbit_radius = cell * 0.6
		layer.add_child(a)
	s._steal_note = "mosaic: %d cells of “%s”" % [cells.size(), slot.get("term", "")]
	s._update_hud()
	return cells.size()


# ---------------- evolve ----------------
## One random change to the stage. Returns a description for the HUD.
func _sync_videos() -> void:
	var wanted := {}
	for sl in Toolbox.slots:
		if str(sl.get("kind", "")) == "video":
			wanted[str(sl["svg_path"])] = true
	for pth in s._videos.keys():
		if not wanted.has(pth):
			IconMedia.unregister_live(pth)
			s._videos[pth]["vp"].queue_free()
			s._videos.erase(pth)
	for pth in wanted:
		if s._videos.has(pth):
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(480, 270)
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		s.add_child(vp)
		var player := VideoStreamPlayer.new()
		player.size = Vector2(480, 270)
		player.expand = true
		player.loop = true
		player.autoplay = true
		var stream := VideoStreamTheora.new()
		stream.file = pth
		player.stream = stream
		vp.add_child(player)
		s._videos[pth] = {"vp": vp, "player": player}
		IconMedia.register_live(pth, vp.get_texture())
	if not wanted.is_empty():
		s._hotbar.refresh()


## Live words (clock, countdown) re-render when their text changes; cycling
## word lists advance on the beat, or every 2 s without one.
func _tick_words(delta: float) -> void:
	s._live_timer += delta
	if s._live_timer >= 0.5:
		s._live_timer = 0.0
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
	var beat := AudioReact.active() and AudioReact.beat_env > s._cycle_last_beat
	s._cycle_last_beat = AudioReact.beat_env
	s._cycle_timer += delta
	var step := beat or (not AudioReact.active() and s._cycle_timer >= 2.0)
	if step:
		s._cycle_timer = 0.0
		for i in Toolbox.slots.size():
			var sl: Dictionary = Toolbox.slots[i]
			if not sl.has("word_paths"):
				continue
			var paths: Array = sl["word_paths"]
			var idx := (int(sl.get("word_index", 0)) + 1) % paths.size()
			sl["word_index"] = idx
			Toolbox.set_slot_path(i, str(paths[idx]))


func advance_words() -> void:
	s._cycle_timer = 2.0
	_tick_words(0.0)


## Pinata: the nearest Sparkle icon under a point bursts and goes.
func syphon_available() -> bool:
	return ClassDB.class_exists("SyphonOutput") and DisplayServer.get_name() != "headless"


## Publishes the composite (the picture, no HUD) as a Syphon server named
## "Video Toy". The addon cannot switch textures on a live output, so the
## node is created fresh each time it is turned on.
func set_syphon(on: bool) -> void:
	if on and not syphon_available():
		s._steal_note = "Syphon: addon not loaded (macOS + Forward+ only)"
		s.syphon_on = false
		s._update_hud()
		return
	if s._syphon:
		s._syphon.queue_free()
		s._syphon = null
	s.syphon_on = on
	if on:
		s._syphon = ClassDB.instantiate("SyphonOutput")
		var sname := str(Settings.get_value("syphon_name"))
		s._syphon.server_name = sname
		s.add_child(s._syphon)
		s._syphon.texture = s._composite.get_texture()
		s._steal_note = "Syphon: publishing '%s' (1920x1080, no HUD)" % sname
	else:
		s._steal_note = "Syphon: off"
	s._update_hud()


# ---------------- clock ----------------
func add_raster(path: String) -> int:
	var idx := Toolbox.add_raster(path)
	if idx >= 0:
		Ledger.record_local(Toolbox.slots[idx])
		s._steal_note = "added “%s” to slot %d — S steals its palette" % [Toolbox.slots[idx]["term"], idx + 1]
	else:
		s._steal_note = "could not add image (toolbox full?)"
	s._update_hud()
	return idx


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		var ext := f.get_extension().to_lower()
		if ext in IconMedia.RASTER_EXT:
			if Input.is_key_pressed(KEY_SHIFT):
				# Shift+drop: chroma-key backdrop
				if s._fx.set_backdrop_from_file(f):
					if s._fx.key_mode == 0:
						s._fx.key_mode = 1
						s._fx._push()
					s._refresh_fx()
			else:
				add_raster(f)
			return
		if ext in ["mp3", "ogg", "wav"]:
			var si: int = s._hotbar.slot_at(s.get_viewport().get_mouse_position())
			if si >= 0 and si < Toolbox.slots.size():
				if Toolbox.set_slot_sound(si, f):
					Sounds.play(str(Toolbox.slots[si]["sound_path"]))
					s._steal_note = "slot %d sounds like %s (spawn, beat with Sparkle, pinata, collisions)" % [si + 1, f.get_file()]
				else:
					s._steal_note = "could not copy that sound"
			else:
				AudioReact.load_file(f)
			s._update_hud()
			return
		if ext == "svg":
			var si := Toolbox.add_svg(f)
			if si >= 0:
				Ledger.record_local(Toolbox.slots[si])
				s._steal_note = "added SVG “%s” to slot %d" % [Toolbox.slots[si]["term"], si + 1]
			s._update_hud()
			return
		if ext in ["ttf", "otf"]:
			s._steal_note = ("font set: %s — new words use it" % f.get_file()) if TextRaster.set_font_file(f) else "could not load that font"
			s._update_hud()
			return
		if ext == "txt":
			var lines := Array(FileAccess.get_file_as_string(f).split("\n"))
			var wi := Toolbox.add_words(lines)
			if wi >= 0:
				Ledger.record_local(Toolbox.slots[wi])
				s._steal_note = "added words to slot %d%s" % [wi + 1, " (cycling on the beat)" if Toolbox.slots[wi].has("words") else ""]
			else:
				s._steal_note = "could not add the word list (empty, or toolbox full)"
			s._update_hud()
			return
		if ext == "cue":
			var cue_err: String = s.run_cues(f)
			s._steal_note = ("cue sheet running: " + f.get_file()) if cue_err == "" else ("cue sheet: " + cue_err)
			s._update_hud()
			return
		if ext == "zip":
			s._steal_note = load("res://src/menu_overlay.gd").import_rig(f)
			s._update_hud()
			return
		if ext == "ogv":
			var vi := Toolbox.add_video(f)
			if vi >= 0:
				Ledger.record_local(Toolbox.slots[vi])
				_sync_videos()
				s._steal_note = "added video “%s” to slot %d" % [Toolbox.slots[vi]["term"], vi + 1]
			s._update_hud()
			return
