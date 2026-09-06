extends ColorRect
## The ASCII pass (see ascii.gdshader): builds the glyph atlas with TextRaster
## once, hides itself when off.

const RAMP := " .:-=+*#%@"
const CELL := Vector2(12, 20)

var mode := 0                          # 0 off, 1 mono, 2 colour
var _mat: ShaderMaterial
var _atlas: ImageTexture


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/ascii.gdshader")
	material = _mat
	_atlas = ImageTexture.create_from_image(build_atlas(RAMP, CELL))
	_mat.set_shader_parameter("glyphs", _atlas)
	_mat.set_shader_parameter("count", RAMP.length())
	_mat.set_shader_parameter("cell", CELL)
	_push()


## One row of glyphs, white on alpha. Every glyph is rendered at the same size
## and cut from the same line box, then scaled by ONE factor, so a dot stays a
## dot and an @ fills the cell: the luminance ramp survives.
static func build_atlas(ramp: String, cell: Vector2) -> Image:
	var img := Image.create(int(cell.x) * ramp.length(), int(cell.y), false, Image.FORMAT_RGBA8)
	var fs := int(cell.y * 0.85)
	for i in ramp.length():
		var ch := ramp.substr(i, 1)
		if ch == " ":
			continue
		var g := TextRaster.render(ch, fs)
		var pad := TextRaster.PAD
		var line_h := g.get_height() - pad * 2
		var line_w := g.get_width() - pad * 2
		if line_h <= 0 or line_w <= 0:
			continue
		var box := g.get_region(Rect2i(pad, pad, line_w, line_h))
		var sc := cell.y / float(line_h)
		var w := maxi(1, int(round(line_w * sc)))
		box.resize(w, int(cell.y), Image.INTERPOLATE_BILINEAR)
		# centre horizontally, clipping anything wider than the cell
		var dst_x := int((cell.x - w) * 0.5)
		var src := Rect2i(0, 0, w, int(cell.y))
		if dst_x < 0:
			src.position.x = -dst_x
			src.size.x = int(cell.x)
			dst_x = 0
		img.blend_rect(box, src, Vector2i(int(i * cell.x) + dst_x, 0))
	return img


func set_mode(m: int) -> void:
	mode = posmod(m, 3)
	_push()


func cycle() -> void:
	set_mode(mode + 1)


func set_palette(index: int) -> void:
	_mat.set_shader_parameter("accent", Palettes.color(index, 0))
	_mat.set_shader_parameter("bg", Palettes.bg(index))


func describe() -> String:
	return ["off", "mono", "colour"][mode]


func _push() -> void:
	_mat.set_shader_parameter("mode", mode)
	visible = mode > 0
