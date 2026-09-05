class_name Palettes
## Named colour sets. Each palette: background, then a ring of icon colours.
## Actors take colours from the ring; the stage takes the background.
## Add a palette here and it shows up in the P-key cycle and the credits.

const SETS := [
	{"name": "Knobcon", "bg": "#0b0b14",
		"ring": ["#ff4fa3", "#ffd166", "#4fd1ff", "#7cff6b", "#ff8c42"]},
	{"name": "Birthday", "bg": "#1d0b2e",
		"ring": ["#ff6ec7", "#fff275", "#6ef3ff", "#c6ff6e", "#ff9f6e", "#b56eff"]},
	{"name": "VHS", "bg": "#101418",
		"ring": ["#ff2e63", "#08d9d6", "#eaeaea", "#ff9a00"]},
	{"name": "Cream", "bg": "#f4ecd8",
		"ring": ["#2b2b2b", "#c0392b", "#2980b9", "#27ae60", "#8e44ad"]},
	{"name": "Mono", "bg": "#000000",
		"ring": ["#ffffff"]},
	{"name": "Chroma Green", "bg": "#00ff00",
		"ring": ["#ffffff", "#ff4fa3", "#ffd166", "#4fd1ff"]},
	{"name": "Chroma Blue", "bg": "#0000ff",
		"ring": ["#ffffff", "#ff4fa3", "#ffd166", "#7cff6b"]},
]


static func count() -> int:
	return SETS.size()


static func get_palette(i: int) -> Dictionary:
	return SETS[posmod(i, SETS.size())]


static func bg(i: int) -> Color:
	return Color(get_palette(i)["bg"])


static func ring(i: int) -> Array:
	var out: Array = []
	for hex in get_palette(i)["ring"]:
		out.append(Color(hex))
	return out


static func color(i: int, slot: int) -> Color:
	var r := ring(i)
	return r[posmod(slot, r.size())]
