class_name TextRaster
## A word as a white-on-alpha Image, rendered through the TextServer's glyph
## atlases on the CPU — no viewport, so it works headless and at add time.
## The result is exactly the shape an icon has, so everything downstream
## (tint, verbs, solids, extrusion, formations) treats it as one.

const PAD := 24
const FONT_DIR := "user://fonts"

static var last_had_color := false          # the last render contained colour (emoji) glyphs
static var _custom: Font
static var _custom_checked := false
static var _emoji: SystemFont


## A dropped .ttf / .otf becomes the font for every later word.
static func set_font_file(src_path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FONT_DIR))
	for old in ["ttf", "otf"]:
		var o := "%s/current.%s" % [FONT_DIR, old]
		if FileAccess.file_exists(o):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(o))
	var dst := "%s/current.%s" % [FONT_DIR, src_path.get_extension().to_lower()]
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	_custom_checked = false
	_custom = null
	return current_font() != ThemeDB.fallback_font


static func clear_font() -> void:
	for ext in ["ttf", "otf"]:
		var o := "%s/current.%s" % [FONT_DIR, ext]
		if FileAccess.file_exists(o):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(o))
	_custom = null
	_custom_checked = true


static func current_font() -> Font:
	if not _custom_checked:
		_custom_checked = true
		for ext in ["ttf", "otf"]:
			var pth := "%s/current.%s" % [FONT_DIR, ext]
			if FileAccess.file_exists(pth):
				var ff := FontFile.new()
				if ff.load_dynamic_font(ProjectSettings.globalize_path(pth)) == OK:
					_custom = ff
				break
	return _custom if _custom else ThemeDB.fallback_font


static func emoji_font() -> SystemFont:
	if _emoji == null:
		_emoji = SystemFont.new()
		_emoji.font_names = ["Apple Color Emoji", "Noto Color Emoji", "Segoe UI Emoji", "Twemoji"]
	return _emoji


static func render(text: String, size := 160, font: Font = null) -> Image:
	if font == null:
		font = current_font()
	last_had_color = false
	var ts := TextServerManager.get_primary_interface()
	var shaped := ts.create_shaped_text()
	var rids := font.get_rids()
	rids.append_array(emoji_font().get_rids())           # emoji fall back to the system emoji font
	ts.shaped_text_add_string(shaped, text, rids, size)
	ts.shaped_text_shape(shaped)
	var glyphs := ts.shaped_text_get_glyphs(shaped)
	var ssize: Vector2 = ts.shaped_text_get_size(shaped)
	var ascent: float = ts.shaped_text_get_ascent(shaped)
	var w := maxi(int(ceil(ssize.x)) + PAD * 2, 8)
	var h := maxi(int(ceil(ssize.y)) + PAD * 2, 8)
	var dst := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var colour := Image.create(w, h, false, Image.FORMAT_RGBA8)   # colour glyphs (emoji) keep their colours
	var pen := Vector2(PAD, PAD + ascent)
	for g in glyphs:
		var frid: RID = g["font_rid"]
		var fsz := Vector2i(int(g["font_size"]), 0)
		var idx: int = g["index"]
		if idx != 0:
			ts.font_render_glyph(frid, fsz, idx)
			var tidx: int = ts.font_get_glyph_texture_idx(frid, fsz, idx)
			if tidx >= 0:
				var uv: Rect2 = ts.font_get_glyph_uv_rect(frid, fsz, idx)
				var off: Vector2 = ts.font_get_glyph_offset(frid, fsz, idx)
				var atlas: Image = ts.font_get_texture_image(frid, fsz, tidx)
				var is_colour := atlas != null and atlas.get_format() == Image.FORMAT_RGBA8
				if atlas and not is_colour:
					atlas = atlas.duplicate()
					atlas.convert(Image.FORMAT_RGBA8)
				if atlas:
					var at := Vector2i(pen + Vector2(g.get("offset", Vector2.ZERO)) + off)
					if is_colour:
						colour.blend_rect(atlas, Rect2i(uv), at)
						last_had_color = true
					else:
						dst.blend_rect(atlas, Rect2i(uv), at)
		pen.x += float(g["advance"]) * int(g.get("repeat", 1))
	ts.free_rid(shaped)
	# force pure white, keep coverage as alpha; colour glyphs go on top as they are
	for y in h:
		for x in w:
			var a := dst.get_pixel(x, y).a
			if a > 0.0:
				dst.set_pixel(x, y, Color(1, 1, 1, a))
	if last_had_color:
		dst.blend_rect(colour, Rect2i(0, 0, w, h), Vector2i.ZERO)
	return dst


static func opaque_count(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n
