extends Node2D
## The virtual monitor: a TV inside the world whose screen shows the stage's
## final composite (post-effects). Since the world feeds that composite, the
## TV shows itself showing itself — the "camera pointed at its own monitor"
## recursion, one frame deeper per frame. Sits behind the actors (z_index -1)
## so icons fly across it. Draggable; sways gently so the tunnel breathes.

const SIZES := [0.25, 0.4, 0.6]
const BEZEL := 22.0

var size_step := 1
var sway := true
var accent := Color("#ff4fa3")
var _screen: Sprite2D
var _t := 0.0
var _base_rot := 0.0


func setup(tex: Texture2D, pos: Vector2) -> void:
	position = pos
	z_index = -1
	_screen = Sprite2D.new()
	_screen.texture = tex
	add_child(_screen)
	_apply_scale()


func cycle_size() -> void:
	size_step = (size_step + 1) % SIZES.size()
	_apply_scale()


func scale_factor() -> float:
	return SIZES[size_step]


func screen_size() -> Vector2:
	return _screen.texture.get_size() * scale_factor() if _screen.texture else Vector2(400, 225)


## Is a world-space point on the TV (bezel included)?
func contains(world_pos: Vector2) -> bool:
	var half := screen_size() * 0.5 + Vector2.ONE * BEZEL
	var local := (world_pos - position).rotated(-rotation)
	return absf(local.x) <= half.x and absf(local.y) <= half.y


func _apply_scale() -> void:
	_screen.scale = Vector2.ONE * scale_factor()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	rotation = _base_rot + (sin(_t * 0.6) * 0.035 if sway else 0.0)


func _draw() -> void:
	var half := screen_size() * 0.5
	var outer := Rect2(-half - Vector2.ONE * BEZEL, screen_size() + Vector2.ONE * BEZEL * 2.0)
	draw_rect(outer, Color(0.05, 0.05, 0.08), true)
	draw_rect(outer, accent, false, 4.0)
	# a little power LED
	draw_circle(Vector2(half.x + BEZEL * 0.5, half.y + BEZEL * 0.5), 4.0, accent)
