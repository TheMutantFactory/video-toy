class_name RadialMenu
extends Control
## The guest wheel: a ring of items around the cursor, drawn by hand, with a
## hub that flips between pages (slots · verbs · more). Items come from a
## provider callable (the stage) so this file stays pure and testable:
## pick() is the hit test.

signal picked(page: String, index: int)
signal closed

const R_IN := 64.0
const R_OUT := 240.0
const PAGES := ["slots", "verbs", "more"]

var provider: Callable                      # func(page: String) -> Array of {text, tex, color, on}
var page := "slots"
var items: Array = []
var centre := Vector2.ZERO
var hover := -1                             # -1 none, -2 hub, else item


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Where a local point lands: -1 outside, -2 the hub, else the item index.
static func pick(local: Vector2, at: Vector2, n: int, r_in := R_IN, r_out := R_OUT) -> int:
	var d := local - at
	var len := d.length()
	if len < r_in:
		return -2
	if len > r_out or n <= 0:
		return -1
	var ang := fposmod(atan2(d.y, d.x) + PI * 0.5, TAU)      # first item straight up
	var sector := TAU / n
	return int(round(ang / sector)) % n


static func item_pos(at: Vector2, i: int, n: int, r_in := R_IN, r_out := R_OUT) -> Vector2:
	var ang := -PI * 0.5 + TAU * i / maxi(n, 1)
	return at + Vector2.from_angle(ang) * (r_in + r_out) * 0.5


func open_at(pos: Vector2, start_page := "slots") -> void:
	centre = pos.clamp(Vector2(R_OUT + 10, R_OUT + 10), size - Vector2(R_OUT + 10, R_OUT + 10)) if size != Vector2.ZERO else pos
	set_page(start_page)
	visible = true
	hover = -1
	if get_parent():
		get_parent().move_child(self, -1)
	queue_redraw()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func set_page(p: String) -> void:
	page = p if PAGES.has(p) else "slots"
	items = provider.call(page) if provider.is_valid() else []
	queue_redraw()


func next_page() -> void:
	set_page(PAGES[(PAGES.find(page) + 1) % PAGES.size()])


func activate(i: int) -> void:
	if i >= 0 and i < items.size():
		picked.emit(page, i)
		set_page(page)                      # refresh on / off marks


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := pick(ev.position, centre, items.size())
		if h != hover:
			hover = h
			queue_redraw()
		accept_event()
	elif ev is InputEventMouseButton and ev.pressed:
		accept_event()
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			close()
			return
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN or ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			next_page()
			return
		if ev.button_index != MOUSE_BUTTON_LEFT:
			return
		var i := pick(ev.position, centre, items.size())
		if i == -2:
			next_page()
		elif i == -1:
			close()
		else:
			activate(i)
	elif ev is InputEventMouseButton:
		accept_event()


func _unhandled_key_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_circle(centre, R_OUT + 14.0, Color(0.05, 0.05, 0.09, 0.9))
	draw_arc(centre, R_OUT + 14.0, 0.0, TAU, 96, UI.ACCENT, 2.0, true)
	var n := items.size()
	for i in n:
		var p := item_pos(centre, i, n)
		var it: Dictionary = items[i]
		var on := bool(it.get("on", false))
		if i == hover:
			draw_circle(p, 46.0, Color(UI.ACCENT, 0.35))
		elif on:
			draw_circle(p, 42.0, Color(UI.ACCENT, 0.16))
		var tex: Texture2D = it.get("tex")
		var col: Color = it.get("color", UI.INK)
		if tex:
			draw_texture_rect(tex, Rect2(p - Vector2(28, 34), Vector2(56, 56)), false, col)
			draw_string(font, p + Vector2(-70, 44), str(it.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, 140, 14, UI.DIM)
		else:
			draw_string(font, p + Vector2(-70, -4), str(it.get("text", "")), HORIZONTAL_ALIGNMENT_CENTER, 140, 17, UI.INK if not on else UI.ACCENT)
			var sub := str(it.get("sub", ""))
			if sub != "":
				draw_string(font, p + Vector2(-70, 16), sub, HORIZONTAL_ALIGNMENT_CENTER, 140, 12, UI.DIM)
	# hub
	draw_circle(centre, R_IN - 4.0, Color(0.1, 0.1, 0.16, 0.95) if hover != -2 else Color(UI.ACCENT, 0.3))
	draw_string(font, centre + Vector2(-60, -2), page.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 16, UI.ACCENT)
	draw_string(font, centre + Vector2(-60, 16), "click: next", HORIZONTAL_ALIGNMENT_CENTER, 120, 11, UI.DIM)
	draw_string(font, centre + Vector2(-200, R_OUT + 40), "right-click or outside closes · hold an icon to remove it", HORIZONTAL_ALIGNMENT_CENTER, 400, 13, UI.DIM)
