extends ColorRect
## The glow pass (see glow.gdshader). Hidden when off so it costs nothing.

var level := 0                       # 0 off, 1 soft, 2 heavy
var _mat: ShaderMaterial


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://src/glow.gdshader")
	material = _mat
	_push()


func cycle() -> void:
	set_level(level + 1)


func set_level(l: int) -> void:
	level = posmod(l, 3)
	_push()


func describe() -> String:
	return ["off", "soft", "heavy"][level]


func _push() -> void:
	_mat.set_shader_parameter("glow", float(level))
	visible = level > 0
