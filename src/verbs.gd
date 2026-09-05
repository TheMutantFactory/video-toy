class_name Verbs
## The things an icon can DO. Each verb is a toggle on a toolbox slot; actors
## spawned from that slot carry the slot's verbs. Actor.gd implements them.

const ALL := [
	{"id": "wander", "name": "Wander", "key": "Q", "hint": "random motion"},
	{"id": "orbit", "name": "Orbit", "key": "W", "hint": "circle around spawn point"},
	{"id": "spin", "name": "Spin", "key": "E", "hint": "rotate in place"},
	{"id": "bounce", "name": "Bounce", "key": "R", "hint": "DVD-logo off the walls"},
	{"id": "pulse", "name": "Pulse", "key": "T", "hint": "breathe in and out"},
	{"id": "sparkle", "name": "Sparkle", "key": "Y", "hint": "spawn particles"},
	{"id": "rainbow", "name": "Rainbow", "key": "U", "hint": "cycle the hue"},
	{"id": "swarm", "name": "Swarm", "key": "I", "hint": "chase the mouse"},
	{"id": "flock", "name": "Flock", "key": "⇧Q", "hint": "boids with the others from this slot; hold click to attract, right-click empty space to scatter", "shift": true},
	{"id": "lorenz", "name": "Lorenz", "key": "⇧W", "hint": "ride the Lorenz butterfly", "shift": true},
	{"id": "rossler", "name": "Rössler", "key": "⇧T", "hint": "ride the Rössler spiral", "shift": true},
	{"id": "clifford", "name": "Clifford", "key": "⇧Y", "hint": "fly between points of the Clifford map", "shift": true},
	{"id": "dejong", "name": "de Jong", "key": "⇧U", "hint": "fly between points of the de Jong map", "shift": true},
	{"id": "field", "name": "Field", "key": "⇧I", "hint": "ride the curl-noise flow field (the same one the particles ride)", "shift": true},
	{"id": "morph", "name": "Morph", "key": "⇧M", "hint": "become the next icon in the toolbox, shape to shape (on the beat with audio)", "shift": true},
	{"id": "outline", "name": "Outline", "key": "⇧J", "hint": "hollow the icon to a ring that follows its silhouette", "shift": true},
]


static func ids() -> Array:
	var out: Array = []
	for v in ALL:
		out.append(v["id"])
	return out


static func by_key(keycode: int, shift := false) -> String:
	var name := OS.get_keycode_string(keycode).to_upper()
	for v in ALL:
		var wants_shift: bool = v.get("shift", false)
		var key: String = v["key"].trim_prefix("⇧")
		if name == key and shift == wants_shift:
			return v["id"]
	return ""


static func get_verb(id: String) -> Dictionary:
	for v in ALL:
		if v["id"] == id:
			return v
	return {}
