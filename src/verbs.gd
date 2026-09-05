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
]


static func ids() -> Array:
	var out: Array = []
	for v in ALL:
		out.append(v["id"])
	return out


static func by_key(keycode: int) -> String:
	for v in ALL:
		if OS.get_keycode_string(keycode).to_upper() == v["key"]:
			return v["id"]
	return ""


static func get_verb(id: String) -> Dictionary:
	for v in ALL:
		if v["id"] == id:
			return v
	return {}
