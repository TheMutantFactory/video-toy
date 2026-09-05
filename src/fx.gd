extends ColorRect
## The post-process layer (see fx.gdshader). Owns the effect state, pushes
## uniforms, and hides itself when nothing is on so the plain path stays free.

const PIXEL_STEPS := [0, 4, 8, 12, 20, 32]

var pixel_step := 0
var quantize := false
var dither := false
var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/fx.gdshader")
	material = _mat
	_push()


func is_active() -> bool:
	return pixel_step > 0 or quantize


func pixel_size() -> int:
	return PIXEL_STEPS[pixel_step]


func cycle_pixelate() -> void:
	pixel_step = (pixel_step + 1) % PIXEL_STEPS.size()
	_push()


func toggle_quantize() -> void:
	quantize = not quantize
	_push()


func toggle_dither() -> void:
	dither = not dither
	_push()


func set_state(pixel: int, quant: bool, dith: bool) -> void:
	pixel_step = maxi(PIXEL_STEPS.find(pixel), 0)
	quantize = quant
	dither = dith
	_push()


## Feed the shader the active palette ring plus its background.
func set_palette(index: int) -> void:
	var colours: Array = Palettes.ring(index)
	colours.append(Palettes.bg(index))
	var arr: Array[Color] = []
	for i in 16:
		arr.append(colours[i] if i < colours.size() else Color.BLACK)
	_mat.set_shader_parameter("palette", PackedColorArray(arr))
	_mat.set_shader_parameter("palette_count", mini(colours.size(), 16))


func describe() -> String:
	if not is_active():
		return "off"
	var parts: Array = []
	if pixel_step > 0:
		parts.append("pixel %d" % pixel_size())
	if quantize:
		parts.append("palette" + ("+dither" if dither else ""))
	return "  ".join(parts)


func _push() -> void:
	_mat.set_shader_parameter("pixel_size", float(pixel_size()))
	_mat.set_shader_parameter("quantize", quantize)
	_mat.set_shader_parameter("dither", dither)
	visible = is_active()
