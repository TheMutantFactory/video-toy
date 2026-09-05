extends ColorRect
## The post-process layer (see fx.gdshader). Owns the effect state, pushes
## uniforms, and hides itself when nothing is on so the plain path stays free.

const PIXEL_STEPS := [0, 4, 8, 12, 20, 32]
const KALEIDO_STEPS := [0, 3, 4, 6, 8, 12]
const KEY_MODES := ["off", "chroma", "luma", "diff", "edge"]
const SLIT_MODES := ["off", "rows", "cols", "radial"]
const SLIT_COLS := 6
const SLIT_ROWS := 6
const SLIT_STRIDE := 2                      # capture every Nth frame -> ~1.2 s of history
const BACKDROP_PATH := "user://backdrop.png"

var pixel_step := 0
var kaleido_step := 0
var crt_level := 0                          # 0 off, 1 soft, 2 heavy
var key_mode := 0
var key_threshold := 0.35
var slit_mode := 0
var quantize := false
var source_tex: Texture2D                   # the pre-fx picture (world+layers), set by the stage
var source_bg := Color.BLACK
var _hist: Array = []                       # two history atlases (ping-pong)
var _hist_slot0: Array = []                 # their "newest frame" sprites
var _hist_bg: Array = []
var _prev: Array = []                       # two previous-frame viewports (ping-pong)
var _flip := 0
var _frame := 0
var dither := false
var backdrop: Texture2D
var live_backdrop: Texture2D            # e.g. the webcam viewport; wins over the file
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


## Backwards-compatible view of the chroma toggle (presets, HUD).
var chroma: bool:
	get: return key_mode == 1
	set(v): key_mode = 1 if v else 0


func is_active() -> bool:
	return pixel_step > 0 or quantize or kaleido_step > 0 or key_mode > 0 or crt_level > 0 or slit_mode > 0


func cycle_key() -> void:
	key_mode = (key_mode + 1) % KEY_MODES.size()
	_push()


func cycle_slit() -> void:
	slit_mode = (slit_mode + 1) % SLIT_MODES.size()
	_push()


## The stage hands over the picture the effects read (world + layers) and the
## background it sits on; the history atlas and previous-frame copies are
## built from it here.
func set_source(tex: Texture2D, bg: Color) -> void:
	source_tex = tex
	source_bg = bg
	if _hist.is_empty():
		_build_history()
	for i in 2:
		_hist_slot0[i].texture = tex
		_hist_bg[i].color = bg
		_prev[i].get_child(0).color = bg
		_prev[i].get_child(1).texture = tex


static func slot_rect(i: int, size: Vector2) -> Rect2:
	var cell := Vector2(size.x / SLIT_COLS, size.y / SLIT_ROWS)
	return Rect2(Vector2(i % SLIT_COLS, i / SLIT_COLS) * cell, cell)


func _build_history() -> void:
	var size := Vector2(1920, 1080)
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(size)
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		_hist.append(vp)
		var pv := SubViewport.new()
		pv.size = Vector2i(size)
		pv.disable_3d = true
		pv.transparent_bg = true
		pv.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(pv)
		_prev.append(pv)
		var pbg := ColorRect.new()
		pbg.size = size
		pbg.color = source_bg
		pv.add_child(pbg)
		var pspr := Sprite2D.new()
		pspr.position = size * 0.5
		pv.add_child(pspr)
	for i in 2:
		var vp: SubViewport = _hist[i]
		var other: SubViewport = _hist[1 - i]
		# slot 0: the newest frame (bg + source) scaled into the first cell
		var r0 := slot_rect(0, size)
		var bg := ColorRect.new()
		bg.position = r0.position
		bg.size = r0.size
		vp.add_child(bg)
		_hist_bg.append(bg)
		var spr := Sprite2D.new()
		spr.centered = false
		spr.position = r0.position
		spr.scale = Vector2(1.0 / SLIT_COLS, 1.0 / SLIT_ROWS)
		vp.add_child(spr)
		_hist_slot0.append(spr)
		# slots 1..N-1: the other atlas's slots 0..N-2, shifted by one
		for k in range(1, SLIT_COLS * SLIT_ROWS):
			var src := slot_rect(k - 1, size)
			var dst := slot_rect(k, size)
			var rs := Sprite2D.new()
			rs.centered = false
			rs.texture = other.get_texture()
			rs.region_enabled = true
			rs.region_rect = src
			rs.position = dst.position
			vp.add_child(rs)


func _process(_delta: float) -> void:
	if _hist.is_empty():
		return
	_frame += 1
	# previous frame: alternate which copy renders; the shader reads the other
	if key_mode == 3:
		var cur := _frame % 2
		_prev[cur].render_target_update_mode = SubViewport.UPDATE_ONCE
		_mat.set_shader_parameter("prev_tex", _prev[1 - cur].get_texture())
	if slit_mode > 0 and _frame % SLIT_STRIDE == 0:
		_hist[_flip].render_target_update_mode = SubViewport.UPDATE_ONCE
		_mat.set_shader_parameter("slit_tex", _hist[_flip].get_texture())
		_flip = 1 - _flip


func cycle_crt() -> void:
	crt_level = (crt_level + 1) % 3
	_push()


func kaleido_segments() -> int:
	return KALEIDO_STEPS[kaleido_step]


func cycle_kaleido() -> void:
	kaleido_step = (kaleido_step + 1) % KALEIDO_STEPS.size()
	_push()


func toggle_chroma() -> void:
	key_mode = 0 if key_mode == 1 else 1
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


func set_live_backdrop(tex: Texture2D) -> void:
	live_backdrop = tex
	_push()


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


func set_state(pixel: int, quant: bool, dith: bool, kaleido := 0, chroma_on := false, crt := 0, key := -1, slit := 0) -> void:
	crt_level = clampi(crt, 0, 2)
	pixel_step = maxi(PIXEL_STEPS.find(pixel), 0)
	kaleido_step = maxi(KALEIDO_STEPS.find(kaleido), 0)
	key_mode = key if key >= 0 else (1 if chroma_on else 0)
	slit_mode = clampi(slit, 0, SLIT_MODES.size() - 1)
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
	if key_mode > 0:
		parts.append("%s key→%s" % [KEY_MODES[key_mode], "webcam" if live_backdrop else ("image" if backdrop else "plasma")])
	if slit_mode > 0:
		parts.append("slit " + SLIT_MODES[slit_mode])
	if quantize:
		parts.append("palette" + ("+dither" if dither else ""))
	return "  ".join(parts)


func _push() -> void:
	_mat.set_shader_parameter("crt", float(crt_level))
	_mat.set_shader_parameter("kaleido_segments", kaleido_segments())
	_mat.set_shader_parameter("key_mode", key_mode)
	_mat.set_shader_parameter("key_threshold", key_threshold)
	_mat.set_shader_parameter("slit_mode", slit_mode)
	_mat.set_shader_parameter("slit_cols", SLIT_COLS)
	_mat.set_shader_parameter("slit_rows", SLIT_ROWS)
	var b: Texture2D = live_backdrop if live_backdrop != null else backdrop
	_mat.set_shader_parameter("has_backdrop", b != null)
	_mat.set_shader_parameter("backdrop_tex", b)
	_mat.set_shader_parameter("pixel_size", float(pixel_size()))
	_mat.set_shader_parameter("quantize", quantize)
	_mat.set_shader_parameter("dither", dither)
	visible = is_active()
