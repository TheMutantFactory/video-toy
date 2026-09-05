class_name UI
## Small helpers so every screen shares one look without a .tres theme.

const ACCENT := Color("#ff4fa3")
const PANEL := Color(0.08, 0.08, 0.13, 0.92)
const INK := Color(0.93, 0.93, 0.97)
const DIM := Color(0.6, 0.6, 0.7)


static func theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_font_size("font_size", "Button", 22)
	t.set_font_size("font_size", "LineEdit", 24)
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.corner_radius_top_left = 10
	panel.corner_radius_top_right = 10
	panel.corner_radius_bottom_left = 10
	panel.corner_radius_bottom_right = 10
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


static func label(text: String, size := 22, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size := 64) -> Label:
	var l := label(text, size, ACCENT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func button(text: String, cb: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 48)
	b.pressed.connect(cb)
	return b


static func hspace(px := 12) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(px, 0)
	return c


static func vspace(px := 12) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	return c


static func slot_style(selected: bool, filled: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.14, 0.14, 0.2, 0.95) if filled else Color(0.1, 0.1, 0.14, 0.7)
	s.set_corner_radius_all(8)
	s.set_border_width_all(3 if selected else 1)
	s.border_color = ACCENT if selected else Color(0.3, 0.3, 0.4)
	return s
