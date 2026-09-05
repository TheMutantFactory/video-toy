extends Node2D
## The scene layer in the world: two full-size ColorRects that crossfade when
## the scene changes. Reads Scenes.current / knobs; the stage calls refresh().

var size := Vector2(1920, 1080)
var _a: ColorRect
var _b: ColorRect
var _tween: Tween
var _shown := ""
var _palette := 0


func _ready() -> void:
	z_index = -3
	_a = _rect()
	_b = _rect()
	_b.modulate.a = 0.0
	add_child(_a)
	add_child(_b)
	refresh(0.0)


func _rect() -> ColorRect:
	var r := ColorRect.new()
	r.size = size
	r.color = Color.WHITE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	return r


func set_palette(i: int) -> void:
	_palette = i
	for r in [_a, _b]:
		if r.material:
			Scenes.apply_palette(r.material, i)


func apply_knobs() -> void:
	for r in [_a, _b]:
		if r.material:
			Scenes.apply_knobs(r.material)


## Show Scenes.current, crossfading from whatever is up over `fade` seconds.
func refresh(fade := 0.8) -> void:
	var id := Scenes.current
	if id == _shown:
		apply_knobs()
		return
	_shown = id
	if _tween:
		_tween.kill()
	if id == "":
		_tween = create_tween()
		_tween.tween_property(_a, "modulate:a", 0.0, fade)
		_tween.tween_callback(func():
			_a.visible = false
			_a.material = null)
		return
	# new scene comes up on _b, then the pair swaps roles
	_b.material = Scenes.material_for(id, _palette)
	_b.visible = true
	_b.modulate.a = 0.0
	if fade <= 0.0 or not _a.visible:
		_b.modulate.a = 1.0
		_a.visible = false
		_a.material = null
		_swap()
		return
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_b, "modulate:a", 1.0, fade)
	_tween.tween_property(_a, "modulate:a", 0.0, fade)
	_tween.chain().tween_callback(func():
		_a.visible = false
		_a.material = null
		_swap())


func _swap() -> void:
	var t := _a
	_a = _b
	_b = t
