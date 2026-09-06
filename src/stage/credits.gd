extends RefCounted
## Credits ticker, credits roll and burned-in screenshots.
## Owned by the stage (src/stage_screen.gd), which exposes these as one-line
## delegations; `s` is the stage, whose state stays in one place.

var s: Stage


func _init(stage: Stage) -> void:
	s = stage


func onstage_ids() -> Array:
	var ids := {}
	for a in s.all_actors():
		ids[a.slot_id] = true
	for sol in s._solids.get_children():
		ids[sol.slot_id] = true
	for f in s._formations.get_children():
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
	s.ticker_on = on
	s._ticker.visible = on
	_refresh_ticker()
	s._update_hud()


func _refresh_ticker() -> void:
	if not s.ticker_on:
		return
	var parts: Array = []
	var ids := onstage_ids()
	for e in Ledger.entries:
		if ids.has(str(e.get("id", ""))):
			parts.append(Ledger.line_for(e))
	s._ticker.text = ("icons: " + "  ·  ".join(parts)) if not parts.is_empty() else "icons from The Noun Project — thenounproject.com"


## Screenshot of the picture (composite, no HUD) with the credits burned in.
func screenshot_with_credits() -> String:
	var img: Image = s._composite.get_texture().get_image()
	if img == null or img.is_empty():
		s._steal_note = "screenshot: no picture (headless?)"
		s._update_hud()
		return ""
	var lines := onstage_credit_lines()
	lines.push_front("Made with Video Toy — icons from The Noun Project (CC BY unless noted)")
	var path := Shot.save(Shot.compose(img, lines))
	s._steal_note = ("saved " + ProjectSettings.globalize_path(path)) if path != "" else "screenshot failed"
	s._update_hud()
	return path


func start_credits_roll() -> void:
	for c in s._roll_body.get_children():
		c.queue_free()
	s._roll_body.add_child(UI.label("Video Toy", 64, UI.ACCENT))
	s._roll_body.add_child(UI.label("icons from The Noun Project · thenounproject.com", 26))
	s._roll_body.add_child(UI.vspace(30))
	for line in Ledger.credits_text().split("\n"):
		if line.strip_edges() != "":
			s._roll_body.add_child(UI.label(line, 22 if not line.ends_with(":") else 26, Color.WHITE if not line.ends_with(":") else UI.ACCENT))
	s._roll_body.add_child(UI.vspace(80))
	s._roll_body.add_child(UI.label("thank you", 40, UI.ACCENT))
	s._roll_body.position = Vector2((1920 - 1200) * 0.5, 1080)
	s._roll_body.custom_minimum_size = Vector2(1200, 0)
	s._roll_t = 0.0
	s._roll.visible = true
	s._update_hud()


func stop_credits_roll() -> void:
	s._roll.visible = false
	s._update_hud()


func _tick_credits(delta: float) -> void:
	if s._roll.visible:
		s._roll_t += delta
		s._roll_body.position.y = 1080.0 - s._roll_t * s._roll_speed
		if s._roll_body.position.y + s._roll_body.size.y < -20.0:
			stop_credits_roll()
	if s.ticker_on and Engine.get_process_frames() % 60 == 0:
		_refresh_ticker()


# ---------------- quality ----------------
## Frame delta is useless on a vsynced display (this one is 30 Hz), so the
## ladder watches real work: script time plus measured CPU + GPU render time
## of the window and every SubViewport the stage owns.
