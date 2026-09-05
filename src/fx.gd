extends ColorRect
## The post-process layer (see fx.gdshader). Owns the effect state, pushes
## uniforms, and hides itself when nothing is on so the plain path stays free.

const PIXEL_STEPS := [0, 4, 8, 12, 20, 32]
const KALEIDO_STEPS := [0, 3, 4, 6, 8, 12]
const BACKDROP_PATH := "user://backdrop.png"

var pixel_step := 0
var kaleido_step := 0
var crt_level := 0                          # 0 off, 1 soft, 2 heavy
var chroma := false
var quantize := false
var dither := false
var backdrop: ImageTexture
var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/fx.gdshader")
	material = _mat
	_load_backdrop()
	_push()


func is_active() -> bool:
	return pixel_step > 0 or quantize or kaleido_step > 0 or chroma or crt_level > 0


func cycle_crt() -> void:
	crt_level = (crt_level + 1) % 3
	_push()


func kaleido_segments() -> int:
	return KALEIDO_STEPS[kaleido_step]


func cycle_kaleido() -> void:
	kaleido_step = (kaleido_step + 1) % KALEIDO_STEPS.size()
	_push()


func toggle_chroma() -> void:
	chroma = not chroma
	_push()


## Drop-in backdrop for chroma key. Saved to user:// so it survives restarts.
func set_backdrop_from_file(path: String) -> bool:
	var img := Image.new()
	if img.load(path) != OK:
		return false
	backdrop = ImageTexture.create_from_image(img)
	img.save_png(BACKDROP_PATH)
	_push()
	return true


func clear_backdrop() -> void:
	backdrop = null
	if FileAccess.file_exists(BACKDROP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKDROP_PATH))
	_push()


func _load_backdrop() -> void:
	if not FileAccess.file_exists(BACKDROP_PATH):
		return
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(BACKDROP_PATH)) == OK:
		backdrop = ImageTexture.create_from_image(img)


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


func set_state(pixel: int, quant: bool, dith: bool, kaleido := 0, chroma_on := false, crt := 0) -> void:
	crt_level = clampi(crt, 0, 2)
	pixel_step = maxi(PIXEL_STEPS.find(pixel), 0)
	kaleido_step = maxi(KALEIDO_STEPS.find(kaleido), 0)
	chroma = chroma_on
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
	_mat.set_shader_parameter("key_color", Palettes.bg(index))   # key = the stage background


func describe() -> String:
	if not is_active():
		return "off"
	var parts: Array = []
	if crt_level > 0:
		parts.append("crt " + ("soft" if crt_level == 1 else "heavy"))
	if kaleido_step > 0:
		parts.append("kaleido %d" % kaleido_segments())
	if pixel_step > 0:
		parts.append("pixel %d" % pixel_size())
	if chroma:
		parts.append("chroma→" + ("image" if backdrop else "plasma"))
	if quantize:
		parts.append("palette" + ("+dither" if dither else ""))
	return "  ".join(parts)


func _push() -> void:
	_mat.set_shader_parameter("crt", float(crt_level))
	_mat.set_shader_parameter("kaleido_segments", kaleido_segments())
	_mat.set_shader_parameter("chroma", chroma)
	_mat.set_shader_parameter("has_backdrop", backdrop != null)
	_mat.set_shader_parameter("backdrop_tex", backdrop)
	_mat.set_shader_parameter("pixel_size", float(pixel_size()))
	_mat.set_shader_parameter("quantize", quantize)
	_mat.set_shader_parameter("dither", dither)
	visible = is_active()
