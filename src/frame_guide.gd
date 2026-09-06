class_name FrameGuide
extends Control
## The clip's crop drawn over the stage: dims what the export will not
## show and outlines what it will, so a 9:16 or 1:1 clip can be composed.

var crop := Vector2i(1920, 1080)
var world := Vector2i(1920, 1080)
var display: Control


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## The picture's rect on screen (keep-aspect, centred), then the crop inside it.
static func rects(display_rect: Rect2, world_size: Vector2i, crop_size: Vector2i) -> Array:
	var scale := minf(display_rect.size.x / world_size.x, display_rect.size.y / world_size.y)
	var drawn := Vector2(world_size) * scale
	var origin := display_rect.position + (display_rect.size - drawn) * 0.5
	var pic := Rect2(origin, drawn)
	var c := Vector2(crop_size) * scale
	var guide := Rect2(origin + (drawn - c) * 0.5, c)
	return [pic, guide]


func _draw() -> void:
	if display == null or crop == world:
		return
	var r: Array = rects(display.get_rect(), world, crop)
	var pic: Rect2 = r[0]
	var g: Rect2 = r[1]
	var dim := Color(0, 0, 0, 0.55)
	if g.position.x > pic.position.x:
		draw_rect(Rect2(pic.position, Vector2(g.position.x - pic.position.x, pic.size.y)), dim)
		draw_rect(Rect2(Vector2(g.end.x, pic.position.y), Vector2(pic.end.x - g.end.x, pic.size.y)), dim)
	if g.position.y > pic.position.y:
		draw_rect(Rect2(pic.position, Vector2(pic.size.x, g.position.y - pic.position.y)), dim)
		draw_rect(Rect2(Vector2(pic.position.x, g.end.y), Vector2(pic.size.x, pic.end.y - g.end.y)), dim)
	draw_rect(g, UI.ACCENT, false, 2.0)
	draw_string(ThemeDB.fallback_font, g.position + Vector2(8, 24), "%d x %d clip" % [crop.x, crop.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.ACCENT)
