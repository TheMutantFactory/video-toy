class_name Keys
## The one list of controls. The stage help panel, docs/KEYS.md and the
## printable key card (docs/key-card.png) are all generated from it, so a
## new key goes here once. Verbs come from the registry (verbs/*.gd).

const DROPS := "drop image / .svg / .ttf .otf / .txt / .ogv / rig .zip"


## [{title, tab, rows: [[keys, what], ...]}, ...]
static func groups() -> Array:
	var verbs: Array = []
	var inst: Array = Verbs.instances().duplicate()
	inst.sort_custom(func(a, b): return a.panel < b.panel)
	for v in inst:
		var hint: String = v.hint if v.hint != "" else v.name.to_lower()
		verbs.append([v.key.replace("⇧", "Shift+").replace("^", "Ctrl+"), "%s — %s" % [v.name, hint]])
	return [
		{"title": "Basics", "tab": "Basics", "rows": [
			["click", "spawn the selected icon at the mouse"],
			["right-click", "remove the nearest icon"],
			["Space", "spawn somewhere"],
			["1-9", "select a toolbox slot · Del removes it"],
			["X", "recolor the slot"],
			["P", "next palette"],
			["C", "clear the stage"],
			["H", "HUD full / compact / hidden"],
			["?", "this key list, with tabs and a search box (Shift+/)"],
			["Esc / ☰", "menu: panic, blackout, attribution, rigs, clip, settings"],
			[DROPS, "raster slot (Shift: chroma backdrop) / icon / font for words / word list / video slot / import rig"],
			["drop .wav .mp3 .ogg on a slot", "its sound: spawn, beat (with Sparkle), pinata, collisions"],
			["drag a Physics icon", "throw it"],
			["Ctrl+Z", "undo the last spawn / remove / clear / mosaic / path / pinata · Ctrl+Shift+Z redo"],
			["Ctrl+U", "guest mode: right-click wheel, hold to remove, mouse only"],
		]},
		{"title": "Verbs (toggle on the selected slot)", "tab": "Verbs", "rows": verbs},
		{"title": "Feedback and scenes", "tab": "Feedback", "rows": [
			["F", "feedback on / off"],
			["[ ]  , .  - =", "feedback zoom · twist · fade"],
			["arrows", "feedback drift · PgUp/PgDn warp · Home resets"],
			["Tab / Shift+Tab", "next / previous scene · ` scene off"],
			["M", "monitor inside the scene (recursion)"],
			["N", "monitor size · drag it to move"],
		]},
		{"title": "Effects", "tab": "Effects", "rows": [
			["O", "kaleidoscope off / 3 / 4 / 6 / 8 / 12"],
			["K", "pixelate off / 4 / 8 / 12 / 20 / 32"],
			["L  J", "palette quantise · dither"],
			["G", "key off / chroma / luma / diff / edge · Shift+G threshold"],
			["Shift+K", "slit-scan off / rows / columns / radial"],
			["V", "CRT off / soft / heavy"],
			["D", "glow off / soft / heavy"],
			["'", "ASCII off / mono / colour"],
		]},
		{"title": "3D and layers", "tab": "3D", "rows": [
			["B", "3D solid of the selected icon at the mouse"],
			["Shift+B", "next shape: cube / sphere / torus / cylinder / prism / cookie"],
			["Shift+Space", "formation of 200 copies · Shift+X next: helix / lattice / shell / ring"],
			["Shift+arrows", "camera orbit / dolly · Shift+PgUp/PgDn roll · Shift+Home resets"],
			["\\", "next layer (1 base, 2, 3) · Shift+\\ blend mix / add / sub / mul · Shift+[ ] opacity"],
			["Shift+D", "draw mode: drag a path and the icon rides it · right-click a path removes it"],
		]},
		{"title": "Modes", "tab": "Modes", "rows": [
			["Shift+S", "mosaic: the slot's picture rebuilt from the toolbox icons"],
			["Shift+E", "evolve: a mutation every 8 beats · Enter keeps · Shift+Enter discards"],
			["Shift+A", "attract mode (automatic after 60 s idle; any input ends it)"],
			["Ctrl+R", "surprise me: a random look from a known-good base (undo takes it back)"],
			["Shift+R  Shift+P", "record controller gestures · loop them"],
			["Shift+N", "particle field (right-click scatters)"],
			["Ctrl+G", "gravity on / off for Physics icons"],
			["Ctrl+S", "play the selected slot's sound"],
			["Shift+O", "reaction-diffusion presets"],
			["click a Sparkle icon", "pinata: it bursts into confetti of itself"],
		]},
		{"title": "Show", "tab": "Show", "rows": [
			["Shift+Esc", "PANIC: known-good look, toolbox untouched"],
			["Shift+H", "blackout (fades over half a second)"],
			["Shift+F", "quality lock: auto / full / high / medium / low"],
			["F1-F12", "recall preset (crossfaded) · Shift+F1-F12 saves"],
			["Shift+, .", "previous / next bank of 12"],
			["Shift+- =", "previous / next filled preset (foot switch)"],
			["Shift+;", "crossfade time 0 / 0.5 / 1 / 2 / 4 s"],
			["Shift+V", "screenshot with the credits strip burned in"],
			["Shift+L  Shift+C", "credits ticker · credits roll (end card)"],
			["Shift+Z", "Syphon output \"Video Toy\" (picture, no HUD)"],
		]},
		{"title": "Sources and controllers", "tab": "Controllers", "rows": [
			[";", "MIDI + audio panel: learn, clock, controller maps, OSC port"],
			["A", "audio off / mic / test groove / file (drop mp3 ogg wav)"],
			["Z", "webcam off / layer behind everything / chroma backdrop"],
			["S", "steal a palette from the raster or the webcam"],
		]},
		{"title": "Player 2 (keypad or gamepad)", "tab": "Player 2", "rows": [
			["8 2 4 6 / stick", "move the cursor"],
			["5 / A", "spawn · 0 / B removes"],
			["+ - / X", "slot · . / Y layer"],
			["* / LB", "spin · / / RB solid"],
			["Shift+2", "hide player 2"],
		]},
	]


## Plain-text column list for the in-app help panel.
static func help_text() -> String:
	var lines: PackedStringArray = []
	for g in groups():
		if not lines.is_empty():
			lines.append("")
		lines.append(str(g["title"]).to_upper())
		for r in g["rows"]:
			lines.append("%-14s %s" % [r[0], r[1]])
	return "\n".join(lines)


## docs/KEYS.md.
static func markdown() -> String:
	var out: PackedStringArray = ["# Video Toy keys", "", "Generated by `./run.sh keycard` from `src/keys.gd`; do not edit by hand.", "The printable version is [key-card.png](key-card.png).", ""]
	for g in groups():
		out.append("## " + str(g["title"]))
		out.append("")
		out.append("| Keys | What |")
		out.append("| --- | --- |")
		for r in g["rows"]:
			out.append("| `%s` | %s |" % [str(r[0]).replace("|", "\\|"), str(r[1]).replace("|", "\\|")])
		out.append("")
	return "\n".join(out)
