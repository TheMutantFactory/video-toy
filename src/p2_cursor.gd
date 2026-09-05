extends Node2D
## Player 2's cursor in the world: a ring in their slot colour with a tag.
var color := Color.CYAN
var label := "P2"


func _draw() -> void:
	draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 40, color, 4.0, true)
	draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 8.0, true)
	draw_arc(Vector2.ZERO, 34.0, 0.0, TAU, 40, color, 4.0, true)
	draw_line(Vector2(-46, 0), Vector2(-24, 0), color, 3.0)
	draw_line(Vector2(24, 0), Vector2(46, 0), color, 3.0)
	draw_line(Vector2(0, -46), Vector2(0, -24), color, 3.0)
	draw_line(Vector2(0, 24), Vector2(0, 46), color, 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(40, -40), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)
