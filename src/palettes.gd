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


const EXTRA_PATH := "user://palettes.json"
static var extra: Array = []                 # user-made sets (stolen from images)
static var _loaded := false


static func count() -> int:
	_ensure()
	return SETS.size() + extra.size()


static func get_palette(i: int) -> Dictionary:
	_ensure()
	var n := SETS.size() + extra.size()
	var j := posmod(i, n)
	return SETS[j] if j < SETS.size() else extra[j - SETS.size()]


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	extra = []
	if not FileAccess.file_exists(EXTRA_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(EXTRA_PATH))
	if data is Dictionary and data.get("extra") is Array:
		for p in data["extra"]:
			if p is Dictionary and p.has("bg") and p.get("ring") is Array:
				extra.append(p)


## Append a user palette (persisted). Returns its index in the cycle.
static func add_extra(p: Dictionary) -> int:
	_ensure()
	for i in extra.size():
		if extra[i].get("name") == p.get("name"):
			extra[i] = p
			_save_extra()
			return SETS.size() + i
	extra.append(p)
	_save_extra()
	return SETS.size() + extra.size() - 1


static func _save_extra() -> void:
	var f := FileAccess.open(EXTRA_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"extra": extra}, "\t"))
		f.close()


## Steal a palette from an image: k-means on a downscaled copy. The darkest
## cluster becomes the background; the rest form the ring, sorted by hue.
static func extract(img: Image, name: String, k := 6) -> Dictionary:
	var small: Image = img.duplicate()
	small.convert(Image.FORMAT_RGBA8)
	small.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var px: Array = []
	for y in small.get_height():
		for x in small.get_width():
			var c := small.get_pixel(x, y)
			if c.a > 0.5:
				px.append(Vector3(c.r, c.g, c.b))
	if px.is_empty():
		return {"name": name, "bg": "#000000", "ring": ["#ffffff"]}
	# seed: evenly spaced samples along the pixel list (deterministic)
	var centres: Array = []
	for i in k:
		centres.append(px[(i * px.size()) / k])
	var counts: Array = []
	for _it in 12:
		var sums: Array = []
		counts = []
		for i in k:
			sums.append(Vector3.ZERO)
			counts.append(0)
		for v in px:
			var best := 0
			var bd := 1e9
			for i in k:
				var d: float = (v - centres[i]).length_squared()
				if d < bd:
					bd = d
					best = i
			sums[best] += v
			counts[best] += 1
		for i in k:
			if counts[i] > 0:
				centres[i] = sums[i] / counts[i]
	var cols: Array = []
	for i in k:
		if counts[i] > px.size() / 100:        # drop clusters under 1 %
			cols.append(Color(centres[i].x, centres[i].y, centres[i].z))
	if cols.is_empty():
		cols.append(Color(centres[0].x, centres[0].y, centres[0].z))
	cols.sort_custom(func(a, b): return a.get_luminance() < b.get_luminance())
	var bg: Color = cols.pop_front()
	if cols.is_empty():
		cols.append(bg.inverted())
	cols.sort_custom(func(a, b): return a.h < b.h)
	var ring: Array = []
	for c in cols:
		# push ring colours up a little so they read on the dark bg
		var cc: Color = c
		cc.s = maxf(cc.s, 0.35)
		cc.v = maxf(cc.v, 0.55)
		ring.append("#" + cc.to_html(false))
	return {"name": name, "bg": "#" + bg.to_html(false), "ring": ring}


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
