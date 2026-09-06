class_name KeyCard
## A printable one-page key card built from Keys: light background, three
## columns, rendered off-screen into docs/key-card.png by `./run.sh keycard`.

const SIZE := Vector2i(2480, 1560)          # A4 landscape at ~210 dpi
const PAPER := Color(0.985, 0.98, 0.97)
const INK := Color(0.1, 0.1, 0.14)
const DIM := Color(0.42, 0.42, 0.5)
const COLUMNS := 3
const FONT := 21
const WRAP := 50                            # chars per line in a column, roughly


## Rows a group takes once long descriptions wrap at `wrap` characters.
static func weight(g: Dictionary, wrap := WRAP) -> int:
	var n := 2
	for r in g["rows"]:
		n += 1 + str(r[1]).length() / wrap
	return n


## Split the groups, in order, into `columns` runs with the smallest tallest
## column (brute force: at most nine groups).
static func split(groups: Array, columns: int, wrap := WRAP) -> Array:
	var w: Array = groups.map(func(g): return weight(g, wrap))
	if groups.size() <= columns:
		var few: Array = []
		for i in columns:
			few.append([groups[i]] if i < groups.size() else [])
		return few
	var best: Array = []
	var best_max := 1 << 30
	var n := groups.size()
	var cuts: Array = []
	_splits(n, columns - 1, 1, [], cuts)
	for c in cuts:
		var bounds: Array = [0] + c + [n]
		var tallest := 0
		for i in columns:
			var sum := 0
			for j in range(bounds[i], bounds[i + 1]):
				sum += w[j]
			tallest = maxi(tallest, sum)
		if tallest < best_max:
			best_max = tallest
			best = bounds
	var out: Array = []
	for i in columns:
		out.append(groups.slice(best[i], best[i + 1]))
	return out


static func _splits(n: int, k: int, start: int, acc: Array, out: Array) -> void:
	if k == 0:
		out.append(acc.duplicate())
		return
	for i in range(start, n):
		acc.append(i)
		_splits(n, k - 1, i + 1, acc, out)
		acc.pop_back()


static func build() -> Control:
	var root := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = PAPER
	bg.content_margin_left = 60
	bg.content_margin_right = 60
	bg.content_margin_top = 40
	bg.content_margin_bottom = 40
	root.add_theme_stylebox_override("panel", bg)
	root.custom_minimum_size = SIZE
	root.size = SIZE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	root.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 30)
	col.add_child(head)
	var t := Label.new()
	t.text = "VIDEO TOY"
	t.add_theme_font_size_override("font_size", 64)
	t.add_theme_color_override("font_color", UI.ACCENT)
	head.add_child(t)
	var sub := Label.new()
	sub.text = "key card · verbs toggle per slot · Shift+Esc is panic · Esc is the menu · %s" % Build.describe()
	sub.add_theme_font_size_override("font_size", 26)
	sub.add_theme_color_override("font_color", DIM)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(sub)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 50)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grid)
	var cols: Array = []
	for i in COLUMNS:
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 22)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_stretch_ratio = 1.0
		grid.add_child(c)
		cols.append(c)
	var runs: Array = split(Keys.groups(), COLUMNS)
	for i in COLUMNS:
		for g in runs[i]:
			cols[i].add_child(_group(g))
	return root


## Does everything fit on the page? Call after a frame has laid it out.
static func overflow(root: Control) -> float:
	var worst := 0.0
	for c in root.get_child(0).get_child(1).get_children():
		for g in c.get_children():
			worst = maxf(worst, g.global_position.y + g.size.y - (SIZE.y - 40))
	return worst


## The in-app help: the same rows, dark, small, in `columns`, minus the verbs
## (the verb panel on the stage already lists them with their keys).
static func help(columns := 2, font := 14, groups: Array = []) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	if groups.is_empty():
		groups = Keys.groups().filter(func(g): return not str(g["title"]).begins_with("Verbs"))
	var runs: Array = split(groups, columns, 38)
	for i in columns:
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 10)
		c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(c)
		for g in runs[i]:
			c.add_child(_group(g, font, UI.ACCENT, UI.INK, UI.DIM, 110, 290))
	return row


static func _group(g: Dictionary, font := FONT, accent := UI.ACCENT, ink := INK, dim := DIM, key_w := 230, wrap_w := 0) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = str(g["title"])
	title.add_theme_font_size_override("font_size", font + 9)
	title.add_theme_color_override("font_color", accent)
	box.add_child(title)
	var table := GridContainer.new()
	table.columns = 2
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 3)
	box.add_child(table)
	for r in g["rows"]:
		var k := Label.new()
		k.text = str(r[0])
		k.add_theme_font_size_override("font_size", font)
		k.add_theme_color_override("font_color", ink)
		k.custom_minimum_size.x = key_w
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		table.add_child(k)
		var w := Label.new()
		w.text = str(r[1])
		w.add_theme_font_size_override("font_size", font)
		w.add_theme_color_override("font_color", dim)
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if wrap_w > 0:
			w.custom_minimum_size.x = wrap_w
		table.add_child(w)
	return box


## Render the card off-screen. Needs a window (not headless); `host` is any
## node in the tree.
static func render(host: Node) -> Image:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var root := build()
	vp.add_child(root)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var over := overflow(root)
	if over > 0.0:
		printerr("KEYCARD OVERFLOW: %.0f px past the bottom of the page" % over)
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img
